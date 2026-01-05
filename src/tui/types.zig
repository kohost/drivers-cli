pub const Mode = enum { normal, command };
pub const Rect = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
};
pub const KeyResult = union(enum) {
    consumed,
    move_to: enum { up, down },
    unhandled,
};
