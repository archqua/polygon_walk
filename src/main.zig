const std = @import("std");
const builtin = @import("builtin");

const vk = @import("vk.zig");
const sdl = @import("sdl2");
const sdlvk = @import("sdlvk.zig");

const Graphics = @import("graphics.zig");
const text = @import("text.zig");
const util = @import("util");
const alg = @import("alg.zig");
const shape = @import("shape.zig");
const rigid = @import("rigid.zig");

const UI = @import("ui.zig");

const application_name = "Polygon Walk";

const n_drawable_layers = 6;
const bg_index = 0;
const obj_index = 1;
const fg_index = 2;
const ui_bg_index = 3;
const ui_obj_index = 4;
const ui_fg_index = 5;


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ator = gpa.allocator();

    var graphics = try Graphics.init(
        .{
            .application_name = application_name,
            .window = .{
                .width = 1280, .height = 720,
            },
        },
        ator,
    );
    defer graphics.terminate(true) catch
        @panic("failed to terminate graphics engine");


    // set main menu
    var active_menu = &menus.main;
    var active_button: u32 = active_menu.active_button;
    var switched_into_game = false;

    var cur_menu_drawables =
        try active_menu.drawables(.center, .{.x = 0.0, .y = -0.7}, ator);
    defer {
        for (&cur_menu_drawables) |*l| {
            while (l.popFirst()) |n| {
                ator.free(n.data.indices);
                ator.free(n.data.vertices);
                ator.destroy(n);
            }
        }
    }
    graphics.drawable_state.lists[ui_obj_index] = cur_menu_drawables[0];
    graphics.drawable_state.lists[ui_fg_index]  = cur_menu_drawables[1];
    var cap_info = graphics.updateDrawableStateInfo();
    try graphics.updateVertexIndexBuffer(cap_info);

    // basically set static camera
    const ubos = [_]Graphics.UniformBufferObject{
        .{.proj = alg.scaleAxes3(720.0/1280.0, 1.0, 1.0)},
        .{.proj = alg.scaleAxes3(720.0/1280.0, 1.0, 1.0)},
    };
    const _data = try graphics.vkd.mapMemory(graphics.device,
        graphics.uniform_buffer.memory,
        0, graphics.uniform_buffer.size,
        .{},
    );
    const data = @ptrCast([*]u8, _data.?);
    @memcpy(data, std.mem.sliceAsBytes(&ubos));
    // no need to flush coherent memory
    graphics.vkd.unmapMemory(graphics.device, graphics.uniform_buffer.memory);

    // player variables
    var player_rot: f32 = 0.0;
    var player_shape0 = shape.Shape2{ .triangle = .{
        .{ -0.1,  0.1 },
        .{  0.0, -0.2 },
        .{  0.1,  0.1 },
    }};
    try shape.apply2(.{.rotation = -0.5*std.math.pi}, &player_shape0);
    var player_shape = player_shape0;
    var player_drawable = try shape.colorize2(
        player_shape, .triangle_list, .{ .Value = util.color.RGBAf.white }, ator,
    );
    defer {
        ator.free(player_drawable.indices);
        ator.free(player_drawable.vertices);
    }
    var player_node = Graphics.PrimitiveCollection.Node{
        .next = null,
        .data = player_drawable,
    };
    
    var player_body = rigid.Body2{};
    var time: i64 = std.time.milliTimestamp();


    MAIN_LOOP: while (true) {
        // while (sdl.pollEvent()) |event| {
        // waiting for even 1 ms makes it not waste computation under easy load
        while (sdl.waitEventTimeout(1)) |event| {
            switch (event) {
                .quit => break :MAIN_LOOP,
                .user => |u| if (u.code == sdlvk.quit_event_code) break: MAIN_LOOP,
                else => {
                    _ = try handler_and_data.handler.handle(event, handler_and_data.data);
                },
            }
        }
        switch (handler_and_data.handler_type) {
            .menu => {
                time = std.time.milliTimestamp();
                const hdata = @ptrCast(*UI.Menu.HandlerData,
                    @alignCast(@alignOf(UI.Menu.HandlerData), handler_and_data.data.?));
                if (switched_into_game) {
                    active_menu = hdata.menu;
                    active_button = hdata.menu.active_button;
                    cur_menu_drawables =
                        try active_menu.drawables(hdata.alignment, hdata.offset, ator);
                    graphics.drawable_state.lists[ui_obj_index] = cur_menu_drawables[0];
                    graphics.drawable_state.lists[ui_fg_index]  = cur_menu_drawables[1];

                    const _cap_info = graphics.updateDrawableStateInfo();
                    try graphics.updateVertexIndexBuffer(_cap_info);

                    switched_into_game = false;

                } else if (active_menu != hdata.menu or active_button != hdata.menu.active_button) {
                    active_menu = hdata.menu;
                    active_button = hdata.menu.active_button;
                    var trash_drawables = cur_menu_drawables;
                    cur_menu_drawables =
                        try active_menu.drawables(hdata.alignment, hdata.offset, ator);
                    defer {
                        for (&trash_drawables) |*l| {
                            while (l.popFirst()) |n| {
                                ator.free(n.data.indices);
                                ator.free(n.data.vertices);
                                ator.destroy(n);
                            }
                        }
                    }
                    graphics.drawable_state.lists[ui_obj_index] = cur_menu_drawables[0];
                    graphics.drawable_state.lists[ui_fg_index]  = cur_menu_drawables[1];

                    const _cap_info = graphics.updateDrawableStateInfo();
                    try graphics.updateVertexIndexBuffer(_cap_info);
                }
            },
            .game => {
                const new_time = std.time.milliTimestamp();
                // this relies on time update at .menu => switch branch
                const dt = 1.0e-03 * @intToFloat(f32, new_time - time);
                time = new_time;
                if (!switched_into_game) {
                    // get rid of menu
                    for (&cur_menu_drawables) |*l| {
                        while (l.popFirst()) |n| {
                            ator.free(n.data.indices);
                            ator.free(n.data.vertices);
                            ator.destroy(n);
                        }
                    }
                    graphics.drawable_state.lists[ui_obj_index] = cur_menu_drawables[0];
                    graphics.drawable_state.lists[ui_fg_index]  = cur_menu_drawables[1];
                    
                    // make sure player is drawn
                    graphics.drawable_state.lists[obj_index] = .{.first = &player_node};

                    switched_into_game = true;
                }

                const mouse_state = sdl.getMouseState();
                const cur_x = (@intToFloat(f32, mouse_state.x) - 640.0) / 360.0;
                const cur_y = (@intToFloat(f32, mouse_state.y) - 360.0) / 360.0;
                const cur_d = std.math.sqrt(cur_x*cur_x + cur_y*cur_y);
                if (cur_d > 1.0e-04) {
                    const c = cur_x / cur_d;
                    var cur_ang = std.math.acos(c);
                    if (cur_y > 0.0)
                        cur_ang *= -1.0;

                    var diff = cur_ang - player_rot;
                    if (@fabs(diff) > std.math.pi)
                        diff += -std.math.sign(diff) * 2.0 * std.math.pi;
                    const torque = 12.0*(
                        (if (@fabs(diff) > 1.0e-04) 2.0*std.math.sign(diff) else 0.0) + diff + 0.5*std.math.sign(diff)*diff*diff
                        - player_body.ang_velocity / (0.5 + @fabs(diff) + 2.0*diff*diff)
                    );
                    const ang_vel_shift = player_body.exertTorsion(torque, dt);
                    const player_velocities = player_body.midPointStep(.{0.0, 0.0}, ang_vel_shift);
                    player_rot += player_velocities.angular * dt;
                    if (@fabs(player_rot) > std.math.pi)
                        player_rot += -std.math.sign(player_rot) * 2.0 * std.math.pi;
                    try shape.cpy2(&player_shape, player_shape0);
                    try shape.apply2(.{.rotation = player_rot}, &player_shape);
                    try shape.colorizeInplace2(
                        player_shape, .triangle_list, .{.Value = util.color.RGBAf.white}, player_drawable,
                    );
                    if (std.math.isNan(player_shape.triangle[0][0]))
                        break: MAIN_LOOP;
                }
            },
        }

        const _cap_info = graphics.updateDrawableStateInfo();
        try graphics.updateVertexIndexBuffer(_cap_info);

        const img_idx = try graphics.beginFrame(~@as(u64, 0));
        try graphics.renderFrame(img_idx.?);
    }
}


const menu_names = [_][]const u8{
    "main", "settings", "in_game",
};
const Menus = UI.Menus(&menu_names);
const MenusEnum = UI.MenusEnum(&menu_names);
fn menuByEnum(_menus: *Menus, en: MenusEnum) *UI.Menu {
    return switch (en) {
        .main => &_menus.main,
        .settings => &_menus.settings,
        .in_game => &_menus.in_game,
    };
}

const HandlerType = enum {
    menu, game,
};
const HandlerAndData = struct {
    handler: UI.EventHandler,
    handler_type: HandlerType,
    data: ?*anyopaque,
};
var handler_and_data = HandlerAndData{
    .handler = menu_handler,
    .handler_type = .menu,
    .data = &main_menu_handler_data,
};
const menu_handler = UI.Menu.handler_qexit;
var main_menu_buttons = [_]UI.Button{
    .{
        .bg_color_idle = util.color.RGBAf{.r = 0.0, .g = 0.6, .b = 0.0},
        .bg_color_focus = util.color.RGBAf{.r = 0.1, .g = 1.0, .b = 0.1},
        .txt_color_idle = util.color.RGBAf.black,
        .text = "play",
        .text_scale = 0.15,
        .margins = .{.top = 0.4, .left = 0.64},
        .callback = struct {
            fn fun(data: ?*anyopaque) !void {
                _ = data;
                handler_and_data.data = &game_handler_data;
                handler_and_data.handler = game_handler;
                handler_and_data.handler_type = .game;
            }
        }.fun,
    },
    .{
        .bg_color_idle = util.color.RGBAf{.r = 0.0, .g = 0.5, .b = 0.5},
        .bg_color_focus = util.color.RGBAf{.r = 0.1, .g = 0.9, .b = 0.9},
        .txt_color_idle = util.color.RGBAf.black,
        .text = "settings",
        .text_scale = 0.15,
        .margins = .{.top = 0.4, .left = 0.64},
        .callback = struct {
            fn fun(data: ?*anyopaque) !void {
                _ = data;
                handler_and_data.data = &settings_menu_handler_data;
            }
        }.fun,
    },
    .{
        .bg_color_idle = util.color.RGBAf{.r = 0.6, .g = 0.0, .b = 0.0},
        .bg_color_focus = util.color.RGBAf{.r = 1.0, .g = 0.1, .b = 0.1},
        .txt_color_idle = util.color.RGBAf.black,
        .text = "quit",
        .text_scale = 0.15,
        .margins = .{.top = 0.4, .left = 0.64},
        .callback = struct {
            fn fun(data: ?*anyopaque) !void {
                _  = data;
                // this is not super fair, but since this basically quits, we can do so
                const ev_type = try sdl.registerEvents(1);
                try sdl.pushEvent(ev_type, sdlvk.quit_event_code, null, null);
            }
        }.fun,
    },
};
var main_menu_button_data = [main_menu_buttons.len]?*anyopaque{null, null, null};
var main_menu_handler_data = UI.Menu.HandlerData{
    .menu = &menus.main,
    .alignment = .center,
    .offset = .{.x = 0.0, .y = -0.7},
    .window_width = 1280, .window_height = 720,
    .button_data = &main_menu_button_data,
};

var settings_menu_buttons = [_]UI.Button{
    .{
        .bg_color_idle = util.color.RGBAf{.r = 0.0, .g = 0.5, .b = 0.5},
        .bg_color_focus = util.color.RGBAf{.r = 0.1, .g = 0.9, .b = 0.9},
        .txt_color_idle = util.color.RGBAf.black,
        .text = "not available",
        .text_scale = 0.15,
        .margins = .{.top = 0.4, .left = 0.64},
        .force_inactive = true,
    },
    .{
        .bg_color_idle = util.color.RGBAf{.r = 0.5, .g = 0.0, .b = 0.5},
        .bg_color_focus = util.color.RGBAf{.r = 0.9, .g = 0.1, .b = 0.9},
        .txt_color_idle = util.color.RGBAf.black,
        .text = "back",
        .text_scale = 0.15,
        .margins = .{.top = 0.4, .left = 0.64},
        .callback = struct {
            fn fun(data: ?*anyopaque) !void {
                _ = data;
                handler_and_data.data = &main_menu_handler_data;
            }
        }.fun,
    },
};
var settings_menu_button_data = [settings_menu_buttons.len]?*anyopaque{null, null};
var settings_menu_handler_data = UI.Menu.HandlerData{
    .menu = &menus.settings,
    .alignment = .center,
    .offset = .{.x = 0.0, .y = -0.5},
    .window_width = 1280, .window_height = 720,
    .button_data = &settings_menu_button_data,
};

var in_game_menu_buttons = [_]UI.Button{
    .{
        .bg_color_idle = util.color.RGBAf{.r = 0.5, .g = 0.0, .b = 0.5},
        .bg_color_focus = util.color.RGBAf{.r = 0.9, .g = 0.1, .b = 0.9},
        .txt_color_idle = util.color.RGBAf.black,
        .text = "main menu",
        .text_scale = 0.15,
        .margins = .{.top = 0.4, .left = 0.64},
        .callback = struct {
            fn fun(data: ?*anyopaque) !void {
                _ = data;
                handler_and_data.data = &main_menu_handler_data;
            }
        }.fun,
    },
    .{
        .bg_color_idle = util.color.RGBAf{.r = 0.0, .g = 0.6, .b = 0.0},
        .bg_color_focus = util.color.RGBAf{.r = 0.1, .g = 1.0, .b = 0.1},
        .txt_color_idle = util.color.RGBAf.black,
        .text = "back",
        .text_scale = 0.15,
        .margins = .{.top = 0.4, .left = 0.64},
        .callback = struct {
            fn fun(data: ?*anyopaque) !void {
                _ = data;
                handler_and_data.data = &game_handler_data;
                handler_and_data.handler = game_handler;
                handler_and_data.handler_type = .game;
            }
        }.fun,
    },
};
var in_game_menu_button_data = [in_game_menu_buttons.len]?*anyopaque{null, null};
var in_game_menu_handler_data = UI.Menu.HandlerData{
    .menu = &menus.in_game,
    .alignment = .center,
    .offset = .{.x = 0.0, .y = -0.5},
    .window_width = 1280, .window_height = 720,
    .button_data = &in_game_menu_button_data,
};

var menus = Menus{
    .main = UI.Menu{
        .buttons = &main_menu_buttons,
        .interval = 0.1,
    },
    .settings = UI.Menu{
        .buttons = &settings_menu_buttons,
        .interval = 0.1,
    },
    .in_game = UI.Menu{
        .buttons = &in_game_menu_buttons,
        .interval = 0.1,
    },
};

const ExtraGameHandlerData = struct {
    esc_pressed: bool = false,
};
var game_handler_data = UI.GameHandlerData{
    .extra_data = &game_handler_extra,
};
var game_handler_extra = ExtraGameHandlerData{};
const game_handler = UI.game_handler.override(.{
    .keyDownCb = struct {
        fn fun(k_down: sdl.KeyboardEvent, data: ?*anyopaque) !void {
            const info = @ptrCast(*UI.GameHandlerData,
                @alignCast(@alignOf(UI.GameHandlerData), data.?));
            const extra_info = @ptrCast(*ExtraGameHandlerData,
                @alignCast(@alignOf(ExtraGameHandlerData), info.extra_data.?));
            switch (k_down.scancode) {
                .escape => {
                    extra_info.esc_pressed = true;
                    handler_and_data.data = &in_game_menu_handler_data;
                    handler_and_data.handler = menu_handler;
                    handler_and_data.handler_type = .menu;
                },
                else => return UI.game_handler.keyDownCb.?(k_down, data),
            }
        }
    }.fun,
    .keyUpCb = struct {
        fn fun(k_up: sdl.KeyboardEvent, data: ?*anyopaque) !void {
            const info = @ptrCast(*UI.GameHandlerData,
                @alignCast(@alignOf(UI.GameHandlerData), data.?));
            const extra_info = @ptrCast(*ExtraGameHandlerData,
                @alignCast(@alignOf(ExtraGameHandlerData), info.extra_data.?));
            switch (k_up.scancode) {
                .escape => extra_info.esc_pressed = false,
                else => return UI.game_handler.keyUpCb.?(k_up, data),
            }
        }
    }.fun,
});




const testing = std.testing;

test "reference all declarations recursively" {
    comptime {
        @setEvalBranchQuota(1000);  // default is 1000
        testing.refAllDeclsRecursive(@This());
    }
}

