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

const hvac_state_labels = [_][]const u8{ "❄️", "🔥", "Off" };
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

    fn hasSetpoints(self: *ThermostatDetail) bool {
        return self.getActiveSetpoint() != null or self.isAutoDualMode();
    }

    fn minCursor(self: *ThermostatDetail) u8 {
        return if (self.hasSetpoints()) 0 else self.modeCursor();
    }

    fn modeCursor(self: *ThermostatDetail) u8 {
        return if (self.isAutoDualMode()) 6 else 3;
    }

    fn fanCursor(self: *ThermostatDetail) u8 {
        return self.modeCursor() + 1;
    }

    fn uiCursor(self: *ThermostatDetail) u8 {
        return self.fanCursor() + 1;
    }

    fn maxCursor(self: *ThermostatDetail) u8 {
        return if (self.thermostat.ui_enabled != null) self.uiCursor() else self.fanCursor();
    }

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

    fn isAutoDualMode(self: *ThermostatDetail) bool {
        return self.thermostat.hvac_mode == .auto and
            self.thermostat.setpoints.auto == null and
            self.thermostat.setpoints.cool != null and
            self.thermostat.setpoints.heat != null;
    }

    fn setpointKey(self: *ThermostatDetail) []const u8 {
        return switch (self.thermostat.hvac_mode) {
            .cool => "cool",
            .heat => "heat",
            .auto => if (self.thermostat.setpoints.auto != null) "auto" else if (self.cursor <= 2) "cool" else "heat",
            .off => "",
        };
    }

    pub fn render(self: *ThermostatDetail, stdout: std.fs.File, focused: bool) !u16 {
        const min = self.minCursor();
        if (self.cursor < min) self.cursor = min;
        const dual_mode = self.isAutoDualMode();
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

        if (dual_mode) {
            // Dual mode labels: CSP CMin CMax HSP HMin HMax
            const csp_lbl = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + 11 });
            try stdout.writeAll(csp_lbl);
            try stdout.writeAll(Color.subtext0);
            try stdout.writeAll("CSP:");
            try stdout.writeAll(Color.reset);

            const cmin_lbl = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + 18 });
            try stdout.writeAll(cmin_lbl);
            try stdout.writeAll(Color.subtext0);
            try stdout.writeAll("CMin:");
            try stdout.writeAll(Color.reset);

            const cmax_lbl = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + 24 });
            try stdout.writeAll(cmax_lbl);
            try stdout.writeAll(Color.subtext0);
            try stdout.writeAll("CMax:");
            try stdout.writeAll(Color.reset);

            const hsp_lbl = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + 30 });
            try stdout.writeAll(hsp_lbl);
            try stdout.writeAll(Color.subtext0);
            try stdout.writeAll("HSP:");
            try stdout.writeAll(Color.reset);

            const hmin_lbl = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + 37 });
            try stdout.writeAll(hmin_lbl);
            try stdout.writeAll(Color.subtext0);
            try stdout.writeAll("HMin:");
            try stdout.writeAll(Color.reset);

            const hmax_lbl = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + 43 });
            try stdout.writeAll(hmax_lbl);
            try stdout.writeAll(Color.subtext0);
            try stdout.writeAll("HMax:");
            try stdout.writeAll(Color.reset);
        } else {
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
        }

        const mode_col: u16 = if (dual_mode) 49 else 31;
        const mode_label_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + mode_col });
        try stdout.writeAll(mode_label_pos);
        try stdout.writeAll(Color.subtext0);
        try stdout.writeAll("Mode:");
        try stdout.writeAll(Color.reset);

        const state_col: u16 = if (dual_mode) 56 else 39;
        const state_label_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + state_col });
        try stdout.writeAll(state_label_pos);
        try stdout.writeAll(Color.subtext0);
        try stdout.writeAll("State:");
        try stdout.writeAll(Color.reset);

        const fan_col: u16 = if (dual_mode) 63 else 46;
        const fan_label_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + fan_col });
        try stdout.writeAll(fan_label_pos);
        try stdout.writeAll(Color.subtext0);
        try stdout.writeAll("Fan:");
        try stdout.writeAll(Color.reset);

        const fan_state_col: u16 = if (dual_mode) 70 else 55;
        const fan_state_label_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + fan_state_col });
        try stdout.writeAll(fan_state_label_pos);
        try stdout.writeAll(Color.subtext0);
        try stdout.writeAll("FanState:");
        try stdout.writeAll(Color.reset);

        const delta_col: u16 = if (dual_mode) 80 else 65;
        const delta_label_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + delta_col });
        try stdout.writeAll(delta_label_pos);
        try stdout.writeAll(Color.subtext0);
        try stdout.writeAll("Delta:");
        try stdout.writeAll(Color.reset);

        const ui_col: u16 = if (dual_mode) 87 else 72;
        if (self.thermostat.ui_enabled != null) {
            const ui_label_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + ui_col });
            try stdout.writeAll(ui_label_pos);
            try stdout.writeAll(Color.subtext0);
            try stdout.writeAll("UI:");
            try stdout.writeAll(Color.reset);
        }

        // Row 2: current temp (right-aligned under "Current:")
        const temp_str = try std.fmt.bufPrint(&temp_buf, "{d:.1}\xc2\xb0", .{self.thermostat.current_temperature});
        const temp_display_len: u16 = @intCast(temp_str.len - 1); // ° is 2 bytes, 1 display char
        const temp_x = self.area.x + 2 + 8 - temp_display_len;
        const temp_val_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 2, temp_x });
        try stdout.writeAll(temp_val_pos);
        try stdout.writeAll(temp_str);

        // Row 2: setpoint, min, max values
        const active_sp = self.getActiveSetpoint();

        if (dual_mode) {
            const cool_sp = self.thermostat.setpoints.cool.?;
            const heat_sp = self.thermostat.setpoints.heat.?;

            // Cool setpoint value (under CSP: at x+11)
            const csp_focused = focused and self.cursor == 0;
            const cool_sp_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 2, self.area.x + 11 });
            try stdout.writeAll(cool_sp_pos);
            if (csp_focused) {
                try stdout.writeAll("\x1b[4m");
                try stdout.writeAll(Color.underline_peach);
            }
            const cool_sp_str = try std.fmt.bufPrint(&temp_buf, "{d:.1}\xc2\xb0", .{cool_sp.value});
            try stdout.writeAll(cool_sp_str);
            if (csp_focused) try stdout.writeAll(Color.reset);

            // Cool min value (right-justified under CMin: at x+18, 5 chars wide)
            const cmin_focused = focused and self.cursor == 1;
            const cool_min_str = try std.fmt.bufPrint(&temp_buf, "{d:.0}\xc2\xb0", .{cool_sp.min});
            const cool_min_dlen: u16 = @intCast(cool_min_str.len - 1);
            const cool_min_x = self.area.x + 18 + 5 - cool_min_dlen;
            const cool_min_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 2, cool_min_x });
            try stdout.writeAll(cool_min_pos);
            if (cmin_focused) {
                try stdout.writeAll("\x1b[4m");
                try stdout.writeAll(Color.underline_peach);
            }
            try stdout.writeAll(cool_min_str);
            if (cmin_focused) try stdout.writeAll(Color.reset);

            // Cool max value (under CMax: at x+24)
            const cmax_focused = focused and self.cursor == 2;
            const cool_max_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 2, self.area.x + 24 });
            try stdout.writeAll(cool_max_pos);
            if (cmax_focused) {
                try stdout.writeAll("\x1b[4m");
                try stdout.writeAll(Color.underline_peach);
            }
            const cool_max_str = try std.fmt.bufPrint(&temp_buf, "{d:.0}\xc2\xb0", .{cool_sp.max});
            try stdout.writeAll(cool_max_str);
            if (cmax_focused) try stdout.writeAll(Color.reset);

            // Heat setpoint value (under HSP: at x+30)
            const sp_focused = focused and self.cursor == 3;
            const heat_sp_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 2, self.area.x + 30 });
            try stdout.writeAll(heat_sp_pos);
            if (sp_focused) {
                try stdout.writeAll("\x1b[4m");
                try stdout.writeAll(Color.underline_peach);
            }
            const heat_sp_str = try std.fmt.bufPrint(&temp_buf, "{d:.1}\xc2\xb0", .{heat_sp.value});
            try stdout.writeAll(heat_sp_str);
            if (sp_focused) try stdout.writeAll(Color.reset);

            // Heat min value (right-justified under HMin: at x+37, 5 chars wide)
            const min_focused = focused and self.cursor == 4;
            const heat_min_str = try std.fmt.bufPrint(&temp_buf, "{d:.0}\xc2\xb0", .{heat_sp.min});
            const heat_min_dlen: u16 = @intCast(heat_min_str.len - 1);
            const heat_min_x = self.area.x + 37 + 5 - heat_min_dlen;
            const heat_min_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 2, heat_min_x });
            try stdout.writeAll(heat_min_pos);
            if (min_focused) {
                try stdout.writeAll("\x1b[4m");
                try stdout.writeAll(Color.underline_peach);
            }
            try stdout.writeAll(heat_min_str);
            if (min_focused) try stdout.writeAll(Color.reset);

            // Heat max value (under HMax: at x+43)
            const max_focused = focused and self.cursor == 5;
            const heat_max_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 2, self.area.x + 43 });
            try stdout.writeAll(heat_max_pos);
            if (max_focused) {
                try stdout.writeAll("\x1b[4m");
                try stdout.writeAll(Color.underline_peach);
            }
            const heat_max_str = try std.fmt.bufPrint(&temp_buf, "{d:.0}\xc2\xb0", .{heat_sp.max});
            try stdout.writeAll(heat_max_str);
            if (max_focused) try stdout.writeAll(Color.reset);
        } else {
            // Single setpoint mode
            const sp_focused = focused and self.cursor == 0;
            const sp_val_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 2, self.area.x + 11 });
            try stdout.writeAll(sp_val_pos);
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

            // Min
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

            // Max
            const max_focused = focused and self.cursor == 2;
            const max_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 2, self.area.x + 26 });
            try stdout.writeAll(max_pos);
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
        }

        // Row 2: controls
        self.hvac_mode_select.x = self.area.x + mode_col;
        self.hvac_mode_select.y = self.area.y + 2;
        self.hvac_mode_select.labels = self.hvac_label_buf[0..self.hvac_label_count];
        const hvac_idx = findModeIndex(HvacMode, self.thermostat.supported_hvac_modes, self.thermostat.hvac_mode);
        try self.hvac_mode_select.render(stdout, hvac_idx, focused and self.cursor == self.modeCursor());

        // Row 2: hvac state
        const hvac_state_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 2, self.area.x + state_col });
        try stdout.writeAll(hvac_state_pos);
        if (self.thermostat.hvac_state) |hs| {
            try stdout.writeAll(hvac_state_labels[@intFromEnum(hs)]);
        } else {
            try stdout.writeAll("--");
        }

        self.fan_mode_select.x = self.area.x + fan_col;
        self.fan_mode_select.y = self.area.y + 2;
        self.fan_mode_select.labels = self.fan_label_buf[0..self.fan_label_count];
        const fan_idx = findModeIndex(FanMode, self.thermostat.supported_fan_modes, self.thermostat.fan_mode);
        try self.fan_mode_select.render(stdout, fan_idx, focused and self.cursor == self.fanCursor());

        // Row 2: fan state
        const fan_state_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 2, self.area.x + fan_state_col });
        try stdout.writeAll(fan_state_pos);
        if (self.thermostat.fan_state) |fs| {
            try stdout.writeAll(fan_state_labels[@intFromEnum(fs)]);
        } else {
            try stdout.writeAll("--");
        }

        // Row 2: delta
        const delta_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 2, self.area.x + delta_col });
        try stdout.writeAll(delta_pos);
        if (self.thermostat.min_auto_delta) |d| {
            const delta_str = try std.fmt.bufPrint(&temp_buf, "{d}", .{d});
            try stdout.writeAll(delta_str);
        } else {
            try stdout.writeAll("--");
        }

        // Row 2: ui enabled
        if (self.thermostat.ui_enabled) |enabled| {
            const ui_focused = focused and self.cursor == self.uiCursor();
            const ui_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 2, self.area.x + ui_col });
            try stdout.writeAll(ui_pos);
            if (ui_focused) {
                try stdout.writeAll("\x1b[4m");
                try stdout.writeAll(Color.underline_peach);
            }
            if (enabled) {
                try stdout.writeAll(Color.green);
                try stdout.writeAll("✓");
            } else {
                try stdout.writeAll(Color.red);
                try stdout.writeAll("✘");
            }
            try stdout.writeAll(Color.reset);
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

        const min = self.minCursor();
        if (self.cursor < min) {
            self.cursor = min;
            _ = try self.render(stdout, true);
            return .unhandled;
        }

        return switch (c) {
            'l' => blk: {
                if (self.cursor < self.maxCursor()) {
                    self.cursor += 1;
                    _ = try self.render(stdout, true);
                }
                break :blk .unhandled;
            },
            'h' => blk: {
                if (self.cursor > min) {
                    self.cursor -= 1;
                    _ = try self.render(stdout, true);
                }
                break :blk .unhandled;
            },
            'j', 'k', '\r', '\n' => blk: {
                const dual = self.isAutoDualMode();
                const has_sp = self.getActiveSetpoint() != null or dual;
                if (dual and self.cursor <= 2) {
                    self.sp_field = switch (self.cursor) {
                        0 => .value,
                        1 => .min,
                        2 => .max,
                        else => unreachable,
                    };
                    self.sp_popup.title = switch (self.cursor) {
                        0 => "Set Cool Setpoint",
                        1 => "Set Cool Min",
                        2 => "Set Cool Max",
                        else => unreachable,
                    };
                    self.sp_popup.show();
                    _ = try self.render(stdout, true);
                } else if (self.cursor == (if (dual) @as(u8, 3) else 0)) {
                    if (has_sp) {
                        self.sp_field = .value;
                        self.sp_popup.title = if (dual) "Set Heat Setpoint" else "Set Temperature";
                        self.sp_popup.show();
                        _ = try self.render(stdout, true);
                    }
                } else if (self.cursor == (if (dual) @as(u8, 4) else 1)) {
                    if (has_sp) {
                        self.sp_field = .min;
                        self.sp_popup.title = if (dual) "Set Heat Min" else "Set Min";
                        self.sp_popup.show();
                        _ = try self.render(stdout, true);
                    }
                } else if (self.cursor == (if (dual) @as(u8, 5) else 2)) {
                    if (has_sp) {
                        self.sp_field = .max;
                        self.sp_popup.title = if (dual) "Set Heat Max" else "Set Max";
                        self.sp_popup.show();
                        _ = try self.render(stdout, true);
                    }
                } else if (self.cursor == self.modeCursor()) {
                    self.hvac_mode_select.open = true;
                    self.hvac_mode_select.cursor = findModeIndex(HvacMode, self.thermostat.supported_hvac_modes, self.thermostat.hvac_mode);
                    _ = try self.render(stdout, true);
                } else if (self.cursor == self.fanCursor()) {
                    self.fan_mode_select.open = true;
                    self.fan_mode_select.cursor = findModeIndex(FanMode, self.thermostat.supported_fan_modes, self.thermostat.fan_mode);
                    _ = try self.render(stdout, true);
                } else if (self.cursor == self.uiCursor()) {
                    if (self.thermostat.ui_enabled) |enabled| {
                        const val = if (enabled) "false" else "true";
                        const cmd = try std.fmt.bufPrint(
                            &self.cmd_buf,
                            "UpdateDevices devices=[{{\"id\":\"{s}\",\"uiEnabled\":{s}}}]",
                            .{ self.thermostat.id, val },
                        );
                        break :blk .{ .command = cmd };
                    }
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
