# Zacktron-33, The Decimal RISC CPU

This is an assembler, disassembler and simulator for an imaginary CPU called Calcutron-33. The rational for this CPU was described first time in [this medium article](https://medium.com/@Jernfrost/decimal-risc-cpu-a13968922812). The original version of this was written in Julia and this is really an exercise in learning and using the Zig programming language. To not confused the Zig version from the Julia version I a calling this the Zacktron-33.

## Example

This is a simple example of the assembly language. In this example we are repeatedly reading two input numbers, multiplying them and writing the result to output.

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

## Remarks on Difference from Julia Implementation
Julia is a high level language and Zig is a low level language, which tend to force a different way of thinking about the problem. In Julia working is text strings is very convenient and easy. In Zig it is often far more verbose to use Zig in a Julia fashion because that involves doing a lot of operations which allocate new memory. E.g. if you want to uppercase a whole string, you need to actually allocate new memory for this new uppercase string.

Functional style programming on collections don't work as well in Zig naturally. So collecting some input from a file and storing in an array is much less practical. In Zig you are more likely to use  iterators, as they allow you to avoid memory allocations.

Thus I am using integer value instead of string to represent the instructions, adding operands is then just a matter of integer operations.

Because I am treating every word on a line by iteration it was more practical to introduce a variable to maintain state in my Zig solution. Thus a switch-case statement allows me to do different things depending on what I determined the previous word was. E.g. was it a label, a mnemonic or operand.

My Julia solution as almost no error handling, but I notice that my Zig solution naturally gravitates towards more error handling. That is a natural outcome of the design of the language which push you towards handling errors.

## Challenges in Implementation
Script language style implementation and thinking don't work well in Zig, you got to think more like a C programmer which take me a bit time getting used to after a long time with Julia.

- When an if-statement needs curly brances and not is often not obvious to me. There seems to be some difference between the usage of expressions and statements.

- Likewise switch statement can be used as a statement or an expression. When used as an expression you need a semicolon at the end.

- Wasted a whole bunch of time trying to figure out if I could iterate over enum values. It does not seem like you can, but then again neither can you in C or C++ either.

- Passing around `Reader` objects to functions doesn't work well. The type is specific to the object it belongs to. I reverted to taking an `fs.File` object as argument instead.

- Wasted time trying to figure out if there was something akin to `-1` like in Python or `end` like in Julia to refer to the last element in a slice. There isn't. Use `slice.len` if you need it. It is simply a struct member.

- Spent a lot of time looking through the Zig source code to understand how `std.StringHashMap` deals with its string keys. Are they automatically deleted when `deinit()` is called?  No Zig does not duplicate strings used as keys. It is your responsibility to deallocate the strings keys. In retrospect this makes sense. Zig is staying low level and doing minimal convieniences for you. That is sort of the point. There is no RAII in Zig, so just deleting stuff automatically would not have been a good idea anyway. 

## Status November 8th 2020
Not all programs will assemble as the pseudo instructions are not all properly handled. There is currently know disassembler and the assembly process only offers output to stdout. Later I want to support writing results to a file of choosing.

    