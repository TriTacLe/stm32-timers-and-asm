/*
 * Practical 1B, Tasks 2 and 3
 * Target is the STM32F051C8 on the UCT Dev Board, running from the reset
 * clock, which is the 8 MHz internal RC oscillator with no PLL.
 *
 * PC13 is the timing pin. It sits high and is pulled low only while the
 * function under test runs, so the low part of the scope trace is the
 * execution window and nothing else.
 * PB1 is the red LED and lights when all ten golden values match.
 * PB0 is the red LED and lights when any of them do not.
 *
 * TIM3 free runs at the full 8 MHz. One tick is therefore 125 ns and the
 * 16 bit counter takes 8.192 ms to come back around to where it started.
 */
#include "stm32f0xx.h"

// ---
// Which part of the practical this build runs. Change it on the command
// line with make TASK=4 rather than editing the file, so the same source
// produces all three images.
#ifndef PRAC1B_TASK
#define PRAC1B_TASK 2
#endif

// Tasks 4 and 5 are written in assembly and live in their own files. These
// declarations are all the C side needs to call into them.
extern void phase_delay_run(void);
extern void lcd_init_asm(void);
extern void lcd_show_A(void);

#define PULSE_PIN 13U // PC13, the pin the scope watches
#define LED_FAIL 0U   // PB0, wrong result
#define LED_PASS 1U   // PB1, correct result

// A prescaler of zero means the timer counts at the full peripheral clock,
// which keeps the resolution as fine as the hardware allows. An auto reload
// of 0xFFFF lets the counter use its whole range before wrapping, so one
// tick is 125 ns and a full lap is 8.192 ms.
#define TIM3_PSC_VALUE 0U
#define TIM3_ARR_VALUE 0xFFFFU

#define NS_PER_TICK 125U

#define GOLDEN_COUNT 10U
// Enough calls that the counter wraps hundreds of times, which is the whole
// point of the long run. It proves the overflow counting works.
#define LONG_RUN_CALLS 200000U

// The ten inputs the practical asks for, with the answers the golden measure
// produced on the PC in Task 1. The board has to agree with all ten before
// any timing number from it means anything.
static const uint32_t golden_in[GOLDEN_COUNT] = {
    0U,     1U,          15U,         16U,         4095U,
    65535U, 123456789U,  987654321U,  4294836225U, 4294967295U,
};
static const uint32_t golden_out[GOLDEN_COUNT] = {
    0U, 1U, 3U, 4U, 63U, 255U, 11111U, 31426U, 65535U, 65535U,
};

// There is no UART in this build, so every result is left in a global where
// the debugger can read it after the run. Marking them volatile stops the
// compiler deciding nobody reads them and throwing the stores away.
volatile uint16_t single_call_span;     // timer ticks one call took
volatile uint32_t single_call_ns;       // that span turned into nanoseconds
volatile uint32_t long_run_ticks;       // ticks for the whole long run
volatile uint32_t long_run_overflows;   // how many times the counter wrapped
volatile uint32_t long_run_ns_per_call; // long run total divided by the calls
volatile uint32_t verify_failures;      // golden values that did not match
volatile uint32_t sink;                 // catches the result so the call stays
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
  phase_delay_run(); // this never comes back, the sample loop runs forever

#elif PRAC1B_TASK == 5
  lcd_init_asm();
  lcd_show_A();
  while (1) {
    // The panel holds the character by itself, so there is nothing to do
    // here. The loop only keeps the processor from running off the end.
  }

#else
  GPIO_Init();
  TIM3_Init();

  // Check correctness before measuring speed. If this order were the other
  // way around, a wrong implementation that happened to be quick could be
  // mistaken for a good result.
  verify_failures = verify_against_golden();
  if (verify_failures == 0U) {
    GPIOB->BSRR = (1U << LED_PASS);
  } else {
    GPIOB->BSRR = (1U << LED_FAIL);
  }

  // 987654321 is the input the Task 2 question asks about, so that is the
  // one that gets timed on its own.
  measure_single_call(987654321U);
  measure_long_run();

  while (1) {
    // Keep repeating the single measurement. The scope then sees the same
    // pulse over and over, which is what lets it trigger on a stable edge
    // during the demo instead of on one pulse that already happened.
    measure_single_call(987654321U);
  }
#endif
  // ---
}

static void GPIO_Init(void) {
  // ---
  // Nothing on a GPIO port responds until its clock is running, so this
  // comes first. Port B carries the LEDs and port C carries the timing pin.
  RCC->AHBENR |= RCC_AHBENR_GPIOBEN | RCC_AHBENR_GPIOCEN;

  // Each pin gets two bits in MODER. Clearing both first and then setting
  // the low one leaves 01, which means plain output. Writing the one bit
  // without clearing would leave whatever was there before.
  GPIOC->MODER &= ~(3U << (PULSE_PIN * 2));
  GPIOC->MODER |= (1U << (PULSE_PIN * 2));

  // Push pull rather than open drain, so the pin drives both directions
  // itself and the edge does not depend on a pullup.
  GPIOC->OTYPER &= ~(1U << PULSE_PIN);

  // Highest slew rate the pin offers. A slow edge would add its own rise
  // time to every measurement taken from this trace.
  GPIOC->OSPEEDR |= (3U << (PULSE_PIN * 2));

  // No pullup and no pulldown, because the output drives the line anyway
  // and a pull would only fight it.
  GPIOC->PUPDR &= ~(3U << (PULSE_PIN * 2));

  // Idle state is high. The timed window is then the low part of the trace,
  // which is easy to put cursors on.
  GPIOC->BSRR = (1U << PULSE_PIN);

  // Both LEDs as outputs, both off until the check has actually run.
  GPIOB->MODER &= ~((3U << (LED_FAIL * 2)) | (3U << (LED_PASS * 2)));
  GPIOB->MODER |= (1U << (LED_FAIL * 2)) | (1U << (LED_PASS * 2));
  GPIOB->BRR = (1U << LED_FAIL) | (1U << LED_PASS);
  // ---
}

static void TIM3_Init(void) {
  // ---
  // Same story as the GPIO ports. TIM3 hangs off APB1 and ignores every
  // register write until its clock is enabled.
  RCC->APB1ENR |= RCC_APB1ENR_TIM3EN;

  TIM3->PSC = TIM3_PSC_VALUE;
  TIM3->ARR = TIM3_ARR_VALUE;

  // The prescaler and the auto reload are both shadowed, meaning the values
  // written above only reach the counter at the next update event. Forcing
  // an update here copies them across straight away, otherwise the first
  // period would run with the reset values instead.
  TIM3->EGR = TIM_EGR_UG;

  // Forcing that update also set the update flag, which would look like a
  // wrap that never happened, so clear it before the counter starts.
  TIM3->SR = 0;

  TIM3->CR1 |= TIM_CR1_CEN;
  // ---
}

// ---
// Integer square root, worked out two bits at a time. Sixteen passes cover
// all thirty two bits of the input.
//
// The idea is the same as long division done in binary. At every step the
// next two bits of the input join the remainder, the answer so far doubles,
// and the question is whether the next bit of the answer can be a one. If
// the remainder is big enough to pay for it then it is, and the cost comes
// off the remainder.
//
// There is no divide and no floating point anywhere in it, which matters
// because the Cortex M0 has neither in hardware. Doing this with a division
// would call into a software routine and the timing would be dominated by
// that instead of by the algorithm.
static uint32_t isqrt_fast(uint32_t n) {
  uint32_t root = 0U;
  uint32_t rem = 0U;

  for (int i = 0; i < 16; i++) {
    // Shift the remainder up by two and take the top two bits of what is
    // left of the input.
    rem = (rem << 2) | (n >> 30);
    n <<= 2;
    root <<= 1;

    // root is doubled already, so it stands in for the trial divisor. The
    // compare decides the bit and the subtraction only happens when the bit
    // turns out to be a one.
    if (rem > root) {
      rem -= root + 1U;
      root += 2U;
    }
  }

  // One extra doubling happened on the way out of the loop, so undo it.
  return root >> 1;
}

// Run all ten golden inputs through the board version and count how many
// disagree with the PC. Zero failures is what lights the green LED.
static uint32_t verify_against_golden(void) {
  uint32_t failures = 0U;

  for (uint32_t i = 0U; i < GOLDEN_COUNT; i++) {
    if (isqrt_fast(golden_in[i]) != golden_out[i]) {
      failures++;
    }
  }
  return failures;
}

// One timed call. The pin drops, the counter is read, the call runs, the
// counter is read again and the pin goes back up.
//
// Subtracting the two counter readings as 16 bit values gives the right
// answer even when the counter wrapped in between, because the subtraction
// wraps in exactly the same way. The only requirement is that the call is
// shorter than one full lap of the counter, and a lap is 8.192 ms, which is
// hundreds of times longer than the call.
static void measure_single_call(uint32_t x) {
  volatile uint32_t measured_x = x;

  GPIOC->BRR = (1U << PULSE_PIN);
  uint16_t before = (uint16_t)TIM3->CNT;

  sink = isqrt_fast(measured_x);

  uint16_t after = (uint16_t)TIM3->CNT;
  GPIOC->BSRR = (1U << PULSE_PIN);

  single_call_span = (uint16_t)(after - before);
  single_call_ns = (uint32_t)single_call_span * NS_PER_TICK;
}

// The long run, which is the case the practical asks about. Two hundred
// thousand calls take far longer than one lap of the counter, so the plain
// difference between the two readings is not enough on its own. The update
// flag is checked after every call and counted, and the total is that count
// of full laps plus the leftover difference.
static void measure_long_run(void) {
  uint32_t overflows = 0U;

  // Clear the flag first so a wrap left over from earlier is not counted as
  // one of ours. Writing ones to every other bit keeps them untouched.
  TIM3->SR = (uint16_t)~TIM_SR_UIF;
  uint16_t before = (uint16_t)TIM3->CNT;

  for (uint32_t i = 0U; i < LONG_RUN_CALLS; i++) {
    // The input changes every pass on purpose. With a constant input the
    // compiler is free to work the answer out once and reuse it, and the
    // loop would then measure nothing at all.
    sink = isqrt_fast(987654321U + i);
    if (TIM3->SR & TIM_SR_UIF) {
      TIM3->SR = (uint16_t)~TIM_SR_UIF;
      overflows++;
    }
  }

  uint16_t after = (uint16_t)TIM3->CNT;

  // A wrap can still land between the last pass of the loop and the read
  // above, so check once more before doing the arithmetic.
  if (TIM3->SR & TIM_SR_UIF) {
    TIM3->SR = (uint16_t)~TIM_SR_UIF;
    overflows++;
  }

  long_run_overflows = overflows;
  long_run_ticks =
      overflows * 65536U +
      (uint32_t)after -
      (uint32_t)before;

  // Cast to 64 bit before multiplying. The tick count times 125 overflows a
  // 32 bit value on a run this long and the mean would come out nonsense.
  long_run_ns_per_call =
      (uint32_t)(((uint64_t)long_run_ticks * NS_PER_TICK) / LONG_RUN_CALLS);
}
// ---
