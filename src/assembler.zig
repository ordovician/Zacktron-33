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

const Opcode = enum(u32) {
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
        return ParseError.UnknownOpcode;
    }
};

fn readSymTable(allocator: *Allocator, file: File) !Dict(u16) {
    const reader = file.reader();
    var labels = Dict(u16).init(allocator);
    errdefer labels.deinit();
    var address: u16 = 0;

    var buffer: [500]u8 = undefined;
    while (try reader.readUntilDelimiterOrEof(buffer[0..], '\n')) |line| {
        var iter = mem.split(line, " ");
        if (iter.next()) |label| {
            if (label.len > 0 and label[label.len - 1] == ':') {
                const duplabel = try mem.dupe(allocator, u8, label);
                try labels.put(duplabel, address);
            } else {
                address += 1;
                continue;
            }
        }
        if (iter.next()) |_|
            address += 1;
    }

    return labels;
}

const State = enum {
    mnemonic,
    operands,
    comment,
};

fn assemble(allocator: *Allocator, file: File) !void {
    var labels = try readSymTable(allocator, file);
    defer {
        var iter = labels.iterator();
        while (iter.next()) |entry| allocator.free(entry.key);
        labels.deinit();
    }

    try file.seekTo(0);
    const reader = file.reader();

    var buffer: [500]u8 = undefined;
    while (try reader.readUntilDelimiterOrEof(buffer[0..], '\n')) |tmp_line| {
        const line = mem.trim(u8, tmp_line, " \t");
        if (line.len == 0) continue;
        var iter = mem.tokenize(line, " ,");

        var state: State = .mnemonic;
        var instruction: u32 = 0;
        var opscale: u32 = 100; // scaling factor for operand.

        while (iter.next()) |word| {
            const n = word.len;
            switch (state) {
                .mnemonic => if (word[n - 1] != ':') {
                    state = .operands;
                    const opcode = Opcode.fromString(word) catch |err| {
                        try stderr.print("Could not pase mnemonic: {}\n", .{line});
                        return err;
                    };
                    instruction = @enumToInt(opcode);
                },
                .operands => if (n == 2 and ascii.isDigit(word[1])) {
                    instruction += opscale * (word[1] - '0');
                    if (opscale <= 1) {
                        state = .comment;
                    } else {
                        opscale /= 10;
                    }
                } else {
                    try stderr.print("Ivalid register name: {}\n", .{word});
                    return ParseError.IllegalRegisterName;
                },
                .comment => break,
            }
        }
    }

    // var iter = labels.iterator();
    //
    // while (iter.next()) |entry| {
    //     try stdout.print("Key: {}, Value: {}\n", .{ entry.key, entry.value });
    // }
}

fn assembleFile(allocator: *Allocator, filename: []const u8) !void {
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
    var allocator = &gpa.allocator;

    try assembleFile(allocator, "examples/maximizer.ct33");

    // const op: Opcode = .ADD;
    try stdout.print("Opcode: {}\n", .{Opcode.fromString("hLto")});
    // const reader = file.reader();
    //
    // var labels = try readSymTable(allocator, reader);

    //

    // const content = try reader.readAllAlloc(allocator, 1024);
    // defer allocator.free(content);
    //
    // try stdout.print("{}\n", .{content});
}
