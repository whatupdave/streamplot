const Builder = @import("std").build.Builder;
const builtin = @import("builtin");

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();

    var exe = b.addExecutable("streamplot", "src/main.zig");
    exe.setBuildMode(mode);
    exe.setOutputDir("zig-cache");
    exe.linkSystemLibrary("ncurses");

    b.default_step.dependOn(&exe.step);
    b.installArtifact(exe);
}
