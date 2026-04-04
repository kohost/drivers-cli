//! Component is an interface. It lets us treat any UI element the same way
//! without knowing its concrete type. The key insight: Component is two
//! pointers, one to the data and one to the behavior. Any struct can become
//! a Component by providing a vtable with its own write/handleKey functions.
//! It's how Zig does polymorphism without inheritance.

const std = @import("std");
const Writer = std.Io.Writer;
const MessageQueue = @import("../message_queue.zig").MessageQueue;

pub const Cursor = struct {
    x: u16 = 0,
    y: u16 = 0,
    visible: bool = false,
};

pub const KeyResult = enum {
    consumed,
    ignored,
    focus_next,
    focus_prev,
    open_search,
    dive_in,
    dive_out,
};

pub const Style = struct {
    color: []const u8 = "",
    secondary_color: []const u8 = "",
    tertiary_color: []const u8 = "",
    bg_color: []const u8 = "",
    secondary_bg_color: []const u8 = "",
    padding_left: u8 = 0,
    padding_right: u8 = 0,
};

pub const Component = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        write: *const fn (
            ptr: *anyopaque,
            writer: *Writer,
            x: u16,
            y: u16,
            w: u16,
            h: u16,
            cursor: *Cursor,
        ) anyerror!void,

        handleKey: *const fn (ptr: *anyopaque, key: u8, mq: *MessageQueue) KeyResult,
    };

    pub fn write(
        self: Component,
        writer: *Writer,
        x: u16,
        y: u16,
        w: u16,
        h: u16,
        cursor: *Cursor,
    ) !void {
        try self.vtable.write(self.ptr, writer, x, y, w, h, cursor);
    }

    pub fn handleKey(self: Component, key: u8, mq: *MessageQueue) KeyResult {
        return self.vtable.handleKey(self.ptr, key, mq);
    }
};
