pub const Alert = struct {
    type: Type,
    status: Status,
    message: []const u8,

    pub const Type = enum { battery, communication, config, door_ajar, equipment, temperature, maintenance, cost, registration };

    pub const Status = enum { active, resolved };
};
