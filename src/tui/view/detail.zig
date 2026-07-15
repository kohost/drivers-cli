const Component = @import("Component.zig");
const KeyValList = @import("component/key_val_list.zig").KeyValList;
const ThermostatView = @import("devices/thermostat.zig").ThermostatView;
const LockView = @import("devices/lock.zig").LockView;
const SwitchView = @import("devices/switch.zig").SwitchView;

// Depth-1 detail view; one variant per drillable device type.
pub const DetailView = union(enum) {
    thermostat: ThermostatView,
    lock: LockView,
    @"switch": SwitchView,
    none,

    pub fn deinit(self: *DetailView) void {
        switch (self.*) {
            .none => {},
            inline else => |*v| v.deinit(),
        }
    }

    pub fn component(self: *DetailView) Component {
        return switch (self.*) {
            .none => unreachable,
            inline else => |*v| v.component(),
        };
    }

    pub fn list(self: *DetailView) ?*KeyValList {
        return switch (self.*) {
            .none => null,
            inline else => |*v| &v.list,
        };
    }
};
