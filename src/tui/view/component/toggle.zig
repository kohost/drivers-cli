const std = @import("std");
const ComponentInterface = @import("../component.zig").ComponentInterface;
const Color = @import("../../color.zig");
const Cursor = @import("../component.zig").Cursor;
const Frame = @import("../component.zig").Frame;
const KeyResult = @import("../component.zig").KeyResult;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;
const Style = @import("../component.zig").Style;
const utils = @import("../../utils.zig");

pub const Toggle = struct {
    interface: ComponentInterface,
    vsource: *?bool, // mutable: points at a vstate field
    source: *const ?bool, // mutable: points at a vstate field
    active: []const u8 = "✔",
    inactive: []const u8 = "☓",
    style: Style,

    pub fn init(vsource: *?bool, source: *const ?bool, style: Style, active: []const u8, inactive: []const u8) Toggle {
        return .{ .active = active, .inactive = inactive, .interface = .{
            .write_fn = write,
            .handleKey_fn = handleKey,
        }, .vsource = vsource, .source = source, .style = style };
    }

    fn write(
        interface: *ComponentInterface,
        writer: *std.Io.Writer,
        _: *Cursor,
        frame: Frame,
    ) anyerror!void {
        const self: *Toggle = @fieldParentPtr("interface", interface);
        try utils.moveTo(writer, frame.x, frame.y);

        const active = self.vsource.*.?;
        const dirty = self.source.*.? != self.vsource.*.?;
        const color = if (dirty) self.style.tertiary_color else if (active) self.style.color else self.style.secondary_color;

        try writer.writeAll(color);
        try writer.writeAll(if (active) self.active else self.inactive);
        try writer.writeAll(Color.reset);
    }

    fn handleKey(interface: *ComponentInterface, key: u8, mq: *MessageQueue) KeyResult {
        const self: *Toggle = @fieldParentPtr("interface", interface);
        return switch (key) {
            'j' => .focus_next,
            'k' => .focus_prev,
            'l', '\r', '\n' => {
                self.vsource.* = !self.vsource.*.?;
                mq.post(.render);
                return .changed;
            },
            else => .ignored,
        };
    }
};
