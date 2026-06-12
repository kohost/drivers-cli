const std = @import("std");
const ComponentInterface = @import("../component.zig").ComponentInterface;
const Binding = @import("../component.zig").Binding;
const Color = @import("../../color.zig");
const Cursor = @import("../component.zig").Cursor;
const Frame = @import("../component.zig").Frame;
const KeyResult = @import("../component.zig").KeyResult;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;
const Style = @import("../component.zig").Style;
const utils = @import("../../utils.zig");

/// A single-line value cell. Renders from a pull `binding` (live model value)
/// when set, otherwise from the static `source`. For scrollable multi-line
/// content use Viewport.
pub const TextDisplay = struct {
    interface: ComponentInterface,
    source: []const u8,
    binding: ?Binding = null,
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
        _: *Cursor,
        frame: Frame,
    ) anyerror!void {
        const self: *TextDisplay = @fieldParentPtr("interface", interface);

        try utils.moveTo(writer, frame.x, frame.y);
        try writer.writeAll(self.style.bg_color);
        try writer.writeAll(self.style.color);
        for (0..self.style.padding_left) |_| try writer.writeAll(" ");
        if (self.binding) |b| try b.read(b.ctx, writer) else try writer.writeAll(self.source);
        try writer.writeAll(Color.reset);
    }

    fn handleKey(_: *ComponentInterface, key: u8, _: *MessageQueue) KeyResult {
        return switch (key) {
            'j' => .focus_next,
            'k' => .focus_prev,
            else => .ignored,
        };
    }
};
