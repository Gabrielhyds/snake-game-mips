# Jogo da Vida de Conway em Assembly MIPS

Trabalho Final de **Arquitetura de Computadores II**. Tema escolhido: **3. Jogo da Vida de Conway**.
Ambiente: simulador **MARS 4.5** (Bitmap Display, Keyboard MMIO e Syscalls).

## Por que este tema?

| Critério | Jogo da Vida |
|---|---|
| Visual na apresentação | Muito bom: padrões que se movem, oscilam e "atiram" na tela |
| Dificuldade | Média. A lógica é simples (4 regras), mas usa muitos conceitos da disciplina |
| Conceitos cobertos | Matrizes 2D, buffer duplo, E/S mapeada em memória (Bitmap e teclado), syscalls, pilha, otimização de laços, operações bit a bit |
| Risco | Baixo. Não depende de áudio nem de arquivos externos, que costumam dar problema no MARS |

Ele cobre os objetivos do próprio tema (matrizes, buffer duplo, otimização de laços) e ainda usa
Bitmap Display, Keyboard MMIO e syscalls. Assim o projeto fica completo sem ser grande demais.

## Como executar

1. Abra o `jogo_da_vida.asm` no MARS 4.5.
2. Abra **Tools → Bitmap Display** e configure:
   - Unit Width / Height in Pixels: **8** / **8**
   - Display Width / Height in Pixels: **512** / **256**
   - Base address for display: **0x10040000 (heap)**
   - Clique em **Connect to MIPS**
3. Abra **Tools → Keyboard and Display MMIO Simulator** e clique em **Connect to MIPS**.
4. **Run → Assemble** (F3) e depois **Run → Go** (F5).
   - Dica: deixe o *Run speed* (slider no topo) no máximo.
5. Digite os comandos na caixa de baixo (**KEYBOARD**) do MMIO Simulator.
   As estatísticas aparecem no console *Run I/O*.

## Controles

| Tecla | Ação |
|---|---|
| `Espaço` / `P` | Pausar / continuar |
| `N` | Avançar 1 geração (quando pausado) |
| `R` | Preencher aleatoriamente (~25% vivas) |
| `C` | Limpar a tela |
| `1` | Canhão de planadores de Gosper |
| `2` | Glider (planador) |
| `3` | Nave LWSS |
| `4` | Pulsar (oscilador de período 3) |
| `5` | R-pentomino (caótico) |
| `+` / `-` | Mais rápido / mais lento |
| `W A S D` | Mover o cursor de edição (visível quando pausado) |
| `E` | Criar / matar a célula sob o cursor |
| `H` | Mostrar a ajuda |
| `Q` | Sair |

As cores indicam a **idade** das células: verde = recém-nascida, ciano = jovem,
azul = adulta, roxo = velha (estruturas estáveis e osciladores).

## Como o programa funciona

### Representação
- Grade de **64 × 32** células (512/8 × 256/8), com bordas **toroidais**: o que sai por um
  lado entra pelo outro.
- Cada célula é **1 byte** com a sua idade (`0` = morta, `1..255` = viva há N gerações).
- Endereço da célula: `base + y*64 + x`, calculado como `base + (y << 6) + x`.

### Buffer duplo
Há dois vetores (`bufA` e `bufB`). A geração N é **lida** de um e a geração N+1 é **escrita**
no outro. No fim de cada passo só os **ponteiros** são trocados (`$s0 ↔ $s1`), sem copiar dados.
Sem o buffer duplo, uma célula já atualizada afetaria as vizinhas na mesma geração.

### Otimizações
- **Wrap com AND em vez de DIV:** como 64 e 32 são potências de 2, `(x-1) mod 64` vira
  `andi $t5, $t5, 63`. Uma instrução no lugar de uma divisão.
- **Endereços das linhas calculados uma vez por linha:** os ponteiros da linha de cima, do meio e
  de baixo são calculados fora do laço das colunas.
- **Contagem sem desvios:** `sltu $a1, $zero, $a1` transforma "idade ≠ 0" em 0/1, que é somado
  direto no contador.
- **Redesenho sob demanda:** a flag `$s7` ("sujo") evita redesenhar a tela quando nada mudou
  (por exemplo, durante a pausa).

### Game loop
```
loop:
    le_teclado        (polling do Keyboard MMIO em 0xFFFF0000 / 0xFFFF0004)
    se rodando ou passo pedido: proxima_geracao
    se sujo: desenha  (1 word por célula no Bitmap Display em 0x10040000)
    sleep(atraso)     (syscall 32 → controla a velocidade)
```

### Registradores globais
| Reg. | Uso |
|---|---|
| `$s0` | ponteiro do buffer atual |
| `$s1` | ponteiro do próximo buffer |
| `$s2` | pausado (0/1) |
| `$s3` | atraso em ms |
| `$s4` | flag "passo único" |
| `$s5`, `$s6` | cursor x, y |
| `$s7` | flag "sujo" (redesenhar) |

### Sub-rotinas
| Rotina | Função |
|---|---|
| `proxima_geracao` | Aplica as regras de Conway e troca os buffers |
| `desenha` | Converte idade em cor e escreve no Bitmap Display |
| `le_teclado` | Lê e trata uma tecla (usa a pilha para salvar `$ra`) |
| `carrega_padrao` | Carrega um padrão a partir de uma tabela de ponteiros |
| `preenche_aleatorio` | Preenche a grade com a syscall 42 |
| `limpa_grade`, `conta_populacao` | Utilitários |
| `imprime_status`, `imprime_ajuda` | Saída no console |

## Sugestão de divisão (4 integrantes)

| Integrante | Responsabilidade | Na apresentação |
|---|---|---|
| 1 | `proxima_geracao` (regras, vizinhança toroidal, buffer duplo) | Explica as regras e o buffer duplo |
| 2 | `desenha` + configuração do Bitmap Display (cores por idade, cursor) | Explica a E/S mapeada em memória para vídeo |
| 3 | `le_teclado` + game loop + controle de velocidade | Explica o polling do MMIO e o frame rate (syscall 32) |
| 4 | Padrões (`tab_padroes`), aleatório, console e testes | Faz a demonstração ao vivo |

## Roteiro de apresentação (~10 min)

1. **O que é o Jogo da Vida** (1 min): as 4 regras.
2. **Demonstração** (3 min): `1` canhão de Gosper → `4` pulsar → `5` R-pentomino → `R` aleatório
   → pausar, editar com o cursor e avançar com `N`.
3. **Estrutura de dados** (2 min): grade de bytes, endereçamento `y<<6 + x`, buffer duplo.
4. **E/S mapeada em memória** (2 min): Bitmap em `0x10040000` e teclado em `0xFFFF0000`.
5. **Otimizações** (1 min): AND no lugar de DIV, ponteiros de linha, `sltu` sem desvio.
6. **Perguntas** (1 min).

## Ideias de extensão (se sobrar tempo)
- Regras alternativas, como *HighLife* (B36/S23): basta mudar as comparações em `proxima_geracao`.
- Mostrar no console o "rastro" de células mortas recentemente.
- Salvar e carregar padrões em arquivo (syscalls 13/14/15/16).
