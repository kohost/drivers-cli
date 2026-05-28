const std = @import("std");
const Color = @import("../../color.zig");
const Panel = @import("../../components/panels.zig").Panel;
const Popup = @import("../../components/popup.zig").Popup;
const Rect = @import("../../types.zig").Rect;
const KeyResult = @import("../../types.zig").KeyResult;
const Alarm = @import("../../state/models/alarm.zig").Alarm;
const Toggle = @import("../../components/toggle.zig").Toggle;
const StateSwitch = @import("../../components/state_switch.zig").StateSwitch;
const StatusList = @import("../../components/status_list.zig").StatusList;

pub const AlarmDetail = struct {
    cursor: u8 = 0,
    area: Rect,
    alarm: *Alarm,
    chime_toggle: Toggle,
    security_switch: StateSwitch,
    zone_list: StatusList,
    credentials_open: bool = false,
    credentials_cursor: usize = 0,
    pending_action: PendingAction = .security,
    code_input: Popup,
    cmd_buf: [256]u8 = undefined,
    cols: u16,
    rows: u16,
    add_name_buf: [32]u8 = undefined,
    add_name_len: u8 = 0,
    add_code_buf: [32]u8 = undefined,
    add_code_len: u8 = 0,

    const PendingAction = enum { security, delete_credential, add_name, add_code, add_auth };

    fn maxCursor(self: *AlarmDetail) u8 {
        var max: u8 = 1; // 0=security, 1=zones
        if (self.alarm.credentials.len > 0) max += 1;
        if (self.alarm.chime != null) max += 1;
        return max;
    }

    const security_states = [_]StateSwitch.State{
        .{ .label = "Armed", .icon = "✔︎", .color = Color.green },
        .{ .label = "Armed", .icon = "✘", .color = Color.red },
        .{ .label = "Arming", .icon = "✔︎", .color = Color.green, .in_progress = true },
        .{ .label = "Disarming", .icon = "✘", .color = Color.red, .in_progress = true },
    };

    pub fn init(area: Rect, alarm: *Alarm, cols: u16, rows: u16) AlarmDetail {
        return .{
            .area = area,
            .alarm = alarm,
            .security_switch = StateSwitch.init(area.x + 2, area.y + 2, &security_states),
            .chime_toggle = Toggle.init(area.x + 2, area.y + 2, .{ "Chime", "Chime" }),
            .zone_list = StatusList.init(area.x + 20, area.y + 2),
            .code_input = Popup.init("Enter Code"),
            .cols = cols,
            .rows = rows,
        };
    }

    pub fn isAnimating(self: *AlarmDetail) bool {
        return self.security_switch.isAnimating();
    }

    pub fn render(self: *AlarmDetail, stdout: std.Io.File, focused: bool) !u16 {
        const zone_items = self.getZoneItems();
        const zones = zone_items.slice();
        const zone_extra: u16 = if (self.zone_list.open) @intCast(zones.len) else 0;
        const cred_extra: u16 = if (self.credentials_open) @intCast(self.alarm.credentials.len) else 0;
        const height: u16 = 4 + zone_extra + cred_extra;
        var panel = Panel.init(self.area.x, self.area.y, self.area.width, 4);
        try panel.draw(stdout, .{ self.alarm.name, self.alarm.id, null, null });

        var pos_buf: [32]u8 = undefined;

        // Row 1: labels
        const security_label_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + 2 });
        try stdout.writeAll(security_label_pos);
        try stdout.writeAll(Color.subtext0);
        try stdout.writeAll("Security Mode:");
        try stdout.writeAll(Color.reset);

        const zones_label_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + 20 });
        try stdout.writeAll(zones_label_pos);
        try stdout.writeAll(Color.subtext0);
        try stdout.writeAll("Zones:");
        try stdout.writeAll(Color.reset);

        if (self.alarm.credentials.len > 0) {
            const credentials_label_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + 34 });
            try stdout.writeAll(credentials_label_pos);
            try stdout.writeAll(Color.subtext0);
            try stdout.writeAll("Credentials:");
            try stdout.writeAll(Color.reset);
        }

        const chime_x = if (self.alarm.credentials.len > 0) self.area.x + 52 else self.area.x + 34;

        if (self.alarm.chime != null) {
            const chime_label_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, chime_x });
            try stdout.writeAll(chime_label_pos);
            try stdout.writeAll(Color.subtext0);
            try stdout.writeAll("Chime:");
            try stdout.writeAll(Color.reset);
        }

        // Row 2: controls (cursor 0=security, 1=zones, 2=chime/credentials) 3=chime
        self.security_switch.x = self.area.x + 2;
        self.security_switch.y = self.area.y + 2;
        self.security_switch.current = blk: {
            const mode = if (self.alarm.areas.len > 0) self.alarm.areas[0].security_mode else null;
            break :blk if (mode) |m| switch (m) {
                .armed => 0,
                .disarmed => 1,
                .arming => 2,
                .disarming => 3,
                else => 1,
            } else 1;
        };
        try self.security_switch.render(stdout, focused and self.cursor == 0);

        // Chime toggle
        if (self.alarm.chime) |chime| {
            const chime_cursor: u8 = if (self.alarm.credentials.len > 0) 3 else 2;
            self.chime_toggle.x = chime_x;
            self.chime_toggle.y = self.area.y + 2;
            try self.chime_toggle.render(stdout, chime, focused and self.cursor == chime_cursor);
        }

        // Render closed list first, open list last
        if (self.zone_list.open) {
            try self.renderCredentials(stdout, &pos_buf, focused);
            self.zone_list.x = self.area.x + 20;
            self.zone_list.y = self.area.y + 2;
            try self.zone_list.render(stdout, zones, focused and self.cursor == 1);
        } else if (self.credentials_open) {
            self.zone_list.x = self.area.x + 20;
            self.zone_list.y = self.area.y + 2;
            try self.zone_list.render(stdout, zones, focused and self.cursor == 1);
            try self.renderCredentials(stdout, &pos_buf, focused);
        } else {
            self.zone_list.x = self.area.x + 20;
            self.zone_list.y = self.area.y + 2;
            try self.zone_list.render(stdout, zones, focused and self.cursor == 1);
            try self.renderCredentials(stdout, &pos_buf, focused);
        }

        try self.code_input.render(stdout, self.cols, self.rows);

        return height;
    }

    const ZoneItems = struct {
        buf: [32]StatusList.Item = undefined,
        len: usize = 0,
        fn slice(self: *const ZoneItems) []const StatusList.Item {
            return self.buf[0..self.len];
        }
    };

    fn getZoneItems(self: *AlarmDetail) ZoneItems {
        var items = ZoneItems{};
        for (self.alarm.zones) |zone| {
            if (items.len >= 32) break;
            items.buf[items.len] = .{
                .id = zone.id,
                .name = zone.name,
                .secure = zone.secure,
                .bypassed = zone.bypassed,
                .offline = zone.offline,
            };
            items.len += 1;
        }
        return items;
    }

    fn renderCredentials(self: *AlarmDetail, stdout: std.Io.File, pos_buf: *[32]u8, focused: bool) !void {
        if (self.alarm.credentials.len == 0) return;
        const cred_focused = focused and self.cursor == 2;
        if (!self.credentials_open) {
            const pos = try std.fmt.bufPrint(pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 2, self.area.x + 34 });
            try stdout.writeAll(pos);
            if (cred_focused) {
                try stdout.writeAll(Color.peach);
                try stdout.writeAll("▶︎ ");
                try stdout.writeAll(Color.reset);
                try stdout.writeAll("\x1b[4m");
                try stdout.writeAll(Color.underline_peach);
            } else {
                try stdout.writeAll("▶︎ ");
            }
            var count_buf: [32]u8 = undefined;
            const count_str = try std.fmt.bufPrint(&count_buf, "{d} credentials", .{self.alarm.credentials.len});
            try stdout.writeAll(count_str);
            try stdout.writeAll(Color.reset);
        } else {
            var max_name: usize = 0;
            for (self.alarm.credentials) |cred| {
                if (cred.name.len > max_name) max_name = cred.name.len;
            }
            for (self.alarm.credentials, 0..) |cred, i| {
                const row = self.area.y + 2 + @as(u16, @intCast(i));
                const pos = try std.fmt.bufPrint(pos_buf, "\x1b[{d};{d}H", .{ row, self.area.x + 34 });
                try stdout.writeAll(pos);
                if (i == self.credentials_cursor and cred_focused) {
                    try stdout.writeAll(Color.peach);
                    try stdout.writeAll("▶︎ ");
                    try stdout.writeAll(Color.reset);
                } else {
                    try stdout.writeAll("  ");
                }
                try stdout.writeAll(cred.name);
                var pad = cred.name.len;
                while (pad < max_name + 1) : (pad += 1) {
                    try stdout.writeAll(" ");
                }
            }
            const next_row = self.area.y + 2 + @as(u16, @intCast(self.alarm.credentials.len));
            const clear_pos = try std.fmt.bufPrint(pos_buf, "\x1b[{d};{d}H\x1b[K", .{ next_row, self.area.x + 34 });
            try stdout.writeAll(clear_pos);
        }
    }

    pub fn handleKey(self: *AlarmDetail, stdout: std.Io.File, c: u8) !KeyResult {
        if (self.code_input.visible) {
            if (self.code_input.handleKey(c)) |code| {
                try self.code_input.clear(stdout, self.cols, self.rows);
                var w = std.io.Writer.fixed(&self.cmd_buf);
                switch (self.pending_action) {
                    .security => {
                        const security_mode = commandBlk: {
                            for (self.alarm.areas) |area| {
                                if (area.security_mode) |mode| switch (mode) {
                                    .armed, .arming, .intrusion, .medical, .fire => break :commandBlk "disarmed",
                                    else => {},
                                };
                            }
                            break :commandBlk "armed";
                        };
                        try w.print("UpdateDevices devices=[{{\"id\":\"{s}\",\"code\":\"{s}\",\"areas\":[", .{ self.alarm.id, code });
                        for (self.alarm.areas, 0..) |area, idx| {
                            if (idx > 0) try w.writeAll(",");
                            try w.print("{{\"id\":\"{s}\",\"securityMode\":\"{s}\"}}", .{ area.id, security_mode });
                        }
                        try w.writeAll("]}]");
                    },
                    .delete_credential => {
                        if (self.credentials_cursor < self.alarm.credentials.len) {
                            const cred = self.alarm.credentials[self.credentials_cursor];
                            try w.print("DeleteCredentials credentials=[{{\"id\":\"{s}\"}}] auth=\"{s}\"", .{ cred.id, code });
                        }
                    },
                    .add_name => {
                        @memcpy(self.add_name_buf[0..code.len], code);
                        self.add_name_len = @intCast(code.len);
                        self.pending_action = .add_code;
                        self.code_input.title = "Enter Credential";
                        self.code_input.show();
                        _ = try self.render(stdout, true);
                        return .unhandled;
                    },
                    .add_code => {
                        @memcpy(self.add_code_buf[0..code.len], code);
                        self.add_code_len = @intCast(code.len);
                        self.pending_action = .add_auth;
                        self.code_input.title = "Enter Auth";
                        self.code_input.show();
                        _ = try self.render(stdout, true);
                        return .unhandled;
                    },
                    .add_auth => {
                        const name = self.add_name_buf[0..self.add_name_len];
                        const credential = self.add_code_buf[0..self.add_code_len];
                        try w.print("AddCredentials credentials=[{{\"deviceId\":\"{s}\",\"name\":\"{s}\",\"credential\":\"{s}\"}}] auth=\"{s}\"", .{ self.alarm.id, name, credential, code });
                    },
                }
                self.pending_action = .security;
                self.code_input.title = "Enter Code";
                return .{ .command = w.buffered() };
            } else {
                if (!self.code_input.visible) {
                    self.pending_action = .security;
                    self.code_input.title = "Enter Code";
                    try self.code_input.clear(stdout, self.cols, self.rows);
                    return .redraw;
                }
                _ = try self.render(stdout, true);
                return .unhandled;
            }
        }

        if (self.zone_list.open) {
            return switch (c) {
                'j' => blk: {
                    if (self.zone_list.cursor < self.alarm.zones.len - 1)
                        self.zone_list.cursor += 1;
                    _ = try self.render(stdout, true);
                    break :blk .unhandled;
                },
                'k' => blk: {
                    if (self.zone_list.cursor > 0)
                        self.zone_list.cursor -= 1;
                    _ = try self.render(stdout, true);
                    break :blk .unhandled;
                },
                '\r', '\n' => blk: {
                    if (self.zone_list.cursor < self.alarm.zones.len) {
                        const zone = self.alarm.zones[self.zone_list.cursor];
                        const new_bypassed = if (zone.bypassed) |b| !b else true;
                        const bypass_str = if (new_bypassed) "true" else "false";
                        const cmd = try std.fmt.bufPrint(
                            &self.cmd_buf,
                            "UpdateDevices devices=[{{\"id\":\"{s}\",\"zones\":[{{\"id\":\"{s}\",\"bypassed\":{s}}}]}}]",
                            .{ self.alarm.id, zone.id, bypass_str },
                        );
                        break :blk .{ .command = cmd };
                    }
                    break :blk .unhandled;
                },
                'h', 'l', 0x1b => blk: {
                    try self.zone_list.close(stdout, self.alarm.zones.len);
                    _ = try self.render(stdout, true);
                    break :blk .unhandled;
                },
                else => .unhandled,
            };
        }

        if (self.credentials_open) {
            return switch (c) {
                'j' => blk: {
                    if (self.credentials_cursor < self.alarm.credentials.len - 1)
                        self.credentials_cursor += 1;
                    _ = try self.render(stdout, true);
                    break :blk .unhandled;
                },
                'k' => blk: {
                    if (self.credentials_cursor > 0)
                        self.credentials_cursor -= 1;
                    _ = try self.render(stdout, true);
                    break :blk .unhandled;
                },
                'a' => blk: {
                    self.pending_action = .add_name;
                    self.add_name_len = 0;
                    self.add_code_len = 0;
                    self.code_input.title = "Enter Name";
                    self.code_input.show();
                    _ = try self.render(stdout, true);
                    break :blk .unhandled;
                },
                'd' => blk: {
                    if (self.credentials_cursor < self.alarm.credentials.len) {
                        self.pending_action = .delete_credential;
                        self.code_input.title = "Enter Code";
                        self.code_input.show();
                        _ = try self.render(stdout, true);
                    }
                    break :blk .unhandled;
                },
                'h', 'l', 0x1b => blk: {
                    var buf: [32]u8 = undefined;
                    var row: u16 = 0;
                    while (row < self.alarm.credentials.len) : (row += 1) {
                        const pos = try std.fmt.bufPrint(&buf, "\x1b[{d};{d}H\x1b[K", .{ self.area.y + 2 + row, self.area.x + 34 });
                        try stdout.writeAll(pos);
                    }
                    self.credentials_open = false;
                    self.credentials_cursor = 0;
                    _ = try self.render(stdout, true);
                    break :blk .unhandled;
                },
                else => .unhandled,
            };
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
                if (self.cursor > 0) {
                    self.cursor -= 1;
                    _ = try self.render(stdout, true);
                }
                break :blk .unhandled;
            },
            'j', 'k' => blk: {
                if (self.cursor == 1) {
                    self.zone_list.open = true;
                    self.zone_list.cursor = 0;
                    _ = try self.render(stdout, true);
                }
                if (self.cursor == 2 and self.alarm.credentials.len > 0) {
                    self.credentials_open = true;
                    self.credentials_cursor = 0;
                    _ = try self.render(stdout, true);
                }
                break :blk .unhandled;
            },
            '\r', '\n' => blk: {
                if (self.cursor == 0) {
                    self.code_input.show();
                    _ = try self.render(stdout, true);
                    break :blk .unhandled;
                }
                if (self.cursor == 1) {
                    self.zone_list.open = true;
                    self.zone_list.cursor = 0;
                    _ = try self.render(stdout, true);
                    break :blk .unhandled;
                }
                if (self.cursor == 2 and self.alarm.credentials.len > 0) {
                    self.credentials_open = true;
                    self.credentials_cursor = 0;
                    _ = try self.render(stdout, true);
                    break :blk .unhandled;
                }
                break :blk .unhandled;
            },
            else => .unhandled,
        };
    }
};
