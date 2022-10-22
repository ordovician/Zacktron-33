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

pub const RuntimeError = error{
    AllInputRead,
    ReadingFromUnsupportedAddress,
    WritingToUnsupportedAddress,
    UnsupportedOpcode,
};

const Computer = struct {
    allocator: Allocator,
    pc: usize = 0,         // program counter
    regs: [10]i16,        // value in registers
    memory: []i16,       // stores program and data
    inputs: Array(i16),  // program inputs
    outputs: Array(i16), // outputs from calculations

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
         return Self {
            .allocator = allocator,
            .pc = 0,
            .memory = []i16{},
            .inputs = Array(i16).init(allocator),
            .outputs = Array(i16).init(allocator),
            .regs = [10]i16{0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        };       
    }

    // Create a computer with given program. The program is duplicated
    // so the passed argument should be released by caller.
    pub fn load(allocator: Allocator, program: []i16) !Self {
        return Self {
            .allocator = allocator,
            .pc = 0,
            .memory = try allocator.dupe(i16, program),
            .inputs = Array(i16).init(allocator),
            .outputs = Array(i16).init(allocator),
            .regs = [10]i16{0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        };
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.memory);
        self.inputs.deinit();
        self.outputs.deinit();
    }

    pub fn reset(comp: *Self) void {
        comp.pc = 0;
        for (comp.regs) |_, i| {
            comp.regs[i] = 0;
        }
        comp.inputs.shrinkRetainingCapacity(0);
        comp.outputs.shrinkRetainingCapacity(0);
    }

    /// Add inputs to program. Read by INP instruction
    pub fn addInputs(comp: *Self, inputs: []const i16) !void {
        // inputs are stored in reverse order so we can pop from the end
        // rather than the fron which would be less efficient
        var i: usize = inputs.len;
        while (i > 0) {
            i -= 1;
            try comp.inputs.append(inputs[i]);
        }      
    }

    /// Set inputs to program. Read by INP instruction
    pub fn setInputs(comp: *Self, inputs: []const i16) !void {
        comp.inputs.shrinkRetainingCapacity(0);
        try comp.addInputs(inputs);
    }

    /// Helpful to read inputs from stdin or a file
    /// reader can be the reader of a file or stdin.
    pub fn readInputs(comp: *Self, reader: anytype) !void {
        var buffer: [1024]u8 = undefined;
        const n = try reader.readAll(buffer[0..]);

        var iter = mem.tokenize(u8, buffer[0..n], " \n");
        while (iter.next()) |line| {
            const input = fmt.parseInt(i16, line, 10) catch {
                return ParseError.InputMustBeInteger;
            };
            try comp.inputs.append(input);
        }
        mem.reverse(i16, comp.inputs.items);
    }   

    pub fn loadFile(allocator: Allocator, filename: []const u8) !Self {
        const dir: Dir = std.fs.cwd();
        var buffer: [1024]u8 = undefined;
        const program: []const u8 = try dir.readFile(filename, buffer[0..]);
        var instructions = Array(i16).init(allocator);
        defer instructions.deinit();

        var iter = mem.tokenize(u8, program, " \n");
        while (iter.next()) |line| {
            const instruction = fmt.parseInt(i16, line, 10) catch {
                return ParseError.InstructionMustBeInteger;
            };
            try instructions.append(instruction);
        }

        return load(allocator, instructions.items);
    }

    pub fn step(comp: *Self) !void { 
        const ir = comp.memory[comp.pc];
        var regs: []i16 = comp.regs[0..];

        try stdout.print("{}: {}; ", .{comp.pc, ir});

        // There is always a destination register. But source
        // could be an address or two registers
        const opcode: Opcode = @intToEnum(Opcode, (@divTrunc(ir, 1000)));
        const operands = @rem(ir, 1000);
        const dst = @intCast(u8, @divTrunc(operands, 100));
        const addr: u8 = @intCast(u8, @rem(operands, 100));
        const src  = @intCast(u8, @divTrunc(addr, 10));
        const offset: u8 = @intCast(u8, @rem(addr, 10));

        // debug("\nsrc: {}, dst: {}, offset: {}\n", .{src, dst, offset});
        // debug("regs[src]: {}, regs[offset] {}\n", .{regs[src], regs[offset]});
        // debug("rd: {}\n", .{regs[dst]});

        var rd: i16 = 0;
        if (dst >= 1 and dst <= 9)
            rd = regs[dst];
        switch (opcode) {
            .ADD => rd = regs[src] + regs[offset],
            .SUB => rd = regs[src] - regs[offset],
            .SUBI => rd = regs[src] - offset,
            .LSH => rd = regs[src]*10^offset,
            .RSH => {
                rd = @rem(regs[src], 10^offset);
                regs[src] = @divTrunc(regs[src], 10^offset);
            },
            .BRZ => if (rd == 0) {
                        comp.pc = addr;
                    } else {
                        comp.pc += 1;
                    },                
            .BGT => if (rd > 0) {
                        comp.pc = addr;
                    } else {
                        comp.pc += 1;
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
                    try comp.outputs.append(rd);

                } else {
                    return RuntimeError.WritingToUnsupportedAddress;
                },
            .HLT => {}, // To avoid moving forward
            else => return RuntimeError.UnsupportedOpcode,      
        }

        if (dst >= 1 and dst <= 9)
            regs[dst] = rd;

        try stdout.print("{s}", .{@tagName(opcode)});
        switch (opcode) {
            .ADD, .SUB => try stdout.print(" x{}, x{}, x{}\n", .{dst, src, offset}),
            .SUBI, .LSH, .RSH => try stdout.print(" x{}, x{}, {}\n", .{dst, src, offset}),
            .HLT => try stdout.print("\n", .{}),
            else => try stdout.print(" x{}, {}\n", .{dst, addr}),
        }

        // If we did a branch, then we have already set PC to the right new address
        if (opcode != .BRZ and opcode != .BGT and opcode != .HLT)
            comp.pc += 1;
    }

    pub fn run(comp: *Computer) !void {
        try runSteps(comp, 100);
    }

    pub fn runSteps(comp: *Computer, nsteps: i32) !void {
        var i:i32 = 0;
        while (i < nsteps) : (i += 1) {
            const pc = comp.pc;
            comp.step() catch |err| {
                switch (err) {
                    RuntimeError.AllInputRead => break,
                    else => return err,
                }
            };

            if (comp.pc == pc) {
                break;
            } 
        }
    }

    pub fn format(
        comp: Computer,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("PC: {}\n", .{comp.pc});
        
        // Register content
        for (comp.regs) |reg, i| {
            try writer.print("x{}: {}, ", .{i, reg});
        }
        try writer.print("\n", .{});

        // Inputs
        try writer.print("Inputs: ", .{});
        const inputs = comp.inputs.items;
        var i: usize = inputs.len;
        while (i > 0) {
            i -= 1;
            try writer.print("{}, ", .{inputs[i]});
        }

        try writer.print("\n", .{});

        // Outputs
        try writer.print("Output: ", .{});
        for (comp.outputs.items) |output| {
            try writer.print("{}, ", .{output});
        }
        try writer.print("\n", .{});
    }

};



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

    try comp.run();
    try stdout.print("\n\nCPU state\n{}\n", .{computer});
}

const testing = std.testing;

test "individual instructions" {
    const allocator = std.testing.allocator;

    var program = [_]i16{
        8190, // INP x1
        8290, // INP x2
        1300, // CLR x3
        3221, // DEC x2
        3987, // SUBI x9, x8, 7
        1908, // MOV x9, x8
    };

    var computer = try Computer.load(allocator, program[0..]);
    defer computer.deinit();

    const inputs = [_]i16{2, 3, 8};

    // Just to have some inputs to play with
    try computer.setInputs(inputs[0..]);

    try computer.step();
    try testing.expectEqual(computer.regs[1], 2);

    try computer.step();
    try testing.expectEqual(computer.regs[2], 3);

    computer.regs[3] = 42; // just so we can check if CLR x3 works
    try computer.step();
    try testing.expectEqual(computer.regs[3], 0); 

    // Check DEC x2
    try computer.step();
    try testing.expectEqual(computer.regs[2], 2); // should be 3 before decrement

    // Check SUBI x9, x8, 7    
    computer.regs[8] = 10;
    try computer.step();
    try testing.expectEqual(computer.regs[9], 3);

    // Check MOV x9, x8
    try computer.step();
    try testing.expectEqual(computer.regs[9], 10);    
}    

test "adder program" {
   const allocator = std.testing.allocator;

    var program = [_]i16{
        8190, // INP x1
        8290, // INP x2
        1112, // ADD x1, x2
        9191, // OUT x1
        6000, // BRA 0
    };

    var computer = try Computer.load(allocator, program[0..]);
    defer computer.deinit();

    const inputs = [_]i16{2, 3, 8, 4};

    // Just to have some inputs to play with
    try computer.setInputs(inputs[0..]);

    // Check that we are the start of program
    try testing.expectEqual(computer.pc, 0);

    try computer.step();
    try testing.expectEqual(computer.regs[1], 2);

    try computer.step();
    try testing.expectEqual(computer.regs[2], 3);

    try computer.step();
    try testing.expectEqual(computer.regs[1], 5);
    try testing.expectEqual(computer.outputs.items.len, 0);

    // check that result got written to output
    try computer.step();
    try testing.expectEqual(computer.outputs.items.len, 1);
    try testing.expectEqual(computer.outputs.items[0], 5); 

    // check that we are at end of program
    try testing.expectEqual(computer.pc, 4);

    // check that jump in program happens
    try computer.step();
    try testing.expectEqual(computer.pc, 0);

    // check that next number is loaded from input
    try computer.step();
    try testing.expectEqual(computer.regs[1], 8);    
}

test "maximizer program" {
    const allocator = std.testing.allocator;

    var computer = try Computer.loadFile(allocator, "examples/maximizer.machine");
    defer computer.deinit();

    const inputs = [_]i16{2, 3, 8, 10};
    const outputs = [_]i16{3, 10};

    try computer.setInputs(inputs[0..]);
    try computer.run();

    try testing.expectEqualSlices(i16, computer.outputs.items, outputs[0..]);
}