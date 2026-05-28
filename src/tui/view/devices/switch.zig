const std = @import("std");
const Panel = @import("../../components/panels.zig").Panel;
const Toggle = @import("../../components/toggle.zig").Toggle;
const Rect = @import("../../types.zig").Rect;
const KeyResult = @import("../../types.zig").KeyResult;
const Color = @import("../../color.zig");
const Switch = @import("../../state/models/switch.zig").Switch;

pub const SwitchDetail = struct {
    area: Rect,
    @"switch": *Switch,
    state_toggle: Toggle,
    cmd_buf: [256]u8 = undefined,

    pub fn init(area: Rect, s: *Switch) SwitchDetail {
        return .{
            .area = area,
            .@"switch" = s,
            .state_toggle = Toggle.init(area.x + 2, area.y + 2, .{ "On", "On" }),
        };
    }

    pub fn render(self: *SwitchDetail, stdout: std.Io.File, focused: bool) !u16 {
        const height: u16 = 4;
        var panel = Panel.init(self.area.x, self.area.y, self.area.width, height);
        try panel.draw(stdout, .{ self.@"switch".name, self.@"switch".id, null, null });

        var pos_buf: [32]u8 = undefined;

        const state_label_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + 2 });
        try stdout.writeAll(state_label_pos);
        try stdout.writeAll(Color.subtext0);
        try stdout.writeAll("State:");
        try stdout.writeAll(Color.reset);

        self.state_toggle.x = self.area.x + 2;
        self.state_toggle.y = self.area.y + 2;
        try self.state_toggle.render(stdout, self.@"switch".state == .on, focused);

        return height;
    }

    pub fn handleKey(self: *SwitchDetail, stdout: std.Io.File, c: u8) !KeyResult {
        _ = stdout;
        return switch (c) {
            '\r', '\n' => blk: {
                const new_state = if (self.@"switch".state == .on) "off" else "on";
                const cmd = try std.fmt.bufPrint(
                    &self.cmd_buf,
                    "UpdateDevices devices=[{{\"id\":\"{s}\",\"state\":\"{s}\"}}]",
                    .{ self.@"switch".id, new_state },
                );
                break :blk .{ .command = cmd };
            },
            else => .unhandled,
        };
    }
};
