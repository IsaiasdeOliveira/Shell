# Avaliação prática — Chamadas de sistema de um shell

**Disciplina:** Sistemas Operacionais
**Projeto:** `zigsh`, shell desenvolvido em Zig
**Integrantes:** Daniel Santos Baptista; Isaias Maia de Oliveira
**Objeto da análise:** seis cenários de uso do `zigsh`, rastreados com `strace -f` em Linux.

> **Escopo documental.** Este relatório utiliza a **recoleta efetuada em Alpine Linux 3.24.2**, no ambiente de Daniel, e a revisão Git indicada abaixo. Os seis traces íntegros chegaram no arquivo `recoleta-strace-daniel.tar.gz`, com o registro do ambiente e `saida.txt`. Os números de linha e PIDs aqui citados são os **da recoleta**, não dos traces antigos já publicados no repositório. Para a entrega final, os seis arquivos de `traces-novos/` devem ser copiados **sem alterações** para `entrega/traces/` e, na integração Git, substituir os arquivos correspondentes em `traces/`. As referências de evidência neste relatório usam os caminhos finais `traces/NN-*.trace`; os originais enviados para auditoria estavam em `traces-novos/` e possuem o mesmo conteúdo, conferível pelos hashes da seção 5. A coleta limpa do cenário 1 substitui a primeira tentativa, que continha entradas adicionais acidentais.

## 1. Preparação, identificação e método de coleta

### 1.1 Ambiente verificado

Saída preservada originalmente em `traces-novos/ambiente-coleta.txt` (a copiar para `evidencias/ambiente-coleta.txt` na branch final), obtida com `cat /etc/alpine-release`, `uname -srm`, `zig version` e `strace -V`:

```text
=== Alpine Linux ===
3.24.2
=== Kernel ===
Linux 6.18.56-0-virt x86_64
=== Zig ===
0.16.0
=== strace ===
strace -- version 6.19
Optional features enabled: stack-trace=libdw stack-demangle no-m32-mpers no-mx32-mpers
=== Revisao Git ===
b5811dba90916bd02f76f7826a9de72a67220b3a
=== Compilacao ===
zig build-exe -lc --dep parser --dep executor -Mroot=src/main.zig -Mparser=src/parser.zig --dep parser -Mexecutor=src/executor.zig -femit-bin=zigsh
Modo: Debug (sem -O)
```

Os comandos foram executados no diretório `~/Shell-strace` (`/home/dBaptista/Shell-strace`), exceto o cenário 4, feito no diretório de testes `/home/dBaptista/Shell-strace/testes-recoleta`. A opção `-f` faz o `strace` acompanhar o processo filho; `-o` preserva as chamadas em arquivo separado da interação no terminal. Foi iniciada uma nova sessão do shell para cada cenário. O shell compilado tem saída `./zigsh`, conforme o comando do projeto; o caminho genérico `zig-out/bin/meu-shell` do enunciado foi ajustado a esse executável.

**Comando de compilação executado:**

```bash
zig build-exe -lc \
  --dep parser --dep executor \
  -Mroot=src/main.zig \
  -Mparser=src/parser.zig \
  --dep parser \
  -Mexecutor=src/executor.zig \
  -femit-bin=zigsh
```

**Modo:** `Debug`, pois não foi especificado `-O`; a compilação terminou sem mensagem de erro e o binário `zigsh` foi executado. A revisão Git registrada no momento da coleta é `b5811dba90916bd02f76f7826a9de72a67220b3a`. O relatório utiliza esse estado do código para relacionar funções Zig às syscalls; nomes de syscalls não significam necessariamente chamadas diretas por uma função do usuário.

**Organização:** os arquivos de recoleta entregues contêm 125, 140, 136, 138, 63 e 64 linhas, respectivamente, nos cenários 1 a 6. O arquivo `testes-recoleta/saida.txt` tem 4 bytes (`ola\n`). Os traces antigos foram preservados separadamente durante a recoleta.

### 1.2 Relação com o código Zig

- `src/main.zig`: `main` exibe o prompt, lê a entrada com a função C `read`, trata linha vazia e EOF; `imprimir` usa a função C `write`; `executarBuiltin` implementa `cd`, `pwd`, `help` e `exit`; `executarExterno` chama o parser e o executor.
- `src/parser.zig`: `tokenize` e `parse` interpretam os argumentos, operadores e redirecionamentos em espaço de usuário. Essas funções, isoladamente, não são syscalls.
- `src/executor.zig`: `executeExternal` realiza o redirecionamento por `std.Io.Dir.cwd().createFile`, inicia comandos com `std.process.spawn`, fecha os arquivos no pai e espera os filhos por `child.wait`; `reapBackground` invoca a função C `waitpid(-1, ..., WNOHANG)`. No Linux, o rastreamento expõe as syscalls subjacentes, como `openat`, `pipe2`, `fork`, `dup2`, `execve`, `close` e `wait4`, sem que o código Zig chame todas elas pelo mesmo nome.

O `strace` registra operações no kernel. `execve` bem-sucedido substitui o programa executado **sem mudar o PID**. A partir desse êxito, as chamadas subsequentes do mesmo PID pertencem ao programa carregado. As chamadas de inicialização, biblioteca C, runtime Zig e utilitários externos estão incluídas no inventário, mesmo quando sua origem exata em código de biblioteca não é determinada pelo trace.

## 2. Cenários avaliados

| Número | Ação principal | Evidência de resultado |
|---|---|---|
| 1 | `/bin/echo ola` | Processo filho escreve `ola` e pai aguarda |
| 2 | Executável absoluto inexistente | `execve = -1 ENOENT`, mensagem `FileNotFound` |
| 3 | `cd /tmp` e `/bin/pwd` | `chdir` no PID do shell e saída `/tmp` do filho |
| 4 | `/bin/echo ola > saida.txt` | `openat`, `dup2`, escrita no arquivo |
| 5 | Enter em prompt vazio | `read(0, "\n", 1) = 1`, novo prompt |
| 6 | Ctrl+D em prompt vazio | `read(0, "", 1) = 0`, encerramento |

## 3. Análise por cenário

### 3.1 Cenário 1 — Comando externo `/bin/echo ola`

**1. Previsão.** A leitura do `main` deve entregar `/bin/echo ola` a `parser.parse` e a `executor.executeExternal`. Espera-se a criação de filho, `execve` de `/bin/echo`, escrita de `ola\n` na saída padrão pelo filho e espera do shell pelo término, antes de exibir novo prompt.

**2. Execução.** Coleta na raiz do projeto:

```bash
strace -f -o traces-novos/01-comando-externo.trace ./zigsh
```

Entradas digitadas e saída observada no terminal da recoleta limpa:

```text
Bem-vindo ao zigsh!
zigsh [/home/dBaptista/Shell-strace]>/bin/echo ola
ola
zigsh [/home/dBaptista/Shell-strace]>exit
Encerrando zigsh.
```

**3. Evidência.** Arquivo `traces/01-comando-externo.trace` (cópia da recoleta `traces-novos/01-comando-externo.trace`) (PIDs 2600 = `zigsh`, 2601 = filho, depois `/bin/echo`). Linhas transcritas com numeração original:

```text
1:2600  execve("./zigsh", ["./zigsh"], 0x7ffcb6b25c28 /* 19 vars */) = 0
68:2600  pipe2([3, 4], O_CLOEXEC)          = 0
71:2600  fork()                            = 2601
84:2601  execve("/bin/echo", ["/bin/echo", "ola"], 0x7f2147680018 /* 19 vars */ <unfinished ...>
88:2600  wait4(2601 <unfinished ...>
89:2601  <... execve resumed>)             = 0
107:2601  write(1, "ola\n", 4)              = 4
108:2601  exit_group(0)                     = ?
110:2600  <... wait4 resumed>, [{WIFEXITED(s) && WEXITSTATUS(s) == 0}], 0, NULL) = 2601
111:2600  --- SIGCHLD {si_signo=SIGCHLD, si_code=CLD_EXITED, si_pid=2601, si_uid=1000, si_status=0, si_utime=0, si_stime=0} ---
123:2600  write(1, "Encerrando zigsh.\n", 18) = 18
124:2600  exit_group(0)                     = ?
```

**4. Interpretação.** `pipe2([3,4], O_CLOEXEC) = 0` cria descritores para comunicação de lançamento/erro da biblioteca; não corresponde a um pipeline digitado pelo usuário. `fork() = 2601` (PID 2600) gera o filho. `execve` é iniciado na linha 84 e conclui com sucesso na linha 89. A partir desse ponto, o PID **2601 passa a executar `/bin/echo`**. A syscall `write(1, "ola\n", 4) = 4` (linha 107), já no utilitário, imprime quatro bytes em `stdout` (fd 1). No pai, `wait4(2601, ...)` é iniciado na linha 88 e termina na linha 110 com status 0; o shell aguarda antes de emitir o próximo prompt. `exit` é tratado por `executarBuiltin`/`std.process.exit` no processo 2600 (linhas 123–124). Confirmou-se a previsão. Código relacionado: `src/main.zig` (`main`, `executarExterno`, `executarBuiltin`) e `src/executor.zig` (`executeExternal`, `child.wait`).

### 3.2 Cenário 2 — Executável inexistente

**1. Previsão.** Após confirmar a inexistência do caminho absoluto, a interpretação da linha deve tentar iniciar um programa externo. Espera-se falha de `execve` com `ENOENT` (se a execução chegar a essa syscall), reporte de erro no terminal e retorno do shell ao prompt, sem derrubar o processo principal.

**2. Execução.** Primeiro foi verificado, fora do `zigsh`:

```bash
test ! -e /tmp/so-avaliacao-executavel-inexistente && echo "Executavel ausente"
# Saída: Executavel ausente
```

Comando de coleta:

```bash
strace -f -o traces-novos/02-inexistente.trace ./zigsh
```

```text
Bem-vindo ao zigsh!
zigsh [/home/dBaptista/Shell-strace]>/tmp/so-avaliacao-executavel-inexistente
zigsh: erro ao executar comando: FileNotFound
zigsh [/home/dBaptista/Shell-strace]>exit
Encerrando zigsh.
```

**3. Evidência.** Arquivo `traces/02-inexistente.trace` (cópia da recoleta `traces-novos/02-inexistente.trace`): PID 2549 = `zigsh`; PID 2550 = filho cuja imagem **não é substituída** porque `execve` falhou.

```text
95:2549  pipe2([3, 4], O_CLOEXEC)          = 0
98:2549  fork()                            = 2550
111:2550  execve("/tmp/so-avaliacao-executavel-inexistente", ["/tmp/so-avaliacao-executavel-ine"...], 0x7f6406fa0018 /* 19 vars */) = -1 ENOENT (No such file or directory)
112:2550  write(4, "!\0\0\0\0\0\0\0", 8 <unfinished ...>
114:2550  <... write resumed>)              = 8
115:2549  read(3 <unfinished ...>
117:2549  <... read resumed>, "!\0\0\0\0\0\0\0", 8) = 8
118:2550  <... exit_group resumed>)         = ?
122:2549  --- SIGCHLD {si_signo=SIGCHLD, si_code=CLD_EXITED, si_pid=2550, si_uid=1000, si_status=1, si_utime=0, si_stime=0} ---
124:2549  gettid()                          = 2549
125:2549  ioctl(2, TIOCGWINSZ, {ws_row=30, ws_col=120, ws_xpixel=640, ws_ypixel=480}) = 0
126:2549  writev(2, [{iov_base="zigsh: erro ao executar comando:"..., iov_len=46}], 1) = 46
127:2549  wait4(-1, [{WIFEXITED(s) && WEXITSTATUS(s) == 1}], WNOHANG, NULL) = 2550
138:2549  write(1, "Encerrando zigsh.\n", 18) = 18
139:2549  exit_group(0)                     = ?
```

**4. Interpretação.** O pai 2549 cria um filho 2550 (`fork = 2550`). O filho **chega a executar a syscall `execve`** com o caminho absoluto, mas recebe `-1 ENOENT (No such file or directory)` (linha 111); não chega a executar o programa solicitado. Na falha, a rotina de lançamento comunica o erro pelo descritor 4 (`write` de oito bytes), lido pelo pai no descritor 3, e o filho termina com código 1. O shell registra o identificador de thread (`gettid`), consulta o terminal (`ioctl` fd 2) e imprime a mensagem com `writev(2, ..., 1) = 46`, isto é, em `stderr`. A camada Zig transforma o erro em `FileNotFound`, observado no terminal. `wait4` recolhe o filho com status 1, e o shell continua até `exit`. A previsão foi confirmada; não há `execve` bem-sucedido nesse filho. Código: `src/main.zig` (`main`, `executarExterno`, ramo `catch` com `std.debug.print`) e `src/executor.zig` (`executeExternal`, `std.process.spawn`); o protocolo do pipe é comportamento da implementação da biblioteca, não uma função do parser.

### 3.3 Cenário 3 — Comando interno `cd /tmp` e `/bin/pwd`

**1. Previsão.** `executarBuiltin` reconhece `cd` e usa a função C `chdir`, que altera o diretório do **próprio processo do shell**, sem filho. O prompt seguinte deve apresentar `/tmp`. Depois, a execução de `/bin/pwd` deve criar um filho que herda o diretório de trabalho e imprime `/tmp`.

**2. Execução.** O shell foi iniciado em `/home/dBaptista/Shell-strace`, diferente de `/tmp`:

```bash
strace -f -o traces-novos/03-cd.trace ./zigsh
```

```text
Bem-vindo ao zigsh!
zigsh [/home/dBaptista/Shell-strace]>cd /tmp
zigsh [/tmp]>/bin/pwd
/tmp
zigsh [/tmp]>exit
Encerrando zigsh.
```

**3. Evidência.** Arquivo `traces/03-cd.trace` (cópia da recoleta `traces-novos/03-cd.trace`): PID 2553 = `zigsh`; PID 2554 = filho, depois `/bin/pwd`.

```text
47:2553  getcwd("/home/dBaptista/Shell-strace", 4096) = 29
59:2553  chdir("/tmp")                     = 0
61:2553  getcwd("/tmp", 4096)              = 5
63:2553  write(1, "/tmp", 4)               = 4
77:2553  pipe2([3, 4], O_CLOEXEC)          = 0
80:2553  fork()                            = 2554
93:2554  execve("/bin/pwd", ["/bin/pwd"], 0x7f19380a0018 /* 19 vars */ <unfinished ...>
97:2553  wait4(2554 <unfinished ...>
98:2554  <... execve resumed>)             = 0
116:2554  getcwd("/tmp", 192)               = 5
117:2554  ioctl(1, TIOCGWINSZ, {ws_row=30, ws_col=120, ws_xpixel=640, ws_ypixel=480}) = 0
118:2554  writev(1, [{iov_base="/tmp", iov_len=4}, {iov_base="\n", iov_len=1}], 2) = 5
119:2554  exit_group(0)                     = ?
121:2553  <... wait4 resumed>, [{WIFEXITED(s) && WEXITSTATUS(s) == 0}], 0, NULL) = 2554
125:2553  getcwd("/tmp", 4096)              = 5
```

**4. Interpretação.** `chdir("/tmp") = 0` ocorre no PID **2553**, o próprio shell, provando que o `cd` é interno. `getcwd("/tmp", 4096) = 5` e `write(1, "/tmp", 4) = 4` comprovam a alteração do prompt. Somente ao executar `/bin/pwd` há `fork() = 2554`. Seu `execve` conclui na linha 98, após o qual PID 2554 pertence ao programa `/bin/pwd`. Ele consulta `getcwd("/tmp", 192) = 5` e grava cinco bytes (`/tmp\n`) em `stdout` via **`writev`**, não `write`. O shell aguarda seu fim por `wait4` (linhas 97 e 121). Confirma a previsão e a herança do diretório do pai. Código: `src/main.zig` (`executarBuiltin` e `main`) e `src/executor.zig` (`executeExternal`).

### 3.4 Cenário 4 — Redirecionamento de saída padrão

**1. Previsão.** `parser.parse` identifica `>` e associa `saida.txt` à saída do comando. Em `executeExternal`, `std.Io.Dir.cwd().createFile` deve abrir/criar o arquivo em processo pai; o lançamento de um filho deve redirecionar o fd 1 para esse arquivo, executar `/bin/echo` e escrever `ola\n` nele. O shell continua após esperar o filho.

**2. Execução.** A coleta ocorreu dentro do diretório de testes com permissão de escrita:

```bash
cd ~/Shell-strace/testes-recoleta
strace -f -o ../traces-novos/04-redirecionamento.trace ../zigsh
```

```text
Bem-vindo ao zigsh!
zigsh [/home/dBaptista/Shell-strace/testes-recoleta]>/bin/echo ola > saida.txt
zigsh [/home/dBaptista/Shell-strace/testes-recoleta]>exit
Encerrando zigsh.
```

Após encerrar a sessão, o comando `cat saida.txt` exibiu `ola`. O arquivo coletado em `testes-recoleta/saida.txt` contém literalmente `ola\n` (quatro bytes).

**3. Evidência.** Arquivo `traces/04-redirecionamento.trace` (cópia da recoleta `traces-novos/04-redirecionamento.trace`): PID 2557 = `zigsh` pai; PID 2558 = filho e, após `execve`, `/bin/echo`.

```text
78:2557  openat(AT_FDCWD, "saida.txt", O_WRONLY|O_CREAT|O_TRUNC|O_LARGEFILE|O_CLOEXEC, 0666) = 3
81:2557  pipe2([4, 5], O_CLOEXEC)          = 0
84:2557  fork()                            = 2558
91:2557  close(5)                          = 0
95:2558  dup2(3, 1)                        = 1
96:2558  execve("/bin/echo", ["/bin/echo", "ola"], 0x7fc289560018 /* 19 vars */ <unfinished ...>
99:2557  close(4)                          = 0
100:2557  close(3)                          = 0
101:2557  wait4(2558 <unfinished ...>
102:2558  <... execve resumed>)             = 0
120:2558  write(1, "ola\n", 4)              = 4
121:2558  exit_group(0)                     = ?
123:2557  <... wait4 resumed>, [{WIFEXITED(s) && WEXITSTATUS(s) == 0}], 0, NULL) = 2558
136:2557  write(1, "Encerrando zigsh.\n", 18) = 18
137:2557  exit_group(0)                     = ?
```

**4. Interpretação.** `openat(AT_FDCWD, "saida.txt", O_WRONLY|O_CREAT|O_TRUNC|O_LARGEFILE|O_CLOEXEC, 0666) = 3` é executado **pelo shell 2557**. `AT_FDCWD` usa o diretório de trabalho do processo; `O_CREAT|O_TRUNC` permite criar/truncar o arquivo, o modo solicitado é `0666`, e o retorno 3 é o fd aberto. O spawn cria `pipe2([4,5], O_CLOEXEC)` para comunicação auxiliar e `fork() = 2558`. O filho ainda executa a lógica pré-`execve` quando faz `dup2(3,1) = 1`, associando `stdout` ao arquivo. Seu `execve("/bin/echo", ...)` começa na linha 96 e é concluído com sucesso na 102; **a partir daí o PID 2558 executa `/bin/echo`**. `write(1, "ola\n", 4) = 4` usa o fd 1 já redirecionado. O pai fecha seus descritores não necessários e o `wait4` termina com status zero (linhas 101–123). A ausência de `ola` no terminal e a presença em `saida.txt` confirmam a previsão. Código: `src/parser.zig` (`parse`); `src/executor.zig` (`executeExternal`, `createFile`, configuração de `stdout`, `std.process.spawn`, `child.wait`).

### 3.5 Cenário 5 — Linha vazia

**1. Previsão.** Ao pressionar Enter sem texto, `main` deve ler uma quebra de linha e encerrar o laço de caracteres. `executarBuiltin` usa `tokenizeAny` e, sem token, retorna `true`; não se espera spawn, `fork` ou `execve` externo. Deve aparecer um novo prompt.

**2. Execução.** Comando de coleta:

```bash
strace -f -o traces-novos/05-linha-vazia.trace ./zigsh
```

```text
Bem-vindo ao zigsh!
zigsh [/home/dBaptista/Shell-strace]>
zigsh [/home/dBaptista/Shell-strace]>exit
Encerrando zigsh.
```

A linha entre os prompts corresponde ao Enter sem texto; `exit` foi digitado apenas para finalizar a sessão.

**3. Evidência.** Arquivo `traces/05-linha-vazia.trace` (cópia da recoleta `traces-novos/05-linha-vazia.trace`): PID 2564 = shell. Linhas do prompt antes e depois da leitura:

```text
45:2564  wait4(-1, 0x7ffef369b418, WNOHANG, NULL) = -1 ECHILD (No child process)
46:2564  getcwd("/home/dBaptista/Shell-strace", 4096) = 29
47:2564  write(1, "zigsh [", 7)            = 7
48:2564  write(1, "/home/dBaptista/Shell-strace", 28) = 28
49:2564  write(1, "]>", 2)                 = 2
50:2564  read(0, "\n", 1)                  = 1
51:2564  wait4(-1, 0x7ffef369b418, WNOHANG, NULL) = -1 ECHILD (No child process)
52:2564  getcwd("/home/dBaptista/Shell-strace", 4096) = 29
53:2564  write(1, "zigsh [", 7)            = 7
54:2564  write(1, "/home/dBaptista/Shell-strace", 28) = 28
55:2564  write(1, "]>", 2)                 = 2
60:2564  read(0, "\n", 1)                  = 1
61:2564  write(1, "Encerrando zigsh.\n", 18) = 18
62:2564  exit_group(0)                     = ?
```

**4. Interpretação.** `read(0, "\n", 1) = 1` indica que a entrada padrão (fd 0) entregou **um byte**, a quebra de linha. Sem comando reconhecível, a função `executarBuiltin` devolve `true` e `executarExterno` não é chamada. O ciclo do `main` consulta o diretório e mostra o prompt outra vez (`write` nas linhas 53–55). Não há criação de filho para a linha vazia; `wait4(..., WNOHANG) = -1 ECHILD` verifica ausência de filhos e não é evidência de execução de comando externo. A previsão foi confirmada. Código relacionado: `src/main.zig` (`main`, `executarBuiltin`, `imprimir`).

### 3.6 Cenário 6 — EOF (Ctrl+D)

**1. Previsão.** Ao receber EOF em um prompt vazio no modo canônico do terminal, a chamada de leitura do `main` deve retornar 0. O código imprime a mensagem de encerramento e sai do laço/retorna da função; não se espera executar um comando externo.

**2. Execução.** Comando de coleta:

```bash
strace -f -o traces-novos/06-eof.trace ./zigsh
```

```text
Bem-vindo ao zigsh!
zigsh [/home/dBaptista/Shell-strace]>
Encerrando zigsh.
```

Ação: pressionar **Ctrl+D** no prompt vazio, sem digitar `exit`.

**3. Evidência.** Arquivo `traces/06-eof.trace` (cópia da recoleta `traces-novos/06-eof.trace`): PID 2567 = shell.

```text
45:2567  write(1, "Bem-vindo ao zigsh!\n", 20) = 20
46:2567  wait4(-1, 0x7ffc15277cd8, WNOHANG, NULL) = -1 ECHILD (No child process)
47:2567  getcwd("/home/dBaptista/Shell-strace", 4096) = 29
48:2567  write(1, "zigsh [", 7)            = 7
49:2567  write(1, "/home/dBaptista/Shell-strace", 28) = 28
50:2567  write(1, "]>", 2)                 = 2
51:2567  read(0, "", 1)                    = 0
52:2567  write(1, "\nEncerrando zigsh.\n", 19) = 19
61:2567  rt_sigaction(SIGIO, {sa_handler=SIG_DFL, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7fc47ac7b8b4}, NULL, 8) = 0
62:2567  rt_sigaction(SIGPIPE, {sa_handler=SIG_DFL, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7fc47ac7b8b4}, NULL, 8) = 0
63:2567  exit_group(0)                     = ?
64:2567  +++ exited with 0 +++
```

**4. Interpretação.** `read(0, "", 1) = 0` indica zero bytes lidos, ou seja, EOF (diferente da linha vazia do cenário 5, na qual o retorno é 1). O shell executa `write(1, "\nEncerrando zigsh.\n", 19) = 19` e termina com `exit_group(0)` (status zero). Entre a mensagem e o encerramento aparecem `rt_sigaction` e liberações de memória do runtime, sem afetar a conclusão. Não existe filho criado nesse cenário. O resultado confirmou a previsão. Código: `src/main.zig`, função `main` (condição `if (n == 0)` e `imprimir`); encerramento final realizado pelo runtime do processo.

## 4. Inventário de chamadas de sistema

O levantamento foi feito sobre **todos os seis traces brutos da recoleta**. Foram encontradas **30 syscalls distintas**; o inventário a seguir apresenta uma ocorrência real de cada uma, com seus argumentos, retornos e PIDs. Repetições da mesma syscall com finalidades diferentes aparecem em entradas adicionais na seção 3.2. Nos exemplos, `01`–`06` abreviam os arquivos finais `traces/01-comando-externo.trace`, `traces/02-inexistente.trace`, `traces/03-cd.trace`, `traces/04-redirecionamento.trace`, `traces/05-linha-vazia.trace` e `traces/06-eof.trace`, cópias exatas dos arquivos analisados em `traces-novos/`. Os números referem-se às linhas originais dos arquivos, e não à saída de `grep`.

### 4.1 Inventário completo (uma ocorrência por syscall distinta)

| Syscall | Arquivo e linha | PID/TID e programa | Argumentos relevantes | Retorno / erro | Finalidade no contexto |
|---|---|---|---|---|---|
| `execve` | `01-comando-externo.trace:1` | 2600 — `zigsh` após sucesso | `"./zigsh"`, argv `./zigsh` | `0`, êxito | Carrega o executável rastreado; chamadas posteriores do PID pertencem ao `zigsh` |
| `arch_prctl` | `01-comando-externo.trace:2` | 2600 — `zigsh` | `ARCH_SET_FS`, endereço TLS | `0`, êxito | Inicializa estado específico da arquitetura/TLS |
| `set_tid_address` | `01-comando-externo.trace:3` | 2600 — `zigsh` | endereço de memória da thread | `2600` | Configura endereço de gerenciamento da thread |
| `brk` | `01-comando-externo.trace:4` | 2600 — `zigsh` | `NULL` | `0x12d35000` | Consulta limite atual do heap |
| `mmap` | `01-comando-externo.trace:6` | 2600 — `zigsh` | endereço, 4096, `PROT_NONE`, `MAP_PRIVATE\|MAP_FIXED\|MAP_ANONYMOUS` | `0x12d35000` | Mapeia região de memória |
| `mprotect` | `01-comando-externo.trace:8` | 2600 — `zigsh` | endereço, 4096, `PROT_READ` | `0`, êxito | Protege região de memória |
| `prlimit64` | `01-comando-externo.trace:11` | 2600 — `zigsh` | PID 0, `RLIMIT_STACK`, limite novo `NULL` | `0`, êxito | Consulta limite da pilha (8 MiB soft, ilimitado hard) |
| `sigaltstack` | `01-comando-externo.trace:13` | 2600 — `zigsh` | pilha alternativa, 262144 bytes | `0`, êxito | Configura pilha alternativa para sinais |
| `rt_sigprocmask` | `01-comando-externo.trace:14` | 2600 — `zigsh` | `SIG_UNBLOCK`, `[RT_1 RT_2]`, tamanho 8 | `0`, êxito | Altera máscara dos sinais |
| `rt_sigaction` | `01-comando-externo.trace:15` | 2600 — `zigsh` | `SIGSEGV`, handler, flags de sinal | `0`, êxito | Configura tratamento de sinais |
| `sched_getaffinity` | `01-comando-externo.trace:19` | 2600 — `zigsh` | PID 0, tamanho 128, afinidade `[0]` | `32` (bytes da máscara) | Consulta afinidade de CPUs permitidas |
| `munmap` | `01-comando-externo.trace:23` | 2600 — `zigsh` | endereço, 65536 bytes | `0`, êxito | Desfaz mapeamento de memória |
| `write` | `01-comando-externo.trace:45` | 2600 — `zigsh` | fd 1, `Bem-vindo ao zigsh!\n`, 20 bytes | `20` bytes | Exibe mensagem inicial do shell |
| `wait4` | `01-comando-externo.trace:46` | 2600 — `zigsh` | PID `-1`, `WNOHANG` | `-1 ECHILD` | Consulta filhos sem bloquear; não havia filho |
| `getcwd` | `01-comando-externo.trace:47` | 2600 — `zigsh` | buffer, 4096 bytes | `29` (comprimento com NUL) | Obtém caminho atual para o prompt |
| `read` | `05-linha-vazia.trace:50` | 2564 — `zigsh` | fd 0, `"\n"`, 1 byte solicitado | `1` byte | Lê Enter sem comando |
| `pipe2` | `01-comando-externo.trace:68` | 2600 — `zigsh` | fds `[3, 4]`, `O_CLOEXEC` | `0`, êxito | Cria pipe interno para protocolo do spawn |
| `fork` | `01-comando-externo.trace:71` | 2600 — `zigsh` | sem argumentos | `2601` (PID do filho) | Cria processo filho para comando externo |
| `close` | `01-comando-externo.trace:87` | 2600 — `zigsh` | fd 3 | `0`, êxito | Fecha descritor auxiliar no pai |
| `getuid` | `01-comando-externo.trace:97` | 2601 — `/bin/echo` | sem argumentos | `1000` | Consulta UID do utilitário externo |
| `getgid` | `01-comando-externo.trace:98` | 2601 — `/bin/echo` | sem argumentos | `1000` | Consulta GID do utilitário externo |
| `setgid` | `01-comando-externo.trace:101` | 2601 — `/bin/echo` | GID `1000` | `0`, êxito | Ajusta grupo no processo externo |
| `setuid` | `01-comando-externo.trace:105` | 2601 — `/bin/echo` | UID `1000` | `0`, êxito | Ajusta usuário no processo externo |
| `exit_group` | `01-comando-externo.trace:108` | 2601 — `/bin/echo` | status 0 | `?`, não retorna | Encerra o utilitário externo com sucesso |
| `gettid` | `02-inexistente.trace:124` | 2549 — `zigsh` | sem argumentos | `2549` | Obtém TID para formatação do erro |
| `ioctl` | `02-inexistente.trace:125` | 2549 — `zigsh` | fd 2, `TIOCGWINSZ` | `0`, êxito | Consulta dimensões do terminal de erro |
| `writev` | `02-inexistente.trace:126` | 2549 — `zigsh` | fd 2, um vetor de 46 bytes | `46` bytes | Imprime erro do spawn na saída padrão de erros |
| `chdir` | `03-cd.trace:59` | 2553 — `zigsh` | `"/tmp"` | `0`, êxito | Altera diretório de trabalho do shell |
| `openat` | `04-redirecionamento.trace:78` | 2557 — `zigsh` | `AT_FDCWD`, `saida.txt`, flags `O_CREAT\|O_TRUNC`, `0666` | fd `3` | Abre/cria arquivo de saída no processo pai |
| `dup2` | `04-redirecionamento.trace:95` | 2558 — filho antes do `execve` | descritor 3 para fd 1 | `1`, êxito | Redireciona a saída padrão para o arquivo |

### 4.2 Usos adicionais importantes da mesma syscall

As linhas seguintes **não aumentam a contagem de 30 nomes**, mas distinguem aplicações e processos relevantes para a atribuição correta, como pede o enunciado.

| Syscall | Arquivo e linha(s) | PID/TID e programa | Argumentos relevantes | Retorno / erro | Uso distinto |
|---|---|---|---|---|---|
| `execve` | `01-comando-externo.trace:84,89` | 2601 — filho → `/bin/echo` | `/bin/echo`, `ola` | `0` na retomada | O PID permanece 2601, mas a imagem do processo muda após sucesso |
| `execve` | `02-inexistente.trace:111` | 2550 — filho do shell | caminho absoluto inexistente | `-1 ENOENT` | Tenta executar e falha; não passa a existir programa externo carregado |
| `execve` | `03-cd.trace:93,98` | 2554 — filho → `/bin/pwd` | `/bin/pwd` | `0` na retomada | Ponto da mudança de programa do PID 2554 |
| `wait4` | `01-comando-externo.trace:88,110` | 2600 — `zigsh` | PID 2601, espera bloqueante | `2601`, status 0 | Aguarda comando em primeiro plano; diferente de `WNOHANG` |
| `wait4` | `02-inexistente.trace:127` | 2549 — `zigsh` | PID `-1`, `WNOHANG` | `2550`, status 1 | Recolhe filho terminado após falha de execução |
| `read` | `01-comando-externo.trace:86` | 2600 — `zigsh` | fd 3, 8 bytes solicitados | `0`, EOF no pipe | Detecta ausência de comunicação de erro do spawn |
| `read` | `02-inexistente.trace:115,117` | 2549 — `zigsh` | fd 3, 8 bytes | `8` bytes | Lê notificação da falha do `execve` pela biblioteca |
| `read` | `06-eof.trace:51` | 2567 — `zigsh` | fd 0, 1 byte solicitado | `0`, EOF | Fim da entrada; distinto do Enter (1 byte) |
| `write` | `01-comando-externo.trace:107` | 2601 — `/bin/echo` | fd 1, `"ola\n"`, 4 bytes | `4` | Escreve no terminal, antes de qualquer redirecionamento |
| `write` | `04-redirecionamento.trace:120` | 2558 — `/bin/echo` | fd 1, `"ola\n"`, 4 bytes | `4` | Mesmo fd 1, mas agora associado ao arquivo `saida.txt` |
| `write` | `02-inexistente.trace:112,114` | 2550 — filho antes de finalizar | fd 4, 8 bytes | `8` | Comunica erro de lançamento pelo pipe |
| `write` | `06-eof.trace:52` | 2567 — `zigsh` | fd 1, mensagem de 19 bytes | `19` | Exibe encerramento causado por EOF |
| `writev` | `03-cd.trace:118` | 2554 — `/bin/pwd` | fd 1, dois vetores (`/tmp` e `\n`) | `5` | Imprime diretório com escrita vetorizada |
| `getcwd` | `03-cd.trace:61` | 2553 — `zigsh` | buffer, 4096 | `5`, `/tmp` | Atualiza o prompt depois de `chdir` |
| `getcwd` | `03-cd.trace:116` | 2554 — `/bin/pwd` | buffer, 192 | `5`, `/tmp` | O utilitário externo herda o diretório do pai |
| `exit_group` | `02-inexistente.trace:116,118` | 2550 — filho com `execve` falho | status 1 | `?` | Encerra processo da tentativa malsucedida |
| `exit_group` | `01-comando-externo.trace:124` | 2600 — `zigsh` | status 0 | `?` | Encerra o shell após `exit` |
| `dup2` | `04-redirecionamento.trace:95` | 2558 — filho pré-`execve` | `3, 1` | `1` | Troca o destino da saída antes de carregar `/bin/echo` |
| `ioctl` | `03-cd.trace:117` | 2554 — `/bin/pwd` | fd 1, `TIOCGWINSZ` | `0` | Consulta dimensão da saída para o programa externo |

### 4.3 Observações de interpretação e abrangência

- No cenário 1, `execve` bem-sucedido do PID 2601 permite atribuir as linhas 90–108 ao `/bin/echo`, incluindo chamadas de inicialização e credenciais do próprio utilitário. No cenário 3 ocorre o mesmo com PID 2554 (`/bin/pwd`) depois da linha 98; no cenário 4 com PID 2558 (`/bin/echo`) depois da linha 102. No cenário 2, o `execve` do PID 2550 falha: não se deve atribuir suas syscalls ao executável inexistente.
- `fork`, `pipe2`, `dup2`, `execve` e `wait4` evidenciam a implementação do lançamento de processos; o programa Zig chama `std.process.spawn`/`child.wait` e não necessariamente cada uma dessas syscalls diretamente. `waitpid` declarado em `src/executor.zig` aparece como `wait4` no Linux. `writev` da mensagem de erro corresponde a `std.debug.print` no ramo de falha do `main`, mas o trace não revela qual função interna da biblioteca realizou o `ioctl` ou a escrita vetorizada.
- As ocorrências `mmap`, `munmap`, `brk`, `mprotect`, `arch_prctl`, `set_tid_address`, `sigaltstack`, `prlimit64`, `rt_sigaction`, `rt_sigprocmask` e `sched_getaffinity` estão associadas a inicialização, gerenciamento de memória, sinais e contexto de execução. O trace comprova sua ocorrência, argumentos e retorno; sem rastreamento da pilha de chamadas correspondente, **não é possível afirmar a função Zig exata que as originou**.
- O sinal `SIGCHLD` registrado ao término dos filhos é um **evento de sinal**, não uma syscall adicional. As linhas `+++ exited with ... +++` são anotações do `strace`, e não chamadas de sistema. O inventário não as conta entre as 30 syscalls.
- Linhas divididas em `<unfinished ...>` e `<... resumed>` pertencem à **mesma chamada**, intercalada com outras threads/processos; os retornos constam nas linhas de retomada. `= ?` em `exit_group` sinaliza ausência de retorno normal à execução do chamador.

## 5. Conferência final de integridade e entrega

**Arquivos analisados neste relatório:**

| Trace | Linhas | Bytes | SHA-256 (recoleta) |
|---|---|---|---|
| 01-comando-externo.trace | 125 | 8147 | f1ff79aa1574ff93673809c7978b713f9753eb0fbd970c835cf862b7843165c2 |
| 02-inexistente.trace | 140 | 8739 | e0a7012bdf543f274a376a2d7ed185801d2abdad05683eb4a4141f965dc7ddb8 |
| 03-cd.trace | 136 | 8713 | 18209ab837bff1106bdf2266c01f0170c3a2fdc9455fbf30e3d8cb2ef6ba8171 |
| 04-redirecionamento.trace | 138 | 8818 | 13c9a2c5ccbb234e60585da19c5a820fdaf74a64859aa8ee8c27ada321e6ce7b |
| 05-linha-vazia.trace | 63 | 4795 | 6db5aa5c5a1e2202263f179be1530a99e5f5484a4daef13e8965469f12e1b7a6 |
| 06-eof.trace | 64 | 4943 | 83f31429d62de146b0184a892c053b44bb233dac1457b4a3916f6f695c1c5319 |

O arquivo `testes-recoleta/saida.txt` tem quatro bytes e conteúdo `ola\n`. O registro original `traces-novos/ambiente-coleta.txt` também integra a evidência da preparação; sua cópia deve ficar em `evidencias/ambiente-coleta.txt` no repositório e em `entrega/ambiente-coleta.txt` no ZIP final. Os hashes acima servem para comparar as cópias enviadas e as que irão compor o pacote; **não substituem** a assinatura Minisign nem a criptografia age.

**Estado da entrega no momento desta redação:** a análise e o inventário estão concluídos com base nos arquivos recebidos, mas a assinatura Minisign, a cifragem age, a validação de acesso de todos os destinatários e a publicação final no GitHub **não são demonstradas por este pacote de recoleta**. Essas etapas devem ser feitas somente após integrar a versão definitiva dos traces e deste relatório.

**Estrutura exigida para a entrega final:**

```text
entrega/
  relatorio.md
  traces/
    01-comando-externo.trace
    02-inexistente.trace
    03-cd.trace
    04-redirecionamento.trace
    05-linha-vazia.trace
    06-eof.trace
  saida.txt
  ambiente-coleta.txt
```

Depois de montar `entrega.zip` com essa pasta, o integrante responsável deve gerar `entrega.zip.minisig` e validar a assinatura com a chave pública Minisign. O ZIP e a assinatura devem ser reunidos em um TAR criptografado com `age`, incluindo como destinatários o professor e **cada integrante do grupo**. Cada integrante deve testar a descriptografia do pacote final com sua chave privada age, verificar a assinatura e a integridade do ZIP. O repositório deve publicar exclusivamente o arquivo final `strace-shell/pacote-entrega.tar.age` na branch **`strace-shell`** (sem divulgar chaves privadas). Commits assinados por SSH e identificados como **Verified** são uma verificação de Git, **não substituem** a assinatura do ZIP por Minisign.

## 6. Conclusão

As seis coletas demonstram que o `zigsh` cria e espera processos externos, detecta a falha de execução de um caminho inexistente, modifica seu próprio diretório de trabalho com `cd`, redireciona a saída de um programa para arquivo, ignora uma linha vazia e encerra ao receber EOF. O rastreamento mostrou a diferença entre PID do shell e PIDs de filhos, em especial as trocas de programa por `execve` bem-sucedido. Ao todo foram identificadas **30 syscalls distintas**; as repetições com papéis diferentes foram documentadas sem confundi-las com funções em espaço de usuário do Zig. As evidências de `saida.txt` e do ambiente acompanham os seis registros brutos para permitir auditoria da entrega.
