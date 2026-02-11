const Alert = @import("../definitions/alert.zig").Alert;
const std = @import("std");

fn dupeStr(alloc: std.mem.Allocator, s: []const u8) []const u8 {
    return alloc.dupe(u8, s) catch "";
}

pub const Lock = struct {
    alloc: std.mem.Allocator,
    id: []const u8,
    name: []const u8,
    driver: []const u8,
    state: enum { locked, unlocked },
    mode: Mode,
    supported_modes: []const Mode,
    manufacturer: []const u8,
    model_number: []const u8,
    serial_number: []const u8,
    firmware_version: []const u8,
    watts: u16,
    alerts: []const Alert,
    offline: bool,

    pub const Mode = enum { autoLock, holdOpen, lockdown };

    pub fn fromJson(alloc: std.mem.Allocator, obj: std.json.ObjectMap) Lock {
        return .{
            .alloc = alloc,
            .id = dupeStr(alloc, if (obj.get("id")) |v| v.string else ""),
            .name = dupeStr(alloc, if (obj.get("name")) |v| v.string else ""),
            .driver = dupeStr(alloc, if (obj.get("driver")) |v| v.string else ""),
            .state = blk: {
                const s = if (obj.get("state")) |v| v.string else "unlocked";
                break :blk if (std.mem.eql(u8, s, "locked")) .locked else .unlocked;
            },
            .mode = blk: {
                const m = if (obj.get("mode")) |v| v.string else "autoLock";
                break :blk if (std.mem.eql(u8, m, "holdOpen")) .holdOpen else if (std.mem.eql(u8, m, "lockdown")) .lockdown else .autoLock;
            },
            .supported_modes = &.{}, // TODO: parse array
            .manufacturer = dupeStr(alloc, if (obj.get("manufacturer")) |v| v.string else ""),
            .serial_number = dupeStr(alloc, if (obj.get("serialNumber")) |v| v.string else ""),
            .model_number = dupeStr(alloc, if (obj.get("modelNumber")) |v| v.string else ""),
            .firmware_version = dupeStr(alloc, if (obj.get("firmwareVersion")) |v| v.string else ""),
            .watts = if (obj.get("watts")) |v| @intCast(v.integer) else 0,
            .alerts = &.{}, // TODO: parse array
            .offline = if (obj.get("offline")) |v| v.bool else false,
        };
    }

    pub fn deinit(self: *Lock) void {
        if (self.id.len > 0) self.alloc.free(self.id);
        if (self.name.len > 0) self.alloc.free(self.name);
        if (self.driver.len > 0) self.alloc.free(self.driver);
        if (self.manufacturer.len > 0) self.alloc.free(self.manufacturer);
        if (self.serial_number.len > 0) self.alloc.free(self.serial_number);
        if (self.model_number.len > 0) self.alloc.free(self.model_number);
        if (self.firmware_version.len > 0) self.alloc.free(self.firmware_version);
    }

    pub fn update(self: *Lock, json: std.json.ObjectMap) bool {
        var changed = false;
        if (json.get("state")) |v| {
            const new_state: @TypeOf(self.state) = if (std.mem.eql(u8, v.string, "locked")) .locked else .unlocked;
            if (self.state != new_state) {
                self.state = new_state;
                changed = true;
            }
        }
        if (json.get("mode")) |v| {
            const new_mode: Mode = if (std.mem.eql(u8, v.string, "holdOpen")) .holdOpen else if (std.mem.eql(u8, v.string, "lockdown")) .lockdown else .autoLock;
            if (self.mode != new_mode) {
                self.mode = new_mode;
                changed = true;
            }
        }
        if (json.get("offline")) |v| {
            if (self.offline != v.bool) {
                self.offline = v.bool;
                changed = true;
            }
        }
        return changed;
    }
};
