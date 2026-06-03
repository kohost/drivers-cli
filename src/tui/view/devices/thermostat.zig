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
const Boolean = @import("../component/boolean.zig").Boolean;
const KeyValList = @import("../component/key_val_list.zig").KeyValList;

const Render = *const fn (*const anyopaque, *std.Io.Writer) anyerror!void;

pub const ThermostatView = struct {
    interface: ComponentInterface,
    arena: ArenaAllocator,
    frame_arena: ArenaAllocator, // scratch for wire fragments on commit
    thermostat: *const Thermostat,
    list: KeyValList,

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

        try self.bindDisplay("name", renderName);
        try self.bindDisplay("model", renderModel);
        try self.bindDisplay("serial", renderSerial);
        try self.bindDisplay("firmware", renderFirmware);
        try self.bindDisplay("watts", renderWatts);
        try self.bindDisplay("online", renderOnline);
        try self.bindDisplay("scale", renderScale);
        try self.bindDisplay("temp", renderTemp);
        try self.bindInput("mode", renderMode);
        try self.bindDisplay("state", renderHvacState);
        try self.bindInput("fan", renderFan);
        try self.bindDisplay("fan state", renderFanState);

        if (thermostat.current_humidity != null) try self.bindDisplay("humidity", renderHumidity);
        if (thermostat.humidity_scale != null) try self.bindDisplay("humidity scale", renderHumidityScale);
        if (thermostat.min_auto_delta != null) try self.bindDisplay("delta", renderDelta);
        if (thermostat.cycle_rate != null) try self.bindDisplay("cycle rate", renderCycleRate);
        if (thermostat.ui_enabled != null) try self.bindBoolean("ui enabled", renderUiEnabled);

        if (thermostat.setpoints.heat != null) {
            try self.bindSetpoint("heat", .heat, .value);
            try self.bindSetpoint("heat min", .heat, .min);
            try self.bindSetpoint("heat max", .heat, .max);
        }
        if (thermostat.setpoints.cool != null) {
            try self.bindSetpoint("cool", .cool, .value);
            try self.bindSetpoint("cool min", .cool, .min);
            try self.bindSetpoint("cool max", .cool, .max);
        }
        if (thermostat.setpoints.auto != null) {
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
        // Components pull their own values from the model and render themselves.
        try self.list.interface.write(writer, cursor, frame);
    }

    fn handleKey(iface: *ComponentInterface, key: u8, mq: *MessageQueue) KeyResult {
        const self: *ThermostatView = @fieldParentPtr("interface", iface);
        const result = self.list.interface.handleKey(key, mq);
        if (result == .committed) {
            const idx = self.list.focused orelse return .consumed;
            const row = self.list.rows.items[idx];
            const ti: *TextInput = @fieldParentPtr("interface", row.value);
            _ = self.frame_arena.reset(.retain_capacity);
            const a = self.frame_arena.allocator();
            const frag = (buildWire(a, row.label, ti.buf[0..ti.buf_len]) catch return .consumed) orelse return .consumed;
            mq.post(.{ .data_changed = .{
                .id = self.thermostat.id,
                .collection = .devices,
                .data = frag,
            } });
        }
        return result;
    }

    // --- Row builders: bind a component to a render fn (pull from the model) ---

    fn bindDisplay(self: *ThermostatView, label: []const u8, render: Render) !void {
        const a = self.arena.allocator();
        const d = try a.create(TextDisplay);
        d.* = TextDisplay.init("", .{});
        d.binding = .{ .ctx = self.thermostat, .render = render };
        try self.list.addRow(label, &d.interface);
    }

    fn bindInput(self: *ThermostatView, label: []const u8, render: Render) !void {
        const a = self.arena.allocator();
        const i = try a.create(TextInput);
        i.* = TextInput.init("");
        i.binding = .{ .ctx = self.thermostat, .render = render };
        try self.list.addRow(label, &i.interface);
    }

    fn bindBoolean(self: *ThermostatView, label: []const u8, render: Render) !void {
        const a = self.arena.allocator();
        const i = try a.create(Boolean);
        i.* = Boolean.init(false);
        i.binding = .{ .ctx = self.thermostat, .render = render };
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
        ref.* = .{ .t = self.thermostat, .which = which, .prop = prop };
        const i = try a.create(TextInput);
        i.* = TextInput.init("");
        i.binding = .{ .ctx = ref, .render = renderSetpoint };
        try self.list.addRow(label, &i.interface);
    }

    // --- Render bindings: cast the opaque ctx back, write the current value ---

    fn t(ctx: *const anyopaque) *const Thermostat {
        return @ptrCast(@alignCast(ctx));
    }

    fn renderName(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.writeAll(t(ctx).name);
    }
    fn renderModel(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.writeAll(t(ctx).model_number);
    }
    fn renderSerial(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.writeAll(t(ctx).serial_number);
    }
    fn renderFirmware(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.writeAll(t(ctx).firmware_version);
    }
    fn renderWatts(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.print("{d}", .{t(ctx).watts});
    }
    fn renderTemp(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.print("{d}", .{t(ctx).current_temperature});
    }
    fn renderScale(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.writeAll(@tagName(t(ctx).temperature_scale));
    }
    fn renderMode(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.writeAll(@tagName(t(ctx).hvac_mode));
    }
    fn renderFan(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.writeAll(@tagName(t(ctx).fan_mode));
    }
    fn renderHvacState(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.writeAll(if (t(ctx).hvac_state) |s| @tagName(s) else "-");
    }
    fn renderFanState(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.writeAll(if (t(ctx).fan_state) |s| @tagName(s) else "-");
    }
    fn renderOnline(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.writeAll(if (t(ctx).offline) Color.red ++ "✗" ++ Color.reset else Color.green ++ "✔︎" ++ Color.reset);
    }
    fn renderHumidity(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.print("{d:.1}", .{t(ctx).current_humidity.?});
    }
    fn renderHumidityScale(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.writeAll(@tagName(t(ctx).humidity_scale.?));
    }
    fn renderDelta(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.print("{d}", .{t(ctx).min_auto_delta.?});
    }
    fn renderCycleRate(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.print("{d}", .{t(ctx).cycle_rate.?});
    }
    fn renderUiEnabled(ctx: *const anyopaque, w: *std.Io.Writer) !void {
        try w.writeAll(if (t(ctx).ui_enabled.?) Color.green ++ "✔︎" ++ Color.reset else Color.red ++ "✗" ++ Color.reset);
    }
    fn renderSetpoint(ctx: *const anyopaque, w: *std.Io.Writer) !void {
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

    // Wire translation: UI label -> command fragment (setpoints: next)

    fn buildWire(alloc: Allocator, label: []const u8, text: []const u8) !?std.json.Value {
        if (std.mem.eql(u8, label, "mode")) return try flat(alloc, "hvacMode", text);
        if (std.mem.eql(u8, label, "fan")) return try flat(alloc, "fanMode", text);
        return null;
    }

    fn flat(alloc: Allocator, key: []const u8, value: []const u8) !std.json.Value {
        var o: std.json.ObjectMap = .empty;
        try o.put(alloc, key, .{ .string = value });
        return .{ .object = o };
    }
};
