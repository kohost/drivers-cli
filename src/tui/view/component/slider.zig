const std = @import("std");
const Writer = std.Io.Writer;
const clamp = std.math.clamp;
const Color = @import("../../color.zig");
const Component = @import("../Component.zig");
const Cursor = @import("../../canvas.zig").Cursor;
const Frame = Component.Frame;
const KeyResult = @import("../../input.zig").KeyResult;
const MessageQueue = @import("../../message_queue.zig").MessageQueue;
const Mouse = @import("../../input.zig").Mouse;
const utils = @import("../../utils.zig");

const eighths = [_][]const u8{ "▏", "▎", "▍", "▌", "▋", "▊", "▉" };

pub fn Slider(comptime T: type) type {
    return struct {
        const Self = @This();
        source: *const T,
        vsource: *T,
        min: T,
        max: T,
        step: T,
        cells: u16,
        frame: Frame = .{},

        pub const Options = struct {
            min: T = 0,
            max: T = 100,
            step: T = 1,
            cells: u16 = 20,
        };

        pub fn init(source: *const T, vsource: *T, opts: Options) Self {
            return .{
                .source = source,
                .vsource = vsource,
                .min = opts.min,
                .max = opts.max,
                .step = opts.step,
                .cells = opts.cells,
            };
        }

        fn toFloat(value: T) f32 {
            return switch (@typeInfo(T)) {
                .int, .comptime_int => @floatFromInt(value),
                .float, .comptime_float => @floatCast(value),
                else => @compileError("Slider requires a numeric type"),
            };
        }

        fn fromFloat(value: f32) T {
            return switch (@typeInfo(T)) {
                .int, .comptime_int => @intFromFloat(@round(value)),
                .float, .comptime_float => @floatCast(value),
                else => @compileError("Slider requires a numeric type"),
            };
        }

        /// Current value's position within [min, max], normalized to 0..1 (clamped).
        /// E.g. range of 0-100 and a vsource of 43 returns 0.43
        fn fraction(self: *Self) f32 {
            const span = toFloat(self.max) - toFloat(self.min);
            if (span == 0) return 0;
            return clamp((toFloat(self.vsource.*) - toFloat(self.min)) / span, 0, 1);
        }

        /// Pins newly proposed UI value into valid range prior to storing.
        fn setClamped(self: *Self, value: f32) void {
            std.debug.print("setClamped value: {d}\n", .{value});
            const clamped_value = clamp(value, toFloat(self.min), toFloat(self.max));

            self.vsource.* = fromFloat(clamped_value);
        }

        pub fn component(self: *Self) Component {
            return .{ .ptr = self, .vtable = &.{
                .write = write,
                .handleKey = handleKey,
                .handleMouse = handleMouse,
            } };
        }

        fn write(ptr: *anyopaque, w: *Writer, _: *Cursor, f: Frame, focused: bool) anyerror!void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            self.frame = f;
            try utils.moveTo(w, f.x, f.y);

            const dirty = self.source.* != self.vsource.*;
            const fill = if (dirty) Color.yellow else if (focused) Color.lavender else Color.subtext0;

            const total_eighths: u32 = @intFromFloat(@round(self.fraction() * @as(f32, @floatFromInt(self.cells)) * 8));
            const full = total_eighths / 8;
            const rem = total_eighths % 8;

            try w.writeAll(fill);
            for (0..full) |_| try w.writeAll("█");
            if (rem > 0) try w.writeAll(eighths[rem - 1]);
            try w.writeAll(Color.overlay0);
            const drawn = full + @as(u32, if (rem > 0) 1 else 0);
            for (drawn..self.cells) |_| try w.writeAll("░");
            try w.writeAll(Color.reset);

            var buf: [16]u8 = undefined;
            const txt = switch (@typeInfo(T)) {
                .float, .comptime_float => std.fmt.bufPrint(&buf, "{d:.1}", .{self.vsource.*}) catch "",
                else => std.fmt.bufPrint(&buf, "{d}", .{self.vsource.*}) catch "",
            };
            try w.writeAll(if (dirty) Color.yellow else Color.subtext1);
            try w.writeAll(" ");
            try w.writeAll(txt);
            try w.writeAll(Color.reset);
        }

        fn handleKey(ptr: *anyopaque, key: u8, _: *MessageQueue) KeyResult {
            const self: *Self = @ptrCast(@alignCast(ptr));
            const before = self.vsource.*;
            switch (key) {
                'j' => return .focus_next,
                'k' => return .focus_prev,
                'l' => self.setClamped(toFloat(self.vsource.*) + toFloat(self.step)),
                'h' => {
                    if (self.vsource.* == self.min) return .ignored; // at min → let driver dive out
                    self.setClamped(toFloat(self.vsource.*) - toFloat(self.step));
                },
                else => return .ignored,
            }
            return if (self.vsource.* != before) .changed else .consumed;
        }

        pub fn handleMouse(ptr: *anyopaque, m: Mouse, mq: *MessageQueue) KeyResult {
            const self: *Self = @ptrCast(@alignCast(ptr));
            const start = self.frame.x;
            const cell: i32 = @as(i32, m.x) - @as(i32, start);

            if (cell < -1 or cell > self.cells) return .ignored;

            mq.post(.{ .update_pointer = utils.pointer_hand });

            if (m.press and m.btn == .left) {
                var frac: f32 = undefined;

                if (cell <= -1) {
                    frac = 0;
                } else if (cell >= self.cells) {
                    frac = 1;
                } else {
                    frac = (@as(f32, @floatFromInt(cell)) + 0.5) / @as(f32, @floatFromInt(self.cells));
                }

                const before = self.vsource.*;
                self.setClamped(toFloat(self.min) + frac * (toFloat(self.max) - toFloat(self.min)));
                return if (self.vsource.* != before) .changed else .consumed;
            }
            return .ignored;
        }
    };
}
