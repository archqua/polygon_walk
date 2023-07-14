const math = @import("std").math;

pub const Mat2 = [4]f32;
pub const Mat3 = [9]f32;
pub const Mat4 = [16]f32;
pub const Vec2 = [2]f32;
pub const Vec3 = [3]f32;
pub const Vec4 = [4]f32;

pub fn addInplace(lhs: anytype, rhs: anytype) void {
    for (lhs, rhs) |*l, r| {
        l.* += r;
    }
}
pub fn scaleInplace(x: anytype, scalar: anytype) void {
    for (x) |*dst| {
        dst.* *= scalar;
    }
}
pub fn add(lhs: anytype, rhs: anytype) @TypeOf(lhs) {
    var res = lhs;
    addInplace(&res, rhs);
    return res;
}
pub fn scale(x: anytype, scalar: anytype) @TypeOf(x) {
    var res = x;
    scaleInplace(&res, scalar);
    return res;
}

pub const eye2 = Mat2{
    1.0, 0.0,
    0.0, 1.0,
};
pub const zeros2 = Mat2{
    0.0, 0.0,
    0.0, 0.0,
};
pub const eye3 = Mat3{
    1.0, 0.0, 0.0,
    0.0, 1.0, 0.0,
    0.0, 0.0, 1.0,
};
pub const zeros3 = Mat3{
    0.0, 0.0, 0.0,
    0.0, 0.0, 0.0,
    0.0, 0.0, 0.0,
};
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
pub fn matElementAccess2(mat: Mat2, row: u8, col: u8) f32 {
    return mat[row + 2*col];
}
pub fn matElementSet2(mat: *Mat2, row: u8, col: u8, val: f32) void {
    mat[row + 2*col] = val;
}
pub fn matElementAccess3(mat: Mat3, row: u8, col: u8) f32 {
    return mat[row + 3*col];
}
pub fn matElementSet3(mat: *Mat3, row: u8, col: u8, val: f32) void {
    mat[row + 3*col] = val;
}
pub fn matElementAccess4(mat: Mat4, row: u8, col: u8) f32 {
    return mat[row + 4*col];
}
pub fn matElementSet4(mat: *Mat4, row: u8, col: u8, val: f32) void {
    mat[row + 4*col] = val;
}
pub fn matmul2(lhs: Mat2, rhs: Mat2) Mat2 {
    var res = zeros2;
    for (0..2) |_i| {
        const i = @intCast(u8, _i);
        for (0..2) |_j| {
            const j = @intCast(u8, _j);
            var val: f32 = 0.0;
            for (0..2) |_k| {
                const k = @intCast(u8, _k);
                val += matElementAccess2(lhs, i, k) * matElementAccess2(rhs, k, j);
            }
            matElementSet2(&res, i, j, val);
        }
    }
    return res;
}
pub fn matmul3(lhs: Mat3, rhs: Mat3) Mat3 {
    var res = zeros3;
    for (0..3) |_i| {
        const i = @intCast(u8, _i);
        for (0..3) |_j| {
            const j = @intCast(u8, _j);
            var val: f32 = 0.0;
            for (0..3) |_k| {
                const k = @intCast(u8, _k);
                val += matElementAccess3(lhs, i, k) * matElementAccess3(rhs, k, j);
            }
            matElementSet3(&res, i, j, val);
        }
    }
    return res;
}
pub fn matmul4(lhs: Mat4, rhs: Mat4) Mat4 {
    var res = zeros4;
    for (0..4) |_i| {
        const i = @intCast(u8, _i);
        for (0..4) |_j| {
            const j = @intCast(u8, _j);
            var val: f32 = 0.0;
            for (0..4) |_k| {
                const k = @intCast(u8, _k);
                val += matElementAccess4(lhs, i, k) * matElementAccess4(rhs, k, j);
            }
            matElementSet4(&res, i, j, val);
        }
    }
    return res;
}

pub fn translate2(shift: Vec2) Mat4 {
    var res = eye4;
    matElementSet4(&res, 0, 3, shift[0]);
    matElementSet4(&res, 1, 3, shift[1]);
    return res;
}
pub fn translate3(shift: Vec3) Mat4 {
    var res = eye4;
    matElementSet4(&res, 0, 3, shift[0]);
    matElementSet4(&res, 1, 3, shift[1]);
    matElementSet4(&res, 2, 3, shift[2]);
    return res;
}

pub fn rotate2(rad: f32) Mat4 {
    const c = math.cos(rad);
    const s = math.sin(rad);
    var res = eye4;
    matElementSet4(&res, 0, 0, c);
    matElementSet4(&res, 0, 1, s);
    matElementSet4(&res, 1, 0, -s);
    matElementSet4(&res, 1, 1, c);
    return res;
}
// TODO rotate3

pub fn scaleAxes3(x: f32, y: f32, z: f32) Mat4 {
    var res = eye4;
    matElementSet4(&res, 0, 0, x);
    matElementSet4(&res, 1, 1, y);
    matElementSet4(&res, 2, 2, z);
    return res;
}
