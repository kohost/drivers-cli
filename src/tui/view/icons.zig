const std = @import("std");

// Nerd Font
pub const search = "\u{f002}";
pub const lock = "\u{f033e}";
pub const unlock = "\u{f033f}";
pub const lock_alert = "\u{f08ee}";
pub const camera = "\u{f030}";
pub const fan_on = "\u{f0210}";
pub const fan_off = "\u{f1471}";
pub const certificate = "\u{f0a3}";
pub const light_on = "\u{f1802}";
pub const light_off = "\u{f1803}";
pub const bell = "\u{f0f3}";
pub const angle_right = "\u{f105}";
pub const caret_down = "\u{f0d7}";
pub const caret_up = "\u{f0d8}";
pub const toggle = "\u{f205}";
pub const thermometer = "\u{f2c9}";
pub const send = "\u{f1d9}";
pub const sprinkler = "\u{f058c}";
pub const motionSensor = "\u{f0d91}";
pub const water_on = "\u{f1504}";
pub const water_off = "\u{f150c}";
pub const window = "\u{f2d2}";

// Wide glyphs that need a trailing space to align correctly
pub const tv = "\u{f26c} ";

pub const device_icon = std.StaticStringMap([]const u8).initComptime(.{
    .{ "alarm", bell },
    .{ "dimmer", light_on },
    .{ "light", light_on },
    .{ "switch", toggle },
    .{ "irrigation", sprinkler },
    .{ "lock", lock },
    .{ "mediaSource", tv },
    .{ "thermostat", thermometer },
    .{ "motionSensor", motionSensor },
    .{ "camera", camera },
    .{ "windowCovering", window },
    .{ "courtesy", certificate },
});
