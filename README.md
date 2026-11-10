# zigsh — Shell Básico em Linux com Zig

Trabalho Prático Avaliativo — Construção de um Shell Básico em Linux (`zigsh`).

Integrantes: Isaias Maia de Oliveira e Daniel Santos Baptista.

## 1. Descrição do projeto

O **zigsh** é um interpretador de comandos (shell) minimalista, desenvolvido em **Zig 0.16.0** para sistemas Linux.

O projeto tem como objetivo aplicar conceitos de Sistemas Operacionais, incluindo:

- Gerenciamento e criação de processos.
- Execução de comandos internos e externos.
- Processos em primeiro e segundo plano.
- Comunicação entre processos por pipelines (IPC).
- Redirecionamento de entrada, saída e erros.
- Manipulação de arquivos e diretórios.

## 2. Tecnologias utilizadas

- Linguagem: Zig 0.16.0
- Sistema operacional: Linux (Ubuntu 26.04.1 LTS)
- Ambiente de desenvolvimento: Visual Studio Code
- Ambiente de execução: WSL 2
- Controle de versão: Git e GitHub

## 3. Estrutura do projeto

```text
Shell/
├── src/
│   ├── main.zig
│   ├── parser.zig
│   └── executor.zig
├── tests/
│   └── test_executor.zig
├── .gitignore
└── README.md
```

### Descrição dos arquivos

**main.zig:** implementa o ciclo REPL, o prompt dinâmico, a leitura de comandos e os comandos internos.

**parser.zig:** realiza a tokenização da entrada e identifica argumentos, aspas, redirecionamentos, pipelines e execução em segundo plano.

**executor.zig:** executa comandos externos, gerencia processos filhos, realiza redirecionamentos e conecta processos por pipes.

**test_executor.zig:** contém um programa de teste para execução de comandos externos.

## 4. Funcionalidades implementadas

### 4.1. REPL e prompt dinâmico

O shell mantém um ciclo contínuo de leitura e execução de comandos, exibindo o diretório atual.

Exemplo:

```text
zigsh [/home/usuario]>
```

O shell pode ser encerrado utilizando `exit` ou `Ctrl+D`.

### 4.2. Comandos internos

| Comando | Descrição |
|---|---|
| `cd [diretório]` | Altera o diretório atual |
| `pwd` | Exibe o diretório atual |
| `help` | Exibe os comandos disponíveis |
| `exit [código]` | Encerra o shell |

### 4.3. Comandos externos

Permite executar programas disponíveis no Linux, criando processos filhos.

Exemplo:

```bash
/bin/ls
/bin/echo Ola
/bin/date
```

### 4.4. Redirecionamento de arquivos

Operadores suportados:

| Operador | Função |
|---|---|
| `>` | Redireciona a saída padrão |
| `2>` | Redireciona a saída de erro |
| `<` | Redireciona a entrada padrão |

Exemplos:

```bash
/bin/echo Teste > saida.txt
/bin/ls /inexistente 2> erros.log
/bin/grep Teste < saida.txt
```

### 4.5. Execução em segundo plano

Utiliza o operador `&` no final do comando.

```bash
/bin/sleep 5 &
```

O shell inicia o processo sem aguardar sua finalização e retorna ao prompt.

### 4.6. Pipelines

Permite conectar a saída de um processo à entrada de outro usando `|`.

Exemplo:

```bash
/bin/echo Alvo 123 | /bin/grep Alvo
```

### 4.7. Argumentos entre aspas

O parser suporta argumentos totalmente delimitados por aspas simples ou duplas.

Exemplos:

```bash
/bin/echo "Ola mundo"
/bin/printf 'Linha 1\nLinha 2\n'
```

## 5. Compilação

### Pré-requisitos

- Linux
- Zig 0.16.0
- Biblioteca C disponível para vinculação

Verifique o compilador:

```bash
zig version
```

Resultado utilizado durante o desenvolvimento:

```text
0.16.0
```

### Compilar o projeto

Na raiz do repositório, execute:

```bash
zig build-exe -lc \
  --dep parser --dep executor \
  -Mroot=src/main.zig \
  -Mparser=src/parser.zig \
  --dep parser -Mexecutor=src/executor.zig \
  -femit-bin=zigsh
```

### Executar

```bash
./zigsh
```

## 6. Testes e validação

Os seguintes testes funcionais foram realizados em ambiente Ubuntu com Zig 0.16.0.

### Teste A — Comandos internos

```bash
pwd
cd /tmp
pwd
help
exit 0
```

**Resultado:** os comandos internos foram executados corretamente e o diretório exibido pelo prompt foi atualizado.

**Situação:** aprovado.

### Teste B — Redirecionamento de saída

```bash
/bin/echo "Teste de criacao de arquivo pelo shell zigsh" > saida.txt
/bin/cat saida.txt
```

**Resultado esperado e observado:**

```text
Teste de criacao de arquivo pelo shell zigsh
```

**Situação:** aprovado.

### Teste C — Redirecionamento de erro

```bash
/bin/ls /caminho_inexistente 2> erros.log
/bin/cat erros.log
```

**Resultado:** o erro do comando foi registrado em `erros.log` e pôde ser consultado com `cat`.

**Situação:** aprovado.

### Teste D — Redirecionamento de entrada

```bash
/bin/grep Teste < saida.txt
```

**Resultado:** o comando leu o arquivo de entrada e encontrou o texto esperado.

**Situação:** aprovado.

### Teste E — Execução em segundo plano

```bash
/bin/sleep 5 &
pwd
```

**Resultado observado:**

```text
[Processo disparado em segundo plano]
```

O prompt retornou sem aguardar os cinco segundos, permitindo executar `pwd`.

**Situação:** aprovado.

### Teste F — Pipeline

```bash
/bin/printf 'Linha 1\nLinha 2\nAlvo 123\n' | /bin/grep Alvo
```

**Resultado esperado e observado:**

```text
Alvo 123
```

**Situação:** aprovado.

## 7. Testes unitários

O arquivo `src/parser.zig` contém testes unitários para validar a interpretação de comandos.

Para executar:

```bash
zig test src/parser.zig
```

Resultado obtido:

```text
All 14 tests passed.
```

Os testes incluem:

- Comandos e argumentos.
- Redirecionamento de entrada.
- Redirecionamento de saída.
- Redirecionamento de erros.
- Execução em segundo plano.
- Pipelines.
- Redirecionamentos combinados.
- Operadores sem espaços.
- Rejeição de comandos inválidos.
- Argumentos entre aspas simples.
- Argumentos entre aspas duplas.

## 8. Limitações e melhorias futuras

A implementação atende aos cenários básicos testados, mas pode ser ampliada com:

- Suporte a aspas misturadas dentro de um mesmo argumento.
- Tratamento mais completo de caracteres de escape.
- Histórico de comandos.
- Gerenciamento avançado de tarefas em segundo plano.
- Tratamento de sinais e interrupções.
- Testes de integração automatizados.
- Melhor tratamento de erros em pipelines.

## 9. Conclusão

O projeto permitiu aplicar conceitos fundamentais de Sistemas Operacionais utilizando Zig.

Foram implementadas e testadas funcionalidades de interpretação de comandos, criação de processos, execução concorrente, redirecionamento de arquivos e comunicação entre processos.

Os seis testes funcionais definidos no enunciado foram executados com sucesso, assim como os 14 testes unitários do parser.

