const std = @import("std");

pub const ParseError = error{
    UnknownOpcode,
    MissingAddress,
    MissingOperand,
    IllegalRegisterName,
};

/// Numerical representation of assembly mnemnonics
/// A opcode basically says what operation to perform on operands.
pub const Opcode = enum(u8) {
    HLT,
    ADD,
    SUB,
    SUBI,
    LSH,
    RSH,
    BRZ,
    BGT,
    LD,
    ST,

    // Psedo instructions
    INP,
    OUT,
    DEC,
    BRA,
    CLR,
    MOV,

    /// Turn a assembly mnemonic into an enum opcode
    pub fn fromString(str: []const u8) !Opcode {
        return std.meta.stringToEnum(Opcode, str) orelse ParseError.UnknownOpcode;
    }

    /// Serve as basis to build up a 4-digit number representing a whole assembly
    /// instruction. Need to  add info to these base number about the registers
    /// addresses and constants used
    pub fn toInteger(opcode: Opcode) u16 {
        return switch (opcode) {
            .HLT => 0,
            .ADD => 1000,
            .SUB => 2000,
            .SUBI => 3000,
            .LSH => 4000,
            .RSH => 5000,
            .BRZ => 6000,
            .BGT => 7000,
            .LD => 8000,
            .ST => 9000,
            // Psedo instructions
            .INP => 8090,
            .OUT => 9091,
            .DEC => 3001,
            .BRA => 6000,
            .MOV => 1000,
            .CLR => 1000,
        };
    }
};
