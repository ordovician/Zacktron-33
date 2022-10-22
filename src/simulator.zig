const std = @import("std");

const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

const process = std.process;
const Allocator = std.mem.Allocator;

const Computer = @import("computer.zig").Computer;
const colors =  @import("colors.zig");
const Color = colors.Color;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    var filename: []const u8 = "testdata/adder.machine"[0..];

    if (args.len == 2) {
        filename = args[1];
    } else {
        try stderr.print("Usage: simulator filename\n", .{});
        try stderr.print("\nInput numbers are read from stdin and are separated by space or newline\n", .{});
        std.os.exit(0);
    }

    var computer = try Computer.loadFile(allocator, filename);
    defer computer.deinit();

    // const inputs = [_]i16{2, 3, 8, 2, 10, 20};
    // try computer.setInputs(inputs[0..]);
    var comp: *Computer = &computer;
    try comp.readInputs(stdin);

    try comp.run(stdout);
    try stdout.print("\n\n{}CPU state{}\n{}\n", .{Color.boldwhite, Color.reset, computer});
}

