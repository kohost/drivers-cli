const std = @import("std");
const ComponentInterface = @import("../component.zig").ComponentInterface;
const Binding = @import("../component.zig").Binding;
const Color = @import("../../color.zig");
const Cursor = @import("../component.zig").Cursor;
const Frame = @import("../component.zig").Frame;
const KeyResult = @import("../component.zig").KeyResult;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;
// const Style = @import("../component.zig").Style;
const utils = @import("../../utils.zig");

/// A single-line value cell with only '✔' or '✗'
pub const Boolean = struct {
    interface: ComponentInterface,
    source: bool,
    binding: ?Binding = null,
    // style: Style,

    pub fn init(source: bool) Boolean {
        return .{ .interface = .{
            .write_fn = write,
            .handleKey_fn = handleKey,
        }, .source = source };
    }

    fn write(
        interface: *ComponentInterface,
        writer: *std.Io.Writer,
        _: *Cursor,
        frame: Frame,
    ) anyerror!void {
        const self: *Boolean = @fieldParentPtr("interface", interface);

        try utils.moveTo(writer, frame.x, frame.y);
        // try writer.writeAll(self.style.bg_color);
        // try writer.writeAll(self.style.color);
        // for (0..self.style.padding_left) |_| try writer.writeAll(" ");
        // if (self.binding) |b| try b.render(b.ctx, writer) else try writer.writeAll(self.source);
        if (self.binding) |b| {
            try b.render(b.ctx, writer);
        } else {
            try writer.writeAll(if (self.source) Color.green ++ "✔" else Color.red ++ "✗");
        }
        try writer.writeAll(Color.reset);
    }

    fn handleKey(_: *ComponentInterface, key: u8, _: *MessageQueue) KeyResult {
        return switch (key) {
            'j' => .focus_next,
            'k' => .focus_prev,
            'l', '\r', '\n' => {
                return .ignored;
            },
            else => .ignored,
        };
    }
};
