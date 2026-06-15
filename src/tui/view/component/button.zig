const std = @import("std");
const Color = @import("../../color.zig");
const utils = @import("../../utils.zig");
const Component = @import("../Component.zig");
const Writer = std.Io.Writer;
const Frame = Component.Frame;
const Cursor = @import("../../canvas.zig").Cursor;
const KeyResult = @import("../../input.zig").KeyResult;
const Style = @import("../_component.zig").Style;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;

pub const Button = struct {
    const Self = @This();

    label: []const u8,
    focused: bool,
    style: Style,

    pub fn init(label: []const u8, style: Style) Button {
        return .{
            .label = label,
            .style = style,
            .focused = false,
        };
    }

    pub fn component(self: *Self) Component {
        return .{ .ptr = self, .vtable = &.{
            .write = write,
            .handleKey = handleKey,
        } };
    }

    pub fn write(ptr: *anyopaque, writer: *Writer, cursor: *Cursor, frame: Frame) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        _ = cursor;

        var color = if (self.style.color.len > 0) self.style.color else Color.text;
        var bg_color = if (self.style.bg_color.len > 0) self.style.bg_color else Color.bg_overlay0;

        if (self.focused) {
            bg_color = Color.bg_lavender_dark;
            color = Color.lavender;
        }

        try utils.moveTo(writer, frame.x, frame.y);
        try writer.writeAll(bg_color);
        try writer.writeAll(color);
        if (self.focused) try writer.writeAll("▎") else try writer.writeAll(" ");
        try writer.writeAll(self.label);
        try writer.writeAll(" ");
        try writer.writeAll(Color.reset);
    }

    pub fn handleKey(ptr: *anyopaque, key: u8, mq: *MessageQueue) KeyResult {
        const self: *Self = @ptrCast(@alignCast(ptr));
        _ = self;

        switch (key) {
            'j' => {},
            'k' => {},
            '\r', '\n', 'l' => {
                mq.post(.send_command);
                return .consumed;
            },
            0x1b, 'h' => {},
            else => return .ignored,
        }
        return .ignored;
    }
};
