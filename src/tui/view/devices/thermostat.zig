const std = @import("std");
const Color = @import("../../color.zig");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ComponentInterface = @import("../component.zig").ComponentInterface;
const Cursor = @import("../component.zig").Cursor;
const Frame = @import("../component.zig").Frame;
const KeyResult = @import("../component.zig").KeyResult;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;
const Thermostat = @import("../../state/models/thermostat.zig").Thermostat;
const TextDisplay = @import("../component/text_display.zig").TextDisplay;
const TextInput = @import("../component/text_input.zig").TextInput;
const KeyVal = @import("../component/key_val_list.zig").KeyVal;
const KeyValList = @import("../component/key_val_list.zig").KeyValList;

pub const ThermostatView = struct {
    interface: ComponentInterface,
    arena: ArenaAllocator,
    frame_arena: ArenaAllocator, // for per frame formatted strings
    thermostat: *const Thermostat,
    list: KeyValList,

    // Default props
    const Row = enum(usize) {
        name,
        model,
        serial,
        firmware,
        watts,
        online,
        scale,
        temp,
        mode,
        hvac_state,
        fan,
        fan_state,
    };

    pub fn init(a: Allocator, thermostat: *const Thermostat) !ThermostatView {
        var self = ThermostatView{
            .interface = .{
                .write_fn = write,
                .handleKey_fn = handleKey,
            },
            .arena = ArenaAllocator.init(a),
            .frame_arena = ArenaAllocator.init(a),
            .thermostat = thermostat,
            .list = undefined,
        };
        self.list = KeyValList.init(self.arena.allocator());

        try self.addDisplay("name", thermostat.name);
        try self.addDisplay("model", thermostat.model_number);
        try self.addDisplay("serial", thermostat.serial_number);
        try self.addDisplay("firmware", thermostat.firmware_version);
        try self.addDisplay("watts", "");
        try self.addDisplay("online", if (thermostat.offline) Color.red ++ "✗" ++ Color.reset else Color.green ++ "✔︎" ++ Color.reset);
        try self.addDisplay("scale", @tagName(thermostat.temperature_scale));
        try self.addDisplay("temp", "");
        try self.addInput("mode", @tagName(thermostat.hvac_mode));
        try self.addDisplay("state", if (thermostat.hvac_state) |s| @tagName(s) else "-");
        try self.addInput("fan", @tagName(thermostat.fan_mode));
        try self.addDisplay("state", if (thermostat.fan_state) |s| @tagName(s) else "-");

        if (thermostat.current_humidity) |h| {
            const humidity_str = try std.fmt.allocPrint(self.arena.allocator(), "{d:.1}", .{h});
            try self.addDisplay("humidity", humidity_str);
        }
        if (thermostat.humidity_scale) |s| {
            try self.addDisplay("humidity scale", @tagName(s));
        }
        if (thermostat.min_auto_delta) |d| {
            const delta_str = try std.fmt.allocPrint(self.arena.allocator(), "{d}", .{d});
            try self.addDisplay("delta", delta_str);
        }
        if (thermostat.cycle_rate) |r| {
            const cycle_rate_str = try std.fmt.allocPrint(self.arena.allocator(), "{d}", .{r});
            try self.addDisplay("cycle rate", cycle_rate_str);
        }

        if (thermostat.ui_enabled) |e| {
            try self.addDisplay("ui enabled", if (e) Color.green ++ "✔︎" ++ Color.reset else Color.red ++ "✗" ++ Color.reset);
        }

        if (thermostat.setpoints.heat) |sp| try self.addSetpoint("heat", sp);
        if (thermostat.setpoints.cool) |sp| try self.addSetpoint("cool", sp);
        if (thermostat.setpoints.auto) |sp| try self.addSetpoint("auto", sp);

        self.list.focused = 0;
        return self;
    }

    pub fn deinit(self: *ThermostatView) void {
        self.arena.deinit();
        self.frame_arena.deinit();
    }

    fn write(
        iface: *ComponentInterface,
        writer: *std.Io.Writer,
        cursor: *Cursor,
        frame: Frame,
    ) anyerror!void {
        const self: *ThermostatView = @fieldParentPtr("interface", iface);

        // Scratch mem reset every write call
        _ = self.frame_arena.reset(.retain_capacity);
        const fa = self.frame_arena.allocator();

        // Sync live fields from current thermostat state
        // const name_display = self.getComponent(TextDisplay, Row.name);
        // name_display.source = self.thermostat.name;
        self.getComponent(TextDisplay, Row.name).source = self.thermostat.name;
        self.getComponent(TextDisplay, Row.model).source = self.thermostat.model_number;
        self.getComponent(TextDisplay, Row.serial).source = self.thermostat.serial_number;
        self.getComponent(TextDisplay, Row.firmware).source = self.thermostat.firmware_version;
        self.getComponent(TextDisplay, Row.watts).source = std.fmt.allocPrint(fa, "{d}", .{self.thermostat.watts}) catch "?";
        self.getComponent(TextDisplay, Row.online).source = if (self.thermostat.offline) Color.red ++ "✗" ++ Color.reset else Color.green ++ "✔︎" ++ Color.reset;
        self.getComponent(TextInput, Row.mode).source = @tagName(self.thermostat.hvac_mode);
        self.getComponent(TextDisplay, Row.temp).source = std.fmt.allocPrint(fa, "{d}", .{self.thermostat.current_temperature}) catch "?";
        self.getComponent(TextInput, Row.scale).source = @tagName(self.thermostat.temperature_scale);
        self.getComponent(TextInput, Row.fan).source = @tagName(self.thermostat.fan_mode);
        self.getComponent(TextDisplay, Row.hvac_state).source = if (self.thermostat.hvac_state) |s| @tagName(s) else "-";
        self.getComponent(TextDisplay, Row.fan_state).source = if (self.thermostat.fan_state) |s| @tagName(s) else "-";

        if (self.thermostat.current_humidity) |h| {
            if (self.list.get(TextDisplay, "humidity")) |td| td.source = std.fmt.allocPrint(fa, "{d}", .{h}) catch "?";
        }
        if (self.thermostat.humidity_scale) |s| {
            if (self.list.get(TextInput, "humidity scale")) |ti| ti.source = @tagName(s);
        }
        if (self.thermostat.min_auto_delta) |d| {
            if (self.list.get(TextDisplay, "delta")) |td| td.source = std.fmt.allocPrint(fa, "{d}", .{d}) catch "?";
        }
        if (self.thermostat.cycle_rate) |cr| {
            if (self.list.get(TextDisplay, "cycle rate")) |td| td.source = std.fmt.allocPrint(fa, "{d}", .{cr}) catch "?";
        }
        if (self.thermostat.ui_enabled) |enabled| {
            if (self.list.get(TextDisplay, "ui enabled")) |td| td.source = if (enabled) Color.green ++ "✔︎" ++ Color.reset else Color.red ++ "✗" ++ Color.reset;
        }
        if (self.thermostat.setpoints.heat) |sp| {
            if (self.list.get(TextInput, "heat")) |ti| ti.source = std.fmt.allocPrint(fa, "{d:.1}", .{sp.value}) catch "?";
            if (self.list.get(TextInput, "heat min")) |ti| ti.source = std.fmt.allocPrint(fa, "{d:.1}", .{sp.min}) catch "?";
            if (self.list.get(TextInput, "heat max")) |ti| ti.source = std.fmt.allocPrint(fa, "{d:.1}", .{sp.max}) catch "?";
        }
        if (self.thermostat.setpoints.cool) |sp| {
            if (self.list.get(TextInput, "cool")) |ti| ti.source = std.fmt.allocPrint(fa, "{d:.1}", .{sp.value}) catch "?";
            if (self.list.get(TextInput, "cool min")) |ti| ti.source = std.fmt.allocPrint(fa, "{d:.1}", .{sp.min}) catch "?";
            if (self.list.get(TextInput, "cool max")) |ti| ti.source = std.fmt.allocPrint(fa, "{d:.1}", .{sp.max}) catch "?";
        }
        if (self.thermostat.setpoints.auto) |sp| {
            if (self.list.get(TextInput, "auto")) |ti| ti.source = std.fmt.allocPrint(fa, "{d:.1}", .{sp.value}) catch "?";
            if (self.list.get(TextInput, "auto min")) |ti| ti.source = std.fmt.allocPrint(fa, "{d:.1}", .{sp.min}) catch "?";
            if (self.list.get(TextInput, "auto max")) |ti| ti.source = std.fmt.allocPrint(fa, "{d:.1}", .{sp.max}) catch "?";
        }

        try self.list.interface.write(writer, cursor, frame);
    }

    fn handleKey(iface: *ComponentInterface, key: u8, mq: *MessageQueue) KeyResult {
        const self: *ThermostatView = @fieldParentPtr("interface", iface);
        return self.list.interface.handleKey(key, mq);
    }

    fn addDisplay(self: *ThermostatView, label: []const u8, source: []const u8) !void {
        const alloc = self.arena.allocator();
        const d = try alloc.create(TextDisplay);
        d.* = TextDisplay.init(source, .{});
        try self.list.addRow(label, &d.interface);
    }

    fn addInput(self: *ThermostatView, label: []const u8, source: []const u8) !void {
        const alloc = self.arena.allocator();
        const i = try alloc.create(TextInput);
        i.* = TextInput.init(source);
        try self.list.addRow(label, &i.interface);
    }

    fn addSetpoint(self: *ThermostatView, name: []const u8, sp: Thermostat.Setpoint) !void {
        const alloc = self.arena.allocator();
        try self.addInput(name, try std.fmt.allocPrint(alloc, "{d:.1}", .{sp.value}));
        try self.addInput(try std.fmt.allocPrint(alloc, "{s} min", .{name}), try std.fmt.allocPrint(alloc, "{d:.1}", .{sp.min}));
        try self.addInput(try std.fmt.allocPrint(alloc, "{s} max", .{name}), try std.fmt.allocPrint(alloc, "{d:.1}", .{sp.max}));
    }

    fn getComponent(self: *ThermostatView, comptime T: type, row: Row) *T {
        const r = self.list.rows.items[@intFromEnum(row)];
        return @fieldParentPtr("interface", r.value);
    }
};
