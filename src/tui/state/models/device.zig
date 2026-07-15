const std = @import("std");
const Alarm = @import("alarm.zig").Alarm;
const Lock = @import("lock.zig").Lock;
const Switch = @import("switch.zig").Switch;
const Thermostat = @import("thermostat.zig").Thermostat;

pub const Device = union(enum) {
    // alarm: Alarm,
    lock: Lock,
    @"switch": Switch,
    thermostat: Thermostat,

    pub fn id(self: Device) []const u8 {
        return switch (self) {
            inline else => |d| d.id,
        };
    }

    pub fn name(self: Device) []const u8 {
        return switch (self) {
            inline else => |d| d.name,
        };
    }

    pub fn deviceType(self: Device) []const u8 {
        return switch (self) {
            inline else => |_, tag| @tagName(tag),
        };
    }

    pub fn discriminator(self: Device) []const u8 {
        return switch (self) {
            inline else => |d| d.discriminator,
        };
    }

    pub fn offline(self: Device) ?bool {
        return switch (self) {
            inline else => |d| d.offline,
        };
    }

    pub fn manufacturer(self: Device) []const u8 {
        return switch (self) {
            inline else => |d| d.manufacturer,
        };
    }

    pub fn modelNumber(self: Device) ?[]const u8 {
        return switch (self) {
            inline else => |d| d.model_number,
        };
    }

    pub fn serialNumber(self: Device) ?[]const u8 {
        return switch (self) {
            inline else => |d| d.serial_number,
        };
    }

    pub fn firmwareVersion(self: Device) ?[]const u8 {
        return switch (self) {
            inline else => |d| d.firmware_version,
        };
    }

    pub fn watts(self: Device) u16 {
        return switch (self) {
            inline else => |d| d.watts,
        };
    }

    pub fn fromJson(alloc: std.mem.Allocator, obj: std.json.ObjectMap) ?Device {
        const device_type = if (obj.get("type")) |v| v.string else return null;
        inline for (@typeInfo(Device).@"union".fields) |field| {
            if (std.mem.eql(u8, field.name, device_type)) {
                return @unionInit(Device, field.name, field.type.fromJson(alloc, obj));
            }
        }
        return null;
    }

    pub fn deinit(self: *Device) void {
        switch (self.*) {
            inline else => |*d| d.deinit(),
        }
    }

    pub fn update(self: *Device, obj: std.json.ObjectMap) bool {
        return switch (self.*) {
            inline else => |*d| d.update(obj),
        };
    }

    pub fn clone(self: *const Device, alloc: std.mem.Allocator) !Device {
        return switch (self.*) {
            inline else => |*d, tag| @unionInit(Device, @tagName(tag), try d.clone(alloc)),
        };
    }

    pub fn revert(self: *Device, source: *const Device) void {
        return switch (self.*) {
            inline else => |*d, tag| d.revert(&@field(source.*, @tagName(tag))),
        };
    }

    pub fn merge(self: *Device, old: *const Device, new: *const Device) void {
        return switch (self.*) {
            inline else => |*d, tag| d.merge(
                &@field(old.*, @tagName(tag)),
                &@field(new.*, @tagName(tag)),
            ),
        };
    }

    pub fn diff(self: *const Device, source: *const Device, a: std.mem.Allocator, out: *std.json.ObjectMap) !bool {
        return switch (self.*) {
            inline else => |*d, tag| d.diff(&@field(source.*, @tagName(tag)), a, out),
        };
    }
};
