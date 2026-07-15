const Alert = @import("../definitions/alert.zig").Alert;
const std = @import("std");

fn dupeStr(alloc: std.mem.Allocator, s: []const u8) []const u8 {
    return alloc.dupe(u8, s) catch "";
}

/// Dupes a JSON string value, or null when absent/not a string.
fn dupeOptStr(alloc: std.mem.Allocator, v: ?std.json.Value) ?[]const u8 {
    const val = v orelse return null;
    if (val != .string) return null;
    return dupeStr(alloc, val.string);
}

/// Parses a JSON string array into a slice of Mode, skipping unknown entries.
fn parseModes(alloc: std.mem.Allocator, v: ?std.json.Value) []const Lock.Mode {
    const val = v orelse return &.{};
    if (val != .array) return &.{};
    const items = val.array.items;
    const result = alloc.alloc(Lock.Mode, items.len) catch return &.{};
    var n: usize = 0;
    for (items) |item| {
        if (item != .string) continue;
        if (std.meta.stringToEnum(Lock.Mode, item.string)) |m| {
            result[n] = m;
            n += 1;
        }
    }
    return result[0..n];
}

pub const Lock = struct {
    alloc: std.mem.Allocator,
    id: []const u8,
    name: []const u8,
    driver: []const u8,
    discriminator: []const u8,
    state: ?State,
    mode: Mode,
    supported_modes: []const Mode,
    manufacturer: []const u8,
    model_number: ?[]const u8,
    serial_number: ?[]const u8,
    firmware_version: ?[]const u8,
    watts: u16,
    alerts: []const Alert,
    offline: ?bool,
    battery: ?i64,

    pub const State = enum { locked, unlocked };
    pub const Mode = enum { autoLock, holdOpen, lockdown };

    pub fn fromJson(alloc: std.mem.Allocator, obj: std.json.ObjectMap) Lock {
        return .{
            .alloc = alloc,
            .id = dupeStr(alloc, if (obj.get("id")) |v| v.string else ""),
            .name = dupeStr(alloc, if (obj.get("name")) |v| v.string else ""),
            .driver = dupeStr(alloc, if (obj.get("driver")) |v| v.string else ""),
            .discriminator = dupeStr(alloc, if (obj.get("discriminator")) |v| v.string else ""),
            .state = if (obj.get("state")) |v|
                (if (v == .string) (if (std.mem.eql(u8, v.string, "locked")) .locked else .unlocked) else null)
            else
                null,
            .mode = blk: {
                const m = if (obj.get("mode")) |v| v.string else "autoLock";
                break :blk if (std.mem.eql(u8, m, "holdOpen")) .holdOpen else if (std.mem.eql(u8, m, "lockdown")) .lockdown else .autoLock;
            },
            .supported_modes = parseModes(alloc, obj.get("supportedModes")),
            .manufacturer = dupeStr(alloc, if (obj.get("manufacturer")) |v| v.string else ""),
            .serial_number = dupeOptStr(alloc, obj.get("serialNumber")),
            .model_number = dupeOptStr(alloc, obj.get("modelNumber")),
            .firmware_version = dupeOptStr(alloc, obj.get("firmwareVersion")),
            .watts = if (obj.get("watts")) |v| @intCast(v.integer) else 0,
            .alerts = &.{}, // TODO: parse array
            .offline = if (obj.get("offline")) |v| v.bool else null,
            .battery = if (obj.get("batteryLevel")) |v| v.integer else null,
        };
    }

    pub fn deinit(self: *Lock) void {
        if (self.id.len > 0) self.alloc.free(self.id);
        if (self.name.len > 0) self.alloc.free(self.name);
        if (self.driver.len > 0) self.alloc.free(self.driver);
        if (self.discriminator.len > 0) self.alloc.free(self.discriminator);
        if (self.manufacturer.len > 0) self.alloc.free(self.manufacturer);
        if (self.serial_number) |s| if (s.len > 0) self.alloc.free(s);
        if (self.model_number) |s| if (s.len > 0) self.alloc.free(s);
        if (self.firmware_version) |s| if (s.len > 0) self.alloc.free(s);
        if (self.supported_modes.len > 0) self.alloc.free(self.supported_modes);
    }

    pub fn update(self: *Lock, json: std.json.ObjectMap) bool {
        var changed = false;
        if (json.get("state")) |v| {
            const new_state: ?State = if (v == .string)
                (if (std.mem.eql(u8, v.string, "locked")) .locked else .unlocked)
            else
                null;
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

    pub fn clone(self: *const Lock, alloc: std.mem.Allocator) !Lock {
        var lock: Lock = .{
            .alloc = alloc,
            .id = "",
            .name = "",
            .driver = "",
            .discriminator = "",
            .state = self.state,
            .mode = self.mode,
            .supported_modes = &.{},
            .manufacturer = "",
            .model_number = null,
            .serial_number = null,
            .firmware_version = null,
            .watts = self.watts,
            .alerts = self.alerts,
            .offline = self.offline,
            .battery = self.battery,
        };
        errdefer lock.deinit();

        lock.id = try dupeOwned(alloc, self.id);
        lock.name = try dupeOwned(alloc, self.name);
        lock.driver = try dupeOwned(alloc, self.driver);
        lock.discriminator = try dupeOwned(alloc, self.discriminator);
        lock.manufacturer = try dupeOwned(alloc, self.manufacturer);
        lock.model_number = if (self.model_number) |s| try dupeOwned(alloc, s) else null;
        lock.serial_number = if (self.serial_number) |s| try dupeOwned(alloc, s) else null;
        lock.firmware_version = if (self.firmware_version) |s| try dupeOwned(alloc, s) else null;
        lock.supported_modes = if (self.supported_modes.len > 0) try alloc.dupe(Mode, self.supported_modes) else &.{};

        return lock;
    }

    fn dupeOwned(alloc: std.mem.Allocator, s: []const u8) ![]const u8 {
        return if (s.len > 0) try alloc.dupe(u8, s) else "";
    }

    pub fn revert(self: *Lock, source: *const Lock) void {
        self.state = source.state;
        self.mode = source.mode;
    }

    pub fn diff(self: *const Lock, source: *const Lock, a: std.mem.Allocator, out: *std.json.ObjectMap) !bool {
        var changed = false;
        if (self.state != source.state) {
            if (self.state) |s| try out.put(a, "state", .{ .string = @tagName(s) });
            changed = true;
        }
        if (self.mode != source.mode) {
            try out.put(a, "mode", .{ .string = @tagName(self.mode) });
            changed = true;
        }
        return changed;
    }

    pub fn merge(self: *Lock, old: *const Lock, new: *const Lock) void {
        if (std.meta.eql(self.state, old.state)) self.state = new.state;
        if (std.meta.eql(self.mode, old.mode)) self.mode = new.mode;

        self.watts = new.watts;
        self.offline = new.offline;
        self.battery = new.battery;
    }
};
