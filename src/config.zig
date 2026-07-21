pub const Config = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 16483,
    tui: bool = false,

    amqp_host: []const u8 = "127.0.0.1",
    amqp_port: u16 = 5672,
    amqp_user: []const u8 = "user",
    amqp_pw: []const u8 = "password",
    amqp_exchange: []const u8 = "kohost.events.drivers",
};
