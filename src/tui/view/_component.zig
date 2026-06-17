//! Parked types still referenced during the Component migration.
//! `Style` (component styling) and `Binding` (pull-based value source) live
//! here until they find permanent homes.

const std = @import("std");
const Writer = std.Io.Writer;

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
};

/// A pull-based value source: pairs a type-erased context (e.g. a model
/// pointer) with a function that formats its current value to the writer.
pub const Binding = struct {
    ctx: *anyopaque,
    read: *const fn (*const anyopaque, *Writer) anyerror!void,
    write: ?*const fn (*anyopaque, []const u8) anyerror!void = null,
};
