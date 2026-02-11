const std = @import("std");
const AlarmDetail = @import("devices/alarm.zig").AlarmDetail;
const LockDetail = @import("devices/lock.zig").LockDetail;
const KeyResult = @import("../types.zig").KeyResult;
const Rect = @import("../types.zig").Rect;
const Device = @import("../state/models/device.zig").Device;
const Alarm = @import("../state/models/alarm.zig").Alarm;
const Lock = @import("../state/models/lock.zig").Lock;

pub const DetailView = union(enum) {
    alarm: AlarmDetail,
    lock: LockDetail,
    none,

    const Self = @This();

    pub fn init(device: *Device, area: Rect, cols: u16, rows: u16) DetailView {
        return switch (device.*) {
            .alarm => |*a| .{ .alarm = AlarmDetail.init(area, a, cols, rows) },
            .lock => |*l| .{ .lock = LockDetail.init(area, l) },
        };
    }

    pub fn tickSpinner(self: *Self, stdout: std.fs.File) !void {
        switch (self.*) {
            .alarm => |*v| try v.security_switch.render(stdout, v.cursor == 0),
            .lock, .none => {},
        }
    }

    pub fn isAnimating(self: *Self) bool {
        return switch (self.*) {
            .alarm => |*v| v.isAnimating(),
            .lock, .none => false,
        };
    }

    pub fn render(self: *Self, stdout: std.fs.File, focused: bool) !u16 {
        return switch (self.*) {
            .alarm => |*v| v.render(stdout, focused),
            .lock => |*v| v.render(stdout, focused),
            .none => 0,
        };
    }

    pub fn handleKey(self: *Self, stdout: std.fs.File, key: u8) !KeyResult {
        return switch (self.*) {
            .alarm => |*v| v.handleKey(stdout, key),
            .lock => |*v| v.handleKey(stdout, key),
            .none => .unhandled,
        };
    }

    pub fn hasOpenSelect(self: *Self) bool {
        return switch (self.*) {
            .alarm => |*v| v.code_input.visible or v.zone_list.open,
            .lock => |*v| v.mode_select.open,
            .none => false,
        };
    }
};
