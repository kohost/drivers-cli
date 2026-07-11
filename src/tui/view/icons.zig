const std = @import("std");

// Nerd Font
pub const search = "\u{f002}";
pub const lock = "\u{f033e}";
pub const unlock = "\u{f033f}";
pub const lock_alert = "\u{f08ee}";
pub const camera = "\u{f030}";
pub const certificate = "\u{f0a3}";
pub const lightbulb = "\u{f0eb}";
pub const bell = "\u{f0f3}";
pub const angle_right = "\u{f105}";
pub const caret_down = "\u{f0d7}";
pub const caret_up = "\u{f0d8}";
pub const toggle = "\u{f205}";
pub const tv = "\u{f26c}";
pub const thermometer = "\u{f2c9}";
pub const window = "\u{f2d2}";
pub const send = "\u{f1d9}";
pub const walking = "\u{f554}";

pub const device_icon = std.StaticStringMap([]const u8).initComptime(.{
    .{ "alarm", bell },
    .{ "dimmer", lightbulb },
    .{ "light", lightbulb },
    .{ "switch", toggle },
    .{ "lock", lock },
    .{ "mediaSource", tv },
    .{ "thermostat", thermometer },
    .{ "motionSensor", walking },
    .{ "camera", camera },
    .{ "windowCovering", window },
    .{ "courtesy", certificate },
});
