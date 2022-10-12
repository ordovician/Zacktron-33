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

const ParseError = error{
    UnknownOpcode,
    IllegalRegisterName,
};

const Opcode = enum(i32) {
    HLT = 0,
    ADD = 1000,
    SUB = 2000,
    SUBI = 3000,
    LSH = 4000,
    RSH = 5000,
    BRZ = 6000,
    BGT = 7000,
    LD = 8000,
    ST = 9000,

    // Psedo instructions
    INP = 8090,
    OUT = 9091,
    DEC = 3001,

    fn fromString(str: []const u8) !Opcode {
        const opcodes = [_]Opcode{
            .HLT,
            .ADD,
            .SUB,
            .SUBI,
            .LSH,
            .RSH,
            .BRZ,
            .BGT,
            .LD,
            .ST,
            .INP,
            .OUT,
            .DEC,
        };
        for (opcodes) |op| {
            if (ascii.eqlIgnoreCase(@tagName(op), str)) {
                return op;
            }
        }
        if (ascii.eqlIgnoreCase("BRA", str)) {
            return .BRZ;
        } else if (ascii.eqlIgnoreCase("CLR", str))
            return .ADD; 
        return ParseError.UnknownOpcode;
    }
};

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

const State = enum {
    operands,
    comment,
};

/// Turn single line of assembly code into an instruction
fn assembleLine(alloc: Allocator, labels: Dict(u8), line: []const u8) !?i32 {
    var code = mem.trim(u8, line, " \t");
    var i = mem.indexOf(u8, code, "//") orelse code.len;
    code = code[0..i];

    const n = code.len;
    if (n == 0 or code[n - 1] == ':') return null;

    i = mem.indexOfScalar(u8, code, ' ') orelse n;
    const mnemonic = code[0..i];

    var iter = mem.tokenize(u8, code[i..], " ,");
    var registers = Array(u8).init(alloc);
    defer registers.deinit();

    var address: ?u8 = null; // address of a label


    while (iter.next()) |operand| {
        if (labels.get(operand)) |addr| {
            address = addr;    
        }
        else if (operand.len == 2 and ascii.isDigit(operand[1])) {
            try registers.append(operand[1] - '0');
        } else {
            return ParseError.IllegalRegisterName;
        }
    }

    const opcode = try Opcode.fromString(mnemonic);
    var instruction: i32 = @enumToInt(opcode); 
    const regs = registers.items;

    if (regs.len >= 1)
        instruction += @as(i32, regs[0]) * 100;
    if (regs.len == 3) {
        instruction += regs[1] * 10;
        instruction += regs[2];
    }
    if (address) |addr| {
        instruction += addr;
    } else if (regs.len < 3) {
        instruction += regs[0] * 10;
        if (regs.len == 2) instruction += regs[1];
    }
    
    return instruction;
}

/// Assemble a whole file and write output to writer which must
/// match the type made from std.io.Writer
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
        const maybeInstruction: ?i32 = assembleLine(allocator, labels, line) catch |err| {
            switch (err) {
                ParseError.IllegalRegisterName => try stderr.print("{d}: Invalid register name or unknown label: {s}\n", .{ lineno, line }),
                ParseError.UnknownOpcode => try stderr.print("{d}: Could not parse mnemonic: {s}\n", .{ lineno, line }),
                else => break,
            }
            
            return err;
        };

        if (maybeInstruction) |instruction|
            try writer.print("{}\n", .{instruction});
    }
}

fn assembleFile(allocator: Allocator, filename: []const u8, writer: anytype) !void {
    const dir: Dir = std.fs.cwd();
    const file: File = try dir.openFile(
        filename,
        .{ .read = true },
    );
    defer file.close();

    try assemble(allocator, file, writer);
}

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

test "string operations" {
    const allocator = std.testing.allocator;

    const line = "ADD x3, x1";
    // const jmpstr = "BGT x4, multiply";

    var labels = Dict(u8).init(allocator);
    defer labels.deinit();
    try labels.put("foo", 42);
    try labels.put("bar", 88);

    const maybe = try assembleLine(allocator, labels, line);
    if (maybe) |instruction| {
        debug("Parse of {s} = {}\n", .{line, instruction});
    }
}

test "individual instructions" {
    const allocator = std.testing.allocator;
    var labels = Dict(u8).init(allocator);

    const lines = [_][]const u8{
        "ADD x3, x1", 
        "CLR x3",
        "DEC x2",
    };

    for (lines) |line| {
        const maybeInst: ?i32 = try assembleLine(allocator, labels, line);
        const instruction = maybeInst orelse continue;
        try stdout.print("{s} : {}\n", .{line, instruction});
    }

    const instruction = (try assembleLine(allocator, labels, "ADD x3, x1")).?;
    try stdout.print("ADD x3, x1 : {}\n", .{instruction});
}

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
