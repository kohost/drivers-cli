const std = @import("std");
const utils = @import("../../utils.zig");
const Color = @import("../../color.zig");
const Component = @import("../Component.zig");
const Writer = std.Io.Writer;
const Cursor = @import("../../canvas.zig").Cursor;
const Frame = Component.Frame;
const KeyResult = @import("../../input.zig").KeyResult;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;
const Style = @import("../_component.zig").Style;

pub fn TextInput(comptime T: type) type {
    return struct {
        const Self = @This();
        source: *const T,
        vsource: *T,
        style: Style,
        buf: [128]u8 = undefined,
        buf_len: u8 = 0,
        cursor: u8 = 0,
        editing: bool = false,

        pub const Options = struct {
            style: Style = .{},
        };

        pub fn init(source: *const T, vsource: *T, opts: Options) Self {
            return .{ .source = source, .vsource = vsource, .style = opts.style };
        }

        pub fn component(self: *Self) Component {
            return .{ .ptr = self, .vtable = &.{
                .write = write,
                .handleKey = handleKey,
            } };
        }

        fn write(ptr: *anyopaque, w: *Writer, c: *Cursor, f: Frame) anyerror!void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            try utils.moveTo(w, f.x, f.y);

            if (self.editing) {
                try w.writeAll(Color.yellow);
                try w.writeAll(self.buf[0..self.buf_len]);
                try w.writeAll(Color.reset);
                c.x = f.x + self.cursor;
                c.y = f.y;
                c.visible = true;
                return;
            }

            try w.writeAll(if (self.isDirty()) Color.yellow else Color.text);
            try format(self.vsource.*, w);
            if (self.style.suffix.len > 0) {
                try w.writeAll(self.style.suffix);
            }
            try w.writeAll(Color.reset);
        }

        fn handleKey(ptr: *anyopaque, key: u8, mq: *MessageQueue) KeyResult {
            const self: *Self = @ptrCast(@alignCast(ptr));

            if (!self.editing) {
                switch (key) {
                    'l', '\r', '\n' => {
                        var fw = Writer.fixed(&self.buf);
                        format(self.vsource.*, &fw) catch {};
                        self.buf_len = @intCast(fw.end);
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
                    if (parse(self.buf[0..self.buf_len])) |v| self.vsource.* = v;
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

        fn format(v: T, w: *Writer) !void {
            switch (@typeInfo(T)) {
                .int, .float => try w.print("{d}", .{v}),
                .@"enum" => try w.writeAll(@tagName(v)),
                .pointer => try w.writeAll(v),
                else => @compileError("TextInput: unsupported type " ++ @typeName(T)),
            }
        }

        fn parse(text: []const u8) ?T {
            return switch (@typeInfo(T)) {
                .int => std.fmt.parseInt(T, text, 10) catch null,
                .float => std.fmt.parseFloat(T, text) catch null,
                .@"enum" => std.meta.stringToEnum(T, text),
                else => null,
            };
        }

        fn isDirty(self: *Self) bool {
            return self.source.* != self.vsource.*;
        }
    };
}
