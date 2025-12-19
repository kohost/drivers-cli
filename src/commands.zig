const std = @import("std");

pub const CommandInfo = struct { name: []const u8, alias: ?[]const u8, description: []const u8, args: ?[]const u8 };

pub const list = [_]CommandInfo{
    .{ .name = "GetHealth", .alias = "gh", .description = "Gets system health", .args = null },
    .{ .name = "GetLogs", .alias = "gl", .description = "Gets system logs", .args = "beginDateTime=\"\" endDateTime=\"\"" },
    .{ .name = "GetMobileKey", .alias = "gm", .description = "Gets mobile key", .args = "lockIds=[\"\"] phone=\"+\" beginDateTime=\"\" endDateTime=\"\"" },

    .{ .name = "GetDevices", .alias = "gd", .description = "Get all devices", .args = null },
    .{ .name = "UpdateDevices", .alias = "ud", .description = "Updates devices", .args = "devices=[{}]" },
    .{ .name = "AddDevices", .alias = "ad", .description = "Add devices", .args = "devices=[{}]" },
    .{ .name = "DeleteDevices", .alias = "dd", .description = "Delete devices", .args = "devices=[{}]" },

    .{ .name = "GetCredentials", .alias = "gc", .description = "Get all credentials", .args = null },
    .{ .name = "UpdateCredentials", .alias = "uc", .description = "Updates credentials", .args = "credentials=[{}] auth=\"\"" },
    .{ .name = "AddCredentials", .alias = "ac", .description = "Add credentials", .args = "credentials=[{}] auth=\"\"" },
    .{ .name = "DeleteCredentials", .alias = "dc", .description = "Delete credentials", .args = "credentials=[{}] auth=\"\"" },
};

pub fn findMatch(str: []const u8) ?[]const u8 {
    if (str.len == 0) return null;

    var best_match: ?[]const u8 = null;

    for (list) |cmd| {
        // Check if str starts with command name, or command starts with str
        if (cmd.name.len >= str.len) {
            // str is shorter - check if command starts with str
            if (std.mem.eql(u8, cmd.name[0..str.len], str)) {
                if (best_match == null or std.mem.lessThan(u8, cmd.name, best_match.?)) {
                    best_match = cmd.name;
                }
            }
        } else if (str.len > cmd.name.len) {
            // str is longer - check if str starts with command (followed by space)
            if (std.mem.eql(u8, str[0..cmd.name.len], cmd.name)) {
                if (str[cmd.name.len] == ' ') {
                    if (best_match == null or std.mem.lessThan(u8, cmd.name, best_match.?)) {
                        best_match = cmd.name;
                    }
                }
            }
        }

        // Check alias
        if (cmd.alias) |alias| {
            if (std.mem.eql(u8, str, alias)) {
                return cmd.name;
            }
        }
    }
    return best_match;
}
