pub const KeyResult = enum {
    consumed, // generic handled
    changed, // user finalized an editable value (e.g. Enter in TextInput) — mirrors the DOM change event
    ignored,
    focus_next,
    focus_prev,
    open_search,
    dive_in,
    dive_out,
};
