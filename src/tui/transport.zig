const std = @import("std");
const Config = @import("../config.zig").Config;
const Allocator = std.mem.Allocator;

pub const Transport = struct {
    alloc: Allocator,
    cfg: Config,
    io: std.Io,

    pub fn init(alloc: Allocator, cfg: Config, io: std.Io) Transport {
        return .{ .alloc = alloc, .cfg = cfg, .io = io };
    }

    pub fn fetch(self: *Transport, bytes: []const u8) ?std.json.Parsed(std.json.Value) {
        const stream = self.connect() catch return null;
        defer stream.close(self.io);
        const raw = self.sendCmd(stream, bytes) catch return null;
        defer self.alloc.free(raw);
        var parsed = std.json.parseFromSlice(std.json.Value, self.alloc, raw, .{}) catch return null;

        // If response includes data.data we return the inner
        if (parsed.value == .object) {
            if (parsed.value.object.get("data")) |outer_data| {
                if (outer_data == .object and outer_data.object.contains("data")) {
                    parsed.value = outer_data;
                }
            }
        }

        return parsed;
    }

    fn connect(self: *Transport) !std.Io.net.Stream {
        const address = try std.Io.net.IpAddress.parseIp4(self.cfg.host, self.cfg.port);
        return address.connect(self.io, .{ .mode = .stream });
    }

    fn sendCmd(self: *Transport, stream: std.Io.net.Stream, cmd: []const u8) ![]const u8 {
        const req = try self.buildRequest(cmd);
        defer self.alloc.free(req);

        var write_buf: [4096]u8 = undefined;
        var w = stream.writer(self.io, &write_buf);
        try w.interface.writeAll(req);
        try w.interface.flush();

        var read_buf: [4096]u8 = undefined;
        var r = stream.reader(self.io, &read_buf);

        var res: std.ArrayList(u8) = .empty;
        errdefer res.deinit(self.alloc);

        var chunk: [4096]u8 = undefined;
        while (true) {
            var bufs: [1][]u8 = .{&chunk};
            const bytes_read = r.interface.readVec(&bufs) catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };
            if (bytes_read == 0) continue;
            try res.appendSlice(self.alloc, chunk[0..bytes_read]);
            if (isCompleteJson(res.items)) break;
        }

        return res.toOwnedSlice(self.alloc);
    }

    fn buildRequest(self: *Transport, cmd: []const u8) ![]const u8 {
        var req_map: std.json.ObjectMap = .empty;
        defer req_map.deinit(self.alloc);

        var data_map: std.json.ObjectMap = .empty;
        defer data_map.deinit(self.alloc);

        try req_map.put(self.alloc, "command", .{ .string = cmd });
        try req_map.put(self.alloc, "data", .{ .object = data_map });

        var aw: std.Io.Writer.Allocating = .init(self.alloc);
        defer aw.deinit();
        try std.json.fmt(std.json.Value{ .object = req_map }, .{}).format(&aw.writer);
        return try aw.toOwnedSlice();
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
};
