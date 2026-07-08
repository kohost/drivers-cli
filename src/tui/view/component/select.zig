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

pub const Select = struct {
    const Self = @This();

    source: []const u8,
    options: []const []const u8,
    selected: usize,
    previous: usize,
    open: bool,
    dirty: bool,
    style: Style,
    frame: Frame = .{},

    pub fn init(source: []const u8, options: []const []const u8, style: Style) Select {
        // Find which option is selected
        var selected: usize = 0;
        for (options, 0..) |o, idx| {
            if (std.mem.eql(u8, o, source)) {
                selected = idx;
                break;
            }
        }
        return .{
            .source = source,
            .options = options,
            .selected = selected,
            .previous = selected,
            .open = false,
            .dirty = false,
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

    fn write(ptr: *anyopaque, writer: *Writer, _: *Cursor, frame: Frame, focused: bool) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.frame = frame;
        if (self.open) self.frame.h = @intCast(1 + self.options.len);
        const x = frame.x;
        const y = frame.y;

        // Get longest option
        var max_width: u8 = 0;
        for (self.options) |o| {
            if (o.len > max_width) max_width = @intCast(o.len);
        }

        // Get text - when open show previous (don't update header until confirmed)
        const text = if (self.open)
            self.options[self.previous]
        else if (self.dirty)
            self.options[self.selected]
        else
            self.source;

        // Figure out color
        const color = if (self.dirty)
            if (self.style.tertiary_color.len > 0) self.style.tertiary_color else Color.yellow
        else if (self.style.color.len > 0)
            self.style.color
        else
            Color.text;

        const secondary_color = if (self.style.secondary_color.len > 0) self.style.secondary_color else Color.subtext1;
        const bg_color = if (self.style.bg_color.len > 0) self.style.bg_color else Color.bg_overlay0;
        const secondary_bg_color = if (self.style.secondary_bg_color.len > 0) self.style.secondary_bg_color else Color.bg_overlay1;

        // Start drawing
        try utils.moveTo(writer, x, y);
        try writer.writeAll(bg_color);
        if (focused and !self.open) {
            try writer.writeAll(color);
            try writer.writeAll("▎");
            for (0..self.style.padding_left -| 1) |_| try writer.writeAll(" ");
            try writer.writeAll(Color.reset);
            // if (self.style.bg_color.len > 0) try writer.writeAll(self.style.bg_color);
            try writer.writeAll(bg_color);
        } else {
            for (0..self.style.padding_left) |_| try writer.writeAll(" ");
        }
        try writer.writeAll(color);
        try writer.writeAll(text);

        const pad = max_width - @as(u8, @intCast(text.len));
        for (0..pad) |_| try writer.writeAll(" ");
        if (self.open) try writer.writeAll(" " ++ icons.caret_up) else try writer.writeAll(" " ++ icons.caret_down);
        for (0..self.style.padding_right) |_| try writer.writeAll(" ");
        try writer.writeAll(Color.reset);

        // Options dropdown
        if (self.open) {
            var next_row = y + 1;

            for (self.options, 0..) |o, i| {
                const ddpad = max_width + self.style.padding_right + self.style.padding_left + utils.displayWidth(icons.caret_down) - @as(u8, @intCast(o.len));
                try utils.moveTo(writer, x, next_row);
                // try writer.writeAll(Color.bg_mauve_darker);
                // try writer.writeAll(Color.mauve_medium);
                try writer.writeAll(secondary_bg_color);
                try writer.writeAll(secondary_color);

                if (i == self.selected) {
                    try writer.writeAll("▎");
                    for (0..self.style.padding_left -| 1) |_| try writer.writeAll(" ");
                } else {
                    for (0..self.style.padding_left) |_| try writer.writeAll(" ");
                }
                try writer.writeAll(o);
                for (0..ddpad) |_| try writer.writeAll(" ");
                next_row += 1;
            }

            try writer.writeAll(Color.reset);
        }
    }

    fn handleKey(ptr: *anyopaque, key: u8, mq: *MessageQueue) KeyResult {
        const self: *Self = @ptrCast(@alignCast(ptr));

        if (!self.open) {
            switch (key) {
                '\r', '\n' => {
                    self.previous = self.selected;
                    self.open = true;
                    mq.post(.render);
                    return .consumed;
                },
                else => return .ignored,
            }
        }

        switch (key) {
            'j' => {
                if (self.selected < self.options.len - 1) {
                    self.selected += 1;
                    mq.post(.render);
                }
                return .consumed;
            },
            'k' => {
                if (self.selected > 0) {
                    self.selected -= 1;
                    mq.post(.render);
                }
                return .consumed;
            },
            '\r', '\n', 'l' => {
                self.open = false;
                self.dirty = true;
                mq.post(.render);
                return .consumed;
            },
            0x1b, 'h' => {
                self.selected = self.previous;
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
                if (row < self.options.len) self.selected = row;
            }
            return .consumed;
        }

        if (m.press and !m.move) {
            if (self.open) {
                self.open = false;
                self.dirty = true;
                return .changed;
            } else {
                self.previous = self.selected;
                self.open = true;
            }
            return .consumed;
        }

        return .ignored;
    }
};
