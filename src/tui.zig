const std = @import("std");
const Config = @import("./config.zig").Config;
const App = @import("./tui/app.zig").App;
const State = @import("./tui/state.zig").State;
const Canvas = @import("./tui/canvas.zig").Canvas;
const Transport = @import("./tui/transport.zig").Transport;
const Mouse = @import("./tui/input.zig").Mouse;
const parseEscape = @import("./tui/input.zig").parseEscape;
const parseInput = @import("./tui/input.zig").parseInput;
const utils = @import("./tui/utils.zig");
const Events = @import("tui/events.zig").Events;

const TermSize = struct { cols: u16, rows: u16 };

pub fn run(cfg: Config, alloc: std.mem.Allocator, io: std.Io) !void {
    // Setup terminal and defer giving it back on program exit
    const stdin = std.Io.File.stdin();
    const stdout = std.Io.File.stdout();
    const original = try setup();
    defer std.posix.tcsetattr(stdin.handle, .FLUSH, original) catch {};

    // Enter alternate screen, hide cursor, enable SGR mouse reporting
    try stdout.writeStreamingAll(
        io,
        comptime utils.sm(.alt_screen) ++
            utils.clear_screen ++
            utils.rm(.cursor) ++
            utils.mouse_on,
    );
    defer stdout.writeStreamingAll(io, comptime utils.mouse_off ++
        utils.sm(.cursor) ++
        utils.rm(.alt_screen)) catch {};

    // Terminal size
    var size = try getTermSize();

    // Data
    var state = State.init(alloc);
    defer state.deinit();

    // App
    var app = try App.init(alloc, &state, size.cols, size.rows, &cfg, io);
    defer app.deinit();

    try app.loadDevices();
    app.layout.view = &app.view;

    // Canvas
    var canvas = try Canvas.init(alloc, io, stdout);
    defer canvas.deinit();
    try canvas.render(&app.layout);

    // AMQP
    var rx_mem: [4096]u8 = undefined;
    var tx_mem: [4096]u8 = undefined;
    var broker: Events = undefined;
    const connected = if (broker.init(io, &rx_mem, &tx_mem, &cfg)) true else |err| blk: {
        std.log.scoped(.events).warn("amqp connect failed: {s}", .{@errorName(err)});
        break :blk false;
    };
    defer if (connected) broker.deinit();

    // Posix
    const kq = std.c.kqueue();
    if (kq < 0) return error.KqueueFailed;
    try handleEvents(kq, io, stdin, &size, &app, &canvas, if (connected) &broker else null);
}

fn setup() !std.posix.termios {
    // Get current term settings and give them back on exit
    const stdin = std.Io.File.stdin();
    const original = try std.posix.tcgetattr(stdin.handle);

    // Make a copy to modify
    var raw = original;

    // Disable canonicle more (line buffering) and echo
    raw.lflag.ICANON = false; // Read char by char, not line by line
    raw.lflag.ECHO = false; // Don't echo typed characters
    raw.lflag.ISIG = false; // Disable Ctrl+C and Ctrl+Z signals

    // Set read timeout: together these return immediately if there
    // is input, or returns 0 after 100ms if there isn't. That's
    // what makes teh input loop non-blocking - it can keep checking
    // without hanging.
    raw.cc[@intFromEnum(std.posix.V.MIN)] = 0; // Min chars to read
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 1; // Timeout in deciseconds

    // Apply new settings
    try std.posix.tcsetattr(stdin.handle, .FLUSH, raw);

    return original;
}

/// Main event loop using kqueue. Blocks until the kernal delivers an event
/// (keypress, terminal resize, etc.) and dispatches it. Zero CPU when idle.
/// Returns when user quits.
fn handleEvents(
    kq: std.c.fd_t,
    io: std.Io,
    stdin: std.Io.File,
    size: *TermSize,
    app: *App,
    canvas: *Canvas,
    broker: ?*Events,
) !void {
    // Register two events with the kernal:
    // 1. stdin has data to read (keypress)
    // 2. SIGWINCH was delivered (terminal resized)
    var changes = [3]std.c.Kevent{ .{
        .ident = @intCast(stdin.handle),
        .filter = std.c.EVFILT.READ,
        .flags = std.c.EV.ADD,
        .fflags = 0,
        .data = 0,
        .udata = 0,
    }, .{
        .ident = @intFromEnum(std.posix.SIG.WINCH),
        .filter = std.c.EVFILT.SIGNAL,
        .flags = std.c.EV.ADD,
        .fflags = 0,
        .data = 0,
        .udata = 0,
    }, undefined };

    var change_count: usize = 2;
    if (broker) |b| {
        changes[2] = .{
            .ident = @intCast(b.fd()),
            .filter = std.c.EVFILT.READ,
            .flags = std.c.EV.ADD,
            .fflags = 0,
            .data = 0,
            .udata = 0,
        };
        change_count = 3;
    }

    // Buffer for the kernel to write fired events into
    var events: [3]std.c.Kevent = undefined;

    // Persists across reads so escape sequences split across reads survive.
    var pending: [256]u8 = undefined;
    var pending_len: usize = 0;

    while (true) {
        // Block until at least one event fires. Returns how many fired.
        // const n = std.posix.kevent(kq, &changes, &events, null) catch continue;
        const n = std.c.kevent(
            kq,
            &changes,
            @intCast(change_count),
            &events,
            @intCast(events.len),
            null,
        );
        // Continue on err
        if (n < 0) continue;

        // Walk events
        for (events[0..@intCast(n)]) |ev| {
            // Terminal was resized
            if (ev.filter == std.c.EVFILT.SIGNAL) {
                size.* = try getTermSize();
                try app.resize(size.cols, size.rows);
                try canvas.render(&app.layout);
            }

            // Input available - drain it into the persistent buffer, then parse
            // complete tokens off the front. Sequences split across reads survive.
            if (ev.filter == std.c.EVFILT.READ) {
                if (broker) |b| {
                    if (ev.ident == @as(usize, @intCast(b.fd()))) {
                        const msg = b.next() catch continue;
                        const parsed = std.json.parseFromSlice(std.json.Value, app.alloc, msg.body, .{}) catch continue;
                        defer parsed.deinit();
                        if (app.applyEvent(parsed.value) catch false) try canvas.render(&app.layout);
                        continue;
                    }
                }
                var chunk: [256]u8 = undefined;
                const nr = stdin.readStreaming(io, &.{&chunk}) catch continue;
                // The event fired but the stream is finished, there's nothing
                // to read!
                if (nr == 0) continue;
                if (pending_len + nr > pending.len) pending_len = 0; // overflow: drop stale tail
                @memcpy(pending[pending_len..][0..nr], chunk[0..nr]);
                pending_len += nr;

                var i: usize = 0;
                while (i < pending_len) {
                    const token = parseInput(pending[i..pending_len]) orelse break;
                    std.log.scoped(.input).info("{f}", .{token});

                    switch (token.action) {
                        .mouse => |m| if (!app.handleMouse(m)) return,
                        .key => |k| if (!app.handleKey(k)) return,
                        .none => {},
                    }
                    i += token.len;
                }

                // Shift any unparsed remainder to the front for next time.
                if (i > 0) {
                    std.mem.copyForwards(u8, pending[0..], pending[i..pending_len]);
                    pending_len -= i;
                }

                // Lone trailing ESC — no sequence followed in this read, so it's
                // the Esc key. parseInput holds a bare 0x1b as "incomplete"; flush it.
                if (pending_len == 1 and pending[0] == 0x1b) {
                    if (!app.handleKey(0x1b)) return;
                    pending_len = 0;
                }

                try canvas.render(&app.layout);
            }
        }
    }
}

fn getTermSize() !TermSize {
    var ws: std.posix.winsize = undefined;
    const rc = std.c.ioctl(std.posix.STDOUT_FILENO, std.c.T.IOCGWINSZ, @intFromPtr(&ws));
    if (rc != 0) return error.IoctlFailed;
    return .{ .cols = ws.col, .rows = ws.row };
}
