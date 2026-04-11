const std = @import("std");
const Color = @import("../../color.zig");
const icons = @import("../../icons.zig");
const utils = @import("../../utils.zig");
const ComponentInterface = @import("../component.zig").ComponentInterface;
const Cursor = @import("../component.zig").Cursor;
const Frame = @import("../component.zig").Frame;
const KeyResult = @import("../component.zig").KeyResult;
const Style = @import("../component.zig").Style;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;

pub const Select = struct {
    interface: ComponentInterface,
    source: []const u8,
    options: []const []const u8,
    selected: usize,
    previous: usize,
    open: bool,
    dirty: bool,
    focused: bool,
    style: Style,

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
            .interface = .{
                .write_fn = write,
                .handleKey_fn = handleKey,
            },
            .source = source,
            .options = options,
            .selected = selected,
            .previous = selected,
            .open = false,
            .dirty = false,
            .focused = false,
            .style = style,
        };
    }

    fn write(
        iface: *ComponentInterface,
        writer: *std.Io.Writer,
        _: *Cursor,
        frame: Frame,
    ) anyerror!void {
        const self: *Select = @fieldParentPtr("interface", iface);
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
        // if (self.style.bg_color.len > 0) try writer.writeAll(self.style.bg_color);
        try writer.writeAll(bg_color);
        if (self.focused and !self.open) {
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

    fn handleKey(iface: *ComponentInterface, key: u8, mq: *MessageQueue) KeyResult {
        const self: *Select = @fieldParentPtr("interface", iface);

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
};
