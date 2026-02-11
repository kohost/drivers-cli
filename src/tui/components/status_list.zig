const std = @import("std");
const Color = @import("../color.zig");

pub const StatusList = struct {
    x: u16,
    y: u16,
    open: bool = false,
    cursor: usize = 0,

    pub const Item = struct {
        id: []const u8,
        name: []const u8,
        secure: ?bool,
        bypassed: ?bool,
        offline: bool,
    };

    pub fn init(x: u16, y: u16) StatusList {
        return .{ .x = x, .y = y };
    }

    pub fn render(self: *StatusList, stdout: std.fs.File, items: []const Item, focused: bool) !void {
        var pos_buf: [32]u8 = undefined;

        if (!self.open) {
            const pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.y, self.x });
            try stdout.writeAll(pos);

            if (focused) {
                try stdout.writeAll(Color.peach);
                try stdout.writeAll("▶︎ ");
                try stdout.writeAll(Color.reset);
                try stdout.writeAll("\x1b[4m");
                try stdout.writeAll(Color.underline_peach);
            } else {
                try stdout.writeAll("▶︎ ");
            }

            var summary_buf: [64]u8 = undefined;
            const summary = buildSummary(&summary_buf, items);
            try stdout.writeAll(summary);
            try stdout.writeAll(Color.reset);
            return;
        }

        // Find longest name
        var max_name: usize = 0;
        for (items) |item| {
            if (item.name.len > max_name) max_name = item.name.len;
        }

        // Expanded: items start at y
        for (items, 0..) |item, i| {
            const row = self.y + @as(u16, @intCast(i));
            const pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ row, self.x });
            try stdout.writeAll(pos);

            if (i == self.cursor and focused) {
                try stdout.writeAll(Color.peach);
                try stdout.writeAll("▶︎ ");
                try stdout.writeAll(Color.reset);
            } else {
                try stdout.writeAll("  ");
            }

            if (item.bypassed != null and item.bypassed.?) {
                try stdout.writeAll(Color.yellow);
                try stdout.writeAll("● ");
            } else if (item.secure) |s| {
                if (s) {
                    try stdout.writeAll(Color.green);
                    try stdout.writeAll("✔︎ ");
                } else {
                    try stdout.writeAll(Color.red);
                    try stdout.writeAll("✘ ");
                }
            } else {
                try stdout.writeAll(Color.overlay0);
                try stdout.writeAll("○ ");
            }
            try stdout.writeAll(Color.reset);

            try stdout.writeAll(item.name);
            var name_pad = item.name.len;
            while (name_pad < max_name + 1) : (name_pad += 1) {
                try stdout.writeAll(" ");
            }
        }
    }

    pub fn close(self: *StatusList, stdout: std.fs.File, item_count: usize) !void {
        var pos_buf: [32]u8 = undefined;
        var row: u16 = 0;
        while (row < item_count) : (row += 1) {
            const pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H\x1b[K", .{ self.y + row, self.x });
            try stdout.writeAll(pos);
        }
        self.open = false;
        self.cursor = 0;
    }

    pub fn height(self: *StatusList, item_count: usize) u16 {
        if (self.open) return @intCast(item_count);
        return 1;
    }

    fn buildSummary(buf: *[64]u8, items: []const Item) []const u8 {
        var secure: u16 = 0;
        var open_count: u16 = 0;
        var bypassed: u16 = 0;
        var offline: u16 = 0;

        for (items) |item| {
            if (item.offline) {
                offline += 1;
            } else if (item.bypassed != null and item.bypassed.?) {
                bypassed += 1;
            } else if (item.secure) |s| {
                if (s) secure += 1 else open_count += 1;
            }
        }

        var stream = std.io.fixedBufferStream(buf);
        const w = stream.writer();
        var first = true;

        if (secure > 0) {
            w.print("{d} secure", .{secure}) catch {};
            first = false;
        }
        if (open_count > 0) {
            if (!first) w.writeAll(", ") catch {};
            w.print("{d} open", .{open_count}) catch {};
            first = false;
        }
        if (bypassed > 0) {
            if (!first) w.writeAll(", ") catch {};
            w.print("{d} bypassed", .{bypassed}) catch {};
            first = false;
        }
        if (offline > 0) {
            if (!first) w.writeAll(", ") catch {};
            w.print("{d} offline", .{offline}) catch {};
        }

        return stream.getWritten();
    }
};
