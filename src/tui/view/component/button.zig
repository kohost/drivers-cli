const std = @import("std");
const Color = @import("../../color.zig");
const utils = @import("../../utils.zig");
const Component = @import("../Component.zig");
const Writer = std.Io.Writer;
const Frame = Component.Frame;
const Cursor = @import("../../canvas.zig").Cursor;
const KeyResult = @import("../../input.zig").KeyResult;
const Mouse = @import("../../input.zig").Mouse;
const Style = @import("../_component.zig").Style;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;

pub const Button = struct {
    const Self = @This();

    label: []const u8,
    style: Style,
    frame: Frame = .{},
    pressed: bool = false,
    // on_click: ?Message = null,
    // on_hover: ?Message = null,

    pub fn init(label: []const u8, style: Style) Button {
        return .{
            .label = label,
            .style = style,
        };
    }

    pub fn component(self: *Self) Component {
        return .{ .ptr = self, .vtable = &.{
            .write = write,
            .handleKey = handleKey,
            .handleMouse = handleMouse,
        } };
    }

    pub fn write(ptr: *anyopaque, w: *Writer, c: *Cursor, f: Frame, focused: bool) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.frame = f;
        _ = c;

        var color = if (self.style.color.len > 0) self.style.color else Color.text;
        var bg_color = if (self.style.bg_color.len > 0) self.style.bg_color else Color.bg_overlay0;

        if (focused or self.pressed) {
            bg_color = Color.bg_lavender_dark;
            color = Color.lavender;
        }

        try utils.moveTo(w, f.x, f.y);
        try w.writeAll(bg_color);
        try w.writeAll(color);
        if (focused) try w.writeAll("▎") else try w.writeAll(" ");
        try w.writeAll(self.label);
        try w.writeAll(" ");
        try w.writeAll(Color.reset);
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

    pub fn handleMouse(ptr: *anyopaque, m: Mouse, mq: *MessageQueue) KeyResult {
        const self: *Self = @ptrCast(@alignCast(ptr));

        mq.post(.{ .update_pointer = utils.pointer_hand });

        if (m.press and !m.move) {
            mq.post(.send_command);
            self.pressed = true;
        }
        if (!m.press and !m.move) self.pressed = false;

        return .consumed;
    }
};
