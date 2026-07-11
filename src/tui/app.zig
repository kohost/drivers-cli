const std = @import("std");
const Config = @import("../config.zig").Config;
const State = @import("state.zig").State;
const Layout = @import("view/layout.zig").Layout;
const View = @import("view.zig").View;
const DriverView = @import("view/driver.zig").DriverView;
const MessageQueue = @import("./message_queue.zig").MessageQueue;
const KeyResult = @import("input.zig").KeyResult;
const Mouse = @import("input.zig").Mouse;
const Allocator = std.mem.Allocator;
const Transport = @import("transport.zig").Transport;
const commands = @import("../commands.zig");

const view_top: u16 = 5; // first row of the view region (below header/menu)

pub const App = struct {
    alloc: Allocator,
    cols: u16,
    rows: u16,
    cfg: *const Config,

    // Canonical data vs virtual data. We keep both so we can diff between them
    // to build our data for updateDevices command.
    state: *State,
    vstate: *State,

    layout: Layout,
    view: View,
    focused: ?usize,
    prev_focus: ?usize,
    input_prefix: u8,
    mq: MessageQueue,
    transport: Transport,
    command: []const u8 = "UpdateDevices",

    pub fn init(
        alloc: std.mem.Allocator,
        state: *State,
        cols: u16,
        rows: u16,
        cfg: *const Config,
        io: std.Io,
    ) !App {
        const x = 1;
        const y = view_top;
        const width = cols;
        const height = rows - 6;
        const vstate = try alloc.create(State);
        errdefer alloc.destroy(vstate);
        vstate.* = try state.clone(alloc);

        return .{
            .alloc = alloc,
            .state = state,
            .vstate = vstate,
            .cols = cols,
            .rows = rows,
            .cfg = cfg,
            .mq = MessageQueue.init(),
            .layout = Layout.init(cols, rows, undefined),
            .view = .{ .driver = try DriverView.init(.{
                .alloc = alloc,
                .state = state,
                .vstate = vstate,
                .appCfg = cfg,
                .frame = .{ .x = x, .y = y, .w = width, .h = height },
            }) },
            .focused = 0,
            .prev_focus = 0,
            .input_prefix = 0,
            .transport = Transport.init(alloc, cfg.*, io),
        };
    }

    pub fn deinit(self: *App) void {
        self.view.deinit();
        self.vstate.deinit(); // frees the devices/strings inside the State
        self.alloc.destroy(self.vstate); // frees the State slot itself
    }

    pub fn resize(self: *App, cols: u16, rows: u16) !void {
        const x = 1;
        const y = view_top;
        const height = rows - 6;

        self.cols = cols;
        self.rows = rows;
        self.layout.resize(cols, rows);
        self.view.deinit();
        self.view = .{
            .driver = try DriverView.init(.{
                .alloc = self.alloc,
                .state = self.state,
                .vstate = self.vstate,
                .appCfg = self.cfg,
                .frame = .{ .x = x, .y = y, .w = cols, .h = height },
            }),
        };
    }

    // Children: 0=menu, 1=view, 2=footer
    pub fn handleKey(self: *App, key: u8) bool {
        const result = switch (self.focused orelse 0) {
            0 => self.layout.menu.handleKey(key, &self.mq),
            1 => self.view.handleKey(key, &self.mq),
            2 => self.layout.footer.handleKey(key, &self.mq),
            else => KeyResult.ignored,
        };

        switch (result) {
            .focus_next => {
                if (self.focused == 0) {
                    self.layout.menu.focused = false;
                    self.focused = 1;
                    self.view.focus();
                    self.mq.post(.render);
                }
            },
            .focus_prev => {
                if (self.focused == 1) {
                    self.focused = 0;
                    self.layout.menu.focused = true;
                    self.view.blur();
                    self.mq.post(.render);
                }
            },
            .open_search => {
                self.prev_focus = self.focused;
                self.focused = 2;
                self.input_prefix = '/';
                self.layout.footer.open('/', self.view.getFilter());
                self.mq.post(.render);
            },
            else => {},
        }

        return self.drain();
    }

    pub fn handleMouse(self: *App, m: Mouse) bool {
        // Outer focus: a click picks which top-level region owns the keyboard.
        // The driver sets its own inner focus during dispatch below.
        if (m.press and !m.move) {
            self.focused = self.regionAt(m);
            self.layout.menu.focused = (self.focused == 0);
            if (self.focused != 1) self.view.blur();
        }
        _ = self.view.handleMouse(m, &self.mq);
        return self.drain();
    }

    // Which top-level region a click lands in: 0=menu, 1=view, 2=footer
    fn regionAt(self: *App, m: Mouse) usize {
        if (m.y >= self.layout.footer.y) return 2;
        if (m.y >= view_top) return 1;
        return 0;
    }

    fn drain(self: *App) bool {
        for (self.mq.drain()) |msg| {
            switch (msg) {
                .quit => return false,
                .open_input => |prefix| {
                    self.prev_focus = self.focused;
                    self.focused = 2;
                    self.input_prefix = prefix;
                    self.layout.footer.open(prefix, "");
                },
                .submit_input => {
                    self.focused = self.prev_focus;
                    if (!self.handleInput(self.input_prefix, self.layout.footer.input())) return false;
                },
                .cancel_input => {
                    self.focused = self.prev_focus;
                    if (self.input_prefix == '/') {
                        self.view.setFilter("");
                    }
                },
                .view_changed => |idx| {
                    self.swapView(idx);
                },
                .render => {
                    if (self.layout.footer.active and self.input_prefix == '/') {
                        self.view.setFilter(self.layout.footer.input());
                    }
                },
                // TODO: Silently swallowing errors with catch{} will want to surface.
                .send_command => self.executeCommand() catch {},
                .command_changed => |name| self.command = name,
                .update_pointer => |seq| self.layout.pointer = seq,
            }
        }

        return true;
    }

    fn handleInput(_: *App, prefix: u8, input: []const u8) bool {
        switch (prefix) {
            ':' => {
                if (std.mem.eql(u8, input, "q") or std.mem.eql(u8, input, "quit")) {
                    return false;
                }
            },
            else => {},
        }
        return true;
    }

    fn swapView(self: *App, idx: usize) void {
        self.view.deinit();
        switch (idx) {
            0 => {
                if (DriverView.init(.{
                    .alloc = self.alloc,
                    .state = self.state,
                    .vstate = self.vstate,
                    .appCfg = self.cfg,
                    .frame = .{ .x = 1, .y = 5, .w = self.cols, .h = self.rows - 6 },
                })) |dv| {
                    self.view = .{ .driver = dv };
                } else |_| {
                    self.view = .none;
                }
            },
            else => self.view = .none,
        }
    }

    fn buildData(self: *App, a: Allocator) std.json.ObjectMap {
        var data: std.json.ObjectMap = .empty;

        // Decide on data we need to send
        const command_info: ?commands.CommandInfo = commands.find(self.command);
        if (command_info) |info| {
            if (info.args) |args| {
                const prop = "devices";
                if (std.mem.startsWith(u8, args, prop)) {
                    const props = self.vstate.diff(self.state, a) catch return data;
                    data.put(a, prop, props) catch return data;
                }
            }
        }

        return data;
    }

    fn executeCommand(self: *App) !void {
        var arena = std.heap.ArenaAllocator.init(self.alloc);
        defer arena.deinit();
        const a = arena.allocator();

        var cmd: std.json.ObjectMap = .empty;
        try cmd.put(a, "command", .{ .string = self.command });
        const data: std.json.ObjectMap = self.buildData(a);
        try cmd.put(a, "data", .{ .object = data });

        const root: std.json.Value = .{ .object = cmd };

        var req_wa: std.Io.Writer.Allocating = std.Io.Writer.Allocating.init(self.alloc);
        defer req_wa.deinit();

        const formatter = std.json.fmt(root, .{ .whitespace = .indent_2 });
        try formatter.format(&req_wa.writer);

        try self.view.setRequest(req_wa.written());

        // Reformat to send down the wire
        req_wa.clearRetainingCapacity();
        try std.json.fmt(root, .{}).format(&req_wa.writer);

        if (self.transport.fetch(req_wa.written())) |parsed| {
            defer parsed.deinit();
            var res_wa: std.Io.Writer.Allocating = std.Io.Writer.Allocating.init(self.alloc);
            defer res_wa.deinit();

            const res_formatter = std.json.fmt(parsed.value, .{ .whitespace = .indent_2 });
            try res_formatter.format(&res_wa.writer);

            try self.view.setResponse(res_wa.written());
            _ = self.state.update(parsed.value);

            for (self.vstate.devices.items) |*vd| {
                if (self.state.getDevice(vd.id())) |sd| vd.revert(sd);
            }
        }
    }

    pub fn loadDevices(self: *App) !void {
        const getAll = "{\"command\":\"GetDevices\",\"data\":{}}";
        if (self.transport.fetch(getAll)) |parsed| {
            defer parsed.deinit();
            self.state.loadFromJson(parsed.value) catch {};
            try self.sync();
        }
    }

    pub fn sync(self: *App) !void {
        self.vstate.deinit();
        self.vstate.* = try self.state.clone(self.alloc);
    }
};

/// Deep-merge a JSON object `src` into `dst`. Nested objects merge recursively
/// (e.g. accumulating multiple setpoints); scalars overwrite. Strings are duped
/// so `dst` doesn't borrow the caller's transient fragment.
fn mergeInto(alloc: std.mem.Allocator, dst: *std.json.ObjectMap, src: std.json.Value) !void {
    if (src != .object) return;
    var it = src.object.iterator();
    while (it.next()) |kv| {
        const key = kv.key_ptr.*;
        const val = kv.value_ptr.*;
        switch (val) {
            .object => {
                const slot = try dst.getOrPutValue(alloc, key, .{ .object = .empty });
                if (slot.value_ptr.* != .object) slot.value_ptr.* = .{ .object = .empty };
                try mergeInto(alloc, &slot.value_ptr.object, val);
            },
            .string => |s| try dst.put(alloc, key, .{ .string = try alloc.dupe(u8, s) }),
            else => try dst.put(alloc, key, val),
        }
    }
}
