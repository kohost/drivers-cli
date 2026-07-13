const std = @import("std");
const Color = @import("../../color.zig");
const utils = @import("../../utils.zig");
const Writer = std.Io.Writer;
const Component = @import("../Component.zig");
const Cursor = @import("../../canvas.zig").Cursor;
const Frame = Component.Frame;
const KeyResult = @import("../../input.zig").KeyResult;
const Mouse = @import("../../input.zig").Mouse;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;
const TextDisplay = @import("text_display.zig").TextDisplay;
const TextInput = @import("text_input.zig").TextInput;
const Toggle = @import("./toggle.zig").Toggle;

pub const KeyVal = struct { label: []const u8, value: Component };

pub const KeyValList = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    rows: std.ArrayList(KeyVal),
    cursor: ?usize,
    prev_key: u8,
    frame: Frame = .{},

    pub fn init(alloc: std.mem.Allocator) KeyValList {
        return .{
            .alloc = alloc,
            .rows = .empty,
            .cursor = null,
            .prev_key = 0,
        };
    }

    pub fn deinit(self: *KeyValList) void {
        self.rows.deinit(self.alloc);
    }

    pub fn component(self: *Self) Component {
        return .{ .ptr = self, .vtable = &.{
            .write = write,
            .handleKey = handleKey,
            .handleMouse = handleMouse,
        } };
    }

    pub fn addRow(self: *KeyValList, label: []const u8, value: Component) !void {
        try self.rows.append(self.alloc, .{ .label = label, .value = value });
    }

    fn write(ptr: *anyopaque, writer: *Writer, cursor: *Cursor, frame: Frame, focused: bool) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.frame = frame;
        const rows = self.rows.items;

        var max_label: u16 = 0;
        for (rows) |row| {
            const lw = utils.displayWidth(row.label) + 1;
            if (lw > max_label) max_label = lw;
        }
        const value_col = max_label + 2;

        var current_row = frame.y;
        for (rows, 0..) |row, idx| {
            if (current_row >= frame.y + frame.h) break;

            const row_focused = focused and self.cursor == idx;

            try utils.moveTo(writer, frame.x, current_row);

            if (row_focused) {
                try utils.moveTo(writer, frame.x -| 2, current_row);
                try writer.writeAll(Color.lavender ++ "┃" ++ Color.reset);
                try utils.moveTo(writer, frame.x, current_row);
            }

            try writer.writeAll(Color.dim ++ Color.lavender);
            try writer.writeAll(row.label);
            try writer.writeAll(":");
            try writer.writeAll(Color.reset);

            const label_w = utils.displayWidth(row.label) + 1;
            const pad = value_col -| label_w;
            for (0..pad) |_| try writer.writeAll(" ");

            const value_x = frame.x + value_col;
            try row.value.write(writer, cursor, .{ .x = value_x, .y = current_row, .w = frame.w -| value_col, .h = 1 }, row_focused);

            current_row += 1;
        }
    }

    fn handleKey(ptr: *anyopaque, key: u8, mq: *MessageQueue) KeyResult {
        const self: *Self = @ptrCast(@alignCast(ptr));
        defer self.prev_key = key;
        const rows = self.rows.items;

        if (self.cursor) |f| {
            const result = rows[f].value.handleKey(key, mq);
            if (result == .consumed) return .consumed;
            if (result == .changed) return .changed;
        }

        switch (key) {
            'j' => {
                if (self.cursor) |f| {
                    if (f < rows.len - 1) {
                        self.cursor = f + 1;
                        mq.post(.render);
                        return .consumed;
                    }
                    return .focus_next;
                }
                return .ignored;
            },
            'k' => {
                if (self.cursor) |f| {
                    if (f > 0) {
                        self.cursor = f - 1;
                        mq.post(.render);
                        return .consumed;
                    }
                    return .focus_prev;
                }
                return .ignored;
            },
            'g' => {
                if (self.prev_key == 'g') {
                    self.cursor = 0;
                    mq.post(.render);
                    return .consumed;
                }
                return .ignored;
            },
            'G' => {
                if (rows.len > 0) {
                    self.cursor = rows.len - 1;
                    mq.post(.render);
                    return .consumed;
                }
                return .ignored;
            },
            ':' => {
                mq.post(.{ .open_input = ':' });
                return .consumed;
            },
            else => return .ignored,
        }
    }

    pub fn handleMouse(ptr: *anyopaque, m: Mouse, mq: *MessageQueue) KeyResult {
        const self: *Self = @ptrCast(@alignCast(ptr));

        // Hover
        const prev = self.cursor;
        self.cursorAt(m.y);
        if (prev != self.cursor) {
            // Left a row, cancel any active edit on it (Esc = discard)
            if (prev) |p| _ = self.rows.items[p].value.handleKey(0x1b, mq);
        }

        // Forward the event to that row's value component
        if (self.cursor) |f| {
            const result = self.rows.items[f].value.handleMouse(m, mq);
            if (result == .consumed or result == .changed) return result;
        }
        return .ignored;
    }

    // Row builders
    pub fn addDisplay(
        self: *KeyValList,
        lbl: []const u8,
        src: anytype,
        opts: TextDisplay(std.meta.Child(@TypeOf(src))).Options,
    ) !void {
        const T = std.meta.Child(@TypeOf(src));
        const display = try self.alloc.create(TextDisplay(T));
        display.* = .init(src, opts);
        try self.addRow(lbl, display.component());
    }

    pub fn addInput(
        self: *KeyValList,
        lbl: []const u8,
        src: anytype,
        vsrc: anytype,
        opts: TextInput(std.meta.Child(@TypeOf(src))).Options,
    ) !void {
        const T = std.meta.Child(@TypeOf(src));
        const input = try self.alloc.create(TextInput(T));
        input.* = .init(src, vsrc, opts);
        try self.addRow(lbl, input.component());
    }

    const toggleOpts = struct { active: []const u8 = "✔", inactive: []const u8 = "✗" };
    pub fn addToggle(
        self: *KeyValList,
        lbl: []const u8,
        src: anytype,
        vsrc: anytype,
        on: std.meta.Child(@TypeOf(vsrc)),
        off: std.meta.Child(@TypeOf(vsrc)),
        opts: toggleOpts,
    ) !void {
        const T = std.meta.Child(@TypeOf(vsrc));
        const toggle = try self.alloc.create(Toggle(T));
        toggle.* = .init(.{
            .source = src,
            .vsource = vsrc,
            .on = on,
            .off = off,
            .active = opts.active,
            .inactive = opts.inactive,
        });
        try self.addRow(lbl, toggle.component());
    }

    pub fn addSelect(
        self: *KeyValList,
        lbl: []const u8,
        src: anytype,
        vsource: anytype,
    ) !void {}

    pub fn get(self: *KeyValList, comptime T: type, label: []const u8) ?*T {
        for (self.rows.items) |item| {
            if (std.mem.eql(u8, item.label, label)) {
                return @ptrCast(@alignCast(item.value.ptr));
            }
        }
        return null;
    }

    pub fn cursorAt(self: *KeyValList, y: u16) void {
        if (y < self.frame.y) return;
        const idx = y - self.frame.y;
        if (idx < self.rows.items.len) self.cursor = idx;
    }
};
