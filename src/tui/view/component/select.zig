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

        fn write(ptr: *anyopaque, w: *Writer, _: *Cursor, f: Frame, focused: bool) anyerror!void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            self.frame = f;
            if (self.open) self.frame.h = @intCast(1 + self.options.len);
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
            const bg_color = if (self.style.bg_color.len > 0) self.style.bg_color else Color.bg_overlay0;
            const secondary_bg_color = if (self.style.secondary_bg_color.len > 0) self.style.secondary_bg_color else Color.bg_overlay1;

            // Start drawing
            try utils.moveTo(w, x, y);
            try w.writeAll(bg_color);
            if (focused and !self.open) {
                try w.writeAll(color);
                try w.writeAll("▎");
                for (0..self.style.padding_left -| 1) |_| try w.writeAll(" ");
                try w.writeAll(Color.reset);
                // if (self.style.bg_color.len > 0) try writer.writeAll(self.style.bg_color);
                try w.writeAll(bg_color);
            } else {
                for (0..self.style.padding_left) |_| try w.writeAll(" ");
            }
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

                for (self.options, 0..) |o, i| {
                    const label = @tagName(o);
                    const ddpad = max_width + self.style.padding_right + self.style.padding_left + utils.displayWidth(icons.caret_down) - @as(u8, @intCast(label.len));
                    try utils.moveTo(w, x, next_row);
                    try w.writeAll(secondary_bg_color);
                    try w.writeAll(secondary_color);

                    if (i == self.cursor) {
                        try w.writeAll("▎");
                        for (0..self.style.padding_left -| 1) |_| try w.writeAll(" ");
                    } else {
                        for (0..self.style.padding_left) |_| try w.writeAll(" ");
                    }
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
                        self.cursor = indexOf(self.options, self.vsource.*);
                        self.open = true;
                        mq.post(.render);
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
                    self.open = false;
                    mq.post(.render);
                    return .changed;
                },
                0x1b, 'h' => { // cancel — vsource untouched
                    self.open = false;
                    mq.post(.render);
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
                    if (row < self.options.len) self.cursor = row;
                }
                return .consumed;
            }

            if (m.press and !m.move) {
                if (self.open) {
                    self.vsource.* = self.options[self.cursor];
                    self.open = false;
                    return .changed;
                } else {
                    self.cursor = indexOf(self.options, self.vsource.*);
                    self.open = true;
                }
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
