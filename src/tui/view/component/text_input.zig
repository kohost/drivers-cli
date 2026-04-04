const std = @import("std");
const utils = @import("../../utils.zig");
const Color = @import("../../color.zig");
const Component = @import("../component.zig").Component;
const Cursor = @import("../component.zig").Cursor;
const KeyResult = @import("../component.zig").KeyResult;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;

pub const TextInput = struct {
    source: []const u8,
    buf: [128]u8,
    buf_len: u8,
    cursor: u8,
    editing: bool,
    dirty: bool,

    pub fn init(source: []const u8) TextInput {
        return .{
            .source = source,
            .buf = undefined,
            .buf_len = 0,
            .cursor = 0,
            .editing = false,
            .dirty = false,
        };
    }

    pub fn component(self: *TextInput) Component {
        return .{
            .ptr = @ptrCast(self),
            .vtable = &.{
                .write = write,
                .handleKey = handleKey,
            },
        };
    }

    pub fn write(
        ptr: *anyopaque,
        writer: *std.Io.Writer,
        x: u16,
        y: u16,
        w: u16,
        h: u16,
        cursor: *Cursor,
    ) anyerror!void {
        const self: *const TextInput = @ptrCast(@alignCast(ptr));
        _ = w;
        _ = h;
        const text = if (self.editing or self.dirty) self.buf[0..self.buf_len] else self.source;
        const color = if (self.editing or self.dirty) Color.yellow else Color.text;

        try utils.moveTo(writer, x, y);
        try writer.writeAll(color);
        try writer.writeAll(text);
        try writer.writeAll(Color.reset);

        if (self.editing) {
            cursor.x = x + self.cursor;
            cursor.y = y;
            cursor.visible = true;
        }
    }


    pub fn handleKey(ptr: *anyopaque, key: u8, mq: *MessageQueue) KeyResult {
        const self: *TextInput = @ptrCast(@alignCast(ptr));

        if (!self.editing) {
            switch (key) {
                'l', '\r', '\n' => {
                    const copy_len: u8 = @intCast(@min(self.source.len, self.buf.len));
                    @memcpy(self.buf[0..copy_len], self.source[0..copy_len]);
                    self.buf_len = copy_len;
                    self.cursor = copy_len;
                    self.editing = true;
                    mq.post(.render);
                    return .consumed;
                },
                else => return .ignored,
            }
        }

        switch (key) {
            // Esc
            0x1b => {
                self.editing = false;
                self.dirty = false;
                mq.post(.render);
                return .consumed;
            },
            // Enter
            '\r', '\n' => {
                self.editing = false;
                self.dirty = true;
                mq.post(.render);
                return .consumed;
            },
            // Backspace
            0x7f => {
                if (self.cursor > 0) {
                    self.cursor -= 1;
                    @memmove(self.buf[self.cursor .. self.buf_len - 1], self.buf[self.cursor + 1 .. self.buf_len]);
                    self.buf_len -= 1;
                    mq.post(.render);
                }
                return .consumed;
            },
            else => {
                if (key >= 0x20 and key < 0x7f and self.buf_len < self.buf.len) {
                    @memmove(self.buf[self.cursor + 1 .. self.buf_len + 1], self.buf[self.cursor..self.buf_len]);
                    self.buf[self.cursor] = key;
                    self.buf_len += 1;
                    self.cursor += 1;
                    mq.post(.render);
                }
                return .consumed;
            },
        }
    }
};
