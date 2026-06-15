const std = @import("std");
const Component = @import("../Component.zig");
const Writer = std.Io.Writer;
const Color = @import("../../color.zig");
const Cursor = @import("../../canvas.zig").Cursor;
const Frame = Component.Frame;
const KeyResult = @import("../../input.zig").KeyResult;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;
const Style = @import("../_component.zig").Style;
const utils = @import("../../utils.zig");

pub const Toggle = struct {
    const Self = @This();

    vsource: *?bool,
    source: *const ?bool,
    style: Style,
    active: []const u8,
    inactive: []const u8,

    const Options = struct {
        vsource: *?bool,
        source: *const ?bool,
        style: Style = .{
            .color = Color.green,
            .secondary_color = Color.red,
            .tertiary_color = Color.yellow,
        },
        active: []const u8 = "✔",
        inactive: []const u8 = "✗",
    };

    pub fn init(opts: Options) Self {
        return .{
            .vsource = opts.vsource,
            .source = opts.source,
            .style = opts.style,
            .active = opts.active,
            .inactive = opts.inactive,
        };
    }

    pub fn component(self: *Self) Component {
        return .{ .ptr = self, .vtable = &.{
            .write = write,
            .handleKey = handleKey,
        } };
    }

    fn write(ptr: *anyopaque, w: *Writer, _: *Cursor, f: Frame) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        try utils.moveTo(w, f.x, f.y);

        const active = self.vsource.*.?;
        const dirty = self.source.*.? != self.vsource.*.?;
        const color = if (dirty) self.style.tertiary_color else if (active) self.style.color else self.style.secondary_color;

        try w.writeAll(color);
        try w.writeAll(if (active) self.active else self.inactive);
        try w.writeAll(Color.reset);
    }

    fn handleKey(ptr: *anyopaque, key: u8, mq: *MessageQueue) KeyResult {
        const self: *Self = @ptrCast(@alignCast(ptr));
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
