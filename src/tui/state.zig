const std = @import("std");
const Device = @import("state/models/device.zig").Device;

pub const State = struct {
    devices: std.ArrayList(Device),
    alloc: std.mem.Allocator,
    system: ?struct {
        manufacturer: []const u8,
        model: []const u8,
        api_version: []const u8,
        ios_app_url: []const u8,
        android_app_url: []const u8,
        web_app_url: []const u8,
    },

    pub fn init(alloc: std.mem.Allocator) State {
        return .{
            .devices = .empty,
            .alloc = alloc,
            .system = null,
        };
    }

    pub fn deinit(self: *State) void {
        if (self.system) |sys| {
            if (sys.manufacturer.len > 0) self.alloc.free(sys.manufacturer);
            if (sys.model.len > 0) self.alloc.free(sys.model);
            if (sys.api_version.len > 0) self.alloc.free(sys.api_version);
            if (sys.ios_app_url.len > 0) self.alloc.free(sys.ios_app_url);
            if (sys.android_app_url.len > 0) self.alloc.free(sys.android_app_url);
            if (sys.web_app_url.len > 0) self.alloc.free(sys.web_app_url);
        }
        for (self.devices.items) |*device| {
            device.deinit();
        }
        self.devices.deinit(self.alloc);
    }

    pub fn getDevice(self: *State, device_id: []const u8) ?*Device {
        for (self.devices.items) |*device| {
            if (std.mem.eql(u8, device.id(), device_id)) return device;
        }
        return null;
    }

    pub fn loadFromJson(self: *State, json: std.json.Value) !void {
        // Unwrap outer data wrapper if present
        const root = blk: {
            const d = json.object.get("data") orelse break :blk json;
            break :blk if (d == .object) d else json;
        };

        if (root.object.get("context")) |ctx| {
            if (ctx.object.get("system")) |sys| {
                const obj = sys.object;
                self.system = .{
                    .manufacturer = if (obj.get("manufacturer")) |v| try self.alloc.dupe(u8, v.string) else "",
                    .model = if (obj.get("model")) |v| try self.alloc.dupe(u8, v.string) else "",
                    .api_version = if (obj.get("apiVersion")) |v| try self.alloc.dupe(u8, v.string) else "",
                    .ios_app_url = if (obj.get("iosAppUrl")) |v| try self.alloc.dupe(u8, v.string) else "",
                    .android_app_url = if (obj.get("androidAppUrl")) |v| try self.alloc.dupe(u8, v.string) else "",
                    .web_app_url = if (obj.get("webAppUrl")) |v| try self.alloc.dupe(u8, v.string) else "",
                };
            }
        }

        const data = root.object.get("data") orelse return;
        if (data != .array) return;

        for (data.array.items) |item| {
            if (Device.fromJson(self.alloc, item.object)) |device| {
                try self.devices.append(self.alloc, device);
            }
        }
    }

    pub fn update(self: *State, json: std.json.Value) bool {
        const data = json.object.get("data") orelse return false;
        if (data != .array) return false;

        var changed = false;
        for (data.array.items) |item| {
            const updated_id = if (item.object.get("id")) |v| v.string else continue;
            if (self.getDevice(updated_id)) |device| {
                if (device.update(item.object)) changed = true;
            }
        }
        return changed;
    }
};
