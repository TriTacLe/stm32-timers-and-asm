# Practical 1A

Timers, interrupts, debouncing, the ADC and software PWM on the UCT Dev Board.
Target is the STM32F051C8. Group 79, LXXTRI004 and SHRGIL004.

The practical is six tasks that build on each other, and each one replaced the
last in `Core/Src/main.c`. The snapshot of each is kept at the top level so the
earlier tasks can still be built and demonstrated.

| Task | What it does | Snapshot |
| --- | --- | --- |
| 1 | Blink LED0 on PB0 and measure the period on the scope | `main.c1` |
| 2 | Running light, one LED at a time from 0 to 7 and back, one step per second, driven by a timer interrupt | `main.c2` |
| 3 | Same running light, with PA0 switching the step between 1 s and 0.5 s, debounced | `main.c3` |
| 4 | Tasks 1 to 3 combined. Four buttons, three modes, speed toggle in every mode | `main.c4` |
| 5 | Read a DC voltage on PA5 and show it as a bar of LEDs on PB0 to PB7, registers only, no HAL | `main.c5` |
| 6 | Software PWM on PB4, 100 Hz at 30 percent duty, generated inside the timer ISR | `main.c6` |

To build an earlier task, copy its snapshot over `Core/Src/main.c` and rebuild.
`Core/Src/main.c` currently holds Task 6.

## Building

The project came from STM32CubeIDE and builds either there or from the command
line with the generated makefile:

    make

## Evidence

The scope captures and the videos recorded for the demo sit next to the
snapshots, named for the task they belong to. The report is
`prac_01A_lxxtri004_shrgil004.tex`.
