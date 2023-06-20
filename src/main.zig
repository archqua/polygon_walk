const std = @import("std");
const builtin = @import("builtin");

const vk = @import("vk.zig");
const sdl = @import("sdl2");
const sdlvk = @import("sdlvk.zig");

const Graphics = @import("graphics.zig");
const text = @import("text.zig");
const util = @import("util");
const alg = @import("alg.zig");

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

    const menu = UI.Menu{
        .buttons = try ator.alloc(UI.Button, 3),
        .interval = 0.1,
    };
    defer ator.free(menu.buttons);
    menu.buttons[0] = UI.Button{
        .bg_color = util.Color.RGBAf{.r = 0.0, .g = 0.8, .b = 0.0},
        .txt_color = util.Color.RGBAf.black,
        .text = "play",
        .text_scale = 0.15,
        .margins = .{.top = 0.4, .left = 0.64},
    };
    menu.buttons[1] = UI.Button{
        .bg_color = util.Color.RGBAf{.r = 0.0, .g = 0.7, .b = 0.7},
        .txt_color = util.Color.RGBAf.black,
        .text = "settings",
        .text_scale = 0.15,
        .margins = .{.top = 0.4, .left = 0.64},
    };
    menu.buttons[2] = UI.Button{
        .bg_color = util.Color.RGBAf{.r = 0.8, .g = 0.0, .b = 0.0},
        .txt_color = util.Color.RGBAf.black,
        .text = "quit",
        .text_scale = 0.15,
        .margins = .{.top = 0.4, .left = 0.64},
    };
    var drawables = try menu.drawables(.center, .{.x = 0.0, .y = -0.7}, ator);
    defer {
        for (&drawables) |*l| {
            while (l.popFirst()) |n| {
                ator.free(n.data.indices);
                ator.free(n.data.vertices);
                ator.destroy(n);
            }
        }
    }
    graphics.drawable_state.lists[ui_obj_index] = drawables[0];
    graphics.drawable_state.lists[ui_fg_index]  = drawables[1];

    const cap_info = graphics.updateDrawableStateInfo();
    try graphics.updateVertexIndexBuffer(cap_info);
    // ubo
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

    MAIN_LOOP: while (true) {
        // while (sdl.pollEvent()) |event| {
        // waiting for even 1 ms makes it not waste computation under easy load
        while (sdl.waitEventTimeout(1)) |event| {
            switch (event) {
                .quit => break :MAIN_LOOP,
                else => {},
            }
        }
        const img_idx = try graphics.beginFrame(~@as(u64, 0));
        try graphics.renderFrame(img_idx.?);
    }
}


const testing = std.testing;

test "reference all declarations recursively" {
    comptime {
        @setEvalBranchQuota(1000);  // default is 1000
        testing.refAllDeclsRecursive(@This());
    }
}
