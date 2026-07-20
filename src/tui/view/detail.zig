const Component = @import("Component.zig");
const KeyValList = @import("component/key_val_list.zig").KeyValList;
const Dimmer = @import("detail/dimmer.zig").DimmerView;
const MediaSource = @import("detail/media_source.zig").MediaSourceView;
const MotionSensor = @import("detail/motion_sensor.zig").MotionSensorView;
const Thermostat = @import("detail/thermostat.zig").ThermostatView;
const Lock = @import("detail/lock.zig").LockView;
const Switch = @import("detail/switch.zig").SwitchView;

pub const DetailView = union(enum) {
    dimmer: Dimmer,
    thermostat: Thermostat,
    lock: Lock,
    mediaSource: MediaSource,
    motionSensor: MotionSensor,
    @"switch": Switch,
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
