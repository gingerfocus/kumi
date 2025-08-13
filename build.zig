const std = @import("std");

const BuildItem = struct {
    name: []const u8,
    root: std.Build.LazyPath,
};

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{ .abi = .musl });
    const optimize = b.standardOptimizeOption(.{});

    const items: [3]BuildItem = .{
        .{
            .name = "kumi",
            .root = b.path("src/kumi.zig"),
        },
        .{
            // .name = "poru-daemon",
            .name = "poru",
            .root = b.path("src/poru.zig"),
        },
        .{
            .name = "runsv",
            .root = b.path("src/runsv.zig"),
        },
    };

    const config = b.addModule("config", .{ .root_source_file = b.path("config.zig") });

    for (items) |item| {
        const exe = b.addExecutable(.{
            .name = item.name,
            .root_source_file = item.root,
            .target = target,
            .optimize = optimize,
            .single_threaded = true,
            .linkage = .static,
        });

        exe.root_module.addImport("config", config);
        exe.linkLibC();

        b.installArtifact(exe);
    }

    // ------------------- Tests -----------------
    // const unit_tests = b.addTest(.{
    //     .root_source_file = .{ .path = "src/main.zig" },
    //     .target = target,
    //     .optimize = optimize,
    // });
    // const run_unit_tests = b.addRunArtifact(unit_tests);
    //
    // const tests = b.step("test", "Run unit tests");
    // tests.dependOn(&run_unit_tests.step);
}

// const Env = struct {
//     step: std.Build.Step,
//     output: std.Build.LazyPath,
//
//     pub fn module() *std.Build.Module {
//         @panic("TOOD");
//     }
// };
//
// pub fn addEnvStep(b: *std.Build, name: []const u8) *Env {
//     _ = name;
//
//     // b.getInstallStep().dependOn()
//     // b.addSystemCommand()
//
//     const env = b.allocator.create(Env) catch @panic("OOM");
//     env.* = .{
//         .step = .init(.{}),
//         .outputfile = .{
//             // .generated =
//         },
//     };
//     return env;
// }
//
//     // ------------------------------------------------------------------------
//
//     const env = addEnvStep(b);
//     env.add("username", "SS_USERNAME");
//     env.add("password", "SS_PASSWORD");
//     // env.add("hunterapi", "HUNTER_API");
//
//     // const env = std.process.getEnvMap(b.allocator) catch {};
//     // defer env.deinit();
//     // env.get()
//     // b.addOptions()
//     adc.addImport("env", env.module());
//
