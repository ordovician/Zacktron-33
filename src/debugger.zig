const std = @import("std");

const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

const mem = std.mem;
const ascii = std.ascii;
const process = std.process;
const Allocator = std.mem.Allocator;

const Computer = @import("computer.zig").Computer;
const colors =  @import("colors.zig");
const Color = colors.Color;

pub fn runDebugger(comp: *Computer) !void {
    var buffer: [1024]u8 = undefined;
    var done = false;

    while (!done) {
        try stdout.print("{}debug> {}", .{Color.brightboldgreen, Color.reset});
        const nchars = try stdin.read(&buffer);
        if (nchars == buffer.len) {
            try stderr.print("Input too long. Try again\n", .{});
            continue;
        }
        var line: []const u8 = mem.trimRight(u8, buffer[0..nchars], "\r\n");
        line = ascii.lowerString(&buffer, line);

        switch (line[0]) {
            'n' => try comp.stepOutput(stdout),
            'x' => try stdout.print("{}\n", .{comp.regs[line[1]-'0']}),
            'i' => try comp.parseInputs(line[1..]),
            'p' => try stdout.print("{}\n", .{comp}),
            'h' => try stdout.print("n: next\nx1 - x9: register value\ni: input\np: print\nh: help\nq: quit\n", .{}),
            'q' => done = true,
            else => try stderr.print("Unknown command. Use 'q' to quit\n", .{}),
        }
    }
}  


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
        try stderr.print("Usage: debug filename\n", .{});
        try stderr.print("\nInput numbers are read from stdin and are separated by space or newline\n", .{});
        std.os.exit(0);
    }

    var computer = try Computer.loadFile(allocator, filename);
    defer computer.deinit();

    // const inputs = [_]i16{2, 3, 8, 2, 10, 20};
    // try computer.setInputs(inputs[0..]);
    var comp: *Computer = &computer;
    try runDebugger(comp);
}