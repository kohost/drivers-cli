const std = @import("std");
const Color = @import("../../color.zig");
const utils = @import("../../utils.zig");
const KeyResult = @import("../../input.zig").KeyResult;
const Mouse = @import("../../input.zig").Mouse;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;

pub const Menu = struct {
    x: u16,
    y: u16,
    items: []const []const u8,
    selected: usize,
    height: u16 = 1,

    focused: bool,

    pub fn init(opts: struct {
        x: u16 = 1,
        y: u16 = 1,
        items: []const []const u8,
        selected: usize = 0,
        focused: bool = false,
    }) Menu {
        return .{
            .x = opts.x,
            .y = opts.y,
            .items = opts.items,
            .selected = opts.selected,
            .focused = opts.focused,
        };
    }

    pub fn write(self: *const Menu, writer: *std.Io.Writer) !void {
        try utils.moveTo(writer, self.x, self.y);

        for (self.items, 0..) |item, idx| {
            const is_selected = idx == self.selected;

            if (idx > 0) {
                try writer.writeAll(Color.overlay1);
                try writer.writeAll(" | ");
            }

            if (is_selected) {
                try writer.writeAll(Color.lavender);
            } else {
                try writer.writeAll(Color.dim ++ Color.lavender);
            }
            try writer.writeAll(item);
            try writer.writeAll(Color.reset);
        }
    }

    pub fn next(self: *Menu) void {
        if (self.selected < self.items.len - 1) self.selected += 1 else self.selected = 0;
    }

    pub fn prev(self: *Menu) void {
        if (self.selected > 0) self.selected -= 1 else self.selected = self.items.len - 1;
    }

    pub fn handleKey(self: *Menu, key: u8, mq: *MessageQueue) KeyResult {
        switch (key) {
            'l' => {
                self.next();
                mq.post(.{ .view_changed = self.selected });
                return .consumed;
            },
            'h' => {
                self.prev();
                mq.post(.{ .view_changed = self.selected });
                return .consumed;
            },
            ':' => {
                mq.post(.{ .open_input = ':' });
                return .consumed;
            },
            'j' => return .focus_next,
            else => return .ignored,
        }
    }

    /// Maps a pointer position to an item index by walking the same layout
    /// write() uses: each item is `displayWidth(item)` wide, separated by
    /// " | " (3 cols). Returns null when the pointer is off any item.
    fn itemAt(self: *const Menu, x: u16, y: u16) ?usize {
        if (y != self.y) return null;
        var col = self.x;
        for (self.items, 0..) |item, idx| {
            if (idx > 0) col += 3; // " | " separator
            const w = utils.displayWidth(item);
            if (x >= col and x < col + w) return idx;
            col += w;
        }
        return null;
    }

    pub fn handleMouse(self: *Menu, m: Mouse, mq: *MessageQueue) KeyResult {
        const hit = self.itemAt(m.x, m.y);

        // Hover feedback: hand over an item, arrow anywhere else in the row.
        mq.post(.{ .update_pointer = if (hit != null) utils.pointer_hand else utils.pointer_default });

        const idx = hit orelse return .ignored;
        if (m.press and !m.move) {
            if (idx != self.selected) {
                self.selected = idx;
                mq.post(.{ .view_changed = idx });
            }
            return .consumed;
        }
        return .consumed;
    }
};
