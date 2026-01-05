const std = @import("std");
const parse = @import("parse.zig");

pub fn connect(host: []const u8, port: u16) !std.net.Stream {
    const address = try std.net.Address.parseIp(host, port);
    const stream = try std.net.tcpConnectToAddress(address);

    return stream;
}

pub fn sendCmd(stream: std.net.Stream, alloc: std.mem.Allocator, cmd: []const u8) ![]const u8 {
    const req = try parse.buildRequest(alloc, cmd);
    defer alloc.free(req);

    _ = try stream.write(req);

    var response: std.ArrayListUnmanaged(u8) = .empty;
    errdefer response.deinit(alloc);

    var buffer: [4096]u8 = undefined;
    while (true) {
        const bytes_read = stream.read(&buffer) catch break;
        if (bytes_read == 0) break;
        try response.appendSlice(alloc, buffer[0..bytes_read]);

        if (isCompleteJson(response.items)) break;
    }

    const res = try response.toOwnedSlice(alloc);
    defer alloc.free(res);

    return try parse.getData(alloc, res);
}

fn isCompleteJson(data: []const u8) bool {
    if (data.len == 0) return false;

    var depth: i32 = 0;
    var in_string = false;
    var escape = false;

    for (data) |c| {
        if (escape) {
            escape = false;
            continue;
        }
        if (c == '\\' and in_string) {
            escape = true;
            continue;
        }
        if (c == '"') {
            in_string = !in_string;
            continue;
        }
        if (in_string) continue;

        if (c == '{' or c == '[') depth += 1;
        if (c == '}' or c == ']') depth -= 1;
    }

    return depth == 0 and (data[0] == '{' or data[0] == '[');
}
