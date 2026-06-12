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
    source: ?Binding = null,
    vsource: ?Binding = null,
    buf: [128]u8 = undefined,
    buf_len: u8 = 0,
    cursor: u8 = 0,
    editing: bool = false,

    pub fn init() TextInput {
        return .{
            .interface = .{
                .write_fn = write,
                .handleKey_fn = handleKey,
            },
        };
    }

    fn write(iface: *ComponentInterface, writer: *std.Io.Writer, cursor: *Cursor, frame: Frame) anyerror!void {
        const self: *TextInput = @fieldParentPtr("interface", iface);
        try utils.moveTo(writer, frame.x, frame.y);

        if (self.editing) {
            try writer.writeAll(Color.yellow);
            try writer.writeAll(self.buf[0..self.buf_len]);
            try writer.writeAll(Color.reset);
            cursor.x = frame.x + self.cursor;
            cursor.y = frame.y;
            cursor.visible = true;
            return;
        }

        try writer.writeAll(if (self.isDirty()) Color.yellow else Color.text);
        if (self.vsource) |b| try b.read(b.ctx, writer);
        try writer.writeAll(Color.reset);
    }

    /// Since this component is generic and will work on multiple types like
    /// []const u8, enums, floats, integers we convert everything into text
    /// and compare the strings.
    fn isDirty(self: *TextInput) bool {
        const v = self.vsource orelse return false;
        const s = self.source orelse return false;
        var va: [128]u8 = undefined;
        var sa: [128]u8 = undefined;
        var vw = std.Io.Writer.fixed(&va);
        var sw = std.Io.Writer.fixed(&sa);

        v.read(v.ctx, &vw) catch return false;
        s.read(s.ctx, &sw) catch return false;
        return !std.mem.eql(u8, va[0..vw.end], sa[0..sw.end]);
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
            0x1b => { // Esc: discard
                self.editing = false;
                mq.post(.render);
                return .consumed;
            },
            '\r', '\n' => { // Enter — commit; stay optimistic until model catches up
                self.editing = false;
                if (self.vsource) |b| {
                    if (b.write) |w| w(b.ctx, self.buf[0..self.buf_len]) catch {};
                }
                mq.post(.render);
                return .changed;
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
        const b = self.vsource orelse return out[0..0];
        var fw = std.Io.Writer.fixed(out);
        b.read(b.ctx, &fw) catch {};
        return out[0..fw.end];
    }
};
