const std = @import("std");
const Allocator = std.mem.Allocator;

const sdl = @import("sdl2");
const vk = @import("vk.zig");
const shaders = @import("shaders");
const sdlvk = @import("sdlvk.zig");
const util = @import("util");


const Graphics = @This();

pub const device_extensions = [_][*:0]const u8{vk.extension_info.khr_swapchain.name};
pub const max_frames_in_flight = 2;
pub const n_drawable_layers = 16;

window: sdl.Window = undefined,

vkb: vk.BaseDispatch = undefined,
vki: vk.InstanceDispatch = undefined,
vkd: vk.DeviceDispatch = undefined,

instance: vk.Instance = .null_handle,
debug_messenger: if (vk.debug) vk.DebugUtilsMessengerEXT else void =
    if (vk.debug) .null_handle else {},
surface: vk.SurfaceKHR = .null_handle,

pdev: PhysicalDevice = undefined,
device: vk.Device = undefined,
queues: Device.Queues = undefined,

swapchain: Swapchain = undefined,

ubo: UniformBufferObject = .{},
uniform_buffer: Buffer = undefined,
descriptor_pool: DescriptorPool(max_frames_in_flight) = undefined,

pipeline: Pipeline = undefined,

cmd_pools: struct {
    graphics: CommandPool(max_frames_in_flight),
    transfer: CommandPool(1),
} = undefined,

stager_final: Buffer.StagerFinalPair = undefined,

semaphores: [max_frames_in_flight] struct {
    image_available: vk.Semaphore,
    render_finished: vk.Semaphore,
} = undefined,
fence: [max_frames_in_flight]vk.Fence = undefined,

drawable_state: DrawableState = .{},

frame_counter: u32 = 0,

resize_requested: bool = false,

ator: Allocator = undefined,


pub const Settings = struct {
    application_name: [:0]const u8 = "",
    window: Window,
    init_n_ubos: u32 = max_frames_in_flight * 128,  // camera position and some objects
    init_n_vertices: u32 = max_frames_in_flight * 1024,
    init_n_indices: u32 = max_frames_in_flight * 2048,

    pub const Window = struct {
        x: sdl.WindowPosition = .{ .centered = {} },
        y: sdl.WindowPosition = .{ .centered = {} },
        width: usize = 0,
        height: usize = 0,
        flags: sdl.WindowFlags = .{},
    };
};
pub fn init(settings: Settings, ator: Allocator) !Graphics {
    var res: Graphics = .{.ator=ator};

    try res.initWindow(settings.application_name, settings.window);
    errdefer res.deinitWindow();

    const init_instance_res = try res.initInstance(settings.application_name);
    errdefer res.deinitInstance();

    try res.initSurface();
    errdefer res.deinitSurface();

    try res.pickPdev();

    try res.initDevice(init_instance_res.validation_available);
    errdefer res.deinitDevice();

    try res.initSwapchain();
    errdefer res.deinitSwapchain();

    try res.initUniformBuffer(settings.init_n_ubos);
    errdefer res.deinitUniformBuffer();

    try res.initDescriptorPool();
    errdefer res.deinitDescriptorPool();

    try res.initPipeline();
    errdefer res.deinitPipeline();

    try res.initCommandPools();
    errdefer res.deinitCommandPools();

    try res.initStagerFinalBufferPair(
        settings.init_n_vertices, settings.init_n_indices,
    );
    errdefer res.deinitStagerFinalBufferPair();

    try res.initSyncObjects();
    errdefer res.deinitSyncObjects();

    return res;
}
pub fn terminate(self: *const Graphics, device_wait_idle: bool) !void {
    if (device_wait_idle)
        try self.vkd.deviceWaitIdle(self.device);
    self.deinit();
}
fn deinit(self: *const Graphics) void {
    self.deinitSyncObjects();
    self.deinitStagerFinalBufferPair();
    self.deinitCommandPools();
    self.deinitPipeline();
    self.deinitDescriptorPool();
    self.deinitUniformBuffer();
    self.deinitSwapchain();
    self.deinitDevice();
    self.deinitSurface();
    self.deinitInstance();
    self.deinitWindow();
}

/// initialize sdl and create window, loading vulkan
fn initWindow(
    self: *Graphics, application_name: [:0]const u8, settings: Settings.Window,
) !void {
    try sdl.init(.{
        .video = true,
        .events = true,
        .audio = true,
    });
    errdefer sdl.quit();
    var flags = settings.flags;
    flags.context = .vulkan;
    self.window = try sdl.createWindow(
        application_name,
        settings.x, .{ .centered = {} },
        settings.width, settings.height,
        flags,
    );
}
fn deinitWindow(self: *const Graphics) void {
    self.window.destroy();
    sdlvk.unloadLibrary();  // make this conditional
    sdl.quit();
}

const InitInstanceResult = struct {
    validation_available: bool = false,
};
/// initialize vulkan instance and debug messenger
fn initInstance(
    self: *Graphics, application_name: [:0]const u8,
) !InitInstanceResult {
    // initialize vulkan
    const vk_proc = sdlvk.getVkGetInstanceProcAddr()
        orelse return error.NullVkInstanceProcAddr;
    self.vkb = try vk.BaseDispatch.load(vk_proc);
    const vk_app_info = vk.ApplicationInfo{
        .p_application_name = application_name,
        .application_version = vk.makeApiVersion(0, 0, 0, 0),
        .p_engine_name = "No Engine",
        .engine_version = vk.makeApiVersion(0, 0, 0, 0),
        .api_version = vk.API_VERSION_1_2,  // ?
    };
    // instance extensions
    const n_debug_ext: u32 = if (vk.debug) vk.debug_extensions.len else 0;
    const n_sdl_ext: u32 = @intCast(u32, try sdlvk.countInstanceExtensions(self.window));
    const n_ext = n_debug_ext + n_sdl_ext;
    const instance_extensions = try self.ator.alloc([*:0]const u8, n_ext);
    defer self.ator.free(instance_extensions);
    for (0..n_debug_ext) |i| {
        instance_extensions[i] = vk.debug_extensions[i];
    }
    try sdlvk.fillInstanceExtensions(self.window, instance_extensions[n_debug_ext..]);
    // instance layers
    const avail_layers = try vk.getInstanceLayers(self.vkb, self.ator);
    defer self.ator.free(avail_layers);
    const validation_available = if (vk.debug) vk.validationLayersAreAvailable(avail_layers) else false;
    const p_debug_create_info = if (vk.debug) &vk.DebugUtilsMessengerCreateInfoEXT{
        .flags = .{},
        .message_severity = vk.validation_msg_severity,
        .message_type = vk.validation_msg_type,
        .pfn_user_callback = vk.debugCallback,
        .p_user_data = null,
    } else null;
    // create instance
    const create_info = vk.InstanceCreateInfo{
        .flags = .{},
        .p_next = p_debug_create_info,
        .p_application_info = &vk_app_info,
        .enabled_layer_count = if (validation_available) vk.validation_layers.len else 0,
        .pp_enabled_layer_names = if (validation_available) &vk.validation_layers else undefined,
        .enabled_extension_count = @intCast(u32, instance_extensions.len),
        .pp_enabled_extension_names = instance_extensions.ptr,
    };
    self.instance = try self.vkb.createInstance(&create_info, null);
    self.vki = try vk.InstanceDispatch.load(self.instance, vk_proc);
    errdefer self.vki.destroyInstance(self.instance, null);
    // debug messenger
    if (vk.debug) {
        self.debug_messenger = try self.vki.createDebugUtilsMessengerEXT(
                                   self.instance,
                                   p_debug_create_info,
                                   null,
                               );
    }
    return .{
        .validation_available = validation_available,
    };
}
fn deinitInstance(self: *const Graphics) void {
    if (vk.debug)
        self.vki.destroyDebugUtilsMessengerEXT(self.instance, self.debug_messenger, null);
    self.vki.destroyInstance(self.instance, null);
}

fn initSurface(self: *Graphics) !void {
    self.surface = try sdlvk.createSurface(self.window, self.instance);
}
fn deinitSurface(self: *const Graphics) void {
    self.vki.destroySurfaceKHR(self.instance, self.surface, null);
}

fn pickPdev(self: *Graphics) !void {
    self.pdev = try PhysicalDevice.pick(
            self.*,
            .{},  // TODO get from config
        );
}
fn initDevice(self: *Graphics, validation_available: bool) !void {
    const res = try Device.init(self.*, validation_available);
    self.vkd = res.dispatch;
    self.device = res.device;
    self.queues = res.queues;
}
fn deinitDevice(self: *const Graphics) void {
    Device.deinit(self.device, self.vkd);
}

fn initSwapchain(self: *Graphics) !void {
    // TODO pass as configuration
    const desired_surf_fmt = vk.Format.r8g8b8a8_srgb;
    // const desired_surf_fmt = vk.Format.a8b8g8r8_srgb_pack32;
    const desired_col_space = vk.ColorSpaceKHR.srgb_nonlinear_khr;
    const desired_prsnt_mode = vk.PresentModeKHR.mailbox_khr;
    const sc_support =
        try PhysicalDevice.querySwapchainSupport(self.*, self.pdev.handle);
    defer sc_support.freeAll(self.ator);
    // capabilities
    const capabilities = sc_support.capabilities;
    var min_image_count = capabilities.min_image_count + 1;
    if (
        capabilities.max_image_count > 0 and
        min_image_count > capabilities.max_image_count
    )
        min_image_count = capabilities.max_image_count;
    var extent = capabilities.current_extent;
    if (extent.width == ~@as(u32, 0)) {
        // const size = self.window.getSize();  // fails for highdpi windows
        const size = sdlvk.getDrawableSize(self.window);
        const max_extent = capabilities.max_image_extent;
        const min_extent = capabilities.min_image_extent;
        extent.width = std.math.clamp(
            @intCast(u32, size.width), min_extent.width, max_extent.width,
        );
        extent.height = std.math.clamp(
            @intCast(u32, size.height), min_extent.height, max_extent.height,
        );
    }
    self.swapchain.extent = extent;
    // surface format and present mode
    const surface_formats = sc_support.formats;
    var image_format = surface_formats[0].format;
    var color_space = surface_formats[0].color_space;
    for (surface_formats) |sf| {
        if (sf.format == desired_surf_fmt and sf.color_space == desired_col_space) {
            image_format = sf.format;
            color_space = sf.color_space;
            break;
        }
    }
    const present_modes = sc_support.present_modes;
    var present_mode = present_modes[0];
    for (present_modes) |pm| {
        if (pm == desired_prsnt_mode) {
            present_mode = pm;
            break;
        }
    }
    // sharing mode and queue family indices
    const family_indices = self.pdev.family_indices;
    const unique_indices = family_indices.unique();
    const s_queue_family_indices = unique_indices.slice();
    var sharing_mode: vk.SharingMode = undefined;
    if (family_indices.transfer) |ti| {
        if (family_indices.graphics) |gi| {
            if (family_indices.present) |pi| {
                if (gi != pi or gi != ti) {
                    sharing_mode = .concurrent;
                } else {
                    sharing_mode = .exclusive;
                }
            } else unreachable;
        } else unreachable;
    } else unreachable;
    // creating swapchain
    const create_info = vk.SwapchainCreateInfoKHR{
        .flags = .{},
        .surface = self.surface,
        .min_image_count = min_image_count,
        .image_format = image_format,
        .image_color_space = color_space,
        .image_extent = extent,
        .image_array_layers = 1,
        .image_usage = .{ .color_attachment_bit = true },
        .image_sharing_mode = sharing_mode,
        .queue_family_index_count = switch (sharing_mode) {
            .concurrent => @intCast(u32, s_queue_family_indices.len),
            .exclusive => 0,
            _ => unreachable,
        },
        .p_queue_family_indices = switch (sharing_mode) {
            .concurrent => s_queue_family_indices.ptr,
            .exclusive => null,
            _ => unreachable,
        },
        .pre_transform = capabilities.current_transform,
        .composite_alpha = .{ .opaque_bit_khr = true },  // why not pre-multiplied?
        .present_mode = present_mode,
        .clipped = vk.TRUE,
        .old_swapchain = .null_handle,
    };
    self.swapchain.handle =
        try self.vkd.createSwapchainKHR(self.device, &create_info, null);
    errdefer self.vkd.destroySwapchainKHR(self.device, self.swapchain.handle, null);
    // swapchain images
    var count: u32 = undefined;
    try vk.autoError(self.vkd.getSwapchainImagesKHR(
        self.device, self.swapchain.handle, &count, null,
    ));
    self.swapchain.images = try self.ator.alloc(vk.Image, count);
    errdefer self.ator.free(self.swapchain.images);
    try vk.autoError(self.vkd.getSwapchainImagesKHR(
        self.device, self.swapchain.handle, &count, self.swapchain.images.ptr,
    ));
    self.swapchain.image_format = image_format;
    // image views, render pass and framebuffers
    try self.swapchain.initImageViews(self.vkd, self.device, self.ator);
    errdefer self.swapchain.deinitImageViews(self.vkd, self.device, self.ator);
    try self.swapchain.initRenderPass(self.vkd, self.device);
    errdefer self.swapchain.deinitRenderPass(self.vkd, self.device);
    try self.swapchain.initFramebuffers(self.vkd, self.device, self.ator);
    errdefer self.swapchain.deinitFramebuffers(self.vkd, self.device, self.ator);
}
fn deinitSwapchain(self: *const Graphics) void {
    self.swapchain.deinitFramebuffers(self.vkd, self.device, self.ator);
    self.swapchain.deinitRenderPass(self.vkd, self.device);
    self.swapchain.deinitImageViews(self.vkd, self.device, self.ator);
    self.ator.free(self.swapchain.images);
    self.vkd.destroySwapchainKHR(self.device, self.swapchain.handle, null);
}

fn initUniformBuffer(self: *Graphics, init_n_ubos: u32) !void {
    // hopefully this is it
    const alignment = self.pdev.props.limits.min_uniform_buffer_offset_alignment;
    const size = blk: {
        const ubo_size: vk.DeviceSize = @sizeOf(UniformBufferObject);
        const single_size = util.padSize(ubo_size, alignment);
        break :blk init_n_ubos * max_frames_in_flight * single_size;
    };
    const unique_indices = self.pdev.family_indices.unique();

    self.uniform_buffer = try Buffer.init(self.vkd, self.device, .{
        .buffer = .{
            .flags = .{},
            .size = size,
            .usage = .{ .uniform_buffer_bit = true, },
            // TODO exclusive
            .sharing_mode = .concurrent,
            .queue_family_index_count = unique_indices.count,
            .p_queue_family_indices = &unique_indices.indices,
        },
        .mem_props = .{
            .host_visible_bit = true,
            .host_coherent_bit = true,
        },
        // .pdev_mem_props = self.vki.getPhysicalDeviceMemoryProperties(self.pdev.handle),
        .pdev_mem_props = self.pdev.mem_props,
        .alignment = alignment,
    });
    errdefer self.uniform_buffer.deinit(self.vkd, self.device);
}
fn deinitUniformBuffer(self: *const Graphics) void {
    self.uniform_buffer.deinit(self.vkd, self.device);
}

fn initDescriptorPool(self: *Graphics) !void {
    const vkd = self.vkd;
    const layout_binding = [_]vk.DescriptorSetLayoutBinding{.{
        .binding = 0,
        // .descriptor_type = .uniform_buffer,
        .descriptor_type = .uniform_buffer_dynamic,
        .descriptor_count = 1,
        .stage_flags = .{ .vertex_bit = true },
    }};
    const set_layout_info = vk.DescriptorSetLayoutCreateInfo{
        .flags = .{},
        .binding_count = layout_binding.len,
        .p_bindings = &layout_binding,
    };
    self.descriptor_pool.set_layout = try vkd.createDescriptorSetLayout(
        self.device, &set_layout_info, null,
    );
    errdefer vkd.destroyDescriptorSetLayout(
        self.device, self.descriptor_pool.set_layout, null,
    );

    const pool_size = [_]vk.DescriptorPoolSize{.{
        // .type = .uniform_buffer,
        .type = .uniform_buffer_dynamic,
        .descriptor_count = max_frames_in_flight, // 1?
        // .descriptor_count = 1,
    }};
    const pool_info = vk.DescriptorPoolCreateInfo{
        .flags = .{},
        .max_sets = max_frames_in_flight,
        .pool_size_count = pool_size.len,
        .p_pool_sizes = &pool_size,
    };
    self.descriptor_pool.handle = try vkd.createDescriptorPool(
        self.device, &pool_info, null,
    );
    errdefer vkd.destroyDescriptorPool(
        self.device, self.descriptor_pool.handle, null,
    );

    var layouts: [max_frames_in_flight]vk.DescriptorSetLayout = undefined;
    for (&layouts) |*layout|
        layout.* = self.descriptor_pool.set_layout;
    // const layouts =
    //     [_]vk.DescriptorSetLayout{self.descriptor_pool.set_layout} ** max_frames_in_flight;
    const alloc_info = vk.DescriptorSetAllocateInfo{
        .descriptor_pool = self.descriptor_pool.handle,
        .descriptor_set_count = self.descriptor_pool.sets.len,
        .p_set_layouts = &layouts,
    };
    try vkd.allocateDescriptorSets(
        self.device, &alloc_info, &self.descriptor_pool.sets,
    );
    // descriptor sets are freed at descriptor pool destruction automatically

    var buffer_infos: [max_frames_in_flight]vk.DescriptorBufferInfo = undefined;
    var writes: [max_frames_in_flight]vk.WriteDescriptorSet = undefined;
    for (&buffer_infos, &writes, 0..) |*bi, *w, i| {
        bi.* = .{
            .buffer = self.uniform_buffer.handle,
            .offset = UniformBufferObject.alignAddress(
                @intCast(u32, i), self.uniform_buffer.alignment,
            ),
            .range = @sizeOf(UniformBufferObject),
        };
        w.* = .{
            .dst_set = self.descriptor_pool.sets[i],
            .dst_binding = 0,
            .dst_array_element = 0,
            // .descriptor_type = .uniform_buffer,
            .descriptor_type = .uniform_buffer_dynamic,
            .descriptor_count = 1,
            .p_image_info = undefined,
            .p_buffer_info = @ptrCast([*]const vk.DescriptorBufferInfo, bi),
            // .p_buffer_info = &[_]vk.DescriptorBufferInfo{bi.*},
            .p_texel_buffer_view = undefined,
        };
    }
    vkd.updateDescriptorSets(
        self.device,
        writes.len, &writes,
        0, undefined,
    );
}
fn deinitDescriptorPool(self: *const Graphics) void {
    const vkd = self.vkd;
    // this frees descriptor sets automatically
    vkd.destroyDescriptorPool(
        self.device, self.descriptor_pool.handle, null,
    );
    vkd.destroyDescriptorSetLayout(
        self.device, self.descriptor_pool.set_layout, null,
    );
}

fn initPipeline(self: *Graphics) !void {
    const vkd = self.vkd;
    const device = self.device;
    const layout_info = vk.PipelineLayoutCreateInfo{
        .flags = .{},
        .set_layout_count = 1,
        .p_set_layouts = @ptrCast([*]const vk.DescriptorSetLayout,
            &self.descriptor_pool.set_layout),
        // .p_set_layouts = &[_]vk.DescriptorSetLayout{self.descriptor_pool.set_layout},
        .push_constant_range_count = 0,
        .p_push_constant_ranges = undefined,
    };
    self.pipeline.layout =
        try vkd.createPipelineLayout(device, &layout_info, null);
    errdefer vkd.destroyPipelineLayout(device, self.pipeline.layout, null);

    const n_stages = 2;
    const module_infos = [n_stages]vk.ShaderModuleCreateInfo{
        vk.bytes2shaderModuleCreateInfo(&shaders.naive_vert),
        vk.bytes2shaderModuleCreateInfo(&shaders.naive_frag),
    };
    var modules: [n_stages]vk.ShaderModule = undefined;
    var m_init_count: usize = 0;
    defer {
        for (modules[0..m_init_count]) |m|
            vkd.destroyShaderModule(device, m, null);
    }
    for (&modules, 0..) |*m, i| {
        m.* = try vkd.createShaderModule(device, &module_infos[i], null);
        m_init_count += 1;
    }
    const shader_stages = [n_stages]vk.PipelineShaderStageCreateInfo{
        .{
            .flags = .{},
            .stage = .{ .vertex_bit = true, },
            .module = modules[0],
            .p_name = "main",
            .p_specialization_info = null,
        },
        .{
            .flags = .{},
            .stage = .{ .fragment_bit = true, },
            .module = modules[1],
            .p_name = "main",
            .p_specialization_info = null,
        },
    };

    const color_blend_attachments = [_]vk.PipelineColorBlendAttachmentState{.{
        .blend_enable = vk.FALSE,
        .src_color_blend_factor = .one,
        .dst_color_blend_factor = .zero,
        // .blend_enable = vk.TRUE,
        // .src_color_blend_factor = .src_alpha,
        // .dst_color_blend_factor = .one_minus_src_alpha,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .one,
        .dst_alpha_blend_factor = .zero,
        .alpha_blend_op = .add,
        .color_write_mask = .{ .r_bit=true, .g_bit=true, .b_bit=true, .a_bit=true, },
    }};
    const builder = vk.GraphicsPipelineBuilder(2){
        .shader_stages = shader_stages,
        .vertex_input = .{
            .flags = .{},
            .vertex_binding_description_count = Vertex.n_bindings,
            .p_vertex_binding_descriptions = &Vertex.binding_descriptions,
            .vertex_attribute_description_count = Vertex.n_attributes,
            .p_vertex_attribute_descriptions = &Vertex.attribute_descriptions,
        },
        .input_assembly = .{
            .flags = .{},
            // TODO fan
            .topology = .triangle_list,
            .primitive_restart_enable = vk.FALSE,
        },
        .viewport = .{
            .x = 0.0, .y = 0.0,
            .width = @intToFloat(f32, self.swapchain.extent.width),
            .height = @intToFloat(f32, self.swapchain.extent.height),
            .min_depth = 0.0, .max_depth = 1.0,
        },
        .scissor = .{
            .offset = .{ .x = 0, .y = 0, },
            .extent = self.swapchain.extent,
        },
        .rasterizer = .{
            .flags = .{},
            .depth_clamp_enable = vk.FALSE,
            .rasterizer_discard_enable = vk.FALSE,
            .polygon_mode = .fill,
            .cull_mode = .{ .front_bit = false, .back_bit = false, },
            .front_face = .clockwise,
            .depth_bias_enable = vk.FALSE,
            .depth_bias_constant_factor = 0.0,
            .depth_bias_clamp = 0.0,
            .depth_bias_slope_factor = 0.0,
            .line_width = 1.0,
        },
        .multisampling = .{
            .flags = .{},
            .rasterization_samples = .{ .@"1_bit" = true, },
            .sample_shading_enable = vk.FALSE,
            .min_sample_shading = 1.0,
            .p_sample_mask = null,
            .alpha_to_coverage_enable = vk.FALSE,
            .alpha_to_one_enable = vk.FALSE,
        },
        .color_blend_attachments = &color_blend_attachments,
        .layout = self.pipeline.layout,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    };
    self.pipeline.handle = try builder.build(vkd, device, self.swapchain.render_pass);
}
fn deinitPipeline(self: *const Graphics) void {
    const vkd = self.vkd;
    const device = self.device;
    vkd.destroyPipeline(device, self.pipeline.handle, null);
    vkd.destroyPipelineLayout(device, self.pipeline.layout, null);
}

pub fn resize(self: *Graphics) !void {
    try self.vkd.deviceWaitIdle(self.device);
    self.deinitPipeline();
    self.deinitSwapchain();

    try self.initSwapchain();
    errdefer self.deinitSwapchain();
    try self.initPipeline();
    errdefer self.deinitPipeline();
}

fn initCommandPools(self: *Graphics) !void {
    const vkd = self.vkd;
    const device = self.device;
    const family_indices = self.pdev.family_indices;
    // graphics
    const g_pool_info = vk.CommandPoolCreateInfo{
        .flags = .{ .reset_command_buffer_bit = true, },
        .queue_family_index = family_indices.graphics.?,
    };
    self.cmd_pools.graphics.handle =
        try vkd.createCommandPool(device, &g_pool_info, null);
    errdefer vkd.destroyCommandPool(device, self.cmd_pools.graphics.handle, null);
    const g_buf_info = vk.CommandBufferAllocateInfo{
        .command_pool = self.cmd_pools.graphics.handle,
        .level = .primary,
        .command_buffer_count = max_frames_in_flight,
    };
    try vkd.allocateCommandBuffers(device, &g_buf_info, &self.cmd_pools.graphics.buffers);
    errdefer vkd.freeCommandBuffers(
        device, self.cmd_pools.graphics.handle,
        max_frames_in_flight, &self.cmd_pools.graphics.buffers,
    );
    // transfer
    const t_pool_info = vk.CommandPoolCreateInfo{
        .flags = .{ .reset_command_buffer_bit = true, },
        .queue_family_index = family_indices.transfer.?,
    };
    self.cmd_pools.transfer.handle =
        try vkd.createCommandPool(device, &t_pool_info, null);
    errdefer vkd.destroyCommandPool(device, self.cmd_pools.transfer.handle, null);
    const t_buf_info = vk.CommandBufferAllocateInfo{
        .command_pool = self.cmd_pools.transfer.handle,
        .level = .primary,
        .command_buffer_count = 1,
    };
    try vkd.allocateCommandBuffers(device, &t_buf_info, &self.cmd_pools.transfer.buffers);
    errdefer vkd.freeCommandBuffers(
        device, self.cmd_pools.transfer.handle,
        1, &self.cmd_pools.transfer.buffers,
    );
}
fn deinitCommandPools(self: *const Graphics) void {
    const vkd = self.vkd;
    const device = self.device;
    vkd.freeCommandBuffers(
        device, self.cmd_pools.transfer.handle,
        1, &self.cmd_pools.transfer.buffers,
    );
    vkd.destroyCommandPool(device, self.cmd_pools.transfer.handle, null);
    vkd.freeCommandBuffers(
        device, self.cmd_pools.graphics.handle,
        max_frames_in_flight, &self.cmd_pools.graphics.buffers,
    );
    vkd.destroyCommandPool(device, self.cmd_pools.graphics.handle, null);
}

fn initStagerFinalBufferPair(
    self: *Graphics, init_n_vertices: u32, init_n_indices: u32,
) !void {
    self.stager_final = try Buffer.StagerFinalPair.init(self.vkd, self.device, .{
        // TODO reconsider size minding alignment
        .final_size = Buffer.pad_factor *
            (init_n_indices * @sizeOf(Index) + init_n_vertices * @sizeOf(Vertex)),
        .final_usage = .{
            .vertex_buffer_bit = true,
            .index_buffer_bit = true,
        },
        .non_coherent_atom_size = self.pdev.props.limits.non_coherent_atom_size,
        .pdev_mem_props = self.pdev.mem_props,
    });
    errdefer self.stager_final.deinit(self.vkd, self.device);
}
fn deinitStagerFinalBufferPair(self: *const Graphics) void {
    self.stager_final.deinit(self.vkd, self.device);
}

fn initSyncObjects(self: *Graphics) !void {
    const vkd = self.vkd;
    const device = self.device;
    const semaphore_info = vk.SemaphoreCreateInfo{.flags=.{}};
    const fence_info = vk.FenceCreateInfo{ .flags=.{ .signaled_bit = true } };
    var init_count: usize = 0;
    errdefer {
        for (0..init_count) |i| {
            vkd.destroySemaphore(device, self.semaphores[i].image_available, null);
            vkd.destroySemaphore(device, self.semaphores[i].render_finished, null);
            vkd.destroyFence(device, self.fence[i], null);
        }
    }
    while (init_count < max_frames_in_flight) : (init_count += 1) {
        self.semaphores[init_count].image_available =
            try vkd.createSemaphore(device, &semaphore_info, null);
        errdefer vkd.destroySemaphore(device, self.semaphores[init_count].image_available, null);
        self.semaphores[init_count].render_finished =
            try vkd.createSemaphore(device, &semaphore_info, null);
        errdefer vkd.destroySemaphore(device, self.semaphores[init_count].render_finished, null);
        self.fence[init_count] =
            try vkd.createFence(device, &fence_info, null);
        errdefer vkd.destroyFence(device, self.fence[init_count], null);
    }
}
fn deinitSyncObjects(self: *const Graphics) void {
    const vkd = self.vkd;
    const device = self.device;
    for (0..max_frames_in_flight) |i| {
        vkd.destroySemaphore(device, self.semaphores[i].image_available, null);
        vkd.destroySemaphore(device, self.semaphores[i].render_finished, null);
        vkd.destroyFence(device, self.fence[i], null);
    }
}


pub const PhysicalDevice = struct {
    pub const QueueFamilyIndices = struct {
        pub const n_indices = 3;
        transfer: ?u32 = null,
        graphics: ?u32 = null,
        present:  ?u32 = null,
        pub fn complete(self: QueueFamilyIndices) bool {
            return self.transfer != null and
                   self.graphics != null and
                   self.present  != null;
        }
        pub const UniqueIndices = struct {
            indices: [QueueFamilyIndices.n_indices]u32,
            count: u8,
            pub fn addIdx(self: *UniqueIndices, idx: u32) error{Overflow}!bool {
                if (self.count >= self.indices.len)
                    return error.Overflow;
                for (self.indices[0..self.count]) |ind| {
                    if (ind == idx)
                        return false;
                }
                self.indices[self.count] = idx;
                self.count += 1;
                return true;
            }
            // *const is necessary to avoid potential copying
            // which invalidates returned memory
            pub fn slice(self: *const UniqueIndices) []const u32 {
                return self.indices[0..self.count];
            }
        };
        pub fn unique(self: QueueFamilyIndices) UniqueIndices {
            var res = UniqueIndices{
                .indices = undefined,
                .count = 0,
            };
            if (self.transfer) |ti|
                _ = res.addIdx(ti) catch unreachable;
            if (self.graphics) |gi|
                _ = res.addIdx(gi) catch unreachable;
            if (self.present) |pi|
                _ = res.addIdx(pi) catch unreachable;
            return res;
        }
    };
    handle: vk.PhysicalDevice = .null_handle,
    family_indices: QueueFamilyIndices = .{},
    props: vk.PhysicalDeviceProperties,
    mem_props: vk.PhysicalDeviceMemoryProperties,

    fn pick(
        graphics: Graphics,
        scorer: Scorer,
    ) !PhysicalDevice {
        const vki = graphics.vki;
        var count: u32 = undefined;
        try vk.autoError(vki.enumeratePhysicalDevices(graphics.instance, &count, null));
        if (count == 0)
            return error.NoGPUsSupportVulkan;
        const devices = try graphics.ator.alloc(vk.PhysicalDevice, count);
        defer graphics.ator.free(devices);
        try vk.autoError(vki.enumeratePhysicalDevices(graphics.instance, &count, devices.ptr));

        var best_score: i64 = -1;
        var best_idx: usize = undefined;
        var best_family_indices: QueueFamilyIndices = undefined;
        var best_props: vk.PhysicalDeviceProperties = undefined;
        var best_mem_props: vk.PhysicalDeviceMemoryProperties = undefined;
        for (devices, 0..) |device, idx| {
            if (try isSuitable(graphics, device)) |family_indices| {
                const properties = vki.getPhysicalDeviceProperties(device);
                const features = vki.getPhysicalDeviceFeatures(device);
                const score = scorer.scoreFn(properties, features);
                if (score > best_score) {
                    best_score = score;
                    best_idx = idx;
                    best_family_indices = family_indices;
                    best_props = properties;
                    best_mem_props = vki.getPhysicalDeviceMemoryProperties(device);
                }
            }
        }
        if (best_score < 0)
            return error.NoSuitableGPUs;
        
        return .{
            .handle = devices[best_idx],
            .family_indices = best_family_indices,
            .props = best_props,
            .mem_props = best_mem_props,
        };
    }

    pub const Scorer = struct {
        scoreFn: ScoreFn = defaultScore,
    };
    pub const ScoreFn = *const
        fn (vk.PhysicalDeviceProperties, vk.PhysicalDeviceFeatures) u32;
    pub fn indifferentScore(_: vk.PhysicalDeviceProperties, _: vk.PhysicalDeviceFeatures) u32 {
        return 0;
    }
    pub const defaultScore = typeScore;
    pub fn typeScorerFn(comptime scale: u16) ScoreFn {
        return struct {
            fn func(
                properties: vk.PhysicalDeviceProperties,
                features: vk.PhysicalDeviceFeatures,
            ) u32 {
                _ = features;
                var score: u32 = 0;
                score += switch (properties.device_type) {
                    .discrete_gpu   => scale << 3,
                    .virtual_gpu    => scale << 2,
                    .integrated_gpu => scale << 1,
                    .cpu            => scale << 0,
                    else => 0,
                };
                return score;
            }
        }.func;
    }
    pub const typeScore = typeScorerFn(1 << 9);

    fn isSuitable(
        graphics: Graphics, device: vk.PhysicalDevice,
    ) !?QueueFamilyIndices {
        const vki = graphics.vki;
        var count: u32 = undefined;
        // get family indices
        var family_indices = QueueFamilyIndices{};
        vki.getPhysicalDeviceQueueFamilyProperties(device, &count, null);
        const families = try graphics.ator.alloc(vk.QueueFamilyProperties, count);
        defer graphics.ator.free(families);
        vki.getPhysicalDeviceQueueFamilyProperties(device, &count, families.ptr);
        for (families, 0..) |family_properties, i| {
            if (family_properties.queue_flags.graphics_bit) {
                family_indices.graphics =
                    if (family_indices.graphics) |gi| gi
                    else @intCast(u32, i);
            } else {
                if (family_properties.queue_flags.transfer_bit) {
                    family_indices.transfer =
                        if (family_indices.transfer) |ti| ti
                        else @intCast(u32, i);
                }
                if (try vki.getPhysicalDeviceSurfaceSupportKHR(
                        device, @intCast(u32, i), graphics.surface) == vk.TRUE) {
                    family_indices.present =
                        if (family_indices.present) |pi| pi
                        else @intCast(u32, i);
                }
            }
            // if (family_indices.complete())
            //     break;
        }
        if (!family_indices.complete())
            return null;

        // check available device extensions
        try vk.autoError(vki.enumerateDeviceExtensionProperties(
            device, null, &count, null,
        ));
        const avail_extensions =
            try graphics.ator.alloc(vk.ExtensionProperties, count);
        defer graphics.ator.free(avail_extensions);
        try vk.autoError(vki.enumerateDeviceExtensionProperties(
            device, null, &count, avail_extensions.ptr,
        ));
        REQ_EXT_LOOP: for (device_extensions) |req_ext| {
            for (avail_extensions) |avail_ext| {
                const rhs = @ptrCast([*:0]const u8, &avail_ext.extension_name);
                if (std.cstr.cmp(req_ext, rhs) == 0)
                    continue :REQ_EXT_LOOP;
            }
            return null;
        }

        // check swapchain support
        const swapchain_support = try querySwapchainSupport(graphics, device);
        defer swapchain_support.freeAll(graphics.ator);
        if (swapchain_support.formats.len == 0 or
                swapchain_support.present_modes.len == 0)
            return null;

        return family_indices;
    }
    const SwapchainSupport = struct {
        capabilities: vk.SurfaceCapabilitiesKHR,
        formats: []vk.SurfaceFormatKHR = &.{},
        present_modes: []vk.PresentModeKHR = &.{},
        fn freeAll(self: SwapchainSupport, ator: Allocator) void {
            ator.free(self.formats);
            ator.free(self.present_modes);
        }
    };
    fn querySwapchainSupport(
        graphics: Graphics, device: vk.PhysicalDevice,
    ) !SwapchainSupport {
        const vki = graphics.vki;
        var support = SwapchainSupport{
            .capabilities = try vki.getPhysicalDeviceSurfaceCapabilitiesKHR(
                device, graphics.surface,
            ),
        };
        var count: u32 = undefined;

        try vk.autoError(vki.getPhysicalDeviceSurfaceFormatsKHR(
            device, graphics.surface, &count, null,
        ));
        support.formats = try graphics.ator.alloc(vk.SurfaceFormatKHR, count);
        errdefer graphics.ator.free(support.formats);
        try vk.autoError(vki.getPhysicalDeviceSurfaceFormatsKHR(
            device, graphics.surface, &count, support.formats.ptr,
        ));

        try vk.autoError(vki.getPhysicalDeviceSurfacePresentModesKHR(
            device, graphics.surface, &count, null,
        ));
        support.present_modes = try graphics.ator.alloc(vk.PresentModeKHR, count);
        errdefer graphics.ator.free(support.present_modes);
        try vk.autoError(vki.getPhysicalDeviceSurfacePresentModesKHR(
            device, graphics.surface, &count, support.present_modes.ptr,
        ));
        
        return support;
    }
};
pub const Device = struct {
    const AndDispatch = struct {
        device: vk.Device,
        queues: Queues,
        dispatch: vk.DeviceDispatch,
    };
    pub const Queues = struct {
        transfer: vk.Queue,
        graphics: vk.Queue,
        present:  vk.Queue,
    };

    fn init(graphics: Graphics, validation_available: bool) !Device.AndDispatch {
        const vki = graphics.vki;
        const family_indices = graphics.pdev.family_indices;
        const unique_family_indices = family_indices.unique();
        var queue_create_infos:
            [PhysicalDevice.QueueFamilyIndices.n_indices]vk.DeviceQueueCreateInfo = undefined;
        const queue_priorities = [_]f32{1.0};
        for (unique_family_indices.slice(), 0..) |fi, ind| {
            queue_create_infos[ind] = vk.DeviceQueueCreateInfo{
                .flags = .{},
                .queue_family_index = fi,
                .queue_count = 1,
                .p_queue_priorities = &queue_priorities,
            };
        }
        const pdev_features = vki.getPhysicalDeviceFeatures(graphics.pdev.handle);

        const valid_avail = if (vk.debug) validation_available else false;
        const create_info = vk.DeviceCreateInfo{
            .flags = .{},
            .queue_create_info_count = unique_family_indices.count,
            .p_queue_create_infos = &queue_create_infos,
            .enabled_layer_count =
                if (valid_avail) vk.validation_layers.len else 0,
            .pp_enabled_layer_names =
                if (valid_avail) &vk.validation_layers else null,
            .enabled_extension_count = device_extensions.len,
            .pp_enabled_extension_names = &device_extensions,
            .p_enabled_features = &pdev_features,
        };
        const dev = try vki.createDevice(graphics.pdev.handle, &create_info, null);
        const vkd = try vk.DeviceDispatch.load(dev, vki.dispatch.vkGetDeviceProcAddr);

        const queues = Queues{
            .transfer =
                if (family_indices.transfer) |ti|
                    vkd.getDeviceQueue(dev, ti, 0)
                else .null_handle,
            .graphics =
                if (family_indices.graphics) |gi|
                    vkd.getDeviceQueue(dev, gi, 0)
                else .null_handle,
            .present =
                if (family_indices.present) |pi|
                    vkd.getDeviceQueue(dev, pi, 0)
                else .null_handle,
        };
        return .{
            .device = dev,
            .queues = queues,
            .dispatch = vkd,
        };
    }
    fn deinit(device: vk.Device, vkd: vk.DeviceDispatch) void {
        vkd.destroyDevice(device, null);
    }
};
pub const Swapchain = struct {
    handle: vk.SwapchainKHR,
    images: []vk.Image,
    image_format: vk.Format,
    image_views: []vk.ImageView,
    extent: vk.Extent2D,
    render_pass: vk.RenderPass,
    framebuffers: []vk.Framebuffer,

    fn initImageViews(
        self: *Swapchain,
        vkd: vk.DeviceDispatch, device: vk.Device,
        ator: Allocator,
    ) !void {
        self.image_views = try ator.alloc(vk.ImageView, self.images.len);
        var init_count = ~@as(usize, 0);
        errdefer {
            while (init_count != ~@as(@TypeOf(init_count), 0)) : (init_count -%= 1) {
                vkd.destroyImageView(device, self.image_views[init_count], null);
            }
            ator.free(self.image_views);
        }
        for (self.images, 0..) |image, i| {
            const createInfo = vk.ImageViewCreateInfo{
                .flags = .{},
                .image = image,
                .view_type = .@"2d",
                .format = self.image_format,
                .components = .{
                    .r = .identity, .g = .identity, .b = .identity, .a = .identity,
                },
                .subresource_range = .{
                    .aspect_mask = .{ .color_bit = true, },
                    .base_mip_level = 0,
                    .level_count = 1,
                    .base_array_layer = 0,
                    .layer_count = 1,
                },
            };
            self.image_views[i] = try vkd.createImageView(
                device, &createInfo, null,
            );
            init_count = i;
        }
    }
    fn deinitImageViews(
        self: Swapchain,
        vkd: vk.DeviceDispatch, device: vk.Device,
        ator: Allocator,
    ) void {
        var i = self.image_views.len -% 1;
        while (i != ~@as(usize, 0)) : (i -%= 1) {
            vkd.destroyImageView(device, self.image_views[i], null);
        }
        ator.free(self.image_views);
    }

    fn initRenderPass(
        self: *Swapchain,
        vkd: vk.DeviceDispatch, device: vk.Device,
    ) !void {
        const color_attachment = [_]vk.AttachmentDescription{.{
            .flags = .{},
            .format = self.image_format,
            .samples = .{ .@"1_bit" = true, },
            .load_op = .clear,
            .store_op = .store,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .initial_layout = .@"undefined",
            .final_layout = .present_src_khr,
        }};
        const color_attachment_ref = [_]vk.AttachmentReference{.{
            .attachment = 0,
            .layout = .color_attachment_optimal,
        }};

        const subpass = [_]vk.SubpassDescription{.{
            .flags = .{},
            .pipeline_bind_point = .graphics,
            .input_attachment_count = 0,
            .p_input_attachments = undefined,
            .color_attachment_count = color_attachment_ref.len,
            .p_color_attachments = &color_attachment_ref,
            .p_resolve_attachments = null,
            .p_depth_stencil_attachment = null,
            .preserve_attachment_count = 0,
            .p_preserve_attachments = undefined,
        }};
        const dependency = [_]vk.SubpassDependency{.{
            .src_subpass = vk.SUBPASS_EXTERNAL,
            .dst_subpass = 0,
            .src_stage_mask = .{ .color_attachment_output_bit = true },
            .dst_stage_mask = .{ .color_attachment_output_bit = true },
            .src_access_mask = .{},
            .dst_access_mask = .{ .color_attachment_write_bit = true },
            .dependency_flags = .{},
        }};

        const create_info = vk.RenderPassCreateInfo{
            .flags = .{},
            .attachment_count = color_attachment.len,
            .p_attachments = &color_attachment,
            .subpass_count = subpass.len,
            .p_subpasses = &subpass,
            .dependency_count = dependency.len,
            .p_dependencies = &dependency,
        };
        self.render_pass = try vkd.createRenderPass(device, &create_info, null);
    }
    fn deinitRenderPass(
        self: Swapchain,
        vkd: vk.DeviceDispatch, device: vk.Device,
    ) void {
        vkd.destroyRenderPass(device, self.render_pass, null);
    }

    fn initFramebuffers(
        self: *Swapchain,
        vkd: vk.DeviceDispatch, device: vk.Device,
        ator: Allocator,
    ) !void {
        self.framebuffers = try ator.alloc(vk.Framebuffer, self.image_views.len);
        var init_count = ~@as(usize, 0);
        errdefer {
            while (init_count != ~@as(@TypeOf(init_count), 0)) : (init_count -%= 1) {
                vkd.destroyFramebuffer(device, self.framebuffers[init_count], null);
            }
            ator.free(self.framebuffers);
        }
        for (self.framebuffers, 0..) |*framebuffer, i| {
            const attachment = [_]vk.ImageView{self.image_views[i]};
            const create_info = vk.FramebufferCreateInfo{
                .flags = .{},
                .render_pass = self.render_pass,
                .attachment_count = attachment.len,
                .p_attachments = &attachment,
                .width = self.extent.width,
                .height = self.extent.height,
                .layers = 1,
            };
            framebuffer.* = try vkd.createFramebuffer(device, &create_info, null);
        }
    }
    fn deinitFramebuffers(
        self: Swapchain,
        vkd: vk.DeviceDispatch, device: vk.Device,
        ator: Allocator,
    ) void {
        var i = self.framebuffers.len -% 1;
        while (i != ~@as(usize, 0)) : (i -%= 1) {
            vkd.destroyFramebuffer(device, self.framebuffers[i], null);
        }
        ator.free(self.framebuffers);
    }
};

pub const Buffer = struct {
    // TODO move memory out of Buffer and work with single memory allocation
    handle: vk.Buffer,
    memory: vk.DeviceMemory,
    size: vk.DeviceSize,
    alignment: vk.DeviceSize,

    pub const pad_factor = 2;

    pub const Config = struct {
        buffer: vk.BufferCreateInfo,
        mem_props: vk.MemoryPropertyFlags,
        pdev_mem_props: vk.PhysicalDeviceMemoryProperties,
        alignment: ?vk.DeviceSize = null,
    };
    fn init(vkd: vk.DeviceDispatch, device: vk.Device, cfg: Config) !Buffer {
        var res = Buffer{
            .handle = try vkd.createBuffer(device, &cfg.buffer, null),
            .memory = undefined,
            .size = cfg.buffer.size,
            .alignment = undefined,
        };
        errdefer vkd.destroyBuffer(device, res.handle, null);

        const mem_reqs = vkd.getBufferMemoryRequirements(device, res.handle);
        res.alignment = if (cfg.alignment) |a| a else mem_reqs.alignment;
        const req_mem_type_bits = mem_reqs.memory_type_bits;
        const Bits = @TypeOf(req_mem_type_bits);
        const memory_type_index = blk: {
            for (0..cfg.pdev_mem_props.memory_type_count) |mem_idx| {
                const mem_type = cfg.pdev_mem_props.memory_types[mem_idx];
                if (
                    req_mem_type_bits &
                        (@as(Bits, 1) << @intCast(u5, mem_idx)) != 0 and
                    mem_type.property_flags.contains(cfg.mem_props)
                ) {
                    break :blk @intCast(u32, mem_idx);
                }
            }
            return error.NoSuitableDeviceMemoryType;
        };
        const alloc_info = vk.MemoryAllocateInfo{
            .allocation_size = mem_reqs.size,
            .memory_type_index = memory_type_index,
        };
        res.memory = try vkd.allocateMemory(device, &alloc_info, null);
        errdefer vkd.freeMemory(device, res.memory, null);
        try vkd.bindBufferMemory(device, res.handle, res.memory, 0);  // zero-offset

        return res;
    }
    fn deinit(self: Buffer, vkd: vk.DeviceDispatch, device: vk.Device) void {
        vkd.freeMemory(device, self.memory, null);
        vkd.destroyBuffer(device, self.handle, null);
    }

    pub const StagerFinalPair = struct {
        stager: Buffer,
        final: Buffer,

        pub const Config = struct {
          final_size: vk.DeviceSize,
          final_usage: vk.BufferUsageFlags,
          non_coherent_atom_size: vk.DeviceSize,
          pdev_mem_props: vk.PhysicalDeviceMemoryProperties,
          stager_sharing_mode: vk.SharingMode = .exclusive,
          final_sharing_mode: vk.SharingMode = .exclusive,
        };
        fn init(
            vkd: vk.DeviceDispatch, device: vk.Device, cfg: StagerFinalPair.Config,
        ) !StagerFinalPair {
            const stager_size =
                util.padSize(cfg.final_size, cfg.non_coherent_atom_size);
            const stager_info = vk.BufferCreateInfo{
                .flags = .{},
                .size = stager_size,
                .usage = .{ .transfer_src_bit = true },
                .sharing_mode = cfg.stager_sharing_mode,
                .queue_family_index_count = 0,
                .p_queue_family_indices = null,
            };
            const stager = try Buffer.init(vkd, device, .{
                .buffer = stager_info,
                .mem_props = .{ .host_visible_bit = true },
                .pdev_mem_props = cfg.pdev_mem_props,
            });
            errdefer stager.deinit(vkd, device);

            const final_info = vk.BufferCreateInfo{
                .flags = .{},
                .size = cfg.final_size,
                .usage = cfg.final_usage.merge(.{ .transfer_dst_bit = true }),
                .sharing_mode = cfg.final_sharing_mode,
                .queue_family_index_count = 0,
                .p_queue_family_indices = null,
            };
            const final = try Buffer.init(vkd, device, .{
                .buffer=  final_info,
                .mem_props = .{ .device_local_bit = true },
                .pdev_mem_props = cfg.pdev_mem_props,
            });
            errdefer final.deinit(vkd, device);

            return .{
                .stager = stager,
                .final = final,
            };
        }
        fn deinit(
            self: StagerFinalPair, vkd: vk.DeviceDispatch, device: vk.Device,
        ) void {
            self.final.deinit(vkd, device);
            self.stager.deinit(vkd, device);
        }

        /// presumably deprecated
        fn stageBytes(
            self: *const StagerFinalPair,
            offset: vk.DeviceSize,
            bytes: []const u8,
            vkd: vk.DeviceDispatch,
            device: vk.Device,
        ) !void {
            if (offset + bytes.len > self.final.size)
                return error.BufferOverflow;
            const range = [_]vk.MappedMemoryRange{.{
                .memory = self.stager.memory,
                .offset = offset,
                .size = bytes.len,
            }};
            const _data = try vkd.mapMemory(device,
                range[0].memory, range[0].offset, range[0].size,
                .{},  // flags
            );
            defer vkd.unmapMemory(device, self.stager.memory);
            const data = @ptrCast([*]u8, _data.?);
            @memcpy(data, bytes);
            // no need to flush host-coherent memory
        }
        pub const TransferInfo = struct {
            reset_transfer_buffer: bool = true,
            transfer_queue_wait_idle: bool = false,
        };
        fn stageDrawableState(
            self: *const StagerFinalPair,
            offset: vk.DeviceSize,
            state: DrawableState,
            vkd: vk.DeviceDispatch,
            device: vk.Device,
        ) !bool {
            var n_vertices: u32 = 0;
            var n_indices: u32 = 0;
            var mem_size: vk.DeviceSize = undefined;
            { // check capacity
                // TODO alignment concerns for general case
                for (state.infos) |info| {
                    n_vertices += info.n_vertices;
                    n_indices += info.n_indices;
                }
                const vertex_region: vk.DeviceSize = @sizeOf(Vertex) * n_vertices;
                const index_region: vk.DeviceSize = @sizeOf(Index) * n_indices;
                mem_size = vertex_region + index_region;
                if (mem_size > self.stager.size) {
                    return false;
                }
            }
            if (mem_size > 0) {
                const range = [_]vk.MappedMemoryRange{.{
                    .memory = self.stager.memory,
                    .offset = offset,
                    .size = mem_size,
                }};
                const _data = try vkd.mapMemory(device,
                    range[0].memory, range[0].offset, range[0].size,
                    .{},  // flags
                );
                defer vkd.unmapMemory(device, self.stager.memory);
                const data = @ptrCast([*]u8, _data.?)[range[0].offset..range[0].size];
                try state.writeAsBytes(.{.n_vertices=n_vertices, .n_indices=n_indices}, data);
                // no need to flash host-coherent memory
            }
            return true;
        }
        fn transfer(
            self: *const StagerFinalPair,
            vkd: vk.DeviceDispatch,
            transfer_buffer: vk.CommandBuffer,
            transfer_queue: vk.Queue,
            info: TransferInfo,
        ) !void {
            const region = [_]vk.BufferCopy{.{
                .src_offset = 0, .dst_offset = 0,
                .size = self.final.size,
            }};
            try vkd.queueWaitIdle(transfer_queue);
            if (info.reset_transfer_buffer)
                try vkd.resetCommandBuffer(transfer_buffer, .{});
            // record command buffer
            const begin_info = vk.CommandBufferBeginInfo{
                .flags = .{},
                .p_inheritance_info = null,
            };
            try vkd.beginCommandBuffer(transfer_buffer, &begin_info);
            { // command buffer commands
                vkd.cmdCopyBuffer(
                    transfer_buffer,
                    self.stager.handle, self.final.handle,
                    region.len, &region,
                );
            }
            try vkd.endCommandBuffer(transfer_buffer);
            // submit
            const submit_info = [_]vk.SubmitInfo{.{
                .wait_semaphore_count = 0,
                .p_wait_semaphores = null,
                .p_wait_dst_stage_mask = undefined,
                .command_buffer_count = 1,
                .p_command_buffers = @ptrCast([*]const vk.CommandBuffer,
                    &transfer_buffer),
                .signal_semaphore_count = 0,
                .p_signal_semaphores = null,
            }};
            try vkd.queueSubmit(
                transfer_queue,
                submit_info.len, &submit_info,
                vk.Fence.null_handle,
            );
            if (info.transfer_queue_wait_idle)
                try vkd.queueWaitIdle(transfer_queue);
        }
    };
};

// should it be extern or packed?
pub const UniformBufferObject = struct {
    pub const Mat4 = [16]f32;
    pub const eye4 = Mat4{
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0,
    };
    model: [16]f32 align(16) = eye4,
    view:  [16]f32 align(16) = eye4,
    proj:  [16]f32 align(16) = eye4,

    pub fn alignAddress(count: u32, alignment: vk.DeviceSize) vk.DeviceSize {
        return util.padSize(
            @intCast(vk.DeviceSize, count * @sizeOf(UniformBufferObject)), alignment,
        );
    }
};

pub fn DescriptorPool(comptime _n_sets: comptime_int) type {
    return struct {
        pub const n_sets = _n_sets;
        set_layout: vk.DescriptorSetLayout,
        handle: vk.DescriptorPool,
        sets: [n_sets]vk.DescriptorSet,
    };
}

pub const Pipeline = struct {
    layout: vk.PipelineLayout,
    handle: vk.Pipeline,
    // TODO cache
};

pub const Vertex = extern struct {
    pos: [2]f32,
    col: [3]f32,

    pub const n_bindings = 1;
    pub const binding_descriptions = [n_bindings]vk.VertexInputBindingDescription{.{
        .binding = 0,
        .stride = @sizeOf(Vertex),
        .input_rate = vk.VertexInputRate.vertex
    }};
    pub const n_attributes = @typeInfo(Vertex).Struct.fields.len;
    pub const attribute_descriptions = [n_attributes]vk.VertexInputAttributeDescription{
        .{
            .location = 0,
            .binding = 0,
            .format = vk.Format.r32g32_sfloat,
            .offset = @offsetOf(Vertex, "pos"),
        },
        .{
            .location = 1,
            .binding = 0,
            .format = vk.Format.r32g32b32_sfloat,
            .offset = @offsetOf(Vertex, "col"),
        },
    };
};
pub const Index = u16;
pub const index_type = vk.IndexType.uint16;

pub fn CommandPool(comptime _n_buffers: comptime_int) type {
    return struct {
        pub const n_buffers = _n_buffers;
        handle: vk.CommandPool,
        buffers: [n_buffers]vk.CommandBuffer,
    };
}

pub const PrimitiveObject = struct {
    vertices: []Vertex,
    indices: []Index,

    pub fn nVertices(self: PrimitiveObject) u32 {
        return @intCast(u32, self.vertices.len);
    }
    pub fn nIndices(self: PrimitiveObject) u32 {
        return @intCast(u32, self.indices.len);
    }
};
pub const PrimitiveCollection = std.SinglyLinkedList(PrimitiveObject);
pub const DrawableInfo = struct {
    n_vertices: u32 = 0,
    n_indices: u32 = 0,
};
/// accumulates drawable infos
pub const DrawableCapacityInfo = DrawableInfo;
pub const DrawableState = struct {
    lists: [n_drawable_layers]PrimitiveCollection = [_]PrimitiveCollection{.{}} ** n_drawable_layers,
    infos: [n_drawable_layers]DrawableInfo = [_]DrawableInfo{.{}} ** n_drawable_layers,

    fn updateInfos(self: *DrawableState) DrawableCapacityInfo {
        var info = DrawableCapacityInfo{};
        for (&self.infos, 0..) |*di, i| {
            di.n_vertices = 0;
            di.n_indices = 0;
            var node = self.lists[i].first;
            while (node) |n| : (node = n.next) {
                di.n_vertices += n.data.nVertices();
                di.n_indices += n.data.nIndices();
            }
            info.n_vertices += di.n_vertices;
            info.n_indices += di.n_indices;
        }
        return info;
    }
    fn writeAsBytes(
        self: *const DrawableState, info: DrawableCapacityInfo,
        dst: []u8,
    ) !void {
        { // ensure capacity
            // TODO alignment concerns for general case
            const n_vertices = info.n_vertices;
            const n_indices = info.n_indices;
            const vertex_region: u32 = @sizeOf(Vertex) * n_vertices;
            const index_region: u32 = @sizeOf(Index) * n_indices;
            const mem_size = vertex_region + index_region;
            if (mem_size > dst.len) {
                return error.Overflow;
            }
        }
        // update bytes
        var vertex_offset: u32 = 0;
        var index_offset: u32 = info.n_vertices * @sizeOf(Vertex);
        var per_list_vertex_offset = [_]u32{0} ** n_drawable_layers;
        for (self.lists, 0..) |list, i| {
            var node = list.first;
            var vertex_region: u32 = undefined;
            var index_region: u32 = undefined;
            while (node) |n| : ({
                node = n.next;
                vertex_offset += vertex_region;
                index_offset += index_region;
                per_list_vertex_offset[i] += vertex_region;
            }) {
                vertex_region = @intCast(u32, n.data.vertices.len * @sizeOf(Vertex));
                index_region = @intCast(u32, n.data.indices.len * @sizeOf(Index));
                @memcpy(
                    dst[vertex_offset..vertex_offset+vertex_region],
                    std.mem.sliceAsBytes(n.data.vertices),
                );
                @memcpy(
                    dst[index_offset..index_offset+index_region],
                    std.mem.sliceAsBytes(n.data.indices),
                );
                const written_index_slice =
                    std.mem.bytesAsSlice(Index, dst[index_offset..index_offset+index_region]);
                for (written_index_slice) |*di| {
                    di.* += @intCast(Index, per_list_vertex_offset[i]/@sizeOf(Vertex));
                }
            }
        }
    }
};

pub fn beginFrame(self: *Graphics, timeout: u64) !?u32 {
    const vkd = self.vkd;
    const device = self.device;
    // TODO handle resize
    const current_frame = self.frame_counter;
    switch (try vkd.waitForFences(device,
        1, &[_]vk.Fence{self.fence[current_frame]},
        vk.TRUE,  // wait all
        timeout,
    )) {
        .success => {},
        .timeout => return null,
        else => unreachable,
    }
    const nxt_img_res = try vkd.acquireNextImageKHR(device,
        self.swapchain.handle, timeout,
        self.semaphores[current_frame].image_available, vk.Fence.null_handle,
    );
    switch (nxt_img_res.result) {
        .success => {},
        .timeout => return null,
        .not_ready => return null,  // TODO error?
        .suboptimal_khr => {
            self.resize_requested = true;
        },
        else => unreachable,
    }

    if (self.resize_requested)
        try self.resize();

    return nxt_img_res.image_index;
}
pub fn renderFrame(self: *Graphics, image_index: u32) !void {
    const vkd = self.vkd;
    const device = self.device;
    const current_frame = self.frame_counter;
    const cmd_buffer = self.cmd_pools.graphics.buffers[current_frame];
    // record command buffer
    const begin_info = vk.CommandBufferBeginInfo{
        .flags = .{ .one_time_submit_bit = true, },
        .p_inheritance_info = null,
    };
    try vkd.beginCommandBuffer(cmd_buffer, &begin_info);
    {
        const clear_value = [_]vk.ClearValue{.{.color = .{
            .float_32 = [4]f32{0.0, 0.0, 0.0, 0.0},
        }}};
        const pass_info = vk.RenderPassBeginInfo{
            .render_pass = self.swapchain.render_pass,
            .framebuffer = self.swapchain.framebuffers[image_index],
            .render_area = .{
                .offset = .{ .x = 0, .y = 0, },
                .extent = self.swapchain.extent,
            },
            .clear_value_count = clear_value.len,
            .p_clear_values = &clear_value,
        };
        vkd.cmdBeginRenderPass(cmd_buffer, &pass_info, .@"inline");
        {
            vkd.cmdBindPipeline(cmd_buffer,
                .graphics, self.pipeline.handle);
            // TODO interleave vertices and indices
            vkd.cmdBindVertexBuffers(cmd_buffer,
                0, // first binding
                1, // binding count
                &[_]vk.Buffer{self.stager_final.final.handle},
                &[_]vk.DeviceSize{0}, // offsets
            );
            var n_vertices: u32 = 0;
            for (self.drawable_state.infos) |di|
                n_vertices += di.n_vertices;
            const offset = util.padSize(n_vertices * @sizeOf(Vertex), @as(u32, @alignOf(Index)));
            vkd.cmdBindIndexBuffer(cmd_buffer,
                self.stager_final.final.handle,
                offset,
                index_type,
            );
            var first_index: u32 = 0;
            var vertex_offset: i32 = 0;
            for (self.drawable_state.infos) |drawable_info| {
                vkd.cmdBindDescriptorSets(cmd_buffer,
                    .graphics, self.pipeline.layout,
                    0, // first set
                    1, // descriptor set count
                    @ptrCast([*]const vk.DescriptorSet, &self.descriptor_pool.sets[current_frame]),
                    1, // dynamic offset count TODO
                    &[_]u32{0},
                );
                // cmdDrawIndexedIndirect for background
                vkd.cmdDrawIndexed(cmd_buffer,
                    drawable_info.n_indices,
                    1, // instance count
                    first_index,
                    vertex_offset, // vertex offset
                    0, // first instance
                );
                first_index += drawable_info.n_indices;
                vertex_offset += @intCast(i32, drawable_info.n_vertices);
            }
        }
        vkd.cmdEndRenderPass(cmd_buffer);
    }
    try vkd.endCommandBuffer(cmd_buffer);
    // submit
    try vkd.resetFences(device, 1, &[_]vk.Fence{self.fence[current_frame]});
    const wait_dst_stage_mask = [_]vk.PipelineStageFlags{.{
        .color_attachment_output_bit = true,
    }};
    const submit_info = [_]vk.SubmitInfo{.{
        .wait_semaphore_count = 1,
        .p_wait_semaphores = @ptrCast([*]const vk.Semaphore,
            &self.semaphores[current_frame].image_available),
        .p_wait_dst_stage_mask = &wait_dst_stage_mask,
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast([*]const vk.CommandBuffer,
            &self.cmd_pools.graphics.buffers[current_frame]),
        .signal_semaphore_count = 1,
        .p_signal_semaphores = @ptrCast([*]const vk.Semaphore,
            &self.semaphores[current_frame].render_finished),
    }};
    try vkd.queueSubmit(
        self.queues.graphics,
        submit_info.len, &submit_info,
        self.fence[current_frame],
    );
    // present
    const present_info = vk.PresentInfoKHR{
        .wait_semaphore_count = 1,
        .p_wait_semaphores = @ptrCast([*]const vk.Semaphore,
            &self.semaphores[current_frame].render_finished),
        .swapchain_count = 1,
        .p_swapchains = @ptrCast([*]const vk.SwapchainKHR,
            &self.swapchain.handle),
        .p_image_indices = @ptrCast([*]const u32, &image_index),
    };
    const present_res = try vkd.queuePresentKHR(self.queues.present, &present_info);
    switch (present_res) {
        .success => {},
        .suboptimal_khr => {
            self.resize_requested = false;
        },
        else => unreachable,
    }
    
    self.frame_counter += 1;
    self.frame_counter %= max_frames_in_flight;
}

pub fn updateDrawableStateInfo(self: *Graphics) DrawableCapacityInfo {
    return self.drawable_state.updateInfos();
}
pub fn updateVertexIndexBuffer(self: *Graphics, info: DrawableCapacityInfo) !void {
    const vkd = self.vkd;
    const device = self.device;
    // try self.stager_final.stageBytes(0, self.drawable_state.bytes, vkd, device);
    const enough_memory = try self.stager_final.stageDrawableState(
        0, self.drawable_state, vkd, device,
    );
    if (!enough_memory) {
        const trash_marked_bp = self.stager_final;
        errdefer self.stager_final = trash_marked_bp;
        try self.initStagerFinalBufferPair(info.n_vertices, info.n_indices);
        const enough = try self.stager_final.stageDrawableState(
            0, self.drawable_state, vkd, device,
        );
        if (!enough) unreachable;
        trash_marked_bp.deinit(vkd, device);
    }
    try self.stager_final.transfer(vkd, self.cmd_pools.transfer.buffers[0], self.queues.transfer, .{});
}

