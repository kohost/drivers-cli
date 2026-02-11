const std = @import("std");
const Color = @import("../color.zig");
const Panel = @import("panels.zig").Panel;

pub const Popup = struct {
    buf: [32]u8 = undefined,
    len: u8 = 0,
    visible: bool = false,
    title: []const u8,

    pub fn init(title: []const u8) Popup {
        return .{ .title = title };
    }

    pub fn show(self: *Popup) void {
        self.visible = true;
        self.len = 0;
    }

    pub fn hide(self: *Popup) void {
        self.visible = false;
        self.len = 0;
    }

    pub fn render(self: *Popup, stdout: std.fs.File, cols: u16, rows: u16) !void {
        if (!self.visible) return;

        const width: u16 = 30;
        const height: u16 = 3;
        const x = (cols - width) / 2;
        const y = (rows - height) / 2;

        var panel = Panel.init(x, y, width, height);
        try panel.draw(stdout, .{ self.title, null, null, null });

        var pos_buf: [32]u8 = undefined;

        const input_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ y + 1, x + 2 });
        try stdout.writeAll(input_pos);
        try stdout.writeAll(self.buf[0..self.len]);

        // Show cursor
        try stdout.writeAll("\x1b[?25h");
    }

    pub fn clear(self: *Popup, stdout: std.fs.File, cols: u16, rows: u16) !void {
        if (self.visible) return;
        const width: u16 = 30;
        const height: u16 = 3;
        const x = (cols - width) / 2;
        const y = (rows - height) / 2;
        var panel = Panel.init(x, y, width, height);
        try panel.clear(stdout);
        try stdout.writeAll("\x1b[?25l");
    }

    pub fn handleKey(self: *Popup, c: u8) ?[]const u8 {
        switch (c) {
            '\r', '\n' => {
                const result = self.buf[0..self.len];
                self.hide();
                return result;
            },
            0x1b => {
                self.hide();
                return null;
            },
            0x7f => {
                if (self.len > 0) self.len -= 1;
                return null;
            },
            else => {
                if (self.len < self.buf.len) {
                    self.buf[self.len] = c;
                    self.len += 1;
                }
                return null;
            },
        }
    }
};
