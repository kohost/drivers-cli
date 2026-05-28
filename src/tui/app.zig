const std = @import("std");
const Config = @import("../config.zig").Config;
const State = @import("state.zig").State;
const Layout = @import("view/layout.zig").Layout;
const View = @import("view.zig").View;
const DriverView = @import("view/driver.zig").DriverView;
const MessageQueue = @import("./message_queue.zig").MessageQueue;
const KeyResult = @import("view/component.zig").KeyResult;
const Allocator = std.mem.Allocator;
const Transport = @import("transport.zig").Transport;

pub const App = struct {
    alloc: Allocator,
    cols: u16,
    rows: u16,
    cfg: Config,
    state: *State,
    layout: Layout,
    view: View,
    focused: ?usize,
    prev_focus: ?usize,
    input_prefix: u8,
    mq: MessageQueue,
    // pending_command: []const u8,
    pending_command: std.json.ObjectMap = .empty,
    transport: Transport,

    pub fn init(
        alloc: std.mem.Allocator,
        state: *State,
        cols: u16,
        rows: u16,
        cfg: Config,
        io: std.Io,
    ) !App {
        const x = 1;
        const y = 5;
        const width = cols;
        const height = rows - 6;
        var pending_command: std.json.ObjectMap = .empty;
        try pending_command.put(alloc, "command", .{ .string = "UpdateDevices" });
        try pending_command.put(alloc, "data", .{ .object = .empty });

        return .{
            .alloc = alloc,
            .state = state,
            .cols = cols,
            .rows = rows,
            .cfg = cfg,
            .mq = MessageQueue.init(),
            .layout = Layout.init(cols, rows, undefined),
            .view = .{ .driver = try DriverView.init(.{
                .alloc = alloc,
                .state = state,
                .appCfg = cfg,
                .frame = .{ .x = x, .y = y, .w = width, .h = height },
            }) },
            .focused = 0,
            .prev_focus = 0,
            .input_prefix = 0,
            // .pending_command = "UpdateDevices",
            .pending_command = pending_command,
            .transport = Transport.init(alloc, cfg, io),
        };
    }

    pub fn deinit(self: *App) void {
        self.view.deinit();
        self.pending_command.deinit(self.alloc);
    }

    pub fn resize(self: *App, cols: u16, rows: u16) !void {
        const x = 1;
        const y = 5;
        const height = rows - 6;

        self.cols = cols;
        self.rows = rows;
        self.layout.resize(cols, rows);
        self.view.deinit();
        self.view = .{
            .driver = try DriverView.init(.{
                .alloc = self.alloc,
                .state = self.state,
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

        for (self.mq.drain()) |msg| {
            std.debug.print("App:handleKey:mq: {s}\n", .{@tagName(msg)});
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
                // TODO: Silently swallowing errors with catch{} will want to surface
                .send_command => self.executeCommand() catch {},
                .command_changed => |name| self.pending_command.put(self.alloc, "command", .{ .string = name }) catch {},
                .data_changed => |data| {
                    self.pending_command
                        .getPtr("data").?.object
                        .put(self.alloc, data.key, data.value) catch {};
                },
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

    fn executeCommand(self: *App) !void {
        var req_wa: std.Io.Writer.Allocating = std.Io.Writer.Allocating.init(self.alloc);
        defer req_wa.deinit();

        const root: std.json.Value = .{ .object = self.pending_command };
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
        }
    }
};
