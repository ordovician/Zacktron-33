const std = @import("std");

/// Escape codes for colors in a Unix terminal
/// If you print any of these escape codes in a Terminal window then the
/// successive text will have that color
pub const Color = enum(u8) {
    black,
    gray,
    red,
    brightred,
    green,
    brightboldgreen,
    yellow,
    blue,
    brightblue,
    magenta,
    cyan,
    boldcyan,
    white,
    boldwhite,
    reset,
    
    pub fn format(
        color: Color,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const s = switch (color) {
            .black => "\u{001B}[0;30m",
            .gray => "\u{001B}[0;90m",
            .red => "\u{001B}[0;31m",
            .brightred => "\u{001B}[0;91m",
            .green => "\u{001B}[0;32m",
            .brightboldgreen => "\u{001B}[1;92m",
            .yellow => "\u{001B}[0;33m",
            .blue => "\u{001B}[0;34m",
            .brightblue => "\u{001B}[0;94m",
            .magenta => "\u{001B}[0;35m",
            .cyan => "\u{001B}[0;36m",
            .boldcyan => "\u{001B}[1;36m",
            .white => "\u{001B}[0;37m",
            .boldwhite => "\u{001B}[1;37m",
            .reset => "\u{001B}[0;0m",
        };
    
        try writer.print("{s}", .{s});
    }
};

pub fn setColor(writer: anytype, color: Color) !void {
    try writer.print("{}", .{color});
}