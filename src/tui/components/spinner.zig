const std = @import("std");
const Color = @import("../color.zig");

pub const Spinner = struct {
    x: u16,
    y: u16,
    frame: u8 = 0,

    const frames = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };

    pub fn init(x: u16, y: u16) Spinner {
        return .{ .x = x, .y = y };
    }

    pub fn render(self: *Spinner, stdout: std.fs.File, label: []const u8) !void {
        var pos_buf: [32]u8 = undefined;
        const pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.y, self.x });
        try stdout.writeAll(pos);
        try stdout.writeAll(Color.yellow);
        try stdout.writeAll(frames[self.frame % frames.len]);
        try stdout.writeAll(" ");
        try stdout.writeAll(Color.reset);
        try stdout.writeAll(label);
        self.frame +%= 1;
    }
};
