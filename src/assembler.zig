const std = @import("std");

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();
const io = std.io;
const process = std.process;

const Array = std.ArrayList;
const fs = std.fs;
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

/// A table containing the memory address of labels in the code
fn readSymTable(allocator: Allocator, file: File) !Dict(u8) {
    const reader = file.reader();

    var labels = Dict(u8).init(allocator);
    errdefer labels.deinit();
    var address: u8 = 0;

    var buffer: [500]u8 = undefined;
    while (try reader.readUntilDelimiterOrEof(buffer[0..], '\n')) |tmp_line| {
        const line = mem.trim(u8, tmp_line, " \t");
        const n = line.len;

        if (n == 0) continue;

        if (mem.indexOf(u8, line, ":")) |i| {
            const label = try allocator.dupe(u8, line[0..i]);
            try labels.put(label, address);

            // is there anything beyond the label?
            if (n == i + 1) continue;
        }
        address += 1;
    }

    return labels;
}

/// Turn single line of assembly code into an instruction, represented by a 4-digit unsigned number
/// labels contains addresses of labels in code. Typically these are used to label data or
/// places to jump to in the code.
fn assembleLine(alloc: Allocator, labels: Dict(u8), line: []const u8) !?u16 {
    var code = mem.trim(u8, line, " \t");
    var i = mem.indexOf(u8, code, "//") orelse code.len;
    code = code[0..i];

    const n = code.len;
    if (n == 0 or code[n - 1] == ':') return null;

    i = mem.indexOfScalar(u8, code, ' ') orelse n;
    const mnemonic = code[0..i];

    var iter = mem.tokenize(u8, code[i..], " ,");
    var registers = Array(u16).init(alloc);
    defer registers.deinit();

    var address: ?u8 = null; // address of a label


    while (iter.next()) |operand| {
        if (labels.get(operand)) |addr| {
            address = addr;    
        }
        else if (operand.len == 2 and ascii.isDigit(operand[1])) {
            try registers.append(operand[1] - '0');
        } else {
            const offset = std.fmt.parseInt(u16, operand, 10) catch {
                return ParseError.IllegalRegisterName;
            };
            try registers.append(offset);
        }
    }
    
    const regs = registers.items;

    // DAT isn't a real mnemonic so we got to check for it
    // before turning it into opcodes
    if (mem.eql(u8, mnemonic, "DAT")) {
        return regs[0];
    }

    const opcode = try Opcode.fromString(mnemonic);
    var instruction: u16 = opcode.toInteger(); 

    switch (opcode) {
        .HLT => {},
        .ADD, .SUB => instruction += switch (regs.len) {
                3 => 100*regs[0] + 10*regs[1] + regs[2],
                2 => 100*regs[0] + 10*regs[0] + regs[1],
                else => return ParseError.MissingOperand,
            },
        .SUBI, .LSH, .RSH => instruction += 100*regs[0] + 10*regs[1] + regs[2],
        .LD, .ST, .BRZ, .BGT, .BRA => if (address) |addr| {
                instruction += addr;
                if (regs.len != 0) instruction += 100*regs[0];
            } else {
                return ParseError.MissingAddress;
            },
        .INP, .OUT => instruction += 100*regs[0],
        .DEC => instruction += 100*regs[0] + 10*regs[0],
        .MOV => instruction += 100*regs[0] + regs[1],
        .CLR => instruction += 100*regs[0],
    }

    return instruction;
}

/// Assemble a whole file and write output to writer which must
/// match the type made from std.io.Writer such as std.fs.File.
/// The stdout obtained from std.io.getStdOut().writer() is such a type
fn assemble(allocator: Allocator, file: File, writer: anytype) !void {
    var labels = try readSymTable(allocator, file);
    defer releaseDict(allocator, &labels);

    try file.seekTo(0);
    const reader = file.reader();
    var lineno: i32 = 0;

    var buffer: [500]u8 = undefined;

    // Read each line in source code file
    while (try reader.readUntilDelimiterOrEof(buffer[0..], '\n')) |tmp_line| {
        lineno += 1;
        const line = mem.trim(u8, tmp_line, " \t");
        const maybeInstruction: ?u16 = assembleLine(allocator, labels, line) catch |err| {
            switch (err) {
                ParseError.IllegalRegisterName => try stderr.print("{d}: Invalid register name or unknown label: {s}\n", .{ lineno, line }),
                ParseError.UnknownOpcode => try stderr.print("{d}: Could not parse mnemonic: {s}\n", .{ lineno, line }),
                else => break,
            }
            
            return err;
        };

        if (maybeInstruction) |instruction|
            try writer.print("{d:0<4}\n", .{instruction});
    }
}

/// Assemble code in filename and write result to writer which must be a type made
/// from std.io.Writer such as std.fs.File
/// The stdout obtained from std.io.getStdOut().writer() is such a type
fn assembleFile(allocator: Allocator, filename: []const u8, writer: anytype) !void {
    const dir: Dir = std.fs.cwd();
    const file: File = try dir.openFile(
        filename,
        .{ .read = true },
    );
    defer file.close();

    try assemble(allocator, file, writer);
}

/// Releases key allocated to dictionary
fn releaseDict(allocator: Allocator, dict: *Dict(u8)) void {
    var iter = dict.iterator();
    while (iter.next()) |entry|
        allocator.free(entry.key_ptr.*);
    dict.deinit();    
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    var filename: []const u8 = "examples/adder.ct33"[0..];

    if (args.len == 2) {
        filename = args[1];
    } else {
        try stderr.print("Usage: assembler filename\n", .{});
        try stderr.print("\nAssembly of {s}:\n", .{filename});
    }

    try assembleFile(allocator, filename, stdout);
}

// Tests
const expect = std.testing.expect;

// helper struct to hold assembly code and the corresponding machine code instruction
const AssemTest = struct {
    src: []const u8,
    inst: u16,
};

// add instruction to this list if you are uncertain if specific
// instruction are being turned into machine code correctly
test "individual instructions" {
    const allocator = std.testing.allocator;
    var labels = Dict(u8).init(allocator);

    const lines = [_]AssemTest{
        .{ .src = "INP x1", .inst = 8190 },
        .{ .src = "INP x2", .inst = 8290 },
        .{ .src = "CLR x3", .inst = 1300 },
        .{ .src = "OUT x3", .inst = 9391 },
        .{ .src = "ADD x3, x1",  .inst = 1331 },
        .{ .src = "CLR x3", .inst = 1300 },
        .{ .src = "DEC x2", .inst = 3221 },
        .{ .src = "SUBI x9, x8, 7", .inst = 3987 },
        .{ .src = "MOV x9, x8", .inst = 1908 },
    };

    for (lines) |line| {
        const maybeInst: ?u16 = try assembleLine(allocator, labels, line.src);
        const instruction = maybeInst orelse continue;
        // try stdout.print("{s} : {}\n", .{line.sr, instruction});
        std.testing.expectEqual(line.inst, instruction) catch |err| {
            try stderr.print("Expected '{s}' to assemble into {} not {}\n", .{line.src, line.inst, instruction});
            return err;
        };
    }
}

// check our parsing of labels (used as jump spots and for data)
test "only labels" {
    const allocator = std.testing.allocator;

    const dir: Dir = std.fs.cwd();
    const file: File = try dir.openFile(
         "testdata/labels-nocode.ct33",
        .{ .read = true },
    );
    defer file.close();

    var labels: Dict(u8) = try readSymTable(allocator, file);
    defer releaseDict(allocator, &labels);

    const keys = [_][]const u8{"alpha", "epsilon", "gamma", "delta", "beta"};
    for (keys) |key| {
        try expect(labels.contains(key));
    }
}

// In testdata folder I have put a bunch of machine code files, previously assembled.
// test against these to make sure that when we assembly the original source code
// again we don't have a regression in the code
test "regression tests" {
    const allocator = std.testing.allocator;
    
    const cwd = std.fs.cwd();
    const dir: Dir = try cwd.openDir("testdata", .{.iterate = true});
    //var binary_filename: [100]u8 = undefined;
    var expected_buffer: [512]u8 = undefined;
    var gotten_buffer: [512]u8 = undefined;

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const filename: []const u8 = entry.name;
        if (!mem.endsWith(u8, filename, ".ct33")) continue;

        const binary_filename = try mem.replaceOwned(u8, allocator, filename, "ct33", "machine");
        defer allocator.free(binary_filename);

        // const binaryfile: File = try dir.openFile(binaryfile, .{.read = true});
        const expected: []const u8 = dir.readFile(binary_filename, expected_buffer[0..]) catch {
            // try stderr.print("Couldn't open file {s} because {}\n", .{binary_filename, err});
            continue;
        };
        
        var source = io.StreamSource{ 
            .buffer = io.fixedBufferStream(&gotten_buffer)
        };

        const srcfile: File = dir.openFile(filename, .{ .read = true }) catch |err| {
            try stderr.print("Couldn't open file {s} because {}\n", .{filename, err});
            return err;
        };        
        defer srcfile.close();
        assemble(allocator, srcfile, source.writer()) catch |err| {
            try stderr.print("Assemble of {s} failed because of {}\n", .{filename, err});
            return err;
        };

        const gotten = source.buffer.getWritten();
        expect(mem.eql(u8, gotten, expected)) catch |err| {
            try stderr.print("{s} got:\n{s}\n", .{filename, gotten});
            try stderr.print("{s} expected:\n{s}\n", .{binary_filename, expected});
            return err;
        };
        // try stdout.print("{s}\n", .{filename});
    }
}
