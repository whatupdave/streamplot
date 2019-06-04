const Builder = @import("std").build.Builder;
const builtin = @import("builtin");

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const linux = b.option(bool, "linux", "create linux build") orelse false;

    var exe = b.addExecutable("streamplot", "src/main.zig");

    exe.setBuildMode(mode);
    exe.setOutputDir("zig-cache");
    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("ncurses");

    if (linux) {
        exe.setTarget(builtin.Arch.x86_64, builtin.Os.linux, builtin.Abi.gnu);
    }

    b.default_step.dependOn(&exe.step);
    b.installArtifact(exe);
}
