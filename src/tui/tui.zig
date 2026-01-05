const std = @import("std");
const term = @import("../terminal.zig");
const connection = @import("../connection.zig");
const Color = @import("./color.zig");
const tabs = @import("./components/tabs.zig");
const panels = @import("./components/panels.zig");
const View = @import("./views/view.zig").View;
const api_view = @import("./views/api.zig");
const Config = @import("../main.zig").Config;
const Mode = @import("./types.zig").Mode;
const Rect = @import("./types.zig").Rect;
const KeyResult = @import("./types.zig").KeyResult;
const Cursor = struct {
    pub const save = "\x1b[s";
    pub const restore = "\x1b[u";
    pub const hide = "\x1b[?25l";
    pub const show = "\x1b[?25h";
};
const Zone = enum { menu, content };

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

fn clearCmdLine(stdout: std.fs.File, content: Rect) !void {
    try moveTo(stdout, content, 0, content.height);
    try stdout.writeAll("\x1b[K"); // clear line
}

// fn getView(stdout: std.fs.File, alloc: std.mem.Allocator, panel: panels.Panel, tab: usize, cfg: Config) !void {
//     switch (tab) {
//         0 => {
//             if (connection.connect(cfg.host, cfg.port)) |stream| {
//                 defer stream.close();
//                 const data = try connection.sendCmd(stream, alloc, "GetDevices");
//                 defer alloc.free(data);
//
//                 var view = try DeviceView.init(alloc, panel.rect, data);
//                 defer view.deinit();
//                 try view.render(stdout);
//                 //                 return view.row_count;
//             } else |err| {
//                 //                  try view.render(err);
//                 std.debug.print("{s}", .{@errorName(err)});
//             }
//         },
//         1 => {
//             return try api_view.draw(stdout, panel.rect);
//         },
//         else => {},
//     }
// }

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
    var panel = panels.Panel.init(content.x, content.y + 5, content.width, content.height - 5);

    // Enter alternate buffer, clear, hide cursor
    try stdout.writeAll("\x1b[?1049h\x1b[2J");
    try stdout.writeAll(Cursor.hide);

    // Title
    try moveTo(stdout, content, 0, 0);
    try print(stdout, "Kohost", .{ .color = Color.pink, .bold = true });

    // Subtitle + version on same line
    try moveTo(stdout, content, 0, 1);
    try print(stdout, "Toolbox", .{ .dim = true });

    // Version on right
    const version = "v1.1.2";
    try moveTo(stdout, content, content.width - @as(u16, @intCast(version.len)), 1);
    try print(stdout, version, .{ .dim = true });

    // Draw header line
    try moveTo(stdout, content, 0, 2);
    var i: u16 = 0;
    while (i < content.width) : (i += 1) {
        try print(stdout, "─", .{ .dim = true });
    }

    // Focus state
    var zone: Zone = .menu;

    // Draw main menu
    try tab_bar.draw(stdout, zone == .menu);
    try moveTo(stdout, content, 0, 4);

    // Draw panel
    var port_buf: [5]u8 = undefined;
    const port_str = try std.fmt.bufPrint(&port_buf, "{d}", .{cfg.port});
    const tab_1_titles: [2][]const u8 = .{ cfg.host, port_str };
    const tab_2_titles: [1][]const u8 = .{"api_config"};
    const tab_3_titles: [1][]const u8 = .{"log_config"};
    const tab_4_titles: [1][]const u8 = .{"settings_config"};
    const all_titles: [4][]const []const u8 = .{ &tab_1_titles, &tab_2_titles, &tab_3_titles, &tab_4_titles };
    try panel.draw(stdout, all_titles[tab_bar.selected]);

    // Draw initial panel content
    // Get data
    const stream = try connection.connect(cfg.host, cfg.port);
    defer stream.close();
    const data = try connection.sendCmd(stream, alloc, "GetDevices");
    defer alloc.free(data);
    const json = try std.json.parseFromSlice(std.json.Value, alloc, data, .{});
    defer json.deinit();
    // Draw
    var view = View.init(tab_bar.selected, panel.rect, &json);
    const focused = false;
    try view.render(stdout, focused);

    // Main loop
    var running = true;

    while (running) {
        var buf: [1]u8 = undefined;
        const n = try stdin.read(&buf);
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
                            try panel.draw(stdout, all_titles[tab_bar.selected]);
                            view = View.init(tab_bar.selected, panel.rect, &json);
                            try view.render(stdout, false);
                        },
                        .move_to => {
                            zone = switch (zone) {
                                .content => .menu,
                                .menu => .content,
                            };

                            try tab_bar.draw(stdout, zone == .menu);
                            view = View.init(tab_bar.selected, panel.rect, &json);
                            try view.render(stdout, zone == .content);

                            //                             try tab_bar.draw(stdout, zone == .menu);
                            //                             try drawPanelContent(stdout, alloc, panel, tab_bar.selected, cfg);
                        },
                        .unhandled => {},
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
