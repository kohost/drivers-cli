const std = @import("std");

// ============================================================================
// Escape sequences
// ============================================================================

pub const clear_screen = "\x1b[2J";
pub const cursor_home = "\x1b[H";
pub const clear_line = "\x1b[K";
pub const mouse_on = sm(.mouse_all) ++ sm(.mouse_sgr);
pub const mouse_off = rm(.mouse_sgr) ++ rm(.mouse_all);
pub const pointer_hand = "\x1b]22;pointer\x1b\\";
pub const pointer_default = "\x1b]22;default\x1b\\";

// Digital Equipment Corporation - the company that made the VT100/VT220 terminals
// in the late 1970s-80s. Those terminals defined the esc sequences that every
// modern terminal emulator still emulates.
pub const DecPrivateMode = enum(u16) {
    alt_screen = 1049,
    cursor = 25,
    mouse_click = 1000,
    mouse_drag = 1002,
    mouse_all = 1003,
    mouse_sgr = 1006,
};
pub fn sm(comptime m: DecPrivateMode) []const u8 {
    return std.fmt.comptimePrint("\x1b[?{d}h", .{@intFromEnum(m)});
}
pub fn rm(comptime m: DecPrivateMode) []const u8 {
    return std.fmt.comptimePrint("\x1b[?{d}l", .{@intFromEnum(m)});
}

pub const CursorStyle = enum(u8) {
    blink_block = 1,
    steady_block = 2,
    blink_underline = 3,
    steady_underline = 4,
    blink_bar = 5,
    steady_bar = 6,
};
pub fn cursorStyle(comptime s: CursorStyle) []const u8 {
    return std.fmt.comptimePrint("\x1b[{d} q", .{@intFromEnum(s)});
}

// Writes an ANSI cursor positioning sequence (CUP) to  move the terminal
// cursor to a given col/row.
pub fn moveTo(writer: *std.Io.Writer, x: u16, y: u16) !void {
    var buf: [32]u8 = undefined;
    const cmd = std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ y, x }) catch return;
    try writer.writeAll(cmd);
}

// ============================================================================
// Utility helpers
// ============================================================================

// Returns the number of terminal columns a string will visually occupy a u16 count
// of cells, not bytes.
//
// It exists because text.len (byte count) lies about visual width in two ways, and this function
// corrects both:
//
// 1. ANSI escape sequences take zero columns. A color code like \x1b[33m is 5 bytes but prints
// nothing. The function detects \x1b[, then skips forward until it passes the terminating m,
// counting none of it:
//
// if (text[i] == 0x1b and i + 1 < text.len and text[i + 1] == '[') {
//     i += 2;
//     while (i < text.len and text[i] != 'm') : (i += 1) {}
//     if (i < text.len) i += 1; // skip 'm'
//     continue;
// }
//
// 2. UTF-8 characters are multiple bytes but usually one column. It inspects the leading byte to
// decode the character's byte length and assign a column width:
//
//  ┌──────────────┬───────────────────┬───────────────┐
//  │ Leading byte │   UTF-8 length    │ Columns added │
//  ├──────────────┼───────────────────┼───────────────┤
//  │ < 0x80       │ 1 (ASCII)         │ 1             │
//  ├──────────────┼───────────────────┼───────────────┤
//  │ 0x80–0xBF    │ continuation byte │ 0 (skipped)   │
//  ├──────────────┼───────────────────┼───────────────┤
//  │ 0xC0–0xDF    │ 2                 │ 1             │
//  ├──────────────┼───────────────────┼───────────────┤
//  │ 0xE0–0xEF    │ 3                 │ 1             │
//  ├──────────────┼───────────────────┼───────────────┤
//  │ ≥ 0xF0       │ 4                 │ 2             │
//  └──────────────┴───────────────────┴───────────────┘
//
// So a 3-byte glyph like \u{f2c9} (thermometer) counts as 1 column despite being 3 bytes; a
// 4 byte character counts as 2 (the heuristic that most 4 byte/astral characters emoji, CJK
// are double-width).
pub fn displayWidth(text: []const u8) u16 {
    var width: u16 = 0;
    var i: usize = 0;
    while (i < text.len) {
        // Skip ANSI escape sequences
        if (text[i] == 0x1b and i + 1 < text.len and text[i + 1] == '[') {
            i += 2;
            while (i < text.len and text[i] != 'm') : (i += 1) {}
            if (i < text.len) i += 1; // skip 'm'
            continue;
        }
        const byte = text[i];
        if (byte < 0x80) {
            width += 1;
            i += 1;
        } else if (byte < 0xC0) {
            i += 1;
        } else if (byte < 0xE0) {
            width += 1;
            i += 2;
        } else if (byte < 0xF0) {
            width += 1;
            i += 3;
        } else {
            // 4-byte UTF-8. Nerd Font glyphs live in the Supplementary Private
            // Use Areas and render single-width; emoji (also 4-byte) are double-width.
            const cp = if (i + 4 <= text.len) std.unicode.utf8Decode(text[i .. i + 4]) catch 0 else 0;
            const nerd_pua = (cp >= 0xF0000 and cp <= 0xFFFFD) or (cp >= 0x100000 and cp <= 0x10FFFD);
            width += if (nerd_pua) 1 else 2;
            i += 4;
        }
    }
    return width;
}
