const std = @import("std");
const icons = @import("icons.zig");

pub fn intToStr(buf: []u8, value: anytype) []const u8 {
    return std.fmt.bufPrint(buf, "{d}", .{value}) catch "?";
}

pub const enter_alt_screen = "\x1b[?1049h";
pub const leave_alt_screen = "\x1b[?1049l";
pub const clear_screen = "\x1b[2J";
pub const hide_cursor = "\x1b[?25l";
pub const show_cursor = "\x1b[?25h\x1b[5 q";
pub const cursor_home = "\x1b[H";
pub const clear_line = "\x1b[K";

pub fn moveTo(writer: *std.Io.Writer, x: u16, y: u16) !void {
    var buf: [32]u8 = undefined;
    const cmd = std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ y, x }) catch return;
    try writer.writeAll(cmd);
}

pub const device_icon = std.StaticStringMap([]const u8).initComptime(.{
    .{ "alarm", icons.bell },
    .{ "dimmer", icons.lightbulb },
    .{ "light", icons.lightbulb },
    .{ "switch", icons.toggle },
    .{ "lock", icons.lock },
    .{ "mediaSource", icons.tv },
    .{ "thermostat", icons.thermometer },
    .{ "motionSensor", icons.walking },
    .{ "camera", icons.camera },
    .{ "windowCovering", icons.window },
    .{ "courtesy", icons.certificate },
});

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
            width += 2;
            i += 4;
        }
    }
    return width;
}
