const std = @import("std");
const Color = @import("../../color.zig");
const utils = @import("../../utils.zig");
const Writer = std.Io.Writer;
const Component = @import("../Component.zig");
const Cursor = @import("../../canvas.zig").Cursor;
const Frame = Component.Frame;
const KeyResult = @import("../../input.zig").KeyResult;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;

pub const KeyVal = struct { label: []const u8, value: Component };

pub const KeyValList = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    rows: std.ArrayList(KeyVal),
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

    pub fn component(self: *Self) Component {
        return .{ .ptr = self, .vtable = &.{
            .write = write,
            .handleKey = handleKey,
        } };
    }

    pub fn addRow(self: *KeyValList, label: []const u8, value: Component) !void {
        try self.rows.append(self.alloc, .{ .label = label, .value = value });
    }

    pub fn get(self: *KeyValList, comptime T: type, label: []const u8) ?*T {
        for (self.rows.items) |item| {
            if (std.mem.eql(u8, item.label, label)) {
                return @ptrCast(@alignCast(item.value.ptr));
            }
        }
        return null;
    }

    fn write(ptr: *anyopaque, writer: *Writer, cursor: *Cursor, frame: Frame) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
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

            try utils.moveTo(writer, frame.x, current_row);

            if (self.focused == idx) {
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
            try row.value.write(writer, cursor, .{ .x = value_x, .y = current_row, .w = frame.w -| value_col, .h = 1 });

            current_row += 1;
        }
    }

    fn handleKey(ptr: *anyopaque, key: u8, mq: *MessageQueue) KeyResult {
        const self: *Self = @ptrCast(@alignCast(ptr));
        defer self.prev_key = key;
        const rows = self.rows.items;

        if (self.focused) |f| {
            const result = rows[f].value.handleKey(key, mq);
            if (result == .consumed) return .consumed;
            if (result == .changed) return .changed;
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
