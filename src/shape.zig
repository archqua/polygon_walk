const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
pub const debug = switch (builtin.mode) {
    .Debug, .ReleaseSafe => true,
    else => false,
};

const vk = @import("vulkan");
const util = @import("util");
const alg = @import("alg.zig");
const Graphics = @import("graphics.zig");

const math = std.math;
const pi = math.pi;
const cos = math.cos;
const sin = math.sin;

pub const Vector2 = alg.Vec2;
pub const Point2 = alg.Vec2;
pub const Segment2 = [2]Point2;

pub fn segmentVector2(segment: Segment2) Vector2 {
    return alg.sub(segment[1], segment[0]);
}
pub fn segmentUnitVector2(segment: Segment2) Vector2 {
    return alg.unitize(segmentVector2(segment));
}
pub fn segmentNormal2(segment: Segment2) Vector2 {
    const v = segmentVector2(segment);
    return .{-v[1], v[0]};
}
pub fn segmentUnitNormal2(segment: Segment2) Vector2 {
    return alg.unitize(segmentNormal2(segment));
}

pub const Box2 = struct {
    /// left-bottom
    lb: Point2,
    /// right-top
    rt: Point2,

    pub fn intersects(self: Box2, other: Box2) bool {
        return (self.lb[0] <= other.rt[0]
            and self.lb[1] <= other.rt[1]
            and self.rt[0] >= other.lb[0]
            and self.rt[1] >= other.lb[1]
        );
    }
    pub fn isInsideOf(self: Box2, other: Box2) bool {
        return (self.lb[0] >= other.lb[0]
            and self.lb[1] >= other.lb[1] 
            and self.rt[0] <= other.rt[0]
            and self.rt[1] <= other.rt[1]
        );
    }
    pub fn span(self: Box2, other: Box2) Box2 {
        return .{
            .lb = .{@min(self.lb[0], other.lb[0]), @min(self.lb[1], other.lb[1])},
            .rt = .{@max(self.rt[0], other.rt[0]), @max(self.rt[1], other.rt[1])},
        };
    }
    // TODO more efficient implementation???
    pub fn spanMultiple(boxes: []const Box2) ?Box2 {
        if (boxes.len < 1)
            return null;
        var res = boxes[0];
        for (boxes[1..]) |box| {
            res = res.span(box);
        }
        return res;
    }

    pub fn perimeter(self: Box2) f32 {
        return 2.0 * (self.rt[0] - self.lb[0] + self.rt[1] - self.rt[1]);
    }
};
pub const Feature2 = union(enum) {
    Vertex: Vertex,
    Edge: Segment2,

    pub const Vertex = struct {
        prev: ?Point2,
        this: Point2,
        next: ?Point2,
    };
};
pub fn distToSegmentSubspace2(segment: Segment2, point: Point2) f32 {
    return @fabs(signedDistToSegmentSubspace2(segment, point));
}
/// outside of positively oriented shape is positive
pub fn signedDistToSegmentSubspace2(segment: Segment2, point: Point2) f32 {
    return alg.cross2(
        alg.sub(point, segment[0]),
        segmentUnitVector2(segment),
        // alg.unitize(alg.sub(segment[1], segment[0])),
    );
}
pub fn distToFeatureSubspace2(feature: Feature2, point: Point2) f32 {
    switch (feature) {
        .Vertex => |v| {
            return alg.norm(alg.sub(point, v), .@"2");
        },
        .Edge => |e| {
            return distToSegmentSubspace2(e, point);
        },
    }
}
pub fn signedDistToFeatureSubspace2(feature: Feature2, point: Point2) f32 {
    switch (feature) {
        .Vertex => |v| {
            return alg.norm(alg.sub(point, v), .@"2");
        },
        .Edge => |e| {
            return signedDistToSegmentSubspace2(e, point);
        },
    }
}

pub const ClosestFeaturesCandidate2 = struct {
    lhs: Feature2,
    rhs: Feature2,
    closest: bool,
};
/// Edge-Edge case is undefined
/// in Vertex-Vertex case only non-null edge candidates are considered
/// -- it is safe to pass nulls if you mean it
/// in Vertex-Edge case vertex candidate preserves 0-1 edge ordering in its prev-this-next order
/// -- just check where null is
pub fn areLocallyClosestFeatures2(lhs: Feature2, rhs: Feature2) ClosestFeaturesCandidate2 {
    const voronoiTest = struct {
        fn fun(begin: Point2, end: Point2, candidate: Point2) bool {
            return alg.dot2(alg.sub(end, begin), alg.sub(candidate, begin)) > 0;
        }
    }.fun;
    switch (lhs) {
        .Vertex => |lv| {
            switch (rhs) {
                .Vertex => |rv| {
                    // V-V
                    if (lv.next) |ln| {
                        if (voronoiTest(lv.this, ln, rv.this))
                            return .{
                                .lhs = .{ .Edge = .{lv.this, ln} },
                                .rhs = rhs,
                                .closest = false,
                            };
                    }
                    if (lv.prev) |lp| {
                        if (voronoiTest(lv.this, lp, rv.this))
                            return .{
                                .lhs = .{ .Edge = .{lv.this, lp} },
                                .rhs = rhs,
                                .closest = false,
                            };
                    }
                    if (rv.next) |rn| {
                        if (voronoiTest(rv.this, rn, lv.this))
                            return .{
                                .lhs = lhs,
                                .rhs = .{ .Edge = .{rv.this, rn} },
                                .closest = false,
                            };
                    }
                    if (rv.prev) |rp| {
                        if (voronoiTest(rv.this, rp, lv.this))
                            return .{
                                .lhs = lhs,
                                .rhs = .{ .Edge = .{rv.this, rp} },
                                .closest = false,
                            };
                    }
                    return .{
                        .lhs = lhs,
                        .rhs = rhs,
                        .closest = true,
                    };
                }, // V-V
                .Edge => |re| {
                    // V-E
                    if (!voronoiTest(re[0], re[1], lv.this))
                        return .{
                            .lhs = lhs,
                            .rhs = .{ .Vertex = .{
                                .prev = null,
                                .this = re[0],
                                .next = re[1],
                            }},
                            .closest = false,
                        };
                    if (!voronoiTest(re[1], re[0], lv.this))
                        return .{
                            .lhs = lhs,
                            .rhs = .{ .Vertex = .{
                                .prev = re[0],
                                .this = re[1],
                                .next = null,
                            }},
                            .closest = false,
                        };
                    return .{
                        .lhs = lhs,
                        .rhs = rhs,
                        .closest = true,
                    };
                }, // V-E
            }
        },
        .Edge => |le| {
            switch (rhs) {
                .Vertex => |rv| {
                    // E-V
                    if (!voronoiTest(le[0], le[1], rv.this))
                        return .{
                            .lhs = .{ .Vertex = .{
                                .prev = null,
                                .this = le[0],
                                .next = le[1],
                            }},
                            .rhs = rhs,
                            .closest = false,
                        };
                    if (!voronoiTest(le[1], le[0], rv.this))
                        return .{
                            .lhs = .{ .Vertex = .{
                                .prev = le[0],
                                .this = le[1],
                                .next = null,
                            }},
                            .rhs = rhs,
                            .closest = false,
                        };
                    return .{
                        .lhs = lhs,
                        .rhs = rhs,
                        .closest = true,
                    };
                }, // E-V
                .Edge => {
                    // E-E
                    unreachable;
                },
            }
        },
    }
} // areLocallyClosestFeatures2()

pub fn findClosestFeature2(shape: Shape2, point: Point2) Feature2 {
    switch (shape) {
        .disk => |d| {
            return findClosestFeatureDisk2(d, point);
        },
        .triangle => |t| {
            return findClosestFeatureTriangle2(t, point);
        },
        .polygon => |p| {
            return findClosestFeaturePolygon2(p, point);
        },
    }
}
pub fn findClosestFeatureDisk2(disk: Disk2, point: Point2) Feature2 {
    const dir = alg.sub(point, disk.center);
    const _n = 1/alg.norm();
    if (std.math.isInf(_n)) {
        return .{ .Vertex = .{
            .prev = null,
            .this = disk.center,
            .next = null,
        }};
    }
    return .{ .Vertex = .{
        .prev = null,
        .this = alg.add(alg.center, alg.scale(dir, _n)),
        .next = null,
    }};
}
pub fn findClosestFeatureTriangle2(triangle: Triangle2, point: Point2) Feature2 {
    const point_feature = Feature2{ .Vertex = .{
        .prev = null,
        .this = point,
        .next = null,
    }};
    var candidate = Feature2{ .Edge = .{triangle[0], triangle[1]} };
    var i: u32 = 0;
    var done = false;
    while (!done) {
        var full_candidate = ClosestFeaturesCandidate2{
            .lhs = point_feature,
            .rhs = candidate,
            .closest = false,
        };
        // find local minimum
        while (!full_candidate.closest) {
            full_candidate = areLocallyClosestFeatures2(point_feature, candidate);
            candidate = full_candidate.rhs;
            switch (candidate) {
                .Vertex => |*rv| {
                    // I hope so much that manipulations with `i` work
                    if (rv.prev == null) {
                        i += 2;
                        i %= 3;
                        rv.prev = triangle[i];
                    } else if (rv.next == null) {
                        i += 1;
                        i %= 3;
                        rv.next = triangle[(i+1) % 3];
                    }
                },
                .Edge => {},
            }
        }
        // handle local minimum
        switch (full_candidate.rhs) {
            .Vertex => {
                done = true; // break
            },
            .Edge => {
                if (escapeLocalMinimumFeatureTriangle2(triangle, point, i)) |_i| {
                    i = _i;
                    candidate = .{ .Edge = .{triangle[i], triangle[(i+1) % 3]} };
                } else {
                    done = true; // break
                }
            },
        }
    }
    return candidate;
} // findClosestFeatureTriangle2()
// TODO change name to a more informative
pub fn escapeLocalMinimumFeatureTriangle2(
    triangle: Triangle2, point: Point2, loc_min: u32,
) ?u32 {
    const e = Segment2{triangle[loc_min], triangle[(loc_min+1)%3]};
    const e3 = triangle[(loc_min+2) % 3];
    var distances: [3]f32 = undefined;
    distances[0] = signedDistToSegmentSubspace2(e, point);
    distances[1] = signedDistToSegmentSubspace2(.{e[1], e3}, point);
    distances[2] = signedDistToSegmentSubspace2(.{e3, e[0]}, point);
    // finding maximum singed distance
    if (distances[1] > distances[0]) {
        return (loc_min+1) % 3;
    } else if (distances[2] > distances[0]) {
        return (loc_min+2) % 3;
    } else {
        return null;
    }
}
pub fn findClosestFeaturePolygon2(polygon: Polygon2, point: Point2) Feature2 {
    const point_feature = Feature2{ .Vertex = .{
        .prev = null,
        .this = point,
        .next = null,
    }};
    var iter = polygon.boundaryIterator();
    var candidate = Feature2{ .Edge = .{iter.cur(), iter.peek(1)} };
    var done = false;
    while (!done) {
        var full_candidate = ClosestFeaturesCandidate2{
            .lhs = point_feature,
            .rhs = candidate,
            .closest = false,
        };
        // find local minimum
        while (!full_candidate.closest) {
            full_candidate = areLocallyClosestFeatures2(point_feature, candidate);
            candidate = full_candidate.rhs;
            switch (candidate) {
                .Vertex => |*rv| {
                    // I hope so much that these manipulations work
                    if (rv.prev == null) {
                        rv.prev = iter.prev();
                    } else if (rv.next == null) {
                        iter.advance(1);
                        rv.next = iter.peek(1);
                    }
                },
                .Edge => {},
            }
        }
        // handle local minimum
        switch (full_candidate.rhs) {
            .Vertex => {
                done = true; // break
            },
            .Edge => {
                if (escapeLocalMinimumFeaturePolygon2(point, iter)) |_iter| {
                    iter = _iter;
                    candidate = .{ .Edge = .{iter.cur(), iter.peek(1)} };
                } else {
                    done = true;
                }
            },
        }
    }
    return candidate;
}
// TODO change name to a more informative
pub fn escapeLocalMinimumFeaturePolygon2(
    point: Point2, loc_min: Polygon2.BoundaryIterator,
) ?Polygon2.BoundaryIterator {
    var iter = loc_min;
    const e = Segment2{iter.cur(), iter.peek(1)};
    const init_i = iter.i;
    const init_dist = signedDistToSegmentSubspace2(e, point);
    // finding maximum signed distance
    var max_i = init_i;
    var max_dist = init_dist;
    iter.advance(1);
    while (iter.i != init_i) : (iter.advance(1)) {
        const dist = signedDistToSegmentSubspace2(.{iter.cur(), iter.peek(1)}, point);
        if (dist > max_dist) {
            max_i = iter.i;
            max_dist = dist;
        }
    }
    if (max_dist > init_dist) {
        iter.i = max_i;
        return iter;
    } else {
        return null;
    }
}

// TODO add segment and point?
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

/// you might get into trouble during collision detection if this is not convex
pub const Polygon2 = struct {
    pub const Layout = enum {
        fan, strip,
    };

    layout: Layout,
    vertices: []Point2,

    /// with strip layout first triangle (vertices[0..3]) and polygon have opposite orientations
    pub const BoundaryIterator = struct {
        host: *const Polygon2,
        i: u32,

        /// might not be very efficient
        pub fn advance(self: *BoundaryIterator, n: i32) void {
            if (n > 0) {
                var counter = @intCast(u32, n);
                while (counter > 0) : (counter -= 1) {
                    switch (self.host.layout) {
                        .fan => {
                            self.i += 1;
                            if (self.i == @intCast(u32, self.host.vertices.len))
                                self.i = 1;
                        },
                        .strip => {
                            const parity = self.i % 2;
                            if (parity == 0) {
                                if (self.i == 0) {
                                    self.i += 1;
                                } else {
                                    self.i -= 2;
                                }
                            } else {
                                if (self.i == @intCast(u32, self.host.vertices.len - 2)) {
                                    self.i += 1;
                                } else if (self.i == @intCast(u32, self.host.vertices.len - 1)) {
                                    self.i -= 1;
                                } else {
                                    self.i += 2;
                                }
                            }
                        },
                    }
                }
            } else if (n < 0) {
                var counter = @intCast(u32, -n);
                while (counter > 0) : (counter -= 1) {
                    switch (self.host.layout) {
                        .fan => {
                            self.i -= 1;
                            if (self.i == 0)
                                self.i = @intCast(u32, self.host.vertices.len - 1);
                        },
                        .strip => {
                            const parity = self.i % 2;
                            if (parity == 0) {
                                if (self.i == @intCast(u32, self.host.vertices.len - 2)) {
                                    self.i += 1;
                                } else if (self.i == @intCast(u32, self.host.vertices.len - 1)) {
                                    self.i -= 1;
                                } else {
                                    self.i += 2;
                                }
                            } else {
                                if (self.i == 1) {
                                    self.i = 0;
                                } else {
                                    self.i -= 2;
                                }
                            }
                        },
                    }
                }
            }
        }
        /// `advance(n); cur();` but without changing internal state
        pub fn peek(self: *const BoundaryIterator, n: i32) Point2 {
            var copy = self.*;
            copy.advance(n);
            return copy.cur();
        }
        ///
        pub fn next(self: *BoundaryIterator) Point2 {
            self.advance(1);
            return self.host.vertices[self.i];
        }
        ///
        pub fn cur(self: *const BoundaryIterator) Point2 {
            return self.host.vertices[self.i];
        }
        ///
        pub fn prev(self: *BoundaryIterator) Point2 {
            self.advance(-1);
            return self.host.vertices[self.i];
        }
    };
    pub fn boundaryIterator(self: *const Polygon2) BoundaryIterator {
        if (debug) {
            // TODO log rather than panic
            if (self.vertices.len < 3)
                @panic("polygon is to small to be iterated over");
        }
        switch (self.layout) {
            .fan => {
                return .{
                    .host = self,
                    .i = 1,
                };
            },
            .strip => {
                return .{
                    .host = self,
                    .i = 0,
                };
            },
        }
    }
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

pub fn boundingBox2(shape: Shape2) Box2 {
    switch (shape) {
        .disk => |d| {
            const l = d.center[0] - d.radius;
            const r = d.center[0] + d.radius;
            const b = d.center[1] - d.radius;
            const t = d.center[1] + d.radius;
            return .{
                .lb = .{l, b},
                .rt = .{r, t},
            };
        },
        .triangle => |tr| {
            const l =  std.math.inf(f32);
            const r = -std.math.inf(f32);
            const b =  std.math.inf(f32);
            const t = -std.math.inf(f32);
            for (&tr) |vx| {
                if (vx[0] < l)
                    l = vx[0];
                if (vx[0] > r)
                    r = vx[0];
                if (vx[1] < b)
                    b = vx[1];
                if (vx[1] > t)
                    t = vx[1];
            }
            return .{
                .lb = .{l, b},
                .rt = .{r, t},
            };
        },
        .polygon => |p| {
            const l =  std.math.inf(f32);
            const r = -std.math.inf(f32);
            const b =  std.math.inf(f32);
            const t = -std.math.inf(f32);
            for (p.vertices) |vx| {
                if (vx[0] < l)
                    l = vx[0];
                if (vx[0] > r)
                    r = vx[0];
                if (vx[1] < b)
                    b = vx[1];
                if (vx[1] > t)
                    t = vx[1];
            }
            return .{
                .lb = .{l, b},
                .rt = .{r, t},
            };
        },
    }
}

pub fn support2(shape: Shape2, direction: Vector2) Point2 {
    switch (shape) {
        .disk => |d| {
            return supportDisk2(d, direction);
        },
        .triangle => |t| {
            return supportTriangle2(t, direction);
        },
        .polygon => |p| {
            return supportPolygon2(p, direction);
        },
    }
}
pub fn supportDisk2(disk: Disk2, direction: Vector2) Point2 {
    const n = alg.norm(direction, .@"2");
    if (debug) {
        if (std.math.isInf(1/n))
            @panic("finding support for disk at zero-length direction");
    }
    return alg.add(disk.center, alg.scale(direction, disk.radius / n));
}
pub fn supportTriangle2(triangle: Triangle2, direction: Vector2) Point2 {
    var max_idx: u32 = undefined;
    var max_dot = -std.math.inf(f32);
    for (&triangle, 0..) |vertex, i| {
        var dot = alg.dot2(vertex, direction);
        if (dot > max_dot) {
            max_idx = @intCast(u32, i);
            max_dot = dot;
        }
    }
    return triangle[max_idx];
}
pub fn supportPolygon2(polygon: Polygon2, direction: Vector2) Point2 {
    var max_idx: u32 = undefined;
    var max_dot = -std.math.inf(f32);
    for (polygon.vertices, 0..) |vertex, i| {
        var dot = alg.dot2(vertex, direction);
        if (dot > max_dot) {
            max_idx = @intCast(u32, i);
            max_dot = dot;
        }
    }
    return polygon.vertices[max_idx];
}

// pub fn minkowskiDifferenceSupport2(lhs: Shape2, rhs: Shape2, direction: Vector2) Point2 {
//     return alg.sub(
//         support2(lhs, direction),
//         support2(rhs, alg.neg(direction)),
//     );
// }

// pub const GJK2_result = struct {
//     simplex: Triangle2,
//     intersection: bool,
// };
// TODO?
// pub fn gjk2(lhs: Shape2, rhs: Shape2) GJK2_result {
//     var simplex: Triangle2 = undefined;
//     simplex[0] = alg.sub(getAnyVertex(lhs), getAnyVertex(rhs));
//     simplex[1] = minkowskiDifferenceSupport2(lhs, rhs, alg.neg(simplex[0]));
// }
pub fn getAnyVertex(shape: Shape2) Point2 {
    return switch (shape) {
        .disk => |d| alg.add(d.center + alg.scale(Vector2{1.0, 0.0}, d.radius)),
        .triangle => |t| t[0],
        .polygon => |p| p.vertices[1],
    };
}

const VertexIndexCount = struct {
    n_vertices: i32,
    n_indices: i32,
};
fn getDrawableVertexIndexCount2(
    shape: Shape2, target_topology: vk.PrimitiveTopology,
) !VertexIndexCount {
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
                                drawable.indices[i*3 + 1] =
                                    @intCast(Graphics.Index, i+1);
                                drawable.indices[i*3 + 2] =
                                    @intCast(Graphics.Index, i+2);
                            }
                            const tail = drawable.vertices.len-2;
                            drawable.indices[tail*3] = 0;
                            drawable.indices[tail*3 + 1] =
                                @intCast(Graphics.Index, tail+1);
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
                                        drawable.indices[i*3 + 1] =
                                            @intCast(Graphics.Index, i+1);
                                        drawable.indices[i*3 + 2] =
                                            @intCast(Graphics.Index, i+2);
                                    }
                                    const tail = drawable.vertices.len-2;
                                    drawable.indices[tail*3] = 0;
                                    drawable.indices[tail*3 + 1] =
                                        @intCast(Graphics.Index, tail+1);
                                    drawable.indices[tail*3 + 2] = 1;
                                },
                                .strip => {
                                    for (drawable.vertices, p.vertices) |*dst, pos| {
                                        dst.pos = pos;
                                        dst.col = .{v.r, v.g, v.b};
                                    }
                                    for (0..drawable.vertices.len-2) |i| {
                                        const parity = @intCast(Graphics.Index, i%2);
                                        drawable.indices[i*3] =
                                            @intCast(Graphics.Index, i);
                                        drawable.indices[i*3 + 1] =
                                            @intCast(Graphics.Index, i + (1 + parity));
                                        drawable.indices[i*3 + 2] =
                                            @intCast(Graphics.Index, i + (2 - parity));
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
                                drawable.indices[i*3 + 1] =
                                    @intCast(Graphics.Index, i+1);
                                drawable.indices[i*3 + 2] =
                                    @intCast(Graphics.Index, i+2);
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
                                        drawable.indices[i*3 + 1] =
                                            @intCast(Graphics.Index, i+1);
                                        drawable.indices[i*3 + 2] =
                                            @intCast(Graphics.Index, i+2);
                                    }
                                    const tail = drawable.vertices.len-2;
                                    drawable.indices[tail*3] = 0;
                                    drawable.indices[tail*3 + 1] =
                                        @intCast(Graphics.Index, tail+1);
                                    drawable.indices[tail*3 + 2] = 1;
                                },
                                .strip => {
                                    for (drawable.vertices, p.vertices, a) |*dst, pos, col| {
                                        dst.pos = pos;
                                        dst.col = .{col.r, col.g, col.b};
                                    }
                                    for (0..drawable.vertices.len-2) |i| {
                                        const parity = @intCast(Graphics.Index, i%2);
                                        drawable.indices[i*3] =
                                            @intCast(Graphics.Index, i);
                                        drawable.indices[i*3 + 1] =
                                            @intCast(Graphics.Index, i + (1 + parity));
                                        drawable.indices[i*3 + 2] =
                                            @intCast(Graphics.Index, i + (2 - parity));
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
        .translation => |t| .{ .translation = alg.neg(t) },
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
            applyTranslation2(t, shape);
        },
        .rotation => |r| {
            applyRotation2(r, shape);
        },
        .scaling => |s| {
            try applyScaling2(s, shape);
        },
    }
}
pub fn applyTranslation2(translation: Translation2, shape: *Shape2) void {
    switch (shape.*) {
        .disk => |*d| {
            alg.addInplace(&d.center, translation);
        },
        .triangle => |*tri| {
            for (tri) |*dst| {
                alg.addInplace(dst, translation);
            }
        },
        .polygon => |p| {
            for (p.vertices) |*dst| {
                alg.addInplace(dst, translation);
            }
        },
    }
}
pub fn applyRotation2(rotation: Rotation2, shape: *Shape2) void {
    switch (shape.*) {
        .disk => {},
        .triangle => |*tri| {
            const s = @sin(rotation);
            const c = @cos(rotation);
            for (tri) |*point| {
                // is this UB?
                // point.* = .{ c*point[0] + s*point[1], -s*point[0] + c*point[1] };
                // calling alg.rotInplace2() recomputes sin and cos
                // TODO profile to check what is faster
                const x = point.*;
                point.* = .{c*x[0] - s*x[1], s*x[0] + c*x[1]};
            }
        },
        .polygon => |p| {
            const s = @sin(rotation);
            const c = @cos(rotation);
            for (p.vertices) |*point| {
                // calling alg.rotInplace2() recomputes sin and cos
                // TODO profile to check what is faster
                point.* = .{ c*point[0] - s*point[1], s*point[0] + c*point[1] };
            }
        },
    }
}
pub fn applyScaling2(scaling: Scaling2, shape: *Shape2) TransformError2!void {
    switch (shape.*) {
        .disk => |*d| {
            if (@fabs(scaling[0] - scaling[1]) > 1e-04) {
                return TransformError2.non_uniform_disk_scaling;
            }
            alg.scaleInplace(&d.center, scaling[0]);
            d.radius *= scaling[0];
        },
        .triangle => |*tri| {
            for (tri) |*point| {
                point[0] *= scaling[0];
                point[1] *= scaling[1];
            }
        },
        .polygon => |p| {
            for (p.vertices) |*point| {
                point[0] *= scaling[0];
                point[1] *= scaling[1];
            }
        },
    }
}
// TODO apply translation chain to a specific shape type



const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;
const tator = testing.allocator;

fn testTriangleClosestFeature2(triangle: Triangle2, point: Point2, expected: Feature2) !void {
    const candidate = findClosestFeatureTriangle2(triangle, point);
    switch (expected) {
        .Vertex => |ev| {
            switch (candidate) {
                .Vertex => |cv| {
                    try expectEqual(ev.this[0], cv.this[0]);
                    try expectEqual(ev.this[1], cv.this[1]);
                },
                .Edge => {
                    return error.FeatureTypeMismatch2;
                },
            }
        },
        .Edge => |ee| {
            switch (candidate) {
                .Vertex => {
                    return error.FeatureTypeMismatch2;
                },
                .Edge => |ce| {
                    try expect(
                        (
                            alg.eql(ee[0], ce[0]) and alg.eql(ee[1], ce[1])
                        ) or (
                            alg.eql(ee[1], ce[0]) and alg.eql(ee[0], ce[1])
                        )
                    );
                },
            }
        },
    }
}
test "triangle closest feature 2D" {
    const triangle = Triangle2{
        .{0.0, 0.0},
        .{1.0, 0.0},
        .{0.0, 1.0},
    };
    const points = [_]Point2{
        triangle[0],
        triangle[1],
        triangle[2],
        .{-1.0, -1.0},
        .{1.0, 1.0},
        .{std.math.sqrt1_2, std.math.sqrt1_2},
        .{std.math.sqrt1_2-0.1, std.math.sqrt1_2-0.1},
        .{-0.5, 0.5},
        .{0.5, -0.5},
        .{-0.5, 1.5},
        .{1.5, -0.5},
    };
    const expected = [points.len]Feature2{
        .{ .Vertex = .{
            .prev = null,
            .this = triangle[0],
            .next = null,
        }},
        .{ .Vertex = .{
            .prev = null,
            .this = triangle[1],
            .next = null,
        }},
        .{ .Vertex = .{
            .prev = null,
            .this = triangle[2],
            .next = null,
        }},
        .{ .Vertex = .{
            .prev = null,
            .this = triangle[0],
            .next = null,
        }},
        .{ .Edge = .{
            triangle[1], triangle[2],
        }},
        .{ .Edge = .{
            triangle[1], triangle[2],
        }},
        .{ .Edge = .{
            triangle[1], triangle[2],
        }},
        .{ .Edge = .{
            triangle[0], triangle[2],
        }},
        .{ .Edge = .{
            triangle[0], triangle[1],
        }},
        .{ .Vertex = .{
            .prev = null,
            .this = triangle[2],
            .next = null,
        }},
        .{ .Vertex = .{
            .prev = null,
            .this = triangle[1],
            .next = null,
        }},
    };
    for (points, expected) |p, e| {
        try testTriangleClosestFeature2(triangle, p, e);
    }
}

fn testPolygonBoundaryIterator2(polygon: Polygon2, expected_indices: []const u32) !void {
    var iter = polygon.boundaryIterator();
    for (expected_indices) |ei| {
        try expectEqual(ei, iter.i);
        _ = iter.next();
    }
    for (expected_indices) |ei| {
        try expectEqual(ei, iter.i);
        _ = iter.next();
    }
    for (1..expected_indices.len+1) |j| {
        _ = iter.prev();
        try expectEqual(expected_indices[expected_indices.len-j], iter.i);
    }
    for (1..expected_indices.len+1) |j| {
        _ = iter.prev();
        try expectEqual(expected_indices[expected_indices.len-j], iter.i);
    }
}
test "polygon boundary iterator 2D" {
    var polygon_memory: [40]Point2 = undefined;
    const polygons = [_]Polygon2{
        .{
            .vertices = polygon_memory[0..3], // 3
            .layout = .strip,
        },
        .{
            .vertices = polygon_memory[3..7], // 4
            .layout = .fan,
        },

        .{
            .vertices = polygon_memory[7..11], // 4
            .layout = .strip,
        },
        .{
            .vertices = polygon_memory[11..16], // 5
            .layout = .fan,
        },

        .{
            .vertices = polygon_memory[16..21], // 5
            .layout = .strip,
        },
        .{
            .vertices = polygon_memory[21..27], // 6
            .layout = .fan,
        },

        .{
            .vertices = polygon_memory[27..33], // 6
            .layout = .strip,
        },
        .{
            .vertices = polygon_memory[33..40], // 7
            .layout = .fan,
        },
    };
    const expected_indices = [_][]const u32 {
        &.{0, 1, 2},
        &.{1, 2, 3},
        &.{0, 1, 3, 2},
        &.{1, 2, 3, 4},
        &.{0, 1, 3, 4, 2},
        &.{1, 2, 3, 4, 5},
        &.{0, 1, 3, 5, 4, 2},
        &.{1, 2, 3, 4, 5, 6},
    };
    for (polygons, expected_indices) |p, ei| {
        try testPolygonBoundaryIterator2(p, ei);
    }
}

fn testPolygonClosestFeature2(polygon: Polygon2, point: Point2, expected: Feature2) !void {
    const candidate = findClosestFeaturePolygon2(polygon, point);
    switch (expected) {
        .Vertex => |ev| {
            switch (candidate) {
                .Vertex => |cv| {
                    try expectEqual(ev.this[0], cv.this[0]);
                    try expectEqual(ev.this[1], cv.this[1]);
                },
                .Edge => {
                    return error.FeatureTypeMismatch2;
                },
            }
        },
        .Edge => |ee| {
            switch (candidate) {
                .Vertex => {
                    return error.FeatureTypeMismatch2;
                },
                .Edge => |ce| {
                    // std.debug.print("{any} vs {any}\n", .{ee, ce});
                    try expect(
                        (
                            alg.eql(ee[0], ce[0]) and alg.eql(ee[1], ce[1])
                        ) or (
                            alg.eql(ee[1], ce[0]) and alg.eql(ee[0], ce[1])
                        )
                    );
                },
            }
        },
    }
}
test "polygon closest feature 2D" {
    {
        var polygon_memory = [_]Point2{
            .{0.0, 0.0},
            .{1.0, 0.0},
            .{0.0, 1.0},
            .{1.0, 1.0},
        };
        const polygon = Polygon2{
            .layout = .strip,
            .vertices = &polygon_memory,
        };
        {
            const pts = [_]Point2{
                .{0.5, -0.5},
                .{1.5, 0.5},
                .{0.5, 1.5},
                .{-0.5, -0.5},
            };
            var iter = polygon.boundaryIterator();
            for (0..polygon.vertices.len) |i| {
                try expect(signedDistToSegmentSubspace2(.{iter.cur(), iter.peek(1)}, pts[i]) > 0);
                iter.advance(1);
            }
        }
        const points = [_]Point2{
            polygon.vertices[0],
            polygon.vertices[1],
            polygon.vertices[2],
            polygon.vertices[3],
            .{0.0, 0.5},
            .{0.1, 0.5},
            .{-0.5, -0.5},
            .{-0.5, 0.5},
            .{-0.5, 1.5},
            .{0.5, 1.5},
            .{1.5, 1.5},
            .{1.5, 0.5},
            .{1.5, -0.5},
            .{0.5, -0.5},
        };
        const expected = [_]Feature2{
            .{ .Vertex = .{
                .prev = null,
                .this = polygon.vertices[0],
                .next = null,
            }},
            .{ .Vertex = .{
                .prev = null,
                .this = polygon.vertices[1],
                .next = null,
            }},
            .{ .Vertex = .{
                .prev = null,
                .this = polygon.vertices[2],
                .next = null,
            }},
            .{ .Vertex = .{
                .prev = null,
                .this = polygon.vertices[3],
                .next = null,
            }},
            .{ .Edge = .{polygon.vertices[0], polygon.vertices[2]} },
            .{ .Edge = .{polygon.vertices[0], polygon.vertices[2]} },
            .{ .Vertex = .{
                .prev = null,
                .this = polygon.vertices[0],
                .next = null,
            }},
            .{ .Edge = .{polygon.vertices[0], polygon.vertices[2]} },
            .{ .Vertex = .{
                .prev = null,
                .this = polygon.vertices[2],
                .next = null,
            }},
            .{ .Edge = .{polygon.vertices[2], polygon.vertices[3]} },
            .{ .Vertex = .{
                .prev = null,
                .this = polygon.vertices[3],
                .next = null,
            }},
            .{ .Edge = .{polygon.vertices[3], polygon.vertices[1]} },
            .{ .Vertex = .{
                .prev = null,
                .this = polygon.vertices[1],
                .next = null,
            }},
            .{ .Edge = .{polygon.vertices[1], polygon.vertices[0]} },
        };
        for (points, expected) |p, e| {
            try testPolygonClosestFeature2(polygon, p, e);
        }
    }

    {
        var polygon_memory = [_]Point2{
            .{0.5, 0.5},
            .{0.0, 0.0},
            .{1.0, 0.0},
            .{1.0, 1.0},
            .{0.0, 1.0},
        };
        const polygon = Polygon2{
            .layout = .fan,
            .vertices = &polygon_memory,
        };
        const points = [_]Point2{
            polygon.vertices[1],
            polygon.vertices[2],
            polygon.vertices[3],
            polygon.vertices[4],
            .{0.0, 0.5},
            .{0.1, 0.5},
            .{-0.5, -0.5},
            .{-0.5, 0.5},
            .{-0.5, 1.5},
            .{0.5, 1.5},
            .{1.5, 1.5},
            .{1.5, 0.5},
            .{1.5, -0.5},
            .{0.5, -0.5},
        };
        const expected = [_]Feature2{
            .{ .Vertex = .{
                .prev = null,
                .this = polygon.vertices[1],
                .next = null,
            }},
            .{ .Vertex = .{
                .prev = null,
                .this = polygon.vertices[2],
                .next = null,
            }},
            .{ .Vertex = .{
                .prev = null,
                .this = polygon.vertices[3],
                .next = null,
            }},
            .{ .Vertex = .{
                .prev = null,
                .this = polygon.vertices[4],
                .next = null,
            }},
            .{ .Edge = .{polygon.vertices[4], polygon.vertices[1]} },
            .{ .Edge = .{polygon.vertices[4], polygon.vertices[1]} },
            .{ .Vertex = .{
                .prev = null,
                .this = polygon.vertices[1],
                .next = null,
            }},
            .{ .Edge = .{polygon.vertices[4], polygon.vertices[1]} },
            .{ .Vertex = .{
                .prev = null,
                .this = polygon.vertices[4],
                .next = null,
            }},
            .{ .Edge = .{polygon.vertices[3], polygon.vertices[4]} },
            .{ .Vertex = .{
                .prev = null,
                .this = polygon.vertices[3],
                .next = null,
            }},
            .{ .Edge = .{polygon.vertices[2], polygon.vertices[3]} },
            .{ .Vertex = .{
                .prev = null,
                .this = polygon.vertices[2],
                .next = null,
            }},
            .{ .Edge = .{polygon.vertices[1], polygon.vertices[2]} },
        };
        for (points, expected[0..points.len]) |p, e| {
            try testPolygonClosestFeature2(polygon, p, e);
        }
    }
}
