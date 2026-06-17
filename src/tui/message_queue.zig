pub const Message = union(enum) {
    quit,
    open_input: u8,
    submit_input,
    cancel_input,
    view_changed: usize,
    render,
    send_command,
    command_changed: []const u8,
};

pub const MessageQueue = struct {
    buf: [16]Message,
    len: usize,

    pub fn init() MessageQueue {
        return .{
            .buf = undefined,
            .len = 0,
        };
    }

    pub fn post(self: *MessageQueue, msg: Message) void {
        if (self.len < self.buf.len) {
            self.buf[self.len] = msg;
            self.len += 1;
        }
    }

    pub fn drain(self: *MessageQueue) []const Message {
        const msgs = self.buf[0..self.len];
        self.len = 0;
        return msgs;
    }
};
