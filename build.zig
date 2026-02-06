const std = @import("std");

pub fn build(b: *std.Build) void {
    // Gets the target platform (cup arch, os)
    const target = b.standardTargetOptions(.{});

    // Gets the optimization mode (Debug, ReleaseFast, ReleaseSafe, ReleaseSmall)
    const optimize = b.standardOptimizeOption(.{});

    const moduleCfg: std.Build.Module.CreateOptions = .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    };
    const module = b.createModule(moduleCfg);

    // Add vendored amqp module
    module.addImport("amqp", b.createModule(.{
        .root_source_file = b.path("src/lib/amqp/amqp.zig"),
        .target = target,
        .optimize = optimize,
    }));

    // Add version from build options
    const options = b.addOptions();
    const git_describe = b.run(&.{ "git", "describe", "--tags", "--abbrev=0" });
    options.addOption([]const u8, "version", git_describe);
    module.addOptions("config", options);

    const exe = b.addExecutable(.{ .name = "drivers-cli", .root_module = module });

    // Tells 'zig build' to copy compiled exe to zig-out/bin/drivers-cli
    b.installArtifact(exe);

    // Command to execute compiled program
    const run_cmd = b.addRunArtifact(exe);

    // Before running exe make sure it's copied to zig-out/bin/drivers-cli
    run_cmd.step.dependOn(b.getInstallStep());

    // Forward command line args
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Create named build step called 'run'
    const run_step = b.step("run", "Run the app");

    // When user types 'zig build run', execute the run_cmd step
    run_step.dependOn(&run_cmd.step);
}
