const std = @import("std");
const Component = @import("../Component.zig");
const Writer = std.Io.Writer;
const Color = @import("../../color.zig");
const Cursor = @import("../../canvas.zig").Cursor;
const Frame = Component.Frame;
const KeyResult = @import("../../input.zig").KeyResult;
const Mouse = @import("../../input.zig").Mouse;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;
const Style = @import("../component.zig").Style;
const utils = @import("../../utils.zig");

/// A scrollable window onto `source` text that may be taller than its frame.
/// Pushed content (set `source` directly); j/k/gg/G scroll the viewport.
pub const Viewport = struct {
    const Self = @This();

    source: []const u8,
    style: Style,
    overflowed: bool = false,
    top_line: u16 = 0,
    cursor_line: u16 = 0,
    visible_h: u16 = 0,
    total_lines: u16 = 0,
    prev_key: u8 = 0,

    pub fn init(source: []const u8, style: Style) Viewport {
        return .{ .source = source, .style = style };
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
        if (m.move) mq.post(.{ .update_pointer = utils.pointer_default });

        return .ignored;
    }

    pub fn scrollBy(self: *Self, delta: i16) bool {
        if (!self.overflowed) return false;
        const max: i32 = self.total_lines -| self.visible_h;
        const next = std.math.clamp(@as(i32, self.top_line) + delta, 0, max);
        if (next == self.top_line) return false;
        self.top_line = @intCast(next);
        return true;
    }

    fn write(ptr: *anyopaque, writer: *Writer, _: *Cursor, frame: Frame, focused: bool) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        self.visible_h = frame.h;
        self.total_lines = countLines(self.source);
        self.overflowed = self.total_lines > frame.h;

        if (self.total_lines > 0 and self.cursor_line >= self.total_lines) {
            self.cursor_line = self.total_lines - 1;
        }

        var lines = std.mem.splitScalar(u8, self.source, '\n');

        var skipped: u16 = 0;
        while (skipped < self.top_line) : (skipped += 1) {
            if (lines.next() == null) break;
        }

        var y = frame.y;
        var line_idx: u16 = self.top_line;
        while (lines.next()) |line| : ({
            y += 1;
            line_idx += 1;
        }) {
            if (y >= frame.y + frame.h) break;

            const is_cursor = focused and self.overflowed and line_idx == self.cursor_line;
            if (is_cursor) {
                try utils.moveTo(writer, frame.x -| 2, y);
                try writer.writeAll(Color.lavender ++ "┃" ++ Color.reset);
            }

            try utils.moveTo(writer, frame.x, y);
            try writer.writeAll(self.style.bg_color);
            try writer.writeAll(self.style.color);
            for (0..self.style.padding_left) |_| try writer.writeAll(" ");
            try writer.writeAll(line);
            try writer.writeAll(Color.reset);
        }
    }

    fn handleKey(ptr: *anyopaque, key: u8, mq: *MessageQueue) KeyResult {
        const self: *Self = @ptrCast(@alignCast(ptr));
        defer self.prev_key = key;

        if (!self.overflowed) {
            switch (key) {
                'j' => return .focus_next,
                'k' => return .focus_prev,
                else => return .ignored,
            }
        }

        switch (key) {
            'j' => {
                if (self.cursor_line + 1 >= self.total_lines) return .focus_next;
                self.cursor_line += 1;
                if (self.cursor_line >= self.top_line + self.visible_h) {
                    self.top_line += 1;
                }
                mq.post(.render);
                return .consumed;
            },
            'k' => {
                if (self.cursor_line == 0) return .focus_prev;
                self.cursor_line -= 1;
                if (self.cursor_line < self.top_line) {
                    self.top_line = self.cursor_line;
                }
                mq.post(.render);
                return .consumed;
            },
            'g' => {
                if (self.prev_key == 'g') {
                    self.cursor_line = 0;
                    self.top_line = 0;
                    mq.post(.render);
                    return .consumed;
                }
                return .ignored;
            },
            'G' => {
                if (self.total_lines == 0) return .ignored;
                self.cursor_line = self.total_lines - 1;
                if (self.total_lines > self.visible_h) {
                    self.top_line = self.total_lines - self.visible_h;
                } else {
                    self.top_line = 0;
                }
                mq.post(.render);
                return .consumed;
            },
            else => return .ignored,
        }
    }

    fn countLines(s: []const u8) u16 {
        if (s.len == 0) return 0;
        var n: u16 = 1;
        for (s) |c| if (c == '\n') {
            n += 1;
        };
        return n;
    }
};
