const std = @import("std");
const Config = @import("../config.zig").Config;
const log = std.log.scoped(.events);
const amqp = @import("amqp");

pub const Events = struct {
    conn: amqp.Connection,
    consumer: amqp.Basic.Consumer = undefined,

    pub fn init(self: *Events, io: std.Io, rx: []u8, tx: []u8, cfg: *const Config) !void {
        self.conn = amqp.Connection.init(rx, tx);

        const addr = try std.Io.net.IpAddress.parseIp4(cfg.amqp_host, cfg.amqp_port);
        var creds_buf: [128]u8 = undefined;
        const creds = try std.fmt.bufPrint(&creds_buf, "\x00{s}\x00{s}", .{
            cfg.amqp_user,
            cfg.amqp_pw,
        });

        try self.conn.connect(io, addr, creds);
        log.info("connected {s}:{d} → {s}", .{ cfg.amqp_host, cfg.amqp_port, cfg.amqp_exchange });

        var ch = try self.conn.channel();
        const queue = try ch.queueDeclare("", .{
            .exclusive = true,
            .auto_delete = true,
        }, null);
        try ch.queueBind(queue, cfg.amqp_exchange, "#");
        self.consumer = try ch.basicConsume(queue, .{ .no_ack = true }, null);
    }

    pub fn deinit(self: *Events) void {
        self.conn.deinit();
    }

    pub fn fd(self: *Events) std.posix.fd_t {
        return self.consumer.connector.stream.socket.handle;
    }

    pub fn next(self: *Events) !amqp.Message {
        return self.consumer.next();
    }
};
