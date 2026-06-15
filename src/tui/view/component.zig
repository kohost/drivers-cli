const std = @import("std");
const Writer = std.Io.Writer;
const MessageQueue = @import("../message_queue.zig").MessageQueue;
const KeyResult = @import("../input.zig").KeyResult;
const Cursor = @import("../canvas.zig").Cursor;
const Component = @This();

pub const Frame = struct {
    x: u16 = 0,
    y: u16 = 0,
    w: u16 = 0,
    h: u16 = 0,
};

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    write: *const fn (*anyopaque, w: *Writer, c: *Cursor, f: Frame) anyerror!void,
    handleKey: *const fn (*anyopaque, k: u8, mq: *MessageQueue) KeyResult,
};

pub fn write(self: Component, w: *Writer, c: *Cursor, f: Frame) !void {
    try self.vtable.write(self.ptr, w, c, f);
}

pub fn handleKey(self: Component, key: u8, mq: *MessageQueue) KeyResult {
    return self.vtable.handleKey(self.ptr, key, mq);
}

