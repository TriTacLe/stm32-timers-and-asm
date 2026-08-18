/*
 * Practical 1B, Task 4
 * ADC on PB0 (channel 8) copied to DAC1 on PA4, with a cycle counted delay
 * that puts the output 45 degrees behind a 1 kHz input.
 *
 * Clock assumptions: HSI 8 MHz, no PLL, so one CPU cycle is 125 ns.
 * The ADC runs from PCLK/2 = 4 MHz (CFGR2 CKMODE = 01) so the conversion
 * time is fixed to the same clock the cycle count is derived from.
 *
 *   T     = 1 / 1000 Hz            = 1 ms
 *   dt    = (45 / 360) * 1 ms      = 125 us
 *   cycles = 125 us / 125 ns       = 1000 cycles
 *
 * Cortex-M0 cycle costs used below (ARMv6-M):
 *   MOVS/SUBS/NOP  1
 *   LDR/STR        2
 *   B / BNE        3 when taken, 1 when it falls through
 *
 * Budget from the sample instant to the DAC write:
 *   the sample and hold closes about 1.5 ADC clocks (3 CPU cycles) after
 *   ADSTART is written, so the path that has to add up to 1000 cycles is
 *
 *     MOVS  r2, #DELAY_ITERS        1
 *     delay loop, N iterations      4N - 2      (4 per pass, last pass 2)
 *     LDR   r3, [ADC, #DR]          2
 *     STR   r3, [DAC, #DHR12R1]     2
 *                                  ----
 *     total                         4N + 3
 *
 *   4N + 3 = 1000 + 3  ->  N = 250
 *
 * One delay iteration is 4 cycles, so DELAY_ITERS moves the output by 500 ns
 * per step when the measured phase needs trimming at the bench.
 */

@ ---
    .syntax unified
    .cpu cortex-m0
    .thumb

    .equ RCC_BASE,      0x40021000
    .equ RCC_AHBENR,    0x14
    .equ RCC_APB1ENR,   0x1C
    .equ RCC_APB2ENR,   0x18

    .equ GPIOA_BASE,    0x48000000
    .equ GPIOB_BASE,    0x48000400
    .equ GPIO_MODER,    0x00

    .equ ADC1_BASE,     0x40012400
    .equ ADC_ISR,       0x00
    .equ ADC_CR,        0x08
    .equ ADC_CFGR1,     0x0C
    .equ ADC_CFGR2,     0x10
    .equ ADC_SMPR,      0x14
    .equ ADC_CHSELR,    0x28
    .equ ADC_DR,        0x40

    .equ DAC_BASE,      0x40007400
    .equ DAC_CR,        0x00
    .equ DAC_DHR12R1,   0x08

    .equ ADC_CR_ADEN,   0x00000001
    .equ ADC_CR_ADSTART,0x00000004
    .equ ADC_CR_ADCAL,  0x80000000
    .equ ADC_ISR_ADRDY, 0x00000001

    .equ DELAY_ITERS,   250          @ derived above, 4 cycles each

    .global phase_delay_run
    .type phase_delay_run, %function

phase_delay_run:
    push    {r4, r5, lr}

    @ GPIOA and GPIOB clocks
    ldr     r0, =RCC_BASE
    ldr     r1, [r0, #RCC_AHBENR]
    ldr     r2, =0x00060000         @ GPIOAEN bit 17, GPIOBEN bit 18
    orrs    r1, r1, r2
    str     r1, [r0, #RCC_AHBENR]

    @ ADC clock on APB2, DAC clock on APB1
    ldr     r1, [r0, #RCC_APB2ENR]
    movs    r2, #1
    lsls    r2, r2, #9              @ ADCEN
    orrs    r1, r1, r2
    str     r1, [r0, #RCC_APB2ENR]

    ldr     r1, [r0, #RCC_APB1ENR]
    movs    r2, #1
    lsls    r2, r2, #29             @ DACEN
    orrs    r1, r1, r2
    str     r1, [r0, #RCC_APB1ENR]

    @ PA4 analog mode, MODER bits 9:8 set to 11
    ldr     r0, =GPIOA_BASE
    ldr     r1, [r0, #GPIO_MODER]
    ldr     r2, =0x00000300
    orrs    r1, r1, r2
    str     r1, [r0, #GPIO_MODER]

    @ PB0 analog mode, MODER bits 1:0 set to 11
    ldr     r0, =GPIOB_BASE
    ldr     r1, [r0, #GPIO_MODER]
    movs    r2, #3
    orrs    r1, r1, r2
    str     r1, [r0, #GPIO_MODER]

    ldr     r0, =ADC1_BASE

    @ ADC clock source PCLK/2 so conversion time follows the system clock
    ldr     r1, =0x40000000         @ CKMODE = 01
    str     r1, [r0, #ADC_CFGR2]

    @ calibrate while the ADC is still disabled
    ldr     r1, =ADC_CR_ADCAL
    str     r1, [r0, #ADC_CR]
1:  ldr     r1, [r0, #ADC_CR]
    ldr     r2, =ADC_CR_ADCAL
    tst     r1, r2
    bne     1b                      @ ADCAL clears when calibration ends

    @ single conversion, 12 bit, right aligned, shortest sampling time
    movs    r1, #0
    str     r1, [r0, #ADC_CFGR1]
    str     r1, [r0, #ADC_SMPR]     @ 1.5 ADC clocks

    movs    r1, #1
    lsls    r1, r1, #8              @ channel 8 is PB0
    str     r1, [r0, #ADC_CHSELR]

    movs    r1, #ADC_CR_ADEN
    str     r1, [r0, #ADC_CR]
2:  ldr     r1, [r0, #ADC_ISR]
    movs    r2, #ADC_ISR_ADRDY
    tst     r1, r2
    beq     2b

    @ DAC channel 1 on, output buffer enabled, no external trigger
    ldr     r1, =DAC_BASE
    movs    r2, #1
    str     r2, [r1, #DAC_CR]

    @ r0 holds the ADC base and r1 the DAC base for the whole timed loop
    movs    r4, #ADC_CR_ADSTART

sample_loop:
    str     r4, [r0, #ADC_CR]       @ 2  start one conversion, sample closes ~3 cycles later
    movs    r2, #DELAY_ITERS        @ 1
delay_loop:
    subs    r2, r2, #1              @ 1  x N
    bne     delay_loop              @ 3 taken, 1 on the last pass
    ldr     r3, [r0, #ADC_DR]       @ 2  conversion long finished, reading clears EOC
    str     r3, [r1, #DAC_DHR12R1]  @ 2  DHR to DOR takes one APB1 clock, no trigger needed
    b       sample_loop             @ 3

    .size phase_delay_run, .-phase_delay_run
@ ---
