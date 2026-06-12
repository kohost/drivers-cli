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
const Toggle = @import("../component/toggle.zig").Toggle;
const KeyValList = @import("../component/key_val_list.zig").KeyValList;

const Read = *const fn (*const anyopaque, *std.Io.Writer) anyerror!void;
const Write = *const fn (*anyopaque, []const u8) anyerror!void;

pub const ThermostatView = struct {
    interface: ComponentInterface,
    arena: ArenaAllocator,
    frame_arena: ArenaAllocator, // scratch for wire fragments on commit
    device: *Thermostat,
    vdevice: *Thermostat,
    list: KeyValList,

    pub fn init(a: Allocator, vdevice: *Thermostat, device: *Thermostat) !ThermostatView {
        var self = ThermostatView{
            .interface = .{
                .write_fn = write,
                .handleKey_fn = handleKey,
            },
            .arena = ArenaAllocator.init(a),
            .frame_arena = ArenaAllocator.init(a),
            .device = device,
            .vdevice = vdevice,
            .list = undefined,
        };
        self.list = KeyValList.init(self.arena.allocator());

        try self.bindDisplay("name", formatName);
        try self.bindDisplay("model", formatModel);
        try self.bindDisplay("serial", formatSerial);
        try self.bindDisplay("firmware", formatFirmware);
        try self.bindDisplay("watts", formatWatts);
        try self.bindDisplay("online", formatOnline);
        try self.bindDisplay("scale", formatScale);
        try self.bindDisplay("temp", formatTemp);
        try self.createTextInputRow("mode", readMode, writeMode);
        try self.bindDisplay("state", formatHvacState);
        try self.createTextInputRow("fan", readFan, writeFan);
        try self.bindDisplay("fan state", formatFanState);

        if (vdevice.current_humidity != null) try self.bindDisplay("humidity", formatHumidity);
        if (vdevice.humidity_scale != null) try self.bindDisplay("humidity scale", formatHumidityScale);
        if (vdevice.min_auto_delta != null) try self.bindDisplay("delta", formatDelta);
        if (vdevice.cycle_rate != null) try self.bindDisplay("cycle rate", formatCycleRate);
        if (vdevice.ui_enabled != null) try self.createToggleRow("ui enabled", &vdevice.ui_enabled, &device.ui_enabled);

        if (vdevice.setpoints.heat != null) {
            try self.bindSetpoint("heat", .heat, .value);
            try self.bindSetpoint("heat min", .heat, .min);
            try self.bindSetpoint("heat max", .heat, .max);
        }
        if (vdevice.setpoints.cool != null) {
            try self.bindSetpoint("cool", .cool, .value);
            try self.bindSetpoint("cool min", .cool, .min);
            try self.bindSetpoint("cool max", .cool, .max);
        }
        if (vdevice.setpoints.auto != null) {
            try self.bindSetpoint("auto", .auto, .value);
            try self.bindSetpoint("auto min", .auto, .min);
            try self.bindSetpoint("auto max", .auto, .max);
        }

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
        // Components pull their own values from the model and format themselves.
        try self.list.interface.write(writer, cursor, frame);
    }

    fn handleKey(iface: *ComponentInterface, key: u8, mq: *MessageQueue) KeyResult {
        const self: *ThermostatView = @fieldParentPtr("interface", iface);
        const result = self.list.interface.handleKey(key, mq);
        if (result == .changed) {
            const idx = self.list.focused orelse return .consumed;
            const row = self.list.rows.items[idx];
            const wire_key = wireKey(row.label) orelse return .consumed;

            _ = self.frame_arena.reset(.retain_capacity);
            const a = self.frame_arena.allocator();

            const payload = (row.value.value(a) catch return .consumed) orelse return .consumed;

            var obj: std.json.ObjectMap = .empty;
            obj.put(a, wire_key, payload) catch return .consumed;
            mq.post(.{ .data_changed = .{
                .id = self.vdevice.id,
                .collection = .devices,
                .data = .{ .object = obj },
            } });
        }
        return result;
    }

    // --- Row builders: bind a component to a format fn (pull from the model) ---

    fn bindDisplay(self: *ThermostatView, label: []const u8, r: Read) !void {
        const a = self.arena.allocator();
        const d = try a.create(TextDisplay);
        d.* = TextDisplay.init("", .{});
        d.binding = .{ .ctx = self.vdevice, .read = r, .write = null };
        try self.list.addRow(label, &d.interface);
    }

    fn createTextInputRow(self: *ThermostatView, label: []const u8, r: Read, w: Write) !void {
        const a = self.arena.allocator();
        const input = try a.create(TextInput);
        input.* = TextInput.init();
        input.source = .{ .ctx = self.device, .read = r, .write = null };
        input.vsource = .{ .ctx = self.vdevice, .read = r, .write = w };
        try self.list.addRow(label, &input.interface);
    }

    fn createToggleRow(self: *ThermostatView, label: []const u8, vsource: *?bool, source: *const ?bool) !void {
        const a = self.arena.allocator();
        const i = try a.create(Toggle);
        i.* = Toggle.init(vsource, source, .{
            .color = Color.green,
            .secondary_color = Color.red,
            .tertiary_color = Color.yellow,
        }, "✔", "✗");
        try self.list.addRow(label, &i.interface);
    }

    const SetpointRef = struct {
        pub const Which = enum { heat, cool, auto };
        pub const Prop = enum { value, min, max };
        t: *const Thermostat,
        which: Which,
        prop: Prop,
    };

    fn bindSetpoint(self: *ThermostatView, label: []const u8, which: SetpointRef.Which, prop: SetpointRef.Prop) !void {
        const a = self.arena.allocator();
        const ref = try a.create(SetpointRef);
        ref.* = .{ .t = self.vdevice, .which = which, .prop = prop };
        const i = try a.create(TextInput);
        i.* = TextInput.init();
        i.vsource = .{ .ctx = ref, .read = formatSetpoint, .write = null };
        try self.list.addRow(label, &i.interface);
    }

    // --- Format bindings: cast the opaque ctx back, write the current value ---

    fn t(ctx: *const anyopaque) *const Thermostat {
        return @ptrCast(@alignCast(ctx));
    }

    fn formatName(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.writeAll(t(ctx).name);
    }
    fn formatModel(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.writeAll(t(ctx).model_number);
    }
    fn formatSerial(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.writeAll(t(ctx).serial_number);
    }
    fn formatFirmware(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.writeAll(t(ctx).firmware_version);
    }
    fn formatWatts(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.print("{d}", .{t(ctx).watts});
    }
    fn formatTemp(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.print("{d}", .{t(ctx).current_temperature});
    }
    fn formatScale(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.writeAll(@tagName(t(ctx).temperature_scale));
    }
    fn readMode(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.writeAll(@tagName(t(ctx).hvac_mode));
    }
    fn writeMode(ctx: *anyopaque, text: []const u8) !void {
        const thermostat: *Thermostat = @ptrCast(@alignCast(ctx));
        if (std.meta.stringToEnum(Thermostat.HvacMode, text)) |mode| {
            thermostat.hvac_mode = mode;
        }
    }
    fn readFan(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.writeAll(@tagName(t(ctx).fan_mode));
    }
    fn writeFan(ctx: *anyopaque, text: []const u8) !void {
        const thermostat: *Thermostat = @ptrCast(@alignCast(ctx));
        if (std.meta.stringToEnum(Thermostat.FanMode, text)) |mode| {
            thermostat.fan_mode = mode;
        }
    }
    fn formatHvacState(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.writeAll(if (t(ctx).hvac_state) |s| @tagName(s) else "-");
    }
    fn formatFanState(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.writeAll(if (t(ctx).fan_state) |s| @tagName(s) else "-");
    }
    fn formatOnline(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.writeAll(if (t(ctx).offline) Color.red ++ "✗" ++ Color.reset else Color.green ++ "✔︎" ++ Color.reset);
    }
    fn formatHumidity(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.print("{d:.1}", .{t(ctx).current_humidity.?});
    }
    fn formatHumidityScale(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.writeAll(@tagName(t(ctx).humidity_scale.?));
    }
    fn formatDelta(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.print("{d}", .{t(ctx).min_auto_delta.?});
    }
    fn formatCycleRate(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.print("{d}", .{t(ctx).cycle_rate.?});
    }
    fn formatSetpoint(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        const r: *const SetpointRef = @ptrCast(@alignCast(ctx));
        const maybe_sp = switch (r.which) {
            .heat => r.t.setpoints.heat,
            .cool => r.t.setpoints.cool,
            .auto => r.t.setpoints.auto,
        };
        const sp = maybe_sp orelse {
            try w.writeAll("-");
            return;
        };
        const v = switch (r.prop) {
            .value => sp.value,
            .min => sp.min,
            .max => sp.max,
        };
        try w.print("{d:.1}", .{v});
    }

    // Wire translation: UI label -> command key. The committed value comes
    // from the component itself (commit), correctly typed.

    fn wireKey(label: []const u8) ?[]const u8 {
        if (std.mem.eql(u8, label, "mode")) return "hvacMode";
        if (std.mem.eql(u8, label, "fan")) return "fanMode";
        if (std.mem.eql(u8, label, "ui enabled")) return "uiEnabled";
        return null;
    }
};
