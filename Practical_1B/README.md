# Practical 1B

[![Firmware](https://github.com/TriTacLe/EEE3095S-prac1/actions/workflows/firmware.yml/badge.svg)](https://github.com/TriTacLe/EEE3095S-prac1/actions/workflows/firmware.yml)
[![Report](https://github.com/TriTacLe/EEE3095S-prac1/actions/workflows/report.yml/badge.svg)](https://github.com/TriTacLe/EEE3095S-prac1/actions/workflows/report.yml)

Execution timing and cycle accurate assembly on the UCT Dev Board. Target is the
STM32F051C8, a Cortex M0 running from the 8 MHz internal RC oscillator with no
PLL, so one CPU cycle is 125 ns. Group 79, LXXTRI004 and SHRGIL004.

## The tasks

| Task | What it is | Where the code lives |
| --- | --- | --- |
| 1 | Integer square root on the PC, plus a timed golden measure | `Task1_PC/golden.c` |
| 2 | Same algorithm on the board, timed with TIM3 against the golden values | `board/Core/Src/main.c` |
| 3 | The Task 2 timing repeated at four optimisation levels | same file, rebuilt |
| 4 | ADC to DAC pass through delayed by 45 degrees, written in assembly | `board/Core/Src/phase_delay.s` |
| 5 | HD44780 LCD driven in 4 bit mode, written in assembly | `board/Core/Src/lcd_asm.s` |

`Task1_PC/verify_fast.c` is the cross check. It runs the board algorithm and the
golden side by side over every input up to a million, every perfect square
boundary, and twenty million scattered values.

## Building

Host side, Task 1:

    cd Task1_PC
    make run

Board side. `TASK` picks which image gets built, since one source tree covers
three separate programs:

    cd board
    make TASK=2               # timing and golden check, Tasks 2 and 3
    make TASK=4               # phase delay
    make TASK=5               # LCD

Optimisation level for the Task 3 table, and for the rebuild the demonstrator
asks for during the demo:

    make TASK=2 OPT=-O0 BUILD_DIR=build_O0
    make TASK=2 OPT=-O1 BUILD_DIR=build_O1
    make TASK=2 OPT=-O2 BUILD_DIR=build_O2
    make TASK=2 OPT=-Os BUILD_DIR=build_Os

Separate build directories keep the four images side by side, otherwise each
build overwrites the last. Flashing goes through `make flash`, which calls
`STM32_Programmer_CLI`. Set `STM32_PROG` to your own path if the tool sits
somewhere else.

## Pins

| Pin | Direction | What it does |
| --- | --- | --- |
| PC13 | output | Timing pin. Idles high, low while the timed function runs. Probe here for Tasks 2 and 3 |
| PB11 | output | Green LED. Lights when all ten golden values match |
| PB10 | output | Red LED. Lights when any of them do not |
| PB0 | analog in | ADC channel 8, the input signal for Task 4. Remove the POT0 jumper before feeding the signal generator in |
| PA4 | analog out | DAC channel 1, the delayed output for Task 4 |
| PB8, PB9, PA12, PA15 | output | LCD data lines D4 to D7 for Task 5, through the NMOS level shifters |
| PC14 | output | LCD register select for Task 5 |
| PC15 | output | LCD enable for Task 5. Probe here for the enable pulse width |

## Report

Source is `prac1B_lxxtri004_shrgil004.tex`, built with plain `pdflatex`, two
passes for the references. Screenshots go in `figures/` under the names the
`\scopefig` calls already use, and the figure appears as soon as the file is
there. Anything still unmeasured shows up in red in the PDF, both as `[BENCH]`
text and as an empty figure box, so nothing unfilled can be mistaken for a
result. The open measurement issues track what is left.

Submission is one PDF on Gradescope with the pages assigned to the questions.
