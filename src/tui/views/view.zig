const std = @import("std");
const DevicesView = @import("./devices.zig").DevicesView;
const Rect = @import("../types.zig").Rect;
const KeyResult = @import("../types.zig").KeyResult;
const Data = @import("../types.zig").Data;

pub const View = union(enum) {
    devices: DevicesView,
    //     api: ApiView,
    //     logs: LogsView,
    //     settings: SettingsView,
    none,

    const Self = @This();

    pub fn init(number: usize, area: Rect, data: *const Data, buf: [][]const u8) Self {
        return switch (number) {
            0 => .{ .devices = DevicesView.init(area, data, buf) },
            else => .none,
        };
    }

    pub fn deinit(self: *Self) void {
        switch (self.*) {
            .devices => |*v| v.deinit(),
            .none => {},
        }
    }

    pub fn render(self: *Self, stdout: std.fs.File, focused: bool) !void {
        try switch (self.*) {
            .devices => |*v| v.render(stdout, focused),
            .none => {},
        };
    }

    pub fn handleKey(self: *Self, stdout: std.fs.File, key: u8) !KeyResult {
        return try switch (self.*) {
            .devices => |*v| v.handleKey(stdout, key),
            .none => .unhandled,
        };
    }
};
