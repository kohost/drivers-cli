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
    consumed, // generic handled
    committed, // user finalized an editable value (e.g. Enter in TextInput)
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

pub const Frame = struct {
    x: u16 = 0,
    y: u16 = 0,
    w: u16 = 0,
    h: u16 = 0,
};

/// A pull-based value source: pairs a type-erased context (e.g. a model
/// pointer) with a function that renders its current value to the writer.
pub const Binding = struct {
    ctx: *const anyopaque,
    render: *const fn (*const anyopaque, *Writer) anyerror!void,
};

pub const ComponentInterface = struct {
    write_fn: *const fn (*ComponentInterface, *Writer, *Cursor, Frame) anyerror!void,
    handleKey_fn: *const fn (*ComponentInterface, u8, *MessageQueue) KeyResult,

    pub fn write(self: *ComponentInterface, writer: *Writer, cursor: *Cursor, frame: Frame) !void {
        try self.write_fn(self, writer, cursor, frame);
    }

    pub fn handleKey(self: *ComponentInterface, key: u8, mq: *MessageQueue) KeyResult {
        return self.handleKey_fn(self, key, mq);
    }
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
