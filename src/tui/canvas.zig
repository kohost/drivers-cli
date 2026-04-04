const std = @import("std");
const Layout = @import("view/layout.zig").Layout;
const Allocator = std.mem.Allocator;
const File = std.fs.File;

pub const Canvas = struct {
    alloc: Allocator,
    stdout: File,
    write_buf: []u8,
    w: std.fs.File.Writer,

    pub fn init(alloc: Allocator, stdout: File) !Canvas {
        const write_buf = try alloc.alloc(u8, 16384);
        return .{
            .alloc = alloc,
            .stdout = stdout,
            .write_buf = write_buf,
            .w = stdout.writer(write_buf),
        };
    }

    pub fn deinit(self: *Canvas) void {
        self.alloc.free(self.write_buf);
    }

    pub fn render(self: *Canvas, layout: *Layout) !void {
        try layout.write(&self.w.interface);
        try self.w.interface.flush();
    }
};
