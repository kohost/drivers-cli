const std = @import("std");
const term = @import("../terminal.zig");
const connection = @import("../connection.zig");
const tabs = @import("./components/tabs.zig");
const panels = @import("./components/panels.zig");
const AppState = @import("state/state.zig").AppState;
const View = @import("./views/view.zig").View;
const Config = @import("../main.zig").Config;
const Mode = @import("./types.zig").Mode;
const Rect = @import("./types.zig").Rect;
const KeyResult = @import("./types.zig").KeyResult;
const api_view = @import("./views/api.zig");
const Color = @import("./color.zig");
const Notification = @import("./components/notification.zig").Notification;
const amqp = @import("amqp");
const Zone = enum { menu, content };
const Cursor = struct {
    pub const save = "\x1b[s";
    pub const restore = "\x1b[u";
    pub const hide = "\x1b[?25l";
    pub const show = "\x1b[?25h";
};

fn print(stdout: std.fs.File, text: []const u8, opts: struct {
    color: ?[]const u8 = null,
    bold: bool = false,
    dim: bool = false,
}) !void {
    if (opts.bold) try stdout.writeAll("\x1b[1m");
    if (opts.dim) try stdout.writeAll("\x1b[2m");
    if (opts.color) |color| try stdout.writeAll(color);
    try stdout.writeAll(text);
    try stdout.writeAll(Color.reset);
}

fn getTermSize() !struct { cols: u16, rows: u16 } {
    var ws: std.posix.winsize = undefined;
    const rc = std.posix.system.ioctl(std.posix.STDOUT_FILENO, std.posix.T.IOCGWINSZ, @intFromPtr(&ws));
    if (rc != 0) return error.IoctlFailed;
    return .{ .cols = ws.col, .rows = ws.row };
}

fn moveTo(stdout: std.fs.File, content: Rect, x: u16, y: u16) !void {
    var buf: [32]u8 = undefined;
    const cmd = try std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ content.y + y, content.x + x });
    try stdout.writeAll(cmd);
}

fn drawCmdLine(stdout: std.fs.File, content: Rect, cmd: []const u8) !void {
    try moveTo(stdout, content, 0, content.height);
    try stdout.writeAll("\x1b[K"); // clear line
    try stdout.writeAll(":");
    try stdout.writeAll(cmd);
}

fn drawHeader(stdout: std.fs.File, content: Rect) !void {
    try moveTo(stdout, content, 0, 0);
    try print(stdout, "Kohost", .{ .color = Color.pink, .bold = true });
    try moveTo(stdout, content, 0, 1);
    try print(stdout, "Toolbox", .{ .dim = true });
    const version = "v1.1.2";
    try moveTo(stdout, content, content.width - @as(u16, @intCast(version.len)), 1);
    try print(stdout, version, .{ .dim = true });
    try moveTo(stdout, content, 0, 2);
    var i: u16 = 0;
    while (i < content.width) : (i += 1) {
        try print(stdout, "─", .{ .dim = true });
    }
}

fn clearCmdLine(stdout: std.fs.File, content: Rect) !void {
    try moveTo(stdout, content, 0, content.height);
    try stdout.writeAll("\x1b[K"); // clear line
}

fn getResponseError(json: std.json.Value) ?[]const u8 {
    const errors = json.object.get("errors") orelse return null;
    if (errors != .array) return null;
    if (errors.array.items.len == 0) return null;
    const first = errors.array.items[0];
    if (first != .object) return null;
    const msg = first.object.get("message") orelse return null;
    if (msg != .string) return null;
    return msg.string;
}

pub fn run(cfg: Config, alloc: std.mem.Allocator) !void {
    const stdout = std.fs.File.stdout();
    const stdin = std.fs.File.stdin();
    const original_termios = try term.enableRawMode();
    defer term.disableRawMode(original_termios) catch {};
    const termSize = try getTermSize();
    const padding: u16 = 2;
    const content = Rect{ .x = padding, .y = padding, .width = termSize.cols - (padding * 2), .height = termSize.rows - padding };
    var mode = Mode.normal;
    var cmd_buf: [64]u8 = undefined;
    var cmd_len: usize = 0;
    var tab_bar = tabs.Tab.init(
        &.{ "Devices", "API", "Logs", "Settings" },
        content.x,
        content.y + 3,
    );

    // Enter alternate buffer, clear, hide cursor
    try stdout.writeAll("\x1b[?1049h\x1b[2J");
    try stdout.writeAll(Cursor.hide);

    try drawHeader(stdout, content);

    // Focus state
    var zone: Zone = .menu;

    // Draw main menu
    try tab_bar.draw(stdout, zone == .menu);
    try moveTo(stdout, content, 0, 4);

    // Initialize data
    var state = AppState.init(alloc);
    defer state.deinit();

    // Load initial state
    var notification = Notification.init();
    const init_err: ?[]const u8 = blk: {
        const stream = connection.connect(cfg.host, cfg.port) catch |err| break :blk @errorName(err);
        defer stream.close();
        const raw = connection.sendCmd(stream, alloc, "GetDevices") catch |err| break :blk @errorName(err);
        defer alloc.free(raw);
        const parsed = std.json.parseFromSlice(std.json.Value, alloc, raw, .{}) catch |err| break :blk @errorName(err);
        defer parsed.deinit();
        if (getResponseError(parsed.value)) |err_msg| break :blk err_msg;
        state.loadFromJson(parsed.value) catch |err| break :blk @errorName(err);
        break :blk null;
    };
    if (init_err) |err_msg| {
        notification.show(err_msg);
        notification.render(stdout, termSize.cols);
    }

    // Draw content
    const view_buf = try alloc.alloc([]const u8, state.devices.items.len);
    defer alloc.free(view_buf);
    var view_content = content;
    view_content.y += 5;
    var view = View.init(tab_bar.selected, cfg, view_content, &state, view_buf, termSize.cols, termSize.rows);
    try view.render(stdout, zone == .content);

    // AMQP setup
    var rx_mem: [4096]u8 = undefined;
    var tx_mem: [4096]u8 = undefined;
    var amqp_conn = amqp.Connection.init(&rx_mem, &tx_mem);
    const address = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 5672);
    amqp_conn.connect(address, "\x00user\x00password") catch |err| {
        std.debug.print("AMQP connect failed: {s}\n", .{@errorName(err)});
        return;
    };
    defer amqp_conn.deinit();

    var ch = try amqp_conn.channel();
    const queue_name = try ch.queueDeclare("", .{ .exclusive = true, .auto_delete = true }, null);
    try ch.queueBind(queue_name, "kohost.events.drivers", "#");
    var consumer = try ch.basicConsume(queue_name, .{ .no_ack = true }, null);

    // Main loop
    var running = true;
    var poll_fds = [_]std.posix.pollfd{
        .{ .fd = stdin.handle, .events = std.posix.POLL.IN, .revents = 0 },
        .{ .fd = consumer.connector.file.handle, .events = std.posix.POLL.IN, .revents = 0 },
    };

    while (running) {
        const animating = notification.isAnimating() or view.isAnimating();
        const poll_timeout: i32 = if (animating) 16 else 100;
        _ = std.posix.poll(&poll_fds, poll_timeout) catch continue;

        if (notification.tick(stdout, termSize.cols)) {
            try drawHeader(stdout, content);
            notification.renderAnimated(stdout, termSize.cols);
        }

        if (view.isAnimating()) {
            try view.tickSpinner(stdout);
        }

        // Handle AMQP message
        if (poll_fds[1].revents & std.posix.POLL.IN != 0) {
            const msg = consumer.next() catch continue;
            const parsed = std.json.parseFromSlice(std.json.Value, alloc, msg.body, .{}) catch continue;
            defer parsed.deinit();
            if (getResponseError(parsed.value)) |err_msg| {
                notification.show(err_msg);
                notification.render(stdout, termSize.cols);
            }
            if (state.update(parsed.value)) {
                try view.render(stdout, zone == .content);
            }
        }

        // Handle keypress
        if (poll_fds[0].revents & std.posix.POLL.IN == 0) continue;
        var buf: [1]u8 = undefined;
        const n = stdin.read(&buf) catch continue;
        if (n == 0) continue;
        const c = buf[0];

        switch (mode) {
            .normal => {
                if (c == ':') {
                    mode = .command;
                    cmd_len = 0;
                    try stdout.writeAll(Cursor.show);
                    try stdout.writeAll(Cursor.save);
                    try drawCmdLine(stdout, content, "");
                } else {
                    const result: KeyResult = switch (zone) {
                        .menu => try tab_bar.handleKey(stdout, c),
                        .content => try view.handleKey(stdout, c),
                    };

                    switch (result) {
                        .consumed => {
                            view = View.init(tab_bar.selected, cfg, view_content, &state, view_buf, termSize.cols, termSize.rows);
                            try view.render(stdout, false);
                        },
                        .move_to => {
                            zone = switch (zone) {
                                .content => .menu,
                                .menu => .content,
                            };

                            try tab_bar.draw(stdout, zone == .menu);
                            //                             view = View.init(tab_bar.selected, panel.rect, &data, view_buf);
                            try view.render(stdout, zone == .content);

                            // Draw or clear detail panel based on zone
                            if (zone == .content and tab_bar.selected == 0) {
                                //                                 const device_id: ?[]const u8 = switch (data) {
                                //                                     .json => |json| blk: {
                                //                                         const devices = json.value.object.get("data") orelse break :blk null;
                                //                                         const device = devices.array.items[view.devices.cursor];
                                //                                         break :blk if (device.object.get("id")) |id| id.string else null;
                                //                                     },
                                //                                     .err => null,
                                //                                 };
                                //                                 const detail_titles: [1]?[]const u8 = .{device_id};
                                //                                 try detail_panel.draw(stdout, &detail_titles);
                            } else {
                                // Clear detail panel
                                //                                 try detail_panel.clear(stdout);
                            }
                        },
                        .command => |cmd| {
                            const stream = connection.connect(cfg.host, cfg.port) catch continue;
                            defer stream.close();
                            const raw = connection.sendCmd(stream, alloc, cmd) catch continue;
                            defer alloc.free(raw);
                            const parsed = std.json.parseFromSlice(std.json.Value, alloc, raw, .{}) catch continue;
                            defer parsed.deinit();
                            if (getResponseError(parsed.value)) |err_msg| {
                                notification.show(err_msg);
                                notification.render(stdout, termSize.cols);
                            }
                            if (state.update(parsed.value)) {
                                try view.render(stdout, zone == .content);
                            }
                        },
                        .unhandled => {},
                    }
                    // Refresh device detail panel
                    if (zone == .content and tab_bar.selected == 0) {
                        //                         const device_id: ?[]const u8 = switch (data) {
                        //                             .json => |json| blk: {
                        //                                 const devices = json.value.object.get("data") orelse break :blk null;
                        //                                 const device = devices.array.items[view.devices.cursor];
                        //                                 break :blk if (device.object.get("id")) |id| id.string else null;
                        //                             },
                        //                             .err => null,
                        //                         };
                        //                         const detail_titles: [1]?[]const u8 = .{device_id};
                        //                         try detail_panel.draw(stdout, &detail_titles);
                    }
                }
            },
            .command => {
                switch (c) {
                    '\r', '\n' => {
                        const cmd = cmd_buf[0..cmd_len];
                        if (std.mem.eql(u8, cmd, "q")) {
                            running = false;
                        }
                        mode = .normal;
                        try stdout.writeAll(Cursor.hide);
                        try clearCmdLine(stdout, content);
                        try stdout.writeAll(Cursor.restore);
                    },
                    0x1b => { // Escape
                        mode = .normal;
                        try stdout.writeAll(Cursor.hide);
                        try clearCmdLine(stdout, content);
                        try stdout.writeAll(Cursor.restore);
                    },
                    0x7f => { // Backspace
                        if (cmd_len > 0) {
                            cmd_len -= 1;
                            try drawCmdLine(stdout, content, cmd_buf[0..cmd_len]);
                        } else {
                            mode = .normal;
                            try stdout.writeAll(Cursor.hide);
                            try clearCmdLine(stdout, content);
                            try stdout.writeAll(Cursor.restore);
                        }
                    },
                    else => {
                        if (cmd_len < cmd_buf.len) {
                            cmd_buf[cmd_len] = c;
                            cmd_len += 1;
                            try drawCmdLine(stdout, content, cmd_buf[0..cmd_len]);
                        }
                    },
                }
            },
        }
    }

    // Restore original buffer
    try stdout.writeAll(Cursor.show);
    try stdout.writeAll("\x1b[?1049l");
}
