const std = @import("std");

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

const fs = std.fs;
const mem = std.mem;
const ascii = std.ascii;

const File = fs.File;
const Dir = fs.Dir;
const Dict = std.StringHashMap;
const Allocator = std.mem.Allocator;
const Reader = std.io.Reader;

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
        if (ascii.eqlIgnoreCase("BRA", str))
            return .BRZ;
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

fn assemble(allocator: Allocator, file: File) !void {
    var labels = try readSymTable(allocator, file);
    defer {
        var iter = labels.iterator();
        while (iter.next()) |entry|
            allocator.free(entry.key_ptr.*);
        labels.deinit();
    }

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
            try stdout.print("{}\n", .{instruction});
    }

    // var iter = labels.iterator();
    
    // while (iter.next()) |entry| {
    //     try stdout.print("Key: {s}, Value: {d}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    // }
}

fn assembleFile(allocator: Allocator, filename: []const u8) !void {
    const dir: Dir = std.fs.cwd();
    const file: File = try dir.openFile(
        filename,
        .{ .read = true },
    );
    defer file.close();

    try assemble(allocator, file);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try assembleFile(allocator, "examples/maximizer.ct33");

    // const reader = file.reader();
    //
    // var labels = try readSymTable(allocator, reader);

    //

    // const content = try reader.readAllAlloc(allocator, 1024);
    // defer allocator.free(content);
    //
    // try stdout.print("{}\n", .{content});
}
