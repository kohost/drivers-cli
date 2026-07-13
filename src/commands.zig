const std = @import("std");

pub const Command = enum {
    GetHealth,
    GetLogs,
    GetMobileKey,

    GetDevices,
    UpdateDevices,
    AddDevices,
    DeleteDevices,

    GetCredentials,
    UpdateCredentials,
    AddCredentials,
    DeleteCredentials,

    GetUsers,
    UpdateUsers,
    AddUsers,
    DeleteUsers,

    GetGroups,
    UpdateGroups,
    AddGroups,
    DeleteGroups,

    pub const Info = struct { alias: ?[]const u8, description: []const u8, args: ?[]const u8 };

    /// Wire/display name — the tag itself ("GetHealth", ...).
    pub fn name(self: Command) []const u8 {
        return @tagName(self);
    }

    /// Per-command metadata, keyed by the enum. Exhaustive, adding a
    /// command without its metadata is a compile error.
    pub fn info(self: Command) Info {
        return switch (self) {
            .GetHealth => .{ .alias = "gh", .description = "Gets system health", .args = null },
            .GetLogs => .{ .alias = "gl", .description = "Gets system logs", .args = "beginDateTime=\"\" endDateTime=\"\"" },
            .GetMobileKey => .{ .alias = "gm", .description = "Gets mobile key", .args = "lockIds=[\"\"] phone=\"+\" beginDateTime=\"\" endDateTime=\"\"" },

            .GetDevices => .{ .alias = "gd", .description = "Get all devices", .args = null },
            .UpdateDevices => .{ .alias = "ud", .description = "Updates devices", .args = "devices=[{}]" },
            .AddDevices => .{ .alias = "ad", .description = "Add devices", .args = "devices=[{}]" },
            .DeleteDevices => .{ .alias = "dd", .description = "Delete devices", .args = "devices=[{}]" },

            .GetCredentials => .{ .alias = "gc", .description = "Get all credentials", .args = null },
            .UpdateCredentials => .{ .alias = "uc", .description = "Updates credentials", .args = "credentials=[{}] auth=\"\"" },
            .AddCredentials => .{ .alias = "ac", .description = "Add credentials", .args = "credentials=[{}] auth=\"\"" },
            .DeleteCredentials => .{ .alias = "dc", .description = "Delete credentials", .args = "credentials=[{}] auth=\"\"" },

            .GetUsers => .{ .alias = "gu", .description = "Get all users", .args = null },
            .UpdateUsers => .{ .alias = "uu", .description = "Update users", .args = "users=[{}]" },
            .AddUsers => .{ .alias = "au", .description = "Add users", .args = "users=[{}]" },
            .DeleteUsers => .{ .alias = "du", .description = "Delete users", .args = "users=[{}]" },

            .GetGroups => .{ .alias = "gg", .description = "Get all groups", .args = null },
            .UpdateGroups => .{ .alias = "ug", .description = "Update groups", .args = "groups=[{}]" },
            .AddGroups => .{ .alias = "ag", .description = "Add groups", .args = "groups=[{}]" },
            .DeleteGroups => .{ .alias = "dg", .description = "Delete groups", .args = "groups=[{}]" },
        };
    }
};

/// All commands — use as the Select's options list.
pub const all = std.enums.values(Command);

/// Resolves user input to a Command for autocomplete.
/// An exact `alias` match wins outright; otherwise returns the best
/// prefix match, either a command whose name starts with `str`, or the
/// command whose name is a prefix of `str` (full name + trailing args).
/// Ambiguous prefixes tie-break to the alphabetically smallest name.
/// Returns null on empty input or no match.
pub fn findMatch(str: []const u8) ?Command {
    if (str.len == 0) return null;

    var best: ?Command = null;
    for (all) |cmd| {
        const nm = @tagName(cmd);

        // Check if str starts with command name, or command starts with str
        if (nm.len >= str.len) {
            // str is shorter - check if command starts with str
            if (std.mem.eql(u8, nm[0..str.len], str)) {
                if (best == null or std.mem.lessThan(u8, nm, @tagName(best.?))) best = cmd;
            }
        } else if (str.len > nm.len) {
            // str is longer - check if str starts with command (followed by space)
            if (std.mem.eql(u8, str[0..nm.len], nm) and str[nm.len] == ' ') {
                if (best == null or std.mem.lessThan(u8, nm, @tagName(best.?))) best = cmd;
            }
        }

        // Check alias
        if (cmd.info().alias) |alias| {
            if (std.mem.eql(u8, str, alias)) return cmd;
        }
    }
    return best;
}
