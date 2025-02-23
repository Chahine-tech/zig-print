const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "md2pdf",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add module dependencies
    const markdown_parser_module = b.createModule(.{
        .root_source_file = b.path("src/markdown/parser.zig"),
    });
    exe.root_module.addImport("markdown_parser", markdown_parser_module);

    const pdf_renderer_module = b.createModule(.{
        .root_source_file = b.path("src/pdf/renderer.zig"),
    });
    exe.root_module.addImport("pdf_renderer", pdf_renderer_module);

    const style_module = b.createModule(.{
        .root_source_file = b.path("src/config/style.zig"),
    });
    exe.root_module.addImport("style", style_module);

    // Add system libraries
    exe.linkSystemLibrary("cmark");
    exe.linkSystemLibrary("cairo");
    exe.linkSystemLibrary("fontconfig");
    exe.linkLibC();

    // Add include and library paths for macOS (Homebrew)
    exe.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
    exe.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });

    // Install the executable
    b.installArtifact(exe);

    // Add tests
    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_main_tests = b.addRunArtifact(main_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
