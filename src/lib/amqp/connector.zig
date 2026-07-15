const std = @import("std");
const posix = std.posix;
const proto = @import("protocol.zig");
const wire = @import("wire.zig");
const Header = @import("wire.zig").Header;
const WireBuffer = @import("wire.zig").WireBuffer;
const Connection = @import("connection.zig").Connection;
const log = std.log.scoped(.amqp);

// TODO: think up a better name for this
pub const Connector = struct {
    stream: std.Io.net.Stream = undefined,
    io: std.Io = undefined,
    // TODO: we're going to run into trouble real fast if we reallocate the buffers
    //       and we have a bunch of copies of Connector everywhere. I think we just
    //       need to store a pointer to the Connection
    rx_buffer: WireBuffer = undefined,
    tx_buffer: WireBuffer = undefined,
    connection: *Connection = undefined,
    channel: u16,

    /// std.posix lost `write` in the std.Io migration, and the lib still does
    /// blocking reads straight on the fd, so keep writes in the same style.
    pub fn sendRaw(fd: posix.fd_t, bytes: []const u8) !void {
        var i: usize = 0;
        while (i < bytes.len) {
            const n = std.c.write(fd, bytes.ptr + i, bytes.len - i);
            if (n <= 0) return error.WriteFailed;
            i += @intCast(n);
        }
    }

    pub fn sendHeader(connector: *Connector, size: u64, class: u16) !void {
        connector.tx_buffer.writeHeader(connector.channel, size, class);
        try Connector.sendRaw(connector.stream.socket.handle, connector.tx_buffer.extent());
        connector.tx_buffer.reset();
    }

    pub fn sendBody(connector: *Connector, body: []const u8) !void {
        connector.tx_buffer.writeBody(connector.channel, body);
        try Connector.sendRaw(connector.stream.socket.handle, connector.tx_buffer.extent());
        connector.tx_buffer.reset();
    }

    pub fn sendHeartbeat(connector: *Connector) !void {
        connector.tx_buffer.writeHeartbeat();
        try Connector.sendRaw(connector.stream.socket.handle, connector.tx_buffer.extent());
        connector.tx_buffer.reset();
        log.debug("Heartbeat ->", .{});
    }

    pub fn awaitHeader(connector: *Connector) !Header {
        while (true) {
            if (!connector.rx_buffer.frameReady()) {
                // TODO: do we need to retry read (if n isn't as high as we expect)?
                const n = try posix.read(connector.stream.socket.handle, connector.rx_buffer.remaining());
                connector.rx_buffer.incrementEnd(n);
                if (connector.rx_buffer.isFull()) connector.rx_buffer.shift();
                continue;
            }
            while (connector.rx_buffer.frameReady()) {
                const frame_header = try connector.rx_buffer.readFrameHeader();
                switch (frame_header.type) {
                    .Method => {
                        const method_header = try connector.rx_buffer.readMethodHeader();
                        if (method_header.class == 10 and method_header.method == 50) {
                            try proto.Connection.closeOkAsync(connector);
                            return error.ConnectionClose;
                        }
                        if (method_header.class == 20 and method_header.method == 40) {
                            try proto.Channel.closeOkAsync(connector);
                            return error.ChannelClose;
                        }
                        log.debug("awaitHeader: unexpected method {any}.{any}\n", .{ method_header.class, method_header.method });
                        return error.ImplementAsyncHandle;
                    },
                    .Heartbeat => {
                        log.debug("\t<- Heartbeat", .{});
                        try connector.rx_buffer.readEOF();
                        try connector.sendHeartbeat();
                    },
                    .Header => {
                        return connector.rx_buffer.readHeader(frame_header.size);
                    },
                    .Body => {
                        _ = try connector.rx_buffer.readBody(frame_header.size);
                    },
                }
            }
        }
        unreachable;
    }

    pub fn awaitBody(connector: *Connector) ![]u8 {
        while (true) {
            if (!connector.rx_buffer.frameReady()) {
                // TODO: do we need to retry read (if n isn't as high as we expect)?
                const n = try posix.read(connector.stream.socket.handle, connector.rx_buffer.remaining());
                connector.rx_buffer.incrementEnd(n);
                if (connector.rx_buffer.isFull()) connector.rx_buffer.shift();
                continue;
            }
            while (connector.rx_buffer.frameReady()) {
                const frame_header = try connector.rx_buffer.readFrameHeader();
                switch (frame_header.type) {
                    .Method => {
                        const method_header = try connector.rx_buffer.readMethodHeader();
                        if (method_header.class == 10 and method_header.method == 50) {
                            try proto.Connection.closeOkAsync(connector);
                            return error.ConnectionClose;
                        }
                        if (method_header.class == 20 and method_header.method == 40) {
                            try proto.Channel.closeOkAsync(connector);
                            return error.ChannelClose;
                        }
                        log.debug("awaitBody: unexpected method {any}.{any}\n", .{ method_header.class, method_header.method });
                        return error.ImplementAsyncHandle;
                    },
                    .Heartbeat => {
                        log.debug("\t<- Heartbeat", .{});
                        try connector.rx_buffer.readEOF();
                        try connector.sendHeartbeat();
                    },
                    .Header => {
                        _ = try connector.rx_buffer.readHeader(frame_header.size);
                    },
                    .Body => {
                        return connector.rx_buffer.readBody(frame_header.size);
                    },
                }
            }
        }
        unreachable;
    }

    pub fn awaitMethod(connector: *Connector, comptime T: type) !T {
        while (true) {
            if (!connector.rx_buffer.frameReady()) {
                // TODO: do we need to retry read (if n isn't as high as we expect)?
                const n = try posix.read(connector.stream.socket.handle, connector.rx_buffer.remaining());
                connector.rx_buffer.incrementEnd(n);
                if (connector.rx_buffer.isFull()) connector.rx_buffer.shift();
                continue;
            }
            while (connector.rx_buffer.frameReady()) {
                const frame_header = try connector.rx_buffer.readFrameHeader();
                switch (frame_header.type) {
                    .Method => {
                        const method_header = try connector.rx_buffer.readMethodHeader();
                        if (T.CLASS == method_header.class and T.METHOD == method_header.method) {
                            return T.read(connector);
                        } else {
                            if (method_header.class == 10 and method_header.method == 50) {
                                _ = try proto.Connection.Close.read(connector);
                                try proto.Connection.closeOkAsync(connector);
                                return error.ConnectionClose;
                            }
                            if (method_header.class == 20 and method_header.method == 40) {
                                _ = try proto.Channel.Close.read(connector);
                                try proto.Channel.closeOkAsync(connector);
                                return error.ChannelClose;
                            }
                            log.debug("awaitBody: unexpected method {any}.{any}\n", .{ method_header.class, method_header.method });
                            return error.ImplementAsyncHandle;
                        }
                    },
                    .Heartbeat => {
                        log.debug("\t<- Heartbeat", .{});
                        try connector.rx_buffer.readEOF();
                        try connector.sendHeartbeat();
                    },
                    .Header => {
                        _ = try connector.rx_buffer.readHeader(frame_header.size);
                    },
                    .Body => {
                        _ = try connector.rx_buffer.readBody(frame_header.size);
                    },
                }
            }
        }
        unreachable;
    }
};
