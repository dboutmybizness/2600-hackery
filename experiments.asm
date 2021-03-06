
  processor 6502
  include "vcs.h"
  include "macro.h"

schedule = #$ff
PF_REFL        = $1  ; mirror playfield
PF_DUP         = $0  ; repeat playfield
TIMER_VBLANK   = $2a ;  ~2688 cycles
TIMER_SCREEN   = $13 ; ~77824 cycles
TIMER_OVERSCAN = $14 ;  ~1280 cycles

  seg.u vars
  org $80

scanline .word 0
xoff .word 20
yoff .word 20
sprite .word      ; pointer to player sprite

  seg code
  org $f000

fencer_high:
  .byte %10110001  ;X XX   X;
  .byte %10110010  ;X XX  X ;
  .byte %10100100  ;X X  X  ;
  .byte %01111000  ; XXXX   ;
  .byte %00110000  ;  XX    ;
  .byte %00110000  ;  XX    ;
  .byte %00110000  ;  XX    ;
  .byte %00110000  ;  XX    ;
  .byte %00111000  ;  XXX   ;
  .byte %00111100  ;  XXXX  ;
  .byte %00110110  ;  XX XX ;
  .byte %00110010  ;  XX  X ;
  .byte %00100110  ;  X  XX ;
  .byte %00100100  ;  X  X  ;
fencer_mid:
  .byte %10110000  ;X XX    ;
  .byte %10110000  ;X XX    ;
  .byte %10100000  ;X X     ;
  .byte %01110000  ; XXX    ;
  .byte %00111001  ;  XXX  X;
  .byte %00110110  ;  XX XX ;
  .byte %00110000  ;  XX    ;
  .byte %00110000  ;  XX    ;
  .byte %00111000  ;  XXX   ;
  .byte %00111100  ;  XXXX  ;
  .byte %00110110  ;  XX XX ;
  .byte %00110010  ;  XX  X ;
  .byte %00100110  ;  X  XX ;
  .byte %00100100  ;  X  X  ;
fencer_low:
  .byte %10110000  ;X XX    ;
  .byte %10110000  ;X XX    ;
  .byte %10100000  ;X X     ;
  .byte %01110000  ; XXX    ;
  .byte %00111000  ;  XXX   ;
  .byte %00110100  ;  XX X  ;
  .byte %00110010  ;  XX  X ;
  .byte %00110001  ;  XX   X;
  .byte %00111000  ;  XXX   ;
  .byte %00111100  ;  XXXX  ;
  .byte %00110110  ;  XX XX ;
  .byte %00110010  ;  XX  X ;
  .byte %00100110  ;  X  XX ;
  .byte %00100100  ;  X  X  ;

reset:
  sei              ; interrupts
  cld              ; decimal mode
  ldx #$ff
  txs              ; stack
  lda #0
  ldx #0
memclear:
  sta 0,x
  inx
  bne memclear

  ; set controller DDR as input
  lda #$00
  sta SWACNT
  
  ; initialize y offset
  lda #191
  sta yoff

  ; playfield setup
  lda #$84
  sta COLUBK
  lda #$2e
  sta COLUP0
  ; set up sprite pointer
  lda #<fencer_low
  sta sprite
  lda #>fencer_low
  sta sprite+1

  lda PF_REFL
  sta CTRLPF

  ;//////
.new_frame:

  ; VSYNC! 1, 2, 3!
  lda #2
  sta VSYNC
  sta WSYNC
  sta WSYNC
  sta WSYNC
  
  ; set timer for the end of VBLANK
  ; TIM64T ticks once every 64 cycles
  ; VBLANK is 37 scan lines, 76 cycles (228 color cycles) per scan line
  ;
  ; 37*76 = 2812
  ;
  ; But we need to take into account the loop itself takes about 6 cycles, 
  ; setting the timer takes 5, and setting WSYNC 3.
  ; => Wait for 2812 - 6 - 5 - 3 = 2798 / 63 => 43 timer ticks, then set WSYNC
  lda #43
  sta TIM64T
  
  ; unset VSYNC here so we don't need to subtract another number from the timer count ;)
  lda #0
  sta VSYNC
  

  
  

  ; read controller status
  lda #%10000000
  bit SWCHA
  bne .notright
  inc xoff
.notright:
  lda #%01000000
  bit SWCHA
  bne .notleft
  dec xoff
.notleft:
  lda #%00100000
  bit SWCHA
  bne .notdown
  lda yoff
  cmp #14
  beq .notdown ; don't move past the lower edge of the screen
  dec yoff
.notdown:
  lda #%00010000
  bit SWCHA
  bne .notup
  lda yoff
  cmp #191
  beq .notup ; don't move past the upper edge of the screen (into vblank territory)
  inc yoff
.notup:

; hack to get around 16-bit operations
; extremely wasteful
  sta WSYNC
  sta WSYNC
  sta WSYNC
  sta WSYNC

; Twiddle thumbs until end of VBLANK period
CheckVblankEnd
  lda INTIM
  bne CheckVblankEnd
  
  
  ldy #0   ; lines of player sprite drawn
  ldx #191 ; 191 scan lines until overscan
  stx scanline
  
  ; WSYNC the final line of VBLANK, then set VBLANK to 0 (accumulator is 0 because the bne above wasn't taken)
  sta WSYNC
  sta RESP0
  sta VBLANK
  
.line_loop:

;  ldx xoff
.sleeploop:
;    SLEEP 20
;    dex
;    cpx #0
;  bmi .sleeploop

  ldx scanline

  ;draw player
  cpx yoff ; compare current scanline to yoff
;            will set N, Z and C status bits as per http://www.6502.org/tutorials/compare_instructions.html
  beq .check_lines_drawn
  bcs .noplayer ; if carry is set, x (the current scanline) is greater than (or equal to, but the last line took care of that)
;                 yoff, so don't draw player sprite yet
.check_lines_drawn:
  cpy #15
  bcs .noplayer ; carry set means Y >= 15 => Y > 14 (i.e. we've already drawn all 14 lines of player sprite)
  ; we have to draw a sprite
  lda (<sprite),y
  iny
  sta GRP0
  jmp .player_done
.noplayer:
  lda #0
  sta GRP0
.player_done:
  dex ; count down lines until overscan
  stx scanline
  sta WSYNC

  cpx #0
  bne .line_loop
  lda #2


  sta WSYNC
  sta VBLANK
  ldx #30
  lda #0
  sta GRP0
Wait_Overscan
  sta WSYNC
  dex
  bne Wait_Overscan
  
  
  jmp .new_frame
  ;//////


  org $fffa

irqvec:
  .word reset  ; NMI
  .word reset  ; RESET
  .word reset  ; IRQ

