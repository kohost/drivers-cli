const std = @import("std");
const Color = @import("../../color.zig");
const utils = @import("../../utils.zig");
const comp = @import("../component.zig");
const Component = comp.Component;
const KeyResult = comp.KeyResult;
const Cursor = comp.Cursor;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;
const Writer = std.Io.Writer;
const displayWidth = utils.displayWidth;

pub const Panel = struct {
    top_left: []const u8,
    top_right: []const u8,
    bottom_left: []const u8,
    bottom_right: []const u8,
    focused: bool,
    children: [4]Component,
    child_count: u8,

    pub fn init(opts: struct {
        top_left: []const u8 = "",
        top_right: []const u8 = "",
        bottom_left: []const u8 = "",
        bottom_right: []const u8 = "",
        focused: bool = false,
    }) Panel {
        return .{
            .top_left = opts.top_left,
            .top_right = opts.top_right,
            .bottom_left = opts.bottom_left,
            .bottom_right = opts.bottom_right,
            .focused = opts.focused,
            .children = undefined,
            .child_count = 0,
        };
    }

    pub fn setChildren(self: *Panel, new_children: []const Component) void {
        const count: u8 = @intCast(@min(new_children.len, self.children.len));
        for (0..count) |i| {
            self.children[i] = new_children[i];
        }
        self.child_count = count;
    }

    pub fn component(self: *Panel) Component {
        return .{ .ptr = @ptrCast(self), .vtable = &.{
            .write = write,
            .handleKey = handleKey,
        } };
    }

    fn handleKey(ptr: *anyopaque, key: u8, mq: *MessageQueue) KeyResult {
        const self: *Panel = @ptrCast(@alignCast(ptr));
        if (self.child_count > 0) {
            return self.children[0].handleKey(key, mq);
        }
        return .ignored;
    }

    fn write(
        ptr: *anyopaque,
        writer: *Writer,
        x: u16,
        y: u16,
        w: u16,
        h: u16,
        cursor: *Cursor,
    ) anyerror!void {
        const self: *Panel = @ptrCast(@alignCast(ptr));
        const inner = w -| 2;
        const border = if (self.focused) Color.overlay1 else Color.dim;
        const label = if (self.focused) Color.lavender else Color.dim ++ Color.lavender;

        // Top border
        try utils.moveTo(writer, x, y);
        try writer.writeAll(border);
        try writer.writeAll("╭");
        if (self.top_left.len > 0) {
            try writer.writeAll("─ ");
            try writer.writeAll(label);
            try writer.writeAll(self.top_left);
            try writer.writeAll(border);
            try writer.writeAll(" ");
        }
        var used: u16 = 0;
        if (self.top_left.len > 0) used += displayWidth(self.top_left) + 3;
        if (self.top_right.len > 0) used += displayWidth(self.top_right) + 3;
        const dashes = inner -| used;
        for (0..dashes) |_| try writer.writeAll("─");
        if (self.top_right.len > 0) {
            try writer.writeAll(" ");
            try writer.writeAll(label);
            try writer.writeAll(self.top_right);
            try writer.writeAll(border);
            try writer.writeAll(" ─");
        }
        try writer.writeAll("╮");
        try writer.writeAll(Color.reset);

        // Middle rows
        var row: u16 = 1;
        while (row < h - 1) : (row += 1) {
            try utils.moveTo(writer, x, y + row);
            try writer.writeAll(border);
            try writer.writeAll("│");
            try writer.writeAll(Color.reset);
            try utils.moveTo(writer, x + w - 1, y + row);
            try writer.writeAll(border);
            try writer.writeAll("│");
            try writer.writeAll(Color.reset);
        }

        // Bottom border
        try utils.moveTo(writer, x, y + h - 1);
        try writer.writeAll(border);
        try writer.writeAll("╰");
        if (self.bottom_left.len > 0) {
            try writer.writeAll("─ ");
            try writer.writeAll(label);
            try writer.writeAll(self.bottom_left);
            try writer.writeAll(border);
            try writer.writeAll(" ");
        }
        var bottom_used: u16 = 0;
        if (self.bottom_left.len > 0) bottom_used += displayWidth(self.bottom_left) + 3;
        if (self.bottom_right.len > 0) bottom_used += displayWidth(self.bottom_right) + 3;
        const bottom_dashes = inner -| bottom_used;
        for (0..bottom_dashes) |_| try writer.writeAll("─");
        if (self.bottom_right.len > 0) {
            try writer.writeAll(" ");
            try writer.writeAll(label);
            try writer.writeAll(self.bottom_right);
            try writer.writeAll(border);
            try writer.writeAll(" ─");
        }
        try writer.writeAll("╯");
        try writer.writeAll(Color.reset);

        // Draw children
        const cy = y + 1;
        const inner_x = x + 2;
        const inner_w = w -| 4;
        for (self.children[0..self.child_count]) |child| {
            if (cy >= y + h - 1) break;
            const remaining = (y + h - 1) - cy;
            try child.write(writer, inner_x, cy, inner_w, remaining, cursor);
        }
    }

};
