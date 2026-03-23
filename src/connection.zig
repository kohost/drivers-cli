const std = @import("std");
const parse = @import("parse.zig");

/// Opens a TCP connection to a Kohost driver at the given host and port.
pub fn connect(host: []const u8, port: u16) !std.net.Stream {
    const address = try std.net.Address.parseIp(host, port);
    const stream = try std.net.tcpConnectToAddress(address);

    return stream;
}

/// Builds a JSON request from the command string, sends it over the stream,
/// reads the response until complete JSON is received, and returns the data payload.
/// Caller owns the returned slice.
pub fn sendCmd(stream: std.net.Stream, alloc: std.mem.Allocator, cmd: []const u8) ![]const u8 {
    const req = try parse.buildRequest(alloc, cmd);
    defer alloc.free(req);

    _ = try stream.write(req);

    var response: std.ArrayListUnmanaged(u8) = .empty;
    errdefer response.deinit(alloc);

    var buffer: [4096]u8 = undefined;
    while (true) {
        const bytes_read = try stream.read(&buffer);
        if (bytes_read == 0) break;
        try response.appendSlice(alloc, buffer[0..bytes_read]);

        if (parse.isCompleteJson(response.items)) break;
    }

    const data = try parse.getData(alloc, response.items);
    response.deinit(alloc);
    return data;
}
