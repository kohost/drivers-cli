const Alert = @import("../definitions/alert.zig").Alert;
const std = @import("std");

fn dupeStr(alloc: std.mem.Allocator, s: []const u8) []const u8 {
    return alloc.dupe(u8, s) catch "";
}

pub const MediaSource = struct {
    alloc: std.mem.Allocator,
    id: []const u8,
    name: []const u8,
    driver: []const u8,
    discriminator: []const u8,
    manufacturer: []const u8,
    model_number: []const u8,
    serial_number: []const u8,
    firmware_version: []const u8,
    watts: u16,
    alerts: []const Alert,
    offline: bool,

    pub fn fromJson(alloc: std.mem.Allocator, obj: std.json.ObjectMap) MediaSource {
        return .{
            .alloc = alloc,
            .id = dupeStr(alloc, if (obj.get("id")) |v| v.string else ""),
            .name = dupeStr(alloc, if (obj.get("name")) |v| v.string else ""),
            .driver = dupeStr(alloc, if (obj.get("driver")) |v| v.string else ""),
            .discriminator = dupeStr(alloc, if (obj.get("discriminator")) |v| v.string else ""),
            .manufacturer = dupeStr(alloc, if (obj.get("manufacturer")) |v| v.string else ""),
            .serial_number = dupeStr(alloc, if (obj.get("serialNumber")) |v| v.string else ""),
            .model_number = dupeStr(alloc, if (obj.get("modelNumber")) |v| v.string else ""),
            .firmware_version = dupeStr(alloc, if (obj.get("firmwareVersion")) |v| v.string else ""),
            .watts = if (obj.get("watts")) |v| @intCast(v.integer) else 0,
            .alerts = &.{}, // TODO: parse array
            .offline = if (obj.get("offline")) |v| v.bool else false,
        };
    }

    pub fn deinit(self: *MediaSource) void {
        if (self.id.len > 0) self.alloc.free(self.id);
        if (self.name.len > 0) self.alloc.free(self.name);
        if (self.driver.len > 0) self.alloc.free(self.driver);
        if (self.discriminator.len > 0) self.alloc.free(self.discriminator);
        if (self.manufacturer.len > 0) self.alloc.free(self.manufacturer);
        if (self.serial_number.len > 0) self.alloc.free(self.serial_number);
        if (self.model_number.len > 0) self.alloc.free(self.model_number);
        if (self.firmware_version.len > 0) self.alloc.free(self.firmware_version);
    }

    pub fn update(self: *MediaSource, json: std.json.ObjectMap) bool {
        var changed = false;
        if (json.get("offline")) |v| {
            if (self.offline != v.bool) {
                self.offline = v.bool;
                changed = true;
            }
        }
        return changed;
    }

    pub fn clone(self: *const MediaSource, alloc: std.mem.Allocator) !MediaSource {
        var sw: MediaSource = .{
            .alloc = alloc,
            .id = "",
            .name = "",
            .driver = "",
            .discriminator = "",
            .manufacturer = "",
            .model_number = "",
            .serial_number = "",
            .firmware_version = "",
            .watts = self.watts,
            .alerts = self.alerts,
            .offline = self.offline,
        };
        errdefer sw.deinit();

        sw.id = try dupeOwned(alloc, self.id);
        sw.name = try dupeOwned(alloc, self.name);
        sw.driver = try dupeOwned(alloc, self.driver);
        sw.discriminator = try dupeOwned(alloc, self.discriminator);
        sw.manufacturer = try dupeOwned(alloc, self.manufacturer);
        sw.model_number = try dupeOwned(alloc, self.model_number);
        sw.serial_number = try dupeOwned(alloc, self.serial_number);
        sw.firmware_version = try dupeOwned(alloc, self.firmware_version);

        return sw;
    }

    fn dupeOwned(alloc: std.mem.Allocator, s: []const u8) ![]const u8 {
        return if (s.len > 0) try alloc.dupe(u8, s) else "";
    }

    pub fn revert(self: *MediaSource, source: *const MediaSource) void {
        _ = self;
        _ = source;
    }

    pub fn merge(self: *MediaSource, old: *const MediaSource, new: *const MediaSource) void {
        // if (self.level == old.level) self.level = new.level;
        _ = old;

        self.watts = new.watts;
        self.offline = new.offline;
    }

    pub fn diff(
        self: *const MediaSource,
        src: *const MediaSource,
        a: std.mem.Allocator,
        out: *std.json.ObjectMap,
    ) !bool {
        // if (self.level == src.level) return false;
        _ = self;
        _ = src;
        _ = a;
        _ = out;
        // try out.put(a, "level", .{ .integer = self.level });
        return true;
    }
};
