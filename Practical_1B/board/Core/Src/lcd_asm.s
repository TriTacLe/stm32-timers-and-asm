/*
 * Practical 1B, Task 5
 *
 * What this file does. It brings the WC1602A character panel up in four bit
 * mode by bit banging, entirely in assembly, and puts the letter A in the
 * first column. The panel is an HD44780 compatible controller.
 *
 * Pins, from the board pinout
 *   Enable is PC15, which reaches the panel as PC15_S after level shifter 1
 *   Register select is PC14, which reaches it as PC14_S after shifter 2
 *   The four data lines are PB8, PB9, PA12 and PA15, carrying D4 to D7
 *
 * Read and write is tied low on the board, so the panel can only be written
 * to and the busy flag can never be read back. Every wait in this file is a
 * counted delay rather than a poll, and each one is sized from the timing
 * table in the HD44780 datasheet.
 *
 * The clock is the 8 MHz internal RC oscillator, so one cycle is 125 ns.
 *
 * Why the enable pulse needs padding. Each level shifter pulls its 5 V side
 * down actively but lets it come back up through a 1.8 kOhm pullup. The line
 * therefore rises as an RC curve rather than as an edge, and the panel only
 * counts the line as high once it passes 3.5 V. All the time spent climbing
 * to that threshold is dead time, and it does not count towards the 450 ns
 * the controller wants the enable line held high.
 *
 * So the number of cycles the pulse needs is the rise time plus 450 ns,
 * divided by 125 ns and rounded up.
 *
 * E_HIGH_NOPS below is that number. Measured on the bench: 380 ns 10 to 90
 * percent rise on PC15_S, about 208 ns to reach 3.5 V, which rounds up to
 * 6 NOPs. 8 is kept as the tested value with two cycles of margin.
 *
 * The same rise time feeds the capacitance calculation, with R equal to
 * 1800 Ohm from the pullup, VCC equal to 5 V and the threshold at 3.5 V.
 * That works out to C equal to t divided by 2167.1.
 */

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

    .equ E_HIGH_NOPS,   8           @ derived floor is 6, see the note above

    .global lcd_init_asm
    .global lcd_show_A
    .type lcd_init_asm, %function
    .type lcd_show_A, %function

@ delay_iters
@ r0 holds the number of passes. Each pass is one SUBS and one taken
@ branch, so four cycles, and the last pass saves two because the
@ branch falls through.
delay_iters:
    subs    r0, r0, #1              @ 1
    bne     delay_iters             @ 3 when taken, 1 on the last pass
    bx      lr

/* At 8 MHz there are 8000 cycles in a millisecond, and each pass above is
   four cycles, so 2000 passes make roughly one millisecond. Close enough
   for power on waits, which only have lower bounds. */
delay_ms:
    push    {r0, r1, lr}
    ldr     r1, =2000
    muls    r0, r1, r0
    bl      delay_iters
    pop     {r0, r1, pc}

@ lcd_pins_init
@ Enable, register select and the four data lines become push pull
@ outputs. All six sit on three different ports, which is why this is
@ longer than it looks like it should be.
lcd_pins_init:
    push    {r4, lr}

    @ Clocks for ports A, B and C, which are bits 17, 18 and 19.
    ldr     r0, =RCC_BASE
    ldr     r1, [r0, #RCC_AHBENR]
    ldr     r2, =0x000E0000
    orrs    r1, r1, r2
    str     r1, [r0, #RCC_AHBENR]

    @ PA12 and PA15 to output. Their MODER fields are bits 25 and 24, and
    @ bits 31 and 30. Clear both fields first, then write 01 into each.
    ldr     r0, =GPIOA_BASE
    ldr     r1, [r0, #GPIO_MODER]
    ldr     r2, =0xC3000000
    bics    r1, r1, r2
    ldr     r2, =0x41000000
    orrs    r1, r1, r2
    str     r1, [r0, #GPIO_MODER]

    @ High speed on both, which keeps the 3V3 edge sharp. The slow part of
    @ the path is the level shifter, so there is no reason to add to it here.
    ldr     r1, [r0, #GPIO_OSPEEDR]
    ldr     r2, =0xC1000000
    orrs    r1, r1, r2
    str     r1, [r0, #GPIO_OSPEEDR]

    @ PB8 and PB9 to output, fields at bits 19 down to 16.
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

    @ PC14 and PC15 to output, fields at bits 31 down to 28.
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

    @ Both control lines start low, so no accidental enable pulse goes out
    @ while the data lines are still settling.
    ldr     r1, =(1 << PIN_E) | (1 << PIN_RS)
    str     r1, [r0, #GPIO_BRR]

    pop     {r4, pc}

@ lcd_put_nibble
@ r0 carries four bits in its bottom four, which go out on D7 to D4.
@
@ BSRR is written rather than the output register because it sets and
@ clears in one write and never disturbs the other pins on the port.
@ The bottom half sets a pin and the top half clears it, so the bits
@ that must go high shift up to their pin number and the bits that
@ must go low shift up by another sixteen on top of that.
@
@ D4 and D5 are PB8 and PB9, so the low pair shifts by 8, and the
@ inverted pair by 24. D6 is PA12 and D7 is PA15, which are further
@ apart, so those two bits are placed one at a time.
lcd_put_nibble:
    push    {r4, r5, lr}
    mov     r4, r0

    @ Port B half, pins 8 and 9.
    movs    r1, #3
    ands    r1, r1, r4
    lsls    r1, r1, #8              @ the bits that go high
    movs    r2, #3
    bics    r2, r2, r4              @ the bits that go low
    lsls    r2, r2, #24
    orrs    r1, r1, r2
    ldr     r0, =GPIOB_BASE
    str     r1, [r0, #GPIO_BSRR]

    @ Port A half, pins 12 and 15.
    movs    r1, #4
    ands    r1, r1, r4
    lsls    r1, r1, #10             @ bit 2 of the nibble lands on pin 12
    movs    r2, #8
    ands    r2, r2, r4
    lsls    r2, r2, #12             @ bit 3 lands on pin 15
    orrs    r1, r1, r2
    movs    r2, #4
    bics    r2, r2, r4
    lsls    r2, r2, #26             @ clearing pin 12
    orrs    r1, r1, r2
    movs    r2, #8
    bics    r2, r2, r4
    lsls    r2, r2, #28             @ clearing pin 15
    orrs    r1, r1, r2
    ldr     r0, =GPIOA_BASE
    str     r1, [r0, #GPIO_BSRR]

    pop     {r4, r5, pc}

@ lcd_pulse_e
@ Raise enable, hold it, drop it. The panel reads the data lines on
@ the falling edge.
@
@ The block of NOPs is the whole point of Task 5. The 3V3 side of the
@ line switches in a few nanoseconds, but the 5 V side has to climb
@ through its pullup, and only the time it spends above 3.5 V counts
@ towards the 450 ns the panel needs.
lcd_pulse_e:
    push    {r0, r1, lr}
    ldr     r0, =GPIOC_BASE
    movs    r1, #1
    lsls    r1, r1, #PIN_E

    str     r1, [r0, #GPIO_BSRR]    @ 2  enable goes high and the 5 V side starts climbing
    .rept   E_HIGH_NOPS
    nop                             @ 1 each, holding the line while it is valid
    .endr
    str     r1, [r0, #GPIO_BRR]     @ 2  enable drops and the panel latches here

    @ The datasheet also asks for a full enable cycle time of 1000 ns, so the
    @ line has to stay low for a while before the next pulse.
    .rept   8
    nop
    .endr
    pop     {r0, r1, pc}

@ lcd_write
@ r0 carries the byte and r1 says what kind it is. Zero means a
@ command and one means a character.
@
@ In four bit mode a byte goes out as two pulses, high half first.
lcd_write:
    push    {r4, r5, lr}
    mov     r4, r0
    mov     r5, r1

    @ Register select picks between the command register and the data
    @ register, and it has to be settled before the first enable pulse.
    ldr     r0, =GPIOC_BASE
    movs    r1, #1
    lsls    r1, r1, #PIN_RS
    cmp     r5, #0
    beq     1f
    str     r1, [r0, #GPIO_BSRR]    @ character, so register select goes high
    b       2f
1:  str     r1, [r0, #GPIO_BRR]     @ command, so it stays low
2:

    lsrs    r0, r4, #4              @ high half first
    bl      lcd_put_nibble
    bl      lcd_pulse_e

    movs    r0, #0x0F
    ands    r0, r0, r4              @ then the low half
    bl      lcd_put_nibble
    bl      lcd_pulse_e

    @ Most instructions take 37 us to finish inside the controller, and there
    @ is no busy flag to watch, so wait a bit longer than that and move on.
    movs    r0, #80
    bl      delay_iters

    pop     {r4, r5, pc}

@ lcd_init_asm
@ The power on sequence from the HD44780 datasheet. It looks strange
@ because the controller starts in eight bit mode and has to be talked
@ into four bit mode using single nibbles.
lcd_init_asm:
    push    {r4, lr}
    bl      lcd_pins_init

    @ The panel needs more than 40 ms after power comes up before it will
    @ accept anything. 50 ms leaves room for a slow supply rise.
    movs    r0, #50
    bl      delay_ms

    @ Three nibbles of 0x3, each with its own wait. Whatever state the
    @ controller powered up in, this puts it in a known eight bit state.
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

    @ Now 0x2 switches it to four bit mode. From here on every byte goes out
    @ as two nibbles.
    movs    r0, #2
    bl      lcd_put_nibble
    bl      lcd_pulse_e
    movs    r0, #1
    bl      delay_ms

    movs    r0, #0x28               @ four bit bus, two lines, 5 by 8 font
    movs    r1, #0
    bl      lcd_write

    movs    r0, #0x08               @ display off while the rest is set up
    movs    r1, #0
    bl      lcd_write

    movs    r0, #0x01               @ clear the display
    movs    r1, #0
    bl      lcd_write
    movs    r0, #2                  @ clearing takes 1.52 ms, far longer than a normal command
    bl      delay_ms

    movs    r0, #0x06               @ after each character the cursor moves right and the display stays put
    movs    r1, #0
    bl      lcd_write

    movs    r0, #0x0C               @ display on, cursor hidden
    movs    r1, #0
    bl      lcd_write

    pop     {r4, pc}
    .size lcd_init_asm, .-lcd_init_asm

@ lcd_show_A
@ Put the cursor at the first column of the first line and write A.
lcd_show_A:
    push    {r4, lr}
    movs    r0, #0x80               @ set the display address to 0, the top left cell
    movs    r1, #0
    bl      lcd_write

    movs    r0, #0x41               @ the character code for A
    movs    r1, #1
    bl      lcd_write
    pop     {r4, pc}
    .size lcd_show_A, .-lcd_show_A
