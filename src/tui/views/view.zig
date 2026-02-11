const std = @import("std");
const DevicesView = @import("./devices.zig").DevicesView;
const ApiView = @import("./api.zig").ApiView;
const Rect = @import("../types.zig").Rect;
const KeyResult = @import("../types.zig").KeyResult;
const AppState = @import("../state/state.zig").AppState;
const Config = @import("../../main.zig").Config;

pub const View = union(enum) {
    devices: DevicesView,
    api: ApiView,
    //     logs: LogsView,
    //     settings: SettingsView,
    none,

    const Self = @This();

    pub fn init(number: usize, cfg: Config, area: Rect, state: *AppState, buf: [][]const u8, cols: u16, rows: u16) Self {
        return switch (number) {
            0 => .{ .devices = DevicesView.init(cfg, area, state, buf, cols, rows) },
            1 => .{ .api = ApiView.init(area) },
            else => .none,
        };
    }

    pub fn deinit(self: *Self) void {
        switch (self.*) {
            .devices => |*v| v.deinit(),
            .api => |*v| v.deinit(),
            .none => {},
        }
    }

    pub fn tickSpinner(self: *Self, stdout: std.fs.File) !void {
        switch (self.*) {
            .devices => |*v| try v.tickSpinner(stdout),
            .api, .none => {},
        }
    }

    pub fn isAnimating(self: *Self) bool {
        return switch (self.*) {
            .devices => |*v| v.isAnimating(),
            .api, .none => false,
        };
    }

    pub fn render(self: *Self, stdout: std.fs.File, focused: bool) !void {
        try switch (self.*) {
            .devices => |*v| v.render(stdout, focused),
            .api => |*v| v.render(stdout, focused),
            .none => {},
        };
    }

    pub fn handleKey(self: *Self, stdout: std.fs.File, key: u8) !KeyResult {
        return try switch (self.*) {
            .devices => |*v| v.handleKey(stdout, key),
            .api => |*v| v.handleKey(stdout, key),
            .none => .unhandled,
        };
    }
};
