pub const color = @import("util/color.zig");

pub fn padSize(size: anytype, alignment: anytype) @TypeOf(size) {
    if (size > 0) {
        return (size + alignment - 1) & ~(alignment - 1);
    } else {
        return size;
    }
}
