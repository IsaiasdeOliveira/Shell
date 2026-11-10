
const std = @import("std");

const MAX_TOKENS = 256;
const MAX_COMMANDS = 16;
const MAX_ARGS = 32;

pub const ParseError = error{
    UnclosedQuote,
    TooManyTokens,
    TooManyCommands,
    TooManyArguments,
    MissingCommand,
    MissingRedirectionTarget,
    DuplicateRedirection,
    BackgroundNotLast,
    EmptyPipeline,
};

pub const Command = struct {
    // args[0] contém o nome do comando.
    args: [MAX_ARGS][]const u8 = undefined,
    arg_count: usize = 0,

    input_file: ?[]const u8 = null,
    output_file: ?[]const u8 = null,
    error_file: ?[]const u8 = null,
};

pub const ParsedLine = struct {
    commands: [MAX_COMMANDS]Command = undefined,
    command_count: usize = 0,
    background: bool = false,
};

const TokenKind = enum {
    word,
    input,
    output,
    error_output,
    pipe,
    background,
};

const Token = struct {
    kind: TokenKind,
    text: []const u8 = "",
};

const TokenList = struct {
    items: [MAX_TOKENS]Token = undefined,
    len: usize = 0,

    fn add(self: *TokenList, token: Token) ParseError!void {
        if (self.len >= MAX_TOKENS) {
            return error.TooManyTokens;
        }

        self.items[self.len] = token;
        self.len += 1;
    }
};

fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}


fn tokenize(line: []const u8) ParseError!TokenList {
    var tokens = TokenList{};
    var i: usize = 0;

    while (i < line.len) {
        if (isWhitespace(line[i])) {
            i += 1;
            continue;
        }

        if (i + 1 < line.len and
            line[i] == '2' and line[i + 1] == '>')
        {
            try tokens.add(.{ .kind = .error_output });
            i += 2;
            continue;
        }

        const kind: ?TokenKind = switch (line[i]) {
            '>' => .output,
            '<' => .input,
            '|' => .pipe,
            '&' => .background,
            else => null,
        };

        if (kind) |operator| {
            try tokens.add(.{ .kind = operator });
            i += 1;
            continue;
        }

        // Argumento inteiramente entre aspas.
        if (line[i] == '"' or line[i] == '\'') {
            const quote = line[i];
            i += 1;
            const start = i;

            while (i < line.len and line[i] != quote) {
                i += 1;
            }

            if (i == line.len) {
                return error.UnclosedQuote;
            }

            try tokens.add(.{
                .kind = .word,
                .text = line[start..i],
            });

            i += 1;
            continue;
        }

        // Argumento sem aspas.
        const start = i;

        while (i < line.len and
            !isWhitespace(line[i]) and
            line[i] != '>' and
            line[i] != '<' and
            line[i] != '|' and
            line[i] != '&' and
            line[i] != '"' and
            line[i] != '\'')
        {
            if (line[i] == '2' and
                i + 1 < line.len and
                line[i + 1] == '>')
            {
                break;
            }

            i += 1;
        }

        try tokens.add(.{
            .kind = .word,
            .text = line[start..i],
        });
    }

    return tokens;
}


pub fn parse(line: []const u8) ParseError!ParsedLine {
    const tokens = try tokenize(line);

    var result = ParsedLine{};

    if (tokens.len == 0) {
        return result;
    }

    result.command_count = 1;
    result.commands[0] = .{};

    var current = &result.commands[0];
    var i: usize = 0;

    while (i < tokens.len) {
        const token = tokens.items[i];

        switch (token.kind) {
            .word => {
                if (current.arg_count >= MAX_ARGS) {
                    return error.TooManyArguments;
                }

                current.args[current.arg_count] = token.text;
                current.arg_count += 1;
            },

            .input, .output, .error_output => {
                i += 1;

                if (i >= tokens.len or tokens.items[i].kind != .word) {
                    return error.MissingRedirectionTarget;
                }

                const filename = tokens.items[i].text;

                switch (token.kind) {
                    .input => {
                        if (current.input_file != null) {
                            return error.DuplicateRedirection;
                        }
                        current.input_file = filename;
                    },
                    .output => {
                        if (current.output_file != null) {
                            return error.DuplicateRedirection;
                        }
                        current.output_file = filename;
                    },
                    .error_output => {
                        if (current.error_file != null) {
                            return error.DuplicateRedirection;
                        }
                        current.error_file = filename;
                    },
                    else => unreachable,
                }
            },

            .pipe => {
                if (current.arg_count == 0) {
                    return error.EmptyPipeline;
                }

                if (result.command_count >= MAX_COMMANDS) {
                    return error.TooManyCommands;
                }

                current = &result.commands[result.command_count];
                result.commands[result.command_count] = .{};
                result.command_count += 1;
            },

            .background => {
                if (i != tokens.len - 1) {
                    return error.BackgroundNotLast;
                }

                result.background = true;
            },
        }

        i += 1;
    }

    if (current.arg_count == 0) {
        if (result.command_count > 1) {
            return error.EmptyPipeline;
        }
        return error.MissingCommand;
    }

    return result;
}

// Testes básicos do parser.
test "interpreta comando e argumentos" {
    const parsed = try parse("echo Ola mundo");

    try std.testing.expectEqual(@as(usize, 1), parsed.command_count);
    try std.testing.expectEqualStrings("echo", parsed.commands[0].args[0]);
    try std.testing.expectEqualStrings("Ola", parsed.commands[0].args[1]);
    try std.testing.expectEqualStrings("mundo", parsed.commands[0].args[2]);
}

test "interpreta redirecionamento de saida" {
    const parsed = try parse("echo Ola > saida.txt");

    try std.testing.expectEqualStrings(
        "saida.txt",
        parsed.commands[0].output_file.?,
    );
}

test "interpreta redirecionamento de entrada" {
    const parsed = try parse("cat < entrada.txt");

    try std.testing.expectEqualStrings(
        "entrada.txt",
        parsed.commands[0].input_file.?,
    );
}

test "interpreta redirecionamento de erro" {
    const parsed = try parse("ls 2> erros.txt");

    try std.testing.expectEqualStrings(
        "erros.txt",
        parsed.commands[0].error_file.?,
    );
}

test "interpreta segundo plano" {
    const parsed = try parse("sleep 5 &");

    try std.testing.expect(parsed.background);
}

test "interpreta pipeline" {
    const parsed = try parse("ls | grep txt");

    try std.testing.expectEqual(@as(usize, 2), parsed.command_count);
    try std.testing.expectEqualStrings("ls", parsed.commands[0].args[0]);
    try std.testing.expectEqualStrings("grep", parsed.commands[1].args[0]);
}

test "rejeita destino de redirecionamento ausente" {
    try std.testing.expectError(
        error.MissingRedirectionTarget,
        parse("echo Ola >"),
    );
}

test "rejeita pipeline vazio" {
    try std.testing.expectError(
        error.EmptyPipeline,
        parse("ls |"),
    );
}
test "interpreta comando sem espacos nos operadores" {
    const parsed = try parse("echo Ola>saida.txt");

    try std.testing.expectEqualStrings(
        "echo",
        parsed.commands[0].args[0],
    );

    try std.testing.expectEqualStrings(
        "saida.txt",
        parsed.commands[0].output_file.?,
    );
}

test "interpreta multiplos redirecionamentos" {
    const parsed = try parse("cat < entrada.txt > saida.txt 2> erros.txt");

    try std.testing.expectEqualStrings(
        "entrada.txt",
        parsed.commands[0].input_file.?,
    );

    try std.testing.expectEqualStrings(
        "saida.txt",
        parsed.commands[0].output_file.?,
    );

    try std.testing.expectEqualStrings(
        "erros.txt",
        parsed.commands[0].error_file.?,
    );
}

test "rejeita segundo plano fora do final" {
    try std.testing.expectError(
        error.BackgroundNotLast,
        parse("sleep 5 & ls"),
    );
}

test "rejeita comando vazio antes do pipeline" {
    try std.testing.expectError(
        error.EmptyPipeline,
        parse("| grep txt"),
    );
}


test "interpreta argumento com aspas duplas" {
    const parsed = try parse(
        "/bin/echo \"Teste de criacao de arquivo\" > saida.txt",
    );

    try std.testing.expectEqual(
        @as(usize, 2),
        parsed.commands[0].arg_count,
    );

    try std.testing.expectEqualStrings(
        "Teste de criacao de arquivo",
        parsed.commands[0].args[1],
    );
}

test "interpreta argumento com aspas simples" {
    const parsed = try parse(
        "/bin/printf 'Linha 1\\nLinha 2\\nAlvo 123\\n' | /bin/grep Alvo",
    );

    try std.testing.expectEqual(
        @as(usize, 2),
        parsed.command_count,
    );

    try std.testing.expectEqualStrings(
        "Linha 1\\nLinha 2\\nAlvo 123\\n",
        parsed.commands[0].args[1],
    );
}
