const std = @import("std");
const Color = @import("../../color.zig");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Component = @import("../Component.zig");
const Writer = std.Io.Writer;
const Cursor = @import("../../canvas.zig").Cursor;
const Frame = Component.Frame;
const KeyResult = @import("../../input.zig").KeyResult;
const Mouse = @import("../../input.zig").Mouse;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;
const Thermostat = @import("../../state/models/thermostat.zig").Thermostat;
const TextDisplay = @import("../component/text_display.zig").TextDisplay;
const TextInput = @import("../component/text_input.zig").TextInput;
const Toggle = @import("../component/toggle.zig").Toggle;
const KeyValList = @import("../component/key_val_list.zig").KeyValList;
const Select = @import("../component/select.zig").Select;

pub const ThermostatView = struct {
    const Self = @This();

    arena: ArenaAllocator,
    source: *Thermostat,
    vsource: *Thermostat,
    list: KeyValList,

    pub fn init(a: Allocator, vsrc: *Thermostat, src: *Thermostat) !ThermostatView {
        var self = ThermostatView{
            .arena = ArenaAllocator.init(a),
            .source = src,
            .vsource = vsrc,
            .list = undefined,
        };
        self.list = KeyValList.init(self.arena.allocator());

        try self.list.addDisplay("name", &vsrc.name, .{});
        try self.list.addDisplay("model", &vsrc.model_number, .{});
        try self.list.addDisplay("serial", &vsrc.serial_number, .{});
        try self.list.addDisplay("firmware", &vsrc.firmware_version, .{});
        try self.list.addDisplay("watts", &vsrc.watts, .{});
        try self.list.addInput("scale", &src.temperature_scale, &vsrc.temperature_scale, .{});
        // try self.list.addInput("mode", &src.hvac_mode, &vsrc.hvac_mode, .{});
        try self.list.addSelect("mode", &src.hvac_mode, &vsrc.hvac_mode, .{});
        try self.list.addDisplay("supported", &src.supported_hvac_modes, .{});
        try self.list.addDisplay("state", &src.hvac_state, .{});
        try self.list.addInput("fan", &src.fan_mode, &vsrc.fan_mode, .{});
        try self.list.addDisplay("supported", &src.supported_fan_modes, .{});
        try self.list.addDisplay("fan state", &src.fan_state, .{});

        inline for (.{
            .{ "humidity", &vsrc.current_humidity },
            .{ "humidity scale", &vsrc.humidity_scale },
            .{ "delta", &vsrc.min_auto_delta },
            .{ "cycle rate", &vsrc.cycle_rate },
        }) |row| {
            if (row[1].* != null) try self.list.addDisplay(row[0], row[1], .{});
        }

        try self.list.addDisplay("temp", &vsrc.current_temperature, .{ .style = .{ .suffix = "°", .color = Color.overlay2 } });
        inline for (.{ "heat", "cool", "auto" }) |name| {
            if (@field(vsrc.setpoints, name) != null) {
                try self.list.addInput(name, &@field(src.setpoints, name).?.value, &@field(vsrc.setpoints, name).?.value, .{ .style = .{ .suffix = "°" } });
                try self.list.addInput(name ++ " min", &@field(src.setpoints, name).?.min, &@field(vsrc.setpoints, name).?.min, .{ .style = .{ .suffix = "°" } });
                try self.list.addInput(name ++ " max", &@field(src.setpoints, name).?.max, &@field(vsrc.setpoints, name).?.max, .{ .style = .{ .suffix = "°" } });
            }
        }
        try self.list.addDisplay("online", &vsrc.offline, .{ .invert = true });
        if (vsrc.ui_enabled != null)
            try self.list.addToggle(
                "ui enabled",
                &src.ui_enabled,
                &vsrc.ui_enabled,
                true,
                false,
                .{},
            );

        self.list.cursor = 0;
        return self;
    }

    pub fn deinit(self: *ThermostatView) void {
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
