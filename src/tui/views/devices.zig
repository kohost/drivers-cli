const std = @import("std");
const Panel = @import("../components/panels.zig").Panel;
const Rect = @import("../types.zig").Rect;
const KeyResult = @import("../types.zig").KeyResult;
const AppState = @import("../state/state.zig").AppState;
const Device = @import("../state/models/device.zig").Device;
const Config = @import("../../main.zig").Config;
const Color = @import("../color.zig");
const DetailView = @import("detail_view.zig").DetailView;

const emoji_map = std.StaticStringMap([]const u8).initComptime(.{
    .{ "alarm", "🚨" },
    .{ "dimmer", "💡" },
    .{ "lock", "🔒" },
    .{ "mediaSource", "📺" },
    .{ "thermostat", "🌡️" },
    .{ "motionSensor", "🏃🏼‍♂️" },
});

const Column = struct {
    name: []const u8,
    align_right: bool,
};

const columns = [_]Column{
    .{ .name = "Type", .align_right = true },
    .{ .name = "Id", .align_right = false },
    .{ .name = "Name", .align_right = false },
    .{ .name = "Model", .align_right = true },
    .{ .name = "Serial", .align_right = false },
    .{ .name = "Online", .align_right = true },
    .{ .name = "Wattage", .align_right = false },
    .{ .name = "Firmware", .align_right = false },
};

pub const DevicesView = struct {
    state: *AppState,
    cursor: u8,
    area: Rect,
    row_count: u8,
    has_focus: bool = false,
    detail_focus: bool = false,
    last_key_timestamp: i64 = 0,
    last_key: u8 = 0,
    selected: [][]const u8,
    selected_len: u8 = 0,
    column_widths: [columns.len]u8,
    config: Config,
    detail: DetailView = .none,

    const Self = @This();

    pub fn init(cfg: Config, area: Rect, state: *AppState, buf: [][]const u8) Self {
        const column_widths = computeColumnWidths(state);
        const row_count: u8 = @intCast(state.devices.items.len);

        return .{
            .state = state,
            .cursor = 0,
            .area = area,
            .row_count = row_count,
            .selected = buf,
            .selected_len = 0,
            .column_widths = column_widths,
            .config = cfg,
        };
    }

    pub fn render(self: *Self, stdout: std.fs.File, has_focus: bool) !void {
        self.has_focus = has_focus;

        var panel = Panel.init(self.area.x, self.area.y, self.area.width, self.row_count + 3);
        var port_buf: [32]u8 = undefined;
        const port_str = try std.fmt.bufPrint(&port_buf, "{s}:{d}", .{ self.config.host, self.config.port });
        const manufacturer: ?[]const u8 = if (self.state.system) |sys| sys.manufacturer else null;
        const titles: [4]?[]const u8 = .{ manufacturer, port_str, null, null };
        try panel.draw(stdout, titles);
        try self.writeHeader(stdout);
        try self.writeRows(stdout);

        try if (has_focus) self.renderDetail(stdout) else self.clearDetail(stdout);
    }

    fn computeColumnWidths(state: *AppState) [columns.len]u8 {
        var widths: [columns.len]u8 = undefined;

        for (columns, 0..) |col, idx| {
            widths[idx] = @intCast(col.name.len + 1);
        }

        for (state.devices.items) |device| {
            widths[0] = @max(widths[0], 2);
            widths[1] = @max(widths[1], @as(u8, @intCast(device.id().len)));
            widths[2] = @max(widths[2], @as(u8, @intCast(device.name().len)));
            widths[3] = @max(widths[3], @as(u8, @intCast(device.modelNumber().len)));
            widths[4] = @max(widths[4], @as(u8, @intCast(device.serialNumber().len)));
            widths[5] = @max(widths[5], 1);
            var watts_buf: [8]u8 = undefined;
            const watts_str = std.fmt.bufPrint(&watts_buf, "{d}", .{device.watts()}) catch "0";
            widths[6] = @max(widths[6], @as(u8, @intCast(watts_str.len)));
            widths[7] = @max(widths[7], @as(u8, @intCast(device.firmwareVersion().len)));
        }

        return widths;
    }

    fn writeHeader(self: *Self, stdout: std.fs.File) !void {
        var pos_buf: [16]u8 = undefined;
        const pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.area.y + 1, self.area.x + 2 });
        try stdout.writeAll(pos);
        try stdout.writeAll(Color.dim);

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
        try stdout.writeAll(Color.reset);
    }

    fn writeRows(self: *Self, stdout: std.fs.File) !void {
        for (self.state.devices.items, 0..) |_, idx| {
            try self.writeRow(stdout, @intCast(idx));
        }
    }

    fn writeRow(self: *Self, stdout: std.fs.File, idx: u8) !void {
        var pos_buf: [16]u8 = undefined;
        var int_buf: [8]u8 = undefined;
        const Y_PAD: u8 = 2;
        const yPos = self.area.y + idx + Y_PAD;

        const row_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ yPos, self.area.x + 1 });
        try stdout.writeAll(row_pos);

        const device = self.state.devices.items[idx];
        const id = device.id();
        const is_selected = self.isSelected(id);

        if (is_selected) {
            try stdout.writeAll(Color.bg_surface0);
        }

        var fill: u16 = 0;
        while (fill < self.area.width - 2) : (fill += 1) {
            try stdout.writeAll(" ");
        }
        try stdout.writeAll(Color.reset);

        const is_focused = idx == self.cursor;
        const indicator_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ yPos, self.area.x });
        try stdout.writeAll(indicator_pos);
        try stdout.writeAll(Color.teal);
        if (self.has_focus and is_focused and !self.detail_focus) {
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
        if (is_selected) try stdout.writeAll(Color.bg_surface0);
        try stdout.writeAll(" ");

        const col_values = [_]struct { data: []const u8, len: u8 }{
            .{ .data = emoji_map.get(device.deviceType()) orelse "?", .len = 2 },
            .{ .data = device.id(), .len = @intCast(device.id().len) },
            .{ .data = device.name(), .len = @intCast(device.name().len) },
            .{ .data = device.modelNumber(), .len = @intCast(device.modelNumber().len) },
            .{ .data = device.serialNumber(), .len = @intCast(device.serialNumber().len) },
            .{ .data = if (device.offline()) "𝑥" else "✓", .len = 1 },
            .{ .data = std.fmt.bufPrint(&int_buf, "{d}", .{device.watts()}) catch "0", .len = @intCast((std.fmt.bufPrint(&int_buf, "{d}", .{device.watts()}) catch "0").len) },
            .{ .data = device.firmwareVersion(), .len = @intCast(device.firmwareVersion().len) },
        };

        for (columns, 0..) |col, col_idx| {
            const val = col_values[col_idx];
            var data_len = val.len;
            if (data_len == 0) data_len = 1;

            if (col_idx % 2 != 0) {
                try stdout.writeAll(Color.teal);
                try stdout.writeAll(Color.dim);
            }

            const data = if (val.data.len == 0) "-" else val.data;

            if (col.align_right) {
                var pad: u8 = self.column_widths[col_idx] - data_len;
                while (pad > 0) : (pad -= 1) try stdout.writeAll(" ");
                try stdout.writeAll(data);
            } else {
                try stdout.writeAll(data);
                while (data_len < self.column_widths[col_idx]) : (data_len += 1) try stdout.writeAll(" ");
            }

            try stdout.writeAll(" ");
            try stdout.writeAll(Color.reset);
            if (is_selected) try stdout.writeAll(Color.bg_surface0);
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
        if (self.cursor >= self.state.devices.items.len) return;
        const device = self.state.devices.items[self.cursor];
        const id = device.id();

        for (self.selected[0..self.selected_len]) |sel_id| {
            if (std.mem.eql(u8, sel_id, id)) return;
        }

        self.selected[self.selected_len] = id;
        self.selected_len += 1;
        try self.writeRow(stdout, self.cursor);
    }

    fn deselectItem(self: *Self, stdout: std.fs.File) !void {
        if (self.cursor >= self.state.devices.items.len) return;
        const device = self.state.devices.items[self.cursor];
        const id = device.id();

        for (self.selected[0..self.selected_len], 0..) |sel_id, i| {
            if (std.mem.eql(u8, sel_id, id)) {
                self.selected[i] = self.selected[self.selected_len - 1];
                self.selected_len -= 1;
                try self.writeRow(stdout, self.cursor);
                return;
            }
        }
    }

    pub fn handleKey(self: *Self, stdout: std.fs.File, c: u8) !KeyResult {
        if (self.detail_focus) return try self.handleDetailKey(stdout, c);

        const now = std.time.milliTimestamp();
        const step: u8 = if (now - self.last_key_timestamp < 100) 2 else 1;
        const prev_key = self.last_key;
        var old: u8 = 0;
        self.last_key_timestamp = now;
        self.last_key = c;

        const result: KeyResult = switch (c) {
            0x1b => blk: {
                if (self.detail_focus) {
                    self.detail_focus = false;
                    try self.clearDetail(stdout);
                    try self.renderDetail(stdout);
                }
                break :blk .unhandled;
            },
            '\r', '\n' => blk: {
                self.detail_focus = true;
                try self.updateFocus(stdout, self.cursor, false);
                const device = self.getFocusedDevice() orelse break :blk .unhandled;
                const y = self.area.y + self.row_count + 4 + @as(u16, self.selected_len) * 4;
                const area = Rect{ .x = self.area.x, .y = y, .width = self.area.width, .height = 4 };
                self.detail = DetailView.init(device, area);
                try self.clearDetail(stdout);
                try self.renderDetail(stdout);
                break :blk .unhandled;
            },
            'g' => blk: {
                if (prev_key == 'g') {
                    old = self.cursor;
                    try self.updateFocus(stdout, old, false);
                    self.cursor = 0;
                    try self.updateFocus(stdout, self.cursor, true);
                    self.last_key = 0;
                }
                break :blk .unhandled;
            },
            'h' => blk: {
                try self.clearDetail(stdout);
                try self.deselectItem(stdout);
                try self.renderDetail(stdout);
                break :blk .unhandled;
            },
            'j' => blk: {
                old = self.cursor;
                try self.updateFocus(stdout, old, false);
                self.cursor = @min(old + step, self.row_count - 1);
                try self.updateFocus(stdout, self.cursor, true);
                break :blk .unhandled;
            },
            'k' => blk: {
                if (self.cursor > 0) {
                    old = self.cursor;
                    try self.updateFocus(stdout, old, false);
                    self.cursor = if (step > old) 0 else old - step;
                    try self.updateFocus(stdout, self.cursor, true);
                    break :blk .unhandled;
                }
                break :blk .{ .move_to = .up };
            },
            'l' => blk: {
                try self.selectItem(stdout);
                try self.renderDetail(stdout);
                break :blk .unhandled;
            },
            'G' => blk: {
                old = self.cursor;
                try self.updateFocus(stdout, old, false);
                self.cursor = self.row_count - 1;
                try self.updateFocus(stdout, self.cursor, true);
                break :blk .unhandled;
            },
            'H' => blk: {
                old = self.cursor;
                try self.updateFocus(stdout, old, false);
                self.cursor = 0;
                try self.updateFocus(stdout, self.cursor, true);
                self.last_key = 0;
                break :blk .unhandled;
            },
            'L' => blk: {
                old = self.cursor;
                try self.updateFocus(stdout, old, false);
                self.cursor = self.row_count - 1;
                try self.updateFocus(stdout, self.cursor, true);
                break :blk .unhandled;
            },
            'M' => blk: {
                old = self.cursor;
                try self.updateFocus(stdout, old, false);
                self.cursor = self.row_count / 2;
                try self.updateFocus(stdout, self.cursor, true);
                break :blk .unhandled;
            },
            else => .unhandled,
        };

        if (self.cursor != old) {
            try self.clearDetail(stdout);
            try self.renderDetail(stdout);
        }
        return result;
    }

    pub fn handleDetailKey(self: *Self, stdout: std.fs.File, c: u8) !KeyResult {
        if (c == 0x1b and !self.detail.hasOpenSelect()) {
            self.detail_focus = false;
            self.detail = .none;
            try self.updateFocus(stdout, self.cursor, true);
            try self.clearDetail(stdout);
            try self.renderDetail(stdout);
            return .unhandled;
        }
        return try self.detail.handleKey(stdout, c);
    }

    fn getDeviceById(self: *Self, id: []const u8) ?*Device {
        for (self.state.devices.items) |*device| {
            if (std.mem.eql(u8, device.id(), id)) return device;
        }
        return null;
    }

    fn getFocusedDevice(self: *Self) ?*Device {
        if (self.cursor >= self.state.devices.items.len) return null;
        return &self.state.devices.items[self.cursor];
    }

    fn renderDeviceDetail(stdout: std.fs.File, device: *Device, x: u16, y: u16, width: u16) !u16 {
        const area = Rect{ .x = x, .y = y, .width = width, .height = 4 };
        var detail = DetailView.init(device, area);
        return try detail.render(stdout, false);
    }

    fn renderDetail(self: *Self, stdout: std.fs.File) !void {
        var y = self.area.y + self.row_count + 4;

        for (self.selected[0..self.selected_len]) |device_id| {
            const device = self.getDeviceById(device_id) orelse continue;
            const height = try renderDeviceDetail(stdout, device, self.area.x, y, self.area.width);
            y += height;
        }

        const cursor_device = self.getFocusedDevice() orelse return;
        if (!self.isSelected(cursor_device.id())) {
            if (self.detail_focus) {
                _ = try self.detail.render(stdout, true);
            } else {
                _ = try renderDeviceDetail(stdout, cursor_device, self.area.x, y, self.area.width);
            }
        }
    }

    fn clearDetail(self: *Self, stdout: std.fs.File) !void {
        var pos_buf: [32]u8 = undefined;
        const detail_y = self.area.y + self.row_count + 4;
        const total_rows: u16 = (@as(u16, self.selected_len) + 1) * 4;
        var row: u16 = 0;
        while (row < total_rows) : (row += 1) {
            const pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ detail_y + row, self.area.x });
            try stdout.writeAll(pos);
            try stdout.writeAll("\x1b[K");
        }
    }
};
