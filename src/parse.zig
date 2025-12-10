const std = @import("std");

pub fn applyFilter(alloc: std.mem.Allocator, json_str: []const u8, filter: []const u8) ![]const u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, json_str, .{});
    defer parsed.deinit();

    var current = parsed.value;
    var i: usize = 0;

    // Handle root array with field access
    if (filter.len > 0 and filter[0] == '.' and filter.len > 1 and filter[1] != '[') {
        switch (current) {
            .array => |arr| {
                var aw: std.Io.Writer.Allocating = .init(alloc);
                errdefer aw.deinit();
                var first = true;

                for (arr.items) |item| {
                    var item_writer: std.Io.Writer.Allocating = .init(alloc);
                    defer item_writer.deinit();
                    try std.json.fmt(item, .{}).format(&item_writer.writer);
                    const item_str = try item_writer.toOwnedSlice();
                    defer alloc.free(item_str);

                    const filtered = try applyFilter(alloc, item_str, filter);
                    defer alloc.free(filtered);

                    if (!first) try aw.writer.writeByte('\n');
                    first = false;
                    try aw.writer.writeAll(filtered);
                }
                return try aw.toOwnedSlice();
            },
            else => {},
        }
    }
    while (i < filter.len) {
        const c = filter[i];

        if (c == '.') {
            i += 1;
            if (i >= filter.len) break;

            const start = i;
            while (i < filter.len and filter[i] != '.' and filter[i] != '[') {
                i += 1;
            }
            const field = filter[start..i];

            if (field.len > 0) {
                switch (current) {
                    .object => |obj| {
                        current = obj.get(field) orelse return error.FieldNotFound;
                    },
                    .array => |arr| {
                        const remaining_filter = filter[i..];

                        var aw: std.Io.Writer.Allocating = .init(alloc);
                        errdefer aw.deinit();
                        var first = true;

                        for (arr.items) |item| {
                            switch (item) {
                                .object => |obj| {
                                    if (obj.get(field)) |val| {
                                        if (remaining_filter.len > 0) {
                                            var val_writer: std.Io.Writer.Allocating =
                                                .init(alloc);
                                            defer val_writer.deinit();
                                            try std.json.fmt(val, .{}).format(&val_writer.writer);
                                            const val_str = try val_writer.toOwnedSlice();
                                            defer alloc.free(val_str);

                                            const filtered = try applyFilter(alloc, val_str, remaining_filter);
                                            defer alloc.free(filtered);

                                            if (!first) try aw.writer.writeByte('\n');
                                            first = false;
                                            try aw.writer.writeAll(filtered);
                                        } else {
                                            if (!first) try aw.writer.writeByte('\n');
                                            first = false;
                                            try std.json.fmt(val, .{}).format(&aw.writer);
                                        }
                                    }
                                },
                                else => {},
                            }
                        }
                        return try aw.toOwnedSlice();
                    },
                    else => return error.NotAnObject,
                }
            }
        } else if (c == '[') {
            i += 1;
            const idx_start = i;
            while (i < filter.len and filter[i] != ']') {
                i += 1;
            }
            const idx_str = filter[idx_start..i];
            const idx = try std.fmt.parseInt(usize, idx_str, 10);
            i += 1;

            switch (current) {
                .array => |arr| {
                    if (arr.items.len <= idx) return error.IndexOutOfBounds;
                    current = arr.items[idx];
                },
                else => return error.NotAnArray,
            }
        } else {
            i += 1;
        }
    }

    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    try std.json.fmt(current, .{}).format(&aw.writer);
    return try aw.toOwnedSlice();
}

// Kohost responses come in the {data: response} format.
// This function strips off the data wrapper.
pub fn getData(alloc: std.mem.Allocator, str: []const u8) ![]const u8 {
    const response = try std.json.parseFromSlice(std.json.Value, alloc, str, .{});
    defer response.deinit();

    // Extract just the data field if it exists
    const data_val = if (response.value.object.get("data")) |data| data else response.value;

    // Stringify it back to JSON string
    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();

    try std.json.fmt(data_val, .{}).format(&aw.writer);

    const data_str = try aw.toOwnedSlice();

    return data_str;
}

// Pretty prints JSON
// Used to format (indent) JSON to console
pub fn formatJSON(alloc: std.mem.Allocator, str: []const u8) ![]const u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, str, .{});
    defer parsed.deinit();

    // Writer that starts with 0 memory allocated
    var aw: std.Io.Writer.Allocating = .init(alloc);
    // Schedules this when func exits to free any memory the writer ended up allocating
    defer aw.deinit();

    // 1. Create formatter obj
    // 2. Call formatter's format method
    // 3. Pass pointer to aw.writer
    // 4. Formatter walks JSON tree and writes formatted output
    try std.json.fmt(parsed.value, .{ .whitespace = .indent_2 }).format(&aw.writer);

    // 1. Converts internal state to an ArrayList
    // 2. Transfer ownership to caller
    // 3. Put empty list back in writer
    // 4. Return the buffer
    //
    // So the buffer gets "stolen" from the writer and given to the caller. The
    // writer is left empty, so when defer aw.deinit() runs, it's freeing nothing.
    return try aw.toOwnedSlice();
}

// Builds request in format Kohost expects
// {command: string, data: Object}
// ex. {command: UpdateDevices, data: {devices: [{id:1234, level: 50}]} }
pub fn buildRequest(alloc: std.mem.Allocator, input: []const u8) ![]const u8 {
    var parts = std.mem.splitScalar(u8, input, ' ');

    // First part is the command
    const cmd = parts.first();

    // Build data obj
    var data_map = std.json.ObjectMap.init(alloc);
    defer data_map.deinit();

    // Optionally holds a single parsed JSON value

    // TODO: If we need to pass more than a single key that contains JSON
    // then we can add an array here and push the paresd values, then this
    // defer can loop through them and deinit.
    var parsed: ?std.json.Parsed(std.json.Value) = null;
    defer if (parsed) |*p| p.deinit();

    while (parts.next()) |arg| {
        if (std.mem.indexOf(u8, arg, "=")) |idx| {
            const key = arg[0..idx];
            const val_str = arg[idx + 1 ..];

            if (val_str[0] == '[' or val_str[0] == '{') {
                // Parse as JSON (array or object)
                parsed = try std.json.parseFromSlice(std.json.Value, alloc, val_str, .{});
                try data_map.put(key, parsed.?.value);
            } else if (std.mem.eql(u8, val_str, "true")) {
                try data_map.put(key, .{ .bool = true });
            } else if (std.mem.eql(u8, val_str, "false")) {
                try data_map.put(key, .{ .bool = false });
            } else if (std.fmt.parseInt(i64, val_str, 10)) |num| {
                try data_map.put(key, .{ .integer = num });
            } else |_| {
                if (std.fmt.parseFloat(f64, val_str)) |num| {
                    try data_map.put(key, .{ .float = num });
                } else |_| {
                    try data_map.put(key, .{ .string = val_str });
                }
            }
        }
    }

    // Build complete request obj
    var req_map = std.json.ObjectMap.init(alloc);
    defer req_map.deinit();

    try req_map.put("command", .{ .string = cmd });
    try req_map.put("data", .{ .object = data_map });

    const req_val = std.json.Value{ .object = req_map };

    // Format JSON to string
    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();

    try std.json.fmt(req_val, .{}).format(&aw.writer);

    return try aw.toOwnedSlice();
}
