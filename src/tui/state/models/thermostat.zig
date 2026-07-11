const std = @import("std");
const Alert = @import("../definitions/alert.zig").Alert;

fn dupeStr(alloc: std.mem.Allocator, s: []const u8) []const u8 {
    return alloc.dupe(u8, s) catch "";
}

/// Dupes a JSON string value, or null when absent/not a string.
fn dupeOptStr(alloc: std.mem.Allocator, v: ?std.json.Value) ?[]const u8 {
    const val = v orelse return null;
    if (val != .string) return null;
    return dupeStr(alloc, val.string);
}

pub const Thermostat = struct {
    alloc: std.mem.Allocator,
    id: []const u8,
    name: []const u8,
    driver: []const u8,
    current_temperature: f32,
    current_humidity: ?f32,
    min_auto_delta: ?u8,
    hvac_mode: HvacMode,
    hvac_state: ?HvacState,
    fan_mode: FanMode,
    fan_state: ?FanState,
    temperature_scale: TemperatureScale,
    humidity_scale: ?HumidityScale,
    supported_hvac_modes: []const HvacMode,
    supported_fan_modes: []const FanMode,
    setpoints: Setpoints,
    manufacturer: []const u8,
    model_number: ?[]const u8,
    serial_number: ?[]const u8,
    firmware_version: []const u8,
    watts: u16,
    alerts: []const Alert,
    offline: bool,
    ui_enabled: ?bool,
    cycle_rate: ?u8,

    pub const Setpoints = struct {
        cool: ?Setpoint = null,
        heat: ?Setpoint = null,
        auto: ?Setpoint = null,
    };
    pub const Setpoint = struct {
        value: f32,
        min: f32,
        max: f32,
    };

    pub const HvacMode = enum { off, heat, cool, auto };
    pub const HvacState = enum { cooling, heating, off };
    pub const FanMode = enum { off, on, auto, low, medium, high };
    pub const FanState = enum { off, on, low, medium, high };
    pub const TemperatureScale = enum { celsius, fahrenheit };
    pub const HumidityScale = enum { absolute, relative };

    pub fn fromJson(alloc: std.mem.Allocator, obj: std.json.ObjectMap) Thermostat {
        return .{
            .alloc = alloc,
            .id = dupeStr(alloc, if (obj.get("id")) |v| v.string else ""),
            .name = dupeStr(alloc, if (obj.get("name")) |v| v.string else ""),
            .driver = dupeStr(alloc, if (obj.get("driver")) |v| v.string else ""),
            .current_temperature = if (obj.get("currentTemperature")) |v| switch (v) {
                .float => |f| @floatCast(f),
                .integer => |i| @floatFromInt(i),
                else => 0.0,
            } else 0.0,
            .current_humidity = if (obj.get("currentHumidity")) |v| switch (v) {
                .float => |f| @floatCast(f),
                .integer => |i| @floatFromInt(i),
                else => null,
            } else null,
            .min_auto_delta = if (obj.get("minAutoDelta")) |v| @intCast(v.integer) else null,
            .hvac_mode = if (obj.get("hvacMode")) |v| std.meta.stringToEnum(HvacMode, v.string) orelse .off else .off,
            .hvac_state = if (obj.get("hvacState")) |v| std.meta.stringToEnum(HvacState, v.string) else null,
            .fan_mode = if (obj.get("fanMode")) |v| std.meta.stringToEnum(FanMode, v.string) orelse .off else .off,
            .fan_state = if (obj.get("fanState")) |v| std.meta.stringToEnum(FanState, v.string) else null,
            .temperature_scale = if (obj.get("temperatureScale")) |v| std.meta.stringToEnum(TemperatureScale, v.string) orelse .fahrenheit else .fahrenheit,
            .humidity_scale = if (obj.get("humidityScale")) |v| std.meta.stringToEnum(HumidityScale, v.string) else null,
            .supported_hvac_modes = parseEnumArr(HvacMode, alloc, obj.get("supportedHvacModes")),
            .supported_fan_modes = parseEnumArr(FanMode, alloc, obj.get("supportedFanModes")),
            .setpoints = if (obj.get("setpoints")) |v| blk: {
                const sp = v.object;
                break :blk .{
                    .cool = parseSetpoint(sp.get("cool")),
                    .heat = parseSetpoint(sp.get("heat")),
                    .auto = parseSetpoint(sp.get("auto")),
                };
            } else .{},
            .manufacturer = dupeStr(alloc, if (obj.get("manufacturer")) |v| v.string else ""),
            .serial_number = dupeOptStr(alloc, obj.get("serialNumber")),
            .model_number = dupeOptStr(alloc, obj.get("modelNumber")),
            .firmware_version = dupeStr(alloc, if (obj.get("firmwareVersion")) |v| v.string else ""),
            .watts = if (obj.get("watts")) |v| @intCast(v.integer) else 0,
            .alerts = &.{}, // TODO: parse array
            .offline = if (obj.get("offline")) |v| v.bool else false,
            .ui_enabled = if (obj.get("uiEnabled")) |v| v.bool else null,
            .cycle_rate = if (obj.get("cycleRate")) |v| @intCast(v.integer) else null,
        };
    }

    pub fn deinit(self: *Thermostat) void {
        if (self.id.len > 0) self.alloc.free(self.id);
        if (self.name.len > 0) self.alloc.free(self.name);
        if (self.driver.len > 0) self.alloc.free(self.driver);
        if (self.manufacturer.len > 0) self.alloc.free(self.manufacturer);
        if (self.serial_number) |s| if (s.len > 0) self.alloc.free(s);
        if (self.model_number) |s| if (s.len > 0) self.alloc.free(s);
        if (self.firmware_version.len > 0) self.alloc.free(self.firmware_version);
        if (self.supported_hvac_modes.len > 0) self.alloc.free(self.supported_hvac_modes);
        if (self.supported_fan_modes.len > 0) self.alloc.free(self.supported_fan_modes);
    }

    pub fn update(self: *Thermostat, json: std.json.ObjectMap) bool {
        var changed = false;
        if (json.get("offline")) |v| {
            if (self.offline != v.bool) {
                self.offline = v.bool;
                changed = true;
            }
        }
        if (json.get("currentTemperature")) |v| {
            const raw: f32 = switch (v) {
                .float => |f| @floatCast(f),
                .integer => |i| @floatFromInt(i),
                else => self.current_temperature,
            };
            const new_temp = @round(raw * 10.0) / 10.0;
            if (self.current_temperature != new_temp) {
                self.current_temperature = new_temp;
                changed = true;
            }
        }
        if (json.get("hvacMode")) |v| {
            if (v == .string) {
                if (std.meta.stringToEnum(HvacMode, v.string)) |mode| {
                    if (self.hvac_mode != mode) {
                        self.hvac_mode = mode;
                        changed = true;
                    }
                }
            }
        }
        if (json.get("hvacState")) |v| {
            const new_state: ?HvacState = if (v == .string) std.meta.stringToEnum(HvacState, v.string) else null;
            if (self.hvac_state != new_state) {
                self.hvac_state = new_state;
                changed = true;
            }
        }
        if (json.get("fanMode")) |v| {
            if (v == .string) {
                if (std.meta.stringToEnum(FanMode, v.string)) |mode| {
                    if (self.fan_mode != mode) {
                        self.fan_mode = mode;
                        changed = true;
                    }
                }
            }
        }
        if (json.get("fanState")) |v| {
            const new_state: ?FanState = if (v == .string) std.meta.stringToEnum(FanState, v.string) else null;
            if (self.fan_state != new_state) {
                self.fan_state = new_state;
                changed = true;
            }
        }
        if (json.get("setpoints")) |v| {
            if (v != .object) return changed;
            const sp = v.object;
            if (sp.get("cool")) |cool| {
                self.setpoints.cool = parseSetpoint(cool);
                changed = true;
            }
            if (sp.get("heat")) |heat| {
                self.setpoints.heat = parseSetpoint(heat);
                changed = true;
            }
            if (sp.get("auto")) |a| {
                self.setpoints.auto = parseSetpoint(a);
                changed = true;
            }
        }
        if (json.get("uiEnabled")) |v| {
            if (self.ui_enabled != v.bool) {
                self.ui_enabled = v.bool;
                changed = true;
            }
        }
        if (json.get("temperatureScale")) |v| {
            if (v == .string) {
                if (std.meta.stringToEnum(TemperatureScale, v.string)) |scale| {
                    if (self.temperature_scale != scale) {
                        self.temperature_scale = scale;
                        changed = true;
                    }
                }
            }
        }

        return changed;
    }

    // ========================================================================
    // Clone
    // ========================================================================
    pub fn clone(self: *const Thermostat, alloc: std.mem.Allocator) !Thermostat {
        // This would be a shallow copy
        // return self;

        var thermostat: Thermostat = .{
            .alloc = alloc,
            .id = "",
            .name = "",
            .driver = "",
            .manufacturer = "",
            .model_number = null,
            .serial_number = null,
            .firmware_version = "",
            .watts = self.watts,
            .alerts = self.alerts,
            .offline = self.offline,
            .current_temperature = self.current_temperature,
            .current_humidity = self.current_humidity,
            .min_auto_delta = self.min_auto_delta,
            .hvac_mode = self.hvac_mode,
            .hvac_state = self.hvac_state,
            .fan_mode = self.fan_mode,
            .fan_state = self.fan_state,
            .temperature_scale = self.temperature_scale,
            .humidity_scale = self.humidity_scale,
            .setpoints = self.setpoints,
            .ui_enabled = self.ui_enabled,
            .cycle_rate = self.cycle_rate,
            .supported_hvac_modes = &.{},
            .supported_fan_modes = &.{},
        };

        errdefer thermostat.deinit();

        thermostat.id = try dupeOwned(u8, alloc, self.id);
        thermostat.name = try dupeOwned(u8, alloc, self.name);
        thermostat.driver = try dupeOwned(u8, alloc, self.driver);
        thermostat.manufacturer = try dupeOwned(u8, alloc, self.manufacturer);
        thermostat.model_number = if (self.model_number) |s| try dupeOwned(u8, alloc, s) else null;
        thermostat.serial_number = if (self.serial_number) |s| try dupeOwned(u8, alloc, s) else null;
        thermostat.firmware_version = try dupeOwned(u8, alloc, self.firmware_version);

        thermostat.supported_fan_modes = try dupeOwned(FanMode, alloc, self.supported_fan_modes);
        thermostat.supported_hvac_modes = try dupeOwned(HvacMode, alloc, self.supported_hvac_modes);

        return thermostat;
    }

    fn dupeOwned(comptime T: type, alloc: std.mem.Allocator, s: []const T) ![]const T {
        return if (s.len > 0) try alloc.dupe(T, s) else &.{};
    }

    const wire_fields = .{
        .{ "hvac_mode", "hvacMode" },
        .{ "fan_mode", "fanMode" },
        .{ "ui_enabled", "uiEnabled" },
        .{ "temperature_scale", "temperatureScale" },
    };
    pub fn revert(self: *Thermostat, source: *const Thermostat) void {
        inline for (wire_fields) |f| @field(self, f[0]) = @field(source, f[0]);
        self.setpoints = source.setpoints;
    }

    pub fn diff(self: *const Thermostat, source: *const Thermostat, a: std.mem.Allocator, out: *std.json.ObjectMap) !bool {
        var changed = false;
        if (self.hvac_mode != source.hvac_mode) {
            try out.put(a, "hvacMode", .{ .string = @tagName(self.hvac_mode) });
            changed = true;
        }
        if (self.fan_mode != source.fan_mode) {
            try out.put(a, "fanMode", .{ .string = @tagName(self.fan_mode) });
            changed = true;
        }
        if (self.ui_enabled != source.ui_enabled) {
            if (self.ui_enabled) |v| {
                try out.put(a, "uiEnabled", .{ .bool = v });
                changed = true;
            }
        }
        if (self.temperature_scale != source.temperature_scale) {
            try out.put(a, "temperatureScale", .{ .string = @tagName(self.temperature_scale) });
            changed = true;
        }

        // Setpoints
        var sp_obj: std.json.ObjectMap = .empty;
        if (try diffSetpoint(a, self.setpoints.heat, source.setpoints.heat)) |v| try sp_obj.put(a, "heat", v);
        if (try diffSetpoint(a, self.setpoints.cool, source.setpoints.cool)) |v| try sp_obj.put(a, "cool", v);
        if (try diffSetpoint(a, self.setpoints.auto, source.setpoints.auto)) |v| try sp_obj.put(a, "auto", v);
        if (sp_obj.count() > 0) {
            try out.put(a, "setpoints", .{ .object = sp_obj });
            changed = true;
        }

        return changed;
    }

    fn diffSetpoint(a: std.mem.Allocator, self_sp: ?Setpoint, source_sp: ?Setpoint) !?std.json.Value {
        const sp = self_sp orelse return null;
        var obj: std.json.ObjectMap = .empty;
        if (source_sp == null or sp.value != source_sp.?.value) try obj.put(a, "value", .{ .float = sp.value });
        if (source_sp == null or sp.min != source_sp.?.min) try obj.put(a, "min", .{ .float = sp.min });
        if (source_sp == null or sp.max != source_sp.?.max) try obj.put(a, "max", .{ .float = sp.max });
        if (obj.count() == 0) return null;
        return .{ .object = obj };
    }

    fn parseSetpoint(val: ?std.json.Value) ?Setpoint {
        const unwrapped = val orelse return null;
        if (unwrapped != .object) return null;
        const obj = unwrapped.object;
        return .{
            .value = if (obj.get("value")) |v| switch (v) {
                .float => |f| @floatCast(f),
                .integer => |i| @floatFromInt(i),
                else => 0.0,
            } else 0.0,
            .min = if (obj.get("min")) |v| switch (v) {
                .float => |f| @floatCast(f),
                .integer => |i| @floatFromInt(i),
                else => 0.0,
            } else 0.0,
            .max = if (obj.get("max")) |v| switch (v) {
                .float => |f| @floatCast(f),
                .integer => |i| @floatFromInt(i),
                else => 0.0,
            } else 0.0,
        };
    }

    fn parseEnumArr(comptime T: type, alloc: std.mem.Allocator, val: ?std.json.Value) []const T {
        const items = (val orelse return &.{}).array.items;
        const result = alloc.alloc(T, items.len) catch return &.{};
        for (items, 0..) |item, idx| {
            result[idx] = std.meta.stringToEnum(T, item.string) orelse continue;
        }
        return result;
    }
};
