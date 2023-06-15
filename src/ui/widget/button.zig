/// Button class
const Button = @This();

const std = @import("std");
const Widget = @import("widget.zig");
// const Color = @import("../../util/color.zig");
const Color = @import("util").Color;
const RGBA = Color.RGBAi;

pub const Pos = struct {
    x: f32, y: f32,
};
pub const Shape = struct {
    width: f32, height: f32,
};

widget: Widget, // stores callbacks
pos: Pos,
shape: Shape,
/// these are set manually after init() call
bg_color: RGBA = RGBA.grey,
txt_color: RGBA = RGBA.black,
text: [:0]const u8 = "",

pub const Config = blk: {
    comptime var retType = std.builtin.Type{.Struct = .{  // should @import("builtin") be used here?
        .layout = .Auto,
        .fields = undefined,
        .decls = &.{},
        .is_tuple = false,
    }};
    const widget_fields = @typeInfo(Widget).Struct.fields;
    comptime var config_fields = [1]std.builtin.Type.StructField{undefined} ** (widget_fields.len + 2);
    // copy widget fields
    inline for (widget_fields, 0..) |field, i| {
        config_fields[i] = field;
    }
    // set button-specific fields
    config_fields[widget_fields.len] = std.builtin.Type.StructField{
        .name = "bg_color",
        .type = RGBA,
        .default_value = &RGBA.grey,
        .is_comptime = false,
        .alignment = @alignOf(RGBA),
    };
    config_fields[widget_fields.len + 1] = std.builtin.Type.StructField{
        .name = "txt_color",
        .type = RGBA,
        .default_value = &RGBA.black,
        .is_comptime = false,
        .alignment = @alignOf(RGBA),
    };
    retType.Struct.fields = &config_fields;

    break :blk @Type(retType);
};

/// order of specification in init() is more natural than order of declaration/(presumed) storage
pub fn init(pos: Pos, shape: Shape, text: [:0]const u8, cfg: Config) Button {
    var res = Button{
        .widget = undefined,
        .pos = pos,
        .shape = shape,
        .text = text,
        // .bg_color = cfg.bg_color,
        // .txt_color = cfg.txt_color,
    };
    // inline for (@typeInfo(Widget).Struct.fields) |field| {
    //     @field(res.widget, field.name) = @field(cfg, field.name);
    // }
    inline for (@typeInfo(Config).Struct.fields) |field| {
        if (@hasField(Widget, field.name)) {
            @field(res.widget, field.name) = @field(cfg, field.name);
        } else {
            @field(res, field.name) = @field(cfg, field.name);
        }
    }
    return res;
}

