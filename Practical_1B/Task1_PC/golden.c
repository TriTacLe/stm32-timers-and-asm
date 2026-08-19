/*
 * Task 1, the golden measure.
 *
 * The job is to work out the integer square root of a 32 bit unsigned value,
 * meaning the largest whole number whose square still fits under the input.
 * This version runs on the PC and uses double precision and the standard
 * library, which is exactly what the practical asks for. It is the reference
 * the board version gets checked against later, so it is written for
 * obviously correct rather than for fast.
 *
 * It also times one call, which is the other half of Task 1.
 */
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <time.h>

static const uint32_t INPUTS[] = {
    0U,          1U,          15U,         16U,         4095U,
    65535U,      123456789U,  987654321U,  4294836225U, 4294967295U,
};
#define N_INPUTS (sizeof(INPUTS) / sizeof(INPUTS[0]))

/*
 * A double holds 53 bits of significand, so every 32 bit input is stored
 * exactly, but the square root itself still gets rounded. Near the top of the
 * range that rounding can push the answer one too high. The two loops walk it
 * back down or up until it is exactly right, which makes the result correct
 * by construction instead of correct as long as the rounding behaves.
 */
uint32_t isqrt_golden(uint32_t x) {
  uint32_t r = (uint32_t)sqrt((double)x);
  while ((uint64_t)r * r > (uint64_t)x) {
    r--;
  }
  while ((uint64_t)(r + 1) * (r + 1) <= (uint64_t)x) {
    r++;
  }
  return r;
}

/*
 * The same check the report writes out by hand for one input. The answer is
 * right when its square fits under the input and the next number up does not.
 * The multiplications go through 64 bit because the square of a large answer
 * overflows 32 bits.
 */
static int hand_check(uint32_t x, uint32_t r) {
  uint64_t lo = (uint64_t)r * r;
  uint64_t hi = (uint64_t)(r + 1) * (r + 1);
  return lo <= (uint64_t)x && hi > (uint64_t)x;
}

/* A monotonic clock, so the reading cannot jump if the system clock is
   adjusted while the loop is running. */
static double now_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec * 1e9 + (double)ts.tv_nsec;
}

/* Every result is stored here. Marking it volatile means the compiler has to
   keep the call, otherwise it would notice nothing uses the answer and delete
   the very thing being timed. */
static volatile uint32_t sink;

/*
 * One call is far too short to time on its own. The clock itself has a
 * resolution of tens of nanoseconds and reading it costs about as much as the
 * function does, so a single reading is mostly measurement overhead. Running
 * many calls and dividing spreads that cost out until it stops mattering.
 */
static double time_per_call_ns(long reps) {
  double t0 = now_ns();
  for (long i = 0; i < reps; i++) {
    /* The input changes every pass so no answer can be reused from the last
       one, either by the compiler or by the branch predictor. */
    sink = isqrt_golden((uint32_t)(123456789U + (uint32_t)i));
  }
  double t1 = now_ns();
  return (t1 - t0) / (double)reps;
}

int main(void) {
  printf("Task 1 golden measure, integer square root\n\n");
  printf("%12s  %10s  %22s  %22s  %s\n", "input", "isqrt", "r*r", "(r+1)*(r+1)",
         "hand check");
  for (size_t i = 0; i < N_INPUTS; i++) {
    uint32_t x = INPUTS[i];
    uint32_t r = isqrt_golden(x);
    printf("%12u  %10u  %22llu  %22llu  %s\n", x, r,
           (unsigned long long)r * r, (unsigned long long)(r + 1) * (r + 1),
           hand_check(x, r) ? "pass" : "FAIL");
  }

  /* Two runs an order of magnitude apart. If the time per call comes out the
     same in both then the number is the cost of the function and not an
     artefact of how long the loop ran. */
  const long reps_a = 1000000L;
  const long reps_b = 10000000L;
  double a = time_per_call_ns(reps_a);
  double b = time_per_call_ns(reps_b);
  double mean = (a + b) / 2.0;

  printf("\nrun A: %ld reps, %.3f ns per call\n", reps_a, a);
  printf("run B: %ld reps, %.3f ns per call\n", reps_b, b);
  printf("mean %.3f ns, spread %.3f ns (%.2f %% of mean)\n", mean,
         a > b ? a - b : b - a, (a > b ? a - b : b - a) / mean * 100.0);
  return 0;
}
