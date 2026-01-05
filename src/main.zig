const std = @import("std");
const config = @import("config");
const connection = @import("./connection.zig");
const parse = @import("./parse.zig");
const term = @import("./terminal.zig");
const commands = @import("./commands.zig");
const tui = @import("./tui/tui.zig");

pub const Config = struct { host: []const u8, port: u16, use_tui: bool };

pub fn main() !void {
    // Get allocator
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // Parse command line args
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    // Parse args - Exit on null return
    const cfg = parseArgs(args) catch |err| {
        std.debug.print("{s}\n", .{@errorName(err)});
        return;
    };
    if (cfg.use_tui) {
        try tui.run(cfg, alloc);
        return;
    }

    // Enable raw mode to capture up and down arrows
    const original_termios = try term.enableRawMode();
    defer term.disableRawMode(original_termios) catch {};

    var buffer: [1024]u8 = undefined;

    // Command history
    var history: std.ArrayList([]const u8) = .{};
    defer {
        for (history.items) |cmd| {
            alloc.free(cmd);
        }
        history.deinit(alloc);
    }

    // Prompt
    const prompt = try std.fmt.allocPrint(alloc, "{s}:{d}> ", .{ cfg.host, cfg.port });
    defer alloc.free(prompt);

    while (true) {
        std.debug.print("{s}:{d}> ", .{ cfg.host, cfg.port });
        const input = term.readUserInput(&buffer, &history, prompt) catch |err| {
            std.debug.print("Error: {s}\n", .{@errorName(err)});
            continue;
        };

        // Check to see if we have any response filters
        var parts = std.mem.splitScalar(u8, input, '|');
        const cmd = std.mem.trim(u8, parts.first(), " ");
        const filter = if (parts.next()) |f| std.mem.trim(u8, f, " ") else null;

        if (cmd.len == 0) continue;
        if (std.mem.eql(u8, cmd, "exit")) break;
        if (std.mem.eql(u8, cmd, "version")) {
            std.debug.print("{s}\n", .{config.version});
            continue;
        }
        if (std.mem.eql(u8, cmd, "help")) {
            // Copies the array into new mutable var on stack
            var sorted = commands.list;
            std.mem.sort(commands.CommandInfo, &sorted, {}, struct {
                fn cmp(_: void, a: commands.CommandInfo, b: commands.CommandInfo) bool {
                    return std.mem.lessThan(u8, a.name, b.name);
                }
            }.cmp);
            std.debug.print("\n{s:<20} {s:<8} {s}\n", .{ "Command", "Alias", "Description" });
            std.debug.print("{s}\n", .{"-" ** 50});
            for (sorted) |c| {
                std.debug.print("{s:<20} {s:<8} {s}\n", .{ c.name, c.alias orelse "", c.description });
            }
            std.debug.print("\n", .{});
            continue;
        }

        // Save to history (duplicate the string for persistance)
        if (history.items.len == 0 or !std.mem.eql(u8, history.items[history.items.len - 1], input)) {
            const input_copy = try alloc.dupe(u8, input);
            try history.append(alloc, input_copy);
        }

        const stream = connection.connect(cfg.host, cfg.port) catch |err| {
            std.debug.print("{s} at {s}:{d}\n", .{ @errorName(err), cfg.host, cfg.port });
            continue;
        };
        defer stream.close();

        const data = connection.sendCmd(stream, alloc, cmd) catch |err| {
            std.debug.print("SendCmd Error: {s}\n", .{@errorName(err)});
            continue;
        };
        defer alloc.free(data);

        if (filter) |f| {
            const filtered = try parse.applyFilter(alloc, data, f);
            defer alloc.free(filtered);

            // Format each line separately (filter may return multiple values)
            var lines = std.mem.splitScalar(u8, filtered, '\n');
            while (lines.next()) |line| {
                if (line.len == 0) continue;
                const formatted = try parse.formatJSON(alloc, line);
                defer alloc.free(formatted);
                std.debug.print("{s}\n", .{formatted});
            }
        } else {
            const parsed = try parse.formatJSON(alloc, data);
            defer alloc.free(parsed);
            std.debug.print("{s}\n", .{parsed});
        }
    }
}

fn parseArgs(args: [][:0]u8) !Config {
    var use_tui = false;
    var host: []const u8 = "127.0.0.1";
    var port: u16 = 16483;

    for (args[1..], 0..) |arg, idx| {
        if (std.mem.eql(u8, arg, "--tui")) {
            use_tui = true;
            break;
        } else {
            switch (idx) {
                0 => host = arg,
                1 => port = std.fmt.parseInt(u16, arg, 10) catch {
                    return error.InvalidPort;
                },
                else => return error.InvalidArg,
            }
        }
    }
    return .{
        .host = host,
        .port = port,
        .use_tui = use_tui,
    };
}
