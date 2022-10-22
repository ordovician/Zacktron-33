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

fn disassembleInstruction(instruction: [4]u8, writer: anytype) !void {
    _ = writer;
    _ = instruction;
}

fn disassemble(allocator: Allocator, reader: anytype, writer: anytype) !void {
    _ = allocator;


    var buffer: [1024]u8 = undefined;
    const n = try reader.readAll(buffer[0..]);

    var iter = mem.tokenize(u8, buffer[0..n], " \n");
    while (iter.next()) |line| {
        const instruction = mem.trim(u8, line, " \t");
        if (instruction[0] == '-') {
            try stdout.print("DAT {s}", .{instruction});
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
