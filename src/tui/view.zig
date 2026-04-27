const std = @import("std");
const DriverView = @import("view/driver.zig").DriverView;
const comp = @import("view/component.zig");
const KeyResult = comp.KeyResult;
const Cursor = comp.Cursor;
const MessageQueue = @import("message_queue.zig").MessageQueue;

pub const View = union(enum) {
    driver: DriverView,
    none,

    pub fn deinit(self: *View) void {
        switch (self.*) {
            .driver => |*v| v.deinit(),
            .none => {},
        }
    }

    pub fn write(self: *View, writer: *std.Io.Writer, cursor: *Cursor) !void {
        switch (self.*) {
            .driver => |*v| try v.write(writer, cursor),
            .none => {},
        }
    }

    pub fn handleKey(self: *View, key: u8, mq: *MessageQueue) KeyResult {
        return switch (self.*) {
            .driver => |*v| v.handleKey(key, mq),
            .none => .ignored,
        };
    }

    pub fn focus(self: *View) void {
        switch (self.*) {
            .driver => |*v| v.focus(),
            .none => {},
        }
    }

    pub fn blur(self: *View) void {
        switch (self.*) {
            .driver => |*v| v.blur(),
            .none => {},
        }
    }

    pub fn setFilter(self: *View, filter: []const u8) void {
        switch (self.*) {
            .driver => |*v| v.setFilter(filter),
            .none => {},
        }
    }

    pub fn getFilter(self: *const View) []const u8 {
        return switch (self.*) {
            .driver => |*v| v.getFilter(),
            .none => "",
        };
    }

    pub fn setRequest(self: *View, text: []const u8) !void {
        switch (self.*) {
            .driver => |*v| try v.setRequest(text),
            .none => {},
        }
    }

    pub fn setResponse(self: *View, text: []const u8) !void {
        switch (self.*) {
            .driver => |*v| try v.setResponse(text),
            .none => {},
        }
    }
};
