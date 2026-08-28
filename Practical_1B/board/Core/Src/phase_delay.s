/*
 * Practical 1B, Task 4
 */

    .syntax unified
    .cpu cortex-m0
    .thumb

    @ Peripheral addresses, taken from the memory map in RM0091. Writing them
    @ out here keeps the code below free of magic numbers.
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

    .equ DELAY_ITERS,   250          @ from the derivation above, 4 cycles each

    .global phase_delay_run
    .type phase_delay_run, %function

phase_delay_run:
    push    {r4, r5, lr}

    @ Turn on the clocks for both GPIO ports. Bit 17 is port A and bit 18 is
    @ port B, so 0x60000 covers the pair.
    ldr     r0, =RCC_BASE
    ldr     r1, [r0, #RCC_AHBENR]
    ldr     r2, =0x00060000
    orrs    r1, r1, r2
    str     r1, [r0, #RCC_AHBENR]

    @ The ADC sits on APB2 and the DAC sits on APB1, so they are enabled in
    @ two different registers.
    ldr     r1, [r0, #RCC_APB2ENR]
    movs    r2, #1
    lsls    r2, r2, #9              @ bit 9 is ADCEN
    orrs    r1, r1, r2
    str     r1, [r0, #RCC_APB2ENR]

    ldr     r1, [r0, #RCC_APB1ENR]
    movs    r2, #1
    lsls    r2, r2, #29             @ bit 29 is DACEN
    orrs    r1, r1, r2
    str     r1, [r0, #RCC_APB1ENR]

    @ PA4 has to be in analog mode before the DAC can drive it. Its MODER
    @ field is bits 9 and 8, and analog is both bits set.
    ldr     r0, =GPIOA_BASE
    ldr     r1, [r0, #GPIO_MODER]
    ldr     r2, =0x00000300
    orrs    r1, r1, r2
    str     r1, [r0, #GPIO_MODER]

    @ Same for PB0, which is the ADC input. Its field is the bottom two bits.
    @ Leaving the pin as a digital input would clamp the signal and load the
    @ source with the input protection.
    ldr     r0, =GPIOB_BASE
    ldr     r1, [r0, #GPIO_MODER]
    movs    r2, #3
    orrs    r1, r1, r2
    str     r1, [r0, #GPIO_MODER]

    ldr     r0, =ADC1_BASE

    @ Clock the ADC from PCLK divided by two. CKMODE is the top two bits of
    @ CFGR2 and 01 selects that mode.
    ldr     r1, =0x40000000
    str     r1, [r0, #ADC_CFGR2]

    @ Calibration only works while the ADC is still disabled, so it happens
    @ before ADEN is ever set. Skipping it leaves an offset error on every
    @ conversion, which shows up as the output sitting off the input.
    ldr     r1, =ADC_CR_ADCAL
    str     r1, [r0, #ADC_CR]
1:  ldr     r1, [r0, #ADC_CR]
    ldr     r2, =ADC_CR_ADCAL
    tst     r1, r2
    bne     1b                      @ the hardware clears ADCAL when it is done

    @ All zeros in CFGR1 means single conversion, twelve bits, right aligned,
    @ no trigger and no continuous mode, which is exactly what the loop wants
    @ because it starts each conversion itself.
    movs    r1, #0
    str     r1, [r0, #ADC_CFGR1]

    @ Shortest sampling time the ADC offers, one and a half clocks. The source
    @ is a signal generator with a low output impedance so there is no reason
    @ to hold the sampling switch closed any longer.
    str     r1, [r0, #ADC_SMPR]

    @ PB0 is channel 8, so bit 8 of CHSELR.
    movs    r1, #1
    lsls    r1, r1, #8
    str     r1, [r0, #ADC_CHSELR]

    @ Enable the ADC and wait for it to say it is ready. Starting a conversion
    @ before ADRDY comes up gives a garbage first sample.
    movs    r1, #ADC_CR_ADEN
    str     r1, [r0, #ADC_CR]
2:  ldr     r1, [r0, #ADC_ISR]
    movs    r2, #ADC_ISR_ADRDY
    tst     r1, r2
    beq     2b

    @ Enable DAC channel 1 with its output buffer on and no external trigger,
    @ so a write to the data register reaches the pin by itself.
    ldr     r1, =DAC_BASE
    movs    r2, #1
    str     r2, [r1, #DAC_CR]

    @ From here on r0 holds the ADC base and r1 holds the DAC base. Keeping
    @ both in registers means the timed loop never has to reload an address,
    @ which would add cycles the budget does not account for.
    movs    r4, #ADC_CR_ADSTART

sample_loop:
    str     r4, [r0, #ADC_CR]       @ 2  start a conversion, sample closes about 3 cycles later
    movs    r2, #DELAY_ITERS        @ 1  load the pass count
delay_loop:
    subs    r2, r2, #1              @ 1  once per pass
    bne     delay_loop              @ 3 when taken, 1 on the final pass
    ldr     r3, [r0, #ADC_DR]       @ 2  conversion finished long ago, this read also clears EOC
    str     r3, [r1, #DAC_DHR12R1]  @ 2  the value reaches the pin one APB1 clock later
    b       sample_loop             @ 3  round again

    .size phase_delay_run, .-phase_delay_run
