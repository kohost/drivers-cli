const std = @import("std");
const utils = @import("../../utils.zig");
const Color = @import("../../color.zig");
const ComponentInterface = @import("../component.zig").ComponentInterface;
const Binding = @import("../component.zig").Binding;
const Cursor = @import("../component.zig").Cursor;
const Frame = @import("../component.zig").Frame;
const KeyResult = @import("../component.zig").KeyResult;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;

pub const TextInput = struct {
    interface: ComponentInterface,
    source: []const u8,
    binding: ?Binding = null,
    buf: [128]u8 = undefined,
    buf_len: u8 = 0,
    cursor: u8 = 0,
    editing: bool = false,
    dirty: bool = false,

    pub fn init(source: []const u8) TextInput {
        return .{
            .interface = .{
                .write_fn = write,
                .handleKey_fn = handleKey,
            },
            .source = source,
        };
    }

    fn write(iface: *ComponentInterface, writer: *std.Io.Writer, cursor: *Cursor, frame: Frame) anyerror!void {
        const self: *TextInput = @fieldParentPtr("interface", iface);

        // Resolve optimistic state: once the model shows what we committed, stop overriding it.
        if (self.dirty and !self.editing) {
            var scratch: [128]u8 = undefined;
            if (std.mem.eql(u8, self.currentValue(&scratch), self.buf[0..self.buf_len])) self.dirty = false;
        }

        try utils.moveTo(writer, frame.x, frame.y);

        if (self.editing or self.dirty) {
            try writer.writeAll(Color.yellow);
            try writer.writeAll(self.buf[0..self.buf_len]);
        } else {
            try writer.writeAll(Color.text);
            if (self.binding) |b| try b.render(b.ctx, writer) else try writer.writeAll(self.source);
        }
        try writer.writeAll(Color.reset);

        if (self.editing) {
            cursor.x = frame.x + self.cursor;
            cursor.y = frame.y;
            cursor.visible = true;
        }
    }

    fn handleKey(iface: *ComponentInterface, key: u8, mq: *MessageQueue) KeyResult {
        const self: *TextInput = @fieldParentPtr("interface", iface);

        if (!self.editing) {
            switch (key) {
                'l', '\r', '\n' => {
                    const v = self.currentValue(&self.buf); // seed from live value
                    self.buf_len = @intCast(v.len);
                    self.cursor = self.buf_len;
                    self.editing = true;
                    mq.post(.render);
                    return .consumed;
                },
                else => return .ignored,
            }
        }

        switch (key) {
            0x1b => { // Esc — discard edit, drop optimistic value
                self.editing = false;
                self.dirty = false;
                mq.post(.render);
                return .consumed;
            },
            '\r', '\n' => { // Enter — commit; stay optimistic until model catches up
                self.editing = false;
                self.dirty = true;
                mq.post(.render);
                return .committed;
            },
            0x7f => { // Backspace
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

    fn currentValue(self: *TextInput, out: []u8) []const u8 {
        if (self.binding) |b| {
            var fw = std.Io.Writer.fixed(out);
            b.render(b.ctx, &fw) catch {};
            return out[0..fw.end];
        }
        const n = @min(self.source.len, out.len);
        @memcpy(out[0..n], self.source[0..n]);
        return out[0..n];
    }
};
