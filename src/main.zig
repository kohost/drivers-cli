const std = @import("std");
const config = @import("config");
const parse = @import("./parse.zig");
const term = @import("./terminal.zig");
const commands = @import("./commands.zig");

fn connect(host: []const u8, port: u16) !std.net.Stream {
    const address = try std.net.Address.parseIp(host, port);
    const stream = try std.net.tcpConnectToAddress(address);

    return stream;
}

fn sendCmd(stream: std.net.Stream, alloc: std.mem.Allocator, cmd: []const u8, filter: ?[]const u8) !void {
    // Build JSON request
    const req = try parse.buildRequest(alloc, cmd);
    defer alloc.free(req);

    _ = try stream.write(req);

    // Read response
    var buffer: [8192]u8 = undefined;
    const bytes_read = try stream.read(&buffer);
    const res = buffer[0..bytes_read];

    const data = try parse.getData(alloc, res);
    defer alloc.free(data);

    // Apply filter if present
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

pub fn main() !void {
    // Get allocator
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // Parse command line args
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    // Default to localhost:16483
    const host = if (args.len > 1) args[1] else "127.0.0.1";
    const port = if (args.len > 2) try std.fmt.parseInt(u16, args[2], 10) else 16483;

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
    const prompt = try std.fmt.allocPrint(alloc, "{s}:{d}> ", .{ host, port });
    defer alloc.free(prompt);

    while (true) {
        std.debug.print("{s}:{d}> ", .{ host, port });
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

        const stream = connect(host, port) catch |err| {
            std.debug.print("{s} at {s}:{d}\n", .{ @errorName(err), host, port });
            continue;
        };
        defer stream.close();

        _ = sendCmd(stream, alloc, cmd, filter) catch |err| {
            std.debug.print("SendCmd Error: {s}\n", .{@errorName(err)});
        };
    }
}
