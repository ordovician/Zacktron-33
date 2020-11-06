# Zacktron-33, The Decimal RISC CPU

This is an assembler, disassembler and simulator for an imaginary CPU called Calcutron-33. The rational for this CPU was described first time in [this medium article](https://medium.com/@Jernfrost/decimal-risc-cpu-a13968922812). The original version of this was written in Julia and this is really an excercise in learning and using the Zig programming language. To not confused the Zig version from the Julia version I a calling this the Zacktron-33.

## Example

This is a simple example of the assembly language. In this example we are repeately reading two input numbers, multiplying them and writing the result to output.

    loop:
        INP x1
        INP x2
        CLR x3
    
    multiply:
        ADD x3, x1
        DEC x2
        BGT x2, multiply
        OUT x3
    
        BRA loop
    
Unlike Little Man Computer, which has only one register this has a more RISC like architecture with 9 register `x1` to `x9`. 

Branching is done similar to MIPS. One compares the contents of a register to 0. So e.g. `BGT x2, multiply` will make a jump to `multiply` if the contents of `x2` register is larger than 0.
