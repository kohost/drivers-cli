const std = @import("std");
const Config = @import("./config.zig").Config;
const App = @import("./tui/app.zig").App;
const State = @import("./tui/state.zig").State;
const Canvas = @import("./tui/canvas.zig").Canvas;
const Transport = @import("./tui/transport.zig").Transport;
const utils = @import("./tui/utils.zig");

const TermSize = struct { cols: u16, rows: u16 };

pub fn run(cfg: Config, alloc: std.mem.Allocator, io: std.Io) !void {
    // Setup terminal and defer giving it back on program exit
    const stdin = std.Io.File.stdin();
    const stdout = std.Io.File.stdout();
    const original = try setup();
    defer std.posix.tcsetattr(stdin.handle, .FLUSH, original) catch {};

    // Enter alternate screen and hide cursor
    try stdout.writeStreamingAll(io, utils.enter_alt_screen ++ utils.clear_screen ++ utils.hide_cursor);
    // try stdout.writeStreamingAll(io, utils.leave_alt_screen //
    // ++ utils.show_cursor //
    // ++ utils.enter_alt_screen //
    // ++ utils.cursor_home //
    // ++ utils.clear_screen //
    // ++ utils.hide_cursor //
    // );
    defer stdout.writeStreamingAll(io, utils.show_cursor ++ utils.leave_alt_screen) catch {};

    // Terminal size
    var size = try getTermSize();

    // Data
    var state = State.init(alloc);
    defer state.deinit();

    // Canvas
    var canvas = try Canvas.init(alloc, io, stdout);
    defer canvas.deinit();

    // App
    var app = try App.init(alloc, &state, size.cols, size.rows, cfg, io);
    defer app.deinit();

    if (app.transport.fetch("GetDevices")) |parsed| {
        defer parsed.deinit();
        state.loadFromJson(parsed.value) catch {};
    }
    app.layout.view = &app.view;

    // Canvas
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
                if (!app.handleKey(buf[0])) return;
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
