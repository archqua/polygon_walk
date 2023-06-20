pub usingnamespace @import("vulkan");
const vk = @import("vulkan");
const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

pub const break16 = 0xFFFF;
pub const break32 = 0xFFFFFFFF;

// pub const debug=true;
pub const debug = switch (builtin.mode) {
    .Debug, .ReleaseSafe => true,
    else => false,
};

pub const BaseDispatch = vk.BaseWrapper(.{
    .createInstance = true,
    .enumerateInstanceLayerProperties = true,
});
pub const InstanceDispatch = vk.InstanceWrapper(.{
    .createDebugUtilsMessengerEXT  = debug,
    .createDevice = true,
    .destroyDebugUtilsMessengerEXT = debug,
    .destroyInstance = true,
    .destroySurfaceKHR = true,
    .enumerateDeviceExtensionProperties = true,
    .enumeratePhysicalDevices = true,
    .getDeviceProcAddr = true,
    .getPhysicalDeviceFeatures = true,
    .getPhysicalDeviceMemoryProperties = true,
    .getPhysicalDeviceProperties = true,
    .getPhysicalDeviceQueueFamilyProperties = true,
    .getPhysicalDeviceSurfaceCapabilitiesKHR = true,
    .getPhysicalDeviceSurfaceFormatsKHR = true,
    .getPhysicalDeviceSurfacePresentModesKHR = true,
    .getPhysicalDeviceSurfaceSupportKHR = true,
});
pub const DeviceDispatch = vk.DeviceWrapper(.{
    .acquireNextImageKHR = true,
    .allocateCommandBuffers = true,
    .allocateDescriptorSets = true,
    .allocateMemory = true,
    .beginCommandBuffer = true,
    .bindBufferMemory = true,
    .cmdBeginRenderPass = true,
    .cmdBindDescriptorSets = true,
    .cmdBindIndexBuffer = true,
    .cmdBindPipeline = true,
    .cmdBindVertexBuffers = true,
    .cmdCopyBuffer = true,
    .cmdDrawIndexed = true,
    .cmdDrawIndexedIndirect = true,
    .cmdEndRenderPass = true,
    .cmdResetEvent = true,
    .cmdSetEvent = true,
    .cmdSetViewport = true,
    .cmdSetScissor = true,
    .createBuffer = true,
    .createCommandPool = true,
    .createDescriptorPool = true,
    .createDescriptorSetLayout = true,
    .createEvent = true,
    .createFence = true,
    .createFramebuffer = true,
    .createGraphicsPipelines = true,
    .createImageView = true,
    .createPipelineLayout = true,
    .createRenderPass = true,
    .createSemaphore = true,
    .createShaderModule = true,
    .createSwapchainKHR = true,
    .destroyBuffer = true,
    .destroyCommandPool = true,
    .destroyDescriptorPool = true,
    .destroyDescriptorSetLayout = true,
    .destroyDevice = true,
    .destroyEvent = true,
    .destroyFence = true,
    .destroyFramebuffer = true,
    .destroyImageView = true,
    .destroyPipeline = true,
    .destroyPipelineLayout = true,
    .destroyRenderPass = true,
    .destroySemaphore = true,
    .destroyShaderModule = true,
    .destroySwapchainKHR = true,
    .deviceWaitIdle = true,
    .endCommandBuffer = true,
    .flushMappedMemoryRanges = true,
    .freeCommandBuffers = true,
    .freeMemory = true,
    .getBufferMemoryRequirements = true,
    .getDeviceQueue = true,
    .getEventStatus = true,
    .getSwapchainImagesKHR = true,
    .mapMemory = true,
    .queuePresentKHR = true,
    .queueSubmit = true,
    .queueWaitIdle = true,
    .resetCommandBuffer = true,
    .resetEvent = true,
    .resetFences = true,
    .setEvent = true,
    .unmapMemory = true,
    .updateDescriptorSets = true,
    .waitForFences = true
});

pub const debug_extensions =
    if (debug) [_][*:0]const u8{vk.extension_info.ext_debug_utils.name}
    else @compileError("no debug utils for unsafe release");

pub const AutoError = error {
        NotReady,
        Timeout,
        EventSet,
        EventReset,
        Incomplete,
        PipelineCompileRequired,
        SuboptimalKhr,
        ThreadIdleKhr,
        ThreadDoneKhr,
        OperationDeferredKhr,
        OperationNotDeferredKhr,
} || if (debug) error {
        UnexpectedAutoError,
     } else error {};
// TODO maybe modify Dispatches so that this is unnecessary
pub fn autoError(status: anyerror!vk.Result) !void {
    return switch (try status) {
        .success => {},
        .not_ready => AutoError.NotReady,
        .timeout => AutoError.Timeout,
        .event_set => AutoError.EventSet,
        .event_reset => AutoError.EventReset,
        .incomplete => AutoError.Incomplete,
        .pipeline_compile_required => AutoError.PipelineCompileRequired,
        .suboptimal_khr => AutoError.SuboptimalKhr,
        .thread_idle_khr => AutoError.ThreadIdleKhr,
        .thread_done_khr => AutoError.ThreadDoneKhr,
        .operation_deferred_khr => AutoError.OperationDeferredKhr,
        .operation_not_deferred_khr => AutoError.OperationNotDeferredKhr,
        else => if (debug) AutoError.UnexpectedAutoError else unreachable,
    };
}

pub fn getInstanceLayers(vkb: BaseDispatch, ator: Allocator) ![]vk.LayerProperties {
    var count: u32 = undefined;
    try autoError(vkb.enumerateInstanceLayerProperties(&count, null));
    const avail_layers = try ator.alloc(vk.LayerProperties, count);
    errdefer ator.free(avail_layers);
    try autoError(vkb.enumerateInstanceLayerProperties(&count, avail_layers.ptr));
    return avail_layers;
}
pub const validation_layers = 
    if (debug) [_][*:0]const u8{"VK_LAYER_KHRONOS_validation"}
    else @compileError("no vulkan validation layers for unsafe release");
pub fn validationLayersAreAvailable(avail_layers: []vk.LayerProperties) bool {
    REQ_LAY_LOOP: for (validation_layers) |req_layer| {
        for (avail_layers) |avail_layer| {
            const rhs = @ptrCast([*:0]const u8, &avail_layer.layer_name);
            if (std.cstr.cmp(req_layer, rhs) == 0) {
                continue :REQ_LAY_LOOP;
            }
        }
        return false;
    }
    return true;
}
pub const validation_msg_severity = if (debug) vk.DebugUtilsMessageSeverityFlagsEXT{
    .verbose_bit_ext = if (builtin.mode == .Debug) true else false,
    .warning_bit_ext = true,
    .error_bit_ext = true,
} else @compileError("no vulkan validation message severity for unsafe release");
pub const validation_msg_type = if (debug) vk.DebugUtilsMessageTypeFlagsEXT{
    .general_bit_ext = true,
    .validation_bit_ext = true,
    .performance_bit_ext = true,
} else @compileError("no vulkan validation message type for unsafe release");
// this should probably be reconsidered eventually
pub fn debugCallback(
    _: vk.DebugUtilsMessageSeverityFlagsEXT,
    _: vk.DebugUtilsMessageTypeFlagsEXT,
    p_callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
    _: ?*anyopaque
) callconv(vk.vulkan_call_conv) vk.Bool32 {
    if (p_callback_data != null) {
        std.log.debug("validation layer: {s}", .{p_callback_data.?.p_message});
    }

    return vk.FALSE;
}

pub fn GraphicsPipelineBuilder(comptime _n_stages: comptime_int) type {
    return struct {
        pub const n_stages = _n_stages;
        shader_stages: [n_stages]vk.PipelineShaderStageCreateInfo,
        vertex_input: vk.PipelineVertexInputStateCreateInfo,
        input_assembly: vk.PipelineInputAssemblyStateCreateInfo,
        viewport: vk.Viewport,
        scissor: vk.Rect2D,
        rasterizer: vk.PipelineRasterizationStateCreateInfo,
        multisampling: vk.PipelineMultisampleStateCreateInfo,
        // no depth stencil testing currently
        color_blend_attachments: []const vk.PipelineColorBlendAttachmentState,
        layout: vk.PipelineLayout,
        base_pipeline_handle: vk.Pipeline = .null_handle,
        base_pipeline_index: i32 = -1,
        
        const Self = @This();
        pub fn build(
            self: Self,
            vkd: DeviceDispatch, device: vk.Device,
            render_pass: vk.RenderPass,
        ) !vk.Pipeline {
            const viewport_state = vk.PipelineViewportStateCreateInfo{
                .viewport_count = 1,
                .p_viewports = @ptrCast([*]const vk.Viewport, &self.viewport),
                .scissor_count = 1,
                .p_scissors = @ptrCast([*]const vk.Rect2D, &self.scissor),
            };
            const color_blending = vk.PipelineColorBlendStateCreateInfo{
                .logic_op_enable = vk.FALSE,
                .logic_op = .copy, // .@"and"?
                .attachment_count = @intCast(u32, self.color_blend_attachments.len),
                .p_attachments = self.color_blend_attachments.ptr,
                .blend_constants = [4]f32{ 0.0, 0.0, 0.0, 0.0, },
            };

            // const dynamic_states = [_]vk.DynamicState{.viewport, .scissor};
            const dynamic_states = [_]vk.DynamicState{};
            const dynamic_state = vk.PipelineDynamicStateCreateInfo{
                .flags = .{},
                .dynamic_state_count = dynamic_states.len,
                .p_dynamic_states = &dynamic_states,
            };
            
            const create_info = [_]vk.GraphicsPipelineCreateInfo{.{
                .flags = .{},
                .stage_count = self.shader_stages.len,
                .p_stages = &self.shader_stages,
                .p_vertex_input_state = &self.vertex_input,
                .p_input_assembly_state = &self.input_assembly,
                .p_tessellation_state = null,
                .p_viewport_state = &viewport_state,
                .p_rasterization_state = &self.rasterizer,
                .p_multisample_state = &self.multisampling,
                .p_depth_stencil_state = null,
                .p_color_blend_state = &color_blending,
                .p_dynamic_state = &dynamic_state,
                .layout = self.layout,
                .render_pass = render_pass,
                .subpass = 0,
                .base_pipeline_handle = self.base_pipeline_handle,
                .base_pipeline_index = self.base_pipeline_index,
            }};
            var pipeline = [_]vk.Pipeline{undefined};
            try autoError(vkd.createGraphicsPipelines(
                device, vk.PipelineCache.null_handle, create_info.len, &create_info, null, &pipeline,
            ));
            return pipeline[0];
        }
    };
}
pub fn bytes2shaderModuleCreateInfo(
    bytes: []align(@alignOf(u32)) const u8,
) vk.ShaderModuleCreateInfo {
    return .{
        .flags = .{},
        .code_size = bytes.len,
        .p_code = @ptrCast([*]const u32, bytes.ptr),
    };
}
