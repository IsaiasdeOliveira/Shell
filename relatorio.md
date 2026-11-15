## Cenário 4 — Redirecionamento de saída

**Comando executado:**
```sh
/bin/echo ola > saida.txt
```

**Resultado observado:** o arquivo `saida.txt` foi criado no diretório de trabalho e contém o texto `ola`.

**Evidências do rastreamento (`04-redirecionamento.trace`):**

- Linha 76, PID 2665: `openat` abre ou cria o arquivo para escrita.
- Linha 86, PID 2665: `fork` cria o processo filho.
- Linha 97, PID 2666: `dup2(3, 1)` redireciona a saída padrão para o arquivo.
- Linha 100, PID 2666: `execve` executa `/bin/echo`.
- Linha 124, PID 2666: `write(1, "ola\n", 4)` grava o conteúdo no arquivo.

**Análise:** o shell abre o arquivo e cria um processo filho. No filho, o descritor de arquivo é duplicado para o descritor 1, correspondente à saída padrão. Em seguida, o programa `/bin/echo` é executado e escreve seu conteúdo no arquivo redirecionado.

## Cenário 5 — Linha vazia

**Entrada executada:** pressionar Enter sem digitar nenhum comando.

**Resultado observado:** o shell recebe a quebra de linha, ignora a entrada vazia e apresenta novamente o prompt.

**Evidências do rastreamento (`05-linha-vazia.trace`):**

- Linha 49, PID 2682: `read(0, "\n", 1) = 1`, indicando o recebimento da quebra de linha.
- Linhas 52 a 54, PID 2682: chamadas `write` responsáveis por apresentar novamente o prompt.

**Análise:** o shell reconhece a entrada vazia e retorna ao ciclo de leitura, sem executar um programa externo. Posteriormente, o comando `exit` é recebido para encerrar o shell.

## Cenário 6 — EOF (Ctrl+D)

**Entrada executada:** pressionar Ctrl+D com o prompt vazio.

**Resultado observado:** o shell identifica o fim da entrada e encerra normalmente.

**Evidências do rastreamento (`06-eof.trace`):**

- Linha 49, PID 2674: `read(0, "", 1) = 0`, indicando o retorno de EOF.
- Linha 50, PID 2674: `write(1, "\nEncerrando zigsh.\n", 19) = 19`, exibindo a mensagem de encerramento.
- Linha 60, PID 2674: `exit_group(0)`, encerrando o processo com código de sucesso.
- Linha 61: confirmação do encerramento com status 0.

**Análise:** quando a chamada `read` retorna zero, o shell identifica que não há mais dados disponíveis na entrada padrão. O programa então executa sua rotina de encerramento.
