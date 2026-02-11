const std = @import("std");
const Color = @import("../color.zig");
const Rect = @import("../types.zig").Rect;

pub const Panel = struct {
    rect: Rect,

    pub fn init(x: u16, y: u16, width: u16, height: u16) Panel {
        return .{ .rect = .{ .x = x, .y = y, .width = width, .height = height } };
    }

    pub fn draw(self: Panel, stdout: std.fs.File, labels: [4]?[]const u8) !void {
        var pos_buf: [32]u8 = undefined;

        // Top border
        var pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.rect.y, self.rect.x });
        try stdout.writeAll(pos);
        try stdout.writeAll(Color.peach);
        try stdout.writeAll(Color.dim);
        try stdout.writeAll("╭");

        // Top left label
        if (labels[0]) |tl| {
            try stdout.writeAll(" ");
            try stdout.writeAll(Color.reset);
            try stdout.writeAll(Color.lavender);
            try stdout.writeAll(tl);
            try stdout.writeAll(Color.reset);
            try stdout.writeAll(Color.peach);
            try stdout.writeAll(Color.dim);
            try stdout.writeAll(" ");
        }

        // Fill top border, leaving room for top right label
        const tl_len: u16 = if (labels[0]) |tl| displayWidth(tl) + 2 else 0;
        const tr_len: u16 = if (labels[1]) |tr| displayWidth(tr) + 2 else 0;
        var i: u16 = 1 + tl_len;
        while (i < self.rect.width - 1 - tr_len) : (i += 1) {
            try stdout.writeAll("─");
        }

        // Top right label
        if (labels[1]) |tr| {
            try stdout.writeAll(" ");
            try stdout.writeAll(Color.reset);
            try stdout.writeAll(Color.lavender);
            try stdout.writeAll(tr);
            try stdout.writeAll(Color.reset);
            try stdout.writeAll(Color.peach);
            try stdout.writeAll(Color.dim);
            try stdout.writeAll(" ");
        }

        try stdout.writeAll("╮");

        // Sides (same as before)
        var row: u16 = 1;
        while (row < self.rect.height - 1) : (row += 1) {
            pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.rect.y + row, self.rect.x });
            try stdout.writeAll(pos);
            try stdout.writeAll(Color.peach);
            try stdout.writeAll(Color.dim);
            try stdout.writeAll("│");
            try stdout.writeAll(Color.reset);
            var col: u16 = 1;
            while (col < self.rect.width - 1) : (col += 1) {
                try stdout.writeAll(" ");
            }
            try stdout.writeAll(Color.peach);
            try stdout.writeAll(Color.dim);
            try stdout.writeAll("│");
            try stdout.writeAll(Color.reset);
        }

        // Bottom border
        pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.rect.y +
            self.rect.height - 1, self.rect.x });
        try stdout.writeAll(pos);
        try stdout.writeAll(Color.peach);
        try stdout.writeAll(Color.dim);
        try stdout.writeAll("╰");

        // Bottom left label
        const bl_len: u16 = if (labels[3]) |bl| displayWidth(bl) + 2 else 0;
        const br_len: u16 = if (labels[2]) |br| displayWidth(br) + 2 else 0;

        if (labels[3]) |bl| {
            try stdout.writeAll(" ");
            try stdout.writeAll(Color.reset);
            try stdout.writeAll(Color.lavender);
            try stdout.writeAll(bl);
            try stdout.writeAll(Color.reset);
            try stdout.writeAll(Color.peach);
            try stdout.writeAll(Color.dim);
            try stdout.writeAll(" ");
        }

        i = 1 + bl_len;
        while (i < self.rect.width - 1 - br_len) : (i += 1) {
            try stdout.writeAll("─");
        }

        // Bottom right label
        if (labels[2]) |br| {
            try stdout.writeAll(" ");
            try stdout.writeAll(Color.reset);
            try stdout.writeAll(Color.lavender);
            try stdout.writeAll(br);
            try stdout.writeAll(Color.reset);
            try stdout.writeAll(Color.peach);
            try stdout.writeAll(Color.dim);
            try stdout.writeAll(" ");
        }

        try stdout.writeAll("╯");
        try stdout.writeAll(Color.reset);
    }

    pub fn clear(self: Panel, stdout: std.fs.File) !void {
        var pos_buf: [32]u8 = undefined;
        var row: u16 = 0;
        while (row < self.rect.height) : (row += 1) {
            const pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.rect.y + row, self.rect.x });
            try stdout.writeAll(pos);
            try stdout.writeAll("\x1b[K");
        }
    }

    fn displayWidth(s: []const u8) u16 {
        var width: u16 = 0;
        var i: usize = 0;
        while (i < s.len) {
            const byte = s[i];
            if (byte < 0x80) {
                // ASCII - 1 column
                width += 1;
                i += 1;
            } else if (byte & 0xE0 == 0xC0) {
                // 2-byte UTF-8
                width += 1;
                i += 2;
            } else if (byte & 0xF0 == 0xE0) {
                // 3-byte UTF-8 (CJK, some symbols)
                width += 2;
                i += 3;
            } else if (byte & 0xF8 == 0xF0) {
                // 4-byte UTF-8 (emojis)
                width += 2;
                i += 4;
            } else {
                i += 1;
            }
        }
        return width;
    }
};
