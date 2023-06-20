const math = @import("std").math;

pub const Mat4 = [16]f32;
pub const Vec2 = [2]f32;
pub const Vec3 = [3]f32;

pub const eye4 = [16]f32{
    1.0, 0.0, 0.0, 0.0,
    0.0, 1.0, 0.0, 0.0,
    0.0, 0.0, 1.0, 0.0,
    0.0, 0.0, 0.0, 1.0,
};
pub const zeros4 = [16]f32{
    0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0,
};
pub fn matElementAccess(mat: Mat4, row: u8, col: u8) f32 {
    return mat[row + 4*col];
}
pub fn matElementSet(mat: *Mat4, row: u8, col: u8, val: f32) void {
    mat[row + 4*col] = val;
}
pub fn matmul(lhs: Mat4, rhs: Mat4) Mat4 {
    var res = zeros4;
    for (0..4) |_i| {
        const i = @intCast(u8, _i);
        for (0..4) |_j| {
            const j = @intCast(u8, _j);
            var val: f32 = 0.0;
            for (0..4) |_k| {
                const k = @intCast(u8, _k);
                val += matElementAccess(lhs, i, k) * matElementAccess(rhs, k, j);
            }
            matElementSet(&res, i, j, val);
        }
    }
    return res;
}

pub fn translate2(shift: Vec2) Mat4 {
    var res = eye4;
    matElementSet(&res, 0, 3, shift[0]);
    matElementSet(&res, 1, 3, shift[1]);
    return res;
}
pub fn translate3(shift: Vec3) Mat4 {
    var res = eye4;
    matElementSet(&res, 0, 3, shift[0]);
    matElementSet(&res, 1, 3, shift[1]);
    matElementSet(&res, 2, 3, shift[2]);
    return res;
}

pub fn rotate2(rad: f32) Mat4 {
    const c = math.cos(rad);
    const s = math.sin(rad);
    var res = eye4;
    matElementSet(&res, 0, 0, c);
    matElementSet(&res, 0, 1, s);
    matElementSet(&res, 1, 0, -s);
    matElementSet(&res, 1, 1, c);
    return res;
}
// TODO rotate3

pub fn scaleAxes3(x: f32, y: f32, z: f32) Mat4 {
    var res = eye4;
    matElementSet(&res, 0, 0, x);
    matElementSet(&res, 1, 1, y);
    matElementSet(&res, 2, 2, z);
    return res;
}
