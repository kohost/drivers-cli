const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Component = @import("../Component.zig");
const Writer = std.Io.Writer;
const Cursor = @import("../../canvas.zig").Cursor;
const Frame = Component.Frame;
const KeyResult = @import("../../input.zig").KeyResult;
const Mouse = @import("../../input.zig").Mouse;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;
const MediaSource = @import("../../state/models/mediaSource.zig").MediaSource;
const KeyValList = @import("../component/key_val_list.zig").KeyValList;
const Color = @import("../../color.zig");
const icons = @import("../../view/icons.zig");

pub const Discriminator = enum { fan, irrigation, light };
pub const MediaSourceView = struct {
    const Self = @This();

    arena: ArenaAllocator,
    source: *MediaSource,
    vsource: *MediaSource,
    list: KeyValList,

    pub fn init(a: Allocator, vsrc: *MediaSource, src: *MediaSource) !MediaSourceView {
        var self = MediaSourceView{
            .arena = ArenaAllocator.init(a),
            .source = src,
            .vsource = vsrc,
            .list = undefined,
        };
        self.list = KeyValList.init(self.arena.allocator());

        try self.list.addDisplay("name", &src.name, .{});
        try self.list.addDisplay("model", &vsrc.model_number, .{});
        try self.list.addDisplay("serial", &vsrc.serial_number, .{});
        try self.list.addDisplay("firmware", &vsrc.firmware_version, .{});
        try self.list.addDisplay("watts", &vsrc.watts, .{});
        // try self.list.addToggle("state", &src.state, &vsrc.state, .on, .off, stateDisplay);
        try self.list.addDisplay("online", &vsrc.offline, .{ .invert = true });

        self.list.cursor = 0;
        return self;
    }

    pub fn deinit(self: *MediaSourceView) void {
        self.arena.deinit();
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
        return self.list.component().handleMouse(m, mq);
    }

    fn write(ptr: *anyopaque, w: *Writer, c: *Cursor, f: Frame, focused: bool) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        try self.list.component().write(w, c, f, focused);
    }

    fn handleKey(ptr: *anyopaque, key: u8, mq: *MessageQueue) KeyResult {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.list.component().handleKey(key, mq);
    }
};
