const std = @import("std");
const Config = @import("./config.zig").Config;
const App = @import("./tui/app.zig").App;
const State = @import("./tui/state.zig").State;
const Canvas = @import("./tui/canvas.zig").Canvas;
const Transport = @import("./tui/transport.zig").Transport;
const parseMouse = @import("./tui/input.zig").parseMouse;
const utils = @import("./tui/utils.zig");

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

    // Posix
    const kq = std.c.kqueue();
    if (kq < 0) return error.KqueueFailed;
    try handleEvents(kq, io, stdin, &size, &app, &canvas);
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
) !void {
    // Register two events with the kernal:
    // 1. stdin has data to read (keypress)
    // 2. SIGWINCH was delivered (terminal resized)
    var changes = [_]std.c.Kevent{ .{
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
    } };

    // Buffer for the kernel to write fired events into
    var events: [2]std.c.Kevent = undefined;

    while (true) {
        // Block until at least one event fires. Returns how many fired.
        // const n = std.posix.kevent(kq, &changes, &events, null) catch continue;

        const n = std.c.kevent(
            kq,
            &changes,
            @intCast(changes.len),
            &events,
            @intCast(events.len),
            null,
        );
        if (n < 0) continue;

        // Walk events
        for (events[0..@intCast(n)]) |ev| {
            // Terminal was resized
            if (ev.filter == std.c.EVFILT.SIGNAL) {
                size.* = try getTermSize();
                try app.resize(size.cols, size.rows);
                try canvas.render(&app.layout);
            }

            // Keypress available - read single byte
            if (ev.filter == std.c.EVFILT.READ) {
                var buf: [1]u8 = undefined;
                const nr = stdin.readStreaming(io, &.{&buf}) catch continue;
                if (nr == 0) continue;

                // Added support here for keys that are > 1 byte in length.
                var key = buf[0];
                if (key == 0x1b) {
                    // Read the rest of the escape sequence (non-blocking via VMIN=0/VTIME=1)
                    var seq: [32]u8 = undefined;
                    const n2 = stdin.readStreaming(io, &.{&seq}) catch 0;
                    const s = seq[0..n2];

                    // Mouse reports arrive as: [<Cb;Cx;Cy(M|m). Log to inspect.
                    if (s.len >= 2 and s[0] == '[' and s[1] == '<') {
                        const mouse = parseMouse(s);
                        std.log.scoped(.mouse).info("{any}", .{mouse});
                        continue;
                    }

                    if (n2 == 2 and s[0] == '[') {
                        const arrow: struct { key: u8, name: []const u8 } = switch (s[1]) {
                            'A' => .{ .key = 'k', .name = "up" },
                            'B' => .{ .key = 'j', .name = "down" },
                            'C' => .{ .key = 'l', .name = "right" },
                            'D' => .{ .key = 'h', .name = "left" },
                            else => .{ .key = 0x1b, .name = "?" },
                        };
                        key = arrow.key;
                        std.log.scoped(.lifecycle).info("pressed [{s} -> {c}]", .{ arrow.name, key });
                    }
                } else {
                    std.log.scoped(.lifecycle).info("pressed [{c}]", .{key});
                }
                if (!app.handleKey(key)) return;
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
