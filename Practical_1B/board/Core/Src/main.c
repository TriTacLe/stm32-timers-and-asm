/*
 * Practical 1B, Tasks 2 and 3
 * Target: STM32F051C8 (UCT Dev Board), reset clock, HSI 8 MHz, no PLL
 *
 * PC13  timing pulse, idle high, driven low for the timed section
 * PB11  green status LED, lit when all ten golden values match
 * PB10  red status LED, lit when any golden value fails
 *
 * TIM3 free runs at 8 MHz with PSC 0 and ARR 0xFFFF, so one tick is 125 ns
 * and the counter wraps every 8.192 ms.
 */
#include "stm32f0xx.h"

// ---
// which part of the practical this image runs, set with make TASK=n
#ifndef PRAC1B_TASK
#define PRAC1B_TASK 2
#endif

// the assembly routines for Tasks 4 and 5
extern void phase_delay_run(void);
extern void lcd_init_asm(void);
extern void lcd_show_A(void);

#define PULSE_PIN 13U // PC13
#define LED_FAIL 10U  // PB10, red
#define LED_PASS 11U  // PB11, green

// PSC 0 keeps the counter clock at the full 8 MHz, ARR 0xFFFF gives the
// widest span before a wrap, so one tick is 125 ns and a wrap is 8.192 ms
#define TIM3_PSC_VALUE 0U
#define TIM3_ARR_VALUE 0xFFFFU

#define NS_PER_TICK 125U

#define GOLDEN_COUNT 10U
#define LONG_RUN_CALLS 200000U // long enough to cross the wrap many times

// the ten inputs from Task 1 and the golden outputs produced on the PC
static const uint32_t golden_in[GOLDEN_COUNT] = {
    0U,     1U,          15U,         16U,         4095U,
    65535U, 123456789U,  987654321U,  4294836225U, 4294967295U,
};
static const uint32_t golden_out[GOLDEN_COUNT] = {
    0U, 1U, 3U, 4U, 63U, 255U, 11111U, 31426U, 65535U, 65535U,
};

// results live in globals so the debugger can read them without a UART
volatile uint16_t single_call_span;     // timer ticks for one call
volatile uint32_t single_call_ns;       // same span converted to ns
volatile uint32_t long_run_ticks;       // ticks for LONG_RUN_CALLS calls
volatile uint32_t long_run_overflows;   // wraps seen during the long run
volatile uint32_t long_run_ns_per_call; // mean ns per call over the long run
volatile uint32_t verify_failures;      // how many golden values mismatched
volatile uint32_t sink;                 // keeps the timed call from folding away
// ---

static void GPIO_Init(void);
static void TIM3_Init(void);
static uint32_t isqrt_fast(uint32_t n);
static uint32_t verify_against_golden(void);
static void measure_single_call(uint32_t x);
static void measure_long_run(void);

int main(void) {
  // ---
#if PRAC1B_TASK == 4
  phase_delay_run(); // never returns, the sample loop runs forever

#elif PRAC1B_TASK == 5
  lcd_init_asm();
  lcd_show_A();
  while (1) {
    /* the panel holds the character on its own */
  }

#else
  GPIO_Init();
  TIM3_Init();

  // the LED says pass or fail before any timing is reported, so a bad
  // implementation cannot be mistaken for a fast one
  verify_failures = verify_against_golden();
  if (verify_failures == 0U) {
    GPIOB->BSRR = (1U << LED_PASS);
  } else {
    GPIOB->BSRR = (1U << LED_FAIL);
  }

  // 987654321 is the input named in the Task 2 question
  measure_single_call(987654321U);
  measure_long_run();

  while (1) {
    // repeat the single measurement so the scope has a stable pulse to
    // trigger on during the demo
    measure_single_call(987654321U);
  }
#endif
  // ---
}

static void GPIO_Init(void) {
  // ---
  RCC->AHBENR |= RCC_AHBENR_GPIOBEN | RCC_AHBENR_GPIOCEN;

  // PC13 as plain output. clear the two MODER bits then set 01 for output.
  // push pull at high speed so the edges stay sharp under the scope probe
  GPIOC->MODER &= ~(3U << (PULSE_PIN * 2));
  GPIOC->MODER |= (1U << (PULSE_PIN * 2));
  GPIOC->OTYPER &= ~(1U << PULSE_PIN);
  GPIOC->OSPEEDR |= (3U << (PULSE_PIN * 2));
  GPIOC->PUPDR &= ~(3U << (PULSE_PIN * 2));

  // idle high, so the low part of the trace is exactly the timed window
  GPIOC->BSRR = (1U << PULSE_PIN);

  // the two status LEDs, both off until the verification has run
  GPIOB->MODER &= ~((3U << (LED_FAIL * 2)) | (3U << (LED_PASS * 2)));
  GPIOB->MODER |= (1U << (LED_FAIL * 2)) | (1U << (LED_PASS * 2));
  GPIOB->BRR = (1U << LED_FAIL) | (1U << LED_PASS);
  // ---
}

static void TIM3_Init(void) {
  // ---
  RCC->APB1ENR |= RCC_APB1ENR_TIM3EN;

  TIM3->PSC = TIM3_PSC_VALUE;
  TIM3->ARR = TIM3_ARR_VALUE;

  // UG copies PSC and ARR into the shadow registers before the counter
  // starts, otherwise the first period runs with the reset values
  TIM3->EGR = TIM_EGR_UG;
  TIM3->SR = 0; // UG also set the update flag, clear it again

  TIM3->CR1 |= TIM_CR1_CEN;
  // ---
}

// ---
// Bit-by-bit integer square root. Two bits of the input shift into the
// remainder each pass, so sixteen passes cover the full 32-bit range. No
// division and no floating point, which matters on the M0 because it has
// neither in hardware.
static uint32_t isqrt_fast(uint32_t n) {
  uint32_t root = 0U;
  uint32_t rem = 0U;

  for (int i = 0; i < 16; i++) {
    rem = (rem << 2) | (n >> 30);
    n <<= 2;
    root <<= 1;

    // root doubles as the trial divisor here, so the compare is the whole
    // decision and the subtract only happens when the bit is a one
    if (rem > root) {
      rem -= root + 1U;
      root += 2U;
    }
  }
  return root >> 1;
}

static uint32_t verify_against_golden(void) {
  uint32_t failures = 0U;

  for (uint32_t i = 0U; i < GOLDEN_COUNT; i++) {
    if (isqrt_fast(golden_in[i]) != golden_out[i]) {
      failures++;
    }
  }
  return failures;
}

// One timed call. The pin goes low, the counter is sampled, the call runs,
// the counter is sampled again and the pin goes high. Subtracting two
// uint16_t values wraps correctly on its own, as long as the call is shorter
// than one counter period, and 8.192 ms leaves plenty of room.
static void measure_single_call(uint32_t x) {
  GPIOC->BRR = (1U << PULSE_PIN);
  uint16_t before = (uint16_t)TIM3->CNT;
  sink = isqrt_fast(x);
  uint16_t after = (uint16_t)TIM3->CNT;
  GPIOC->BSRR = (1U << PULSE_PIN);

  single_call_span = (uint16_t)(after - before);
  single_call_ns = (uint32_t)single_call_span * NS_PER_TICK;
}

// Long run across many wraps. One call is far shorter than a counter period,
// so the update flag is polled inside the loop and counted. The total is then
// overflows * 65536 plus the plain 16-bit difference.
static void measure_long_run(void) {
  uint32_t overflows = 0U;

  TIM3->SR = (uint16_t)~TIM_SR_UIF;
  uint16_t before = (uint16_t)TIM3->CNT;

  for (uint32_t i = 0U; i < LONG_RUN_CALLS; i++) {
    // the input changes every pass so no result can be cached or hoisted
    sink = isqrt_fast(987654321U + i);
    if (TIM3->SR & TIM_SR_UIF) {
      TIM3->SR = (uint16_t)~TIM_SR_UIF;
      overflows++;
    }
  }

  uint16_t after = (uint16_t)TIM3->CNT;

  // a wrap can land between the last loop pass and this read, so check once more
  if (TIM3->SR & TIM_SR_UIF) {
    TIM3->SR = (uint16_t)~TIM_SR_UIF;
    overflows++;
  }

  long_run_overflows = overflows;
  long_run_ticks = overflows * 65536U + (uint32_t)(uint16_t)(after - before);
  long_run_ns_per_call =
      (uint32_t)(((uint64_t)long_run_ticks * NS_PER_TICK) / LONG_RUN_CALLS);
}
// ---
