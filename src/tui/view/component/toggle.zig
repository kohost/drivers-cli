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

pub const Display = struct {
    style: Style = .{
        .color = Color.green,
        .secondary_color = Color.red,
        .tertiary_color = Color.yellow,
    },
    active: []const u8 = "✔",
    inactive: []const u8 = "✗",
};

pub fn Toggle(comptime T: type) type {
    return struct {
        const Self = @This();
        vsource: *T,
        source: *const T,
        on: T,
        off: T,
        style: Style,
        active: []const u8,
        inactive: []const u8,

        const Options = struct {
            vsource: *T,
            source: *const T,
            on: T,
            off: T,
            display: Display = .{},
        };

        pub fn init(opts: Options) Self {
            return .{
                .vsource = opts.vsource,
                .source = opts.source,
                .on = opts.on,
                .off = opts.off,
                .style = opts.display.style,
                .active = opts.display.active,
                .inactive = opts.display.inactive,
            };
        }

        pub fn component(self: *Self) Component {
            return .{ .ptr = self, .vtable = &.{
                .write = write,
                .handleKey = handleKey,
                .handleMouse = handleMouse,
            } };
        }

        fn write(ptr: *anyopaque, w: *Writer, _: *Cursor, f: Frame, _: bool) anyerror!void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            try utils.moveTo(w, f.x, f.y);

            const active = self.isOn();
            const dirty = self.source.* != self.vsource.*;
            const color = if (dirty) self.style.tertiary_color else if (active) self.style.color else self.style.secondary_color;

            try w.writeAll(color);
            try w.writeAll(if (active) self.active else self.inactive);
            try w.writeAll(Color.reset);
        }

        fn handleKey(ptr: *anyopaque, key: u8, _: *MessageQueue) KeyResult {
            const self: *Self = @ptrCast(@alignCast(ptr));
            return switch (key) {
                'j' => .focus_next,
                'k' => .focus_prev,
                'l', '\r', '\n' => {
                    self.vsource.* = if (self.isOn()) self.off else self.on;
                    return .changed;
                },
                else => .ignored,
            };
        }

        pub fn handleMouse(ptr: *anyopaque, m: Mouse, mq: *MessageQueue) KeyResult {
            const self: *Self = @ptrCast(@alignCast(ptr));

            mq.post(.{ .update_pointer = utils.pointer_hand });

            if (m.press and !m.move) {
                self.vsource.* = if (self.isOn()) self.off else self.on;
                return .changed;
            }

            return .ignored;
        }

        fn isOn(self: *Self) bool {
            return self.vsource.* == self.on;
        }
    };
}
