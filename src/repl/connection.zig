const std = @import("std");
const parse = @import("parse.zig");

/// Opens a TCP connection to a Kohost driver at the given host and port.
pub fn connect(io: std.Io, host: []const u8, port: u16) !std.Io.net.Stream {
    const address = try std.Io.net.IpAddress.parseIp4(host, port);
    return address.connect(io, .{ .mode = .stream });
}

/// Builds a JSON request from the command string, sends it over the stream,
/// reads the response until complete JSON is received, and returns the data payload.
/// Caller owns the returned slice.
pub fn sendCmd(io: std.Io, stream: std.Io.net.Stream, alloc: std.mem.Allocator, cmd: []const u8) ![]const u8 {
    const req = try parse.buildRequest(alloc, cmd);
    defer alloc.free(req);

    var write_buf: [4096]u8 = undefined;
    var w = stream.writer(io, &write_buf);
    try w.interface.writeAll(req);
    try w.interface.flush();

    var response: std.ArrayList(u8) = .empty;
    errdefer response.deinit(alloc);

    var chunk: [4096]u8 = undefined;
    while (true) {
        const bytes_read = try std.posix.read(stream.socket.handle, &chunk);
        if (bytes_read == 0) break;
        try response.appendSlice(alloc, chunk[0..bytes_read]);
        if (parse.isCompleteJson(response.items)) break;
    }

    const data = try parse.getData(alloc, response.items);
    response.deinit(alloc);
    return data;
}
