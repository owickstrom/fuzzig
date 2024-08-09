const std = @import("std");

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

    const fuzzig = b.addModule("fuzzig", .{
        .root_source_file = b.path("src/root.zig"),
    });

    const lib = b.addStaticLibrary(.{
        .name = "fuzzig",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // This declares intent for the library to be installed into the 61.494799,23.75890361.494799,23.758903standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    const fuzzers = [_]*std.Build.Step{
        add_fuzzer(b, "shortest", target, fuzzig),
        add_fuzzer(b, "bound5", target, fuzzig),
    };
    const fuzz_step = b.step("fuzz", "Build all fuzzers");
    for (fuzzers) |fuzzer| {
        fuzz_step.dependOn(fuzzer);
    }
}

fn add_fuzzer(b: *std.Build, comptime name: []const u8, target: std.Build.ResolvedTarget, fuzzig: *std.Build.Module) *std.Build.Step {
    const fuzz_lib = b.addStaticLibrary(.{
        .name = "fuzz-" ++ name ++ "-lib",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/fuzz/" ++ name ++ ".zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    fuzz_lib.root_module.addImport("fuzzig", fuzzig);
    fuzz_lib.want_lto = true;
    fuzz_lib.bundle_compiler_rt = true;
    // Seems to be necessary for LLVM >= 15
    fuzz_lib.root_module.pic = true;

    // Setup the output name
    const fuzz_executable_name = "fuzz-" ++ name;

    // We want `afl-clang-lto -o path/to/output path/to/library`
    const fuzz_compile = b.addSystemCommand(&.{ "afl-clang-lto", "-o" });
    const fuzz_exe_path = fuzz_compile.addOutputFileArg("fuzz-" ++ name);
    // Add the path to the library file to afl-clang-lto's args
    fuzz_compile.addArtifactArg(fuzz_lib);

    // Install the cached output to the install 'bin' path
    const fuzz_install = b.addInstallBinFile(fuzz_exe_path, fuzz_executable_name);
    fuzz_install.step.dependOn(&fuzz_compile.step);

    // Add a top-level step that compiles and installs the fuzz executable
    const fuzz_compile_run = b.step("fuzz-" ++ name, "Build executable for fuzz testing using afl-clang-lto");
    fuzz_compile_run.dependOn(&fuzz_compile.step);
    fuzz_compile_run.dependOn(&fuzz_install.step);

    // Compile a companion exe for debugging crashes
    const fuzz_debug_exe = b.addExecutable(.{
        .name = "fuzz-" ++ name ++ "-debug",
        .root_source_file = b.path("src/fuzz/" ++ name ++ ".zig"),
        .target = target,
        .optimize = .Debug,
    });
    fuzz_debug_exe.root_module.addImport("fuzzig", fuzzig);

    // Only install debug program when the fuzz step is run
    const install_fuzz_debug_exe = b.addInstallArtifact(fuzz_debug_exe, .{});
    fuzz_compile_run.dependOn(&install_fuzz_debug_exe.step);

    return fuzz_compile_run;
}
