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
    pending_command: []const u8,
    transport: Transport,

    pub fn init(
        alloc: std.mem.Allocator,
        state: *State,
        cols: u16,
        rows: u16,
        cfg: Config,
    ) !App {
        const x = 1;
        const y = 5;
        const width = cols;
        const height = rows - 6;
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
            .pending_command = "UpdateDevices",
            .transport = Transport.init(alloc, cfg),
        };
    }

    pub fn deinit(self: *App) void {
        self.view.deinit();
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
            std.debug.print("mq: {s}\n", .{@tagName(msg)});
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
                .send_command => blk: {
                    var data_map = std.json.ObjectMap.init(self.alloc);
                    defer data_map.deinit();

                    var req_map = std.json.ObjectMap.init(self.alloc);
                    defer req_map.deinit();

                    req_map.put("command", .{ .string = self.pending_command }) catch break :blk;
                    req_map.put("data", .{ .object = data_map }) catch break :blk;

                    var aw: std.Io.Writer.Allocating = .init(self.alloc);
                    defer aw.deinit();

                    const root = std.json.Value{ .object = req_map };
                    std.json.fmt(root, .{ .whitespace = .indent_2 }).format(&aw.writer) catch break :blk;

                    self.view.setRequest(aw.written()) catch break :blk;

                    if (self.transport.fetch(self.pending_command)) |parsed| {
                        defer parsed.deinit();
                        var res_aw: std.Io.Writer.Allocating = .init(self.alloc);
                        defer res_aw.deinit();
                        std.json.fmt(parsed.value, .{ .whitespace = .indent_2 }).format(&res_aw.writer) catch break :blk;
                        self.view.setResponse(res_aw.written()) catch break :blk;
                        _ = self.state.update(parsed.value);
                    }
                },
                .command_changed => |name| self.pending_command = name,
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
};
