###############################################################################
#  JOGO DA COBRINHA (SNAKE)  -  Assembly MIPS (simulador MARS 4.5)
#  Arquitetura de Computadores II - Trabalho Final (Tema 1)
#
#  Recursos do MARS utilizados:
#    * Bitmap Display ............ video (E/S mapeada em memoria): escrita E
#                                  leitura de pixels (a colisao e detectada
#                                  lendo a cor da memoria de video)
#    * Keyboard and Display MMIO . teclado por polling
#    * Syscalls .................. 30 (tempo), 32 (sleep), 42 (aleatorio),
#                                  1/4 (console), 10 (sair)
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
#  Tela: 64 x 32 unidades.
#     linhas 0..6  = painel (placar e recorde desenhados com fonte 3x5)
#     linha 7 e 31, colunas 0 e 63 = paredes
#     area de jogo = colunas 1..62, linhas 8..30
#
#  Posicao de uma celula = y*64 + x   (endereco do pixel = BITMAP + pos*4)
#
#  O corpo da cobra e um BUFFER CIRCULAR de halfwords (posicoes):
#     cabeca = corpo[$s0], cauda = corpo[$s1]
#     andar = escrever nova cabeca em ($s0+1) e "soltar" a cauda ($s1+1)
#     crescer = andar sem soltar a cauda.   Tudo em O(1) por quadro!
###############################################################################

#------------------------------- Constantes -----------------------------------
.eqv BITMAP      0x10040000
.eqv KBD_CTRL    0xFFFF0000     # bit 0 = existe tecla pronta
.eqv KBD_DATA    0xFFFF0004     # codigo ASCII da tecla

.eqv COLS        64
.eqv ROW_SHIFT   6              # y*64 == y << 6
.eqv CELLS       2048           # 64 x 32
.eqv HUD_ROWS    7              # linhas 0..6 = painel
.eqv TOPO        7              # linha da parede de cima
.eqv BASE        31             # linha da parede de baixo
.eqv DIREITA     63             # coluna da parede da direita

.eqv BUF_MASK    2047           # buffer circular com 2048 posicoes
.eqv CRESCE      3              # segmentos ganhos por comida

.eqv FRAME_INI   120            # ms por quadro no inicio (~8 FPS)
.eqv FRAME_MIN   50             # limite de velocidade (~20 FPS)
.eqv FRAME_PASSO 4              # acelera 4 ms a cada comida

.eqv COR_FUNDO   0x0012141C
.eqv COR_HUD     0x00202436
.eqv COR_PAREDE  0x00505A78
.eqv COR_CORPO   0x0022C55E
.eqv COR_CABECA  0x00A3FF7A
.eqv COR_COMIDA  0x00FF4D4D
.eqv COR_MORTA   0x00B02020
.eqv COR_PLACAR  0x00FFFFFF
.eqv COR_RECORDE 0x00FFD700

#------------------------------- Dados ----------------------------------------
.data
corpo:       .space 4096        # 2048 halfwords (buffer circular de posicoes)
recorde:     .word 0

# Fonte 3x5 para os digitos 0..9. Cada digito = 15 bits (5 linhas de 3 bits),
# do bit 14 (canto superior esquerdo) ate o bit 0 (canto inferior direito).
fonte:       .word 0x7B6F, 0x2C97, 0x73E7, 0x73CF, 0x5BC9
             .word 0x79CF, 0x79EF, 0x7292, 0x7BEF, 0x7BCF

msg_titulo:  .asciiz "\n============ JOGO DA COBRINHA (MIPS) ============\n"
msg_ajuda:   .asciiz "Controles (digite no Keyboard MMIO Simulator):\n  W A S D   mover (cima / esquerda / baixo / direita)\n  P         pausar / continuar\n  R         reiniciar\n  Q         sair\nComa a comida vermelha para crescer. Nao bata nas\nparedes nem no proprio corpo!\n=================================================\n"
msg_comeca:  .asciiz "\n>> Novo jogo! Pressione W, A, S ou D para comecar.\n"
msg_pontos:  .asciiz "Pontos: "
msg_rec:     .asciiz "   Recorde: "
msg_vel:     .asciiz "   ms/quadro: "
msg_nl:      .asciiz "\n"
msg_pausa:   .asciiz "[PAUSADO] pressione P para continuar\n"
msg_gameov:  .asciiz "\n*** GAME OVER ***\n"
msg_novorec: .asciiz "*** NOVO RECORDE! ***\n"
msg_denovo:  .asciiz "Pressione R para jogar de novo ou Q para sair.\n"
msg_fim:     .asciiz "\nObrigado por jogar!\n"

#------------------------------- Codigo ---------------------------------------
# Registradores globais:
#   $s0 = indice da CABECA no buffer circular   $s4 = pontos
#   $s1 = indice da CAUDA  no buffer circular   $s5 = duracao do quadro (ms)
#   $s2 = direcao (deslocamento: +1,-1,+64,-64) $s6 = pausado (0/1)
#   $s3 = segmentos a crescer (pendentes)       $s7 = instante do inicio do quadro
.text
.globl main
main:
    li   $v0, 4
    la   $a0, msg_titulo
    syscall
    la   $a0, msg_ajuda
    syscall

novo_jogo:
    jal  inicia_jogo

#----------------------------- GAME LOOP --------------------------------------
# Taxa de quadros fixa: marca o tempo no inicio do quadro (syscall 30), faz o
# trabalho e dorme apenas o que FALTA para completar $s5 ms (syscall 32).
loop_principal:
    li   $v0, 30                # tempo do sistema em ms -> $a0 (parte baixa)
    syscall
    move $s7, $a0

    jal  le_teclado             # v0: 0 = nada, 1 = sair, 2 = reiniciar
    li   $t0, 1
    beq  $v0, $t0, fim
    li   $t0, 2
    beq  $v0, $t0, novo_jogo

    bnez $s6, espera_quadro     # pausado: nao anda
    jal  move_cobra             # v0 = 1 se bateu
    bnez $v0, game_over

espera_quadro:
    li   $v0, 30
    syscall
    sub  $t0, $a0, $s7          # t0 = tempo gasto neste quadro
    sub  $a0, $s5, $t0          # a0 = tempo que falta
    blez $a0, loop_principal
    li   $v0, 32
    syscall
    j    loop_principal

#----------------------------- GAME OVER --------------------------------------
game_over:
    jal  pinta_cobra_morta
    li   $v0, 4
    la   $a0, msg_gameov
    syscall

    lw   $t0, recorde
    ble  $s4, $t0, go_placar
    sw   $s4, recorde
    li   $v0, 4
    la   $a0, msg_novorec
    syscall
go_placar:
    jal  desenha_placar
    jal  imprime_placar
    li   $v0, 4
    la   $a0, msg_denovo
    syscall

go_espera:                      # espera R (reiniciar) ou Q (sair)
    li   $t0, KBD_CTRL
    lw   $t1, 0($t0)
    andi $t1, $t1, 1
    beqz $t1, go_dorme
    lw   $t1, 4($t0)
    ori  $t1, $t1, 0x20         # truque ASCII: 'R'|0x20 = 'r' (minuscula)
    li   $t2, 114               # 'r'
    beq  $t1, $t2, novo_jogo
    li   $t2, 113               # 'q'
    beq  $t1, $t2, fim
go_dorme:
    li   $v0, 32
    li   $a0, 20
    syscall
    j    go_espera

fim:
    li   $v0, 4
    la   $a0, msg_fim
    syscall
    li   $v0, 10
    syscall

###############################################################################
# inicia_jogo: desenha a tela (painel, paredes, fundo), cria a cobra com
# 4 segmentos, sorteia a primeira comida e zera o placar.
###############################################################################
inicia_jogo:
    addi $sp, $sp, -4
    sw   $ra, 0($sp)

    # ---- pinta todas as 2048 unidades da tela ----
    li   $t0, 0                 # t0 = posicao (0..2047)
    li   $t1, BITMAP            # t1 = endereco do pixel
ij_tela:
    srl  $t2, $t0, ROW_SHIFT    # t2 = y
    andi $t3, $t0, 63           # t3 = x
    li   $t4, COR_HUD
    blt  $t2, HUD_ROWS, ij_pinta
    li   $t4, COR_PAREDE
    beq  $t2, TOPO, ij_pinta
    beq  $t2, BASE, ij_pinta
    beqz $t3, ij_pinta
    beq  $t3, DIREITA, ij_pinta
    li   $t4, COR_FUNDO
ij_pinta:
    sw   $t4, 0($t1)
    addi $t0, $t0, 1
    addi $t1, $t1, 4
    blt  $t0, CELLS, ij_tela

    # ---- cobra inicial: (9,19) (10,19) (11,19) (12,19), indo para a direita
    la   $t0, corpo
    li   $t1, 1225              # 19*64 + 9
    li   $t2, 0                 # t2 = indice no buffer
    li   $t5, BITMAP
    li   $t6, COR_CORPO
ij_cobra:
    sh   $t1, 0($t0)
    sll  $t3, $t1, 2
    add  $t3, $t3, $t5
    sw   $t6, 0($t3)
    addi $t0, $t0, 2
    addi $t1, $t1, 1
    addi $t2, $t2, 1
    blt  $t2, 4, ij_cobra
    li   $t6, COR_CABECA        # repinta o ultimo segmento como cabeca
    sw   $t6, 0($t3)

    li   $s0, 3                 # cabeca = corpo[3]
    li   $s1, 0                 # cauda  = corpo[0]
    li   $s2, 1                 # direita
    li   $s3, 0
    li   $s4, 0
    li   $s5, FRAME_INI
    li   $s6, 1                 # comeca pausado ate apertar W/A/S/D

    jal  sorteia_comida
    jal  desenha_placar
    li   $v0, 4
    la   $a0, msg_comeca
    syscall

    lw   $ra, 0($sp)
    addi $sp, $sp, 4
    jr   $ra

###############################################################################
# move_cobra: avanca a cobra uma casa na direcao $s2.
# Retorno: $v0 = 1 se a cobra morreu, 0 caso contrario.
#
# Ordem importa: a cauda e apagada ANTES de testar a colisao, entao a cabeca
# pode entrar na casa que a cauda acabou de liberar.
###############################################################################
move_cobra:
    addi $sp, $sp, -4
    sw   $ra, 0($sp)

    li   $t8, 0                 # t8 = 1 se comeu nesta jogada
    la   $t1, corpo
    li   $t5, BITMAP

    sll  $t0, $s0, 1            # posicao atual da cabeca
    add  $t0, $t0, $t1
    lhu  $t2, 0($t0)            # t2 = cabeca antiga
    add  $t3, $t2, $s2          # t3 = nova cabeca

    # ---- cauda: apaga, a menos que ainda esteja crescendo ----
    bgtz $s3, mc_cresce
    sll  $t0, $s1, 1
    add  $t0, $t0, $t1
    lhu  $t4, 0($t0)
    sll  $t4, $t4, 2
    add  $t4, $t4, $t5
    li   $t6, COR_FUNDO
    sw   $t6, 0($t4)
    addi $s1, $s1, 1
    andi $s1, $s1, BUF_MASK     # avanca a cauda no buffer circular
    j    mc_colisao
mc_cresce:
    addi $s3, $s3, -1

    # ---- colisao: LE a cor do pixel de destino na memoria de video ----
mc_colisao:
    sll  $t4, $t3, 2
    add  $t4, $t4, $t5          # t4 = endereco do pixel da nova cabeca
    lw   $t6, 0($t4)
    li   $t7, COR_COMIDA
    beq  $t6, $t7, mc_come
    li   $t7, COR_FUNDO
    bne  $t6, $t7, mc_morre     # parede ou corpo
    j    mc_avanca
mc_come:
    li   $t8, 1
    addi $s4, $s4, 1            # +1 ponto
    addi $s3, $s3, CRESCE       # vai crescer nos proximos quadros
    addi $s5, $s5, -4           # -FRAME_PASSO: fica mais rapido
    bge  $s5, FRAME_MIN, mc_avanca
    li   $s5, FRAME_MIN

mc_avanca:
    sll  $t9, $t2, 2            # cabeca antiga vira corpo
    add  $t9, $t9, $t5
    li   $t7, COR_CORPO
    sw   $t7, 0($t9)

    addi $s0, $s0, 1            # empilha a nova cabeca no buffer circular
    andi $s0, $s0, BUF_MASK
    sll  $t0, $s0, 1
    add  $t0, $t0, $t1
    sh   $t3, 0($t0)
    li   $t7, COR_CABECA
    sw   $t7, 0($t4)

    beqz $t8, mc_ok
    jal  sorteia_comida         # comeu: nova comida e placar atualizado
    jal  desenha_placar
    jal  imprime_placar
mc_ok:
    li   $v0, 0
    j    mc_ret
mc_morre:
    li   $v0, 1
mc_ret:
    lw   $ra, 0($sp)
    addi $sp, $sp, 4
    jr   $ra

###############################################################################
# le_teclado: polling do Keyboard MMIO. Trata no maximo UMA tecla por quadro.
# Retorno: $v0 = 0 (nada), 1 (sair), 2 (reiniciar)
###############################################################################
le_teclado:
    addi $sp, $sp, -4
    sw   $ra, 0($sp)

    li   $t0, KBD_CTRL
    lw   $t1, 0($t0)
    andi $t1, $t1, 1            # bit "ready"
    beqz $t1, lt_nada
    lw   $t1, 4($t0)            # le a tecla (isso limpa o "ready")
    ori  $t1, $t1, 0x20         # maiuscula -> minuscula

    li   $t2, -64
    beq  $t1, 119, lt_direcao   # 'w'
    li   $t2, 64
    beq  $t1, 115, lt_direcao   # 's'
    li   $t2, -1
    beq  $t1, 97, lt_direcao    # 'a'
    li   $t2, 1
    beq  $t1, 100, lt_direcao   # 'd'
    beq  $t1, 112, lt_pausa     # 'p'
    beq  $t1, 114, lt_reinicia  # 'r'
    beq  $t1, 113, lt_sair      # 'q'
    j    lt_nada

lt_direcao:
    sub  $t3, $zero, $s2        # proibe virar 180 graus (entrar no pescoco)
    beq  $t2, $t3, lt_nada
    move $s2, $t2
    li   $s6, 0                 # uma direcao tambem tira da pausa / inicia
    j    lt_nada
lt_pausa:
    xori $s6, $s6, 1
    beqz $s6, lt_nada
    li   $v0, 4
    la   $a0, msg_pausa
    syscall
    j    lt_nada
lt_reinicia:
    li   $v0, 2
    j    lt_ret
lt_sair:
    li   $v0, 1
    j    lt_ret
lt_nada:
    li   $v0, 0
lt_ret:
    lw   $ra, 0($sp)
    addi $sp, $sp, 4
    jr   $ra

###############################################################################
# sorteia_comida: escolhe uma casa livre aleatoria na area de jogo
#   x = 1 + rand(62)   y = 8 + rand(23)   (syscall 42)
# Se a casa nao estiver livre (cor != fundo), sorteia de novo.
###############################################################################
sorteia_comida:
sc_tenta:
    li   $v0, 42
    li   $a0, 0
    li   $a1, 62
    syscall
    addi $t0, $a0, 1            # t0 = x
    li   $v0, 42
    li   $a0, 0
    li   $a1, 23
    syscall
    addi $t1, $a0, 8            # t1 = y
    sll  $t1, $t1, ROW_SHIFT
    add  $t0, $t0, $t1          # posicao
    sll  $t0, $t0, 2
    li   $t1, BITMAP
    add  $t0, $t0, $t1
    lw   $t2, 0($t0)
    li   $t3, COR_FUNDO
    bne  $t2, $t3, sc_tenta
    li   $t3, COR_COMIDA
    sw   $t3, 0($t0)
    jr   $ra

###############################################################################
# pinta_cobra_morta: percorre o buffer circular da cauda ate a cabeca
# pintando cada segmento de vermelho escuro.
###############################################################################
pinta_cobra_morta:
    move $t0, $s1
    la   $t1, corpo
    li   $t2, BITMAP
    li   $t3, COR_MORTA
pm_loop:
    sll  $t4, $t0, 1
    add  $t4, $t4, $t1
    lhu  $t5, 0($t4)
    sll  $t5, $t5, 2
    add  $t5, $t5, $t2
    sw   $t3, 0($t5)
    beq  $t0, $s0, pm_fim
    addi $t0, $t0, 1
    andi $t0, $t0, BUF_MASK
    j    pm_loop
pm_fim:
    jr   $ra

###############################################################################
# desenha_placar: pontos (branco, esquerda) e recorde (dourado, direita)
###############################################################################
desenha_placar:
    addi $sp, $sp, -4
    sw   $ra, 0($sp)
    move $a0, $s4
    li   $a1, 2
    li   $a2, 1
    li   $a3, COR_PLACAR
    jal  desenha_numero
    lw   $a0, recorde
    li   $a1, 47
    li   $a2, 1
    li   $a3, COR_RECORDE
    jal  desenha_numero
    lw   $ra, 0($sp)
    addi $sp, $sp, 4
    jr   $ra

###############################################################################
# desenha_numero: desenha $a0 com 4 digitos na posicao ($a1,$a2), cor $a3.
# Extrai os digitos da direita para a esquerda (resto da divisao por 10).
# Usa a pilha para preservar valor/coluna/contador entre as chamadas.
###############################################################################
desenha_numero:
    addi $sp, $sp, -16
    sw   $ra, 0($sp)
    sw   $s0, 4($sp)
    sw   $s1, 8($sp)
    sw   $s2, 12($sp)

    move $s0, $a0               # s0 = valor restante
    addi $s1, $a1, 12           # s1 = coluna do digito das unidades
    li   $s2, 4                 # s2 = digitos restantes
dn_loop:
    li   $t0, 10
    divu $s0, $t0
    mfhi $a0                    # a0 = digito (resto)
    mflo $s0                    # s0 = valor / 10
    move $a1, $s1
    jal  desenha_digito         # a2 (y) e a3 (cor) nao sao alterados
    addi $s1, $s1, -4
    addi $s2, $s2, -1
    bgtz $s2, dn_loop

    lw   $ra, 0($sp)
    lw   $s0, 4($sp)
    lw   $s1, 8($sp)
    lw   $s2, 12($sp)
    addi $sp, $sp, 16
    jr   $ra

###############################################################################
# desenha_digito: digito $a0 (0..9) com fonte 3x5 em ($a1,$a2), cor $a3.
# Testa os 15 bits da mascara com SRLV + ANDI.
###############################################################################
desenha_digito:
    la   $t0, fonte
    sll  $t1, $a0, 2
    add  $t0, $t0, $t1
    lw   $t0, 0($t0)            # t0 = mascara de 15 bits
    li   $t1, 14                # t1 = bit atual
    li   $t2, 0                 # t2 = linha (0..4)
dd_linha:
    li   $t3, 0                 # t3 = coluna (0..2)
dd_coluna:
    srlv $t4, $t0, $t1
    andi $t4, $t4, 1
    li   $t5, COR_HUD
    beqz $t4, dd_pinta
    move $t5, $a3
dd_pinta:
    add  $t6, $a2, $t2          # y + linha
    sll  $t6, $t6, ROW_SHIFT
    add  $t6, $t6, $a1          # + x
    add  $t6, $t6, $t3          # + coluna
    sll  $t6, $t6, 2
    li   $t7, BITMAP
    add  $t6, $t6, $t7
    sw   $t5, 0($t6)
    addi $t1, $t1, -1
    addi $t3, $t3, 1
    blt  $t3, 3, dd_coluna
    addi $t2, $t2, 1
    blt  $t2, 5, dd_linha
    jr   $ra

###############################################################################
# imprime_placar: mostra pontos, recorde e velocidade no console Run I/O
###############################################################################
imprime_placar:
    li   $v0, 4
    la   $a0, msg_pontos
    syscall
    li   $v0, 1
    move $a0, $s4
    syscall
    li   $v0, 4
    la   $a0, msg_rec
    syscall
    li   $v0, 1
    lw   $a0, recorde
    syscall
    li   $v0, 4
    la   $a0, msg_vel
    syscall
    li   $v0, 1
    move $a0, $s5
    syscall
    li   $v0, 4
    la   $a0, msg_nl
    syscall
    jr   $ra
