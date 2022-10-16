const std = @import("std");

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

pub const RuntimeError = error{
    AllInputRead,
    ReadingFromUnsupportedAddress,
    WritingToUnsupportedAddress,
};

const Computer = struct {
    allocator: Allocator,
    pc: i16 = 0,         // program counter
    regs: [9]i16,        // value in registers
    memory: []u16,       // stores program and data
    inputs: Array(i16),  // program inputs
    outputs: Array(i16), // outputs from calculations

    const Self = @This();

    // Create a computer with given program. The program is duplicated
    // so the passed argument should be released by caller.
    pub fn load(allocator: Allocator, program: []u16) Self {
        return Self {
            .allocator = allocator,
            .pc = 0,
            .memory = allocator.dupe(u16, program),
            .inputs = Array(i16).init(allocator),
            .outputs = Array(i16).init(allocator),
        };
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.memory);
        self.inputs.deinit();
        self.outputs.deinit;
    }

    fn reset(comp: *Self) void {
        comp.pc = 0;
        for (comp.regs) |_, i| {
            comp.regs[i] = 0;
        }
        comp.inputs.shrinkRetainingCapacity(0);
        comp.outputs.shrinkRetainingCapacity(0);
    }

    fn loadFile(allocator: Allocator, filename: []const u8) ParseError!void {
        const dir: Dir = std.fs.cwd();
        var buffer: [1024]u8 = undefined;
        const program: []const u8 = try dir.readFile(filename, buffer[0..]);
        var instructions = Array(u16).init(allocator);
        defer instructions.deinit();

        var iter = mem.tokenize(u8, program, " \n");
        while (iter.next()) |line| {
            const instruction = fmt.parseInt(u16, line, 10) catch {
                return ParseError.InstructionMustBeInteger;
            };
            instructions.append(instruction);
        }

        return load(allocator, instructions.items);
    }

    fn step(comp: *Self) !void { 
        const ir = comp.memory[comp.pc + 1];
        const regs = comp.regs;

        stdout.print("{}: {}; ", .{comp.pc, ir});

        // There is always a destination register. But source
        // could be an address or two registers
         const opcode: Opcode = @intToEnum(Opcode, (@divTrunc(ir, 1000)));
         const operands = ir % 1000;
         const dst = @divTrunc(operands, 100);
         const addr = operands % 100;
         const src  = @divTrunc(addr, 10);
         const offset = addr % 10;

        var rd = 0;
        if (dst >= 1 and dst <= 9)
            rd = regs[dst];
        switch (opcode) {
            .ADD => rd = regs[src] + regs[offset],
            .SUB => rd = regs[src] - regs[offset],
            .SUBI => rd = regs[src] - offset,
            .LSH => rd = regs[src]*10^offset,
            .RSH => {
                rd = regs[src] % 10^offset;
                regs[src] = @divTrunc(regs[src], 10^offset);
            },
            .BRZ => if (rd == 0) {
                        comp.pc = addr - 1; // Since we are increasing later
                    },                
            .BGT => if (rd > 0) {
                        comp.pc = addr - 1;
                    },
            .LD => if (addr < 90) {
                       rd = comp.memory[addr+1];
                    } else if (addr == 90) {                     
                        rd = comp.inputs.popOrNull() orelse return RuntimeError.AllInputRead;
                    }
                    else {
                        return RuntimeError.ReadingFromUnsupportedAddress;
                    },                
            .ST => if (addr < 90) {
                        comp.memory[addr+1] = rd;                 
                } else if (addr == 91) {
                        comp.outputs.append(rd);

                } else {
                    return RuntimeError.WritingToUnsupportedAddress;
                },
            .HLT => comp.pc -= 1, // To avoid moving forward            
        }

        if (dst >= 1 and dst <= 9)
            rd = regs[dst];

        stdout.print("{}", @tagName(opcode));
        switch (opcode) {
            .ADD, .SUB => stdout.print(" x{}, x{}, x{}\n", .{dst, src, offset}),
            .SUBI, .LSH, .RSH => stdout.print(" x{}, x{}, {}\n", .{dst, src, offset}),
            .HLT => stdout.print("\n", .{}),
            else => stdout.print(" x{}, {}\n", .{dst, addr}),
        }

        comp.pc += 1;
    }

};



pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    var filename: []const u8 = "examples/adder.machine"[0..];

    if (args.len == 2) {
        filename = args[1];
    } else {
        try stderr.print("Usage: simulator filename\n", .{});
    }

}