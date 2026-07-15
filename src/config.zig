pub const Config = struct {
    host: []const u8,
    port: u16,
    tui: bool,

    amqp_host: []const u8,
    amqp_port: u16,
    amqp_user: []const u8,
    amqp_pw: []const u8,
    amqp_exchange: []const u8,
};
