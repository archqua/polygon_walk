const std = @import("std");

const alg = @import("alg.zig");
const Vec2 = alg.Vec2;

pub const Body2 = struct {
    lin_inertia: f32 = 1.0,
    lin_velocity: Vec2 = .{0.0, 0.0},
    ang_inertia: f32 = 1.0,
    ang_velocity: f32 = 0.0,

    pub fn exertForce(self: Body2, force: Vec2, duration: f32) Vec2 {
        // const vel_shift = Vec2{
        //     force[0] * duration / self.lin_inertia,
        //     force[1] * duration / self.lin_inertia,
        // };
        if (std.math.isInf(self.lin_inertia))
            return .{0.0, 0.0};
        return alg.scale(force, duration/self.lin_inertia);
    }
    pub fn exertTorsion(self: Body2, torsion: f32, duration: f32) f32 {
        if (std.math.isInf(self.ang_inertia))
            return 0.0;
        return torsion * duration / self.ang_inertia;
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

        // std.debug.print("angular midpoint is {}\n", .{ang_mid_point_vel});
        return .{
            .linear = lin_mid_point_vel,
            .angular = ang_mid_point_vel,
        };
    }
};
