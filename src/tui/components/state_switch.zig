const std = @import("std");
const Color = @import("../color.zig");

pub const StateSwitch = struct {
    x: u16,
    y: u16,
    current: u8,
    states: []const State,
    spin_frame: u8 = 0,
    last_spin: i64 = 0,

    const blink_interval: i64 = 500;

    pub const State = struct {
        label: []const u8,
        icon: []const u8,
        color: []const u8,
        in_progress: bool = false,
    };

    pub fn init(x: u16, y: u16, states: []const State) StateSwitch {
        return .{ .x = x, .y = y, .current = 0, .states = states };
    }

    pub fn isAnimating(self: *StateSwitch) bool {
        if (self.current >= self.states.len) return false;
        return self.states[self.current].in_progress;
    }

    pub fn render(self: *StateSwitch, stdout: std.fs.File, focused: bool) !void {
        var pos_buf: [32]u8 = undefined;
        const pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ self.y, self.x });
        try stdout.writeAll(pos);

        if (self.current >= self.states.len) return;
        const state = self.states[self.current];

        // Clear previous content (max label + icon + space)
        try stdout.writeAll("          ");
        try stdout.writeAll(pos);

        if (state.in_progress) {
            const now = std.time.milliTimestamp();
            if (now - self.last_spin >= blink_interval) {
                self.spin_frame +%= 1;
                self.last_spin = now;
            }
            const icon_visible = self.spin_frame % 2 == 0;
            try stdout.writeAll(state.color);
            if (icon_visible) {
                try stdout.writeAll(state.icon);
            } else {
                try stdout.writeAll(" ");
            }
            try stdout.writeAll(" ");
            try stdout.writeAll(Color.reset);
            if (focused) {
                try stdout.writeAll("\x1b[4m");
                try stdout.writeAll(Color.underline_peach);
            }
            try stdout.writeAll(state.label);
        } else {
            try stdout.writeAll(state.color);
            try stdout.writeAll(state.icon);
            try stdout.writeAll(" ");
            try stdout.writeAll(Color.reset);
            if (focused) {
                try stdout.writeAll("\x1b[4m");
                try stdout.writeAll(Color.underline_peach);
            }
            try stdout.writeAll(state.label);
        }

        try stdout.writeAll(Color.reset);
    }
};
