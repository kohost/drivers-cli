const std = @import("std");
const Rect = @import("../types.zig").Rect;
const KeyResult = @import("../types.zig").KeyResult;
const Color = @import("../color.zig");

const emoji_map = std.StaticStringMap([]const u8).initComptime(.{
    .{ "alarm", "🚨" },
    .{ "dimmer", "💡" },
    .{ "lock", "🔒" },
    .{ "mediaSource", "📺" },
    .{ "thermostat", "🌡️" },
});
const Column = struct { name: []const u8, key: []const u8, width: u8, align_right: bool };
const columns = [_]Column{
    .{ .name = "Type", .key = "type", .width = 6, .align_right = true },
    .{ .name = "Id", .key = "id", .width = 8, .align_right = false },
    .{ .name = "Name", .key = "name", .width = 24, .align_right = false },
    .{ .name = "Model", .key = "modelNumber", .width = 16, .align_right = true },
    .{ .name = "Serial", .key = "serialNumber", .width = 16, .align_right = false },
    .{ .name = "Online", .key = "offline", .width = 8, .align_right = true },
    .{ .name = "Wattage", .key = "watts", .width = 8, .align_right = false },
    .{ .name = "Firmware", .key = "firmwareVersion", .width = 8, .align_right = false },
};

pub const DevicesView = struct {
    data: *const std.json.Parsed(std.json.Value),
    cursor: u8,
    area: Rect,
    row_count: u8,
    has_focus: bool = false,

    const Self = @This();

    pub fn init(area: Rect, data: *const std.json.Parsed(std.json.Value)) Self {
        return .{ .data = data, .cursor = 0, .area = area, .row_count = @intCast(data.value.array.items.len) };
    }

    pub fn render(self: *Self, stdout: std.fs.File, has_focus: bool) !void {
        self.has_focus = has_focus;
        try self.writeHeader(stdout);
        try self.writeRows(stdout);
    }

    fn writeHeader(self: *Self, stdout: std.fs.File) !void {
        const padding: u8 = 1;
        var pos_buf: [16]u8 = undefined;
        const pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + padding, self.area.x + padding });
        try stdout.writeAll(pos);

        for (columns) |col| {
            var buf: [16]u8 = undefined;
            const label = try std.fmt.bufPrint(&buf, "{s}:", .{col.name});
            const len: u8 = @intCast(label.len);
            if (col.align_right) {
                var pad = col.width - len;
                while (pad > 0) : (pad -= 1) try stdout.writeAll(" ");
                try stdout.writeAll(label);
            } else {
                try stdout.writeAll(label);
                var pad: u8 = len;
                while (pad < col.width) : (pad += 1) try stdout.writeAll(" ");
            }
            try stdout.writeAll(" ");
        }
    }

    fn writeRows(
        self: *Self,
        stdout: std.fs.File,
    ) !void {
        const Y_PAD: u8 = 2;
        const X_PAD: u8 = 1;
        var pos_buf: [16]u8 = undefined;
        const xPos = self.area.x + X_PAD;

        // Loop through devices
        for (self.data.value.array.items, 0..) |device, idx| {
            // Move cursor
            const yPos = self.area.y + @as(u8, @intCast(idx)) + Y_PAD;
            const row_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ yPos, xPos });
            try stdout.writeAll(row_pos);

            // Highlight focused row
            //             const is_focused: bool = if (focus) |f| idx == f else false;
            const is_focused = idx == self.cursor;
            const indicator_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ yPos, self.area.x });
            try stdout.writeAll(indicator_pos);
            try stdout.writeAll(Color.teal);
            if (self.has_focus and is_focused) {
                try stdout.writeAll("┃");
            } else {
                try stdout.writeAll(Color.dim);
                try stdout.writeAll("│");
            }
            try stdout.writeAll(Color.reset);

            // Write data
            var int_buff: [8]u8 = undefined;
            for (columns, 0..) |col, col_idx| {
                if (device.object.get(col.key)) |val| {
                    var data_len: u8 = 1;

                    // Alternate colors
                    if (col_idx % 2 != 0) {
                        try stdout.writeAll(Color.teal);
                        try stdout.writeAll(Color.dim);
                    }

                    // Make everything a printable string
                    const data: []const u8 = switch (val) {
                        .string => |s| blk: {
                            data_len = @intCast(s.len);
                            if (std.mem.eql(u8, "Type", col.name)) {
                                if (emoji_map.get(s)) |e| {
                                    data_len = 2;
                                    break :blk e;
                                }
                            }
                            break :blk s;
                        },
                        .integer => |n| blk: {
                            const s = try std.fmt.bufPrint(&int_buff, "{d}", .{n});
                            data_len = @intCast(s.len);
                            break :blk s;
                        },
                        .bool => |b| if (b != std.mem.eql(u8, "Online", col.name)) "✓" else "𝑥",
                        else => "-",
                    };

                    // Format data based on alignment
                    if (col.align_right) {
                        var pad: u8 = col.width - data_len;
                        while (pad > 0) : (pad -= 1) try stdout.writeAll(" ");
                        try stdout.writeAll(data);
                    } else {
                        try stdout.writeAll(data);
                        while (data_len < col.width) : (data_len += 1) try stdout.writeAll(" ");
                    }
                } else {
                    // Key is missing, still need to add padding
                    if (col.align_right) {
                        var pad: u8 = col.width - 1;
                        while (pad > 0) : (pad -= 1) try stdout.writeAll(" ");
                        try stdout.writeAll("-");
                    } else {
                        var pad: u8 = 1;
                        try stdout.writeAll("-");
                        while (pad < col.width) : (pad += 1) {
                            try stdout.writeAll(" ");
                        }
                    }
                }

                try stdout.writeAll(" ");
                try stdout.writeAll(Color.reset);
            }
        }
    }

    fn updateFocus(self: *Self, stdout: std.fs.File, idx: u8, is_focused: bool) !void {
        var pos_buf: [16]u8 = undefined;
        const yPos = self.area.y + idx + 2;
        const pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ yPos, self.area.x });
        try stdout.writeAll(pos);
        try stdout.writeAll(Color.teal);
        if (is_focused) {
            try stdout.writeAll("┃");
        } else {
            try stdout.writeAll(Color.dim);
            try stdout.writeAll("│");
        }
        try stdout.writeAll(Color.reset);
    }

    pub fn handleKey(self: *Self, stdout: std.fs.File, c: u8) !KeyResult {
        switch (c) {
            'j' => {
                const old = self.cursor;
                try self.updateFocus(stdout, old, false);
                self.cursor = if (old < self.row_count - 1) old + 1 else 0;
                try self.updateFocus(stdout, self.cursor, true);
                return .unhandled;
            },
            'k' => {
                if (self.cursor > 0) {
                    const old = self.cursor;
                    self.cursor -= 1;
                    try self.updateFocus(stdout, old, false);
                    try self.updateFocus(stdout, self.cursor, true);
                    return .unhandled;
                }
                return .{ .move_to = .up }; // cursor at 0, move to menu
            },
            else => return .unhandled,
        }
    }
};
