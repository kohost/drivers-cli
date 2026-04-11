const std = @import("std");
const ComponentInterface = @import("../component.zig").ComponentInterface;
const Color = @import("../../color.zig");
const Cursor = @import("../component.zig").Cursor;
const Frame = @import("../component.zig").Frame;
const KeyResult = @import("../component.zig").KeyResult;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;
const Style = @import("../component.zig").Style;
const utils = @import("../../utils.zig");

pub const TextDisplay = struct {
    interface: ComponentInterface,
    source: []const u8,
    style: Style,

    pub fn init(source: []const u8, style: Style) TextDisplay {
        return .{ .interface = .{
            .write_fn = write,
            .handleKey_fn = handleKey,
        }, .source = source, .style = style };
    }

    fn write(
        interface: *ComponentInterface,
        writer: *std.Io.Writer,
        cursor: *Cursor,
        frame: Frame,
    ) anyerror!void {
        const self: *TextDisplay = @fieldParentPtr("interface", interface);
        _ = cursor;

        try utils.moveTo(writer, frame.x, frame.y);
        try writer.writeAll(self.style.bg_color);
        try writer.writeAll(self.style.color);
        for (0..self.style.padding_left -| 0) |_| try writer.writeAll(" ");
        try writer.writeAll(if (self.source.len > 0) self.source else "-");
        try writer.writeAll(Color.reset);
    }

    fn handleKey(_: *ComponentInterface, _: u8, _: *MessageQueue) KeyResult {
        return .ignored;
    }
};
