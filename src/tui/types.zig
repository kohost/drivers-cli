const std = @import("std");

pub const Mode = enum { normal, command };
pub const Rect = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
};
pub const KeyResult = union(enum) {
    consumed,
    move_to: enum { up, down },
    command: []const u8,
    unhandled,
};
pub const Data = union(enum) { json: std.json.Parsed(std.json.Value), err: []const u8 };
