const std = @import("std");
const Color = @import("../../color.zig");
const utils = @import("../../utils.zig");
const Component = @import("../Component.zig");
const Cursor = @import("../../canvas.zig").Cursor;
const Frame = Component.Frame;
const KeyResult = @import("../../input.zig").KeyResult;
const Mouse = @import("../../input.zig").Mouse;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;
const Writer = std.Io.Writer;

pub const CellValue = union(enum) {
    string: []const u8,
    int: u16,
    float: f32,

    pub fn format(self: CellValue, buf: []u8) []const u8 {
        return switch (self) {
            .string => |s| s,
            .int => |n| std.fmt.bufPrint(buf, "{d}", .{n}) catch "?",
            .float => |f| std.fmt.bufPrint(buf, "{d:.1}", .{f}) catch "?",
        };
    }

    pub fn displayWidth(self: CellValue) u16 {
        return switch (self) {
            .string => |s| utils.displayWidth(s),
            .int => |n| blk: {
                var buf: [8]u8 = undefined;
                break :blk utils.displayWidth(std.fmt.bufPrint(&buf, "{d}", .{n}) catch "?");
            },
            .float => |f| blk: {
                var buf: [16]u8 = undefined;
                break :blk utils.displayWidth(std.fmt.bufPrint(&buf, "{d:.1}", .{f}) catch "?");
            },
        };
    }
};

pub const Cell = struct {
    value: CellValue = .{ .string = "" },
    style: []const u8 = "",
    align_right: bool = false,
};

pub const Row = []const Cell;

pub const Table = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    headers: []const Cell,
    rows: std.ArrayList(Row),
    selected: ?usize,
    scroll_offset: u16,
    visible_rows: u16,
    prev_key: u8,
    filter_buf: [64]u8,
    filter_len: usize,
    filtered_count: u16,
    frame: Frame = .{},

    pub fn init(alloc: std.mem.Allocator, headers: []const Cell) Table {
        return .{
            .alloc = alloc,
            .headers = headers,
            .rows = .empty,
            .selected = null,
            .scroll_offset = 0,
            .visible_rows = 0,
            .prev_key = 0,
            .filter_buf = undefined,
            .filter_len = 0,
            .filtered_count = 0,
        };
    }

    pub fn deinit(self: *Table) void {
        for (self.rows.items) |row| {
            self.alloc.free(row);
        }
        self.rows.deinit(self.alloc);
    }

    pub fn addRow(self: *Table, cells: []const Cell) !void {
        const owned = try self.alloc.alloc(Cell, cells.len);
        @memcpy(owned, cells);
        try self.rows.append(self.alloc, owned);
    }

    pub fn clearRows(self: *Table) void {
        for (self.rows.items) |row| {
            self.alloc.free(row);
        }
        self.rows.clearRetainingCapacity();
    }

    pub fn component(self: *Self) Component {
        return .{ .ptr = self, .vtable = &.{
            .write = write,
            .handleKey = handleKey,
            .handleMouse = handleMouse,
        } };
    }

    pub fn handleMouse(ptr: *anyopaque, m: Mouse, mq: *MessageQueue) KeyResult {
        const self: *Self = @ptrCast(@alignCast(ptr));

        // Scroll
        if (m.btn == .wheel_up or m.btn == .wheel_down) {
            const delta: i16 = if (m.btn == .wheel_up) -1 else 1;
            if (self.scrollBy(delta)) {
                return .consumed;
            }
        }

        // Hover
        if (m.move and m.press) {
            if (self.rowAt(m.y)) |i| {
                self.selected = i;
                mq.post(.{ .update_pointer = utils.pointer_hand });
            } else {
                mq.post(.{ .update_pointer = utils.pointer_default });
            }
            return .consumed;
        }

        // Press
        if (m.press) {
            self.selectAt(m.y);
            return .dive_in;
        }

        return .ignored;
    }

    pub fn handleKeyDirect(self: *Table, key: u8, mq: *MessageQueue) KeyResult {
        return handleKeyImpl(self, key, mq);
    }

    fn handleKey(ptr: *anyopaque, key: u8, mq: *MessageQueue) KeyResult {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return handleKeyImpl(self, key, mq);
    }

    fn handleKeyImpl(self: *Table, key: u8, mq: *MessageQueue) KeyResult {
        defer self.prev_key = key;
        switch (key) {
            'j' => {
                const count = self.activeCount();
                if (self.selected) |s| {
                    if (s < count -| 1) {
                        self.selected = s + 1;
                        if (s + 1 >= self.scroll_offset + self.visible_rows) {
                            self.scroll_offset = @intCast(s + 2 -| self.visible_rows);
                        }
                        mq.post(.render);
                        return .consumed;
                    } else {
                        return .focus_next;
                    }
                }
                return .ignored;
            },
            'k' => {
                if (self.selected) |s| {
                    if (s > 0) {
                        self.selected = s - 1;
                        if (s - 1 < self.scroll_offset) {
                            self.scroll_offset = @intCast(s - 1);
                        }
                        mq.post(.render);
                        return .consumed;
                    } else {
                        return .focus_prev;
                    }
                }
                return .ignored;
            },
            'g' => {
                if (self.prev_key == 'g') {
                    self.selected = 0;
                    self.scroll_offset = 0;
                    mq.post(.render);
                    return .consumed;
                }
                return .ignored;
            },
            'G' => {
                const count = self.activeCount();
                if (count > 0) {
                    self.selected = count - 1;
                    if (count > self.visible_rows) {
                        self.scroll_offset = count - self.visible_rows;
                    }
                    mq.post(.render);
                    return .consumed;
                }
                return .ignored;
            },
            'l', '\n' => return .dive_in,
            'h' => return .dive_out,
            '/' => return .open_search,
            ':' => {
                mq.post(.{ .open_input = ':' });
                return .consumed;
            },
            else => return .ignored,
        }
    }

    pub fn setFilter(self: *Table, filter: []const u8) void {
        if (self.filter_len == filter.len and
            std.mem.eql(u8, self.filter_buf[0..self.filter_len], filter)) return;
        const copy_len = @min(filter.len, self.filter_buf.len);
        @memcpy(self.filter_buf[0..copy_len], filter[0..copy_len]);
        self.filter_len = copy_len;
        self.scroll_offset = 0;
        self.selected = if (copy_len > 0) 0 else self.selected;
    }

    pub fn getFilter(self: *const Table) []const u8 {
        return self.filter_buf[0..self.filter_len];
    }

    pub fn rowAt(self: *Table, y: u16) ?usize {
        if (y <= self.frame.y) return null;
        const idx = self.scroll_offset + (y - self.frame.y - 1);
        return if (idx < self.filtered_count) idx else null;
    }

    pub fn selectAt(self: *Table, y: u16) void {
        if (self.rowAt(y)) |i| self.selected = i;
    }

    pub fn scrollBy(self: *Table, delta: i16) bool {
        const max: i32 = self.filtered_count -| self.visible_rows;
        const next = std.math.clamp(@as(i32, self.scroll_offset) + delta, 0, max);
        if (next == self.scroll_offset) return false;
        self.scroll_offset = @intCast(next);
        return true;
    }

    fn write(ptr: *anyopaque, writer: *Writer, _: *Cursor, frame: Frame, focused: bool) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.frame = frame;
        const x = frame.x;
        const y = frame.y;
        const h = frame.h;
        const items = self.rows.items;

        var widths: [16]u16 = .{0} ** 16;
        for (self.headers, 0..) |hdr, i| {
            widths[i] = hdr.value.displayWidth();
        }
        for (items) |row| {
            for (row, 0..) |cell, i| {
                const len = cell.value.displayWidth();
                if (len > widths[i]) widths[i] = len;
            }
        }

        // Header
        try utils.moveTo(writer, x, y);
        for (self.headers, 0..) |hdr, i| {
            var hdr_buf: [32]u8 = undefined;
            const hdr_text = hdr.value.format(&hdr_buf);
            const pad = widths[i] - utils.displayWidth(hdr_text);
            if (hdr.align_right) {
                for (0..pad) |_| try writer.writeAll(" ");
            }
            try writer.writeAll(if (hdr.style.len > 0) hdr.style else Color.lavender ++ Color.dim);
            try writer.writeAll(hdr_text);
            try writer.writeAll(Color.reset);
            if (!hdr.align_right) {
                for (0..pad) |_| try writer.writeAll(" ");
            }
            try writer.writeAll("  ");
        }

        // Build filtered row indices
        var filtered: [512]usize = undefined;
        var filtered_count: u16 = 0;
        for (items, 0..) |row, idx| {
            if (self.filter_len == 0 or rowMatches(row, self.filter_buf[0..self.filter_len])) {
                if (filtered_count < filtered.len) {
                    filtered[filtered_count] = idx;
                    filtered_count += 1;
                }
            }
        }

        // Clamp selection to filtered set
        if (filtered_count == 0) {
            self.selected = null;
        } else if (self.selected) |s| {
            if (s >= filtered_count) self.selected = filtered_count - 1;
        }
        self.filtered_count = filtered_count;

        // Rows
        self.visible_rows = h -| 1;
        var row_y = y + 1;
        var drawn: u16 = 0;
        for (filtered[0..filtered_count]) |src_idx| {
            if (drawn < self.scroll_offset) {
                drawn += 1;
                continue;
            }
            if (row_y >= y + h) break;
            const row = items[src_idx];
            try utils.moveTo(writer, x, row_y);
            const is_selected = focused and self.selected != null and drawn == self.selected.?;
            if (is_selected) {
                try utils.moveTo(writer, x -| 2, row_y);
                try writer.writeAll(Color.lavender ++ "┃" ++ Color.reset);
                try utils.moveTo(writer, x, row_y);
            }
            for (row, 0..) |cell, i| {
                var cell_buf: [32]u8 = undefined;
                const cell_text = cell.value.format(&cell_buf);
                const pad = widths[i] - utils.displayWidth(cell_text);
                const right = if (i < self.headers.len) self.headers[i].align_right else false;
                if (right) {
                    for (0..pad) |_| try writer.writeAll(" ");
                }
                try writer.writeAll(if (cell.style.len > 0) cell.style else Color.lavender);
                try writer.writeAll(cell_text);
                try writer.writeAll(Color.reset);
                if (!right) {
                    for (0..pad) |_| try writer.writeAll(" ");
                }
                try writer.writeAll("  ");
            }
            row_y += 1;
            drawn += 1;
        }
    }

    pub fn selectedRow(self: *const Table) ?[]const Cell {
        const sel = self.selected orelse return null;
        const items = self.rows.items;
        if (self.filter_len == 0) {
            if (sel < items.len) return items[sel];
            return null;
        }
        var count: usize = 0;
        for (items) |row| {
            if (rowMatches(row, self.filter_buf[0..self.filter_len])) {
                if (count == sel) return row;
                count += 1;
            }
        }
        return null;
    }

    fn activeCount(self: *Table) u16 {
        return if (self.filter_len > 0) self.filtered_count else @intCast(self.rows.items.len);
    }

    fn rowMatches(row: []const Cell, filter: []const u8) bool {
        for (row) |cell| {
            var buf: [32]u8 = undefined;
            const text = cell.value.format(&buf);
            if (std.mem.indexOf(u8, text, filter) != null) return true;
        }
        return false;
    }
};
