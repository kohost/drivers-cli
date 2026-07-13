const std = @import("std");
const build_options = @import("build_options");
const connection = @import("./repl/connection.zig");
const parse = @import("./repl/parse.zig");
const readline = @import("./repl/readline.zig");
const commands = @import("./commands.zig");
const Config = @import("./config.zig").Config;

pub fn run(cfg: Config, alloc: std.mem.Allocator, io: std.Io) !void {
    // Setup terminal and defer giving it back on program exit
    const stdin = std.Io.File.stdin();
    const stdout = std.Io.File.stdout();
    const original = try setup();
    defer std.posix.tcsetattr(stdin.handle, .FLUSH, original) catch {};

    // Bar cursor (blinking line)
    try stdout.writeStreamingAll(io, "\x1b[5 q");

    // Our buffer for user input
    var input_buf: [1024]u8 = undefined;

    // Command history list
    var history_list: std.ArrayList([]const u8) = .empty;
    defer {
        for (history_list.items) |item| {
            alloc.free(item);
        }
        history_list.deinit(alloc);
    }

    // Prompt (10.4.10.199:15889>)
    const prompt = try std.fmt.allocPrint(alloc, "{s}:{d}> ", .{ cfg.host, cfg.port });
    defer alloc.free(prompt);

    // Main loop
    while (true) {
        try stdout.writeStreamingAll(io, prompt);

        // Get user input
        const input = try readline.readUserInput(io, &input_buf, &history_list, prompt);
        try updateHistory(&history_list, alloc, input);

        if (input.len == 0) continue;
        if (std.mem.eql(u8, input, "exit")) break;
        if (std.mem.eql(u8, input, "help")) {
            // Copy into a mutable array to sort alphabetically
            var sorted: [commands.all.len]commands.Command = undefined;
            @memcpy(sorted[0..], commands.all);
            std.mem.sort(commands.Command, &sorted, {}, struct {
                fn cmp(_: void, a: commands.Command, b: commands.Command) bool {
                    return std.mem.lessThan(u8, @tagName(a), @tagName(b));
                }
            }.cmp);
            var buf: [4096]u8 = undefined;
            var w = stdout.writer(io, &buf);
            try w.interface.print("\n{s:<20} {s:<8} {s}\n", .{ "Command", "Alias", "Description" });
            try w.interface.print("{s}\n", .{"-" ** 50});
            for (sorted) |c| {
                const info = c.info();
                try w.interface.print("{s:<20} {s:<8} {s}\n", .{ @tagName(c), info.alias orelse "", info.description });
            }
            try w.interface.print("\n", .{});
            try w.interface.flush();
            continue;
        }
        if (std.mem.eql(u8, input, "version")) {
            try stdout.writeStreamingAll(io, build_options.version);
            continue;
        }

        // Command
        var parts = std.mem.splitScalar(u8, input, '|');
        const cmd = std.mem.trim(u8, parts.first(), " ");
        const filter = if (parts.next()) |f| std.mem.trim(u8, f, " ") else null;

        try executeCommand(cfg, alloc, io, stdout, cmd, filter);
    }
}

/// Configures the terminal for raw input and returns the original settings for
/// restoration.
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

/// History
fn updateHistory(history: *std.ArrayList([]const u8), alloc: std.mem.Allocator, input: []const u8) !void {
    if (input.len == 0) return;
    if (history.items.len > 0 and std.mem.eql(u8, history.items[history.items.len - 1], input)) return;
    const copy = try alloc.dupe(u8, input);
    try history.append(alloc, copy);
}

/// Connects to the host, sends a command, and prints the response.
/// Optionally filters the response using a pipe expression.
/// Disconnects and clean up when done.
fn executeCommand(
    cfg: Config,
    alloc: std.mem.Allocator,
    io: std.Io,
    stdout: std.Io.File,
    cmd: []const u8,
    filter: ?[]const u8,
) !void {
    const stream = connection.connect(io, cfg.host, cfg.port) catch |err| {
        try stdout.writeStreamingAll(io, @errorName(err));
        try stdout.writeStreamingAll(io, "\n");
        return;
    };
    defer stream.close(io);

    const data = connection.sendCmd(io, stream, alloc, cmd) catch |err| {
        try stdout.writeStreamingAll(io, @errorName(err));
        try stdout.writeStreamingAll(io, "\n");
        return;
    };
    defer alloc.free(data);

    if (filter) |f| {
        const filtered = parse.applyFilter(alloc, data, f) catch |err| {
            try stdout.writeStreamingAll(io, @errorName(err));
            try stdout.writeStreamingAll(io, "\n");
            return;
        };
        defer alloc.free(filtered);

        var lines = std.mem.splitScalar(u8, filtered, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            const formatted = try parse.formatJSON(alloc, line);
            defer alloc.free(formatted);
            try stdout.writeStreamingAll(io, formatted);
            try stdout.writeStreamingAll(io, "\n");
        }
    } else {
        const parsed = try parse.formatJSON(alloc, data);
        defer alloc.free(parsed);
        try stdout.writeStreamingAll(io, parsed);
        try stdout.writeStreamingAll(io, "\n");
    }
}
