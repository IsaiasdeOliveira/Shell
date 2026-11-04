const std = @import("std");

extern "c" fn read(
    fd: c_int,
    buf: [*]u8,
    count: usize,
) isize;

extern "c" fn write(
    fd: c_int,
    buf: [*]const u8,
    count: usize,
) isize;

extern "c" fn getcwd(
    buf: [*]u8,
    size: usize,
) ?[*:0]u8;

fn imprimir(texto: []const u8) void {
    _ = write(1, texto.ptr, texto.len);
}

extern "c" fn chdir(path: [*:0]const u8) c_int;

fn executarBuiltin(comando: []const u8) !bool {
    const texto = std.mem.trim(u8, comando, " \t\r");

    var partes = std.mem.tokenizeAny(u8, texto, " \t");
    const nome = partes.next() orelse return true;

    if (std.mem.eql(u8, nome, "pwd")) {
        var diretorio: [4096]u8 = undefined;

        const caminho = getcwd(&diretorio, diretorio.len);

        if (caminho) |p| {
            imprimir(std.mem.span(p));
            imprimir("\n");
        } else {
            imprimir("Erro ao obter diretorio.\n");
        }

        return true;
    }

    if (std.mem.eql(u8, nome, "cd")) {
        const destino = partes.next() orelse {
            imprimir("Uso: cd <diretorio>\n");
            return true;
        };

        var buffer: [4096]u8 = undefined;

        if (destino.len >= buffer.len) {
            imprimir("Caminho muito longo.\n");
            return true;
        }

        @memcpy(buffer[0..destino.len], destino);
        buffer[destino.len] = 0;

        if (chdir(@ptrCast(&buffer)) != 0) {
            imprimir("Erro: diretorio nao encontrado.\n");
        }

        return true;
    }

    if (std.mem.eql(u8, nome, "help")) {
        imprimir("\nComandos internos do zigsh:\n" ++
            "  cd <dir>  - Altera o diretorio\n" ++
            "  pwd       - Mostra o diretorio atual\n" ++
            "  help      - Exibe esta ajuda\n" ++
            "  exit [n]  - Encerra o shell\n\n");

        return true;
    }

    if (std.mem.eql(u8, nome, "exit")) {
        const codigo_texto = partes.next() orelse "0";

        const codigo = std.fmt.parseInt(
            u8,
            codigo_texto,
            10,
        ) catch {
            imprimir("Codigo de saida invalido.\n");
            return true;
        };

        imprimir("Encerrando zigsh.\n");
        std.process.exit(codigo);
    }

    return false;
}

fn executarExterno(
    io: std.Io,
    allocator: std.mem.Allocator,
    comando: []const u8,
) !void {
    // Lista dos argumentos do comando.
    var argumentos: std.ArrayList([]const u8) = .empty;
    defer argumentos.deinit(allocator);

    // Separa o comando usando espacos como delimitadores.
    var partes = std.mem.tokenizeAny(u8, comando, " \t\r");

    while (partes.next()) |parte| {
        try argumentos.append(allocator, parte);
    }

    // Nao executa comandos vazios.
    if (argumentos.items.len == 0) {
        return;
    }

    // Cria o processo filho.
    var filho = try std.process.spawn(io, .{
        .argv = argumentos.items,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });

    // Aguarda o termino do processo filho.
    _ = try filho.wait(io);
}

pub fn main(init: std.process.Init) !void {
    var diretorio: [4096]u8 = undefined;
    var entrada: [1024]u8 = undefined;

    imprimir("Bem-vindo ao zigsh!\n");

    while (true) {
        const cwd = getcwd(&diretorio, diretorio.len);

        imprimir("zigsh [");

        if (cwd) |caminho| {
            imprimir(std.mem.span(caminho));
        } else {
            imprimir("?");
        }

        imprimir("]>");

        var tamanho: usize = 0;

        while (tamanho < entrada.len) {
            var caractere: [1]u8 = undefined;
            const n = read(0, &caractere, 1);

            if (n == 0) {
                imprimir("\nEncerrando zigsh.\n");
                return;
            }
            if (n < 0) {
                imprimir("\nErro de leitura.\n");
                return;
            }

            if (caractere[0] == '\n') break;

            entrada[tamanho] = caractere[0];
            tamanho += 1;
        }

        const comando = entrada[0..tamanho];

        // Verifica se o comando e interno.
        const reconhecido = try executarBuiltin(comando);

        // Se nao for interno, executa processo externo.
        if (!reconhecido) {
            executarExterno(
                init.io,
                init.gpa,
                comando,
            ) catch |err| {
                std.debug.print(
                    "zigsh: erro ao executar comando: {s}\n",
                    .{@errorName(err)},
                );
            };
        }
    } // Fecha o while principal
} // Fecha a funcao main
