const std = @import("std");
const Rect = @import("../types.zig").Rect;
const KeyResult = @import("../types.zig").KeyResult;
const Color = @import("../color.zig");
const Column = struct { name: []const u8, width: u8 };
const columns = [_]Column{
    .{ .name = "Label1", .width = 10 },
    .{ .name = "Label2", .width = 10 },
    .{ .name = "Label3", .width = 10 },
    .{ .name = "Label4", .width = 10 },
    .{ .name = "Label5", .width = 10 },
    .{ .name = "Label6", .width = 10 },
    .{ .name = "Label7", .width = 10 },
};
const Row = struct {
    Label1: []const u8,
    Label2: []const u8,
    Label3: []const u8,
    Label4: []const u8,
    Label5: []const u8,
    Label6: []const u8,
    Label7: []const u8,
};

const devices = [_]Row{
    .{ .Label1 = "Item1", .Label2 = "Item1a", .Label3 = "Item1b", .Label4 = "Item1c", .Label5 = "Item1d", .Label6 = "Item1e", .Label7 = "Item1f" },
    .{ .Label1 = "Item2", .Label2 = "Item2a", .Label3 = "Item2b", .Label4 = "Item2c", .Label5 = "Item2d", .Label6 = "Item2e", .Label7 = "Item2f" },
    .{ .Label1 = "Item3", .Label2 = "Item3a", .Label3 = "Item3b", .Label4 = "Item3c", .Label5 = "Item3d", .Label6 = "Item3e", .Label7 = "Item3f" },
    .{ .Label1 = "Item4", .Label2 = "Item4a", .Label3 = "Item4b", .Label4 = "Item4c", .Label5 = "Item4d", .Label6 = "Item4e", .Label7 = "Item4f" },
    .{ .Label1 = "Item5", .Label2 = "Item5a", .Label3 = "Item5b", .Label4 = "Item5c", .Label5 = "Item5d", .Label6 = "Item5e", .Label7 = "Item5f" },
    .{ .Label1 = "Item6", .Label2 = "Item6a", .Label3 = "Item6b", .Label4 = "Item6c", .Label5 = "Item6d", .Label6 = "Item6e", .Label7 = "Item6f" },
    .{ .Label1 = "Item7", .Label2 = "Item7a", .Label3 = "Item7b", .Label4 = "Item7c", .Label5 = "Item7d", .Label6 = "Item7e", .Label7 = "Item7f" },
};

pub fn draw(stdout: std.fs.File, area: Rect) !void {
    return try writeContent(stdout, area);
}

fn writeContent(stdout: std.fs.File, area: Rect) !void {
    var pos_buf: [16]u8 = undefined;
    var item_count: u8 = 0;
    const yPad: u8 = 2;
    const xPad: u8 = 1;

    for (devices, 0..) |device, idx| {
        const yPos = area.y + @as(u8, @intCast(idx)) + yPad;
        item_count += 1;

        // Indicator
        //         const is_focused = if (focus) |f| idx == f else false;
        //         const indicator_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ yPos, area.x });
        //         try stdout.writeAll(indicator_pos);
        //         try stdout.writeAll(Color.teal);
        //         if (is_focused) {
        //             try stdout.writeAll("┃");
        //         } else {
        //             try stdout.writeAll(Color.dim);
        //             try stdout.writeAll("│");
        //         }
        //         try stdout.writeAll(Color.reset);

        // Content - aligned to columns
        const row_pos = try std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ yPos, area.x + xPad });
        try stdout.writeAll(row_pos);

        const fields = [_][]const u8{
            device.Label1,
            device.Label2,
            device.Label3,
            device.Label4,
            device.Label5,
            device.Label6,
            device.Label7,
        };

        for (columns, 0..) |col, i| {
            const value = fields[i];
            try stdout.writeAll(" ");
            try stdout.writeAll(value);
            var pad: u8 = @intCast(value.len);
            while (pad < col.width) : (pad += 1) try stdout.writeAll(" ");
            try stdout.writeAll(" ");
        }
    }
}

pub fn handleKey(c: u8, cursor: *?u8, row_count: u8) !KeyResult {
    const row = cursor.* orelse 0;
    switch (c) {
        'j' => {
            if (row < row_count -| 1) {
                cursor.* = row + 1;
            } else {
                cursor.* = 0;
            }
            return .consumed;
        },
        'k' => {
            if (row > 0) {
                cursor.* = row - 1;
                return .consumed;
            }
            cursor.* = null;
            return .{ .move_to = .up };
        },
        else => return .unhandled,
    }
}
