const std = @import("std");
const build_options = @import("build_options");
const tui = @import("./tui.zig");
const repl = @import("./repl.zig");
const amqp = @import("amqp");
const Config = @import("./config.zig").Config;

pub const std_options = std.Options{
    .log_level = .debug,
    .logFn = myLog,
};

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const cfg = parseArgs(args, init.environ_map);

    if (cfg.tui) {
        try tui.run(cfg, init.gpa, init.io);
    } else {
        try repl.run(cfg, init.gpa, init.io);
    }
}

/// Parses command-line args into a Config.
fn parseArgs(args: []const [:0]const u8, env: *std.process.Environ.Map) Config {
    var use_tui = false;
    var host: []const u8 = "127.0.0.1";
    var port: u16 = 16483;

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--tui")) {
            use_tui = true;
            continue;
        }

        if (std.fmt.parseInt(u16, arg, 10)) |p| {
            port = p;
            continue;
        } else |_| {}

        if (isValidIp(arg)) {
            host = arg;
        }
    }

    return .{
        .host = host,
        .port = port,
        .tui = use_tui,

        .amqp_host = env.get("AMQP_HOST") orelse "127.0.0.1",
        .amqp_port = if (env.get("AMQP_PORT")) |s| std.fmt.parseInt(u16, s, 10) catch 5672 else 5672,
        .amqp_user = env.get("AMQP_USER") orelse "user",
        .amqp_pw = env.get("AMQP_PW") orelse "password",
        .amqp_exchange = env.get("AMQP_EXCHANGE") orelse "kohost.events.drivers",
    };
}

/// Validates an IPv4 address string.
fn isValidIp(addr: []const u8) bool {
    var segments: u8 = 0;
    var it = std.mem.splitScalar(u8, addr, '.');
    while (it.next()) |part| {
        if (part.len == 0) return false;
        _ = std.fmt.parseInt(u8, part, 10) catch return false;
        segments += 1;
    }
    return segments == 4;
}

fn myLog(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    if (scope == .amqp) return;
    std.log.defaultLog(level, scope, format, args);
}
