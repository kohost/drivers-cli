const std = @import("std");
const Color = @import("../color.zig");
const Rect = @import("../types.zig").Rect;
const KeyResult = @import("../types.zig").KeyResult;

pub const Tab = struct {
    labels: []const []const u8,
    selected: usize = 0,
    x: u16 = 0,
    y: u16 = 0,

    pub fn init(labels: []const []const u8, x: u16, y: u16) Tab {
        return .{ .labels = labels, .x = x, .y = y };
    }

    pub fn draw(self: Tab, stdout: std.fs.File, focused: bool) !void {
        // Move to position
        var pos_buf: [32]u8 = undefined;
        const pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.y, self.x });
        try stdout.writeAll(pos);
        try stdout.writeAll("\x1b[K");

        for (self.labels, 0..) |label, idx| {
            if (idx == self.selected) {
                if (focused) {
                    try stdout.writeAll("\x1b[4m"); // Underline
                }
                try stdout.writeAll(Color.mauve);
            } else {
                try stdout.writeAll(Color.overlay1);
            }
            try stdout.writeAll(label);
            try stdout.writeAll(Color.reset);

            if (idx < self.labels.len - 1) {
                try stdout.writeAll(Color.dim);
                try stdout.writeAll("  |  ");
                try stdout.writeAll(Color.reset);
            }
        }
    }

    pub fn next(self: *Tab) void {
        if (self.selected < self.labels.len - 1) self.selected += 1 else self.selected = 0;
    }

    pub fn prev(self: *Tab) void {
        if (self.selected > 0) self.selected -= 1 else self.selected = self.labels.len - 1;
    }

    pub fn handleKey(self: *Tab, stdout: std.fs.File, c: u8) !KeyResult {
        switch (c) {
            'h' => {
                self.prev();
                try self.draw(stdout, true);
                return .consumed;
            },
            'l' => {
                self.next();
                try self.draw(stdout, true);
                return .consumed;
            },
            'j' => return .{ .move_to = .down },
            else => return .unhandled,
        }
    }
};
