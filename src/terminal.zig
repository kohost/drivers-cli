const std = @import("std");
const commands = @import("commands.zig");

const KEY_CTRL_A = 0x01;
const KEY_CTRL_E = 0x05;
const KEY_TAB = 0x09;
const KEY_ESC = 0x1B;
const KEY_BACKSPACE = 0x7F;
const KEY_BACKSPACE_ALT = 0x08;
const KEY_OPTION_LEFT = 'b';
const KEY_OPTION_RIGHT = 'f';
const KEY_ARROW_UP = 'A';
const KEY_ARROW_DOWN = 'B';
const KEY_ARROW_RIGHT = 'C';
const KEY_ARROW_LEFT = 'D';
const KEY_HOME = 'H';
const KEY_END = 'F';

const EscapeAction = enum { none, up, down, left, right, word_left, word_right, word_delete };

pub fn enableRawMode() !std.posix.termios {
    const stdin = std.fs.File.stdin();

    // Bar cursor (blinking line)
    const stdout = std.fs.File.stdout();
    try stdout.writeAll("\x1b[5 q");

    // Get current term settings
    const original = try std.posix.tcgetattr(stdin.handle);

    // Make copy to modify
    var raw = original;

    // Disable canonical mode (line buffering) and echo
    raw.lflag.ICANON = false; // Read char by char, not line by line
    raw.lflag.ECHO = false; // Don't echo typed characters
    raw.lflag.ISIG = false; // Disable Ctrl+C and Ctrl+Z signals

    // Set read timeout
    raw.cc[@intFromEnum(std.posix.V.MIN)] = 0; // Min chars to read
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 1; // Timeout in deciseconds

    // Apply new settings
    try std.posix.tcsetattr(stdin.handle, .FLUSH, raw);

    // Return original so we can restore later
    return original;
}

pub fn disableRawMode(original: std.posix.termios) !void {
    const stdin = std.fs.File.stdin();
    try std.posix.tcsetattr(stdin.handle, .FLUSH, original);
}

fn readEscSeq(stdin: std.fs.File) !EscapeAction {
    var seq: [1]u8 = undefined;
    if (try stdin.read(&seq) != 1) return .none;

    if (seq[0] == KEY_OPTION_LEFT) return .word_left;
    if (seq[0] == KEY_OPTION_RIGHT) return .word_right;
    if (seq[0] == KEY_BACKSPACE) return .word_delete;
    if (seq[0] == KEY_BACKSPACE_ALT) return .word_delete;
    if (seq[0] != '[') return .none;

    var seq2: [1]u8 = undefined;
    if (try stdin.read(&seq2) != 1) return .none;
    return switch (seq2[0]) {
        KEY_ARROW_UP => .up,
        KEY_ARROW_DOWN => .down,
        KEY_ARROW_RIGHT => .right,
        KEY_ARROW_LEFT => .left,
        else => .none,
    };
}

fn showSuggestion(stdout: std.fs.File, buf: []const u8, pos: usize, cursor: usize) !void {
    if (cursor != pos) return;

    try stdout.writeAll("\x1b[K");

    if (commands.findMatch(buf[0..pos])) |match| {
        // Check if we have an exact match (command fully typed)
        const is_exact = std.mem.eql(u8, buf[0..pos], match) or
            (pos > match.len and buf[match.len] == ' ');

        if (is_exact) {
            // Show args hint if available
            for (commands.list) |cmd| {
                if (std.mem.eql(u8, cmd.name, match)) {
                    if (cmd.args) |args| {
                        // Check if args not already typed
                        if (pos == match.len) {
                            try stdout.writeAll("\x1b[90m");
                            try stdout.writeAll(" ");
                            try stdout.writeAll(args);
                            try stdout.writeAll("\x1b[0m");

                            var move_buf: [16]u8 = undefined;
                            const move_cmd = std.fmt.bufPrint(&move_buf, "\x1b[{d}D", .{args.len + 1}) catch unreachable;
                            try stdout.writeAll(move_cmd);
                        }
                    }
                    break;
                }
            }
        } else if (match.len > pos) {
            // Show command completion
            try stdout.writeAll("\x1b[90m");
            try stdout.writeAll(match[pos..]);
            try stdout.writeAll("\x1b[0m");

            var move_buf: [16]u8 = undefined;
            const move_cmd = std.fmt.bufPrint(&move_buf, "\x1b[{d}D", .{match.len - pos}) catch unreachable;
            try stdout.writeAll(move_cmd);
        }
    }
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

pub fn readUserInput(buf: *[1024]u8, history: *std.ArrayList([]const u8), prompt: []const u8) ![]const u8 {
    const stdin = std.fs.File.stdin();
    const stdout = std.fs.File.stdout();

    var pos: usize = 0; // Length of text in buffer
    var cursor: usize = 0; // Current cursor position
    var history_idx: ?usize = null; // Current position in history
    var arg_slot: usize = 0;

    while (true) {
        var byte: [1]u8 = undefined;
        const n = try stdin.read(&byte);

        if (n == 0) continue; // No data, keep waiting

        const c = byte[0];

        // Check for escape sequence
        if (c == KEY_ESC) {
            const action = try readEscSeq(stdin);

            switch (action) {
                .up => {
                    if (history.items.len > 0) {
                        if (history_idx) |idx| {
                            if (idx > 0) history_idx = idx - 1;
                        } else {
                            history_idx = history.items.len - 1;
                        }

                        // Clear current line
                        try stdout.writeAll("\r\x1B[K");
                        try stdout.writeAll(prompt);

                        // Copy history command to buffer
                        const hist_cmd = history.items[history_idx.?];
                        @memcpy(buf[0..hist_cmd.len], hist_cmd);
                        pos = hist_cmd.len;

                        // Redraw command
                        try stdout.writeAll(buf[0..pos]);
                        cursor = pos;
                    }
                },
                .down => {
                    if (history_idx) |idx| {
                        if (idx < history.items.len - 1) {
                            history_idx = idx + 1;

                            // Clear and redraw
                            try stdout.writeAll("\r\x1B[K");
                            try stdout.writeAll(prompt);

                            const hist_cmd = history.items[history_idx.?];
                            @memcpy(buf[0..hist_cmd.len], hist_cmd);
                            pos = hist_cmd.len;
                            try stdout.writeAll(buf[0..pos]);
                            cursor = pos;
                        } else {
                            // At end of history, clear line
                            history_idx = null;
                            pos = 0;
                            cursor = 0;
                            try stdout.writeAll("\r\x1B[K");
                            try stdout.writeAll(prompt);
                        }
                    }
                },
                .right => {
                    if (cursor < pos) {
                        cursor += 1;
                        try stdout.writeAll("\x1b[C");
                    }
                },
                .left => {
                    if (cursor > 0) {
                        cursor -= 1;
                        try stdout.writeAll("\x1b[D");
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
                    // Move cursor visually
                    try stdout.writeAll("\r");
                    try stdout.writeAll(prompt);
                    if (cursor > 0) {
                        var move_buf: [16]u8 = undefined;
                        const move_cmd = std.fmt.bufPrint(&move_buf, "\x1b[{d}C", .{cursor}) catch unreachable;
                        try stdout.writeAll(move_cmd);
                    }
                },
                .word_right => {
                    // Skip over word
                    while (cursor < pos and buf[cursor] != ' ') {
                        cursor += 1;
                    }
                    // Skip over spaces
                    while (cursor < pos and buf[cursor] == ' ') {
                        cursor += 1;
                    }
                    // Move cursor visually
                    try stdout.writeAll("\r");
                    try stdout.writeAll(prompt);
                    if (cursor > 0) {
                        var move_buf: [16]u8 = undefined;
                        const move_cmd = std.fmt.bufPrint(&move_buf, "\x1b[{d}C", .{cursor}) catch unreachable;
                        try stdout.writeAll(move_cmd);
                    }
                },
                .word_delete => {
                    // Find where word starts
                    var new_cursor = cursor;
                    while (new_cursor > 0 and buf[new_cursor - 1] == ' ') {
                        new_cursor -= 1;
                    }
                    while (new_cursor > 0 and buf[new_cursor - 1] != ' ') {
                        new_cursor -= 1;
                    }

                    // Delete from new_cursor to cursor
                    const chars_to_del = cursor - new_cursor;
                    if (chars_to_del > 0) {
                        const chars_after = pos - cursor;
                        if (chars_after > 0) {
                            std.mem.copyForwards(u8, buf[new_cursor .. new_cursor + chars_after], buf[cursor..pos]);
                        }
                        pos -= chars_to_del;
                        cursor = new_cursor;

                        // Redraw line
                        try stdout.writeAll("\r");
                        try stdout.writeAll(prompt);
                        try stdout.writeAll(buf[0..pos]);
                        try stdout.writeAll("\x1b[K");

                        // Move cursor back to position
                        if (pos > cursor) {
                            var move_buf: [16]u8 = undefined;
                            const move_cmd = std.fmt.bufPrint(&move_buf, "\x1b[{d}D", .{pos - cursor}) catch
                                unreachable;
                            try stdout.writeAll(move_cmd);
                        }
                    }
                },
                .none => {},
            }
            continue;
        }

        // Home
        if (c == KEY_CTRL_A) {
            cursor = 0;
            try stdout.writeAll("\r");
            try stdout.writeAll(prompt);
            continue;
        }

        // End
        if (c == KEY_END) {
            cursor = pos;
            try stdout.writeAll("\r");
            try stdout.writeAll(prompt);
            try stdout.writeAll(buf[0..pos]);
            continue;
        }

        // Enter
        if (c == '\r' or c == '\n') {
            try stdout.writeAll("\n");
            history_idx = null;
            return buf[0..pos];
        }

        // Backspace
        if (c == KEY_BACKSPACE or c == KEY_BACKSPACE_ALT) {
            if (cursor > 0) {
                // Shift chars left
                const chars_to_move = pos - cursor;
                if (chars_to_move > 0) {
                    std.mem.copyForwards(u8, buf[cursor - 1 .. pos - 1], buf[cursor..pos]);
                }
                cursor -= 1;
                pos -= 1;

                // Redraw: move back, print rest of line, clear trailing char, reposition cursor
                try stdout.writeAll("\x08");
                try stdout.writeAll(buf[cursor..pos]);
                try stdout.writeAll(" \x1b[D");

                // Move cursor back to position
                if (pos > cursor) {
                    var move_buf: [16]u8 = undefined;
                    const move_cmd = std.fmt.bufPrint(&move_buf, "\x1b[{d}D", .{pos - cursor}) catch unreachable;
                    try stdout.writeAll(move_cmd);
                }
            }

            try showSuggestion(stdout, buf, pos, cursor);
            continue;
        }

        // Tab (autocomplete, cycle args)
        if (c == KEY_TAB) {
            if (commands.findMatch(buf[0..pos])) |match| {
                if (match.len > pos) {
                    // Complete command name
                    @memcpy(buf[0..match.len], match);
                    pos = match.len;
                    cursor = match.len;
                    arg_slot = 0;

                    try stdout.writeAll("\r");
                    try stdout.writeAll(prompt);
                    try stdout.writeAll(buf[0..pos]);
                } else if (pos >= match.len) {
                    // Command complete, add args if available
                    for (commands.list) |cmd| {
                        if (std.mem.eql(u8, cmd.name, match)) {
                            if (cmd.args) |args| {
                                const args_start = match.len + 1;

                                // Only add args if not yet added
                                if (pos == match.len) {
                                    buf[pos] = ' ';
                                    @memcpy(buf[pos + 1 .. pos + 1 + args.len], args);
                                    pos += 1 + args.len;
                                    arg_slot = 0;
                                }

                                // Find slots and move to current one
                                const slots = findArgSlots(buf[args_start..pos]);
                                if (slots[arg_slot]) |slot_offset| {
                                    cursor = args_start + slot_offset;
                                }

                                // Next tab will go to next slot
                                arg_slot += 1;
                                if (slots[arg_slot] == null) {
                                    arg_slot = 0; // Wrap around
                                }

                                try stdout.writeAll("\r");
                                try stdout.writeAll(prompt);
                                try stdout.writeAll(buf[0..pos]);

                                // Move cursor back to position
                                if (pos > cursor) {
                                    var move_buf: [16]u8 = undefined;
                                    const move_cmd = std.fmt.bufPrint(&move_buf, "\x1b[{d}D", .{pos - cursor}) catch unreachable;
                                    try stdout.writeAll(move_cmd);
                                }
                            }
                            break;
                        }
                    }
                }
            }
            try showSuggestion(stdout, buf, pos, cursor);
            continue;
        }

        // Regular character
        if (pos < buf.len) {
            // Shift characters right to make room
            const chars_to_move = pos - cursor;
            if (chars_to_move > 0) {
                std.mem.copyBackwards(u8, buf[cursor + 1 .. pos + 1], buf[cursor..pos]);
            }
            buf[cursor] = c;
            pos += 1;
            cursor += 1;

            // Print from cursor to end then reposition cursor
            try stdout.writeAll(buf[cursor - 1 .. pos]);
            if (pos > cursor) {
                var move_buf: [16]u8 = undefined;
                const move_cmd = std.fmt.bufPrint(&move_buf, "\x1b[{d}D", .{pos - cursor}) catch
                    unreachable;
                try stdout.writeAll(move_cmd);
            }

            try showSuggestion(stdout, buf, pos, cursor);
        }
    }
}
