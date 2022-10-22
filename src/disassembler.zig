const std = @import("std");

const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();
const io = std.io;
const process = std.process;

const Array = std.ArrayList;
const fs = std.fs;
const fmt = std.fmt;
const mem = std.mem;
const ascii = std.ascii;

const File = fs.File;
const Dir = fs.Dir;
const Dict = std.StringHashMap;
const Allocator = std.mem.Allocator;

const debug = std.debug.print;

const common = @import("common.zig");
const colors =  @import("colors.zig");
const Color = colors.Color;
const setColor = colors.setColor;

const ParseError = common.ParseError;
const Opcode = common.Opcode;

/// Check if all characters in string are digits
fn isAllDigits(s: []const u8) bool {
    for (s) |ch| {
        if (!ascii.isDigit(ch))
            return false;
    }
    return true;
}

/// Write disassembled 4-digit instruction to writer which should be 
/// a writer object akind to what you get from a file or stdout
fn disassembleInstruction(instruction: [4]u8, writer: anytype) !void {
    // NOTE: This is implemented quite different from how similar
    // disassembly is done in simulator.zig. That is on purpose.
    // Instead of reusing code I wanted to show different ways
    // of solving the same problem. 

    // Convert from characters to integer numbers
    var digits: [4]u8 = undefined;
    for (instruction) |digit, i| {
        digits[i] = digit - '0';
    }

    const opcode = @intToEnum(Opcode, digits[0]);
    try setColor(writer, Color.boldcyan);
    try writer.print("{s:<4}", .{@tagName(opcode)});
    try setColor(writer, Color.reset);

    const dst = digits[1];
    const src = digits[2];
    const offset = digits[3];

    // address is last two digits
    const addr = 10*src + offset;

    // write out the operands to each mnemonic
    switch (opcode) {
        .ADD, .SUB => try writer.print(" x{}, x{}, x{}\n", .{dst, src, offset}),
        .SUBI, .LSH, .RSH => try writer.print(" x{}, x{}, {}{}{}\n", .{dst, src, Color.brightred, offset, Color.reset}),
        .HLT => try writer.print("\n", .{}),
        else => try writer.print(" x{}, {}{}{}\n", .{dst, Color.brightred, addr, Color.reset}),
    }   
}

fn disassemble(allocator: Allocator, reader: anytype, writer: anytype) !void {
    _ = allocator;


    var buffer: [1024]u8 = undefined;
    const n = try reader.readAll(buffer[0..]);

    var iter = mem.tokenize(u8, buffer[0..n], " \n");
    var i: i32 = 0;
    while (iter.next()) |line| : (i += 1) {
        const instruction = mem.trim(u8, line, " \t");
        try writer.print("{}{}{}: {s};{} ", .{Color.yellow, i, Color.gray, instruction, Color.reset});
        if (instruction[0] == '-') {
            try stdout.print("{}DAT{} {s}{}", .{Color.boldcyan, Color.brightred, instruction, Color.reset});
            continue;
        }

        if (instruction.len != 4) {
            return ParseError.OnlyFourDigitInstructionsAllowed;
        } 

        if (!isAllDigits(instruction))
            return ParseError.InstructionMustBeInteger;


        try disassembleInstruction(instruction[0..4].*, writer);
    }
}

fn disassembleFile(allocator: Allocator, filename: []const u8, writer: anytype) !void {
    const dir: Dir = std.fs.cwd();
    const file: File = try dir.openFile(
        filename,
        .{ .read = true },
    );
    defer file.close();

    try disassemble(allocator, file.reader(), writer);
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
        try stderr.print("Usage: disassemble filename\n", .{});
        std.os.exit(0);
    }

    try disassembleFile(allocator, filename, stdout);
}

// const testing = std.testing;
