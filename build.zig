const std = @import("std");

// const Sdk = @import("lib/SDL/Sdk.zig"); // seemingly deprecated
const Sdk = @import("lib/SDL/build.zig");
const vkgen = @import("lib/vulkan/generator/index.zig");
const VK_REG_XML = "vulkan_registry.xml";

const compile_shaders_cmd = [_][]const u8{
    "glslc", "--target-env=vulkan1.2",
};


fn integrateVulkanAndSDL(
    c: *std.Build.Step.Compile,
    vk_module: *std.Build.Module,
    shader_module: *std.Build.Module,
    sdk: *Sdk,
) void {
    const vulkan_module_name = "vulkan";
    const shader_module_name = "shaders";
    const sdl_module_name = "sdl2";

    c.addModule(vulkan_module_name, vk_module);
    c.addModule(shader_module_name, shader_module);

    sdk.link(c, .dynamic);
    // c.addModule(sdl_module_name, sdk.getWrapperModuleVulkan(vk_module));  // this breaks somehow
    c.addModule(sdl_module_name, sdk.getWrapperModule());
}

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // prepare vulkan and SDL for integration
    const vk_gen_step = vkgen.VkGenerateStep.create(b, VK_REG_XML);
    const vk_module = vk_gen_step.getModule();
    const shaders =
        vkgen.ShaderCompileStep.create(b, &compile_shaders_cmd, "-o");
    shaders.add("naive_vert", "shaders/naive.vert", .{});
    shaders.add("naive_frag", "shaders/naive.frag", .{});
    const shader_module = shaders.getModule();
    const sdk = Sdk.init(b, null);

    // local modules
    const util = b.addModule("util", .{
        .source_file = .{.path = "src/util.zig"},
    });

    const exe = b.addExecutable(.{
        .name = "polygon_walk",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    integrateVulkanAndSDL(exe, vk_module, shader_module, sdk);
    exe.addModule("util", util);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    integrateVulkanAndSDL(unit_tests, vk_module, shader_module, sdk);
    unit_tests.addModule("util", util);

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
