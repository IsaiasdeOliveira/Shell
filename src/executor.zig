
const std = @import("std");
const parser = @import("parser");

pub const ExecuteError = error{
    EmptyCommand,
    MultipleCommandsNotSupportedYet,
};

/// Executa um comando externo com suporte a redirecionamentos.
pub fn executeExternal(
    io: std.Io,
    parsed: *const parser.ParsedLine,
) !void {
    if (parsed.command_count > 1) {
        return error.MultipleCommandsNotSupportedYet;
    }

    if (parsed.command_count == 0) {
        return error.EmptyCommand;
    }

    const command = &parsed.commands[0];

    if (command.arg_count == 0) {
        return error.EmptyCommand;
    }

    const argv = command.args[0..command.arg_count];

    var input_file: ?std.Io.File = null;
    var output_file: ?std.Io.File = null;
    var error_file: ?std.Io.File = null;

    defer {
        if (input_file) |file| {
            file.close(io);
        }

        if (output_file) |file| {
            file.close(io);
        }

        if (error_file) |file| {
            file.close(io);
        }
    }

    // Redirecionamento de entrada: <
    const stdin: std.process.SpawnOptions.StdIo =
        if (command.input_file) |path| blk: {
            input_file = try std.Io.Dir.cwd().openFile(io, path, .{});
            break :blk .{ .file = input_file.? };
        } else .inherit;

    // Redirecionamento de saída: >
    const stdout: std.process.SpawnOptions.StdIo =
        if (command.output_file) |path| blk: {
            output_file = try std.Io.Dir.cwd().createFile(io, path, .{});
            break :blk .{ .file = output_file.? };
        } else .inherit;

    // Redirecionamento de erro: 2>
    const stderr: std.process.SpawnOptions.StdIo =
        if (command.error_file) |path| blk: {
            error_file = try std.Io.Dir.cwd().createFile(io, path, .{});
            break :blk .{ .file = error_file.? };
        } else .inherit;

    var child = try std.process.spawn(io, .{
        .argv = argv,
        .stdin = stdin,
        .stdout = stdout,
        .stderr = stderr,
    });

    // Em segundo plano, não aguarda o processo.
    if (parsed.background) {
        return;
    }

    // Em primeiro plano, aguarda a conclusão.
    _ = try child.wait(io);
}


