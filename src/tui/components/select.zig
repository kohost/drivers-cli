const std = @import("std");
const Color = @import("../color.zig");

pub const Select = struct {
    labels: []const []const u8,
    x: u16,
    y: u16,
    open: bool = false,
    cursor: usize = 0,

    pub fn init(x: u16, y: u16, labels: []const []const u8) Select {
        return .{ .x = x, .y = y, .labels = labels };
    }

    pub fn render(self: *Select, stdout: std.fs.File, selected: usize, focused: bool) !void {
        var pos_buf: [32]u8 = undefined;

        if (!self.open) {
            const pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.y, self.x });
            try stdout.writeAll(pos);

            if (focused) {
                try stdout.writeAll("▶︎ ");
                try stdout.writeAll("\x1b[4m");
                try stdout.writeAll(Color.underline_peach);
            } else {
                try stdout.writeAll("▶︎ ");
            }
            try stdout.writeAll(self.labels[selected]);
            try stdout.writeAll(Color.reset);
            return;
        }

        for (self.labels, 0..) |label, i| {
            const row = self.y + @as(u16, @intCast(i));
            const pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ row, self.x });
            try stdout.writeAll(pos);

            if (i == self.cursor) {
                try stdout.writeAll("▶︎ ");
                try stdout.writeAll("\x1b[4m");
                try stdout.writeAll(Color.underline_peach);
                try stdout.writeAll(label);
                try stdout.writeAll(Color.reset);
                try stdout.writeAll(" ");
            } else {
                try stdout.writeAll(Color.dim);
                try stdout.writeAll("  ");
                try stdout.writeAll(label);
                try stdout.writeAll(Color.reset);
                try stdout.writeAll(" ");
            }
        }
    }

    pub fn close(self: *Select, stdout: std.fs.File) !void {
        var pos_buf: [32]u8 = undefined;
        for (0..self.labels.len) |i| {
            const row = self.y + @as(u16, @intCast(i));
            const pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H\x1b[K", .{ row, self.x });
            try stdout.writeAll(pos);
        }
        self.open = false;
    }

    pub fn height(self: *Select) u16 {
        if (self.open) return @intCast(self.labels.len);
        return 1;
    }
};
