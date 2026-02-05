const std = @import("std");
const LockDetail = @import("devices/lock.zig").LockDetail;
const KeyResult = @import("../types.zig").KeyResult;
const Rect = @import("../types.zig").Rect;
const Device = @import("../state/models/device.zig").Device;
const Lock = @import("../state/models/lock.zig").Lock;

pub const DetailView = union(enum) {
    lock: LockDetail,
    none,

    const Self = @This();

    pub fn init(device: *Device, area: Rect) DetailView {
        return switch (device.*) {
            .lock => |*l| .{ .lock = LockDetail.init(area, l) },
        };
    }

    pub fn render(self: *Self, stdout: std.fs.File, focused: bool) !u16 {
        return switch (self.*) {
            .lock => |*v| v.render(stdout, focused),
            .none => 0,
        };
    }

    pub fn handleKey(self: *Self, stdout: std.fs.File, key: u8) !KeyResult {
        return switch (self.*) {
            .lock => |*v| v.handleKey(stdout, key),
            .none => .unhandled,
        };
    }
};
