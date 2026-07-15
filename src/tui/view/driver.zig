const std = @import("std");
const Color = @import("../color.zig");
const utils = @import("../utils.zig");
const AppConfig = @import("../../config.zig").Config;
const State = @import("../state.zig").State;
const Panel = @import("component/panel.zig").Panel;
const Cell = @import("component/table.zig").Cell;
const Table = @import("component/table.zig").Table;
const Component = @import("Component.zig");
const Cursor = @import("../canvas.zig").Cursor;
const Frame = Component.Frame;
const KeyResult = @import("../input.zig").KeyResult;
const Mouse = @import("../input.zig").Mouse;
const MessageQueue = @import("../message_queue.zig").MessageQueue;
const ThermostatView = @import("devices/thermostat.zig").ThermostatView;
const LockView = @import("devices/lock.zig").LockView;
const SwitchView = @import("devices/switch.zig").SwitchView;
const DetailView = @import("detail.zig").DetailView;
const Select = @import("component/select.zig").Select;
const Button = @import("component/button.zig").Button;
const TextDisplay = @import("component/text_display.zig").TextDisplay;
const Viewport = @import("component/viewport.zig").Viewport;
const Style = @import("_component.zig").Style;
const icons = @import("icons.zig");
const commands = @import("../../commands.zig");
const Writer = std.Io.Writer;


const Focus = enum { main, commands, request, response, command_select, send_button };

pub const DriverView = struct {
    alloc: std.mem.Allocator,
    state: *State,
    vstate: *State,
    panels: [4]Panel,
    table: Table,
    focused: ?Focus,
    host_label: []const u8,
    manufacturer: []const u8,
    depth: u8,
    device_idx: ?usize,
    list_selected: ?usize,
    detail: DetailView,
    command_select: Select(commands.Command),
    url: TextDisplay([]const u8),
    send_button: Button,
    frame: Frame,
    req_text: []const u8,
    req_display: Viewport,
    res_text: []const u8,
    res_display: Viewport,
    // Backing store for the depth-1 breadcrumb title. Must outlive write() so
    // handleMouse can read top_left; a write()-local buffer would dangle.
    title_buf: [128]u8 = undefined,

    pub const Config = struct {
        alloc: std.mem.Allocator,
        state: *State,
        vstate: *State,
        appCfg: *const AppConfig,
        command: *commands.Command,
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
            .vstate = cfg.vstate,
            .host_label = host_label,
            .manufacturer = manufacturer,
            .depth = 0,
            .device_idx = null,
            .list_selected = null,
            .detail = .none,
            .command_select = Select(commands.Command).init(cfg.command, cfg.command, commands.all, .{
                .color = Color.flamingo,
                .secondary_color = Color.dim ++ Color.flamingo,
                .tertiary_color = Color.flamingo,
                .bg_color = Color.bg_lavender_dark,
                .secondary_bg_color = Color.bg_surface0,
                .padding_left = 0,
                .padding_right = 1,
            }),
            // source wired in write() once the view is at its final address
            .url = .{ .source = undefined, .style = .{
                .color = Color.flamingo,
                .bg_color = Color.bg_mantle,
                .padding_left = 1,
            } },
            .send_button = Button.init(
                icons.send ++ " Send",
                .{
                    .color = Color.mantle,
                    .bg_color = Color.bg_lavender,
                },
            ),
            .frame = cfg.frame,
            .panels = panels,
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
            .req_text = try cfg.alloc.dupe(u8, ""),
            .req_display = Viewport.init("", .{
                .color = Color.subtext0,
                .padding_left = 1,
            }),
            .res_text = try cfg.alloc.dupe(u8, ""),
            .res_display = Viewport.init("", .{
                .color = Color.subtext0,
                .padding_left = 1,
            }),
        };
    }

    pub fn deinit(self: *DriverView) void {
        if (self.depth == 1) self.detail.deinit();
        self.table.deinit();
        self.alloc.free(self.host_label);
        self.alloc.free(self.req_text);
        self.alloc.free(self.res_text);
    }

    pub fn write(self: *DriverView, writer: *Writer, cursor: *Cursor) !void {
        self.url.source = &self.host_label;
        if (self.depth == 0) {
            // Get manufacturer
            const manufacturer = if (self.state.system) |sys| sys.manufacturer else "Unknown";
            self.panels[0].top_left = manufacturer;

            // Build table rows from state
            self.table.clearRows();
            for (self.state.devices.items) |device| {
                const off = device.offline();
                const online_glyph = if (off) |o| (if (o) "✗" else "✔") else "-";
                const online_style = if (off) |o| (if (o) Color.red else Color.green) else Color.subtext0;
                try self.table.addRow(&.{
                    .{ .value = .{ .string = (if (device.discriminator().len > 0) icons.device_icon.get(device.discriminator()) else null) orelse icons.device_icon.get(device.deviceType()) orelse device.deviceType() } },
                    .{ .value = .{ .string = device.id() } },
                    .{ .value = .{ .string = device.name() } },
                    .{ .value = .{ .string = if (device.modelNumber()) |m| (if (m.len > 0) m else "-") else "-" } },
                    .{ .value = .{ .string = if (device.serialNumber()) |s| (if (s.len > 0) s else "-") else "-" } },
                    .{ .value = .{ .string = if (device.firmwareVersion()) |fw| (if (fw.len > 0) fw else "-") else "-" } },
                    .{ .value = .{ .int = device.watts() } },
                    .{ .value = .{ .string = online_glyph }, .style = online_style },
                });
            }
            self.panels[0].setChildren(&.{self.table.component()});

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
            const manufacturer = if (self.state.system) |sys| sys.manufacturer else "Unknown";

            self.panels[0].setChildren(&.{self.detail.component()});

            // Panel label: manufacturer/device-id
            if (self.device_idx) |idx| {
                if (idx < self.state.devices.items.len) {
                    const dev = self.state.devices.items[idx];
                    const title = std.fmt.bufPrint(&self.title_buf, "{s} " ++ icons.angle_right ++ " {s}", .{ manufacturer, dev.id() }) catch manufacturer;
                    self.panels[0].top_left = title;
                }
            }
            self.panels[0].bottom_right = "";
        }

        // Request
        self.req_display.source = self.req_text;
        self.panels[2].setChildren(&.{self.req_display.component()});

        // Response
        self.res_display.source = self.res_text;
        self.panels[3].setChildren(&.{self.res_display.component()});

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

        try self.panels[0].component().write(writer, cursor, .{ .x = f.x, .y = f.y, .w = f.w, .h = half }, self.focused == .main);
        // Panel 1: left 20%, bottom
        try self.panels[1].component().write(writer, cursor, .{ .x = f.x, .y = bottom_y, .w = left_w, .h = bottom_h }, self.focused == .commands);
        // Panel 2: right 80%, top-right
        try self.panels[2].component().write(writer, cursor, .{ .x = right_x, .y = bottom_y, .w = right_w, .h = right_half }, self.focused == .request);
        // Panel 3: right 80%, bottom-right
        try self.panels[3].component().write(writer, cursor, .{ .x = right_x, .y = bottom_y + right_half, .w = right_w, .h = bottom_h - right_half }, self.focused == .response);
        // Command row - draw bg_mantle across, then select/button draw on top
        try utils.moveTo(writer, f.x + 1, select_y);
        try writer.writeAll(Color.bg_mantle);
        for (0..f.w -| 2) |_| try writer.writeAll(" ");
        try writer.writeAll(Color.reset);
        // Command row components
        const url_x = f.x + 22;
        const btn_x = f.x + f.w - 9;

        // Command select — stop where the url begins
        try self.command_select.component().write(writer, cursor, .{
            .x = f.x + 1,
            .y = select_y,
            .w = url_x - (f.x + 1),
            .h = 1,
        }, self.focused == .command_select);

        // Url — span from its start up to the button
        try self.url.component().write(writer, cursor, .{
            .x = url_x,
            .y = select_y,
            .w = btn_x -| url_x,
            .h = 1,
        }, false);

        // Send button, right-justified
        try self.send_button.component().write(writer, cursor, .{
            .x = btn_x,
            .y = select_y,
            .w = 10,
            .h = 1,
        }, self.focused == .send_button);
    }

    // Children: 0=main(table or kv_list), 1=details
    pub fn handleKey(self: *DriverView, key: u8, mq: *MessageQueue) KeyResult {
        if (self.focused == .main) {
            const result = if (self.depth == 0)
                self.table.handleKeyDirect(key, mq)
            else
                self.detail.component().handleKey(key, mq);
            switch (result) {
                .dive_in => return self.diveIn(mq),
                .ignored => {
                    if (self.depth == 1 and (key == 'h' or key == 0x1b)) {
                        self.detail.deinit();
                        self.detail = .none;
                        self.depth = 0;
                        self.table.selected = self.list_selected;
                        self.device_idx = null;
                        mq.post(.render);
                        return .consumed;
                    }
                    return .ignored;
                },
                .focus_next => {
                    self.setFocus(.command_select);
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
            if (f == .command_select) {
                const select_result = self.command_select.component().handleKey(key, mq);
                if (select_result == .consumed or select_result == .changed) {
                    return .consumed;
                }
            }
            if (f == .send_button) {
                const button_result = self.send_button.component().handleKey(key, mq);
                if (button_result == .consumed) return .consumed;
            }
            if (f == .request or f == .response) {
                const display = if (f == .request) &self.req_display else &self.res_display;
                const r = display.component().handleKey(key, mq);
                switch (r) {
                    .consumed => return .consumed,
                    .focus_next, .focus_prev => {}, // fall through to spatial nav
                    else => {},
                }
            }
            // Spatial navigation
            //   Panel 0 (top)
            //   Select (4) | Button (5) (command row)
            //   Panel 1 (bottom-left) | Panel 2 (top-right)
            //                         | Panel 3 (bottom-right)
            const target: ?Focus = switch (f) {
                .command_select => switch (key) {
                    'k' => .main,
                    'l' => .send_button,
                    'j' => .commands,
                    else => null,
                },
                .send_button => switch (key) {
                    'k' => .main,
                    'h' => .command_select,
                    'j' => .request,
                    else => null,
                },
                .commands => switch (key) {
                    'k' => .command_select,
                    'l' => .request,
                    else => null,
                },
                .request => switch (key) {
                    'k' => .send_button,
                    'h' => .commands,
                    'j' => .response,
                    else => null,
                },
                .response => switch (key) {
                    'k' => .request,
                    'h' => .commands,
                    else => null,
                },
                else => null,
            };
            if (target) |t| {
                if (t == .main and self.depth == 1) {
                    if (self.detail.list()) |l| {
                        const len = l.rows.items.len;
                        if (len > 0) l.cursor = len - 1;
                    }
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

    pub fn handleMouse(self: *DriverView, m: Mouse, mq: *MessageQueue) KeyResult {
        // Find component
        const target: ?Component = blk: {
            if (self.command_select.frame.contains(m.x, m.y)) {
                self.setFocus(.command_select);
                break :blk self.command_select.component();
            }
            if (self.url.frame.contains(m.x, m.y))
                break :blk self.url.component();
            if (self.send_button.frame.contains(m.x, m.y))
                break :blk self.send_button.component();
            for (&self.panels, 0..) |*p, i| {
                if (p.frame.contains(m.x, m.y)) {
                    self.setFocus(switch (i) {
                        0 => .main,
                        1 => .commands,
                        2 => .request,
                        3 => .response,
                        else => unreachable,
                    });
                    break :blk p.component();
                }
            }
            break :blk null;
        };

        const result = if (target) |t| t.handleMouse(m, mq) else .ignored;

        // Dive in
        if (result == .dive_in) return self.diveIn(mq);

        // Dive out
        if (result == .dive_out) return self.diveOut();

        return result;

        // Scrolling
        // if (m.btn == .wheel_down or m.btn == .wheel_up) {
        //     const delta: i16 = if (m.btn == .wheel_up) -1 else 1;
        //     var scrolled = false;
        //     if (self.depth == 0 and self.panels[0].frame.contains(m.x, m.y))
        //         scrolled = self.table.scrollBy(delta)
        //     else if (self.panels[2].frame.contains(m.x, m.y))
        //         scrolled = self.req_display.scrollBy(delta)
        //     else if (self.panels[3].frame.contains(m.x, m.y))
        //         scrolled = self.res_display.scrollBy(delta);
        //     if (scrolled) mq.post(.render);
        //     return if (scrolled) .consumed else .ignored;
        // }
        // if (!m.press or m.btn != .left) return .ignored;

        // Open dropdown: options are an overlay below the header frame.
        // if (self.command_select.open) {
        //     const f = self.command_select.frame;
        //     const first = f.y + 1;
        //     const last = first + @as(u16, @intCast(self.command_select.options.len));
        //     if (m.x >= f.x and m.x < f.x + f.w and m.y >= first and m.y < last) {
        //         self.command_select.selected = m.y - first;
        //         const committed = self.command_select.selected != self.command_select.previous;
        //         _ = self.command_select.component().handleKey('\r', mq); // confirm and close
        //         if (committed)
        //             mq.post(.{ .command_changed = self.command_select.options[self.command_select.selected] });
        //         mq.post(.render);
        //         return .consumed;
        //     }
        // }

        // Find the clicked component
        // const target: ?Focus = blk: {
        //     if (self.send_button.frame.contains(m.x, m.y)) break :blk .send_button;
        //     if (self.command_select.frame.contains(m.x, m.y)) break :blk .command_select;
        //     if (self.panels[0].frame.contains(m.x, m.y)) break :blk .main;
        //     if (self.panels[1].frame.contains(m.x, m.y)) break :blk .commands;
        //     if (self.panels[2].frame.contains(m.x, m.y)) break :blk .request;
        //     if (self.panels[3].frame.contains(m.x, m.y)) break :blk .response;
        //     break :blk null;
        // };

        // Return if no component found
        // const t = target orelse return .ignored;

        // Set focus on clicked component
        // self.setFocus(t);

        // switch (t) {
        //     .main => if (self.depth == 0)
        //         self.table.selectAt(m.y)
        //     else
        //         self.thermostat_view.list.cursorAt(m.y),
        //     // .send_button => mq.post(.send_command),
        //     .send_button => {
        //         self.send_button.component();
        //     },
        //     .command_select => _ = self.command_select.component().handleKey('\r', mq),
        //     else => {},
        // }

        // mq.post(.render);
        // return .consumed;
    }

    pub fn focus(self: *DriverView) void {
        self.setFocus(.main);
        if (self.table.selected == null) self.table.selected = 0;
    }

    pub fn blur(self: *DriverView) void {
        self.setFocus(null);
    }

    fn setFocus(self: *DriverView, f: ?Focus) void {
        self.focused = f;
        // Focus cascades down at render time via write(); here we only seed
        // the thermostat list cursor when diving into the main panel.
        if (self.depth == 1) {
            if (self.detail.list()) |l| {
                if (f == .main) {
                    if (l.cursor == null) l.cursor = 0;
                } else {
                    l.cursor = null;
                }
            }
        }
    }

    pub fn setRequest(self: *DriverView, text: []const u8) !void {
        const new_text = try self.alloc.dupe(u8, text);
        self.alloc.free(self.req_text);
        self.req_text = new_text;
    }

    pub fn setResponse(self: *DriverView, text: []const u8) !void {
        const new_text = try self.alloc.dupe(u8, text);
        self.alloc.free(self.res_text);
        self.res_text = new_text;
    }

    pub fn setFilter(self: *DriverView, filter: []const u8) void {
        self.table.setFilter(filter);
    }

    pub fn getFilter(self: *const DriverView) []const u8 {
        return self.table.getFilter();
    }

    fn diveIn(self: *DriverView, mq: *MessageQueue) KeyResult {
        if (self.depth != 0) return .consumed;
        const row = self.table.selectedRow() orelse return .consumed;
        if (row.len < 2) return .consumed;
        const id = switch (row[1].value) {
            .string => |s| s,
            else => return .consumed,
        };

        for (self.state.devices.items, 0..) |*device, i| {
            if (!std.mem.eql(u8, device.id(), id)) continue;
            self.list_selected = self.table.selected;
            self.device_idx = i;
            const sdevice = &self.state.devices.items[i];
            const vdevice = &self.vstate.devices.items[i];
            switch (vdevice.*) {
                .thermostat => |*vd| switch (sdevice.*) {
                    .thermostat => |*sd| {
                        self.detail = .{ .thermostat = ThermostatView.init(self.alloc, vd, sd) catch return .consumed };
                    },
                    else => return .consumed,
                },
                .lock => |*vd| switch (sdevice.*) {
                    .lock => |*sd| {
                        self.detail = .{ .lock = LockView.init(self.alloc, vd, sd) catch return .consumed };
                    },
                    else => return .consumed,
                },
                .@"switch" => |*vd| switch (sdevice.*) {
                    .@"switch" => |*sd| {
                        self.detail = .{ .@"switch" = SwitchView.init(self.alloc, vd, sd) catch return .consumed };
                    },
                    else => return .consumed,
                },
            }
        }
        self.depth = 1;
        mq.post(.render);
        return .consumed;
    }

    fn diveOut(self: *DriverView) KeyResult {
        if (self.depth != 1) return .ignored;
        self.detail.deinit();
        self.detail = .none;
        self.depth = 0;
        self.table.selected = self.list_selected;
        self.device_idx = null;
        self.setFocus(.main);
        return .consumed;
    }
};
