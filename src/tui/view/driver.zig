const std = @import("std");
const Color = @import("../color.zig");
const utils = @import("../utils.zig");
const AppConfig = @import("../../config.zig").Config;
const State = @import("../state.zig").State;
const Panel = @import("component/panel.zig").Panel;
const Cell = @import("component/table.zig").Cell;
const Table = @import("component/table.zig").Table;
const Cursor = @import("component.zig").Cursor;
const Frame = @import("component.zig").Frame;
const KeyResult = @import("component.zig").KeyResult;
const MessageQueue = @import("../message_queue.zig").MessageQueue;
const ThermostatView = @import("devices/thermostat.zig").ThermostatView;
const Select = @import("component/select.zig").Select;
const Button = @import("component/button.zig").Button;
const TextDisplay = @import("component/text_display.zig").TextDisplay;
const Style = @import("component.zig").Style;
const icons = @import("../icons.zig");
const commands = @import("../../commands.zig");
const Writer = std.Io.Writer;

const command_names = blk: {
    var names: [commands.list.len][]const u8 = undefined;
    for (commands.list, 0..) |cmd, i| {
        names[i] = cmd.name;
    }
    break :blk names;
};

pub const DriverView = struct {
    alloc: std.mem.Allocator,
    state: *State,
    panels: [4]Panel,
    panel_count: u8,
    table: Table,
    focused: ?usize,
    host_label: []const u8,
    manufacturer: []const u8,
    depth: u8,
    device_idx: ?usize,
    list_selected: ?usize,
    thermostat_view: ThermostatView,
    command_select: Select,
    url: TextDisplay,
    send_button: Button,
    frame: Frame,

    pub const Config = struct {
        alloc: std.mem.Allocator,
        state: *State,
        appCfg: AppConfig,
        frame: Frame,
    };

    pub fn init(cfg: Config) !DriverView {
        const app = cfg.appCfg;
        const manufacturer = if (cfg.state.system) |sys| sys.manufacturer else "Unknown";
        const host_label = try std.fmt.allocPrint(cfg.alloc, "tcp://{s}:{d}", .{
            app.host,
            app.port,
        });
        var panels: [4]Panel = undefined;
        panels[0] = Panel.init(.{
            .top_left = manufacturer,
            .top_right = host_label,
        });
        panels[1] = Panel.init(.{ .top_right = "Commands" });
        panels[2] = Panel.init(.{ .top_left = "Request" });
        panels[3] = Panel.init(.{ .top_left = "Response" });
        return .{
            .alloc = cfg.alloc,
            .state = cfg.state,
            .host_label = host_label,
            .manufacturer = manufacturer,
            .depth = 0,
            .device_idx = null,
            .list_selected = null,
            .thermostat_view = undefined,
            .command_select = Select.init("UpdateCredentials", &command_names, .{
                .color = Color.flamingo,
                .secondary_color = Color.dim ++ Color.flamingo,
                .tertiary_color = Color.flamingo,
                .bg_color = Color.bg_lavender_dark,
                .secondary_bg_color = Color.bg_surface0,
                .padding_left = 1,
                .padding_right = 1,
            }),
            .url = TextDisplay.init(host_label, .{
                // .color = Color.subtext0,
                .color = Color.flamingo,
                .bg_color = Color.bg_mantle,
                .padding_left = 1,
            }),
            .send_button = Button.init(
                icons.send ++ " Send",
                .{
                    .color = Color.mantle,
                    .bg_color = Color.bg_lavender,
                },
            ),
            .frame = cfg.frame,
            .panels = panels,
            .panel_count = 4,
            .table = Table.init(cfg.alloc, &.{
                .{ .value = .{ .string = "type" }, .align_right = true },
                .{ .value = .{ .string = "id" } },
                .{ .value = .{ .string = "name" } },
                .{ .value = .{ .string = "model" } },
                .{ .value = .{ .string = "serial" } },
                .{ .value = .{ .string = "firmware" } },
                .{ .value = .{ .string = "watts" } },
                .{ .value = .{ .string = "online" } },
            }),
            .focused = null,
        };
    }

    pub fn deinit(self: *DriverView) void {
        if (self.depth == 1) self.thermostat_view.deinit();
        self.table.deinit();
        self.alloc.free(self.host_label);
    }

    pub fn write(self: *DriverView, writer: *Writer, cursor: *Cursor) !void {
        if (self.depth == 0) {
            // Build table rows from state
            self.table.clearRows();
            for (self.state.devices.items) |device| {
                try self.table.addRow(&.{
                    .{ .value = .{ .string = utils.device_icon.get(device.deviceType()) orelse device.deviceType() } },
                    .{ .value = .{ .string = device.id() } },
                    .{ .value = .{ .string = device.name() } },
                    .{ .value = .{ .string = if (device.modelNumber().len > 0) device.modelNumber() else "-" } },
                    .{ .value = .{ .string = device.serialNumber() } },
                    .{ .value = .{ .string = device.firmwareVersion() } },
                    .{ .value = .{ .int = device.watts() } },
                    .{ .value = .{ .string = if (device.offline()) "✗" else "✔" }, .style = if (device.offline()) Color.red else Color.green },
                });
            }
            self.panels[0].setChildren(&.{&self.table.interface});
            self.panels[0].top_left = self.manufacturer;

            // Search label
            const filter = self.table.getFilter();
            var label_buf: [72]u8 = undefined;
            const icon = icons.search;
            if (filter.len > 0) {
                const label = std.fmt.bufPrint(&label_buf, "{s} {s}", .{ icon, filter }) catch icon;
                self.panels[0].bottom_right = label;
            } else {
                self.panels[0].bottom_right = icon;
            }
        } else if (self.depth == 1) {
            self.panels[0].setChildren(&.{&self.thermostat_view.interface});

            // Panel label: manufacturer/device-id
            var title_buf: [128]u8 = undefined;
            if (self.device_idx) |idx| {
                if (idx < self.state.devices.items.len) {
                    const dev = self.state.devices.items[idx];
                    const title = std.fmt.bufPrint(&title_buf, "{s} " ++ icons.angle_right ++ " {s}", .{ self.manufacturer, dev.id() }) catch self.manufacturer;
                    self.panels[0].top_left = title;
                }
            }
            self.panels[0].bottom_right = "";
        }

        // Draw panels
        // Panel 0: full width, top 50%
        const f = self.frame;
        const half = f.h / 2;
        const select_y = f.y + half + 1;
        const bottom_y = select_y + 1;
        const bottom_h = f.h - half - 2;
        const left_w = f.w / 5;
        const right_w = f.w - left_w;
        const right_x = f.x + left_w;
        const right_half = bottom_h / 2;

        try self.panels[0].interface.write(writer, cursor, .{ .x = f.x, .y = f.y, .w = f.w, .h = half });
        // Panel 1: left 20%, bottom
        try self.panels[1].interface.write(writer, cursor, .{ .x = f.x, .y = bottom_y, .w = left_w, .h = bottom_h });
        // Panel 2: right 80%, top-right
        try self.panels[2].interface.write(writer, cursor, .{ .x = right_x, .y = bottom_y, .w = right_w, .h = right_half });
        // Panel 3: right 80%, bottom-right
        try self.panels[3].interface.write(writer, cursor, .{ .x = right_x, .y = bottom_y + right_half, .w = right_w, .h = bottom_h - right_half });
        // Command row - draw bg_mantle across, then select/button draw on top
        try utils.moveTo(writer, f.x + 1, select_y);
        try writer.writeAll(Color.bg_mantle);
        for (0..f.w -| 2) |_| try writer.writeAll(" ");
        try writer.writeAll(Color.reset);
        // Command row components
        try self.command_select.interface.write(writer, cursor, .{ .x = f.x + 1, .y = select_y, .w = f.w, .h = 1 });

        // Url
        // try self.url.component().write(writer, )
        try self.url.interface.write(writer, cursor, .{
            .x = f.x + 22, //
            .y = select_y,
            .w = f.w,
            .h = f.h,
        });

        // Send button, right-justified
        const btn_x = f.x + f.w - 9;
        try self.send_button.interface.write(writer, cursor, .{
            .x = btn_x,
            .y = select_y,
            .w = 10,
            .h = 1,
        });
    }

    // Children: 0=main(table or kv_list), 1=details
    pub fn handleKey(self: *DriverView, key: u8, mq: *MessageQueue) KeyResult {
        if (self.focused == 0) {
            const result = if (self.depth == 0)
                self.table.handleKeyDirect(key, mq)
            else
                self.thermostat_view.interface.handleKey(key, mq);
            switch (result) {
                .dive_in => {
                    if (self.depth == 0) {
                        if (self.table.selectedRow()) |row| {
                            if (row.len < 2) return .consumed;
                            const id = switch (row[1].value) {
                                .string => |s| s,
                                else => return .consumed,
                            };
                            for (self.state.devices.items, 0..) |*device, idx| {
                                if (std.mem.eql(u8, device.id(), id)) {
                                    self.list_selected = self.table.selected;
                                    self.device_idx = idx;
                                    switch (device.*) {
                                        .thermostat => |*d| {
                                            self.thermostat_view = ThermostatView.init(self.alloc, d) catch return .consumed;
                                        },
                                        else => return .consumed,
                                    }
                                    self.depth = 1;
                                    mq.post(.render);
                                    return .consumed;
                                }
                            }
                        }
                    }
                    return .consumed;
                },
                .ignored => {
                    if (self.depth == 1 and (key == 'h' or key == 0x1b)) {
                        self.thermostat_view.deinit();
                        self.depth = 0;
                        self.table.selected = self.list_selected;
                        self.device_idx = null;
                        mq.post(.render);
                        return .consumed;
                    }
                    return .ignored;
                },
                .focus_next => {
                    self.setFocus(4);
                    mq.post(.render);
                    return .consumed;
                },
                .focus_prev => {
                    self.setFocus(null);
                    return .focus_prev;
                },
                else => return result,
            }
        } else if (self.focused) |f| {
            // Forward keys to Select when focused
            if (f == 4) {
                const select_result = self.command_select.interface.handleKey(key, mq);
                if (select_result == .consumed) return .consumed;
            }
            // Spatial navigation
            //   Panel 0 (top)
            //   Select (4) | Button (5) (command row)
            //   Panel 1 (bottom-left) | Panel 2 (top-right)
            //                         | Panel 3 (bottom-right)
            const target: ?usize = switch (f) {
                4 => switch (key) {
                    'k' => 0,
                    'l' => 5,
                    'j' => 1,
                    else => null,
                },
                5 => switch (key) {
                    'k' => 0,
                    'h' => 4,
                    'j' => 2,
                    else => null,
                },
                1 => switch (key) {
                    'k' => 4,
                    'l' => 2,
                    else => null,
                },
                2 => switch (key) {
                    'k' => 5,
                    'h' => 1,
                    'j' => 3,
                    else => null,
                },
                3 => switch (key) {
                    'k' => 2,
                    'h' => 1,
                    else => null,
                },
                else => null,
            };
            if (target) |t| {
                if (t == 0 and self.depth == 1) {
                    const len = self.thermostat_view.list.rows.items.len;
                    if (len > 0) self.thermostat_view.list.focused = len - 1;
                }
                self.setFocus(t);
                mq.post(.render);
                return .consumed;
            }
            switch (key) {
                ':' => {
                    mq.post(.{ .open_input = ':' });
                    return .consumed;
                },
                else => return .ignored,
            }
        }
        return .ignored;
    }

    pub fn focus(self: *DriverView) void {
        self.setFocus(0);
        if (self.table.selected == null) self.table.selected = 0;
    }

    pub fn blur(self: *DriverView) void {
        self.setFocus(null);
    }

    fn setFocus(self: *DriverView, idx: ?usize) void {
        self.focused = idx;
        // Update panel focus
        for (self.panels[0..self.panel_count], 0..) |*panel, i| {
            panel.focused = (idx != null and idx.? == i);
        }
        // Update child focus
        self.table.focused = (idx == 0 and self.depth == 0);
        self.command_select.focused = (idx == 4);
        self.send_button.focused = (idx == 5);
        if (self.depth == 1) {
            if (idx == 0) {
                if (self.thermostat_view.list.focused == null) self.thermostat_view.list.focused = 0;
            } else {
                self.thermostat_view.list.focused = null;
            }
        }
    }

    pub fn setFilter(self: *DriverView, filter: []const u8) void {
        self.table.setFilter(filter);
    }

    pub fn getFilter(self: *const DriverView) []const u8 {
        return self.table.getFilter();
    }
};
