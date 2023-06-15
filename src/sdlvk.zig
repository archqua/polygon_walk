const c = @cImport({
    @cInclude("SDL.h");
    @cInclude("SDL_vulkan.h");
    @cInclude("vulkan/vulkan.h");
});
const sdl = @import("sdl2");
const vk = @import("vulkan");

const std = @import("std");
const Allocator = std.mem.Allocator;

/// SDL.zig doesn't provide vulkan compatibility with sdl

pub fn createSurface(
    window: sdl.Window,
    instance: vk.Instance,
) error{SDLVkSurfaceCreationFail}!vk.SurfaceKHR {
    var surface: vk.SurfaceKHR = undefined;
    const status = c.SDL_Vulkan_CreateSurface(
        @ptrCast(*c.SDL_Window, window.ptr),  // this pointer cast is quirky as fuck
        @intToPtr(c.VkInstance, @enumToInt(instance)),
        @ptrCast(*c.VkSurfaceKHR, &surface),
    );
    if (status != c.SDL_TRUE) {
        return error.SDLVkSurfaceCreationFail;
    } else {
        return surface;
    }
}

pub fn countInstanceExtensions(window: sdl.Window)
error{NoSDLVkInstanceExtensions}!c_uint {
    var count: c_uint = undefined;
    const status = c.SDL_Vulkan_GetInstanceExtensions(
        // window.ptr,  // type check fails somehow
        @ptrCast(*c.SDL_Window, window.ptr),  // this pointer cast is quirky as fuck
        &count, null,
    );
    if (status != c.SDL_TRUE)
        return error.NoSDLVkInstanceExtensions;
    return count;
}
pub fn fillInstanceExtensions(window: sdl.Window, dst: [][*:0]const u8) !void {
    var count = try countInstanceExtensions(window);
    if (@intCast(usize, count) > dst.len)
        return error.Overflow;
    const ptr = @ptrCast([*c][*c]const u8, dst.ptr);
    const status = c.SDL_Vulkan_GetInstanceExtensions(
        // window.ptr,  // type check fails somehow
        @ptrCast(*c.SDL_Window, window.ptr),  // this pointer cast is quirky as fuck
        &count, ptr,
    );
    if (status != c.SDL_TRUE)
        return error.NoSDLVkInstanceExtensions;
}

const vkGetInstanceProcAddr =
    *const fn (vk.Instance, [*:0]const u8) callconv(.C) vk.PfnVoidFunction;
pub fn getVkGetInstanceProcAddr() ?vkGetInstanceProcAddr {
    return
        if (c.SDL_Vulkan_GetVkGetInstanceProcAddr()) |res| @ptrCast(vkGetInstanceProcAddr, res)
        else null;
}

pub const Size = struct {
    width: c_int,
    height: c_int,
};
pub fn getDrawableSize(window: sdl.Window) Size {
    var size: Size = undefined;
    c.SDL_Vulkan_GetDrawableSize(
        @ptrCast(?*c.SDL_Window, window.ptr),
        &size.width, &size.height,
    );
    return size;
}

pub fn loadLibrary(path: ?[:0]const u8) bool {
    const status = c.SDL_Vulkan_LoadLibrary(if (path) |p| p.ptr else null);
    if (status != 0) {
        return false;
    } else {
        return true;
    }
}
pub fn unloadLibrary() void {
    c.SDL_Vulkan_UnloadLibrary();
}
