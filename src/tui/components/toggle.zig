const std = @import("std");
const Color = @import("../color.zig");

pub const Toggle = struct {
    labels: [2][]const u8,
    x: u16,
    y: u16,

    pub fn init(x: u16, y: u16, labels: [2][]const u8) Toggle {
        return .{ .x = x, .y = y, .labels = labels };
    }

    pub fn render(self: *Toggle, stdout: std.fs.File, state: bool, focused: bool) !void {
        var pos_buf: [32]u8 = undefined;
        const pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.y, self.x });
        try stdout.writeAll(pos);

        if (state) {
            try stdout.writeAll(Color.green);
            try stdout.writeAll("✔︎ ");
        } else {
            try stdout.writeAll(Color.red);
            try stdout.writeAll("✘ ");
        }
        try stdout.writeAll(Color.reset);

        if (focused) {
            try stdout.writeAll("\x1b[4m");
            try stdout.writeAll(Color.underline_teal);
        }

        if (state) {
            try stdout.writeAll(self.labels[0]);
        } else {
            try stdout.writeAll(self.labels[1]);
        }

        try stdout.writeAll(Color.reset);
    }
};
