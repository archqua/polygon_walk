/// base class for widgets
const Widget = @This();

pub const Callback = *const fn (self: Widget, data: usize) void;
pressCallback: ?Callback = null,
moveCallback: ?Callback = null,
active: bool = false,


/// not sure if this is needed
const Error = error {
    callback_not_set,
};
