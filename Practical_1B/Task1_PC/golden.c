/*
 * Task 1: golden measure for the integer square root, run on the PC.
 * isqrt(x) is the largest n with n*n <= x, for any 32-bit unsigned x.
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

/* double sqrt can land one off at the top of the range, so clamp both ways */
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

/* squaring both r and r+1 is the same check the report writes out by hand */
static int hand_check(uint32_t x, uint32_t r) {
  uint64_t lo = (uint64_t)r * r;
  uint64_t hi = (uint64_t)(r + 1) * (r + 1);
  return lo <= (uint64_t)x && hi > (uint64_t)x;
}

static double now_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec * 1e9 + (double)ts.tv_nsec;
}

/* sink keeps the optimiser from deleting the call we are trying to time */
static volatile uint32_t sink;

static double time_per_call_ns(long reps) {
  double t0 = now_ns();
  for (long i = 0; i < reps; i++) {
    /* vary the input so no cached result can be reused across iterations */
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
