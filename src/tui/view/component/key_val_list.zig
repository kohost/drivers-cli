const std = @import("std");
const Color = @import("../../color.zig");
const utils = @import("../../utils.zig");
const Writer = std.Io.Writer;
const Component = @import("../component.zig").Component;
const Cursor = @import("../component.zig").Cursor;
const KeyResult = @import("../component.zig").KeyResult;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;

pub const KeyVal = struct { label: []const u8, value: Component };

pub const KeyValList = struct {
    alloc: std.mem.Allocator,
    rows: std.ArrayListUnmanaged(KeyVal),
    focused: ?usize,
    prev_key: u8,

    pub fn init(alloc: std.mem.Allocator) KeyValList {
        return .{
            .alloc = alloc,
            .rows = .empty,
            .focused = null,
            .prev_key = 0,
        };
    }

    pub fn deinit(self: *KeyValList) void {
        self.rows.deinit(self.alloc);
    }

    pub fn addRow(self: *KeyValList, label: []const u8, value: Component) !void {
        try self.rows.append(self.alloc, .{ .label = label, .value = value });
    }

    pub fn component(self: *KeyValList) Component {
        return .{
            .ptr = @ptrCast(self),
            .vtable = &.{
                .write = write,
                .handleKey = handleKey,
            },
        };
    }

    pub fn write(
        ptr: *anyopaque,
        writer: *Writer,
        x: u16,
        y: u16,
        w: u16,
        h: u16,
        cursor: *Cursor,
    ) anyerror!void {
        const self: *KeyValList = @ptrCast(@alignCast(ptr));
        const rows = self.rows.items;

        var max_label: u16 = 0;
        for (rows) |row| {
            const lw = utils.displayWidth(row.label) + 1;
            if (lw > max_label) max_label = lw;
        }
        const value_col = max_label + 2;

        var current_row = y;
        for (rows, 0..) |row, idx| {
            if (current_row >= y + h) break;

            try utils.moveTo(writer, x, current_row);

            if (self.focused == idx) {
                try utils.moveTo(writer, x -| 2, current_row);
                try writer.writeAll(Color.lavender ++ "┃" ++ Color.reset);
                try utils.moveTo(writer, x, current_row);
            }

            try writer.writeAll(Color.dim ++ Color.lavender);
            try writer.writeAll(row.label);
            try writer.writeAll(":");
            try writer.writeAll(Color.reset);

            const label_w = utils.displayWidth(row.label) + 1;
            const pad = value_col -| label_w;
            for (0..pad) |_| try writer.writeAll(" ");

            const value_x = x + value_col;
            try row.value.write(writer, value_x, current_row, w -| value_col, 1, cursor);

            current_row += 1;
        }
    }


    fn handleKey(ptr: *anyopaque, key: u8, mq: *MessageQueue) KeyResult {
        const self: *KeyValList = @ptrCast(@alignCast(ptr));
        defer self.prev_key = key;
        const rows = self.rows.items;

        if (self.focused) |f| {
            const result = rows[f].value.handleKey(key, mq);
            if (result == .consumed) return .consumed;
        }

        switch (key) {
            'j' => {
                if (self.focused) |f| {
                    if (f < rows.len - 1) {
                        self.focused = f + 1;
                        mq.post(.render);
                        return .consumed;
                    }
                    return .focus_next;
                }
                return .ignored;
            },
            'k' => {
                if (self.focused) |f| {
                    if (f > 0) {
                        self.focused = f - 1;
                        mq.post(.render);
                        return .consumed;
                    }
                    return .focus_prev;
                }
                return .ignored;
            },
            'g' => {
                if (self.prev_key == 'g') {
                    self.focused = 0;
                    mq.post(.render);
                    return .consumed;
                }
                return .ignored;
            },
            'G' => {
                if (rows.len > 0) {
                    self.focused = rows.len - 1;
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
};
