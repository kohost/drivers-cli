const std = @import("std");
const Color = @import("../color.zig");
const Rect = @import("../types.zig").Rect;

pub const Panel = struct {
    rect: Rect,

    pub fn init(x: u16, y: u16, width: u16, height: u16) Panel {
        return .{ .rect = .{ .x = x, .y = y, .width = width, .height = height } };
    }

    pub fn draw(self: Panel, stdout: std.fs.File, titles: []const ?[]const u8) !void {
        // Move to position
        var pos_buf: [32]u8 = undefined;
        var pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.rect.y, self.rect.x });
        var titles_len: u8 = 0;
        try stdout.writeAll(pos);

        // Top
        try stdout.writeAll(Color.teal);
        try stdout.writeAll(Color.dim);
        try stdout.writeAll("┌┐");
        try stdout.writeAll(Color.reset);
        for (titles, 0..) |maybe_title, idx| {
            const title = maybe_title orelse continue; // skip nulls
            titles_len += @intCast(title.len);
            try stdout.writeAll(title);
            if (idx < titles.len - 1) {
                titles_len += 2;
                try stdout.writeAll(Color.teal);
                try stdout.writeAll(Color.dim);
                try stdout.writeAll("┌┐");
                try stdout.writeAll(Color.reset);
            }
        }
        try stdout.writeAll(Color.teal);
        try stdout.writeAll(Color.dim);
        try stdout.writeAll("┌");

        // self.title.len is usize so we cast to int
        var i: u8 = 4 + titles_len;

        while (i < self.rect.width) : (i += 1) {
            try stdout.writeAll("─");
        }

        try stdout.writeAll("┐");

        // Sides
        var row: u16 = 1;
        while (row < self.rect.height - 1) : (row += 1) {
            pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.rect.y + row, self.rect.x });
            try stdout.writeAll(pos);
            try stdout.writeAll("│");

            // Clear interior
            var col: u16 = 1;
            while (col < self.rect.width - 1) : (col += 1) {
                try stdout.writeAll(" ");
            }

            try stdout.writeAll("│");
        }

        // Bottom
        pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.rect.y + self.rect.height - 1, self.rect.x });

        try stdout.writeAll(pos);
        try stdout.writeAll("└");
        i = 1;
        while (i < self.rect.width - 1) : (i += 1) {
            try stdout.writeAll("─");
        }
        try stdout.writeAll("┘");

        try stdout.writeAll(Color.reset);
    }
};
