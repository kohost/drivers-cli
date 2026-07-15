const std = @import("std");
const Component = @import("../Component.zig");
const Writer = std.Io.Writer;
const Color = @import("../../color.zig");
const Cursor = @import("../../canvas.zig").Cursor;
const Frame = Component.Frame;
const KeyResult = @import("../../input.zig").KeyResult;
const Mouse = @import("../../input.zig").Mouse;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;
const Style = @import("../_component.zig").Style;
const utils = @import("../../utils.zig");

pub fn TextDisplay(comptime T: type) type {
    return struct {
        const Self = @This();

        source: *const T,
        style: Style,
        frame: Frame = .{},
        invert: bool = false,

        pub const Options = struct {
            style: Style = .{ .color = Color.overlay2 },
            invert: bool = false,
        };

        pub fn init(source: *const T, opts: Options) Self {
            return .{ .source = source, .style = opts.style, .invert = opts.invert };
        }

        pub fn component(self: *Self) Component {
            return .{ .ptr = self, .vtable = &.{
                .write = write,
                .handleKey = handleKey,
                .handleMouse = handleMouse,
            } };
        }

        pub fn handleMouse(_: *anyopaque, _: Mouse, mq: *MessageQueue) KeyResult {
            mq.post(.{ .update_pointer = utils.pointer_default });

            return .ignored;
        }

        fn write(ptr: *anyopaque, w: *Writer, _: *Cursor, f: Frame, _: bool) anyerror!void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            self.frame = f;
            try utils.moveTo(w, f.x, f.y);

            try w.writeAll(self.style.bg_color);
            try w.writeAll(self.style.color);
            for (0..self.style.padding_left) |_| try w.writeAll(" ");
            if (T == bool) {
                if (self.invert) try format(T, !self.source.*, w) else try format(T, self.source.*, w);
            } else {
                try format(T, self.source.*, w);
            }
            if (self.style.suffix.len > 0) {
                try w.writeAll(self.style.suffix);
            }
            try w.writeAll(Color.reset);
        }

        fn handleKey(_: *anyopaque, key: u8, _: *MessageQueue) KeyResult {
            return switch (key) {
                'j' => .focus_next,
                'k' => .focus_prev,
                else => .ignored,
            };
        }

        /// Render a value of any T to text, resolved at compile time.
        /// Optionals print their child or "-" when null; empty strings print "-".
        fn format(comptime U: type, v: U, w: *Writer) anyerror!void {
            switch (@typeInfo(U)) {
                .optional => |o| if (v) |inner| try format(o.child, inner, w) else try w.writeAll("-"),
                .pointer => |p| if (p.child == u8)
                    try w.writeAll(if (v.len == 0) "-" else v)
                else switch (@typeInfo(p.child)) {
                    .@"enum" => for (v, 0..) |e, i| {
                        if (i > 0) try w.writeAll(", ");
                        try w.writeAll(@tagName(e));
                    },
                    else => @compileError("TextDisplay: unsupported slice element " ++ @typeName(p.child)),
                },
                .@"enum" => try w.writeAll(@tagName(v)),
                .int, .comptime_int, .float, .comptime_float => try w.print("{d}", .{v}),
                .bool => try w.writeAll(if (v) Color.green ++ "✔" else Color.red ++ "✗"),
                else => @compileError("TextDisplay: unsupported type " ++ @typeName(U)),
            }
        }
    };
}
