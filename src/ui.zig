const std = @import("std");
const Allocator = std.mem.Allocator;
const math = std.math;

const Graphics = @import("graphics.zig");
const text = @import("text.zig");
const Color = @import("util").Color;

pub const Offset = text.Offset; // struct {
//     x: f32 = 0.0,
//     y: f32 = 0.0,
// };
pub const Shape = struct {
    width: f32 = 1.0,
    height: f32 = 1.0,
};
pub const Rect = struct {
    offset: Offset = .{},
    shape: Shape = .{},
};
pub const Margins = struct {
    top: f32 = 0.0,
    left: f32 = 0.0,
};

pub const Button = struct {
    bg_color: Color.RGBAf,
    txt_color: Color.RGBAf = Color.RGBAf.black,
    text: []const u8,
    _width: ?f32 = null,
    _height: ?f32 = null,
    text_scale: f32 = 1.0,
    margins: Margins = .{},

    pub fn naturalWidth(self: Button) f32 {
        const scale = text.Scale{.y = self.text_scale, .flipy=true};
        const scalex = scale.scalex();
        return 2.0*scalex*(1.0 + self.margins.left) +
            2.4*scalex*@intToFloat(f32, self.text.len-1);
    }
    pub fn naturalHeight(self: Button) f32 {
        const scale = text.Scale{.y = self.text_scale, .flipy=true};
        const scaley = -scale.scaley();
        return 2.0*scaley*(1.0 + self.margins.top);
    }
    pub fn width(self: Button) f32 {
        return self._width orelse self.naturalWidth();
    }
    pub fn height(self: Button) f32 {
        return self._height orelse self.naturalHeight();
    }

    pub fn drawables(self: *const Button, offset: Offset, ator: Allocator) ![2]Graphics.PrimitiveObject {
        const scale = text.Scale{.y = self.text_scale, .flipy=true};
        const scalex = scale.scalex();
        const scaley = -scale.scaley();
        const width_ = self.width();
        const height_ = self.height();

        const string = try text.stringFromChars(self.text, ator);
        defer ator.free(string);
        const string_offset = Offset{
            .x = offset.x + scalex*(1.0 + self.margins.left),
            .y = offset.y + scaley*(1.0 + self.margins.top),
        };
        const s_drawable = try text.string2drawable(
            string, self.txt_color,
            string_offset,
            scale,
            ator,
        );
        errdefer ator.free(s_drawable.vertices);
        errdefer ator.free(s_drawable.indices);

        const bg_vertices = try ator.alloc(Graphics.Vertex, 4);
        errdefer ator.free(bg_vertices);
        const bg_indices = try ator.alloc(Graphics.Index, 6);
        errdefer ator.free(bg_indices);
        bg_vertices[0] = .{
            .pos = .{offset.x, offset.y},
            .col = .{self.bg_color.r, self.bg_color.g, self.bg_color.b},
        };
        bg_vertices[1] = .{
            .pos = .{width_ + offset.x, offset.y},
            .col = .{self.bg_color.r, self.bg_color.g, self.bg_color.b},
        };
        bg_vertices[2] = .{
            .pos = .{width_ + offset.x, height_ + offset.y},
            .col = .{self.bg_color.r, self.bg_color.g, self.bg_color.b},
        };
        bg_vertices[3] = .{
            .pos = .{offset.x, height_ + offset.y},
            .col = .{self.bg_color.r, self.bg_color.g, self.bg_color.b},
        };
        bg_indices[0] = 0;
        bg_indices[1] = 1;
        bg_indices[2] = 3;
        bg_indices[3] = 1;
        bg_indices[4] = 2;
        bg_indices[5] = 3;
        const bg_drawable = Graphics.PrimitiveObject{
            .vertices=bg_vertices, .indices=bg_indices,
        };

        return .{bg_drawable, s_drawable};
    }
};

pub const Menu = struct {
    buttons: []Button,
    interval: f32 = 0.0,

    pub const Alignment = enum {
        left, center, right,
    };

    pub fn drawables(
        self: *const Menu,
        alignment: Alignment, offset: Offset,
        ator: Allocator,
    ) ![2]Graphics.PrimitiveCollection {
        var accum_height: f32 = 0.0;
        var res = [2]Graphics.PrimitiveCollection{.{}, .{}};
        errdefer {
            for (&res) |*r| {
                while (r.popFirst()) |node| {
                    ator.free(node.data.indices);
                    ator.free(node.data.vertices);
                }
            }
        }

        for (self.buttons) |b| {
            const b_width = b.width();
            const b_height = b.height();
            const b_offset = .{
                .x = switch (alignment) {
                    .left => offset.x,
                    .center => offset.x - 0.5*b_width,
                    .right => offset.x - b_width,
                },
                .y = offset.y + accum_height,
            };
            accum_height += b_height + self.interval;
            const b_obj = try b.drawables(b_offset, ator);
            errdefer {
                for (b_obj) |bo| {
                    ator.free(bo.indices);
                    ator.free(bo.vertices);
                }
            }
            for (b_obj, 0..) |bo, i| {
                const node = try ator.create(Graphics.PrimitiveCollection.Node);
                node.data = bo;
                res[i].prepend(node);
            }
        }

        return res;
    }
};
