const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
pub const debug = switch (builtin.mode) {
    .Debug, .ReleaseSafe => true,
    else => false,
};

pub const Dim = u32;
pub fn Vec(comptime T: type, comptime dim: Dim) type {
    return [dim]T;
}
pub fn Mat(comptime T: type, comptime dim: Dim) type {
    return [dim*dim]T;
}
// pub fn vecAllocFn(comptime T: type, comptime dim: Dim) fn (Allocator) error{OutOfMemory}!*Vec(T, dim) {
//     const V = Vec(T, dim);
//     return struct {
//         fn fun(ator: Allocator) !*V {
//             const slice = try ator.alloc(T, dim);
//             return @ptrCast(*V, slice);
//         }
//     }.fun;
// }
// pub fn vecFreeFn(comptime T: type, comptime dim: Dim) fn (Allocator, *Vec(T, dim)) void {
//     const V = Vec(T, dim);
//     return struct {
//         fn fun(ator: Allocator, v: *V) void {
//             const slice: []T = v;
//             return ator.free(slice);
//         }
//     }.fun;
// }
pub const Mat2 = Mat(f32, 2);
pub const Mat3 = Mat(f32, 3);
pub const Mat4 = Mat(f32, 4);
pub const Vec2 = Vec(f32, 2);
pub const Vec3 = Vec(f32, 3);
pub const Vec4 = Vec(f32, 4);

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
pub fn subInplace(lhs: anytype, rhs: anytype) void {
    for (lhs, rhs) |*l, r| {
        l.* -= r;
    }
}
pub fn negInplace(x: anytype) void {
    for (x) |*dst| {
        dst.* = -dst.*;
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
pub fn sub(lhs: anytype, rhs: anytype) @TypeOf(lhs) {
    var res = lhs;
    subInplace(&res, rhs);
    return res;
}
pub fn neg(x: anytype) @TypeOf(x) {
    var res = x;
    negInplace(&res);
    return res;
}

pub fn eql(x: anytype, y: anytype) bool {
    for (x, y) |xv, yv| {
        if (xv != yv)
            return false;
    }
    return true;
}
pub fn eqlApproxAbs(x: anytype, y: anytype, tol: VecFieldType(@TypeOf(x))) bool {
    for (x, y) |xv, yv| {
        if (abs(xv - yv) > tol)
            return false;
    }
    return true;
}

pub const NormType = enum {
    @"1", @"2", inf,
};
pub fn VecFieldType(comptime V: type) type {
    switch (@typeInfo(V)) {
        .Array => |array_info| {
            return array_info.child;
        },
        .Pointer => |pointer_info| {
            switch (pointer_info.size) {
                .Many, .Slice, .C => {
                    return pointer_info.child;
                },
                .One => {
                    switch (@typeInfo(pointer_info.child)) {
                        .Array => |child_array_info| {
                            return child_array_info.child;
                        },
                        else => @compileError("single item pointer can only be vector if it is pointer to array"),
                    }
                },
            }
        },
        .Struct => |struct_info| {
            if (struct_info.is_tuple) {
                if (struct_info.len < 1)
                    @compileError("can't deduce vector field type from empty tuple");
                const fields = struct_info.fields;
                const res = fields[0].type;
                for (fields) |field| {
                    if (field.type != res)
                        @compileError("can't deduce vector field type from tuple with different types");
                }
                return res;
            } else {
                @compileError("struct can only be vector if it is tuple");
            }
        },
        else => @compileError("can't deduce field type of vector: wrong vector type"),
    }
}
fn abs(x: anytype) @TypeOf(x) {
    return switch (@typeInfo(@TypeOf(x))) {
        .Float => @fabs(x),
        .Int => |int_info| switch (int_info.signedness) {
            .signed => std.math.absInt(x),
            else => x,
        },
        .ComptimeInt, .ComptimeFloat => if (x >= 0) x else -x,
        else => @compileError("can't take absolute value of smth different from int or float"),
    };
}
pub fn norm(x: anytype, t: NormType) VecFieldType(@TypeOf(x)) {
    if (x.len == 0)
        return 0;
    const F = VecFieldType(@TypeOf(x));
    switch (t) {
        .@"1" => {
            var res: F = 0;
            for (x) |v| {
                res += abs(v);
            }
            return res;
        },
        .@"2" => {
            var square: F = 0;
            for (x) |v| {
                square += v*v;
            }
            return std.math.sqrt(square);
        },
        .inf => {
            var max: F = 0;
            for (x) |v| {
                max = @max(max, abs(v));
            }
            return max;
        },
    }
}
pub fn unitizeInplace(x: anytype) void {
    const n = norm(x, .@"2");
    if (debug) {
        const nn = 1/n;
        // TODO log instead of panic
        if (std.math.isInf(nn))
            @panic("division by zero when trying to unitize vector");
    }
    scaleInplace(x, 1/n);
}
pub fn unitize(x: anytype) @TypeOf(x) {
    var res = x;
    unitizeInplace(&res);
    return res;
}

pub fn rot2(vec: anytype, ang: anytype) @TypeOf(vec) {
    const c = @cos(ang);
    const s = @sin(ang);
    return .{
        c*vec[0] - s*vec[1],
        s*vec[0] + c*vec[1],
    };
}
pub fn rotInplace2(vec: anytype, ang: anytype) void {
    // naive no-copy implementation triggers UB
    vec.* = rot2(vec.*, ang);
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
pub const eye4 = Mat4{
    1.0, 0.0, 0.0, 0.0,
    0.0, 1.0, 0.0, 0.0,
    0.0, 0.0, 1.0, 0.0,
    0.0, 0.0, 0.0, 1.0,
};
pub const zeros4 = Mat4{
    0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0,
};
/// column-major
pub fn matElementAccessFn(comptime T: type, comptime dim: Dim) fn (Mat(T, dim), Dim, Dim) T {
    const Mx = Mat(T, dim);
    return struct {
        fn fun(mat: Mx, row: Dim, col: Dim) T {
            return mat[dim*col + row];
        }
    }.fun;
}
/// column-major
pub fn matElementSetFn(comptime T: type, comptime dim: Dim) fn (*Mat(T, dim), Dim, Dim, T) void {
    const Mx = Mat(T, dim);
    return struct {
        fn fun(mat: *Mx, row: Dim, col: Dim, val: T) void {
            mat[dim*col + row] = val;
        }
    }.fun;
}
pub const matElementAccess2 = matElementAccessFn(f32, 2);
pub const matElementSet2 = matElementSetFn(f32, 2);
pub const matElementAccess3 = matElementAccessFn(f32, 3);
pub const matElementSet3 = matElementSetFn(f32, 3);
pub const matElementAccess4 = matElementAccessFn(f32, 4);
pub const matElementSet4 = matElementSetFn(f32, 4);
pub fn matmulFn(comptime T: type, comptime dim: Dim) fn (Mat(T, dim), Mat(T, dim)) Mat(T, dim) {
    const Mx = Mat(T, dim);
    const matElementAccess = matElementAccessFn(T, dim);
    const matElementSet = matElementSetFn(T, dim);
    return struct {
        fn fun(lhs: Mx, rhs: Mx) Mx {
            var res = [1]T{0} ** (dim*dim);
            for (0..dim) |_i| {
                const i = @intCast(Dim, _i);
                for (0..dim) |_j| {
                    const j = @intCast(Dim, _j);
                    var val: f32 = 0.0;
                    for (0..dim) |_k| {
                        const k = @intCast(Dim, _k);
                        val += matElementAccess(lhs, i, k) * matElementAccess(rhs, k, j);
                    }
                    matElementSet(&res, i, j, val);
                }
            }
            return res;
        }
    }.fun;
}
pub const matmul2 = matmulFn(f32, 2);
pub const matmul3 = matmulFn(f32, 3);
pub const matmul4 = matmulFn(f32, 4);

pub fn dotFn(comptime T: type, comptime dim: Dim) fn (Vec(T, dim), Vec(T, dim)) T {
    const V = Vec(T, dim);
    return struct {
        fn fun(lhs: V, rhs: V) T {
            var res: T = 0;
            for (&lhs, &rhs) |l, r| {
                res += l*r;
            }
            return res;
        }
    }.fun;
}
pub const dot2 = dotFn(f32, 2);
pub const dot3 = dotFn(f32, 3);
pub const dot4 = dotFn(f32, 4);
pub fn cross2Fn(comptime T: type) fn (Vec(T, 2), Vec(T, 2)) T {
    const V = Vec(T, 2);
    return struct {
        fn fun(lhs: V, rhs: V) T {
            return lhs[0]*rhs[1] - lhs[1]*rhs[0];
        }
    }.fun;
}
pub const cross2 = cross2Fn(f32);
pub fn cross3Fn(comptime T: type) fn (Vec(T, 3), Vec(T, 3)) Vec(T, 3) {
    const V = Vec(T, 3);
    return struct {
        fn fun(lhs: V, rhs: V) V {
            return .{
                 lhs[1]*rhs[2] - lhs[2]*rhs[1],
                -lhs[0]*rhs[2] + lhs[2]*lhs[0],
                 lhs[0]*rhs[1] - lhs[1]*rhs[0],
            };
        }
    }.fun;
}
pub const cross3 = cross3Fn(f32);

pub fn det2Fn(comptime T: type) fn (Mat(T, 2)) T {
    const Mx = Mat(T, 2);
    const matElementAccess = matElementAccessFn(T, 2);
    return struct {
        fn fun(mat: Mx) T {
            return matElementAccess(mat, 0, 0) * matElementAccess(mat, 1, 1)
                - matElementAccess(mat, 0, 1) * matElementAccess(mat, 1, 0);
        }
    }.fun;
}
pub const det2 = det2Fn(f32);
pub fn det3Fn(comptime T: type) fn (Mat(T, 3)) T {
    const Mx = Mat(T, 2);
    const matElementAccess = matElementAccessFn(T, 3);
    return struct {
        fn fun(mat: Mx) T {
            return matElementAccess(mat, 0, 0) * (
                    matElementAccess(mat, 1, 1) * matElementAccess(mat, 2, 2)
                    - matElementAccess(mat, 1, 2) * matElementAccess(mat, 2, 1)
                )
                - matElementAccess(mat, 0, 1) * (
                    matElementAccess(mat, 1, 0) * matElementAccess(mat, 2, 2)
                    - matElementAccess(mat, 1, 2) * matElementAccess(mat, 2, 0)
                )
                + matElementAccess(mat, 0, 2) * (
                    matElementAccess(mat, 1, 0) * matElementAccess(2, 1)
                    - matElementAccess(mat, 1, 1) * matElementAccess(mat, 2, 0)
                );
        }
    }.fun;
}
pub const det3 = det3Fn(f32);

pub fn translate24(shift: Vec2) Mat4 {
    var res = eye4;
    matElementSet4(&res, 0, 3, shift[0]);
    matElementSet4(&res, 1, 3, shift[1]);
    return res;
}
pub fn translate34(shift: Vec3) Mat4 {
    var res = eye4;
    matElementSet4(&res, 0, 3, shift[0]);
    matElementSet4(&res, 1, 3, shift[1]);
    matElementSet4(&res, 2, 3, shift[2]);
    return res;
}

pub fn rotate24(rad: f32) Mat4 {
    const c = @cos(rad);
    const s = @sin(rad);
    var res = eye4;
    matElementSet4(&res, 0, 0, c);
    matElementSet4(&res, 0, 1, s);
    matElementSet4(&res, 1, 0, -s);
    matElementSet4(&res, 1, 1, c);
    return res;
}
// TODO rotate3

pub fn scaleAxes34(x: f32, y: f32, z: f32) Mat4 {
    var res = eye4;
    matElementSet4(&res, 0, 0, x);
    matElementSet4(&res, 1, 1, y);
    matElementSet4(&res, 2, 2, z);
    return res;
}
