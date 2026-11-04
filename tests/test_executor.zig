const std = @import("std");
const parser = @import("parser");
const executor = @import("executor");

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    const parsed = try parser.parse("cat < entrada.txt");

    try executor.executeExternal(io, &parsed);
}
