const std = @import("std");
const Rect = @import("../types.zig").Rect;
const KeyResult = @import("../types.zig").KeyResult;
const Data = @import("../types.zig").Data;
const Color = @import("../color.zig");

const emoji_map = std.StaticStringMap([]const u8).initComptime(.{
    .{ "alarm", "🚨" },
    .{ "dimmer", "💡" },
    .{ "lock", "🔒" },
    .{ "mediaSource", "📺" },
    .{ "thermostat", "🌡️" },
    .{ "motionSensor", "🏃🏼‍♂️" },
});
const Column = struct { name: []const u8, key: []const u8, align_right: bool };
const columns = [_]Column{
    .{ .name = "Type", .key = "type", .align_right = true },
    .{ .name = "Id", .key = "id", .align_right = false },
    .{ .name = "Name", .key = "name", .align_right = false },
    .{ .name = "Model", .key = "modelNumber", .align_right = true },
    .{ .name = "Serial", .key = "serialNumber", .align_right = false },
    .{ .name = "Online", .key = "offline", .align_right = true },
    .{ .name = "Wattage", .key = "watts", .align_right = false },
    .{ .name = "Firmware", .key = "firmwareVersion", .align_right = false },
};

pub const DevicesView = struct {
    data: *const Data,
    cursor: u8,
    area: Rect,
    row_count: u8,
    has_focus: bool = false,
    last_key_timestamp: i64 = 0,
    last_key: u8 = 0,
    selected: [][]const u8,
    selected_len: u8 = 0,
    column_widths: [columns.len]u8,

    const Self = @This();

    pub fn init(area: Rect, data: *const Data, buf: [][]const u8) Self {
        const column_widths: [columns.len]u8 = computeColumnWidths(data);

        const row_count: u8 = switch (data.*) {
            .json => |json| blk: {
                const items = json.value.object.get("data") orelse break :blk 0;
                break :blk @intCast(items.array.items.len);
            },
            .err => 0,
        };
        return .{ .data = data, .cursor = 0, .area = area, .row_count = row_count, .selected = buf, .selected_len = 0, .column_widths = column_widths };
    }

    pub fn render(self: *Self, stdout: std.fs.File, has_focus: bool) !void {
        self.has_focus = has_focus;
        try self.writeHeader(stdout);
        try self.writeRows(stdout);
    }

    fn computeColumnWidths(data: *const Data) [columns.len]u8 {
        var widths: [columns.len]u8 = undefined;

        for (columns, 0..) |col, idx| {
            widths[idx] = @intCast(col.name.len + 1);
        }

        switch (data.*) {
            .json => |json| {
                const items = json.value.object.get("data") orelse return widths;

                for (items.array.items) |device| {
                    for (columns, 0..) |col, idx| {
                        if (device.object.get(col.key)) |val| {
                            if (val == .string) {
                                widths[idx] = @max(widths[idx], @as(u8, @intCast(val.string.len)));
                            }
                        }
                    }
                }
            },
            .err => {},
        }
        return widths;
    }

    fn writeHeader(self: *Self, stdout: std.fs.File) !void {
        const padding: u8 = 1;
        var pos_buf: [16]u8 = undefined;
        const pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + padding, self.area.x + padding });
        try stdout.writeAll(pos);

        for (columns, 0..) |col, idx| {
            var buf: [16]u8 = undefined;
            const label = try std.fmt.bufPrint(&buf, "{s}:", .{col.name});
            const len: u8 = @intCast(label.len);
            if (col.align_right) {
                var pad = self.column_widths[idx] - len;
                while (pad > 0) : (pad -= 1) try stdout.writeAll(" ");
                try stdout.writeAll(label);
            } else {
                try stdout.writeAll(label);
                var pad: u8 = len;
                while (pad < self.column_widths[idx]) : (pad += 1) try stdout.writeAll(" ");
            }
            try stdout.writeAll(" ");
        }
    }

    fn writeRows(self: *Self, stdout: std.fs.File) !void {
        var pos_buf: [16]u8 = undefined;

        switch (self.data.*) {
            .err => |msg| {
                const yPos = self.area.y + self.area.height - 1;
                const xPos = self.area.x + 1;
                const row_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ yPos, xPos });
                try stdout.writeAll(row_pos);
                try stdout.writeAll(Color.teal);
                try stdout.writeAll(Color.dim);
                try stdout.writeAll("┘");
                try stdout.writeAll(Color.reset);
                try stdout.writeAll(Color.pink);
                try stdout.writeAll(msg);
                try stdout.writeAll(Color.teal);
                try stdout.writeAll(Color.dim);
                try stdout.writeAll("└");
                try stdout.writeAll(Color.reset);
            },
            .json => |json| {
                for (0..self.row_count) |idx| {
                    try self.writeRow(stdout, json, @intCast(idx));
                }
            },
        }
    }

    fn writeRow(self: *Self, stdout: std.fs.File, json: std.json.Parsed(std.json.Value), idx: u8) !void {
        var pos_buf: [16]u8 = undefined;
        var int_buff: [8]u8 = undefined;
        const Y_PAD: u8 = 2;
        const X_PAD: u8 = 1;

        const yPos = self.area.y + idx + Y_PAD;
        const xPos = self.area.x + X_PAD;

        // Move to row position
        const row_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ yPos, xPos });
        try stdout.writeAll(row_pos);

        const devices = json.value.object.get("data") orelse return;
        const device = devices.array.items[idx];
        const id = if (device.object.get("id")) |v| v.string else "";
        const is_selected = self.isSelected(id);

        // Set background if selected
        if (is_selected) {
            try stdout.writeAll(Color.bg_teal_dim);
        }

        // Fill interior width (panel width minus 2 borders)
        var fill: u16 = 0;
        while (fill < self.area.width - 2) : (fill += 1) {
            try stdout.writeAll(" ");
        }
        try stdout.writeAll(Color.reset);

        // Focus indicator
        const is_focused = idx == self.cursor;
        const indicator_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ yPos, self.area.x });
        try stdout.writeAll(indicator_pos);
        try stdout.writeAll(Color.teal);
        if (self.has_focus and is_focused) {
            try stdout.writeAll("┃");
        } else {
            try stdout.writeAll(Color.dim);
            if (is_selected) {
                try stdout.writeAll("▐");
            } else {
                try stdout.writeAll("│");
            }
        }
        try stdout.writeAll(Color.reset);
        if (is_selected) try stdout.writeAll(Color.bg_teal_dim);

        // Write columns
        for (columns, 0..) |col, col_idx| {
            if (device.object.get(col.key)) |val| {
                var data_len: u8 = 1;

                if (col_idx % 2 != 0) {
                    try stdout.writeAll(Color.teal);
                    try stdout.writeAll(Color.dim);
                }

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

                if (col.align_right) {
                    var pad: u8 = self.column_widths[col_idx] - data_len;
                    while (pad > 0) : (pad -= 1) try stdout.writeAll(" ");
                    try stdout.writeAll(data);
                } else {
                    try stdout.writeAll(data);
                    while (data_len < self.column_widths[col_idx]) : (data_len += 1) try stdout.writeAll(" ");
                }
            } else {
                if (col.align_right) {
                    var pad: u8 = self.column_widths[col_idx] - 1;
                    while (pad > 0) : (pad -= 1) try stdout.writeAll(" ");
                    try stdout.writeAll("-");
                } else {
                    try stdout.writeAll("-");
                    var pad: u8 = 1;
                    while (pad < self.column_widths[col_idx]) : (pad += 1) try stdout.writeAll(" ");
                }
            }

            try stdout.writeAll(" ");
            try stdout.writeAll(Color.reset);
            if (is_selected) try stdout.writeAll(Color.bg_teal_dim);
        }

        try stdout.writeAll(Color.reset);
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

    fn isSelected(self: *Self, id: []const u8) bool {
        for (self.selected[0..self.selected_len]) |sel_id| {
            if (std.mem.eql(u8, sel_id, id)) return true;
        }
        return false;
    }

    fn selectItem(self: *Self, stdout: std.fs.File) !void {
        switch (self.data.*) {
            .err => return,
            .json => |json| {
                const devices = json.value.object.get("data") orelse return;
                const item = devices.array.items[self.cursor];
                const val = item.object.get("id") orelse return;
                const id = val.string;

                for (self.selected[0..self.selected_len]) |sel_id| {
                    if (std.mem.eql(u8, sel_id, id)) return;
                }

                self.selected[self.selected_len] = id;
                self.selected_len += 1;
                try self.writeRow(stdout, json, self.cursor);
            },
        }
    }

    fn deselectItem(self: *Self, stdout: std.fs.File) !void {
        switch (self.data.*) {
            .err => return,
            .json => |json| {
                const devices = json.value.object.get("data") orelse return;
                const item = devices.array.items[self.cursor];
                const val = item.object.get("id") orelse return;
                const id = val.string;

                for (self.selected[0..self.selected_len], 0..) |sel_id, i| {
                    if (std.mem.eql(u8, sel_id, id)) {
                        self.selected[i] = self.selected[self.selected_len - 1];
                        self.selected_len -= 1;
                        try self.writeRow(stdout, json, self.cursor);
                        return;
                    }
                }
            },
        }
    }

    pub fn handleKey(self: *Self, stdout: std.fs.File, c: u8) !KeyResult {
        const now = std.time.milliTimestamp();
        const step: u8 = if (now - self.last_key_timestamp < 100) 2 else 1;
        const prev_key = self.last_key;
        self.last_key_timestamp = now;
        self.last_key = c;

        switch (c) {
            'j' => {
                const old = self.cursor;
                try self.updateFocus(stdout, old, false);
                self.cursor = @min(old + step, self.row_count - 1);
                try self.updateFocus(stdout, self.cursor, true);
                return .unhandled;
            },
            'k' => {
                if (self.cursor > 0) {
                    const old = self.cursor;
                    try self.updateFocus(stdout, old, false);
                    self.cursor = if (step > old) 0 else old - step;
                    try self.updateFocus(stdout, self.cursor, true);
                    return .unhandled;
                }
                return .{ .move_to = .up };
            },
            'l' => { // select current item
                try self.selectItem(stdout);
                return .unhandled;
            },
            'h' => { // deselect current item
                try self.deselectItem(stdout);
                return .unhandled;
            },
            'H' => { // low
                const old = self.cursor;
                try self.updateFocus(stdout, old, false);
                self.cursor = 0;
                try self.updateFocus(stdout, self.cursor, true);
                self.last_key = 0; // reset so ggg doesn't trigger again
                return .unhandled;
            },
            'M' => { // middle
                const old = self.cursor;
                try self.updateFocus(stdout, old, false);
                self.cursor = self.row_count / 2;
                try self.updateFocus(stdout, self.cursor, true);
                return .unhandled;
            },
            'L' => { // high
                const old = self.cursor;
                try self.updateFocus(stdout, old, false);
                self.cursor = self.row_count - 1;
                try self.updateFocus(stdout, self.cursor, true);
                return .unhandled;
            },
            'G' => { // Shift+g = bottom
                const old = self.cursor;
                try self.updateFocus(stdout, old, false);
                self.cursor = self.row_count - 1;
                try self.updateFocus(stdout, self.cursor, true);
                return .unhandled;
            },
            'g' => {
                if (prev_key == 'g') { // gg = top
                    const old = self.cursor;
                    try self.updateFocus(stdout, old, false);
                    self.cursor = 0;
                    try self.updateFocus(stdout, self.cursor, true);
                    self.last_key = 0; // reset so ggg doesn't trigger again
                }
                return .unhandled;
            },
            else => return .unhandled,
        }
    }
};
