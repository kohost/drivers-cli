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
const Lock = @import("../../state/models/lock.zig").Lock;
const TextDisplay = @import("../component/text_display.zig").TextDisplay;
const TextInput = @import("../component/text_input.zig").TextInput;
const KeyValList = @import("../component/key_val_list.zig").KeyValList;
const Toggle = @import("../component/toggle.zig").Toggle;
const icons = @import("../icons.zig");
const Color = @import("../../color.zig");

pub const LockView = struct {
    const Self = @This();

    arena: ArenaAllocator,
    source: *Lock,
    vsource: *Lock,
    list: KeyValList,

    pub fn init(a: Allocator, vsrc: *Lock, src: *Lock) !LockView {
        var self = LockView{
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
        try self.list.addSelect("mode", &src.mode, &vsrc.mode, self.source.supported_modes);

        if (vsrc.state != null) try self.list.addToggle("state", &src.state, &vsrc.state, .locked, .unlocked, .{ .active = icons.lock, .inactive = icons.unlock }) else {
            const lockAlloc = self.arena.allocator();
            const p = try lockAlloc.create([]const u8);
            p.* = icons.lock_alert;
            try self.list.addDisplay("state", p, .{ .style = .{ .color = Color.red } });
        }
        if (vsrc.offline) |*val| {
            try self.list.addDisplay("online", val, .{ .invert = true });
        }
        if (vsrc.battery != null) try self.list.addDisplay("battery", &vsrc.battery, .{});

        self.list.cursor = 0;
        return self;
    }

    pub fn deinit(self: *LockView) void {
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
