const std = @import("std");
const Lock = @import("lock.zig").Lock;
// const Dimmer = @import("dimmer.zig").Dimmer;
// const Thermostat = @import("thermostat.zig").Thermostat;

pub const Device = union(enum) {
    lock: Lock,
    //     dimmer: Dimmer,
    //     thermostat: Thermostat

    pub fn id(self: Device) []const u8 {
        return switch (self) {
            .lock => |l| l.id,
        };
    }

    pub fn name(self: Device) []const u8 {
        return switch (self) {
            .lock => |l| l.name,
        };
    }

    pub fn deviceType(self: Device) []const u8 {
        return switch (self) {
            .lock => "lock",
        };
    }

    pub fn offline(self: Device) bool {
        return switch (self) {
            .lock => |l| l.offline,
        };
    }

    pub fn manufacturer(self: Device) []const u8 {
        return switch (self) {
            .lock => |l| l.manufacturer,
        };
    }

    pub fn modelNumber(self: Device) []const u8 {
        return switch (self) {
            .lock => |l| l.model_number,
        };
    }

    pub fn serialNumber(self: Device) []const u8 {
        return switch (self) {
            .lock => |l| l.serial_number,
        };
    }

    pub fn firmwareVersion(self: Device) []const u8 {
        return switch (self) {
            .lock => |l| l.firmware_version,
        };
    }

    pub fn watts(self: Device) u16 {
        return switch (self) {
            .lock => |l| l.watts,
        };
    }

    pub fn fromJson(alloc: std.mem.Allocator, obj: std.json.ObjectMap) ?Device {
        const device_type = if (obj.get("type")) |v| v.string else return null;

        if (std.mem.eql(u8, device_type, "lock")) {
            return .{ .lock = Lock.fromJson(alloc, obj) };
        }

        return null;
    }

    pub fn deinit(self: *Device) void {
        switch (self.*) {
            .lock => |*l| l.deinit(),
        }
    }

    pub fn update(self: *Device, obj: std.json.ObjectMap) void {
        switch (self.*) {
            .lock => |*l| l.update(obj),
        }
    }
};
