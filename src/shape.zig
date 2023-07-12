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

pub const Colorize2Error = error {
    NotImplemented,
    bad_shape,
    bad_target,
    bad_color,
};

pub fn colorize2(
    shape: Shape2,
    target_topology: vk.PrimitiveTopology,
    color: union(enum) {
        Value: util.color.RGBAf,
        Array: []const util.color.RGBAf,
    },
    ator: Allocator,
) !Graphics.PrimitiveObject {
    // allocate
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
    if (n_indices < 0)
        return Colorize2Error.bad_shape;
    var res: Graphics.PrimitiveObject = undefined;
    res.vertices = try ator.alloc(Graphics.Vertex, @intCast(usize, n_vertices));
    errdefer ator.free(res.vertices);
    res.indices = try ator.alloc(Graphics.Index, @intCast(usize, n_indices));
    errdefer ator.free(res.indices);
    // fill
    switch (color) {
        .Value => |v| {
            switch (shape) {
                .disk => |d| {
                    switch (target_topology) {
                        .triangle_list => {
                            res.vertices[0].pos = d.center;
                            res.vertices[0].col = .{v.r, v.g, v.b};
                            for (res.vertices[1..], 0..) |*vx, i| {
                                vx.pos = .{
                                    d.center[0] + d.radius*cos(
                                        2.0 * pi * @intToFloat(f32, i) / @intToFloat(f32, res.vertices.len-1)
                                    ),
                                    d.center[1] + d.radius*sin(
                                        2.0 * pi * @intToFloat(f32, i) / @intToFloat(f32, res.vertices.len-1)
                                    ),
                                };
                                vx.col = .{v.r, v.g, v.b};
                            }
                            for (0..res.vertices.len-2) |i| {
                                res.indices[i*3] = 0;
                                res.indices[i*3 + 1] = @intCast(Graphics.Index, i+1);
                                res.indices[i*3 + 2] = @intCast(Graphics.Index, i+2);
                            }
                            const tail = res.vertices.len-2;
                            res.indices[tail*3] = 0;
                            res.indices[tail*3 + 1] = @intCast(Graphics.Index, tail+1);
                            res.indices[tail*3 + 2] = 1;
                        },
                        .triangle_strip => return Colorize2Error.NotImplemented,
                        .triangle_fan => {
                            res.vertices[0].pos = d.center;
                            res.vertices[0].col = .{v.r, v.g, v.b};
                            res.indices[0] = 0;
                            for (res.vertices[1..], 0..) |*vx, i| {
                                vx.pos = .{
                                    d.center[0] + d.radius*cos(
                                        2.0 * pi * @intToFloat(f32, i) / @intToFloat(f32, res.vertices.len-1)
                                    ),
                                    d.center[1] + d.radius*sin(
                                        2.0 * pi * @intToFloat(f32, i) / @intToFloat(f32, res.vertices.len-1)
                                    ),
                                };
                                vx.col = .{v.r, v.g, v.b};
                                res.indices[i] = @intCast(Graphics.Index, i);
                            }
                        },
                        else => unreachable,  // checked above
                    }
                },
                .triangle => |t| {
                    for (res.vertices, t, 0..) |*dst, pos, i| {
                        dst.pos = pos;
                        dst.col = .{v.r, v.g, v.b};
                        res.indices[i] = @intCast(Graphics.Index, i);
                    }
                },
                .polygon => |p| {
                    switch (target_topology) {
                        .triangle_list => {
                            switch (p.layout) {
                                .fan => {
                                    for (res.vertices, p.vertices) |*dst, pos| {
                                        dst.pos = pos;
                                        dst.col = .{v.r, v.g, v.b};
                                    }
                                    for (0..res.vertices.len-2) |i| {
                                        res.indices[i*3] = 0;
                                        res.indices[i*3 + 1] = @intCast(Graphics.Index, i+1);
                                        res.indices[i*3 + 2] = @intCast(Graphics.Index, i+2);
                                    }
                                    const tail = res.vertices.len-2;
                                    res.indices[tail*3] = 0;
                                    res.indices[tail*3 + 1] = @intCast(Graphics.Index, tail+1);
                                    res.indices[tail*3 + 2] = 1;
                                },
                                .strip => {
                                    for (res.vertices, p.vertices) |*dst, pos| {
                                        dst.pos = pos;
                                        dst.col = .{v.r, v.g, v.b};
                                    }
                                    for (0..res.vertices.len-2) |i| {
                                        res.indices[i*3] = @intCast(Graphics.Index, i);
                                        res.indices[i*3 + 1] = @intCast(Graphics.Index, i+1);
                                        res.indices[i*3 + 2] = @intCast(Graphics.Index, i+2);
                                    }
                                },
                            }
                        },
                        else => {
                            for (res.vertices, p.vertices, 0..) |*dst, pos, i| {
                                dst.pos = pos;
                                dst.col = .{v.r, v.g, v.b};
                                res.indices[i] = @intCast(Graphics.Index, i);
                            }
                        },
                    }
                },
            }
        },
        .Array => |a| {
            if (a.len != res.vertices.len) {
                return Colorize2Error.bad_color;
            }
            switch (shape) {
                .disk => |d| {
                    switch (target_topology) {
                        .triangle_list => {
                            res.vertices[0].pos = d.center;
                            res.vertices[0].col = .{a[0].r, a[0].g, a[0].b};
                            for (res.vertices[1..], 0..) |*vx, i| {
                                vx.pos = .{
                                    d.center[0] + d.radius*cos(
                                        2.0 * pi * @intToFloat(f32, i) / @intToFloat(f32, res.vertices.len-1)
                                    ),
                                    d.center[1] + d.radius*sin(
                                        2.0 * pi * @intToFloat(f32, i) / @intToFloat(f32, res.vertices.len-1)
                                    ),
                                };
                                vx.col = .{a[i+1].r, a[i+1].g, a[i+1].b};
                            }
                            for (0..res.vertices.len-2) |i| {
                                res.indices[i*3] = 0;
                                res.indices[i*3 + 1] = @intCast(Graphics.Index, i+1);
                                res.indices[i*3 + 2] = @intCast(Graphics.Index, i+2);
                            }
                            const tail = res.vertices.len-2;
                            res.indices[tail*3] = 0;
                            res.indices[tail*3 + 1] = @intCast(Graphics.Index, tail+1);
                            res.indices[tail*3 + 2] = 1;
                        },
                        .triangle_strip => return Colorize2Error.NotImplemented,
                        .triangle_fan => {
                            res.vertices[0].pos = d.center;
                            res.vertices[0].col = .{a[0].r, a[0].g, a[0].b};
                            res.indices[0] = 0;
                            for (res.vertices[1..], 0..) |*vx, i| {
                                vx.pos = .{
                                    d.center[0] + d.radius*cos(
                                        2.0 * pi * @intToFloat(f32, i) / @intToFloat(f32, res.vertices.len-1)
                                    ),
                                    d.center[1] + d.radius*sin(
                                        2.0 * pi * @intToFloat(f32, i) / @intToFloat(f32, res.vertices.len-1)
                                    ),
                                };
                                vx.col = .{a[i+1].r, a[i+1].g, a[i+1].b};
                                res.indices[i] = @intCast(Graphics.Index, i);
                            }
                        },
                        else => unreachable,  // checked above
                    }
                },
                .triangle => |t| {
                    for (res.vertices, t, a, 0..) |*dst, pos, col, i| {
                        dst.pos = pos;
                        dst.col = .{col.r, col.g, col.b};
                        res.indices[i] = @intCast(Graphics.Index, i);
                    }
                },
                .polygon => |p| {
                    switch (target_topology) {
                        .triangle_list => {
                            switch (p.layout) {
                                .fan => {
                                    for (res.vertices, p.vertices, a) |*dst, pos, col| {
                                        dst.pos = pos;
                                        dst.col = .{col.r, col.g, col.b};
                                    }
                                    for (0..res.vertices.len-2) |i| {
                                        res.indices[i*3] = 0;
                                        res.indices[i*3 + 1] = @intCast(Graphics.Index, i+1);
                                        res.indices[i*3 + 2] = @intCast(Graphics.Index, i+2);
                                    }
                                    const tail = res.vertices.len-2;
                                    res.indices[tail*3] = 0;
                                    res.indices[tail*3 + 1] = @intCast(Graphics.Index, tail+1);
                                    res.indices[tail*3 + 2] = 1;
                                },
                                .strip => {
                                    for (res.vertices, p.vertices, a) |*dst, pos, col| {
                                        dst.pos = pos;
                                        dst.col = .{col.r, col.g, col.b};
                                    }
                                    for (0..res.vertices.len-2) |i| {
                                        res.indices[i*3] = @intCast(Graphics.Index, i);
                                        res.indices[i*3 + 1] = @intCast(Graphics.Index, i+1);
                                        res.indices[i*3 + 2] = @intCast(Graphics.Index, i+2);
                                    }
                                },
                            }
                        },
                        else => {
                            for (res.vertices, p.vertices, a, 0..) |*dst, pos, col, i| {
                                dst.pos = pos;
                                dst.col = .{col.r, col.g, col.b};
                                res.indices[i] = @intCast(Graphics.Index, i);
                            }
                        },
                    }
                },
            }
        },
    }

    return res;
} // colorize2()
