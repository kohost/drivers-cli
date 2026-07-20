const std = @import("std");
const Writer = std.Io.Writer;
const MessageQueue = @import("../message_queue.zig").MessageQueue;
const KeyResult = @import("../input.zig").KeyResult;
const Mouse = @import("../input.zig").Mouse;
const Cursor = @import("../canvas.zig").Cursor;
const Component = @This();

pub const Frame = struct {
    x: u16 = 0,
    y: u16 = 0,
    w: u16 = 0,
    h: u16 = 0,

    pub fn contains(f: Frame, x: u16, y: u16) bool {
        return x >= f.x and x < f.x + f.w and y >= f.y and y < f.y + f.h;
    }
};

pub const Style = struct {
    color: []const u8 = "",
    secondary_color: []const u8 = "",
    tertiary_color: []const u8 = "",
    bg_color: []const u8 = "",
    secondary_bg_color: []const u8 = "",
    padding_left: u8 = 0,
    padding_right: u8 = 0,
    prefix: []const u8 = "",
    suffix: []const u8 = "",
    focus_marker: bool = true,
};

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    write: *const fn (*anyopaque, w: *Writer, c: *Cursor, f: Frame, focused: bool) anyerror!void,
    handleKey: *const fn (*anyopaque, k: u8, mq: *MessageQueue) KeyResult,
    handleMouse: *const fn (*anyopaque, m: Mouse, mq: *MessageQueue) KeyResult,
};

pub fn write(self: Component, w: *Writer, c: *Cursor, f: Frame, focused: bool) !void {
    try self.vtable.write(self.ptr, w, c, f, focused);
}

pub fn handleKey(self: Component, key: u8, mq: *MessageQueue) KeyResult {
    return self.vtable.handleKey(self.ptr, key, mq);
}

pub fn handleMouse(self: Component, m: Mouse, mq: *MessageQueue) KeyResult {
    return self.vtable.handleMouse(self.ptr, m, mq);
}
