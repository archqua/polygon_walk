const std = @import("std");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");
const util = @import("util");
const alg = @import("alg.zig");
const Graphics = @import("graphics.zig");

const math = std.math;
const pi = math.pi;
const cos = math.cos;
const sin = math.sin;

pub const Point2 = alg.Vec2;

pub const Type2 = enum {
    disk, triangle, polygon,
};

pub const Shape2 = union(Type2) {
    disk: Disk2,
    triangle: Triangle2,
    polygon: Polygon2,
};

pub const Circle2 = struct {
    center: Point2,
    radius: f32,

    pub const n_sectors_approx = 64;
};
pub const Disk2 = Circle2;

pub const Triangle2 = [3]Point2;

pub const Polygon2 = struct {
    pub const Layout = enum {
        fan, strip,
    };

    layout: Layout,
    vertices: []Point2,
};

pub const Cpy2Error = error {
    shape_mismatch, polygon_mismatch,
};
pub fn cpy2(dst: *Shape2, src: Shape2) Cpy2Error!void {
    switch (dst.*) {
        .disk => {
            switch (src) {
                .disk => {
                    dst.* = src;
                },
                else => return Cpy2Error.shape_mismatch,
            }
        },
        .triangle => {
            switch (src) {
                .triangle => {
                    dst.* = src;
                },
                else => return Cpy2Error.shape_mismatch,
            }
        },
        .polygon => |dp| {
            switch (src) {
                .polygon => |sp| {
                    if (dp.vertices.len != sp.vertices.len)
                        return Cpy2Error.polygon_mismatch;
                    for (dp.vertices, sp.vertices) |*dv, sv| {
                        dv.* = sv;
                    }
                },
                else => return Cpy2Error.shape_mismatch,
            }
        },
    }
}

const VertexIndexCount = struct {
    n_vertices: i32,
    n_indices: i32,
};
fn getDrawableVertexIndexCount2(shape: Shape2, target_topology: vk.PrimitiveTopology) !VertexIndexCount {
    const n_vertices = switch (shape) {
        .disk => Circle2.n_sectors_approx + 1,
        .triangle => 3,
        .polygon => |p| @intCast(i32, p.vertices.len),
    };
    const n_indices = switch (shape) {
        .disk => switch (target_topology) {
            .triangle_list => n_vertices*3 - 3,
            .triangle_strip => return Colorize2Error.NotImplemented,
            .triangle_fan => n_vertices,
            else => return Colorize2Error.bad_target,
        },
        .triangle => 3,
        .polygon => |p| switch (target_topology) {
            .triangle_list => switch (p.layout) {
                .fan => n_vertices*3 - 3,
                .strip => n_vertices*3 - 6,
            },
            .triangle_strip => switch (p.layout) {
                .fan => return Colorize2Error.NotImplemented,
                .strip => n_vertices,
            },
            .triangle_fan => switch (p.layout) {
                .fan => n_vertices,
                .strip => return Colorize2Error.NotImplemented,
            },
            else => return Colorize2Error.bad_target,
        },
    };
    return .{
        .n_vertices = n_vertices,
        .n_indices  = n_indices,
    };
}

pub const Colorize2Error = error {
    NotImplemented,
    bad_shape,
    bad_target,
    bad_color,
    drawable_mismatch,
};

pub const ColorInfo = union(enum) {
    Value: util.color.RGBAf,
    Array: []const util.color.RGBAf,
};
pub fn colorizeInplace2(
    shape: Shape2,
    target_topology: vk.PrimitiveTopology,
    color: ColorInfo,
    drawable: Graphics.PrimitiveObject,
) !void {
    // check drawable size
    const vi_count = try getDrawableVertexIndexCount2(shape, target_topology);
    const n_vertices = vi_count.n_vertices;
    const n_indices = vi_count.n_indices;
    if (n_indices < 0)
        return Colorize2Error.bad_shape;
    if (@intCast(u32, n_vertices) != drawable.nVertices() or @intCast(u32, n_indices) != drawable.nIndices())
        return Colorize2Error.drawable_mismatch;

    // fill
    switch (color) {
        .Value => |v| {
            switch (shape) {
                .disk => |d| {
                    switch (target_topology) {
                        .triangle_list => {
                            drawable.vertices[0].pos = d.center;
                            drawable.vertices[0].col = .{v.r, v.g, v.b};
                            for (drawable.vertices[1..], 0..) |*vx, i| {
                                vx.pos = .{
                                    d.center[0] + d.radius*cos(
                                        2.0 * pi * @intToFloat(f32, i) / @intToFloat(f32, drawable.vertices.len-1)
                                    ),
                                    d.center[1] + d.radius*sin(
                                        2.0 * pi * @intToFloat(f32, i) / @intToFloat(f32, drawable.vertices.len-1)
                                    ),
                                };
                                vx.col = .{v.r, v.g, v.b};
                            }
                            for (0..drawable.vertices.len-2) |i| {
                                drawable.indices[i*3] = 0;
                                drawable.indices[i*3 + 1] = @intCast(Graphics.Index, i+1);
                                drawable.indices[i*3 + 2] = @intCast(Graphics.Index, i+2);
                            }
                            const tail = drawable.vertices.len-2;
                            drawable.indices[tail*3] = 0;
                            drawable.indices[tail*3 + 1] = @intCast(Graphics.Index, tail+1);
                            drawable.indices[tail*3 + 2] = 1;
                        },
                        .triangle_strip => return Colorize2Error.NotImplemented,
                        .triangle_fan => {
                            drawable.vertices[0].pos = d.center;
                            drawable.vertices[0].col = .{v.r, v.g, v.b};
                            drawable.indices[0] = 0;
                            for (drawable.vertices[1..], 0..) |*vx, i| {
                                vx.pos = .{
                                    d.center[0] + d.radius*cos(
                                        2.0 * pi * @intToFloat(f32, i) / @intToFloat(f32, drawable.vertices.len-1)
                                    ),
                                    d.center[1] + d.radius*sin(
                                        2.0 * pi * @intToFloat(f32, i) / @intToFloat(f32, drawable.vertices.len-1)
                                    ),
                                };
                                vx.col = .{v.r, v.g, v.b};
                                drawable.indices[i] = @intCast(Graphics.Index, i);
                            }
                        },
                        else => unreachable,  // checked above
                    }
                },
                .triangle => |t| {
                    for (drawable.vertices, t, 0..) |*dst, pos, i| {
                        dst.pos = pos;
                        dst.col = .{v.r, v.g, v.b};
                        drawable.indices[i] = @intCast(Graphics.Index, i);
                    }
                },
                .polygon => |p| {
                    switch (target_topology) {
                        .triangle_list => {
                            switch (p.layout) {
                                .fan => {
                                    for (drawable.vertices, p.vertices) |*dst, pos| {
                                        dst.pos = pos;
                                        dst.col = .{v.r, v.g, v.b};
                                    }
                                    for (0..drawable.vertices.len-2) |i| {
                                        drawable.indices[i*3] = 0;
                                        drawable.indices[i*3 + 1] = @intCast(Graphics.Index, i+1);
                                        drawable.indices[i*3 + 2] = @intCast(Graphics.Index, i+2);
                                    }
                                    const tail = drawable.vertices.len-2;
                                    drawable.indices[tail*3] = 0;
                                    drawable.indices[tail*3 + 1] = @intCast(Graphics.Index, tail+1);
                                    drawable.indices[tail*3 + 2] = 1;
                                },
                                .strip => {
                                    for (drawable.vertices, p.vertices) |*dst, pos| {
                                        dst.pos = pos;
                                        dst.col = .{v.r, v.g, v.b};
                                    }
                                    for (0..drawable.vertices.len-2) |i| {
                                        drawable.indices[i*3] = @intCast(Graphics.Index, i);
                                        drawable.indices[i*3 + 1] = @intCast(Graphics.Index, i+1);
                                        drawable.indices[i*3 + 2] = @intCast(Graphics.Index, i+2);
                                    }
                                },
                            }
                        },
                        else => {
                            for (drawable.vertices, p.vertices, 0..) |*dst, pos, i| {
                                dst.pos = pos;
                                dst.col = .{v.r, v.g, v.b};
                                drawable.indices[i] = @intCast(Graphics.Index, i);
                            }
                        },
                    }
                },
            }
        },
        .Array => |a| {
            if (a.len != drawable.vertices.len) {
                return Colorize2Error.bad_color;
            }
            switch (shape) {
                .disk => |d| {
                    switch (target_topology) {
                        .triangle_list => {
                            drawable.vertices[0].pos = d.center;
                            drawable.vertices[0].col = .{a[0].r, a[0].g, a[0].b};
                            for (drawable.vertices[1..], 0..) |*vx, i| {
                                vx.pos = .{
                                    d.center[0] + d.radius*cos(
                                        2.0 * pi * @intToFloat(f32, i) / @intToFloat(f32, drawable.vertices.len-1)
                                    ),
                                    d.center[1] + d.radius*sin(
                                        2.0 * pi * @intToFloat(f32, i) / @intToFloat(f32, drawable.vertices.len-1)
                                    ),
                                };
                                vx.col = .{a[i+1].r, a[i+1].g, a[i+1].b};
                            }
                            for (0..drawable.vertices.len-2) |i| {
                                drawable.indices[i*3] = 0;
                                drawable.indices[i*3 + 1] = @intCast(Graphics.Index, i+1);
                                drawable.indices[i*3 + 2] = @intCast(Graphics.Index, i+2);
                            }
                            const tail = drawable.vertices.len-2;
                            drawable.indices[tail*3] = 0;
                            drawable.indices[tail*3 + 1] = @intCast(Graphics.Index, tail+1);
                            drawable.indices[tail*3 + 2] = 1;
                        },
                        .triangle_strip => return Colorize2Error.NotImplemented,
                        .triangle_fan => {
                            drawable.vertices[0].pos = d.center;
                            drawable.vertices[0].col = .{a[0].r, a[0].g, a[0].b};
                            drawable.indices[0] = 0;
                            for (drawable.vertices[1..], 0..) |*vx, i| {
                                vx.pos = .{
                                    d.center[0] + d.radius*cos(
                                        2.0 * pi * @intToFloat(f32, i) / @intToFloat(f32, drawable.vertices.len-1)
                                    ),
                                    d.center[1] + d.radius*sin(
                                        2.0 * pi * @intToFloat(f32, i) / @intToFloat(f32, drawable.vertices.len-1)
                                    ),
                                };
                                vx.col = .{a[i+1].r, a[i+1].g, a[i+1].b};
                                drawable.indices[i] = @intCast(Graphics.Index, i);
                            }
                        },
                        else => unreachable,  // checked above
                    }
                },
                .triangle => |t| {
                    for (drawable.vertices, t, a, 0..) |*dst, pos, col, i| {
                        dst.pos = pos;
                        dst.col = .{col.r, col.g, col.b};
                        drawable.indices[i] = @intCast(Graphics.Index, i);
                    }
                },
                .polygon => |p| {
                    switch (target_topology) {
                        .triangle_list => {
                            switch (p.layout) {
                                .fan => {
                                    for (drawable.vertices, p.vertices, a) |*dst, pos, col| {
                                        dst.pos = pos;
                                        dst.col = .{col.r, col.g, col.b};
                                    }
                                    for (0..drawable.vertices.len-2) |i| {
                                        drawable.indices[i*3] = 0;
                                        drawable.indices[i*3 + 1] = @intCast(Graphics.Index, i+1);
                                        drawable.indices[i*3 + 2] = @intCast(Graphics.Index, i+2);
                                    }
                                    const tail = drawable.vertices.len-2;
                                    drawable.indices[tail*3] = 0;
                                    drawable.indices[tail*3 + 1] = @intCast(Graphics.Index, tail+1);
                                    drawable.indices[tail*3 + 2] = 1;
                                },
                                .strip => {
                                    for (drawable.vertices, p.vertices, a) |*dst, pos, col| {
                                        dst.pos = pos;
                                        dst.col = .{col.r, col.g, col.b};
                                    }
                                    for (0..drawable.vertices.len-2) |i| {
                                        drawable.indices[i*3] = @intCast(Graphics.Index, i);
                                        drawable.indices[i*3 + 1] = @intCast(Graphics.Index, i+1);
                                        drawable.indices[i*3 + 2] = @intCast(Graphics.Index, i+2);
                                    }
                                },
                            }
                        },
                        else => {
                            for (drawable.vertices, p.vertices, a, 0..) |*dst, pos, col, i| {
                                dst.pos = pos;
                                dst.col = .{col.r, col.g, col.b};
                                drawable.indices[i] = @intCast(Graphics.Index, i);
                            }
                        },
                    }
                },
            }
        },
    }
}
pub fn colorize2(
    shape: Shape2,
    target_topology: vk.PrimitiveTopology,
    color: ColorInfo,
    ator: Allocator,
) !Graphics.PrimitiveObject {
    // allocate
    const vi_count = try getDrawableVertexIndexCount2(shape, target_topology);
    const n_vertices = vi_count.n_vertices;
    const n_indices = vi_count.n_indices;
    if (n_indices < 0)
        return Colorize2Error.bad_shape;
    var res: Graphics.PrimitiveObject = undefined;
    res.vertices = try ator.alloc(Graphics.Vertex, @intCast(usize, n_vertices));
    errdefer ator.free(res.vertices);
    res.indices = try ator.alloc(Graphics.Index, @intCast(usize, n_indices));
    errdefer ator.free(res.indices);

    // fill
    try colorizeInplace2(shape, target_topology, color, res);
    return res;
} // colorize2()

pub const TransformType2 = enum {
    translation,
    rotation,
    scaling,
};
pub const Transform2 = union(TransformType2) {
    translation: Translation2,
    rotation: Rotation2,
    scaling: Scaling2,
};
pub const Translation2 = alg.Vec2;
pub const Rotation2 = f32;
pub const Scaling2 = alg.Vec2;

pub fn inverse2(fwd: Transform2) Transform2 {
    return switch (fwd) {
        .translation => |t| .{ .translation = alg.scale(t, -1.0) },
        .rotation => |r| .{ .rotation = -r },
        .scaling => |s| .{ .scaling = .{ 1.0 / s[0], 1.0 / s[1] } },
    };
}
pub const TransformError2 = error {
    non_uniform_disk_scaling,
};
pub fn apply2(transform: Transform2, shape: *Shape2) TransformError2!void {
    switch (transform) {
        .translation => |t| {
            switch (shape.*) {
                .disk => |*d| {
                    alg.addInplace(&d.center, t);
                },
                .triangle => |*tri| {
                    for (tri) |*dst| {
                        alg.addInplace(dst, t);
                    }
                },
                .polygon => |p| {
                    for (p.vertices) |*dst| {
                        alg.addInplace(dst, t);
                    }
                },
            }
        },
        .rotation => |r| {
            switch (shape.*) {
                .disk => {},
                .triangle => |*tri| {
                    const s = @sin(r);
                    const c = @cos(r);
                    // std.debug.print("rotating triangle for {}\n", .{r});
                    for (tri) |*point| {
                        // is this UB?
                        // point.* = .{ c*point[0] + s*point[1], -s*point[0] + c*point[1] };
                        const x = point.*;
                        point.* = .{c*x[0] + s*x[1], -s*x[0] + c*x[1]};
                    }
                },
                .polygon => |p| {
                    const s = @sin(r);
                    const c = @cos(r);
                    for (p.vertices) |*point| {
                        point.* = .{ c*point[0] + s*point[1], -s*point[0] + c*point[1] };
                    }
                },
            }
        },
        .scaling => |s| {
            switch (shape.*) {
                .disk => |*d| {
                    if (@fabs(s[0] - s[1]) > 1e-04) {
                        return TransformError2.non_uniform_disk_scaling;
                    }
                    alg.scaleInplace(&d.center, s[0]);
                    d.radius *= s[0];
                },
                .triangle => |*tri| {
                    for (tri) |*point| {
                        point[0] *= s[0];
                        point[1] *= s[1];
                    }
                },
                .polygon => |p| {
                    for (p.vertices) |*point| {
                        point[0] *= s[0];
                        point[1] *= s[1];
                    }
                },
            }
        },
    }
}
