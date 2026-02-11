const std = @import("std");
const Alert = @import("../definitions/alert.zig").Alert;

fn dupeStr(alloc: std.mem.Allocator, s: []const u8) []const u8 {
    return alloc.dupe(u8, s) catch "";
}

pub const Alarm = struct {
    alloc: std.mem.Allocator,
    id: []const u8,
    name: []const u8,
    driver: []const u8,
    areas: []Area,
    zones: []Zone,
    code: []const u8,
    chime: ?bool,
    manufacturer: []const u8,
    model_number: []const u8,
    serial_number: []const u8,
    firmware_version: []const u8,
    watts: u16,
    alerts: []const Alert,
    offline: bool,

    pub const Area = struct {
        id: []const u8,
        name: []const u8,
        supported_security_modes: []const SecurityMode,
        security_mode: ?SecurityMode,
    };

    pub const Zone = struct {
        id: []const u8,
        name: []const u8,
        secure: ?bool,
        bypassed: ?bool,
        offline: bool,
        battery_level: ?u8,
    };

    pub const SecurityMode = enum { arming, armed, disarming, disarmed, intrusion, fire, medical };

    pub fn fromJson(alloc: std.mem.Allocator, obj: std.json.ObjectMap) Alarm {
        return .{
            .alloc = alloc,
            .id = dupeStr(alloc, if (obj.get("id")) |v| v.string else ""),
            .name = dupeStr(alloc, if (obj.get("name")) |v| v.string else ""),
            .driver = dupeStr(alloc, if (obj.get("driver")) |v| v.string else ""),
            .areas = parseAreas(alloc, obj.get("areas")),
            .zones = parseZones(alloc, obj.get("zones")),
            .code = dupeStr(alloc, if (obj.get("code")) |v| v.string else ""),
            .manufacturer = dupeStr(alloc, if (obj.get("manufacturer")) |v| v.string else ""),
            .serial_number = dupeStr(alloc, if (obj.get("serialNumber")) |v| v.string else ""),
            .model_number = dupeStr(alloc, if (obj.get("modelNumber")) |v| v.string else ""),
            .firmware_version = dupeStr(alloc, if (obj.get("firmwareVersion")) |v| v.string else ""),
            .watts = if (obj.get("watts")) |v| @intCast(v.integer) else 0,
            .alerts = &.{}, // TODO: parse array
            .chime = if (obj.get("chime")) |v| v.bool else null,
            .offline = if (obj.get("offline")) |v| v.bool else false,
        };
    }

    pub fn deinit(self: *Alarm) void {
        if (self.id.len > 0) self.alloc.free(self.id);
        if (self.name.len > 0) self.alloc.free(self.name);
        if (self.driver.len > 0) self.alloc.free(self.driver);
        if (self.manufacturer.len > 0) self.alloc.free(self.manufacturer);
        if (self.serial_number.len > 0) self.alloc.free(self.serial_number);
        if (self.model_number.len > 0) self.alloc.free(self.model_number);
        if (self.firmware_version.len > 0) self.alloc.free(self.firmware_version);

        for (self.areas) |area| {
            if (area.id.len > 0) self.alloc.free(area.id);
            if (area.name.len > 0) self.alloc.free(area.name);
        }
        if (self.areas.len > 0) self.alloc.free(self.areas);

        for (self.zones) |zone| {
            if (zone.id.len > 0) self.alloc.free(zone.id);
            if (zone.name.len > 0) self.alloc.free(zone.name);
        }
        if (self.zones.len > 0) self.alloc.free(self.zones);
    }

    pub fn update(self: *Alarm, json: std.json.ObjectMap) bool {
        var changed = false;
        if (json.get("offline")) |v| {
            if (self.offline != v.bool) {
                self.offline = v.bool;
                changed = true;
            }
        }
        if (json.get("chime")) |v| {
            const new_chime = v.bool;
            if (self.chime == null or self.chime.? != new_chime) {
                self.chime = new_chime;
                changed = true;
            }
        }
        if (json.get("areas")) |areas_val| {
            for (areas_val.array.items) |item| {
                const obj = item.object;
                const area_id = if (obj.get("id")) |v| v.string else continue;
                const new_mode = parseSecurityMode(if (obj.get("securityMode")) |v| v.string else null) orelse continue;
                for (self.areas) |*area| {
                    if (std.mem.eql(u8, area.id, area_id)) {
                        if (area.security_mode == null or area.security_mode.? != new_mode) {
                            area.security_mode = new_mode;
                            changed = true;
                        }
                    }
                }
            }
        }
        if (json.get("zones")) |zones_val| {
            for (zones_val.array.items) |item| {
                const obj = item.object;
                const zone_id = if (obj.get("id")) |v| v.string else continue;
                for (self.zones) |*zone| {
                    if (std.mem.eql(u8, zone.id, zone_id)) {
                        if (obj.get("secure")) |v| {
                            const new_secure = v.bool;
                            if (zone.secure == null or zone.secure.? != new_secure) {
                                zone.secure = new_secure;
                                changed = true;
                            }
                        }
                        if (obj.get("bypassed")) |v| {
                            const new_bypassed = v.bool;
                            if (zone.bypassed == null or zone.bypassed.? != new_bypassed) {
                                zone.bypassed = new_bypassed;
                                changed = true;
                            }
                        }
                        if (obj.get("offline")) |v| {
                            if (zone.offline != v.bool) {
                                zone.offline = v.bool;
                                changed = true;
                            }
                        }
                    }
                }
            }
        }
        return changed;
    }

    fn parseAreas(alloc: std.mem.Allocator, val: ?std.json.Value) []Area {
        const arr = (val orelse return &.{}).array.items;
        var list = alloc.alloc(Area, arr.len) catch return &.{};
        for (arr, 0..) |item, idx| {
            const obj = item.object;
            list[idx] = .{
                .id = dupeStr(alloc, if (obj.get("id")) |v| v.string else ""),
                .name = dupeStr(alloc, if (obj.get("name")) |v| v.string else ""),
                .supported_security_modes = &.{}, // TODO
                .security_mode = parseSecurityMode(if (obj.get("securityMode")) |v| v.string else null),
            };
        }
        return list;
    }

    fn parseZones(alloc: std.mem.Allocator, val: ?std.json.Value) []Zone {
        const arr = (val orelse return &.{}).array.items;
        var list = alloc.alloc(Zone, arr.len) catch return &.{};
        for (arr, 0..) |item, idx| {
            const obj = item.object;
            list[idx] = .{
                .id = dupeStr(alloc, if (obj.get("id")) |v| v.string else ""),
                .name = dupeStr(alloc, if (obj.get("name")) |v| v.string else ""),
                .secure = if (obj.get("secure")) |v| v.bool else null,
                .bypassed = if (obj.get("bypassed")) |v| v.bool else null,
                .offline = if (obj.get("offline")) |v| v.bool else false,
                .battery_level = if (obj.get("batteryLevel")) |v| @as(?u8, @intCast(v.integer)) else null,
            };
        }
        return list;
    }

    fn parseSecurityMode(s: ?[]const u8) ?SecurityMode {
        const str = s orelse return null;
        if (std.mem.eql(u8, str, "arming")) return .arming;
        if (std.mem.eql(u8, str, "armed")) return .armed;
        if (std.mem.eql(u8, str, "disarming")) return .disarming;
        if (std.mem.eql(u8, str, "disarmed")) return .disarmed;
        if (std.mem.eql(u8, str, "intrusion")) return .intrusion;
        if (std.mem.eql(u8, str, "fire")) return .fire;
        if (std.mem.eql(u8, str, "medical")) return .medical;
        return null;
    }
};
