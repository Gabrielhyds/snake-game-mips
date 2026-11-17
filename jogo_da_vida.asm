###############################################################################
#  JOGO DA VIDA DE CONWAY  -  Assembly MIPS (simulador MARS 4.5)
#  Arquitetura de Computadores II - Trabalho Final (Tema 3)
#
#  Recursos do MARS utilizados:
#    * Bitmap Display ............ saida grafica (E/S mapeada em memoria)
#    * Keyboard and Display MMIO . entrada pelo teclado (polling)
#    * Syscalls .................. 1/4/11 (console), 32 (sleep), 42 (aleatorio)
#
#  CONFIGURACAO DO BITMAP DISPLAY (Tools > Bitmap Display):
#    Unit Width in Pixels .......... 8
#    Unit Height in Pixels ......... 8
#    Display Width in Pixels ....... 512
#    Display Height in Pixels ...... 256
#    Base address for display ...... 0x10040000 (heap)
#    -> clique em "Connect to MIPS"
#
#  TECLADO (Tools > Keyboard and Display MMIO Simulator):
#    -> clique em "Connect to MIPS" e digite na caixa de baixo (KEYBOARD)
#
#  Grade: 64 x 32 celulas (= 512/8 x 256/8), bordas "toroidais" (o que sai
#  por um lado entra pelo outro).
#
#  Cada celula guarda um byte com a sua IDADE:
#     0      = morta
#     1..255 = viva ha N geracoes (usado para colorir as celulas)
###############################################################################

#------------------------------- Constantes -----------------------------------
.eqv BITMAP      0x10040000     # endereco base do Bitmap Display
.eqv KBD_CTRL    0xFFFF0000     # Receiver Control  (bit 0 = tecla pronta)
.eqv KBD_DATA    0xFFFF0004     # Receiver Data     (codigo ASCII da tecla)

.eqv COLS        64             # largura da grade (potencia de 2!)
.eqv ROWS        32             # altura  da grade (potencia de 2!)
.eqv COL_MASK    63             # COLS-1 -> "x mod 64" vira "x AND 63"
.eqv ROW_MASK    31             # ROWS-1 -> "y mod 32" vira "y AND 31"
.eqv ROW_SHIFT   6              # y*64 == y << 6
.eqv CELLS       2048           # COLS * ROWS

.eqv COR_MORTA   0x00101820     # fundo (azul bem escuro)
.eqv COR_NOVA    0x0000FF66     # idade 1      (acabou de nascer)
.eqv COR_JOVEM   0x0000D0FF     # idade 2..3
.eqv COR_ADULTA  0x003C78FF     # idade 4..9
.eqv COR_VELHA   0x00B060FF     # idade >= 10  (estavel / oscilador)
.eqv COR_CURSOR  0x00FFD700     # cursor de edicao (amarelo)
.eqv COR_CURSOR2 0x00FF4040     # cursor sobre celula viva (vermelho)

.eqv DELAY_INI   60             # atraso inicial entre geracoes (ms)
.eqv DELAY_MAX   500
.eqv DELAY_PASSO 20

#------------------------------- Dados ----------------------------------------
.data
# Buffer duplo: a geracao N e lida de um buffer e a N+1 escrita no outro.
# Ao final de cada passo os ponteiros sao trocados (nao ha copia de dados).
bufA:        .space CELLS
bufB:        .space CELLS

geracao:     .word 0
populacao:   .word 0

# ---- Padroes classicos: pares (x,y) terminados por -1 ----
pad_glider:  .byte 1,0, 2,1, 0,2, 1,2, 2,2, -1
pad_lwss:    .byte 1,0, 4,0, 0,1, 0,2, 4,2, 0,3, 1,3, 2,3, 3,3, -1
pad_rpento:  .byte 1,0, 2,0, 0,1, 1,1, 1,2, -1
pad_pulsar:  .byte 2,0,3,0,4,0,8,0,9,0,10,0, 2,5,3,5,4,5,8,5,9,5,10,5
             .byte 2,7,3,7,4,7,8,7,9,7,10,7, 2,12,3,12,4,12,8,12,9,12,10,12
             .byte 0,2,0,3,0,4,0,8,0,9,0,10, 5,2,5,3,5,4,5,8,5,9,5,10
             .byte 7,2,7,3,7,4,7,8,7,9,7,10, 12,2,12,3,12,4,12,8,12,9,12,10, -1
pad_canhao:  .byte 24,0, 22,1,24,1, 12,2,13,2,20,2,21,2,34,2,35,2
             .byte 11,3,15,3,20,3,21,3,34,3,35,3, 0,4,1,4,10,4,16,4,20,4,21,4
             .byte 0,5,1,5,10,5,14,5,16,5,17,5,22,5,24,5, 10,6,16,6,24,6
             .byte 11,7,15,7, 12,8,13,8, -1

# Tabela de padroes (teclas '1'..'5'): endereco, x0, y0 (posicao na tela)
.align 2
tab_padroes: .word pad_canhao, 2,  2
             .word pad_glider, 4,  4
             .word pad_lwss,   2, 14
             .word pad_pulsar, 25, 9
             .word pad_rpento, 31, 15

# ---- Textos do console ----
msg_titulo:  .asciiz "\n========== JOGO DA VIDA DE CONWAY (MIPS) ==========\n"
msg_ajuda:   .asciiz "Controles (digite no Keyboard MMIO Simulator):\n  ESPACO/P  pausar / continuar\n  N         avancar 1 geracao (pausado)\n  R         preencher aleatoriamente\n  C         limpar a tela\n  1..5      padroes: 1 canhao de Gosper, 2 glider, 3 nave LWSS,\n                     4 pulsar, 5 R-pentomino\n  + / -     mais rapido / mais lento\n  W A S D   mover cursor (pausado)\n  E         criar / matar celula sob o cursor\n  H         mostrar esta ajuda\n  Q         sair\n===================================================\n"
msg_ger:     .asciiz "Geracao: "
msg_pop:     .asciiz "   Populacao: "
msg_delay:   .asciiz "   Atraso(ms): "
msg_pausa:   .asciiz "   [PAUSADO]"
msg_nl:      .asciiz "\n"
msg_fim:     .asciiz "\nFim da simulacao. Ate mais!\n"

#------------------------------- Codigo ---------------------------------------
# Registradores globais (preservados durante todo o programa):
#   $s0 = ponteiro para o buffer ATUAL       $s4 = flag "passo unico"
#   $s1 = ponteiro para o PROXIMO buffer     $s5 = cursor x
#   $s2 = pausado (0/1)                      $s6 = cursor y
#   $s3 = atraso em ms                       $s7 = "sujo" (precisa redesenhar)
.text
.globl main
main:
    la   $s0, bufA
    la   $s1, bufB
    li   $s2, 0
    li   $s3, DELAY_INI
    li   $s4, 0
    li   $s5, 32
    li   $s6, 16
    li   $s7, 1

    jal  imprime_ajuda

    li   $a0, 0                 # comeca com o canhao de planadores
    jal  carrega_padrao
    jal  conta_populacao
    jal  desenha
    jal  imprime_status

#----------------------------- GAME LOOP --------------------------------------
loop_principal:
    jal  le_teclado             # v0 = 1 se o usuario pediu para sair
    bnez $v0, fim

    # avanca se estiver rodando OU se foi pedido um passo unico
    beqz $s2, lp_avancar
    beqz $s4, lp_desenhar
lp_avancar:
    li   $s4, 0
    jal  proxima_geracao
    li   $s7, 1

    # imprime estatisticas a cada 25 geracoes (ou a cada passo, se pausado)
    lw   $t0, geracao
    li   $t1, 25
    divu $t0, $t1
    mfhi $t0
    beqz $t0, lp_status
    beqz $s2, lp_desenhar
lp_status:
    jal  imprime_status

lp_desenhar:
    beqz $s7, lp_dormir
    jal  desenha
    li   $s7, 0

lp_dormir:
    move $a0, $s3               # syscall 32: sleep($a0 ms) -> controla o FPS
    bnez $s2, lp_sleep          # pausado: dorme pouco para responder rapido
    beqz $a0, loop_principal
    j    lp_sleep2
lp_sleep:
    li   $a0, 15
lp_sleep2:
    li   $v0, 32
    syscall
    j    loop_principal

fim:
    li   $v0, 4
    la   $a0, msg_fim
    syscall
    li   $v0, 10
    syscall

###############################################################################
# proxima_geracao: aplica as regras de Conway lendo de $s0 e escrevendo em $s1
#   - viva com 2 ou 3 vizinhas  -> sobrevive (idade+1, satura em 255)
#   - morta com exatamente 3    -> nasce (idade 1)
#   - qualquer outro caso       -> morre / continua morta
# Depois troca os ponteiros dos buffers e incrementa o contador de geracoes.
#
# Otimizacao: como COLS e ROWS sao potencias de 2, o "modulo" das bordas
# toroidais e feito com uma unica instrucao AND em vez de DIV.
# Os enderecos das 3 linhas (cima/meio/baixo) sao calculados uma vez por linha.
###############################################################################
proxima_geracao:
    li   $t9, 0                 # t9 = populacao da nova geracao
    li   $t0, 0                 # t0 = y (linha)
pg_linha:
    # t1 = endereco da linha de cima, t2 = linha atual, t3 = linha de baixo
    addi $t1, $t0, -1
    andi $t1, $t1, ROW_MASK
    sll  $t1, $t1, ROW_SHIFT
    add  $t1, $t1, $s0

    sll  $t2, $t0, ROW_SHIFT
    add  $t2, $t2, $s0

    addi $t3, $t0, 1
    andi $t3, $t3, ROW_MASK
    sll  $t3, $t3, ROW_SHIFT
    add  $t3, $t3, $s0

    li   $t4, 0                 # t4 = x (coluna)
pg_coluna:
    addi $t5, $t4, -1           # t5 = x-1 (com wrap)
    andi $t5, $t5, COL_MASK
    addi $t6, $t4, 1            # t6 = x+1 (com wrap)
    andi $t6, $t6, COL_MASK

    li   $t7, 0                 # t7 = numero de vizinhas vivas
    # --- linha de cima ---
    add  $a0, $t1, $t5
    lbu  $a1, 0($a0)
    sltu $a1, $zero, $a1        # a1 = (idade != 0) ? 1 : 0
    add  $t7, $t7, $a1
    add  $a0, $t1, $t4
    lbu  $a1, 0($a0)
    sltu $a1, $zero, $a1
    add  $t7, $t7, $a1
    add  $a0, $t1, $t6
    lbu  $a1, 0($a0)
    sltu $a1, $zero, $a1
    add  $t7, $t7, $a1
    # --- mesma linha (esquerda e direita) ---
    add  $a0, $t2, $t5
    lbu  $a1, 0($a0)
    sltu $a1, $zero, $a1
    add  $t7, $t7, $a1
    add  $a0, $t2, $t6
    lbu  $a1, 0($a0)
    sltu $a1, $zero, $a1
    add  $t7, $t7, $a1
    # --- linha de baixo ---
    add  $a0, $t3, $t5
    lbu  $a1, 0($a0)
    sltu $a1, $zero, $a1
    add  $t7, $t7, $a1
    add  $a0, $t3, $t4
    lbu  $a1, 0($a0)
    sltu $a1, $zero, $a1
    add  $t7, $t7, $a1
    add  $a0, $t3, $t6
    lbu  $a1, 0($a0)
    sltu $a1, $zero, $a1
    add  $t7, $t7, $a1

    # --- estado atual da celula ---
    add  $a0, $t2, $t4
    lbu  $t8, 0($a0)            # t8 = idade atual
    li   $a2, 3
    beqz $t8, pg_morta

    # celula viva: sobrevive com 2 ou 3 vizinhas
    li   $a3, 2
    beq  $t7, $a3, pg_sobrevive
    beq  $t7, $a2, pg_sobrevive
    li   $t8, 0                 # morre (solidao ou superpopulacao)
    j    pg_grava
pg_sobrevive:
    sltiu $a3, $t8, 255         # envelhece ate o limite de 255
    add  $t8, $t8, $a3
    j    pg_vivo
pg_morta:
    bne  $t7, $a2, pg_grava     # t8 ja e 0
    li   $t8, 1                 # nasce!
pg_vivo:
    addi $t9, $t9, 1
pg_grava:
    sub  $a0, $a0, $s0          # deslocamento da celula dentro do buffer
    add  $a0, $a0, $s1          # mesma posicao no proximo buffer
    sb   $t8, 0($a0)

    addi $t4, $t4, 1
    blt  $t4, COLS, pg_coluna
    addi $t0, $t0, 1
    blt  $t0, ROWS, pg_linha

    # troca dos buffers (buffer duplo): atual <-> proximo
    move $t0, $s0
    move $s0, $s1
    move $s1, $t0

    sw   $t9, populacao
    lw   $t0, geracao
    addi $t0, $t0, 1
    sw   $t0, geracao
    jr   $ra

###############################################################################
# desenha: percorre o buffer atual e escreve uma cor (word) por celula no
# Bitmap Display. A cor depende da idade da celula. Se pausado, desenha o
# cursor de edicao por cima.
###############################################################################
desenha:
    move $t0, $s0               # t0 = ponteiro da celula
    li   $t1, BITMAP            # t1 = ponteiro do pixel
    addi $t2, $s0, CELLS        # t2 = fim do buffer
    li   $t5, COR_MORTA
    li   $t6, COR_NOVA
    li   $t7, COR_JOVEM
    li   $t8, COR_ADULTA
    li   $t9, COR_VELHA
ds_loop:
    lbu  $t3, 0($t0)
    move $t4, $t5               # morta
    beqz $t3, ds_pinta
    move $t4, $t6               # idade 1
    slti $a0, $t3, 2
    bnez $a0, ds_pinta
    move $t4, $t7               # idade 2..3
    slti $a0, $t3, 4
    bnez $a0, ds_pinta
    move $t4, $t8               # idade 4..9
    slti $a0, $t3, 10
    bnez $a0, ds_pinta
    move $t4, $t9               # idade >= 10
ds_pinta:
    sw   $t4, 0($t1)
    addi $t0, $t0, 1
    addi $t1, $t1, 4
    bne  $t0, $t2, ds_loop

    beqz $s2, ds_fim            # cursor so aparece quando pausado
    sll  $t0, $s6, ROW_SHIFT    # indice = y*64 + x
    add  $t0, $t0, $s5
    add  $t3, $t0, $s0
    lbu  $t3, 0($t3)
    li   $t4, COR_CURSOR
    beqz $t3, ds_cursor
    li   $t4, COR_CURSOR2
ds_cursor:
    sll  $t0, $t0, 2            # *4 bytes por pixel
    li   $t1, BITMAP
    add  $t0, $t0, $t1
    sw   $t4, 0($t0)
ds_fim:
    jr   $ra

###############################################################################
# le_teclado: verifica (polling) o Keyboard MMIO e trata UMA tecla.
# Retorno: $v0 = 1 se o usuario pediu para sair, 0 caso contrario.
###############################################################################
le_teclado:
    addi $sp, $sp, -4
    sw   $ra, 0($sp)
    li   $v0, 0

    li   $t0, KBD_CTRL
    lw   $t1, 0($t0)
    andi $t1, $t1, 1            # bit "ready"
    beqz $t1, lt_sai
    lw   $t1, 4($t0)            # KBD_DATA: le a tecla (limpa o ready)

    # converte maiuscula para minuscula ('A'..'Z' -> 'a'..'z')
    blt  $t1, 65, lt_desp   # 'A'
    bgt  $t1, 90, lt_desp   # 'Z'
    addi $t1, $t1, 32
lt_desp:
    li   $s7, 1                 # qualquer tecla -> redesenha
    beq  $t1, 32, lt_pausa   # ' '
    beq  $t1, 112, lt_pausa   # 'p'
    beq  $t1, 110, lt_passo   # 'n'
    beq  $t1, 114, lt_aleat   # 'r'
    beq  $t1, 99, lt_limpa   # 'c'
    beq  $t1, 43, lt_rapido   # '+'
    beq  $t1, 61, lt_rapido   # '='
    beq  $t1, 45, lt_lento   # '-'
    beq  $t1, 119, lt_cima   # 'w'
    beq  $t1, 115, lt_baixo   # 's'
    beq  $t1, 97, lt_esq   # 'a'
    beq  $t1, 100, lt_dir   # 'd'
    beq  $t1, 101, lt_edita   # 'e'
    beq  $t1, 104, lt_ajuda   # 'h'
    beq  $t1, 113, lt_sair   # 'q'
    blt  $t1, 49, lt_sai   # '1'
    bgt  $t1, 53, lt_sai   # '5'
    # '1'..'5' -> carrega padrao 0..4
    addi $a0, $t1, -49
    jal  carrega_padrao
    j    lt_reinicia

lt_pausa:
    xori $s2, $s2, 1
    jal  imprime_status
    j    lt_sai
lt_passo:
    beqz $s2, lt_sai            # so faz sentido pausado
    li   $s4, 1
    j    lt_sai
lt_aleat:
    jal  preenche_aleatorio
    j    lt_reinicia
lt_limpa:
    jal  limpa_grade
    j    lt_reinicia
lt_rapido:
    addi $s3, $s3, -20          # -DELAY_PASSO
    bgez $s3, lt_vel
    li   $s3, 0
    j    lt_vel
lt_lento:
    addi $s3, $s3, DELAY_PASSO
    ble  $s3, DELAY_MAX, lt_vel
    li   $s3, DELAY_MAX
lt_vel:
    jal  imprime_status
    j    lt_sai
lt_cima:
    addi $s6, $s6, -1
    andi $s6, $s6, ROW_MASK
    j    lt_sai
lt_baixo:
    addi $s6, $s6, 1
    andi $s6, $s6, ROW_MASK
    j    lt_sai
lt_esq:
    addi $s5, $s5, -1
    andi $s5, $s5, COL_MASK
    j    lt_sai
lt_dir:
    addi $s5, $s5, 1
    andi $s5, $s5, COL_MASK
    j    lt_sai
lt_edita:
    sll  $t0, $s6, ROW_SHIFT
    add  $t0, $t0, $s5
    add  $t0, $t0, $s0
    lbu  $t1, 0($t0)
    sltiu $t1, $t1, 1           # viva -> 0 ; morta -> 1
    sb   $t1, 0($t0)
    jal  conta_populacao
    j    lt_sai
lt_ajuda:
    jal  imprime_ajuda
    j    lt_sai
lt_sair:
    li   $v0, 1
    j    lt_ret

lt_reinicia:                    # nova configuracao -> zera o contador
    sw   $zero, geracao
    jal  conta_populacao
    jal  imprime_status
lt_sai:
    li   $v0, 0
lt_ret:
    lw   $ra, 0($sp)
    addi $sp, $sp, 4
    jr   $ra

###############################################################################
# limpa_grade: zera o buffer atual (escrevendo words de 4 em 4 bytes)
###############################################################################
limpa_grade:
    move $t0, $s0
    addi $t1, $s0, CELLS
lg_loop:
    sw   $zero, 0($t0)
    addi $t0, $t0, 4
    bne  $t0, $t1, lg_loop
    jr   $ra

###############################################################################
# preenche_aleatorio: cada celula fica viva com ~25% de chance (syscall 42)
###############################################################################
preenche_aleatorio:
    move $t0, $s0
    addi $t1, $s0, CELLS
pa_loop:
    li   $v0, 42                # random int range: a0 = id, a1 = limite
    li   $a0, 0
    li   $a1, 4
    syscall                     # a0 = 0..3
    sltiu $t2, $a0, 1           # viva se sorteou 0
    sb   $t2, 0($t0)
    addi $t0, $t0, 1
    bne  $t0, $t1, pa_loop
    jr   $ra

###############################################################################
# carrega_padrao: limpa a grade e desenha o padrao de indice $a0 (0..4)
#   tab_padroes[i] = { endereco da lista (x,y), x0, y0 }  -> 12 bytes
###############################################################################
carrega_padrao:
    addi $sp, $sp, -8
    sw   $ra, 0($sp)
    sw   $a0, 4($sp)
    jal  limpa_grade
    lw   $a0, 4($sp)

    li   $t0, 12
    mul  $t0, $a0, $t0
    la   $t1, tab_padroes
    add  $t1, $t1, $t0
    lw   $t2, 0($t1)            # t2 = ponteiro para os pares (x,y)
    lw   $t3, 4($t1)            # t3 = x0
    lw   $t4, 8($t1)            # t4 = y0
cp_loop:
    lb   $t5, 0($t2)            # x (com sinal: -1 = fim da lista)
    bltz $t5, cp_fim
    lb   $t6, 1($t2)            # y
    add  $t5, $t5, $t3
    andi $t5, $t5, COL_MASK
    add  $t6, $t6, $t4
    andi $t6, $t6, ROW_MASK
    sll  $t6, $t6, ROW_SHIFT
    add  $t6, $t6, $t5
    add  $t6, $t6, $s0
    li   $t7, 1
    sb   $t7, 0($t6)
    addi $t2, $t2, 2
    j    cp_loop
cp_fim:
    lw   $ra, 0($sp)
    addi $sp, $sp, 8
    jr   $ra

###############################################################################
# conta_populacao: conta as celulas vivas do buffer atual
###############################################################################
conta_populacao:
    move $t0, $s0
    addi $t1, $s0, CELLS
    li   $t2, 0
cpop_loop:
    lbu  $t3, 0($t0)
    sltu $t3, $zero, $t3
    add  $t2, $t2, $t3
    addi $t0, $t0, 1
    bne  $t0, $t1, cpop_loop
    sw   $t2, populacao
    jr   $ra

###############################################################################
# Rotinas de console
###############################################################################
imprime_ajuda:
    li   $v0, 4
    la   $a0, msg_titulo
    syscall
    la   $a0, msg_ajuda
    syscall
    jr   $ra

imprime_status:
    li   $v0, 4
    la   $a0, msg_ger
    syscall
    li   $v0, 1
    lw   $a0, geracao
    syscall
    li   $v0, 4
    la   $a0, msg_pop
    syscall
    li   $v0, 1
    lw   $a0, populacao
    syscall
    li   $v0, 4
    la   $a0, msg_delay
    syscall
    li   $v0, 1
    move $a0, $s3
    syscall
    beqz $s2, is_nl
    li   $v0, 4
    la   $a0, msg_pausa
    syscall
is_nl:
    li   $v0, 4
    la   $a0, msg_nl
    syscall
    jr   $ra
