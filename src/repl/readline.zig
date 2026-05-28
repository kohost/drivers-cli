const std = @import("std");
const commands = @import("../commands.zig");

const Action = union(enum) {
    none, //
    up,
    down,
    left,
    right,
    word_left,
    word_right,
    word_delete,
    enter,
    backspace,
    tab,
    ctrl_a,
    char: u8,
    esc,
};
const KeyBinding = struct {
    seq: []const u8,
    action: Action,
};
const keymap = [_]KeyBinding{
    .{ .seq = &.{ 0x1B, '[', 'A' }, .action = .up },
    .{ .seq = &.{ 0x1B, '[', 'C' }, .action = .right },
    .{ .seq = &.{ 0x1B, '[', 'B' }, .action = .down },
    .{ .seq = &.{ 0x1B, '[', 'D' }, .action = .left },
    .{ .seq = &.{ 0x1B, 'b' }, .action = .word_left },
    .{ .seq = &.{ 0x1B, 'f' }, .action = .word_right },
    .{ .seq = &.{ 0x1B, 0x7F }, .action = .word_delete },
    .{ .seq = &.{ 0x1B, 0x08 }, .action = .word_delete },
    .{ .seq = &.{'\r'}, .action = .enter },
    .{ .seq = &.{'\n'}, .action = .enter },
    .{ .seq = &.{0x7F}, .action = .backspace },
    .{ .seq = &.{0x08}, .action = .backspace },
    .{ .seq = &.{0x09}, .action = .tab },
    .{ .seq = &.{0x01}, .action = .ctrl_a },
    .{ .seq = &.{0x1B}, .action = .esc },
};

fn showSuggestion(
    stdout: std.Io.File,
    io: std.Io,
    buf: []const u8,
    input_len: usize,
    cursor: usize,
    prefix: []const u8,
) !void {
    if (cursor != input_len) return;
    try stdout.writeStreamingAll(io, "\x1b[K");

    const match = commands.findMatch(buf[0..input_len]) orelse return;

    if (match.len > input_len) {
        // Partial match — show remaining chars in dim
        try stdout.writeStreamingAll(io, "\x1b[90m");
        try stdout.writeStreamingAll(io, match[input_len..]);
        try stdout.writeStreamingAll(io, "\x1b[0m");
        try setCursor(stdout, io, prefix.len + cursor);
    } else if (input_len == match.len) {
        // Exact match — show args hint if available
        const cmd = findCommand(match) orelse return;
        const args = cmd.args orelse return;
        try stdout.writeStreamingAll(io, "\x1b[90m ");
        try stdout.writeStreamingAll(io, args);
        try stdout.writeStreamingAll(io, "\x1b[0m");
        try setCursor(stdout, io, prefix.len + cursor);
    }
}

fn findCommand(name: []const u8) ?commands.CommandInfo {
    for (commands.list) |cmd| {
        if (std.mem.eql(u8, cmd.name, name)) return cmd;
    }
    return null;
}

fn findArgSlots(str: []const u8) [8]?usize {
    var slots: [8]?usize = .{null} ** 8;
    var slot_idx: usize = 0;
    var i: usize = 0;

    while (i < str.len and slot_idx < 8) : (i += 1) {
        if (str[i] == '{' or str[i] == '"') {
            slots[slot_idx] = i + 1;
            slot_idx += 1;
            if (str[i] == '"') {
                i += 1;
                while (i < str.len and str[i] != '"') : (i += 1) {}
            }
        }
    }
    return slots;
}

pub fn readUserInput(
    io: std.Io,
    buf: *[1024]u8, //
    history: *std.ArrayList([]const u8),
    prefix: []const u8,
) ![]const u8 {
    const stdin = std.Io.File.stdin();
    const stdout = std.Io.File.stdout();

    // Length of text in buffer
    var input_len: usize = 0;

    // Current cursor position
    var cursor: usize = 0;

    // Current position history
    var history_idx: ?usize = null;
    var arg_slot: usize = 0;

    // Last was escape (track for double Esc to clear line)
    var last_was_esc = false;

    while (true) {
        const action = try readKey(stdin, io);

        // Any other key resets
        if (action != .esc) last_was_esc = false;

        switch (action) {
            .none => continue,
            .backspace => {
                if (cursor > 0) {
                    const chars_to_shift = input_len - cursor;
                    if (chars_to_shift > 0) {
                        const source = buf[cursor..input_len];
                        const dest = buf[cursor - 1 .. input_len - 1];
                        @memmove(dest, source);
                    }

                    input_len -= 1;
                    cursor -= 1;

                    // Move cursor left by 1
                    try stdout.writeStreamingAll(io, "\x08");
                    // Print everything from cursor to end
                    try stdout.writeStreamingAll(io, buf[cursor..input_len]);
                    // Overright last char with a space and jump back 1
                    try stdout.writeStreamingAll(io, " \x1b[D");
                    // Reposition cursor
                    if (input_len > cursor) {
                        try setCursor(stdout, io, prefix.len + cursor);
                    }
                }
                try showSuggestion(stdout, io, buf, input_len, cursor, prefix);
            },
            .char => |c| {
                // If we are in the middle of a string shift everything over
                // to the right by one as we type.
                const chars_to_shift = input_len - cursor;
                if (chars_to_shift > 0) {
                    const dest = buf[cursor + 1 .. input_len + 1];
                    const source = buf[cursor..input_len];
                    @memmove(dest, source);
                }

                // Add char to buffer
                buf[cursor] = c;
                input_len += 1;
                cursor += 1;

                // Write to terminal
                try stdout.writeStreamingAll(io, buf[cursor - 1 .. input_len]);

                // Move cursor back if necessary (user typed mid string)
                if (input_len > cursor) {
                    try setCursor(stdout, io, prefix.len + cursor);
                }

                // Handle alias expansion
                if (expandAlias(buf, &input_len, &cursor)) {
                    try clearLine(stdout, io, prefix);
                    try stdout.writeStreamingAll(io, buf[0..input_len]);
                    if (input_len > cursor) {
                        try setCursor(stdout, io, prefix.len + cursor);
                    }
                }

                try showSuggestion(stdout, io, buf, input_len, cursor, prefix);
            },
            .ctrl_a => {
                cursor = 0;
                try setCursor(stdout, io, prefix.len);
            },
            .down => {
                if (history_idx) |idx| {
                    if (idx < history.items.len - 1) {
                        history_idx = idx + 1;
                        try clearLine(stdout, io, prefix);

                        const command = history.items[history_idx.?];
                        @memcpy(buf[0..command.len], command);
                        input_len = command.len;
                        try stdout.writeStreamingAll(io, buf[0..input_len]);
                        cursor = input_len;
                    } else {
                        // At end of history, clear line
                        history_idx = null;
                        input_len = 0;
                        cursor = 0;
                        try clearLine(stdout, io, prefix);
                    }
                }
            },
            .enter => {
                try stdout.writeStreamingAll(io, "\n");
                history_idx = null;
                return buf[0..input_len];
            },
            .esc => {
                if (last_was_esc) {
                    input_len = 0;
                    cursor = 0;
                    try clearLine(stdout, io, prefix);
                    last_was_esc = false;
                } else {
                    last_was_esc = true;
                }
                continue;
            },
            .left => {
                if (cursor > 0) {
                    cursor -= 1;
                    try stdout.writeStreamingAll(io, "\x1b[D");
                }
            },
            .right => {
                if (cursor < input_len) {
                    cursor += 1;
                    try stdout.writeStreamingAll(io, "\x1b[C");
                }
            },
            .tab => {
                if (commands.findMatch(buf[0..input_len])) |match| {
                    if (match.len > input_len) {
                        // Complete command name
                        @memcpy(buf[0..match.len], match);
                        input_len = match.len;
                        cursor = match.len;
                        arg_slot = 0;
                    } else if (input_len >= match.len) {
                        // Command complete, add/cycle args
                        for (commands.list) |cmd| {
                            if (std.mem.eql(u8, cmd.name, match)) {
                                if (cmd.args) |args| {
                                    const args_start = match.len + 1;

                                    if (input_len == match.len) {
                                        buf[input_len] = ' ';
                                        @memcpy(buf[input_len + 1 .. input_len + 1 + args.len], args);
                                        input_len += 1 + args.len;
                                        arg_slot = 0;
                                    }

                                    const slots = findArgSlots(buf[args_start..input_len]);
                                    if (slots[arg_slot]) |slot_offset| {
                                        cursor = args_start + slot_offset;
                                    }

                                    arg_slot += 1;
                                    if (slots[arg_slot] == null) {
                                        arg_slot = 0;
                                    }
                                }
                                break;
                            }
                        }
                    }

                    try clearLine(stdout, io, prefix);
                    try stdout.writeStreamingAll(io, buf[0..input_len]);
                    if (input_len > cursor) {
                        try setCursor(stdout, io, prefix.len + cursor);
                    }
                }
                try showSuggestion(stdout, io, buf, input_len, cursor, prefix);
            },
            .up => {
                if (history.items.len > 0) {
                    if (history_idx) |idx| {
                        if (idx > 0) history_idx = idx - 1;
                    } else {
                        history_idx = history.items.len - 1;
                    }

                    try clearLine(stdout, io, prefix);

                    // Copy history command to buffer
                    const command = history.items[history_idx.?];
                    @memcpy(buf[0..command.len], command);
                    input_len = command.len;

                    // Redraw command
                    try stdout.writeStreamingAll(io, buf[0..input_len]);
                    cursor = input_len;
                }
            },
            .word_delete => {
                var new_cursor = cursor;
                // Walk back over spaces
                while (new_cursor > 0 and buf[new_cursor - 1] == ' ') {
                    new_cursor -= 1;
                }
                // Keep walking until next space essentially bookending
                // the word we want to delete.
                while (new_cursor > 0 and buf[new_cursor - 1] != ' ') {
                    new_cursor -= 1;
                }

                // Delete from new_cursor to cursor
                const chars_to_del = cursor - new_cursor;
                if (chars_to_del > 0) {
                    const chars_after = input_len - cursor;
                    if (chars_after > 0) {
                        std.mem.copyForwards(u8, buf[new_cursor .. new_cursor + chars_after], buf[cursor..input_len]);
                    }
                    input_len -= chars_to_del;
                    cursor = new_cursor;

                    try clearLine(stdout, io, prefix);
                    try stdout.writeStreamingAll(io, buf[0..input_len]);
                    try stdout.writeStreamingAll(io, "\x1b[K");
                    try setCursor(stdout, io, prefix.len + cursor);
                }
            },
            .word_left => {
                // Skip back over spaces
                while (cursor > 0 and buf[cursor - 1] == ' ') {
                    cursor -= 1;
                }
                // Skip back over word
                while (cursor > 0 and buf[cursor - 1] != ' ') {
                    cursor -= 1;
                }
                try setCursor(stdout, io, prefix.len + cursor);
            },
            .word_right => {
                // Skip forward over spaces
                while (cursor < input_len and buf[cursor] == ' ') {
                    cursor += 1;
                }
                // Skip forward over word
                while (cursor < input_len and buf[cursor] != ' ') {
                    cursor += 1;
                }
                try setCursor(stdout, io, prefix.len + cursor);
            },
        }
    }
}

fn readKey(stdin: std.Io.File, io: std.Io) !Action {
    var buf: [3]u8 = undefined;
    var len: usize = 0;

    const n = stdin.readStreaming(io, &.{buf[0..1]}) catch |err| switch (err) {
        error.EndOfStream => return .none,
        else => return err,
    };
    if (n == 0) return .none;
    len = 1;

    // Get buffer length
    if (buf[0] == 0x1B) {
        const n1 = stdin.readStreaming(io, &.{buf[1..2]}) catch |err| switch (err) {
            error.EndOfStream => 0,
            else => return err,
        };
        if (n1 == 1) {
            len = 2;
            if (buf[1] == '[') {
                const n2 = stdin.readStreaming(io, &.{buf[2..3]}) catch |err| switch (err) {
                    error.EndOfStream => 0,
                    else => return err,
                };
                if (n2 == 1) {
                    len = 3;
                }
            }
        }
    }

    for (keymap) |binding| {
        if (binding.seq.len == len and std.mem.eql(u8, binding.seq, buf[0..len])) {
            return binding.action;
        }
    }

    // Char not in keymap
    if (len == 1) return .{ .char = buf[0] };

    return .none;
}

fn clearLine(stdout: std.Io.File, io: std.Io, prefix: []const u8) !void {
    try stdout.writeStreamingAll(io, "\r\x1B[K");
    try stdout.writeStreamingAll(io, prefix);
}

fn setCursor(stdout: std.Io.File, io: std.Io, col: usize) !void {
    try stdout.writeStreamingAll(io, "\r");
    if (col > 0) {
        var buf: [16]u8 = undefined;
        const cmd = std.fmt.bufPrint(&buf, "\x1b[{d}C", .{col}) catch
            unreachable;
        try stdout.writeStreamingAll(io, cmd);
    }
}

fn expandAlias(buf: *[1024]u8, input_len: *usize, cursor: *usize) bool {
    for (commands.list) |cmd| {
        if (cmd.alias) |alias| {
            if (input_len.* == alias.len and std.mem.eql(u8, buf[0..input_len.*], alias)) {
                @memcpy(buf[0..cmd.name.len], cmd.name);
                input_len.* = cmd.name.len;
                cursor.* = cmd.name.len;

                if (cmd.args) |args| {
                    buf[input_len.*] = ' ';
                    @memcpy(buf[input_len.* + 1 .. input_len.* + 1 + args.len], args);
                    input_len.* += 1 + args.len;

                    const slots = findArgSlots(buf[cmd.name.len + 1 .. input_len.*]);
                    if (slots[0]) |slot_offset| {
                        cursor.* = cmd.name.len + 1 + slot_offset;
                    }
                }
                return true;
            }
        }
    }
    return false;
}
