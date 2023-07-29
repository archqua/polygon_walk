const std = @import("std");
const builtin = @import("builtin");
pub const debug = switch (builtin.mode) {
    .Debug, .ReleaseSafe => true,
    else => false,
};

const alg = @import("alg.zig");
const shape = @import("shape.zig");
const rigid = @import("rigid.zig");


/// narrow phase of collision detection
/// null if no collision
pub fn collisionPoint2(lhs: shape.Shape2, rhs: shape.Shape2) ?shape.Point2 {
    switch (lhs) {
        .disk => |ld| {
            switch (rhs) {
                .disk => |rd| {
                    // disk - disk
                    if (debug) {
                        // TODO log rather than panic
                        if (ld.radius <= 0 or rd.radius <= 0)
                            @panic("trying to detect collision with disk of non-positive radius");
                    }
                    const l2r = alg.sub(rd.center, ld.center);
                    const l2r_norm = alg.norm(l2r, .@"2");
                    if (l2r_norm <= rd.radius + ld.radius) {
                        // is this test good enough?
                        if (l2r_norm < 1e-04)
                            return ld.center;
                        const lcp = shape.supportDisk2(ld, l2r);
                        const rcp = shape.supportDisk2(rd, alg.neg(l2r));
                        return alg.scale(alg.add(lcp, rcp), 0.5);
                    } else {
                        return null;
                    }
                }, // disk - disk
                .triangle => |rt| {
                    // disk - triangle
                    const rt_feature =
                        shape.findClosestFeatureTriangle2(rt, ld.center);
                    const signed_dist_to_center =
                        shape.signedDistToFeatureSubspace(rt_feature, ld.center);
                    if (signed_dist_to_center < ld.radius) {
                        switch (rt_feature) {
                            .Vertex => |rt_v| {
                                const l2r = alg.sub(rt_v, ld.center);
                                const l2r_norm = alg.norm(l2r, .@"2");
                                if (l2r_norm < 1e-04) {
                                    return ld.center;
                                } else {
                                    return alg.scale(alg.add(
                                        shape.supportDisk2(ld, l2r),
                                        rt_v,
                                    ), 0.5);
                                }
                            },
                            .Edge => |rt_e| {
                                const segment_normal = shape.segmentUnitNormal2(rt_e);
                                return alg.scale(alg.add(
                                    shape.supportDisk2(ld, segment_normal),
                                    alg.add(
                                        ld.center,
                                        alg.scale(
                                            segment_normal, signed_dist_to_center,
                                        ),
                                    ),
                                ), 0.5);
                            },
                        }
                    } else {
                        return null;
                    }
                }, // disk - triangle
                .polygon => |rp| {
                    // disk - polygon
                    const rp_feature = shape.findClosestFeaturePolygon2(rp, ld.center);
                    const signed_dist_to_center =
                        shape.signedDistToFeatureSubspace(rp_feature, ld.center);
                    if (signed_dist_to_center < ld.radius) {
                        switch (rp_feature) {
                            .Vertex => |rp_v| {
                                const l2r = alg.sub(rp_v, ld.center);
                                const l2r_norm = alg.norm(l2r, .@"2");
                                if (l2r_norm < 1e-04) {
                                    return ld.center;
                                } else {
                                    return alg.scale(alg.add(
                                        shape.supportDisk2(ld, l2r),
                                        rp_v,
                                    ), 0.5);
                                }
                            },
                            .Edge => |rp_e| {
                                const segment_normal = shape.segmentUnitNormal2(rp_e);
                                return alg.scale(alg.add(
                                    shape.supportDisk2(ld, segment_normal),
                                    alg.add(
                                        ld.center,
                                        alg.scale(
                                            segment_normal, signed_dist_to_center,
                                        ),
                                    ),
                                ), 0.5);
                            },
                        }
                    } else {
                        return null;
                    }
                }, // disk - polygon
            }
        }, // disk - ...
        .triangle => |lt| {
            _ = lt;
            switch (rhs) {
                .disk => |rd| {
                    _ = rd;
                    // triangle - disk
                },
                .triangle => |rt| {
                    _ = rt;
                    // triangle - triangle
                },
                .polygon => |rp| {
                    _ = rp;
                    // triangle - polygon
                },
            }
        }, // triangle - ...
        .polygon => |lp| {
            _ = lp;
            switch (rhs) {
                .disk => |rd| {
                    _ = rd;
                    // polygon - disk
                },
                .triangle => |rt| {
                    _ = rt;
                    // polygon - triangle
                },
                .polygon => |rp| {
                    _ = rp;
                    // polygon - polygon
                },
            }
        },
    }
} // collisionPoint2()


pub const Collider2 = struct {
    shapes: []shape.Shape2,
    rigid: rigid.Body2,
    center_of_mass: shape.Point2,

    pub fn applyTransform(self: *Collider2, transform: shape.Transform2) !void {
        switch (transform) {
            .translation => |tr| {
                self.applyTranslation(tr);
            },
            .rotation => |rot| {
                self.applyRotation(rot);
            },
            .scaling => |sc| {
                try self.applyScaling(sc);
            },
        }
    }
    pub fn applyTranslation(self: *Collider2, translation: shape.Translation2) void {
        for (self.shapes) |*s| {
            shape.applyTranslation2(translation, s);
        }
        alg.addInplace(&self.center_of_mass, translation);
    }
    pub fn applyRotation(self: *Collider2, rotation: shape.Rotation2) void {
        for (self.shapes) |*s| {
            // TODO apply translation chain to a specific shape type
            shape.applyTranslation2(alg.neg(self.center_of_mass), s);
            shape.applyRotation2(rotation, s);
            shape.applyTranslation2(self.center_of_mass, s);
        }
    }
    pub fn applyScaling(self: *Collider2, scaling: shape.Scaling2) !void {
        for (self.shapes) |*s| {
            // TODO apply translation chain to a specific shape type
            shape.applyTranslation2(alg.neg(self.center_of_mass), s);
            try shape.applyScaling2(scaling, s);
            shape.applyTranslation2(self.center_of_mass, s);
        }
    }

    pub fn applyCentralMomentum(self: Collider2, momentum: alg.Vec2) alg.Vec2 {
        return self.rigid.applyCentralMomentum(momentum);
    }
    pub fn applyAngMomentum(self: Collider2, momentum: f32) f32 {
        return self.rigid.applyAngMomentum(momentum);
    }
    /// contact_point is absolute
    pub fn applyMomentumAt(
        self: Collider2, momentum: alg.Vec2, contact_point: alg.Vec2,
    ) rigid.Body2.Velocities {
        return self.rigid.applyMomentumAt(
            momentum, alg.sum(contact_point, self.center_of_mass),
        );
    }
    pub fn applyCentralForce(self: Collider2, force: alg.Vec2, duration: f32) alg.Vec2 {
        return self.rigid.applyCentralForce(force, duration);
    }
    pub fn applyTorsion(self: Collider2, torsion: f32, duration: f32) f32 {
        return self.rigid.applyTorsion(torsion, duration);
    }
    pub fn applyForceAt(
        self: Collider2, force: alg.Vec2, duration: f32, contact_point: alg.Vec2,
    ) rigid.Body2.Velocities {
        return self.rigid.applyForceAt(
            force, duration, alg.sub(contact_point, self.center_of_mass),
        );
    }

    pub fn midPointStepAccelerate(self: *Collider2, lin_vel_shift: alg.Vec2, ang_vel_shift: f32) rigid.Velocities {
        return self.rigid.midPointStep(lin_vel_shift, ang_vel_shift);
    }
    pub fn eulerStepMove(self: *Collider2, velocities: rigid.Velocities, dt: f32) void {
        self.applyRotation(dt*velocities.angular);
        self.applyTranslation(alg.scale(self.velocities.linear, dt));
    }

    pub fn box(self: Collider2) shape.Box2 {
        if (debug) {
            // TODO log rather than panic
            if (self.shapes.len < 1)
                @panic("encountered Collider2 with zero shapes when trying to get bounding box");
        }
        var res: shape.Box2 = shape.boundingBox2(self.shapes[0]);
        for (self.shapes[1..]) |shp| {
            res = res.span(shape.boundingBox2(shp));
        }
        return res;
    }
};
