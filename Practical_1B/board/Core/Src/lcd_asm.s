/*
 * Practical 1B, Task 5
 * HD44780 (WC1602A) driven by bit banging in 4-bit mode, written in assembly.
 *
 *   E   PC15  ->  PC15_S through NMOS level shifter 1
 *   RS  PC14  ->  PC14_S through NMOS level shifter 2
 *   D4  PB8   D5  PB9   D6  PA12   D7  PA15
 *
 * R/W is tied low on the board, so the panel is write only and the busy flag
 * cannot be read. Every wait below is a timed delay.
 *
 * Clock assumption: HSI 8 MHz, no PLL, one CPU cycle is 125 ns.
 *
 * Why the enable pulse needs padding:
 * each shifter pulls its 5 V side low actively but releases it high through a
 * 1.8 kOhm pullup, so PC15_S rises as an RC curve into the trace capacitance.
 * The panel only sees a logic high above 3.5 V, so the time the pin spends
 * climbing is dead time that does not count towards the 450 ns the HD44780
 * needs on E.
 *
 *   cycles = ceil( (t_rise + 450 ns) / 125 ns )
 *
 * t_rise is the 0 V to 3.5 V time measured on PC15_S with the scope.
 * E_HIGH_NOPS below is that count. It is a starting value, not a measurement:
 * substitute the measured t_rise, redo the division, and set it before the
 * demo. Each NOP moves the high time by 125 ns.
 *
 * The same measurement feeds the capacitance calculation, with R = 1800 Ohm
 * from the shifter pullup, VCC = 5 V and VC = 3.5 V:
 *
 *   C = -t / ( R * ln(1 - VC/VCC) ) = t / (1800 * 1.20397) = t / 2167.1
 */

@ ---
    .syntax unified
    .cpu cortex-m0
    .thumb

    .equ RCC_BASE,      0x40021000
    .equ RCC_AHBENR,    0x14

    .equ GPIOA_BASE,    0x48000000
    .equ GPIOB_BASE,    0x48000400
    .equ GPIOC_BASE,    0x48000800
    .equ GPIO_MODER,    0x00
    .equ GPIO_OSPEEDR,  0x08
    .equ GPIO_BSRR,     0x18
    .equ GPIO_BRR,      0x28

    .equ PIN_E,         15          @ PC15
    .equ PIN_RS,        14          @ PC14

    .equ E_HIGH_NOPS,   8           @ see the derivation above, retune from t_rise

    .global lcd_init_asm
    .global lcd_show_A
    .type lcd_init_asm, %function
    .type lcd_show_A, %function

/* ------------------------------------------------------------------ */
/* r0 = number of iterations, 4 cycles each, 4N - 2 cycles in total    */
/* ------------------------------------------------------------------ */
delay_iters:
    subs    r0, r0, #1              @ 1
    bne     delay_iters             @ 3 taken, 1 on the last pass
    bx      lr

/* 8 MHz gives 8000 cycles per ms, so 2000 delay iterations per ms */
delay_ms:
    push    {r0, r1, lr}
    ldr     r1, =2000
    muls    r0, r1, r0
    bl      delay_iters
    pop     {r0, r1, pc}

/* ------------------------------------------------------------------ */
/* lcd_pins_init: E, RS and the four data lines as push pull outputs   */
/* ------------------------------------------------------------------ */
lcd_pins_init:
    push    {r4, lr}

    ldr     r0, =RCC_BASE
    ldr     r1, [r0, #RCC_AHBENR]
    ldr     r2, =0x000E0000         @ GPIOAEN 17, GPIOBEN 18, GPIOCEN 19
    orrs    r1, r1, r2
    str     r1, [r0, #RCC_AHBENR]

    @ PA12 and PA15 to output, MODER bits 25:24 and 31:30 set to 01
    ldr     r0, =GPIOA_BASE
    ldr     r1, [r0, #GPIO_MODER]
    ldr     r2, =0xC3000000         @ clear both fields
    bics    r1, r1, r2
    ldr     r2, =0x41000000         @ 01 in each
    orrs    r1, r1, r2
    str     r1, [r0, #GPIO_MODER]
    ldr     r1, [r0, #GPIO_OSPEEDR]
    ldr     r2, =0xC1000000         @ high speed on both, keeps the 3V3 edge sharp
    orrs    r1, r1, r2
    str     r1, [r0, #GPIO_OSPEEDR]

    @ PB8 and PB9 to output, MODER bits 19:16
    ldr     r0, =GPIOB_BASE
    ldr     r1, [r0, #GPIO_MODER]
    ldr     r2, =0x000F0000
    bics    r1, r1, r2
    ldr     r2, =0x00050000
    orrs    r1, r1, r2
    str     r1, [r0, #GPIO_MODER]
    ldr     r1, [r0, #GPIO_OSPEEDR]
    ldr     r2, =0x000F0000
    orrs    r1, r1, r2
    str     r1, [r0, #GPIO_OSPEEDR]

    @ PC14 and PC15 to output, MODER bits 31:28
    ldr     r0, =GPIOC_BASE
    ldr     r1, [r0, #GPIO_MODER]
    ldr     r2, =0xF0000000
    bics    r1, r1, r2
    ldr     r2, =0x50000000
    orrs    r1, r1, r2
    str     r1, [r0, #GPIO_MODER]
    ldr     r1, [r0, #GPIO_OSPEEDR]
    ldr     r2, =0xF0000000
    orrs    r1, r1, r2
    str     r1, [r0, #GPIO_OSPEEDR]

    @ E and RS start low
    ldr     r1, =(1 << PIN_E) | (1 << PIN_RS)
    str     r1, [r0, #GPIO_BRR]

    pop     {r4, pc}

/* ------------------------------------------------------------------ */
/* lcd_put_nibble: r0 = nibble in bits 3:0, placed on D7..D4          */
/*                                                                    */
/* D4 and D5 are PB8 and PB9, so the low two bits shift up by 8 and    */
/* the inverted pair shifts up by 24 to land in the BSRR reset half.   */
/* D6 is PA12 and D7 is PA15, so those two bits move by 10 and 12.     */
/* ------------------------------------------------------------------ */
lcd_put_nibble:
    push    {r4, r5, lr}
    mov     r4, r0

    @ GPIOB half, pins 8 and 9
    movs    r1, #3
    ands    r1, r1, r4
    lsls    r1, r1, #8              @ set bits
    movs    r2, #3
    bics    r2, r2, r4              @ bits that must go low
    lsls    r2, r2, #24             @ reset half of BSRR
    orrs    r1, r1, r2
    ldr     r0, =GPIOB_BASE
    str     r1, [r0, #GPIO_BSRR]

    @ GPIOA half, pins 12 and 15
    movs    r1, #4
    ands    r1, r1, r4
    lsls    r1, r1, #10             @ bit 2 -> pin 12
    movs    r2, #8
    ands    r2, r2, r4
    lsls    r2, r2, #12             @ bit 3 -> pin 15
    orrs    r1, r1, r2
    movs    r2, #4
    bics    r2, r2, r4
    lsls    r2, r2, #26             @ pin 12 reset
    orrs    r1, r1, r2
    movs    r2, #8
    bics    r2, r2, r4
    lsls    r2, r2, #28             @ pin 15 reset
    orrs    r1, r1, r2
    ldr     r0, =GPIOA_BASE
    str     r1, [r0, #GPIO_BSRR]

    pop     {r4, r5, pc}

/* ------------------------------------------------------------------ */
/* lcd_pulse_e: raise E, hold it, drop it                             */
/*                                                                    */
/* The NOP block is the whole point of Task 5. The 3V3 side switches   */
/* in a few nanoseconds, the 5 V side needs t_rise to climb past       */
/* 3.5 V, and only the time after that counts towards the 450 ns the   */
/* panel requires.                                                     */
/* ------------------------------------------------------------------ */
lcd_pulse_e:
    push    {r0, r1, lr}
    ldr     r0, =GPIOC_BASE
    movs    r1, #1
    lsls    r1, r1, #PIN_E

    str     r1, [r0, #GPIO_BSRR]    @ 2  E high, PC15_S starts its RC climb
    .rept   E_HIGH_NOPS
    nop                             @ 1 each, holds E while the 5 V side is valid
    .endr
    str     r1, [r0, #GPIO_BRR]     @ 2  E low, the panel latches on this edge

    @ the HD44780 enable cycle time is 1000 ns, so keep E low a while too
    .rept   8
    nop
    .endr
    pop     {r0, r1, pc}

/* ------------------------------------------------------------------ */
/* lcd_write: r0 = byte, r1 = 0 for a command, 1 for data             */
/* ------------------------------------------------------------------ */
lcd_write:
    push    {r4, r5, lr}
    mov     r4, r0
    mov     r5, r1

    ldr     r0, =GPIOC_BASE
    movs    r1, #1
    lsls    r1, r1, #PIN_RS
    cmp     r5, #0
    beq     1f
    str     r1, [r0, #GPIO_BSRR]    @ data, RS high
    b       2f
1:  str     r1, [r0, #GPIO_BRR]     @ command, RS low
2:

    lsrs    r0, r4, #4              @ high nibble first
    bl      lcd_put_nibble
    bl      lcd_pulse_e

    movs    r0, #0x0F
    ands    r0, r0, r4              @ then the low nibble
    bl      lcd_put_nibble
    bl      lcd_pulse_e

    @ most instructions need 37 us, 40 us of margin costs nothing here
    movs    r0, #80
    bl      delay_iters

    pop     {r4, r5, pc}

/* ------------------------------------------------------------------ */
/* lcd_init_asm: the HD44780 power on sequence in 4-bit mode          */
/* ------------------------------------------------------------------ */
lcd_init_asm:
    push    {r4, lr}
    bl      lcd_pins_init

    movs    r0, #50                 @ panel needs more than 40 ms after power on
    bl      delay_ms

    @ three 0x3 nibbles put the controller into a known 8-bit state
    movs    r0, #3
    bl      lcd_put_nibble
    bl      lcd_pulse_e
    movs    r0, #5
    bl      delay_ms

    movs    r0, #3
    bl      lcd_put_nibble
    bl      lcd_pulse_e
    movs    r0, #1
    bl      delay_ms

    movs    r0, #3
    bl      lcd_put_nibble
    bl      lcd_pulse_e
    movs    r0, #1
    bl      delay_ms

    movs    r0, #2                  @ now switch to 4-bit
    bl      lcd_put_nibble
    bl      lcd_pulse_e
    movs    r0, #1
    bl      delay_ms

    movs    r0, #0x28               @ 4-bit, two lines, 5x8 font
    movs    r1, #0
    bl      lcd_write

    movs    r0, #0x08               @ display off while it is being set up
    movs    r1, #0
    bl      lcd_write

    movs    r0, #0x01               @ clear
    movs    r1, #0
    bl      lcd_write
    movs    r0, #2                  @ clear takes 1.52 ms
    bl      delay_ms

    movs    r0, #0x06               @ cursor moves right, no display shift
    movs    r1, #0
    bl      lcd_write

    movs    r0, #0x0C               @ display on, cursor off
    movs    r1, #0
    bl      lcd_write

    pop     {r4, pc}
    .size lcd_init_asm, .-lcd_init_asm

/* ------------------------------------------------------------------ */
/* lcd_show_A: put the cursor home and write the letter A             */
/* ------------------------------------------------------------------ */
lcd_show_A:
    push    {r4, lr}
    movs    r0, #0x80               @ DDRAM address 0, first column
    movs    r1, #0
    bl      lcd_write

    movs    r0, #0x41               @ 'A'
    movs    r1, #1
    bl      lcd_write
    pop     {r4, pc}
    .size lcd_show_A, .-lcd_show_A
@ ---
