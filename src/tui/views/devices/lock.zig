const std = @import("std");
const Panel = @import("../../components/panels.zig").Panel;
const Toggle = @import("../../components/toggle.zig").Toggle;
const Rect = @import("../../types.zig").Rect;
const KeyResult = @import("../../types.zig").KeyResult;
const Color = @import("../../color.zig");
const Lock = @import("../../state/models/lock.zig").Lock;

pub const LockDetail = struct {
    cursor: u8 = 0,
    area: Rect,
    lock: *Lock,
    lock_toggle: Toggle,
    cmd_buf: [256]u8 = undefined,

    const max_cursor: u8 = 0;

    pub fn init(area: Rect, lock: *Lock) LockDetail {
        return .{
            .area = area,
            .lock = lock,
            .lock_toggle = Toggle.init(
                area.x + 2,
                area.y + 2,
                .{ "Locked", "Unlocked" },
            ),
        };
    }

    pub fn render(self: *LockDetail, stdout: std.fs.File, focused: bool) !u16 {
        const height: u16 = 4;
        var panel = Panel.init(self.area.x, self.area.y, self.area.width, height);
        try panel.draw(stdout, .{ self.lock.name, self.lock.id, null, null });

        var pos_buf: [32]u8 = undefined;
        const pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + 2 });
        try stdout.writeAll(pos);
        try stdout.writeAll(Color.dim);
        try stdout.writeAll("State:");
        try stdout.writeAll(Color.reset);

        try self.lock_toggle.render(stdout, self.lock.state == .locked, focused and self.cursor == 0);

        return height;
    }

    pub fn handleKey(self: *LockDetail, stdout: std.fs.File, c: u8) !KeyResult {
        return switch (c) {
            'l' => blk: {
                if (self.cursor < max_cursor) self.cursor += 1;
                _ = try self.render(stdout, true);
                break :blk .unhandled;
            },
            'h' => blk: {
                if (self.cursor > 0) self.cursor -= 1;
                _ = try self.render(stdout, true);
                break :blk .unhandled;
            },
            '\r', '\n' => blk: {
                if (self.cursor == 0) {
                    const new_state = if (self.lock.state == .locked) "unlocked" else "locked";
                    const cmd = try std.fmt.bufPrint(
                        &self.cmd_buf,
                        "UpdateDevices devices=[{{\"id\":\"{s}\",\"state\":\"{s}\"}}]",
                        .{ self.lock.id, new_state },
                    );
                    break :blk .{ .command = cmd };
                }
                break :blk .unhandled;
            },
            else => .unhandled,
        };
    }
};
