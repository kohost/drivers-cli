const std = @import("std");

pub const KeyResult = enum {
    // generic handled
    consumed,

    // user finalized an editable value (e.g. Enter in TextInput) — mirrors the DOM change event
    changed,

    ignored,
    focus_next,
    focus_prev,
    open_search,
    dive_in,
    dive_out,
};

pub const MouseBtn = enum { left, middle, right, wheel_up, wheel_down, other };
pub const Mouse = struct {
    x: u16,
    y: u16,
    btn: MouseBtn,
    press: bool,
};
pub fn parseMouse(s: []const u8) ?Mouse {
    if (s.len < 2 or s[0] != '[' or s[1] != '<') return null;

    const end = s[s.len - 1];
    if (end != 'M' and end != 'm') return null;

    var it = std.mem.splitScalar(u8, s[2 .. s.len - 1], ';'); // strip "[<" and end
    const cb = std.fmt.parseInt(u16, it.next() orelse return null, 10) catch return null;
    const cx = std.fmt.parseInt(u16, it.next() orelse return null, 10) catch return null;
    const cy = std.fmt.parseInt(u16, it.next() orelse return null, 10) catch return null;

    return .{ .x = cx, .y = cy, .press = end == 'M', .btn = switch (cb & 0b11000011) {
        0 => .left,
        1 => .middle,
        2 => .right,
        64 => .wheel_up,
        65 => .wheel_down,
        else => .other,
    } };
}
