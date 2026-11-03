
const std = @import("std");
const parser = @import("parser");

// Funções POSIX disponíveis no Linux.
extern "c" fn pipe(fds: *[2]c_int) c_int;
extern "c" fn waitpid(pid: c_int, status: *c_int, options: c_int) c_int;

const File = std.Io.File;

const MAX_COMMANDS = 16;
const WNOHANG: c_int = 1;

pub const ExecuteError = error{
    EmptyCommand,
    TooManyCommands,
    PipeCreationFailed,
};

fn fileFromFd(fd: c_int) File {
    return .{
        .handle = fd,
        .flags = .{ .nonblocking = false },
    };
}

/// Recolhe processos em segundo plano que já terminaram.
/// Específico para sistemas POSIX/Linux.
pub fn reapBackground() void {
    var status: c_int = 0;

    while (waitpid(-1, &status, WNOHANG) > 0) {}
}

fn closeFile(file: ?File, io: std.Io) void {
    if (file) |f| {
        f.close(io);
    }
}

/// Executa um comando ou uma sequência de comandos conectados por pipes.
pub fn executeExternal(
    io: std.Io,
    parsed: *const parser.ParsedLine,
) !void {
    reapBackground();

    if (parsed.command_count == 0) {
        return error.EmptyCommand;
    }

    if (parsed.command_count > MAX_COMMANDS) {
        return error.TooManyCommands;
    }

    var children: [MAX_COMMANDS]std.process.Child = undefined;

    var previous_read: ?File = null;

    for (parsed.commands[0..parsed.command_count], 0..) |command, index| {
        if (command.arg_count == 0) {
            closeFile(previous_read, io);
            return error.EmptyCommand;
        }

        var next_read: ?File = null;
        var next_write: ?File = null;

        // Cria um pipe para conectar ao próximo comando.
        if (index + 1 < parsed.command_count) {
            var fds: [2]c_int = undefined;

            if (pipe(&fds) != 0) {
                closeFile(previous_read, io);
                return error.PipeCreationFailed;
            }

            next_read = fileFromFd(fds[0]);
            next_write = fileFromFd(fds[1]);
        }

        var input_file: ?File = null;
        var output_file: ?File = null;
        var error_file: ?File = null;

        // Abre os arquivos de redirecionamento.
        if (command.input_file) |path| {
            input_file = try std.Io.Dir.cwd().openFile(io, path, .{});
        }

        if (command.output_file) |path| {
            output_file = try std.Io.Dir.cwd().createFile(io, path, .{});
        }

        if (command.error_file) |path| {
            error_file = try std.Io.Dir.cwd().createFile(io, path, .{});
        }

        // Redirecionamento explícito tem prioridade sobre o pipe.
        const stdin: std.process.SpawnOptions.StdIo =
            if (input_file) |file|
                .{ .file = file }
            else if (previous_read) |file|
                .{ .file = file }
            else
                .inherit;

        const stdout: std.process.SpawnOptions.StdIo =
            if (output_file) |file|
                .{ .file = file }
            else if (next_write) |file|
                .{ .file = file }
            else
                .inherit;

        const stderr: std.process.SpawnOptions.StdIo =
            if (error_file) |file|
                .{ .file = file }
            else
                .inherit;

        // Inicia o processo.
const child = std.process.spawn(io, .{
    .argv = command.args[0..command.arg_count],
    .stdin = stdin,
    .stdout = stdout,
    .stderr = stderr,
}) catch |err| {
    closeFile(input_file, io);
    closeFile(output_file, io);
    closeFile(error_file, io);
    closeFile(previous_read, io);
    closeFile(next_read, io);
    closeFile(next_write, io);
    return err;
};

children[index] = child;

        // O processo pai não precisa manter esses descritores abertos.
        closeFile(input_file, io);
        closeFile(output_file, io);
        closeFile(error_file, io);
        closeFile(previous_read, io);
        closeFile(next_write, io);

        // O lado de leitura será usado pelo próximo processo.
        previous_read = next_read;
    }

    // Todos os processos já foram iniciados.
    // Não aguarda processos em segundo plano.
    if (parsed.background) {
        reapBackground();
        return;
    }

    // Aguarda todos os processos do pipeline.
    for (children[0..parsed.command_count]) |*child| {
        _ = try child.wait(io);
    }

    reapBackground();
}

