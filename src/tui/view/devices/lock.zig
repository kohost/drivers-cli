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

        // try self.createDisplayRow("name", &vsrc.name, .{});
        try self.createTextInputRow("name", &src.name, &vsrc.name, .{});
        try self.createDisplayRow("model", &vsrc.model_number, .{});
        try self.createDisplayRow("serial", &vsrc.serial_number, .{});
        try self.createDisplayRow("firmware", &vsrc.firmware_version, .{});
        try self.createDisplayRow("watts", &vsrc.watts, .{});
        try self.createTextInputRow("mode", &src.mode, &vsrc.mode, .{});
        try self.createDisplayRow("supported", &vsrc.supported_modes, .{});

        if (vsrc.state != null) try self.createToggleRow("state", &src.state, &vsrc.state, .locked, .unlocked, icons.lock, icons.unlock) else {
            const lockAlloc = self.arena.allocator();
            const p = try lockAlloc.create([]const u8);
            p.* = icons.lock_alert;
            try self.createDisplayRow("state", p, .{ .style = .{ .color = Color.red } });
        }
        if (vsrc.offline) |*val| {
            try self.createDisplayRow("online", val, .{ .invert = true });
        }
        if (vsrc.battery != null) try self.createDisplayRow("battery", &vsrc.battery, .{});

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

    // Row builders
    fn createDisplayRow(
        s: *LockView,
        lbl: []const u8,
        src: anytype,
        opts: TextDisplay(std.meta.Child(@TypeOf(src))).Options,
    ) !void {
        const T = std.meta.Child(@TypeOf(src));
        const a = s.arena.allocator();
        const d = try a.create(TextDisplay(T));
        d.* = .init(src, opts);
        try s.list.addRow(lbl, d.component());
    }

    fn createTextInputRow(
        self: *LockView,
        lbl: []const u8,
        src: anytype,
        vsrc: anytype,
        opts: TextInput(std.meta.Child(@TypeOf(src))).Options,
    ) !void {
        const T = std.meta.Child(@TypeOf(src));
        const a = self.arena.allocator();
        const i = try a.create(TextInput(T));
        i.* = .init(src, vsrc, opts);
        try self.list.addRow(lbl, i.component());
    }

    fn createToggleRow(
        self: *LockView,
        lbl: []const u8,
        src: anytype,
        vsrc: anytype,
        on: std.meta.Child(@TypeOf(vsrc)),
        off: std.meta.Child(@TypeOf(vsrc)),
        active: []const u8,
        inactive: []const u8,
    ) !void {
        const T = std.meta.Child(@TypeOf(vsrc));
        const a = self.arena.allocator();
        const i = try a.create(Toggle(T));
        i.* = .init(.{
            .source = src,
            .vsource = vsrc,
            .on = on,
            .off = off,
            .active = active,
            .inactive = inactive,
        });
        try self.list.addRow(lbl, i.component());
    }
};
