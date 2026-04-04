const std = @import("std");
const Color = @import("../../color.zig");
const utils = @import("../../utils.zig");

const style_bold = "\x1b[1m";

pub const Header = struct {
    x: u16,
    y: u16,
    width: u16,
    title: []const u8,
    subtitle: []const u8,
    gap: u16,
    height: u16 = 1,

    pub fn init(opts: struct {
        x: u16 = 1,
        y: u16 = 1,
        width: u16,
        title: []const u8,
        subtitle: []const u8 = "",
    }) Header {
        const title_len = utils.displayWidth(opts.title);
        const sub_len = utils.displayWidth(opts.subtitle);
        return .{
            .x = opts.x,
            .y = opts.y,
            .width = opts.width,
            .title = opts.title,
            .subtitle = opts.subtitle,
            .gap = opts.width -| title_len -| sub_len -| 1,
        };
    }

    pub fn write(self: *const Header, writer: *std.Io.Writer) !void {
        try utils.moveTo(writer, self.x, self.y);
        try writer.writeAll(style_bold ++ Color.pink);
        try writer.writeAll(self.title);
        try writer.writeAll(Color.reset);
        for (0..self.gap) |_| try writer.writeAll(" ");
        try writer.writeAll(Color.pink ++ Color.dim);
        try writer.writeAll(self.subtitle);
        try writer.writeAll(Color.reset);
    }
};
