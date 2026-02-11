const std = @import("std");
const Panel = @import("../../components/panels.zig").Panel;
const Toggle = @import("../../components/toggle.zig").Toggle;
const Select = @import("../../components/select.zig").Select;
const Rect = @import("../../types.zig").Rect;
const KeyResult = @import("../../types.zig").KeyResult;
const Color = @import("../../color.zig");
const Lock = @import("../../state/models/lock.zig").Lock;

pub const LockDetail = struct {
    cursor: u8 = 0,
    area: Rect,
    lock: *Lock,
    lock_toggle: Toggle,
    mode_select: Select,
    cmd_buf: [256]u8 = undefined,

    const max_cursor: u8 = 1;
    const mode_labels = [_][]const u8{ "Auto Lock", "Hold Open", "Lockdown" };

    pub fn init(area: Rect, lock: *Lock) LockDetail {
        return .{
            .area = area,
            .lock = lock,
            .lock_toggle = Toggle.init(
                area.x + 2,
                area.y + 2,
                .{ "Locked", "Locked" },
            ),
            .mode_select = Select.init(
                area.x + 22,
                area.y + 1,
                &mode_labels,
            ),
        };
    }

    pub fn render(self: *LockDetail, stdout: std.fs.File, focused: bool) !u16 {
        const height: u16 = 4;
        var panel = Panel.init(self.area.x, self.area.y, self.area.width, height);
        try panel.draw(stdout, .{ self.lock.name, self.lock.id, null, null });

        var pos_buf: [32]u8 = undefined;

        // Row 1: labels
        const state_label_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + 2 });
        try stdout.writeAll(state_label_pos);
        try stdout.writeAll(Color.subtext0);
        try stdout.writeAll("State:");
        try stdout.writeAll(Color.reset);

        const mode_label_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + 15 });
        try stdout.writeAll(mode_label_pos);
        try stdout.writeAll(Color.subtext0);
        try stdout.writeAll("Mode:");
        try stdout.writeAll(Color.reset);

        // Row 2: controls
        self.lock_toggle.x = self.area.x + 2;
        self.lock_toggle.y = self.area.y + 2;
        try self.lock_toggle.render(stdout, self.lock.state == .locked, focused and self.cursor == 0);

        self.mode_select.x = self.area.x + 15;
        self.mode_select.y = self.area.y + 2;
        try self.mode_select.render(stdout, @intFromEnum(self.lock.mode), focused and self.cursor == 1);

        return height;
    }

    pub fn handleKey(self: *LockDetail, stdout: std.fs.File, c: u8) !KeyResult {
        if (self.mode_select.open) {
            return switch (c) {
                'j' => blk: {
                    if (self.mode_select.cursor < self.mode_select.labels.len - 1)
                        self.mode_select.cursor += 1;
                    _ = try self.render(stdout, true);
                    break :blk .unhandled;
                },
                'k' => blk: {
                    if (self.mode_select.cursor > 0)
                        self.mode_select.cursor -= 1;
                    _ = try self.render(stdout, true);
                    break :blk .unhandled;
                },
                '\r', '\n' => blk: {
                    const mode_str = switch (self.mode_select.cursor) {
                        0 => "autoLock",
                        1 => "holdOpen",
                        2 => "lockdown",
                        else => "autoLock",
                    };
                    try self.mode_select.close(stdout);
                    _ = try self.render(stdout, true);
                    const cmd = try std.fmt.bufPrint(
                        &self.cmd_buf,
                        "UpdateDevices devices=[{{\"id\":\"{s}\",\"mode\":\"{s}\"}}]",
                        .{ self.lock.id, mode_str },
                    );
                    break :blk .{ .command = cmd };
                },
                'h' => blk: {
                    try self.mode_select.close(stdout);
                    self.cursor = 0;
                    _ = try self.render(stdout, true);
                    break :blk .unhandled;
                },
                0x1b => blk: {
                    try self.mode_select.close(stdout);
                    _ = try self.render(stdout, true);
                    break :blk .unhandled;
                },
                else => .unhandled,
            };
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
            'j', 'k' => blk: {
                if (self.cursor == 1) {
                    self.mode_select.open = true;
                    self.mode_select.cursor = @intFromEnum(self.lock.mode);
                    _ = try self.render(stdout, true);
                    break :blk .unhandled;
                }
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
                if (self.cursor == 1) {
                    self.mode_select.open = true;
                    self.mode_select.cursor = @intFromEnum(self.lock.mode);
                    _ = try self.render(stdout, true);
                    return .unhandled;
                }
                break :blk .unhandled;
            },
            else => .unhandled,
        };
    }
};
