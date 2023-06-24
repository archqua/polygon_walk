const std = @import("std");
const Allocator = std.mem.Allocator;
const math = std.math;

const sdl = @import("sdl2");

const Graphics = @import("graphics.zig");
const text = @import("text.zig");
const Color = @import("util").Color;

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
    bg_color_idle: Color.RGBAf,
    bg_color_focus: ?Color.RGBAf = null,
    txt_color_idle: Color.RGBAf = Color.RGBAf.black,
    txt_color_focus: ?Color.RGBAf = null,
    text: []const u8,
    _width: ?f32 = null,
    _height: ?f32 = null,
    text_scale: f32 = 1.0,
    margins: Margins = .{},

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
};

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

    pub fn findButton(
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
};

pub const EventHandler = struct {
    pub const ClipBoardUpdateCallback = *const fn(event: sdl.Event.CommonEvent, data: usize) anyerror!void;
    pub const AppDidEnterBackgroundCallback = *const fn(event: sdl.Event.CommonEvent, data: usize) anyerror!void;
    pub const AppDidEnterForegroundCallback = *const fn(event: sdl.Event.CommonEvent, data: usize) anyerror!void;
    pub const AppWillEnterForegroundCallback = *const fn(event: sdl.Event.CommonEvent, data: usize) anyerror!void;
    pub const AppWillEnterBackgroundCallback = *const fn(event: sdl.Event.CommonEvent, data: usize) anyerror!void;
    pub const AppLowMemoryCallback = *const fn(event: sdl.Event.CommonEvent, data: usize) anyerror!void;
    pub const AppTerminatingCallback = *const fn(event: sdl.Event.CommonEvent, data: usize) anyerror!void;
    pub const RenderTargetsResetCallback = *const fn(event: sdl.Event.CommonEvent, data: usize) anyerror!void;
    pub const RenderDeviceResetCallback = *const fn(event: sdl.Event.CommonEvent, data: usize) anyerror!void;
    pub const KeyMapChangedCallback = *const fn(event: sdl.Event.CommonEvent, data: usize) anyerror!void;
    pub const DisplayCallback = *const fn(event: sdl.Event.DisplayEvent, data: usize) anyerror!void;
    pub const WindowCallback = *const fn(event: sdl.WindowEvent, data: usize) anyerror!void;
    pub const KeyDownCallback = *const fn(event: sdl.KeyboardEvent, data: usize) anyerror!void;
    pub const KeyUpCallback = *const fn(event: sdl.KeyboardEvent, data: usize) anyerror!void;
    pub const TextEditingCallback = *const fn(event: sdl.Event.TextEditingEvent, data: usize) anyerror!void;
    pub const TextInputCallback = *const fn(event: sdl.Event.TextInputEvent, data: usize) anyerror!void;
    pub const MouseMotionCallback = *const fn(event: sdl.MouseMotionEvent, data: usize) anyerror!void;
    pub const MouseButtonDownCallback = *const fn(event: sdl.MouseButtonEvent, data: usize) anyerror!void;
    pub const MouseButtonUpCallback = *const fn(event: sdl.MouseButtonEvent, data: usize) anyerror!void;
    pub const MouseWheelCallback = *const fn(event: sdl.MouseWheelEvent, data: usize) anyerror!void;
    pub const JoyAxisMotionCallback = *const fn(event: sdl.JoyAxisEvent, data: usize) anyerror!void;
    pub const JoyBallMotionCallback = *const fn(event: sdl.JoyBallEvent, data: usize) anyerror!void;
    pub const JoyHatMotionCallback = *const fn(event: sdl.JoyHatEvent, data: usize) anyerror!void;
    pub const JoyButtonDownCallback = *const fn(event: sdl.JoyButtonEvent, data: usize) anyerror!void;
    pub const JoyButtonUpCallback = *const fn(event: sdl.JoyButtonEvent, data: usize) anyerror!void;
    pub const JoyDeviceAddedCallback = *const fn(event: sdl.Event.JoyDeviceEvent, data: usize) anyerror!void;
    pub const JoyDeviceRemovedCallback = *const fn(event: sdl.Event.JoyDeviceEvent, data: usize) anyerror!void;
    pub const ControllerAxisMotionCallback = *const fn(event: sdl.ControllerAxisEvent, data: usize) anyerror!void;
    pub const ControllerButtonDownCallback = *const fn(event: sdl.ControllerButtonEvent, data: usize) anyerror!void;
    pub const ControllerButtonUpCallback = *const fn(event: sdl.ControllerButtonEvent, data: usize) anyerror!void;
    pub const ControllerDeviceAddedCallback = *const fn(event: sdl.Event.ControllerDeviceEvent, data: usize) anyerror!void;
    pub const ControllerDeviceRemovedCallback = *const fn(event: sdl.Event.ControllerDeviceEvent, data: usize) anyerror!void;
    pub const ControllerDeviceRemappedCallback = *const fn(event: sdl.Event.ControllerDeviceEvent, data: usize) anyerror!void;
    pub const AudioDeviceAddedCallback = *const fn(event: sdl.Event.AudioDeviceEvent, data: usize) anyerror!void;
    pub const AudioDeviceRemovedCallback = *const fn(event: sdl.Event.AudioDeviceEvent, data: usize) anyerror!void;
    pub const SensorUpdateCallback = *const fn(event: sdl.Event.SensorEvent, data: usize) anyerror!void;
    pub const QuitCallback = *const fn(event: sdl.Event.QuitEvent, data: usize) anyerror!void;
    pub const SysWmCallback = *const fn(event: sdl.Event.SysWMEvent, data: usize) anyerror!void;
    pub const FingerDownCallback = *const fn(event: sdl.Event.TouchFingerEvent, data: usize) anyerror!void;
    pub const FingerUpCallback = *const fn(event: sdl.Event.TouchFingerEvent, data: usize) anyerror!void;
    pub const FingerMotionCallback = *const fn(event: sdl.Event.TouchFingerEvent, data: usize) anyerror!void;
    pub const MultiGestureCallback = *const fn(event: sdl.Event.MultiGestureEvent, data: usize) anyerror!void;
    pub const DollarGestureCallback = *const fn(event: sdl.Event.DollarGestureEvent, data: usize) anyerror!void;
    pub const DollarRecordCallback = *const fn(event: sdl.Event.DollarGestureEvent, data: usize) anyerror!void;
    pub const DropFileCallback = *const fn(event: sdl.Event.DropEvent, data: usize) anyerror!void;
    pub const DropTextCallback = *const fn(event: sdl.Event.DropEvent, data: usize) anyerror!void;
    pub const DropBeginCallback = *const fn(event: sdl.Event.DropEvent, data: usize) anyerror!void;
    pub const DropCompleteCallback = *const fn(event: sdl.Event.DropEvent, data: usize) anyerror!void;
    pub const UserCallback = *const fn(event: sdl.UserEvent, data: usize) anyerror!void;

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
    pub fn handle(self: EventHandler, event: sdl.Event, data: usize) !bool {
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
};
