const std = @import("std");
const Color = @import("../../color.zig");
const utils = @import("../../utils.zig");
const KeyResult = @import("../../input.zig").KeyResult;
const Cursor = @import("../../canvas.zig").Cursor;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;

pub const Footer = struct {
    y: u16,
    width: u16,
    status: []const u8,
    buf: [64]u8,
    len: usize,
    active: bool,
    prefix: u8,

    pub fn init(opts: struct {
        y: u16,
        width: u16,
        status: []const u8 = "",
    }) Footer {
        return .{
            .y = opts.y,
            .width = opts.width,
            .status = opts.status,
            .buf = undefined,
            .len = 0,
            .active = false,
            .prefix = ':',
        };
    }

    pub fn open(self: *Footer, prefix: u8, prefill: []const u8) void {
        self.active = true;
        self.prefix = prefix;
        const copy_len = @min(prefill.len, self.buf.len);
        if (copy_len > 0) {
            @memcpy(self.buf[0..copy_len], prefill[0..copy_len]);
        }
        self.len = copy_len;
    }

    pub fn input(self: *const Footer) []const u8 {
        return self.buf[0..self.len];
    }

    pub fn handleKey(self: *Footer, key: u8, mq: *MessageQueue) KeyResult {
        switch (key) {
            '\r', '\n' => {
                self.active = false;
                mq.post(.submit_input);
            },
            0x1b => {
                self.active = false;
                mq.post(.cancel_input);
            },
            0x7f => {
                if (self.len > 0) {
                    self.len -= 1;
                    mq.post(.render);
                } else {
                    self.active = false;
                    mq.post(.cancel_input);
                }
            },
            else => {
                if (self.len < self.buf.len) {
                    self.buf[self.len] = key;
                    self.len += 1;
                    mq.post(.render);
                }
            },
        }
        return .consumed;
    }

    pub fn write(self: *const Footer, writer: *std.Io.Writer, cursor: *Cursor) !void {
        try utils.moveTo(writer, 1, self.y);
        for (0..self.width) |_| try writer.writeAll(" ");
        try utils.moveTo(writer, 1, self.y);
        try writer.writeAll(Color.bg_mantle);
        if (self.active) {
            try writer.writeAll(Color.text);
            try writer.writeAll(&.{self.prefix});
            try writer.writeAll(self.buf[0..self.len]);
            cursor.x = @intCast(1 + 1 + self.len);
            cursor.y = self.y;
            cursor.visible = true;
        } else {
            try writer.writeAll(Color.mauve);
            try writer.writeAll(self.status);
        }
        try writer.writeAll(Color.reset);
    }
};
