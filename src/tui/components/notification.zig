const std = @import("std");
const Color = @import("../color.zig");

pub const Notification = struct {
    message: [128]u8 = undefined,
    msg_len: u8 = 0,
    timestamp: i64 = 0,
    visible: bool = false,
    slide_offset: u16 = 0,

    const hold_ms: i64 = 4000;
    const slide_ms: i64 = 300;
    const max_width: u16 = 40;
    const padding: u16 = 2;
    const border_overhead: u16 = 2;

    // red (243,139,168) -> surface0 (49,50,68)
    const r0: i64 = 243;
    const g0: i64 = 139;
    const b0: i64 = 168;
    const r1: i64 = 49;
    const g1: i64 = 50;
    const b1: i64 = 68;

    pub fn init() Notification {
        return .{};
    }

    pub fn show(self: *Notification, msg: []const u8) void {
        const len = @min(msg.len, self.message.len);
        @memcpy(self.message[0..len], msg[0..len]);
        self.msg_len = @intCast(len);
        self.timestamp = std.time.milliTimestamp();
        self.visible = true;
        self.slide_offset = 0;
    }

    pub fn isAnimating(self: *Notification) bool {
        if (!self.visible) return false;
        const elapsed = std.time.milliTimestamp() - self.timestamp;
        return elapsed >= hold_ms;
    }

    fn boxWidth(self: *Notification) u16 {
        const msg = self.message[0..self.msg_len];
        const content_width: u16 = @intCast(@min(msg.len + padding * 2, max_width));
        return content_width + border_overhead;
    }

    fn baseX(self: *Notification, cols: u16) u16 {
        const bw = self.boxWidth();
        return if (cols > bw + 2) cols - bw - 2 else 1;
    }

    fn fadeColor(buf: *[20]u8, t: i64, d: i64) []const u8 {
        const r: u8 = @intCast(r0 + @divTrunc((r1 - r0) * t, d));
        const g: u8 = @intCast(g0 + @divTrunc((g1 - g0) * t, d));
        const b: u8 = @intCast(b0 + @divTrunc((b1 - b0) * t, d));
        return std.fmt.bufPrint(buf, "\x1b[38;2;{d};{d};{d}m", .{ r, g, b }) catch Color.red;
    }

    pub fn tick(self: *Notification, stdout: std.fs.File, cols: u16) bool {
        if (!self.visible) return false;
        const elapsed = std.time.milliTimestamp() - self.timestamp;
        const x = self.baseX(cols);

        if (x + self.slide_offset >= cols) {
            self.visible = false;
            return true;
        }

        if (elapsed >= hold_ms) {
            const t_slide = @min(elapsed - hold_ms, slide_ms);
            const travel: i64 = @intCast(cols - x);
            const new_offset: u16 = @intCast(@divTrunc(travel * t_slide * t_slide, slide_ms * slide_ms));

            if (new_offset != self.slide_offset) {
                const old_x = x + self.slide_offset;
                const strip = new_offset - self.slide_offset;
                self.clearStrip(stdout, old_x, @min(strip, cols -| old_x));
                self.slide_offset = new_offset;
                return true;
            }
        }

        return false;
    }

    pub fn render(self: *Notification, stdout: std.fs.File, cols: u16) void {
        self.renderWithFade(stdout, cols, Color.red);
    }

    fn renderWithFade(self: *Notification, stdout: std.fs.File, cols: u16, color: []const u8) void {
        if (!self.visible) return;
        const x = self.baseX(cols) + self.slide_offset;
        if (x >= cols) return;
        const msg = self.message[0..self.msg_len];
        const content_width: u16 = @intCast(@min(msg.len + padding * 2, max_width));
        const bw = content_width + border_overhead;
        const visible_w: u16 = @min(bw, cols - x);
        const y: u16 = 2;

        var buf: [32]u8 = undefined;

        // Top border
        var pos = std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ y, x }) catch return;
        stdout.writeAll(pos) catch return;
        stdout.writeAll(color) catch return;
        stdout.writeAll(Color.dim) catch return;
        stdout.writeAll("╭") catch return;
        var i: u16 = 1;
        while (i < visible_w -| 1) : (i += 1) {
            stdout.writeAll("─") catch return;
        }
        if (visible_w >= bw) stdout.writeAll("╮") catch return;
        stdout.writeAll(Color.reset) catch return;

        // Message row
        pos = std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ y + 1, x }) catch return;
        stdout.writeAll(pos) catch return;
        stdout.writeAll(color) catch return;
        stdout.writeAll(Color.dim) catch return;
        stdout.writeAll("│") catch return;
        stdout.writeAll(Color.reset) catch return;

        const inner_w = visible_w -| border_overhead;
        var p: u16 = 0;
        while (p < @min(padding, inner_w)) : (p += 1) {
            stdout.writeAll(" ") catch return;
        }

        const text_space = content_width -| padding * 2;
        const display_len: u16 = @intCast(@min(msg.len, text_space));
        const text_visible = @min(display_len, inner_w -| padding);
        stdout.writeAll(color) catch return;
        stdout.writeAll(msg[0..text_visible]) catch return;
        stdout.writeAll(Color.reset) catch return;

        var filled: u16 = padding + text_visible;
        while (filled < inner_w) : (filled += 1) {
            stdout.writeAll(" ") catch return;
        }

        if (visible_w >= bw) {
            stdout.writeAll(color) catch return;
            stdout.writeAll(Color.dim) catch return;
            stdout.writeAll("│") catch return;
            stdout.writeAll(Color.reset) catch return;
        }

        // Bottom border
        pos = std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ y + 2, x }) catch return;
        stdout.writeAll(pos) catch return;
        stdout.writeAll(color) catch return;
        stdout.writeAll(Color.dim) catch return;
        stdout.writeAll("╰") catch return;
        i = 1;
        while (i < visible_w -| 1) : (i += 1) {
            stdout.writeAll("─") catch return;
        }
        if (visible_w >= bw) stdout.writeAll("╯") catch return;
        stdout.writeAll(Color.reset) catch return;
    }

    pub fn renderAnimated(self: *Notification, stdout: std.fs.File, cols: u16) void {
        if (!self.visible) return;
        const elapsed = std.time.milliTimestamp() - self.timestamp;
        if (elapsed < hold_ms) {
            self.renderWithFade(stdout, cols, Color.red);
            return;
        }
        const t_slide = @min(elapsed - hold_ms, slide_ms);
        var color_buf: [20]u8 = undefined;
        const color = fadeColor(&color_buf, t_slide, slide_ms);
        self.renderWithFade(stdout, cols, color);
    }

    fn clearStrip(_: *Notification, stdout: std.fs.File, x: u16, width: u16) void {
        const y: u16 = 2;
        var buf: [32]u8 = undefined;
        var row: u16 = 0;
        while (row < 3) : (row += 1) {
            const pos = std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ y + row, x }) catch return;
            stdout.writeAll(pos) catch return;
            var col: u16 = 0;
            while (col < width) : (col += 1) {
                stdout.writeAll(" ") catch return;
            }
        }
    }

    pub fn clear(self: *Notification, stdout: std.fs.File, cols: u16) void {
        const bw = self.boxWidth();
        const x = self.baseX(cols);
        self.clearStrip(stdout, x, bw);
    }
};
