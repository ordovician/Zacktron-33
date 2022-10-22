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

## Install and Usage
You can use the the `zig build --help` command to get overview over how to build and use the files.  

    ❯ zig build --help
    Usage: zig build [steps] [options]

    Steps:
    install (default)            Copy build artifacts to prefix path
    uninstall                    Remove build artifacts from prefix path
    assemble                     Run the assembler
    simulate                     Run the simulator
    disassemble                  Run the disassembler

Running `zig build` will create three executables `assemble`, `simulate` and `disassemble` in the `zig-out` directory. You can install built executable anywhere with the `zig build install` command. To install in the current directory, you can write:

    ❯ zig build install -p . --prefix-exe-dir .

To build and run an executable directly you can write the following:

    ❯ zig build assemble
    ❯ zig build simulate

Once you have the `assemble` and `simulate` programs you can use them to assemble `.ct33` programs into `.machine` code which can be run by the simulator. For instance this will assemble the bundled `adder.ct33` program:

    ❯ assemble testdata/adder.ct33 > adder.machine

You can later run the this program in the simulator. Programs read input from stdin, so you can either type input on the keyboard when the program runs or you can redirect some input. Input numbers are separated by space or newline.

    ❯ echo 2 3 8 4 | simulate adder.machine
    0: 8190; LD x1, 90
    1: 8290; LD x2, 90
    2: 1112; ADD x1, x1, x2
    3: 9191; ST x1, 91
    4: 6000; BRZ x0, 0
    0: 8190; LD x1, 90
    1: 8290; LD x2, 90
    2: 1112; ADD x1, x1, x2
    3: 9191; ST x1, 91
    4: 6000; BRZ x0, 0
    0: 8190;

    CPU state
    PC: 0
    x0: 0, x1: 12, x2: 4, x3: 0, x4: 0, x5: 0, x6: 0, x7: 0, x8: 0, x9: 0,
    Inputs:
    Output: 5, 12,

Here we feed in the numbers 2, 3, 8 and 4 into the simulator as  inputs. You can then see what line of code is executed in sequence. The first machine code instruction executed is 8190 which disassembled turns into a load instruction `LD x1, 90`. The 5th  machine code instruction is 6000 which causes a branch to the start of the program. That is why you see the 1st machine code instruction over again.

When there is no more input or a `HLT` instruction is hit the simulator will write out the state of the virtual CPU. You can see the contents of its program counter (PC) and registers (x1 to x9). x0 is not in use. x0 will always be 0.

You will see inputs and outputs as well. Inputs are added as pairs, thus output is the result of 2+3, 8+4 which equals 5, 12.

We can also disassemble machine code. When you write assembly code you will use labels and pseudo instructions such as `INP`, `OUT`, `CLR` and `DEC`. When you disassemble you will instead see what these pseudo instructions map to.

    ❯ /disassemble  testdata/adder.machine
    0: 8190; LD x1, 90
    1: 8290; LD x2, 90
    2: 1112; ADD x1, x1, x2
    3: 9191; ST x1, 91
    4: 6000; BRZ x0, 0

Notice how the `INP` instruction maps to a load, `LD`, instruction which loads from memory address 90. The always branch instruction `BRA` actually maps to a conditional instruction, `BRZ`, which checks register `x0`, which is hardwired to always be zero.

## Remarks on Difference from Julia Implementation
Julia is a high level language and Zig is a low level language, which tend to force a different way of thinking about the problem. In Julia working is text strings is very convenient and easy. In Zig it is often far more verbose to use Zig in a Julia fashion because that involves doing a lot of operations which allocate new memory. E.g. if you want to uppercase a whole string, you need to actually allocate new memory for this new uppercase string.

Functional style programming on collections don't work as well in Zig naturally. So collecting some input from a file and storing in an array is much less practical. In Zig you are more likely to use  iterators, as they allow you to avoid memory allocations.

Thus I am using integer value instead of string to represent the instructions, adding operands is then just a matter of integer operations.

Because I am treating every word on a line by iteration it was more practical to introduce a variable to maintain state in my Zig solution. Thus a switch-case statement allows me to do different things depending on what I determined the previous word was. E.g. was it a label, a mnemonic or operand.

My Julia solution as almost no error handling, but I notice that my Zig solution naturally gravitates towards more error handling. That is a natural outcome of the design of the language which push you towards handling errors.

## Challenges in Implementation
Script language style implementation and thinking don't work well in Zig, you got to think more like a C programmer which take me a bit time getting used to after a long time with Julia.

- When an if-statement needs curly braces and not is often not obvious to me. There seems to be some difference between the usage of expressions and statements.

- Likewise switch statement can be used as a statement or an expression. When used as an expression you need a semicolon at the end.

- Wasted a whole bunch of time trying to figure out if I could iterate over enum values. It does not seem like you can, but then again neither can you in C or C++ either.

- Passing around `Reader` objects to functions doesn't work well. The type is specific to the object it belongs to. I reverted to taking an `fs.File` object as argument instead.

- Wasted time trying to figure out if there was something akin to `-1` like in Python or `end` like in Julia to refer to the last element in a slice. There isn't. Use `slice.len` if you need it. It is simply a struct member.

- Spent a lot of time looking through the Zig source code to understand how `std.StringHashMap` deals with its string keys. Are they automatically deleted when `deinit()` is called?  No Zig does not duplicate strings used as keys. It is your responsibility to deallocate the strings keys. In retrospect this makes sense. Zig is staying low level and doing minimal conveniences for you. That is sort of the point. There is no RAII in Zig, so just deleting stuff automatically would not have been a good idea anyway. 



    