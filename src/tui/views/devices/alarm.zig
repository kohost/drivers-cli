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
    code_input: Popup,
    cmd_buf: [256]u8 = undefined,
    cols: u16,
    rows: u16,

    fn maxCursor(self: *AlarmDetail) u8 {
        return if (self.alarm.chime != null) 2 else 1;
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

    pub fn render(self: *AlarmDetail, stdout: std.fs.File, focused: bool) !u16 {
        const zone_items = self.getZoneItems();
        const zones = zone_items.slice();
        const zone_extra: u16 = if (self.zone_list.open) @intCast(zones.len) else 0;
        const height: u16 = 4 + zone_extra;
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

        if (self.alarm.chime != null) {
            const chime_label_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + 50 });
            try stdout.writeAll(chime_label_pos);
            try stdout.writeAll(Color.subtext0);
            try stdout.writeAll("Chime:");
            try stdout.writeAll(Color.reset);
        }

        // Row 2: controls (cursor 0=security, 1=zones, 2=chime)
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

        self.zone_list.x = self.area.x + 20;
        self.zone_list.y = self.area.y + 2;
        try self.zone_list.render(stdout, zones, focused and self.cursor == 1);

        if (self.alarm.chime) |chime| {
            self.chime_toggle.x = self.area.x + 50;
            self.chime_toggle.y = self.area.y + 2;
            try self.chime_toggle.render(stdout, chime, focused and self.cursor == 2);
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

    pub fn handleKey(self: *AlarmDetail, stdout: std.fs.File, c: u8) !KeyResult {
        if (self.code_input.visible) {
            if (self.code_input.handleKey(c)) |code| {
                try self.code_input.clear(stdout, self.cols, self.rows);
                const security_mode = commandBlk: {
                    for (self.alarm.areas) |area| {
                        if (area.security_mode) |mode| switch (mode) {
                            .armed, .arming, .intrusion, .medical, .fire => break :commandBlk "disarmed",
                            else => {},
                        };
                    }
                    break :commandBlk "armed";
                };
                var w = std.io.Writer.fixed(&self.cmd_buf);
                try w.print("UpdateDevices devices=[{{\"id\":\"{s}\",\"code\":\"{s}\",\"areas\":[", .{ self.alarm.id, code });
                for (self.alarm.areas, 0..) |area, idx| {
                    if (idx > 0) try w.writeAll(",");
                    try w.print("{{\"id\":\"{s}\",\"securityMode\":\"{s}\"}}", .{ area.id, security_mode });
                }
                try w.writeAll("]}]");
                return .{ .command = w.buffered() };
            } else {
                if (!self.code_input.visible) {
                    try self.code_input.clear(stdout, self.cols, self.rows);
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
                break :blk .unhandled;
            },
            else => .unhandled,
        };
    }
};
