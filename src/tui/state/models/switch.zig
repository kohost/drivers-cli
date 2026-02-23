const Alert = @import("../definitions/alert.zig").Alert;
const std = @import("std");

fn dupeStr(alloc: std.mem.Allocator, s: []const u8) []const u8 {
    return alloc.dupe(u8, s) catch "";
}

pub const Switch = struct {
    alloc: std.mem.Allocator,
    id: []const u8,
    name: []const u8,
    driver: []const u8,
    state: enum { on, off },
    manufacturer: []const u8,
    model_number: []const u8,
    serial_number: []const u8,
    firmware_version: []const u8,
    watts: u16,
    alerts: []const Alert,
    offline: bool,

    pub const Mode = enum { autoSwitch, holdOpen, lockdown };

    pub fn fromJson(alloc: std.mem.Allocator, obj: std.json.ObjectMap) Switch {
        return .{
            .alloc = alloc,
            .id = dupeStr(alloc, if (obj.get("id")) |v| v.string else ""),
            .name = dupeStr(alloc, if (obj.get("name")) |v| v.string else ""),
            .driver = dupeStr(alloc, if (obj.get("driver")) |v| v.string else ""),
            .state = blk: {
                const s = if (obj.get("state")) |v| v.string else "off";
                break :blk if (std.mem.eql(u8, s, "on")) .on else .off;
            },
            .manufacturer = dupeStr(alloc, if (obj.get("manufacturer")) |v| v.string else ""),
            .serial_number = dupeStr(alloc, if (obj.get("serialNumber")) |v| v.string else ""),
            .model_number = dupeStr(alloc, if (obj.get("modelNumber")) |v| v.string else ""),
            .firmware_version = dupeStr(alloc, if (obj.get("firmwareVersion")) |v| v.string else ""),
            .watts = if (obj.get("watts")) |v| @intCast(v.integer) else 0,
            .alerts = &.{}, // TODO: parse array
            .offline = if (obj.get("offline")) |v| v.bool else false,
        };
    }

    pub fn deinit(self: *Switch) void {
        if (self.id.len > 0) self.alloc.free(self.id);
        if (self.name.len > 0) self.alloc.free(self.name);
        if (self.driver.len > 0) self.alloc.free(self.driver);
        if (self.manufacturer.len > 0) self.alloc.free(self.manufacturer);
        if (self.serial_number.len > 0) self.alloc.free(self.serial_number);
        if (self.model_number.len > 0) self.alloc.free(self.model_number);
        if (self.firmware_version.len > 0) self.alloc.free(self.firmware_version);
    }

    pub fn update(self: *Switch, json: std.json.ObjectMap) bool {
        var changed = false;
        if (json.get("state")) |v| {
            const new_state: @TypeOf(self.state) = if (std.mem.eql(u8, v.string, "on")) .on else .off;
            if (self.state != new_state) {
                self.state = new_state;
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
