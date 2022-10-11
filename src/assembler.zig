const std = @import("std");

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();
const io = std.io;
const process = std.process;

//const ArrayList = std.ArrayList;
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

fn readSymTable(allocator: Allocator, file: File) !Dict(i16) {
    const reader = file.reader();

    var labels = Dict(i16).init(allocator);
    errdefer labels.deinit();
    var address: i16 = 0;

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
    mnemonic,
    operands,
    comment,
};

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
        // debug("{}: {} -> ", .{ lineno, line });

        if (line.len == 0) continue;
        var iter = mem.tokenize(u8, line, " ,");

        var state: State = .mnemonic;
        var instruction: i32 = -1;
        var opscale: i32 = 100; // scaling factor for operand.

        // Process each part of the instruction on a line
        while (iter.next()) |word| {
            const n = word.len;
            switch (state) {
                .mnemonic => if (word[n - 1] != ':') {
                    state = .operands;
                    const opcode = Opcode.fromString(word) catch |err| {
                        try stderr.print("{d}: Could not parse mnemonic: {s}\n", .{ lineno, line });
                        return err;
                    };
                    instruction = @enumToInt(opcode);
                },
                .operands => if (labels.get(word)) |addr| {
                    instruction += addr;
                    state = .comment;
                } else if (n == 2 and ascii.isDigit(word[1])) {
                    instruction += opscale * @as(i32, (word[1] - '0'));
                    
                    // We reduce opscale by 10 on each iteration to place
                    // digit representing register at correct position
                    // SUB x3, x1, x2 turns into 2312
                    // When word == "x3" we extract 3 and multiply by hundred to get right position
                    // while when we get to word == "x1" we got to multiply by ten to get right position
                    if (opscale <= 1) {
                        state = .comment;
                    } else {
                        opscale = @divTrunc(opscale, 10);
                    }
                } else {
                    try stderr.print("{d}: Invalid register name or unknown label: {s}\n", .{ lineno, word });
                    // debug("Addr: {}\n", .{labels.get("first")});

                    return ParseError.IllegalRegisterName;
                },
                .comment => break,
            }
        }
        if (instruction >= 0)
            try writer.print("{}\n", .{instruction});
    }

    // var iter = labels.iterator();
    
    // while (iter.next()) |entry| {
    //     try stdout.print("Key: {s}, Value: {d}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    // }
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

fn releaseDict(allocator: Allocator, dict: *Dict(i16)) void {
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

test "only labels" {
    const allocator = std.testing.allocator;

    const dir: Dir = std.fs.cwd();
    const file: File = try dir.openFile(
         "testdata/labels-nocode.ct33",
        .{ .read = true },
    );
    defer file.close();

    var labels: Dict(i16) = try readSymTable(allocator, file);
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