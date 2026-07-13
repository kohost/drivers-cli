const std = @import("std");
const Color = @import("../../color.zig");
const icons = @import("../icons.zig");
const utils = @import("../../utils.zig");
const Component = @import("../Component.zig");
const Writer = std.Io.Writer;
const Cursor = @import("../../canvas.zig").Cursor;
const Frame = Component.Frame;
const KeyResult = @import("../../input.zig").KeyResult;
const Mouse = @import("../../input.zig").Mouse;
const Style = @import("../_component.zig").Style;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;

pub fn Select(comptime T: type) type {
    return struct {
        const Self = @This();

        source: *const T,
        vsource: *T,
        options: []const T,
        cursor: usize,
        open: bool,
        style: Style,
        frame: Frame = .{},

        pub fn init(source: *const T, vsource: *T, options: []const T, style: Style) Self {
            return .{
                .source = source,
                .vsource = vsource,
                .options = options,
                .cursor = indexOf(options, vsource.*),
                .open = false,
                .style = style,
            };
        }

        pub fn component(self: *Self) Component {
            return .{ .ptr = self, .vtable = &.{
                .write = write,
                .handleKey = handleKey,
                .handleMouse = handleMouse,
            } };
        }

        /// Open the dropdown and take the mouse: every event inside the expanded
        /// frame is ours until we close.
        fn openDropdown(self: *Self, mq: *MessageQueue) void {
            self.cursor = indexOf(self.options, self.vsource.*);
            self.open = true;
            mq.post(.{ .capture_mouse = .{ .component = self.component(), .frame = self.expandedFrame() } });
            mq.post(.render);
        }

        fn closeDropdown(self: *Self, mq: *MessageQueue) void {
            self.open = false;
            mq.post(.release_mouse);
            mq.post(.render);
        }

        fn expandedFrame(self: *Self) Frame {
            var f = self.frame;
            f.h = @intCast(1 + self.options.len);
            // The dropdown hangs one column left when there's no header marker.
            if (!self.style.focus_marker) {
                f.x = self.frame.x -| 1;
                f.w = self.frame.w + 1;
            }
            return f;
        }

        fn write(ptr: *anyopaque, w: *Writer, _: *Cursor, f: Frame, focused: bool) anyerror!void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            self.frame = f;
            const x = f.x;
            const y = f.y;

            // Get longest option
            var max_width: u8 = 0;
            for (self.options) |o| {
                const olen: u8 = @intCast(@tagName(o).len);
                if (olen > max_width) max_width = olen;
            }

            // Header shows the current (vstate) value.
            const text = @tagName(self.vsource.*);

            // Figure out color
            const color = if (self.isDirty())
                if (self.style.tertiary_color.len > 0) self.style.tertiary_color else Color.yellow
            else if (self.style.color.len > 0)
                self.style.color
            else
                Color.text;

            const secondary_color = if (self.style.secondary_color.len > 0) self.style.secondary_color else Color.subtext1;
            const bg_color = self.style.bg_color; // empty = no background box
            const secondary_bg_color = if (self.style.secondary_bg_color.len > 0) self.style.secondary_bg_color else Color.bg_overlay1;

            // Start drawing
            try utils.moveTo(w, x, y);
            try w.writeAll(bg_color);

            // Marker column — 1 cell, reserved only where the header can take focus.
            if (self.style.focus_marker) {
                if (focused and !self.open) {
                    try w.writeAll(color);
                    try w.writeAll("▎");
                    try w.writeAll(Color.reset);
                    try w.writeAll(bg_color);
                } else {
                    try w.writeAll(" ");
                }
            }
            for (0..self.style.padding_left) |_| try w.writeAll(" ");

            try w.writeAll(color);
            try w.writeAll(text);

            const pad = max_width - @as(u8, @intCast(text.len));
            for (0..pad) |_| try w.writeAll(" ");
            if (self.open) try w.writeAll(" " ++ icons.caret_up) else try w.writeAll(" " ++ icons.caret_down);
            for (0..self.style.padding_right) |_| try w.writeAll(" ");
            try w.writeAll(Color.reset);

            // Options dropdown
            if (self.open) {
                var next_row = y + 1;
                const caret_w = utils.displayWidth(icons.caret_down);
                // Without a header marker column, the option cursor hangs in the gutter
                // so option labels line up with the header value.
                const dd_x = if (self.style.focus_marker) x else x -| 1;

                for (self.options, 0..) |o, i| {
                    const label = @tagName(o);
                    const ddpad = max_width + 1 + caret_w + self.style.padding_right - @as(u16, @intCast(label.len));
                    try utils.moveTo(w, dd_x, next_row);
                    try w.writeAll(secondary_bg_color);
                    try w.writeAll(secondary_color);

                    try w.writeAll(if (i == self.cursor) "▎" else " ");
                    for (0..self.style.padding_left) |_| try w.writeAll(" ");

                    try w.writeAll(label);
                    for (0..ddpad) |_| try w.writeAll(" ");
                    next_row += 1;
                }

                try w.writeAll(Color.reset);
            }
        }

        fn handleKey(ptr: *anyopaque, key: u8, mq: *MessageQueue) KeyResult {
            const self: *Self = @ptrCast(@alignCast(ptr));

            if (!self.open) {
                switch (key) {
                    '\r', '\n' => {
                        self.openDropdown(mq);
                        return .consumed;
                    },
                    else => return .ignored,
                }
            }

            switch (key) {
                'j' => {
                    if (self.cursor < self.options.len - 1) {
                        self.cursor += 1;
                        mq.post(.render);
                    }
                    return .consumed;
                },
                'k' => {
                    if (self.cursor > 0) {
                        self.cursor -= 1;
                        mq.post(.render);
                    }
                    return .consumed;
                },
                '\r', '\n', 'l' => {
                    self.vsource.* = self.options[self.cursor]; // commit into vstate
                    self.closeDropdown(mq);
                    return .changed;
                },
                0x1b, 'h' => { // cancel — vsource untouched
                    self.closeDropdown(mq);
                    return .consumed;
                },
                else => return .ignored,
            }
            return .ignored;
        }

        pub fn handleMouse(ptr: *anyopaque, m: Mouse, mq: *MessageQueue) KeyResult {
            const self: *Self = @ptrCast(@alignCast(ptr));
            mq.post(.{ .update_pointer = utils.pointer_hand });

            // Focus follows mouse while open
            if (self.open and m.move) {
                if (m.y > self.frame.y) {
                    const row = m.y - self.frame.y - 1;
                    if (row < self.options.len and row != self.cursor) {
                        self.cursor = row;
                        mq.post(.render);
                    }
                }
                return .consumed;
            }

            if (m.press and !m.move) {
                if (self.open) {
                    self.vsource.* = self.options[self.cursor];
                    self.closeDropdown(mq);
                    return .changed;
                }
                self.openDropdown(mq);
                return .consumed;
            }

            return .ignored;
        }

        fn indexOf(options: []const T, value: T) usize {
            for (options, 0..) |o, i| if (o == value) return i;
            return 0;
        }

        fn isDirty(self: *Self) bool {
            return self.source.* != self.vsource.*;
        }
    };
}
