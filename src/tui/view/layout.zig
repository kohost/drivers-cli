const std = @import("std");
const Header = @import("component/header.zig").Header;
const Menu = @import("component/menu.zig").Menu;
const Footer = @import("component/footer.zig").Footer;
const View = @import("../view.zig").View;
const Cursor = @import("../canvas.zig").Cursor;
const utils = @import("../utils.zig");

pub const Layout = struct {
    header: Header,
    menu: Menu,
    footer: Footer,
    view: *View,
    pointer: []const u8 = utils.pointer_default,

    pub fn init(cols: u16, rows: u16, view: *View) Layout {
        return .{
            .header = Header.init(.{
                .x = 2,
                .width = cols,
                .title = "🌸 Kohost",
                .subtitle = std.mem.trimEnd(
                    u8,
                    @import("build_options").version,
                    "\n\r",
                ),
            }),
            .menu = Menu.init(.{
                .x = 2,
                .y = 3,
                .items = &.{ "Driver", "API", "Logs", "Settings" },
                .focused = true,
            }),
            .footer = Footer.init(.{ .y = rows, .width = cols }),
            .view = view,
        };
    }

    pub fn write(self: *Layout, writer: *std.Io.Writer) !void {
        var cursor = Cursor{};
        try writer.writeAll(utils.clear_screen ++ utils.cursor_home ++ comptime utils.rm(.cursor));
        try self.header.write(writer);
        try self.menu.write(writer);
        try self.view.write(writer, &cursor);
        try self.footer.write(writer, &cursor);

        if (cursor.visible) {
            try utils.moveTo(writer, cursor.x, cursor.y);
            try writer.writeAll(utils.sm(.cursor));
        }
    }

    pub fn resize(self: *Layout, cols: u16, rows: u16) void {
        self.header = Header.init(.{
            .x = 2,
            .width = cols,
            .title = "🌸 Kohost",
            .subtitle = self.header.subtitle,
        });
        self.footer.y = rows;
        self.footer.width = cols;
    }
};

pub const Frame = struct {
    x: u16 = 0,
    y: u16 = 0,
    w: u16 = 0,
    h: u16 = 0,
};
