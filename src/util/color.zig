pub const RGBAi = packed struct {
    const Int = u8;
    r: Int = 0,
    g: Int = 0,
    b: Int = 0,
    a: Int = 255,

    pub fn toRGBAf(self: RGBAi) RGBAf {
        return .{
            .r = @intToFloat(RGBAf.Float, self.r) / 255.0,
            .g = @intToFloat(RGBAf.Float, self.g) / 255.0,
            .b = @intToFloat(RGBAf.Float, self.b) / 255.0,
            .a = @intToFloat(RGBAf.Float, self.a) / 255.0,
        };
    }
    pub fn toRGBAhf(self: RGBAi) RGBAhf {
        return .{
            .r = @intToFloat(RGBAhf.HalfFloat, self.r) / 255.0,
            .g = @intToFloat(RGBAhf.HalfFloat, self.g) / 255.0,
            .b = @intToFloat(RGBAhf.HalfFloat, self.b) / 255.0,
            .a = @intToFloat(RGBAhf.HalfFloat, self.a) / 255.0,
        };
    }

    pub const black = RGBAi{.r = 0,   .g = 0,   .b = 0};
    pub const white = RGBAi{.r = 255, .g = 255, .b = 255};
    pub const grey  = RGBAi{.r = 128, .g = 128, .b = 128};
    pub const red   = RGBAi{.r = 128, .g = 0,   .b = 0};
    pub const green = RGBAi{.r = 0,   .g = 128, .b = 0};
    pub const blue  = RGBAi{.r = 0,   .g = 0,   .b = 128};
};

pub const RGBAf = packed struct {
    const Float = f32;
    r: Float = 0.0,
    g: Float = 0.0,
    b: Float = 0.0,
    a: Float = 1.0,

    pub fn toRGBAi(self: RGBAf) RGBAi {
        return .{
            .r = @floatToInt(RGBAi.Int, self.r * 255.0),
            .g = @floatToInt(RGBAi.Int, self.g * 255.0),
            .b = @floatToInt(RGBAi.Int, self.b * 255.0),
            .a = @floatToInt(RGBAi.Int, self.a * 255.0),
        };
    }
    pub fn toRGBAhf(self: RGBAf) RGBAhf {
        return .{
            .r = @floatCast(RGBAhf.HalfFloat, self.r),
            .g = @floatCast(RGBAhf.HalfFloat, self.g),
            .b = @floatCast(RGBAhf.HalfFloat, self.b),
            .a = @floatCast(RGBAhf.HalfFloat, self.a),
        };
    }

    pub const black = RGBAf{.r = 0.0, .g = 0.0, .b = 0.0};
    pub const white = RGBAf{.r = 1.0, .g = 1.0, .b = 1.0};
    pub const grey  = RGBAf{.r = 0.5, .g = 0.5, .b = 0.5};
    pub const red   = RGBAf{.r = 0.5, .g = 0.0, .b = 0.0};
    pub const green = RGBAf{.r = 0.0, .g = 0.5, .b = 0.0};
    pub const blue  = RGBAf{.r = 0.0, .g = 0.0, .b = 0.5};
};

pub const RGBAhf = packed struct {
    const HalfFloat = f16;
    r: HalfFloat = 0.0,
    g: HalfFloat = 0.0,
    b: HalfFloat = 0.0,
    a: HalfFloat = 1.0,

    pub fn toRGBAi(self: RGBAhf) RGBAi {
        return .{
            .r = @floatToInt(RGBAi.Int, self.r * 255.0),
            .g = @floatToInt(RGBAi.Int, self.g * 255.0),
            .b = @floatToInt(RGBAi.Int, self.b * 255.0),
            .a = @floatToInt(RGBAi.Int, self.a * 255.0),
        };
    }
    pub fn toRGBAf(self: RGBAhf) RGBAf {
        return .{
            .r = @floatCast(RGBAf.Float, self.r),
            .g = @floatCast(RGBAf.Float, self.g),
            .b = @floatCast(RGBAf.Float, self.b),
            .a = @floatCast(RGBAf.Float, self.a),
        };
    }

    pub const black = RGBAhf{.r = 0.0, .g = 0.0, .b = 0.0};
    pub const white = RGBAhf{.r = 1.0, .g = 1.0, .b = 1.0};
    pub const grey  = RGBAhf{.r = 0.5, .g = 0.5, .b = 0.5};
    pub const red   = RGBAhf{.r = 0.5, .g = 0.0, .b = 0.0};
    pub const green = RGBAhf{.r = 0.0, .g = 0.5, .b = 0.0};
    pub const blue  = RGBAhf{.r = 0.0, .g = 0.0, .b = 0.5};
};
