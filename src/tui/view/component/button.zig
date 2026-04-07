const std = @import("std");
const Color = @import("../../color.zig");
const utils = @import("../../utils.zig");
const ComponentInterface = @import("../component.zig").ComponentInterface;
const Frame = @import("../component.zig").Frame;
const Cursor = @import("../component.zig").Cursor;
const KeyResult = @import("../component.zig").KeyResult;
const Style = @import("../component.zig").Style;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;

pub const Button = struct {
    interface: ComponentInterface,
    label: []const u8,
    focused: bool,
    style: Style,

    pub fn init(label: []const u8, style: Style) Button {
        return .{
            .interface = .{
                .write_fn = write,
                .handleKey_fn = handleKey,
            },
            .label = label,
            .style = style,
            .focused = false,
        };
    }

    pub fn write(
        interface: *ComponentInterface,
        writer: *std.Io.Writer,
        cursor: *Cursor,
        frame: Frame,
    ) anyerror!void {
        const self: *Button = @fieldParentPtr("interface", interface);
        _ = cursor;

        const color = if (self.style.color.len > 0) self.style.color else Color.text;
        const bg_color = if (self.style.bg_color.len > 0) self.style.bg_color else Color.bg_overlay0;

        try utils.moveTo(writer, frame.x, frame.y);
        try writer.writeAll(bg_color);
        try writer.writeAll(color);
        try writer.writeAll(" ");
        try writer.writeAll(self.label);
        try writer.writeAll(" ");
        try writer.writeAll(Color.reset);
    }

    pub fn handleKey(interface: *ComponentInterface, key: u8, mq: *MessageQueue) KeyResult {
        const self: *Button = @fieldParentPtr("interface", interface);
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
