const std = @import("std");

pub const Token = struct {
    len: usize, // how many bytes this sequence occupies
    action: union(enum) {
        mouse: Mouse,
        key: u8,
        none,
    },

    pub fn format(self: Token, w: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self.action) {
            .key => |k| switch (k) {
                0x0a, 0x0d => try w.writeAll("return"),
                0x1b => try w.writeAll("esc"),
                else => try w.print("{c}", .{k}),
            },
            .mouse => |m| try w.print("{any}", .{m}),
            .none => try w.writeAll("none"),
        }
    }
};
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

pub const MouseBtn = enum { left, middle, right, none, wheel_up, wheel_down, other };
pub const Mouse = struct {
    x: u16,
    y: u16,
    btn: MouseBtn,
    press: bool,
    move: bool,
};

fn parseMouse(s: []const u8) ?Mouse {
    if (s.len < 2 or s[0] != '[' or s[1] != '<') return null;

    const end = s[s.len - 1];
    if (end != 'M' and end != 'm') return null;

    var it = std.mem.splitScalar(u8, s[2 .. s.len - 1], ';'); // strip "[<" and end
    const cb = std.fmt.parseInt(u16, it.next() orelse return null, 10) catch return null;
    const cx = std.fmt.parseInt(u16, it.next() orelse return null, 10) catch return null;
    const cy = std.fmt.parseInt(u16, it.next() orelse return null, 10) catch return null;
    const move = (cb & 0b11000011) != 0; // 0x20 = motion flag
    const btn: MouseBtn = switch (cb & 0b11000011) {
        0 => .left,
        1 => .middle,
        2 => .right,
        3 => .none,
        64 => .wheel_up,
        65 => .wheel_down,
        else => .other,
    };
    return .{ .x = cx, .y = cy, .press = end == 'M', .move = move, .btn = btn };
}

pub fn parseInput(in: []const u8) ?Token {
    if (in[0] != 0x1b) {
        return .{ .len = 1, .action = .{ .key = in[0] } };
    }

    if (in.len < 2) return null; // just ESC so far
    if (in[1] != '[') return .{ .len = 1, .action = .{ .key = 0x1b } }; // bare ESC key
    if (in.len < 3) return null; // "" incomplete

    // SGR mouse: ESC [ < Cb ; Cx ; Cy (M|m)
    if (in[2] == '<') {
        const end = std.mem.indexOfAnyPos(u8, in, 3, "Mm") orelse return null; // no terminator yet
        const consumed = end + 1;
        const m = parseMouse(in[1..consumed]) orelse return .{ .len = consumed, .action = .none };
        return .{ .len = consumed, .action = .{ .mouse = m } };
    }

    // Arrows: ESC [ A/B/C/D
    const key: u8 = switch (in[2]) {
        'A' => 'k',
        'B' => 'j',
        'C' => 'l',
        'D' => 'h',
        else => return .{ .len = 3, .action = .none },
    };

    return .{ .len = 3, .action = .{ .key = key } };
}
