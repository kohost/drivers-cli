const std = @import("std");
const Color = @import("../../color.zig");
const icons = @import("../../icons.zig");
const utils = @import("../../utils.zig");
const Component = @import("../component.zig").Component;
const Cursor = @import("../component.zig").Cursor;
const KeyResult = @import("../component.zig").KeyResult;
const Style = @import("../component.zig").Style;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;

pub const Button = struct {
    label: []const u8,
    focused: bool,
    style: Style,

    pub fn init(label: []const u8, style: Style) Button {
        return .{
            .label = label,
            .focused = false,
            .style = style,
        };
    }

    pub fn component(self: *Button) Component {
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
        _: *Cursor,
    ) anyerror!void {
        const self: *Button = @ptrCast(@alignCast(ptr));
        _ = w;
        _ = h;

        const color = if (self.style.color.len > 0) self.style.color else Color.text;
        // const secondary_color = if (self.style.secondary_color > 0) self.style.secondary_color else Color.subtext1;
        const bg_color = if (self.style.bg_color.len > 0) self.style.bg_color else Color.bg_overlay0;
        // const bg_secondary_color = if (self.style.secondary_bg_color.len > 0) self.style.secondary_bg_color else Color.bg_overlay1;

        try utils.moveTo(writer, x, y);
        try writer.writeAll(bg_color);
        try writer.writeAll(color);
        try writer.writeAll(" ");
        try writer.writeAll(self.label);
        try writer.writeAll(" ");
        try writer.writeAll(Color.reset);
    }

    pub fn handleKey(ptr: *anyopaque, key: u8, mq: *MessageQueue) KeyResult {
        const self: *Button = @ptrCast(@alignCast(ptr));
        _ = self;

        switch (key) {
            'j' => {},
            'k' => {},
            '\r', '\n', 'l' => {
                mq.post(.render);
            },
            0x1b, 'h' => {},
            else => return .ignored,
        }
        return .ignored;
    }
};
