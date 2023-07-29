const std = @import("std");

const alg = @import("alg.zig");
const Vec2 = alg.Vec2;

pub const Body2 = struct {
    lin_inertia: f32 = 1.0,
    lin_velocity: Vec2 = .{0.0, 0.0},
    ang_inertia: f32 = 1.0,
    ang_velocity: f32 = 0.0,
    restitution: f32 = 1.0,
    friction: f32 = 0.0,

    pub fn applyCentralMomentum(self: Body2, momentum: Vec2) Vec2 {
        if (std.math.isInf(self.lin_inertia))
            return .{0.0, 0.0};
        return alg.scale(momentum, 1/self.lin_inertia);
    }
    pub fn applyAngMomentum(self: Body2, momentum: f32) f32 {
        if (std.math.isInf(self.ang_inertia))
            return 0.0;
        return momentum / self.ang_inetria;
    }
    /// contact_point is relative to the center of mass
    pub fn applyMomentumAt(self: Body2, momentum: Vec2, contact_point: Vec2) Velocities {
        const ang_momentum = alg.cross2(contact_point, momentum);
        return .{
            .linear = self.applyCentralMomentum(momentum),
            .angular = self.applyAngMomentum(ang_momentum),
        };
    }
    pub fn exertCentralForce(self: Body2, force: Vec2, duration: f32) Vec2 {
        if (std.math.isInf(self.lin_inertia))
            return .{0.0, 0.0};
        // this results in fewer multiplication operations
        // than calling `applyLinMomentum(alg.scale(force, duration))`
        return alg.scale(force, duration/self.lin_inertia);
    }
    pub fn exertTorsion(self: Body2, torsion: f32, duration: f32) f32 {
        // this check might filter-out unnecessary `torsion * duration` multiplication
        // as opposed to calling `applyAngMomentum(torsion * duration)`
        if (std.math.isInf(self.ang_inertia))
            return 0.0;
        return torsion * duration / self.ang_inertia;
    }
    /// contact_point is relative to the center of mass
    pub fn exertForceAt(self: Body2, force: Vec2, duration: f32, contact_point: Vec2) Velocities {
        const torsion = alg.cross2(contact_point, force);
        return .{
            .linear = self.exertCentralForce(force, duration),
            .angular = self.exertTorsion(torsion, duration),
        };
    }

    pub const Velocities = struct {
        linear: Vec2,
        angular: f32,
    };
    pub fn midPointStep(self: *Body2, lin_vel_shift: Vec2, ang_vel_shift: f32) Velocities {
        const lin_mid_point_vel = alg.add(self.lin_velocity, alg.scale(lin_vel_shift, 0.5));
        const ang_mid_point_vel = self.ang_velocity + 0.5*ang_vel_shift;

        alg.addInplace(&self.lin_velocity, lin_vel_shift);
        self.ang_velocity += ang_vel_shift;

        return .{
            .linear = lin_mid_point_vel,
            .angular = ang_mid_point_vel,
        };
    }
};
