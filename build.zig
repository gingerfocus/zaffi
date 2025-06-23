const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zaffi = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    // artifactAdd(b, "pakker", pakker);

    // ------------------------------------------------------------------------

    const unit_tests = b.addTest(.{ .root_module = zaffi });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const tests = b.step("test", "Run unit tests");
    tests.dependOn(&run_unit_tests.step);

    // ------------------------------------------------------------------------

    const examples = b.step("examples", "build all the examples");
    inline for (EXAMPLES) |example| {
        const ex = b.addExecutable(.{
            .root_source_file = b.path("examples/" ++ example ++ ".zig"),
            .name = example,
            .target = target,
            .optimize = optimize,
        });
        ex.root_module.addImport("zaffi", zaffi);
        const step = b.step("example-" ++ example, "run the example");
        const run = b.addRunArtifact(ex);
        step.dependOn(&run.step);

        const exe = b.addInstallArtifact(ex, .{});
        examples.dependOn(&exe.step);
    }

    // const check = b.step("check", "Lsp Check Step");
    // check.dependOn(&zaffi.step);
}

const EXAMPLES = [_][]const u8{
    "runlength-decode",
};

// fn artifactAdd(b: *std.Build, comptime name: []const u8, artifact: *std.Build.Step.Compile) void {
//     const install = b.addInstallArtifact(artifact, .{});
//     const step = b.step(name, "compile " ++ name ++ " executable");
//     step.dependOn(&install.step);
//
//     const run = b.addRunArtifact(artifact);
//     if (b.args) |args| run.addArgs(args);
//     const runner = b.step(name ++ "-run", "Run the app");
//     runner.dependOn(&run.step);
// }
