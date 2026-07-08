const std = @import("std");
const Layout = @import("view/layout.zig").Layout;

pub const Canvas = struct {
    alloc: std.mem.Allocator,
    buf: []u8,
    w: std.Io.File.Writer,

    pub fn init(alloc: std.mem.Allocator, io: std.Io, stdout: std.Io.File) !Canvas {
        const buf = try alloc.alloc(u8, 16384);
        return .{
            .alloc = alloc,
            .buf = buf,
            .w = stdout.writer(io, buf),
        };
    }

    pub fn deinit(self: *Canvas) void {
        self.alloc.free(self.buf);
    }

    pub fn render(self: *Canvas, layout: *Layout) !void {
        std.log.scoped(.canvas).info("render\n", .{});
        try layout.write(&self.w.interface);
        try self.w.interface.writeAll(layout.pointer);
        try self.w.interface.flush();
    }
};

pub const Cursor = struct {
    x: u16 = 0,
    y: u16 = 0,
    visible: bool = false,
};
