const std = @import("std");
const Panel = @import("../../components/panels.zig").Panel;
const Select = @import("../../components/select.zig").Select;
const Popup = @import("../../components/popup.zig").Popup;
const Rect = @import("../../types.zig").Rect;
const KeyResult = @import("../../types.zig").KeyResult;
const Color = @import("../../color.zig");
const Thermostat = @import("../../state/models/thermostat.zig").Thermostat;

const HvacMode = Thermostat.HvacMode;
const HvacState = Thermostat.HvacState;
const FanMode = Thermostat.FanMode;
const FanState = Thermostat.FanState;

const hvac_state_labels = [_][]const u8{ "Cooling", "Heating", "Off" };
const fan_state_labels = [_][]const u8{ "Off", "On", "Low", "Medium", "High" };

const hvac_labels = [_][]const u8{ "Off", "Heat", "Cool", "Auto" };
const hvac_values = [_][]const u8{ "off", "heat", "cool", "auto" };
const fan_labels = [_][]const u8{ "Off", "On", "Auto", "Low", "Medium", "High" };
const fan_values = [_][]const u8{ "off", "on", "auto", "low", "medium", "high" };

pub const ThermostatDetail = struct {
    cursor: u8 = 0,
    area: Rect,
    thermostat: *Thermostat,
    hvac_mode_select: Select,
    fan_mode_select: Select,
    hvac_label_buf: [4][]const u8 = undefined,
    hvac_label_count: u8 = 0,
    fan_label_buf: [6][]const u8 = undefined,
    fan_label_count: u8 = 0,
    sp_popup: Popup,
    sp_field: enum { value, min, max } = .value,
    cmd_buf: [256]u8 = undefined,
    cols: u16,
    rows: u16,

    const max_cursor: u8 = 4;

    fn findModeIndex(comptime T: type, modes: []const T, current: T) usize {
        for (modes, 0..) |mode, i| {
            if (mode == current) return i;
        }
        return 0;
    }

    pub fn init(area: Rect, thermostat: *Thermostat, cols: u16, rows: u16) ThermostatDetail {
        var self = ThermostatDetail{
            .area = area,
            .thermostat = thermostat,
            .hvac_mode_select = Select.init(area.x + 31, area.y + 2, &hvac_labels),
            .fan_mode_select = Select.init(area.x + 48, area.y + 2, &fan_labels),
            .sp_popup = Popup.init("Set Temperature"),
            .cols = cols,
            .rows = rows,
        };
        for (thermostat.supported_hvac_modes, 0..) |mode, i| {
            self.hvac_label_buf[i] = hvac_labels[@intFromEnum(mode)];
        }
        self.hvac_label_count = @intCast(thermostat.supported_hvac_modes.len);
        for (thermostat.supported_fan_modes, 0..) |mode, i| {
            self.fan_label_buf[i] = fan_labels[@intFromEnum(mode)];
        }
        self.fan_label_count = @intCast(thermostat.supported_fan_modes.len);
        return self;
    }

    fn getActiveSetpoint(self: *ThermostatDetail) ?Thermostat.Setpoint {
        return switch (self.thermostat.hvac_mode) {
            .cool => self.thermostat.setpoints.cool,
            .heat => self.thermostat.setpoints.heat,
            .auto => self.thermostat.setpoints.auto,
            .off => null,
        };
    }

    fn setpointKey(self: *ThermostatDetail) []const u8 {
        return switch (self.thermostat.hvac_mode) {
            .cool => "cool",
            .heat => "heat",
            .auto => "auto",
            .off => "",
        };
    }

    pub fn render(self: *ThermostatDetail, stdout: std.fs.File, focused: bool) !u16 {
        const height: u16 = 4;
        var panel = Panel.init(self.area.x, self.area.y, self.area.width, height);
        try panel.draw(stdout, .{ self.thermostat.name, self.thermostat.id, null, null });

        var pos_buf: [32]u8 = undefined;
        var temp_buf: [16]u8 = undefined;

        // Row 1: labels
        const temp_label_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + 2 });
        try stdout.writeAll(temp_label_pos);
        try stdout.writeAll(Color.subtext0);
        try stdout.writeAll("Current:");
        try stdout.writeAll(Color.reset);

        const sp_label_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + 11 });
        try stdout.writeAll(sp_label_pos);
        try stdout.writeAll(Color.subtext0);
        try stdout.writeAll("Setpoint:");
        try stdout.writeAll(Color.reset);

        const min_label_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + 21 });
        try stdout.writeAll(min_label_pos);
        try stdout.writeAll(Color.subtext0);
        try stdout.writeAll("Min:");
        try stdout.writeAll(Color.reset);

        const max_label_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + 26 });
        try stdout.writeAll(max_label_pos);
        try stdout.writeAll(Color.subtext0);
        try stdout.writeAll("Max:");
        try stdout.writeAll(Color.reset);

        const mode_label_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + 31 });
        try stdout.writeAll(mode_label_pos);
        try stdout.writeAll(Color.subtext0);
        try stdout.writeAll("Mode:");
        try stdout.writeAll(Color.reset);

        const state_label_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + 39 });
        try stdout.writeAll(state_label_pos);
        try stdout.writeAll(Color.subtext0);
        try stdout.writeAll("State:");
        try stdout.writeAll(Color.reset);

        const fan_label_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + 48 });
        try stdout.writeAll(fan_label_pos);
        try stdout.writeAll(Color.subtext0);
        try stdout.writeAll("Fan:");
        try stdout.writeAll(Color.reset);

        const fan_state_label_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + 56 });
        try stdout.writeAll(fan_state_label_pos);
        try stdout.writeAll(Color.subtext0);
        try stdout.writeAll("FanState:");
        try stdout.writeAll(Color.reset);

        const delta_label_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + 66 });
        try stdout.writeAll(delta_label_pos);
        try stdout.writeAll(Color.subtext0);
        try stdout.writeAll("Delta:");
        try stdout.writeAll(Color.reset);

        const ui_label_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + 73 });
        try stdout.writeAll(ui_label_pos);
        try stdout.writeAll(Color.subtext0);
        try stdout.writeAll("UIEnabled:");
        try stdout.writeAll(Color.reset);

        // Row 2: current temp (right-aligned under "Current:")
        const temp_str = try std.fmt.bufPrint(&temp_buf, "{d:.1}\xc2\xb0", .{self.thermostat.current_temperature});
        const temp_display_len: u16 = @intCast(temp_str.len - 1); // ° is 2 bytes, 1 display char
        const temp_x = self.area.x + 2 + 8 - temp_display_len;
        const temp_val_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 2, temp_x });
        try stdout.writeAll(temp_val_pos);
        try stdout.writeAll(temp_str);

        // Row 2: min (right-aligned under "Min:")
        const active_sp = self.getActiveSetpoint();
        const min_focused = focused and self.cursor == 1;
        if (active_sp) |sp| {
            const min_str = try std.fmt.bufPrint(&temp_buf, "{d:.0}\xc2\xb0", .{sp.min});
            const min_display_len: u16 = @intCast(min_str.len - 1);
            const min_x = self.area.x + 21 + 4 - min_display_len;
            const min_val_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 2, min_x });
            try stdout.writeAll(min_val_pos);
            if (min_focused) {
                try stdout.writeAll("\x1b[4m");
                try stdout.writeAll(Color.underline_peach);
            }
            try stdout.writeAll(min_str);
            if (min_focused) try stdout.writeAll(Color.reset);
        } else {
            const min_val_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 2, self.area.x + 23 });
            try stdout.writeAll(min_val_pos);
            try stdout.writeAll("--");
        }

        // Row 2: max
        const max_focused = focused and self.cursor == 2;
        const max_val_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 2, self.area.x + 26 });
        try stdout.writeAll(max_val_pos);
        if (active_sp) |sp| {
            if (max_focused) {
                try stdout.writeAll("\x1b[4m");
                try stdout.writeAll(Color.underline_peach);
            }
            const max_str = try std.fmt.bufPrint(&temp_buf, "{d:.0}\xc2\xb0", .{sp.max});
            try stdout.writeAll(max_str);
            if (max_focused) try stdout.writeAll(Color.reset);
        } else {
            try stdout.writeAll("--");
        }

        // Row 2: controls
        self.hvac_mode_select.x = self.area.x + 31;
        self.hvac_mode_select.y = self.area.y + 2;
        self.hvac_mode_select.labels = self.hvac_label_buf[0..self.hvac_label_count];
        const hvac_idx = findModeIndex(HvacMode, self.thermostat.supported_hvac_modes, self.thermostat.hvac_mode);
        try self.hvac_mode_select.render(stdout, hvac_idx, focused and self.cursor == 3);

        // Row 2: hvac state
        const hvac_state_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 2, self.area.x + 39 });
        try stdout.writeAll(hvac_state_pos);
        if (self.thermostat.hvac_state) |hs| {
            try stdout.writeAll(hvac_state_labels[@intFromEnum(hs)]);
        } else {
            try stdout.writeAll("--");
        }

        self.fan_mode_select.x = self.area.x + 48;
        self.fan_mode_select.y = self.area.y + 2;
        self.fan_mode_select.labels = self.fan_label_buf[0..self.fan_label_count];
        const fan_idx = findModeIndex(FanMode, self.thermostat.supported_fan_modes, self.thermostat.fan_mode);
        try self.fan_mode_select.render(stdout, fan_idx, focused and self.cursor == 4);

        // Row 2: fan state
        const fan_state_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 2, self.area.x + 56 });
        try stdout.writeAll(fan_state_pos);
        if (self.thermostat.fan_state) |fs| {
            try stdout.writeAll(fan_state_labels[@intFromEnum(fs)]);
        } else {
            try stdout.writeAll("--");
        }

        // Row 2: delta
        const delta_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 2, self.area.x + 66 });
        try stdout.writeAll(delta_pos);
        if (self.thermostat.min_auto_delta) |d| {
            const delta_str = try std.fmt.bufPrint(&temp_buf, "{d}", .{d});
            try stdout.writeAll(delta_str);
        } else {
            try stdout.writeAll("--");
        }

        // Row 2: ui enabled
        const ui_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 2, self.area.x + 73 });
        try stdout.writeAll(ui_pos);
        if (self.thermostat.ui_enabled) {
            try stdout.writeAll(Color.green);
            try stdout.writeAll("✓");
        } else {
            try stdout.writeAll(Color.red);
            try stdout.writeAll("✘");
        }
        try stdout.writeAll(Color.reset);

        // Row 2: setpoint value (left-aligned at x+11)
        const sp_val_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 2, self.area.x + 11 });
        try stdout.writeAll(sp_val_pos);
        const sp_focused = focused and self.cursor == 0;
        if (active_sp) |sp| {
            if (sp_focused) {
                try stdout.writeAll("\x1b[4m");
                try stdout.writeAll(Color.underline_peach);
            }
            const sp_str = try std.fmt.bufPrint(&temp_buf, "{d:.1}\xc2\xb0", .{sp.value});
            try stdout.writeAll(sp_str);
            if (sp_focused) try stdout.writeAll(Color.reset);
        } else {
            try stdout.writeAll("--");
        }

        try self.sp_popup.render(stdout, self.cols, self.rows);

        return height;
    }

    pub fn handleKey(self: *ThermostatDetail, stdout: std.fs.File, c: u8) !KeyResult {
        if (self.sp_popup.visible) {
            return self.handleSetpointPopup(stdout, c);
        }
        if (self.hvac_mode_select.open) {
            return self.handleHvacSelect(stdout, c);
        }
        if (self.fan_mode_select.open) {
            return self.handleFanSelect(stdout, c);
        }

        return switch (c) {
            'l' => blk: {
                if (self.cursor < max_cursor) {
                    self.cursor += 1;
                    _ = try self.render(stdout, true);
                }
                break :blk .unhandled;
            },
            'h' => blk: {
                if (self.cursor > 0) {
                    self.cursor -= 1;
                    _ = try self.render(stdout, true);
                }
                break :blk .unhandled;
            },
            'j', 'k', '\r', '\n' => blk: {
                if (self.cursor == 0) {
                    if (self.getActiveSetpoint() != null) {
                        self.sp_field = .value;
                        self.sp_popup.title = "Set Temperature";
                        self.sp_popup.show();
                        _ = try self.render(stdout, true);
                    }
                } else if (self.cursor == 1) {
                    if (self.getActiveSetpoint() != null) {
                        self.sp_field = .min;
                        self.sp_popup.title = "Set Min";
                        self.sp_popup.show();
                        _ = try self.render(stdout, true);
                    }
                } else if (self.cursor == 2) {
                    if (self.getActiveSetpoint() != null) {
                        self.sp_field = .max;
                        self.sp_popup.title = "Set Max";
                        self.sp_popup.show();
                        _ = try self.render(stdout, true);
                    }
                } else if (self.cursor == 3) {
                    self.hvac_mode_select.open = true;
                    self.hvac_mode_select.cursor = findModeIndex(HvacMode, self.thermostat.supported_hvac_modes, self.thermostat.hvac_mode);
                    _ = try self.render(stdout, true);
                } else if (self.cursor == 4) {
                    self.fan_mode_select.open = true;
                    self.fan_mode_select.cursor = findModeIndex(FanMode, self.thermostat.supported_fan_modes, self.thermostat.fan_mode);
                    _ = try self.render(stdout, true);
                }
                break :blk .unhandled;
            },
            else => .unhandled,
        };
    }

    fn handleHvacSelect(self: *ThermostatDetail, stdout: std.fs.File, c: u8) !KeyResult {
        return switch (c) {
            'j' => blk: {
                if (self.hvac_mode_select.cursor < self.hvac_mode_select.labels.len - 1)
                    self.hvac_mode_select.cursor += 1;
                _ = try self.render(stdout, true);
                break :blk .unhandled;
            },
            'k' => blk: {
                if (self.hvac_mode_select.cursor > 0)
                    self.hvac_mode_select.cursor -= 1;
                _ = try self.render(stdout, true);
                break :blk .unhandled;
            },
            '\r', '\n' => blk: {
                const mode = self.thermostat.supported_hvac_modes[self.hvac_mode_select.cursor];
                const val = hvac_values[@intFromEnum(mode)];
                try self.hvac_mode_select.close(stdout);
                _ = try self.render(stdout, true);
                const cmd = try std.fmt.bufPrint(
                    &self.cmd_buf,
                    "UpdateDevices devices=[{{\"id\":\"{s}\",\"hvacMode\":\"{s}\"}}]",
                    .{ self.thermostat.id, val },
                );
                break :blk .{ .command = cmd };
            },
            'h', 'l', 0x1b => blk: {
                try self.hvac_mode_select.close(stdout);
                _ = try self.render(stdout, true);
                break :blk .unhandled;
            },
            else => .unhandled,
        };
    }

    fn handleFanSelect(self: *ThermostatDetail, stdout: std.fs.File, c: u8) !KeyResult {
        return switch (c) {
            'j' => blk: {
                if (self.fan_mode_select.cursor < self.fan_mode_select.labels.len - 1)
                    self.fan_mode_select.cursor += 1;
                _ = try self.render(stdout, true);
                break :blk .unhandled;
            },
            'k' => blk: {
                if (self.fan_mode_select.cursor > 0)
                    self.fan_mode_select.cursor -= 1;
                _ = try self.render(stdout, true);
                break :blk .unhandled;
            },
            '\r', '\n' => blk: {
                const mode = self.thermostat.supported_fan_modes[self.fan_mode_select.cursor];
                const val = fan_values[@intFromEnum(mode)];
                try self.fan_mode_select.close(stdout);
                _ = try self.render(stdout, true);
                const cmd = try std.fmt.bufPrint(
                    &self.cmd_buf,
                    "UpdateDevices devices=[{{\"id\":\"{s}\",\"fanMode\":\"{s}\"}}]",
                    .{ self.thermostat.id, val },
                );
                break :blk .{ .command = cmd };
            },
            'h', 'l', 0x1b => blk: {
                try self.fan_mode_select.close(stdout);
                _ = try self.render(stdout, true);
                break :blk .unhandled;
            },
            else => .unhandled,
        };
    }

    fn handleSetpointPopup(self: *ThermostatDetail, stdout: std.fs.File, c: u8) !KeyResult {
        if (self.sp_popup.handleKey(c)) |val| {
            try self.sp_popup.clear(stdout, self.cols, self.rows);
            const sp_key = self.setpointKey();
            if (val.len == 0 or sp_key.len == 0) return .unhandled;
            const field_key = switch (self.sp_field) {
                .value => "value",
                .min => "min",
                .max => "max",
            };
            const cmd = try std.fmt.bufPrint(
                &self.cmd_buf,
                "UpdateDevices devices=[{{\"id\":\"{s}\",\"setpoints\":{{\"" ++ "{s}" ++ "\":{{\"" ++ "{s}" ++ "\":{s}}}}}}}]",
                .{ self.thermostat.id, sp_key, field_key, val },
            );
            return .{ .command = cmd };
        } else {
            if (!self.sp_popup.visible) {
                try self.sp_popup.clear(stdout, self.cols, self.rows);
                return .redraw;
            }
            _ = try self.render(stdout, true);
            return .unhandled;
        }
    }
};
