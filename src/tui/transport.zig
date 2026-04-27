const std = @import("std");
const Config = @import("../config.zig").Config;
const Allocator = std.mem.Allocator;

pub const Transport = struct {
    alloc: Allocator,
    cfg: Config,

    pub fn init(alloc: Allocator, cfg: Config) Transport {
        return .{ .alloc = alloc, .cfg = cfg };
    }

    pub fn fetch(self: *Transport, cmd: []const u8) ?std.json.Parsed(std.json.Value) {
        const stream = self.connect() catch return null;
        defer stream.close();
        const raw = self.sendCmd(stream, cmd) catch return null;
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

    fn connect(self: *Transport) !std.net.Stream {
        const address = try std.net.Address.parseIp(self.cfg.host, self.cfg.port);
        return try std.net.tcpConnectToAddress(address);
    }

    fn sendCmd(self: *Transport, stream: std.net.Stream, cmd: []const u8) ![]const u8 {
        const req = try self.buildRequest(cmd);
        defer self.alloc.free(req);
        _ = try stream.write(req);

        var res: std.ArrayListUnmanaged(u8) = .empty;
        errdefer res.deinit(self.alloc);

        var buf: [4096]u8 = undefined;
        while (true) {
            const bytes_read = try stream.read(&buf);
            if (bytes_read == 0) break;
            try res.appendSlice(self.alloc, buf[0..bytes_read]);
            if (isCompleteJson(res.items)) break;
        }

        return res.toOwnedSlice(self.alloc);
    }

    fn buildRequest(self: *Transport, cmd: []const u8) ![]const u8 {
        var req_map = std.json.ObjectMap.init(self.alloc);
        defer req_map.deinit();

        try req_map.put("command", .{ .string = cmd });
        try req_map.put("data", .{ .object = std.json.ObjectMap.init(self.alloc) });

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
