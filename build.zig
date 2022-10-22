const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const assembler = b.addExecutable("assemble", "src/assembler.zig");
    assembler.setTarget(target);
    assembler.setBuildMode(mode);
    assembler.install();

    const simulator = b.addExecutable("simulate", "src/simulator.zig");
    simulator.setTarget(target);
    simulator.setBuildMode(mode);
    simulator.install();

    const disassembler = b.addExecutable("disassemble", "src/disassembler.zig");
    disassembler.setTarget(target);
    disassembler.setBuildMode(mode);
    disassembler.install();

    const run_assembler = assembler.run();
    run_assembler.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_assembler.addArgs(args);
    }

    const run_simulator = simulator.run();
    run_simulator.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_simulator.addArgs(args);
    }

    const run_disassembler = disassembler.run();
    run_disassembler.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_disassembler.addArgs(args);
    }

    const run_assem_step = b.step("assemble", "Run the assembler");
    run_assem_step.dependOn(&run_assembler.step);

    const run_sim_step = b.step("simulate", "Run the simulator");
    run_sim_step.dependOn(&run_simulator.step);

    const run_disassem_step = b.step("disassemble", "Run the disassembler");
    run_disassem_step.dependOn(&run_disassembler.step);
}
