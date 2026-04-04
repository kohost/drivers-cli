const std = @import("std");
const Rect = @import("../types.zig").Rect;
const KeyResult = @import("../types.zig").KeyResult;

pub const ApiView = struct {
    area: Rect,

    const Self = @This();

    pub fn init(area: Rect) Self {
        return .{ .area = area };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn render(self: *Self, stdout: std.fs.File, has_focus: bool) !void {
        _ = has_focus;
        var pos_buf: [32]u8 = undefined;
        var row: u16 = 0;
        while (row < self.area.height) : (row += 1) {
            const pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + row, self.area.x });
            try stdout.writeAll(pos);
            try stdout.writeAll("\x1b[K");
        }
    }

    pub fn handleKey(self: *Self, stdout: std.fs.File, c: u8) !KeyResult {
        _ = self;
        _ = stdout;
        _ = c;
        return .unhandled;
    }
};
