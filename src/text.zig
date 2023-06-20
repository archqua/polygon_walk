const std = @import("std");
const Allocator = std.mem.Allocator;

const Graphics = @import("graphics.zig");
const Color = @import("util").Color;

pub const Letter = struct {
    ///
    vertices: []const [2]f32,
    ///
    indices: []const u8,

    pub fn fromCode(_code: u8) !Letter {
        return switch (_code) {
            'a', 'A' => A,
            'b', 'B' => B,
            'c', 'C' => C,
            'd', 'D' => D,
            'e', 'E' => E,
            'f', 'F' => F,
            'g', 'G' => G,
            'h', 'H' => H,
            'i', 'I' => I,
            'j', 'J' => J,
            'k', 'K' => K,
            'l', 'L' => L,
            'm', 'M' => M,
            'n', 'N' => N,
            'o', 'O' => O,
            'p', 'P' => P,
            'q', 'Q' => Q,
            'r', 'R' => R,
            's', 'S' => S,
            't', 'T' => T,
            'u', 'U' => U,
            'v', 'V' => V,
            'w', 'W' => W,
            'x', 'X' => X,
            'y', 'Y' => Y,
            'z', 'Z' => Z,
            ' '      => space,
            else => error.InvalidCharCode,
        };
    }

    pub const A = Letter{
        .vertices = &[_][2]f32{
            .{-0.5,  0.0},
            .{ 0.0,  1.0},
            .{ 0.5,  0.0},
            .{-1.0, -1.0},
            .{ 0.0, -1.0},
            .{ 1.0, -1.0},
        },
        .indices = &[_]u8{
            0, 1, 2,
            3, 0, 4,
            4, 2, 5,
        },
    };
    pub const B = Letter{
        .vertices = &[_][2]f32{
            .{-1.0,  0.0},
            .{-1.0,  1.0},
            .{ 1.0,  0.5},
            .{ 1.0, -0.5},
            .{-1.0, -1.0},
        },
        .indices = &[_]u8{
            0, 1, 2,
            0, 3, 4,
        },
    };
    pub const C = Letter{
        .vertices = &[_][2]f32{
            .{-1.0,  1.0},
            .{ 1.0,  1.0},
            .{ 1.0,  0.5},
            .{-1.0, -1.0},
            .{-0.2, -1.0},
            .{ 1.0, -0.5},
            .{ 1.0, -1.0},
        },
        .indices = &[_]u8{
            0, 1, 2,
            0, 4, 3,
            4, 5, 6,
        },
    };
    pub const D = Letter{
        .vertices = &[_][2]f32{
            .{-1.0,  1.0},
            .{ 1.0,  0.0},
            .{-1.0, -1.0},
        },
        .indices = &[_]u8{
            0, 1, 2,
        },
    };
    pub const E = Letter{
        .vertices = &[_][2]f32{
            .{-1.0,  1.0},
            .{ 1.0,  1.0},
            .{ 1.0,  0.5},
            .{ 0.2,  0.0},
            .{-1.0, -1.0},
            .{ 1.0, -0.5},
            .{ 1.0, -1.0},
        },
        .indices = &[_]u8{
            0, 1, 2,
            0, 3, 4,
            4, 5, 6,
        },
    };
    pub const F = Letter{
        .vertices = &[_][2]f32{
            .{-1.0,  1.0},
            .{ 1.0,  1.0},
            .{ 1.0,  0.5},
            .{ 0.2,  0.0},
            .{-1.0, -1.0},
        },
        .indices = &[_]u8{
            0, 1, 2,
            0, 3, 4,
        },
    };
    pub const G = Letter{
        .vertices = &[_][2]f32{
            .{-1.0,  1.0},
            .{ 1.0,  1.0},
            .{ 1.0,  0.5},
            .{-1.0, -1.0},
            .{-0.2, -1.0},
            .{ 1.0, -0.5},
            .{ 1.0, -1.0},
            .{ 0.2,  0.0},
            .{ 1.0,  0.0},
        },
        .indices = &[_]u8{
            0, 1, 2,
            0, 4, 3,
            4, 5, 6,
            5, 7, 8,
        },
    };
    pub const H = Letter{
        // X-like
        .vertices = &[_][2]f32{
            .{-1.0,  1.0},
            .{ 0.0,  0.0},
            .{-1.0, -1.0},
            .{ 1.0,  1.0},
            .{ 1.0, -1.0},
        },
        .indices = &[_]u8{
            0, 1, 2,
            1, 3, 4,
        },
        // not X-like
        // .vertices = &[_][2]f32{
        //     .{-1.0,  1.0},
        //     .{-0.2,  1.0},
        //     .{-1.0,  0.0},
        //     .{-0.2, -1.0},
        //     .{-1.0, -1.0},
        //     .{ 1.0,  0.25},
        //     .{ 1.0, -0.25},
        //     .{ 0.2,  1.0},
        //     .{ 1.0,  1.0},
        //     .{ 1.0, -1.0},
        //     .{ 0.2, -1.0},
        // },
        // .indices = &[_]u8{
        //     0, 1, 2,
        //     2, 3, 4,
        //     2, 5, 6,
        //     5, 7, 8,
        //     6, 9, 10,
        // },
    };
    pub const I = Letter{
        .vertices = &[_][2]f32{
            .{-0.37,  1.0},
            .{ 0.37,  1.0},
            .{ 0.0,   0.5},
            .{ 0.37, -1.0},
            .{-0.37, -1.0},
        },
        .indices = &[_]u8{
            0, 1, 2,
            2, 3, 4,
        },
    };
    pub const J = Letter{
        .vertices = &[_][2]f32{
            .{-1.0,  1.0},
            .{ 1.0,  1.0},
            .{ 0.4,  0.5},
            .{ 0.4, -1.0},
            .{-0.2, -1.0},
            .{-0.8, -1.0},
            .{-0.8, -0.5},
        },
        .indices = &[_]u8{
            0, 1, 2,
            2, 3, 4,
            4, 5, 6,
        },
    };
    pub const K = Letter{
        .vertices = &[_][2]f32{
            .{-1.0,  1.0},
            .{-0.2,  1.0},
            .{-1.0,  0.0},
            .{-0.2, -1.0},
            .{-1.0, -1.0},
            .{ 1.0,  0.5},
            .{ 1.0,  1.0},
            .{ 1.0, -1.0},
            .{ 1.0, -0.5},
        },
        .indices = &[_]u8{
            0, 1, 2,
            2, 3, 4,
            2, 5, 6,
            2, 7, 8,
        },
    };
    pub const L = Letter{
        .vertices = &[_][2]f32{
            .{-1.0,  1.0},
            .{-0.2,  1.0},
            .{-1.0, -1.0},
            .{ 1.0, -1.0},
            .{ 1.0, -0.5},
        },
        .indices = &[_]u8{
            0, 1, 2,
            2, 3, 4,
        },
    };
    pub const M = Letter{
        .vertices = &[_][2]f32{
            .{-1.0, -1.0},
            .{-1.0,  1.0},
            .{-0.4, -1.0},
            .{ 1.0,  1.0},
            .{ 0.0,  0.0},
            .{ 1.0, -1.0},
            .{ 0.4, -1.0},
        },
        .indices = &[_]u8{
            0, 1, 2,
            1, 3, 4,
            3, 5, 6,
        },
    };
    pub const N = Letter{
        .vertices = &[_][2]f32{
            .{-1.0,  1.0},
            .{ 0.0, -1.0},
            .{-1.0, -1.0},
            .{ 0.0,  1.0},
            .{ 1.0,  1.0},
            .{ 1.0, -1.0},
        },
        .indices = &[_]u8{
            0, 1, 2,
            3, 4, 5,
        },
    };
    pub const O = Letter{
        .vertices = &[_][2]f32{
            .{-0.2,  1.0},
            .{ 1.0,  1.0},
            .{ 1.0,  0.5},
            .{ 1.0, -1.0},
            .{ 0.2, -1.0},
            .{-1.0, -1.0},
            .{-1.0, -0.5},
            .{-1.0,  1.0},
        },
        .indices = &[_]u8{
            0, 1, 2,
            2, 3, 4,
            4, 5, 6,
            6, 7, 0,
        },
    };
    pub const P = Letter{
        .vertices = &[_][2]f32{
            .{-1.0,  1.0},
            .{ 1.0,  0.5},
            .{-1.0,  0.0},
            .{-0.2, -1.0},
            .{-1.0, -1.0},
        },
        .indices = &[_]u8{
            0, 1, 2,
            2, 3, 4,
        },
    };
    pub const Q = Letter{
        .vertices = &[_][2]f32{
            .{-0.2,  1.0},
            .{ 1.0,  1.0},
            .{ 1.0,  0.5},
            .{ 0.6, -0.75},
            .{-0.2, -1.0},
            .{-1.0, -1.0},
            .{-1.0, -0.5},
            .{-1.0,  1.0},
            .{ 0.0,  0.0},
            .{ 1.0, -1.0},
            .{ 0.6, -1.0}
        },
        .indices = &[_]u8{
            0, 1, 2,
            2, 3, 4,
            4, 5, 6,
            6, 7, 0,
            8, 9, 10,
        },
    };
    pub const R = Letter{
        .vertices = &[_][2]f32{
            .{-1.0,  1.0},
            .{ 1.0,  0.5},
            .{-1.0,  0.0},
            .{ 1.0, -0.5},
            .{ 1.0, -1.0},
            .{-0.2, -1.0},
            .{-1.0, -1.0},
        },
        .indices = &[_]u8{
            0, 1, 2,
            2, 3, 4,
            2, 5, 6,
        },
    };
    pub const S = Letter{
        .vertices = &[_][2]f32{
            .{ 1.0,  1.0},
            .{ 1.0,  0.5},
            .{-1.0,  1.0},
            .{ 0.6,  0.0},
            .{-0.6,  0.0},
            .{ 1.0, -1.0},
            .{-1.0, -1.0},
            .{-1.0, -0.5},
        },
        .indices = &[_]u8{
            0, 1, 2,
            2, 3, 4,
            3, 5, 4,
            5, 6, 7,
        },
    };
    pub const T = Letter{
        .vertices = &[_][2]f32{
            .{-1.0,  1.0},
            .{ 1.0,  1.0},
            .{ 0.0,  0.625},
            .{ 0.4, -1.0},
            .{-0.4, -1.0},
        },
        .indices = &[_]u8{
            0, 1, 2,
            2, 3, 4,
        },
    };
    pub const U = Letter{
        .vertices = &[_][2]f32{
            .{-1.0,  1.0},
            .{-0.4,  1.0},
            .{-1.0, -1.0},
            .{ 1.0, -0.5},
            .{ 1.0, -1.0},
            .{ 0.4,  1.0},
            .{ 1.0,  1.0},
        },
        .indices = &[_]u8{
            0, 1, 2,
            2, 3, 4,
            3, 5, 6,
        },
    };
    pub const V = Letter{
        // .vertices = &[_][2]f32{
        //     .{-1.0,  1.0},
        //     .{-0.6,  1.0},
        //     .{ 0.0, -1.0},
        //     .{-1.0,  0.5},
        //     .{ 0.6,  1.0},
        //     .{ 1.0,  1.0},
        //     .{ 1.0,  0.5},
        // },
        // .indices = &[_]u8{
        //     0, 1, 2,
        //     0, 2, 3,
        //     2, 4, 5,
        //     2, 5, 6,
        // },
        .vertices = &[_][2]f32{
            .{-1.0,  1.0},
            .{-0.4,  1.0},
            .{ 0.0, -1.0},
            .{ 0.4,  1.0},
            .{ 1.0,  1.0},
        },
        .indices = &[_]u8{
            0, 1, 2,
            2, 3, 4,
        },
    };
    pub const W = Letter{
        .vertices = &[_][2]f32{
            .{-1.0,  1.0},
            .{-0.4,  1.0},
            .{-1.0, -1.0},
            .{ 0.0,  0.0},
            .{ 1.0, -1.0},
            .{ 0.4,  1.0},
            .{ 1.0,  1.0},
        },
        .indices = &[_]u8{
            0, 1, 2,
            2, 3, 4,
            4, 5, 6,
        },
    };
    pub const X = Letter{
        // vent-like
        .vertices = &[_][2]f32{
            .{ 0.0,  0.0},
            .{-1.0,  1.0},
            .{-0.4,  1.0},
            .{ 1.0,  1.0},
            .{ 1.0,  0.5},
            .{ 1.0, -1.0},
            .{ 0.4, -1.0},
            .{-1.0, -1.0},
            .{-1.0, -0.5},
        },
        // chromosome-like
        // .vertices = &[_][2]f32{
        //     .{ 0.0,  0.0},
        //     .{-1.0,  1.0},
        //     .{-0.4,  1.0},
        //     .{ 0.4,  1.0},
        //     .{ 1.0,  1.0},
        //     .{-1.0, -1.0},
        //     .{-0.4, -1.0},
        //     .{ 0.4, -1.0},
        //     .{ 1.0, -1.0},
        // },
        .indices = &[_]u8{
            0, 1, 2,
            0, 3, 4,
            0, 5, 6,
            0, 7, 8,
        },
    };
    pub const Y = Letter{
        .vertices = &[_][2]f32{
            .{ 0.0,  0.0},

            // vent-like
            .{-1.0,  0.5},
            .{-1.0,  1.0},
            // chormosome-like
            // .{-0.4,  1.0},
            // .{-1.0,  1.0},

            .{ 0.4,  1.0},
            .{ 1.0,  1.0},
            .{-0.4, -1.0},
            .{-1.0, -1.0},
        },
        .indices = &[_]u8{
            0, 1, 2,
            0, 3, 4,
            0, 5, 6,
        },
    };
    pub const Z = Letter{
        .vertices = &[_][2]f32{
            .{-1.0,  0.5},
            .{-1.0,  1.0},
            .{ 1.0,  1.0},
            .{ 0.0,  0.0},
            .{-0.6,  0.15},
            .{ 0.6, -0.15},
            .{-1.0, -1.0},
            .{ 1.0, -0.5},
            .{ 1.0, -1.0},
        },
        .indices = &[_]u8{
            0, 1, 2,
            2, 3, 4,
            3, 5, 6,
            6, 7, 8,
        },
    };
    pub const space = Letter{
        .vertices = &[_][2]f32{},
        .indices = &[_]u8{},
    };
};

pub const String = []const Letter;
pub fn stringFromChars(chars: []const u8, ator: Allocator) !String {
    const letters = try ator.alloc(Letter, chars.len);
    errdefer ator.free(letters);
    for (letters, chars) |*letter, char| {
        letter.* = try Letter.fromCode(char);
    }
    return letters;
}
pub const Scale = struct {
    x: ?f32 = null,  // null defaults ot .y * 5/8
    y: ?f32 = 1.0,  // null defaults to .x * 8/5
    flipy: bool = false,
    pub fn scalex(self: Scale) f32 {
        if (self.x) |sx|
            return sx
        else
            return (self.y orelse 1.0) * 0.625;
    }
    pub fn scaley(self: Scale) f32 {
        if (self.y) |sy|
            return if (self.flipy) -sy else sy
        else
            return if (self.flipy) -self.scalex() * 1.6 else self.scalex() * 1.6;
    }
};
pub const Offset = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
};
pub fn string2drawable(
    string: String, color: Color.RGBAf,
    offset: Offset, scale: Scale,
    ator: Allocator,
) !Graphics.PrimitiveObject {
    const scalex = scale.scalex();
    const scaley = scale.scaley();
    const charwidth = 2.4*scalex;
    var info = Graphics.DrawableInfo{ .n_vertices = 0, .n_indices = 0 };
    for (string) |letter| {
        info.n_vertices += @intCast(u32, letter.vertices.len);
        info.n_indices += @intCast(u32, letter.indices.len);
    }
    var drawable: Graphics.PrimitiveObject = undefined;
    drawable.vertices = try ator.alloc(Graphics.Vertex, info.n_vertices);
    errdefer ator.free(drawable.vertices);
    drawable.indices = try ator.alloc(Graphics.Index, info.n_indices);
    errdefer ator.free(drawable.indices);

    var vertex_counter: u32 = 0;
    var index_counter: u32 = 0;
    for (string, 0..) |letter, letter_counter| {
        for (letter.indices, 0..) |l_index, i| {
            drawable.indices[index_counter + i] =
                @intCast(Graphics.Index, l_index + vertex_counter);
        }
        index_counter += @intCast(u32, letter.indices.len);
        for (letter.vertices) |l_vertex| {
            drawable.vertices[vertex_counter] = .{
                .pos = .{
                    offset.x + scalex*l_vertex[0] + @intToFloat(f32, letter_counter)*charwidth,
                    offset.y + scaley*l_vertex[1],
                },
                .col = .{color.r, color.g, color.b},
            };
            vertex_counter += 1;
        }
    }

    return drawable;
}
