const std = @import("std");
const Allocator = std.mem.Allocator;
const math = std.math;

const sdl = @import("sdl2");
const sdlvk = @import("sdlvk.zig");

const Graphics = @import("graphics.zig");
const text = @import("text.zig");
const color = @import("util").color;

pub const Offset = text.Offset; // struct {
//     x: f32 = 0.0,
//     y: f32 = 0.0,
// };
pub const Shape = struct {
    width: f32 = 1.0,
    height: f32 = 1.0,
};
pub const Rect = struct {
    offset: Offset = .{},
    shape: Shape = .{},
};
pub const Margins = struct {
    top: f32 = 0.0,
    left: f32 = 0.0,
};

pub const Button = struct {
    pub const Callback = *const fn(data: ?*anyopaque) anyerror!void;

    bg_color_idle: color.RGBAf,
    bg_color_focus: ?color.RGBAf = null,
    txt_color_idle: color.RGBAf = color.RGBAf.black,
    txt_color_focus: ?color.RGBAf = null,
    text: []const u8,
    _width: ?f32 = null,
    _height: ?f32 = null,
    text_scale: f32 = 1.0,
    margins: Margins = .{},
    callback: ?Callback = null,
    force_inactive: bool = false,

    pub fn naturalWidth(self: Button) f32 {
        const scale = text.Scale{.y = self.text_scale, .flipy=true};
        const scalex = scale.scalex();
        return 2.0*scalex*(1.0 + self.margins.left) +
            2.4*scalex*@intToFloat(f32, self.text.len-1);
    }
    pub fn naturalHeight(self: Button) f32 {
        const scale = text.Scale{.y = self.text_scale, .flipy=true};
        const scaley = -scale.scaley();
        return 2.0*scaley*(1.0 + self.margins.top);
    }
    pub fn width(self: Button) f32 {
        return self._width orelse self.naturalWidth();
    }
    pub fn height(self: Button) f32 {
        return self._height orelse self.naturalHeight();
    }

    pub fn drawables(
        self: *const Button, offset: Offset, ator: Allocator, mode: enum{idle, focus},
    ) ![2]Graphics.PrimitiveObject {
        const scale = text.Scale{.y = self.text_scale, .flipy=true};
        const scalex = scale.scalex();
        const scaley = -scale.scaley();
        const width_ = self.width();
        const height_ = self.height();

        const string = try text.stringFromChars(self.text, ator);
        defer ator.free(string);
        const string_offset = Offset{
            .x = offset.x + scalex*(1.0 + self.margins.left),
            .y = offset.y + scaley*(1.0 + self.margins.top),
        };
        const s_drawable = try text.string2drawable(
            string,
            switch (mode) {
                .idle => self.txt_color_idle,
                .focus => if (self.txt_color_focus) |cf| cf else self.txt_color_idle,
            },
            string_offset,
            scale,
            ator,
        );
        errdefer ator.free(s_drawable.vertices);
        errdefer ator.free(s_drawable.indices);

        const bg_vertices = try ator.alloc(Graphics.Vertex, 4);
        errdefer ator.free(bg_vertices);
        const bg_indices = try ator.alloc(Graphics.Index, 6);
        errdefer ator.free(bg_indices);
        const bg_color = switch (mode) {
            .idle => self.bg_color_idle,
            .focus => if (self.bg_color_focus) |cf| cf else self.bg_color_idle,
        };
        bg_vertices[0] = .{
            .pos = .{offset.x, offset.y},
            .col = .{bg_color.r, bg_color.g, bg_color.b},
        };
        bg_vertices[1] = .{
            .pos = .{width_ + offset.x, offset.y},
            .col = .{bg_color.r, bg_color.g, bg_color.b},
        };
        bg_vertices[2] = .{
            .pos = .{width_ + offset.x, height_ + offset.y},
            .col = .{bg_color.r, bg_color.g, bg_color.b},
        };
        bg_vertices[3] = .{
            .pos = .{offset.x, height_ + offset.y},
            .col = .{bg_color.r, bg_color.g, bg_color.b},
        };
        bg_indices[0] = 0;
        bg_indices[1] = 1;
        bg_indices[2] = 3;
        bg_indices[3] = 1;
        bg_indices[4] = 2;
        bg_indices[5] = 3;
        const bg_drawable = Graphics.PrimitiveObject{
            .vertices=bg_vertices, .indices=bg_indices,
        };

        return .{bg_drawable, s_drawable};
    }
}; // Button

pub const Menu = struct {
    // TODO add horizontal orientation
    buttons: []Button,
    interval: f32 = 0.0,
    active_button: u32 = ~@as(u32, 0),

    pub const Alignment = enum {
        left, center, right,
    };

    pub fn drawables(
        self: *const Menu,
        alignment: Alignment, offset: Offset,
        ator: Allocator,
    ) ![2]Graphics.PrimitiveCollection {
        var accum_height: f32 = 0.0;
        var res = [2]Graphics.PrimitiveCollection{.{}, .{}};
        errdefer {
            for (&res) |*r| {
                while (r.popFirst()) |node| {
                    ator.free(node.data.indices);
                    ator.free(node.data.vertices);
                }
            }
        }

        for (self.buttons, 0..) |b, i| {
            const b_width = b.width();
            const b_height = b.height();
            const b_offset = .{
                .x = switch (alignment) {
                    .left => offset.x,
                    .center => offset.x - 0.5*b_width,
                    .right => offset.x - b_width,
                },
                .y = offset.y + accum_height,
            };
            accum_height += b_height + self.interval;
            const b_obj = try b.drawables(
                b_offset, ator,
                if (self.active_button == @intCast(u32, i))
                    .focus
                else
                    .idle,
            );
            errdefer {
                for (b_obj) |bo| {
                    ator.free(bo.indices);
                    ator.free(bo.vertices);
                }
            }
            for (b_obj, 0..) |bo, j| {
                const node = try ator.create(Graphics.PrimitiveCollection.Node);
                node.data = bo;
                res[j].prepend(node);
            }
        }

        return res;
    }

    pub fn locateButton(
        self: *const Menu,
        alignment: Alignment, offset: Offset,
        x: f32, y: f32,
    ) ?u32 {
        var accum_height: f32 = offset.y;
        for (self.buttons, 0..) |button, i| {
            const bw = button.width();
            const bh = button.height();
            const l = switch (alignment) {
                .left => offset.x,
                .center => offset.x - 0.5*bw,
                .right => offset.x - bw,
            };
            const r = switch (alignment) {
                .left => offset.x + bw,
                .center => offset.x + 0.5*bw,
                .right => offset.x,
            };
            const t = accum_height;
            const b = accum_height + bh;
            if (l < x and x < r and t < y and y < b) {
                return @intCast(u32, i);
            }
            accum_height += bh + self.interval;
        }
        return null;
    }
    pub fn focusButton(self: *Menu, btn_idx: u32) bool {
        if (self.active_button != btn_idx and
            btn_idx < self.buttons.len and
            !self.buttons[btn_idx].force_inactive
        ) {
            self.active_button = btn_idx;
            return true;
        } else {
            return false;
        }
    }
    pub fn activeButton(self: *const Menu) ?*const Button {
        if (self.active_button < self.buttons.len and !self.buttons[self.active_button].force_inactive)
            return &self.buttons[self.active_button]
        else
            return null;
    }
    pub fn focusNext(self: *Menu) bool {
        if (self.active_button == ~@as(u32, 0))
            self.active_button = 0;
        var candidate = self.active_button +% 1;
        if (candidate >= self.buttons.len)
            return false;
        while (self.buttons[candidate].force_inactive) {
            candidate +%= 1;
            if (candidate >= self.buttons.len)
                return false;
        }
        return self.focusButton(candidate);
    }
    pub fn focusPrev(self: *Menu) bool {
        if (self.active_button == ~@as(u32, 0))
            self.active_button = @intCast(u32, self.buttons.len) -% 1;
        var candidate = self.active_button -% 1;
        if (candidate >= self.buttons.len)
            return false;
        while (self.buttons[candidate].force_inactive) {
            candidate -%= 1;
            if (candidate >= self.buttons.len)
                return false;
        }
        return self.focusButton(candidate);
    }
    pub fn focusNextWrap(self: *Menu) bool {
        if (self.buttons.len == 0)
            return false;
        var candidate = self.active_button +% 1;
        if (candidate >= self.buttons.len)
            candidate %= @intCast(u32, self.buttons.len);
        while (self.buttons[candidate].force_inactive) {
            candidate +%= 1;
            if (candidate >= self.buttons.len)
                return false;
        }
        return self.focusButton(candidate);
    }
    pub fn focusPrevWrap(self: *Menu) bool {
        if (self.buttons.len == 0)
            return false;
        var candidate = self.active_button -% 1;
        if (candidate >= self.buttons.len)
            candidate = @intCast(u32, self.buttons.len) -% 1;
        while (self.buttons[candidate].force_inactive) {
            candidate -%= 1;
            if (candidate >= self.buttons.len)
                return false;
        }
        return self.focusButton(candidate);
    }

    pub const HandlerData = struct {
        menu: *Menu,
        alignment: Alignment,
        offset: Offset,
        window_width: usize,
        window_height: usize,
        button_data: []?*anyopaque,
    };

    pub const handler = EventHandler{
        .mouseMotionCb = struct {
            fn fun(m_motion: sdl.MouseMotionEvent, data: ?*anyopaque) !void {
                const info = @ptrCast(*HandlerData, @alignCast(@alignOf(HandlerData), data.?));
                const half_width = 0.5 * @intToFloat(f32, info.window_width);
                const half_height = 0.5 * @intToFloat(f32, info.window_height);
                const aspect = half_width / half_height;
                const cur_x: f32 = aspect * (@intToFloat(f32, m_motion.x) - half_width) / half_width;
                const cur_y: f32 = (@intToFloat(f32, m_motion.y) - half_height) / half_height;
                if (info.menu.locateButton(info.alignment, info.offset, cur_x, cur_y)) |btn_idx| {
                    if (info.menu.focusButton(btn_idx))
                        std.debug.print("button \"{s}\" focus\n", .{info.menu.buttons[btn_idx].text});
                }
            }
        }.fun,
        .mouseButtonDownCb = struct {
            fn fun(m_down: sdl.MouseButtonEvent, data: ?*anyopaque) !void {
                const info = @ptrCast(*HandlerData, @alignCast(@alignOf(HandlerData), data.?));
                const half_width = 0.5 * @intToFloat(f32, info.window_width);
                const half_height = 0.5 * @intToFloat(f32, info.window_height);
                const aspect = half_width / half_height;
                const cur_x: f32 = aspect * (@intToFloat(f32, m_down.x) - half_width) / half_width;
                const cur_y: f32 = (@intToFloat(f32, m_down.y) - half_height) / half_height;
                if (info.menu.locateButton(info.alignment, info.offset, cur_x, cur_y)) |btn_idx| {
                    if (btn_idx == info.menu.active_button) {
                        std.debug.print("button \"{s}\" press\n", .{info.menu.buttons[btn_idx].text});
                        if (info.menu.buttons[btn_idx].callback) |cb| {
                            try cb(info.button_data[btn_idx]);
                        }
                    } else {
                        if (info.menu.focusButton(btn_idx))
                            std.debug.print("button \"{s}\" focus\n", .{info.menu.buttons[btn_idx].text});
                    }
                }
            }
        }.fun,
        .keyDownCb = struct {
            fn fun(k_down: sdl.KeyboardEvent, data: ?*anyopaque) !void {
                const info = @ptrCast(*HandlerData, @alignCast(@alignOf(HandlerData), data.?));
                switch (k_down.scancode) {
                    // .q => {
                    //     if (k_down.modifiers.get(.left_control) or k_down.modifiers.get(.right_control)) {
                    //         // this is not super fair, but since this basically quits, we can do so
                    //         const ev_type = try sdl.registerEvents(1);
                    //         try sdl.pushEvent(ev_type, sdlvk.quit_event_code, null, null);
                    //     }
                    // },
                    .@"return" => {
                        if (info.menu.activeButton()) |ab| {
                            if (ab.callback) |cb| {
                                try cb(info.button_data[info.menu.active_button]);
                            }
                        }
                    },
                    .j, .down => {
                        // if (info.menu.focusNext())
                        if (info.menu.focusNextWrap())
                            std.debug.print(
                                "button \"{s}\" focus\n",
                                .{info.menu.activeButton().?.text},
                            );
                    },
                    .k, .up => {
                        // if (info.menu.focusPrev())
                        if (info.menu.focusPrevWrap())
                            std.debug.print(
                                "button \"{s}\" focus\n",
                                .{info.menu.activeButton().?.text},
                            );
                    },
                    else => {},
                }
            }
        }.fun,
    };
    pub const handler_qexit = handler.override(.{
        .keyDownCb = struct {
            fn fun(k_down: sdl.KeyboardEvent, data: ?*anyopaque) !void {
                // const info = @ptrCast(*HandlerData, @alignCast(@alignOf(HandlerData), data.?));
                switch (k_down.scancode) {
                    .q => {
                        if (k_down.modifiers.get(.left_control) or k_down.modifiers.get(.right_control)) {
                            // this is not super fair, but since this basically quits, we can do so
                            const ev_type = try sdl.registerEvents(1);
                            try sdl.pushEvent(ev_type, sdlvk.quit_event_code, null, null);
                        }
                    },
                    else => return handler.keyDownCb.?(k_down, data),
                }
            }
        }.fun,
    });
    pub fn bindButtons(comptime _handler: EventHandler, comptime bindings: anytype) EventHandler {
        return _handler.override(.{
            .keyDownCb = struct {
                fn fun(k_down: sdl.KeyboardEvent, data: ?*anyopaque) !void {
                    const info = @ptrCast(*HandlerData, @alignCast(@alignOf(HandlerData), data.?));
                    for (bindings, 0..) |binding, button_idx| {
                        if (binding) |scancode| {
                            if (k_down.scancode == scancode) {
                                if (info.menu.active_button != button_idx) {
                                    info.menu.active_button = @intCast(u32, button_idx);
                                    return;
                                } else {
                                    return info.menu.buttons[button_idx].callback.?(info.button_data[button_idx]);
                                }
                            }
                        }
                    }
                    return _handler.keyDownCb.?(k_down, data);
                }
            }.fun,
        });
    }
}; // Menu

pub fn Menus(comptime names: []const []const u8) type {
    const n_menus = names.len;
    comptime var fields = [1]std.builtin.Type.StructField{undefined} ** n_menus;
    for (&fields, names) |*field, name| {
        field.* = .{
            .name = name,
            .type = Menu,
            .default_value = null,
            .is_comptime = false,
            .alignment = @alignOf(Menu),
        };
    }
    return @Type(std.builtin.Type{ .Struct = .{
        .layout = .Auto,
        .fields = &fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}
pub fn MenusEnum(comptime names: []const []const u8) type {
    const n_menus = names.len;
    comptime var fields = [1]std.builtin.Type.EnumField{undefined} ** n_menus;
    inline for (&fields, names, 0..) |*field, name, i| {
        field.* = .{
            .name = name,
            .value = i,
        };
    }
    return @Type(std.builtin.Type{ .Enum = .{
        .tag_type = u32,
        .fields = &fields,
        .decls = &.{},
        .is_exhaustive = true,
    } });
}

pub const GameHandlerData = struct {
    right_magn: f32 = 0.0,
    fwd_magn:   f32 = 0.0,
    cur_x: i32 = 0,
    cur_y: i32 = 0,
    lmb: bool = false,
    rmb: bool = false,
    // TODO wheel
    extra_data: ?*anyopaque = null,
};
pub const game_handler = EventHandler{
    .mouseMotionCb = struct {
        fn fun(m_motion: sdl.MouseMotionEvent, data: ?*anyopaque) !void {
            const info = @ptrCast(*GameHandlerData, @alignCast(@alignOf(GameHandlerData), data.?));
            info.cur_x = m_motion.x;
            info.cur_y = m_motion.y;
        }
    }.fun,
    .mouseButtonDownCb = struct {
        fn fun(m_button: sdl.MouseButtonEvent, data: ?*anyopaque) !void {
            const info = @ptrCast(*GameHandlerData, @alignCast(@alignOf(GameHandlerData), data.?));
            switch (m_button.button) {
                .left => info.lmb = true,
                .right => info.rmb = true,
                else => {},
            }
        }
    }.fun,
    .mouseButtonUpCb = struct {
        fn fun(m_button: sdl.MouseButtonEvent, data: ?*anyopaque) !void {
            const info = @ptrCast(*GameHandlerData, @alignCast(@alignOf(GameHandlerData), data.?));
            switch (m_button.button) {
                .left => info.lmb = false,
                .right => info.rmb = false,
                else => {},
            }
        }
    }.fun,
    .keyDownCb = struct {
        fn fun(k_down: sdl.KeyboardEvent, data: ?*anyopaque) !void {
            const info = @ptrCast(*GameHandlerData, @alignCast(@alignOf(GameHandlerData), data.?));
            switch (k_down.scancode) {
                .w, .up => {
                    if (info.fwd_magn < 0.0)
                        info.fwd_magn += 1.0
                    else
                        info.fwd_magn = 1.0;
                },
                .s, .down => {
                    if (info.fwd_magn > 0.0)
                        info.fwd_magn -= 1.0
                    else
                        info.fwd_magn = -1.0;
                },
                .d, .right => {
                    if (info.right_magn < 0.0)
                        info.right_magn += 1.0
                    else
                        info.right_magn = 1.0;
                },
                .a, .left => {
                    if (info.right_magn > 0.0)
                        info.right_magn -= 1.0
                    else
                        info.right_magn = -1.0;
                },
                else => {},
            }
        }
    }.fun,
    .keyUpCb = struct {
        fn fun(k_up: sdl.KeyboardEvent, data: ?*anyopaque) !void {
            const info = @ptrCast(*GameHandlerData, @alignCast(@alignOf(GameHandlerData), data.?));
            switch (k_up.scancode) {
                .w, .up => {
                    if (info.fwd_magn > 0.0)
                        info.fwd_magn -= 1.0
                    else
                        info.fwd_magn = -1.0;
                },
                .s, .down => {
                    if (info.fwd_magn < 0.0)
                        info.fwd_magn += 1.0
                    else
                        info.fwd_magn = 1.0;
                },
                .d, .right => {
                    if (info.right_magn > 0.0)
                        info.right_magn -= 1.0
                    else
                        info.right_magn = -1.0;
                },
                .a, .left => {
                    if (info.right_magn < 0.0)
                        info.right_magn += 1.0
                    else
                        info.right_magn = 1.0;
                },
                else => {},
            }
        }
    }.fun,
};
pub const no_wasd_game_handler = game_handler.override(.{
    .keyDownCb = struct {
        fn fun(k_down: sdl.KeyboardEvent, data: ?*anyopaque) !void {
            const info = @ptrCast(*GameHandlerData, @alignCast(@alignOf(GameHandlerData), data.?));
            switch (k_down.scancode) {
                .up => {
                    if (info.fwd_magn < 0.0)
                        info.fwd_magn += 1.0
                    else
                        info.fwd_magn = 1.0;
                },
                .down => {
                    if (info.fwd_magn > 0.0)
                        info.fwd_magn -= 1.0
                    else
                        info.fwd_magn = -1.0;
                },
                .right => {
                    if (info.right_magn < 0.0)
                        info.right_magn += 1.0
                    else
                        info.right_magn = 1.0;
                },
                .left => {
                    if (info.right_magn > 0.0)
                        info.right_magn -= 1.0
                    else
                        info.right_magn = -1.0;
                },
                else => {},
            }
        }
    }.fun,
    .keyUpCb = struct {
        fn fun(k_up: sdl.KeyboardEvent, data: ?*anyopaque) !void {
            const info = @ptrCast(*GameHandlerData, @alignCast(@alignOf(GameHandlerData), data.?));
            switch (k_up.scancode) {
                .up => {
                    if (info.fwd_magn > 0.0)
                        info.fwd_magn -= 1.0
                    else
                        info.fwd_magn = -1.0;
                },
                .down => {
                    if (info.fwd_magn < 0.0)
                        info.fwd_magn += 1.0
                    else
                        info.fwd_magn = 1.0;
                },
                .right => {
                    if (info.right_magn > 0.0)
                        info.right_magn -= 1.0
                    else
                        info.right_magn = -1.0;
                },
                .left => {
                    if (info.right_magn < 0.0)
                        info.right_magn += 1.0
                    else
                        info.right_magn = 1.0;
                },
                else => {},
            }
        }
    }.fun,
});


pub const EventHandler = struct {
    pub const ClipBoardUpdateCallback = *const fn(event: sdl.Event.CommonEvent, data: ?*anyopaque) anyerror!void;
    pub const AppDidEnterBackgroundCallback = *const fn(event: sdl.Event.CommonEvent, data: ?*anyopaque) anyerror!void;
    pub const AppDidEnterForegroundCallback = *const fn(event: sdl.Event.CommonEvent, data: ?*anyopaque) anyerror!void;
    pub const AppWillEnterForegroundCallback = *const fn(event: sdl.Event.CommonEvent, data: ?*anyopaque) anyerror!void;
    pub const AppWillEnterBackgroundCallback = *const fn(event: sdl.Event.CommonEvent, data: ?*anyopaque) anyerror!void;
    pub const AppLowMemoryCallback = *const fn(event: sdl.Event.CommonEvent, data: ?*anyopaque) anyerror!void;
    pub const AppTerminatingCallback = *const fn(event: sdl.Event.CommonEvent, data: ?*anyopaque) anyerror!void;
    pub const RenderTargetsResetCallback = *const fn(event: sdl.Event.CommonEvent, data: ?*anyopaque) anyerror!void;
    pub const RenderDeviceResetCallback = *const fn(event: sdl.Event.CommonEvent, data: ?*anyopaque) anyerror!void;
    pub const KeyMapChangedCallback = *const fn(event: sdl.Event.CommonEvent, data: ?*anyopaque) anyerror!void;
    pub const DisplayCallback = *const fn(event: sdl.Event.DisplayEvent, data: ?*anyopaque) anyerror!void;
    pub const WindowCallback = *const fn(event: sdl.WindowEvent, data: ?*anyopaque) anyerror!void;
    pub const KeyDownCallback = *const fn(event: sdl.KeyboardEvent, data: ?*anyopaque) anyerror!void;
    pub const KeyUpCallback = *const fn(event: sdl.KeyboardEvent, data: ?*anyopaque) anyerror!void;
    pub const TextEditingCallback = *const fn(event: sdl.Event.TextEditingEvent, data: ?*anyopaque) anyerror!void;
    pub const TextInputCallback = *const fn(event: sdl.Event.TextInputEvent, data: ?*anyopaque) anyerror!void;
    pub const MouseMotionCallback = *const fn(event: sdl.MouseMotionEvent, data: ?*anyopaque) anyerror!void;
    pub const MouseButtonDownCallback = *const fn(event: sdl.MouseButtonEvent, data: ?*anyopaque) anyerror!void;
    pub const MouseButtonUpCallback = *const fn(event: sdl.MouseButtonEvent, data: ?*anyopaque) anyerror!void;
    pub const MouseWheelCallback = *const fn(event: sdl.MouseWheelEvent, data: ?*anyopaque) anyerror!void;
    pub const JoyAxisMotionCallback = *const fn(event: sdl.JoyAxisEvent, data: ?*anyopaque) anyerror!void;
    pub const JoyBallMotionCallback = *const fn(event: sdl.JoyBallEvent, data: ?*anyopaque) anyerror!void;
    pub const JoyHatMotionCallback = *const fn(event: sdl.JoyHatEvent, data: ?*anyopaque) anyerror!void;
    pub const JoyButtonDownCallback = *const fn(event: sdl.JoyButtonEvent, data: ?*anyopaque) anyerror!void;
    pub const JoyButtonUpCallback = *const fn(event: sdl.JoyButtonEvent, data: ?*anyopaque) anyerror!void;
    pub const JoyDeviceAddedCallback = *const fn(event: sdl.Event.JoyDeviceEvent, data: ?*anyopaque) anyerror!void;
    pub const JoyDeviceRemovedCallback = *const fn(event: sdl.Event.JoyDeviceEvent, data: ?*anyopaque) anyerror!void;
    pub const ControllerAxisMotionCallback = *const fn(event: sdl.ControllerAxisEvent, data: ?*anyopaque) anyerror!void;
    pub const ControllerButtonDownCallback = *const fn(event: sdl.ControllerButtonEvent, data: ?*anyopaque) anyerror!void;
    pub const ControllerButtonUpCallback = *const fn(event: sdl.ControllerButtonEvent, data: ?*anyopaque) anyerror!void;
    pub const ControllerDeviceAddedCallback = *const fn(event: sdl.Event.ControllerDeviceEvent, data: ?*anyopaque) anyerror!void;
    pub const ControllerDeviceRemovedCallback = *const fn(event: sdl.Event.ControllerDeviceEvent, data: ?*anyopaque) anyerror!void;
    pub const ControllerDeviceRemappedCallback = *const fn(event: sdl.Event.ControllerDeviceEvent, data: ?*anyopaque) anyerror!void;
    pub const AudioDeviceAddedCallback = *const fn(event: sdl.Event.AudioDeviceEvent, data: ?*anyopaque) anyerror!void;
    pub const AudioDeviceRemovedCallback = *const fn(event: sdl.Event.AudioDeviceEvent, data: ?*anyopaque) anyerror!void;
    pub const SensorUpdateCallback = *const fn(event: sdl.Event.SensorEvent, data: ?*anyopaque) anyerror!void;
    pub const QuitCallback = *const fn(event: sdl.Event.QuitEvent, data: ?*anyopaque) anyerror!void;
    pub const SysWmCallback = *const fn(event: sdl.Event.SysWMEvent, data: ?*anyopaque) anyerror!void;
    pub const FingerDownCallback = *const fn(event: sdl.Event.TouchFingerEvent, data: ?*anyopaque) anyerror!void;
    pub const FingerUpCallback = *const fn(event: sdl.Event.TouchFingerEvent, data: ?*anyopaque) anyerror!void;
    pub const FingerMotionCallback = *const fn(event: sdl.Event.TouchFingerEvent, data: ?*anyopaque) anyerror!void;
    pub const MultiGestureCallback = *const fn(event: sdl.Event.MultiGestureEvent, data: ?*anyopaque) anyerror!void;
    pub const DollarGestureCallback = *const fn(event: sdl.Event.DollarGestureEvent, data: ?*anyopaque) anyerror!void;
    pub const DollarRecordCallback = *const fn(event: sdl.Event.DollarGestureEvent, data: ?*anyopaque) anyerror!void;
    pub const DropFileCallback = *const fn(event: sdl.Event.DropEvent, data: ?*anyopaque) anyerror!void;
    pub const DropTextCallback = *const fn(event: sdl.Event.DropEvent, data: ?*anyopaque) anyerror!void;
    pub const DropBeginCallback = *const fn(event: sdl.Event.DropEvent, data: ?*anyopaque) anyerror!void;
    pub const DropCompleteCallback = *const fn(event: sdl.Event.DropEvent, data: ?*anyopaque) anyerror!void;
    pub const UserCallback = *const fn(event: sdl.UserEvent, data: ?*anyopaque) anyerror!void;

    clipBoardUpdateCb: ?ClipBoardUpdateCallback = null,
    appDidEnterBackgroundCb: ?AppDidEnterBackgroundCallback = null,
    appDidEnterForegroundCb: ?AppDidEnterForegroundCallback = null,
    appWillEnterForegroundCb: ?AppWillEnterForegroundCallback = null,
    appWillEnterBackgroundCb: ?AppWillEnterBackgroundCallback = null,
    appLowMemoryCb: ?AppLowMemoryCallback = null,
    appTerminatingCb: ?AppTerminatingCallback = null,
    renderTargetsResetCb: ?RenderTargetsResetCallback = null,
    renderDeviceResetCb: ?RenderDeviceResetCallback = null,
    keyMapChangedCb: ?KeyMapChangedCallback = null,
    displayCb: ?DisplayCallback = null,
    windowCb: ?WindowCallback = null,
    keyDownCb: ?KeyDownCallback = null,
    keyUpCb: ?KeyUpCallback = null,
    textEditingCb: ?TextEditingCallback = null,
    textInputCb: ?TextInputCallback = null,
    mouseMotionCb: ?MouseMotionCallback = null,
    mouseButtonDownCb: ?MouseButtonDownCallback = null,
    mouseButtonUpCb: ?MouseButtonUpCallback = null,
    mouseWheelCb: ?MouseWheelCallback = null,
    joyAxisMotionCb: ?JoyAxisMotionCallback = null,
    joyBallMotionCb: ?JoyBallMotionCallback = null,
    joyHatMotionCb: ?JoyHatMotionCallback = null,
    joyButtonDownCb: ?JoyButtonDownCallback = null,
    joyButtonUpCb: ?JoyButtonUpCallback = null,
    joyDeviceAddedCb: ?JoyDeviceAddedCallback = null,
    joyDeviceRemovedCb: ?JoyDeviceRemovedCallback = null,
    controllerAxisMotionCb: ?ControllerAxisMotionCallback = null,
    controllerButtonDownCb: ?ControllerButtonDownCallback = null,
    controllerButtonUpCb: ?ControllerButtonUpCallback = null,
    controllerDeviceAddedCb: ?ControllerDeviceAddedCallback = null,
    controllerDeviceRemovedCb: ?ControllerDeviceRemovedCallback = null,
    controllerDeviceRemappedCb: ?ControllerDeviceRemappedCallback = null,
    audioDeviceAddedCb: ?AudioDeviceAddedCallback = null,
    audioDeviceRemovedCb: ?AudioDeviceRemovedCallback = null,
    sensorUpdateCb: ?SensorUpdateCallback = null,
    quitCb: ?QuitCallback = null,
    sysWmCb: ?SysWmCallback = null,
    fingerDownCb: ?FingerDownCallback = null,
    fingerUpCb: ?FingerUpCallback = null,
    fingerMotionCb: ?FingerMotionCallback = null,
    multiGestureCb: ?MultiGestureCallback = null,
    dollarGestureCb: ?DollarGestureCallback = null,
    dollarRecordCb: ?DollarRecordCallback = null,
    dropFileCb: ?DropFileCallback = null,
    dropTextCb: ?DropTextCallback = null,
    dropBeginCb: ?DropBeginCallback = null,
    dropCompleteCb: ?DropCompleteCallback = null,
    userCb: ?UserCallback = null,

    /// returns `true` if appropriate callback was called
    pub fn handle(self: EventHandler, event: sdl.Event, data: ?*anyopaque) !bool {
        switch (event) {
            .clip_board_update => |e| if (self.clipBoardUpdateCb) |callback| {
                try callback(e, data);
                return true;
            },
            .app_did_enter_background => |e| if (self.appDidEnterBackgroundCb) |callback| {
                try callback(e, data);
                return true;
            },
            .app_did_enter_foreground => |e| if (self.appDidEnterForegroundCb) |callback| {
                try callback(e, data);
                return true;
            },
            .app_will_enter_foreground => |e| if (self.appWillEnterForegroundCb) |callback| {
                try callback(e, data);
                return true;
            },
            .app_will_enter_background => |e| if (self.appWillEnterBackgroundCb) |callback| {
                try callback(e, data);
                return true;
            },
            .app_low_memory => |e| if (self.appLowMemoryCb) |callback| {
                try callback(e, data);
                return true;
            },
            .app_terminating => |e| if (self.appTerminatingCb) |callback| {
                try callback(e, data);
                return true;
            },
            .render_targets_reset => |e| if (self.renderTargetsResetCb) |callback| {
                try callback(e, data);
                return true;
            },
            .render_device_reset => |e| if (self.renderDeviceResetCb) |callback| {
                try callback(e, data);
                return true;
            },
            .key_map_changed => |e| if (self.keyMapChangedCb) |callback| {
                try callback(e, data);
                return true;
            },
            .display => |e| if (self.displayCb) |callback| {
                try callback(e, data);
                return true;
            },
            .window => |e| if (self.windowCb) |callback| {
                try callback(e, data);
                return true;
            },
            .key_down => |e| if (self.keyDownCb) |callback| {
                try callback(e, data);
                return true;
            },
            .key_up => |e| if (self.keyUpCb) |callback| {
                try callback(e, data);
                return true;
            },
            .text_editing => |e| if (self.textEditingCb) |callback| {
                try callback(e, data);
                return true;
            },
            .text_input => |e| if (self.textInputCb) |callback| {
                try callback(e, data);
                return true;
            },
            .mouse_motion => |e| if (self.mouseMotionCb) |callback| {
                try callback(e, data);
                return true;
            },
            .mouse_button_down => |e| if (self.mouseButtonDownCb) |callback| {
                try callback(e, data);
                return true;
            },
            .mouse_button_up => |e| if (self.mouseButtonUpCb) |callback| {
                try callback(e, data);
                return true;
            },
            .mouse_wheel => |e| if (self.mouseWheelCb) |callback| {
                try callback(e, data);
                return true;
            },
            .joy_axis_motion => |e| if (self.joyAxisMotionCb) |callback| {
                try callback(e, data);
                return true;
            },
            .joy_ball_motion => |e| if (self.joyBallMotionCb) |callback| {
                try callback(e, data);
                return true;
            },
            .joy_hat_motion => |e| if (self.joyHatMotionCb) |callback| {
                try callback(e, data);
                return true;
            },
            .joy_button_down => |e| if (self.joyButtonDownCb) |callback| {
                try callback(e, data);
                return true;
            },
            .joy_button_up => |e| if (self.joyButtonUpCb) |callback| {
                try callback(e, data);
                return true;
            },
            .joy_device_added => |e| if (self.joyDeviceAddedCb) |callback| {
                try callback(e, data);
                return true;
            },
            .joy_device_removed => |e| if (self.joyDeviceRemovedCb) |callback| {
                try callback(e, data);
                return true;
            },
            .controller_axis_motion => |e| if (self.controllerAxisMotionCb) |callback| {
                try callback(e, data);
                return true;
            },
            .controller_button_down => |e| if (self.controllerButtonDownCb) |callback| {
                try callback(e, data);
                return true;
            },
            .controller_button_up => |e| if (self.controllerButtonUpCb) |callback| {
                try callback(e, data);
                return true;
            },
            .controller_device_added => |e| if (self.controllerDeviceAddedCb) |callback| {
                try callback(e, data);
                return true;
            },
            .controller_device_removed => |e| if (self.controllerDeviceRemovedCb) |callback| {
                try callback(e, data);
                return true;
            },
            .controller_device_remapped => |e| if (self.controllerDeviceRemappedCb) |callback| {
                try callback(e, data);
                return true;
            },
            .audio_device_added => |e| if (self.audioDeviceAddedCb) |callback| {
                try callback(e, data);
                return true;
            },
            .audio_device_removed => |e| if (self.audioDeviceRemovedCb) |callback| {
                try callback(e, data);
                return true;
            },
            .sensor_update => |e| if (self.sensorUpdateCb) |callback| {
                try callback(e, data);
                return true;
            },
            .quit => |e| if (self.quitCb) |callback| {
                try callback(e, data);
                return true;
            },
            .sys_wm => |e| if (self.sysWmCb) |callback| {
                try callback(e, data);
                return true;
            },
            .finger_down => |e| if (self.fingerDownCb) |callback| {
                try callback(e, data);
                return true;
            },
            .finger_up => |e| if (self.fingerUpCb) |callback| {
                try callback(e, data);
                return true;
            },
            .finger_motion => |e| if (self.fingerMotionCb) |callback| {
                try callback(e, data);
                return true;
            },
            .multi_gesture => |e| if (self.multiGestureCb) |callback| {
                try callback(e, data);
                return true;
            },
            .dollar_gesture => |e| if (self.dollarGestureCb) |callback| {
                try callback(e, data);
                return true;
            },
            .dollar_record => |e| if (self.dollarRecordCb) |callback| {
                try callback(e, data);
                return true;
            },
            .drop_file => |e| if (self.dropFileCb) |callback| {
                try callback(e, data);
                return true;
            },
            .drop_text => |e| if (self.dropTextCb) |callback| {
                try callback(e, data);
                return true;
            },
            .drop_begin => |e| if (self.dropBeginCb) |callback| {
                try callback(e, data);
                return true;
            },
            .drop_complete => |e| if (self.dropCompleteCb) |callback| {
                try callback(e, data);
                return true;
            },
            .user => |e| if (self.userCb) |callback| {
                try callback(e, data);
                return true;
            },
        }
        return false;
    }

    pub fn override(self: EventHandler, comptime callbacks: anytype) EventHandler {
        var res = self;
        inline for (@typeInfo(@TypeOf(callbacks)).Struct.fields) |field| {
            @field(res, field.name) = @field(callbacks, field.name);
        }
        return res;
    }
};
