const std = @import("std");
const Component = @import("../component.zig").Component;
const Cursor = @import("../component.zig").Cursor;
const KeyResult = @import("../component.zig").KeyResult;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;
const utils = @import("../../utils.zig");

pub const TextDisplay = struct {
    source: []const u8,

    pub fn init(source: []const u8) TextDisplay {
        return .{ .source = source };
    }

    pub fn component(self: *TextDisplay) Component {
        return .{ .ptr = @ptrCast(self), .vtable = &.{
            .write = write,
            .handleKey = handleKey,
        } };
    }

    fn write(
        ptr: *anyopaque,
        writer: *std.Io.Writer,
        x: u16,
        y: u16,
        w: u16,
        h: u16,
        _: *Cursor,
    ) anyerror!void {
        const self: *const TextDisplay = @ptrCast(@alignCast(ptr));
        _ = w;
        _ = h;
        try utils.moveTo(writer, x, y);
        try writer.writeAll(if (self.source.len > 0) self.source else "-");
    }

    fn handleKey(_: *anyopaque, _: u8, _: *MessageQueue) KeyResult {
        return .ignored;
    }
};
