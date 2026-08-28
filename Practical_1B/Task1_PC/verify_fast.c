/*
 * Cross check for Task 2. The board version of the square root has to be
 * right for every 32 bit input, and ten golden values only prove it is right
 * ten times. This runs the same algorithm on the PC against the golden and
 * hammers it with far more inputs than the board ever sees.
 *
 * Three passes, each aimed at a different way the algorithm could be wrong.
 */
#include <math.h>
#include <stdint.h>
#include <stdio.h>

/* The golden version, same as in golden.c. Double precision gets close and
   the two loops walk the answer back to the exact integer. */
uint32_t isqrt_golden(uint32_t x) {
  uint32_t r = (uint32_t)sqrt((double)x);
  while ((uint64_t)r * r > (uint64_t)x)
    r--;
  while ((uint64_t)(r + 1) * (r + 1) <= (uint64_t)x)
    r++;
  return r;
}

/* Character for character the same function the board runs. It is copied
   rather than shared so this test cannot pass because of a header change
   that never reached the firmware. */
uint32_t isqrt_fast(uint32_t n) {
  uint32_t root = 0, rem = 0;
  for (int i = 0; i < 16; i++) {
    rem = (rem << 2) | (n >> 30);
    n <<= 2;
    root <<= 1;
    if (rem > root) {
      rem -= root + 1;
      root += 2;
    }
  }
  return root >> 1;
}

int main(void) {
  uint64_t bad = 0, checked = 0;

  /* Pass one. Every input up to just over a million, with no gaps. This is
     where an off by one in the small cases would show up. */
  for (uint64_t x = 0; x <= 0x100000ULL; x++) {
    if (isqrt_fast((uint32_t)x) != isqrt_golden((uint32_t)x)) {
      bad++;
      if (bad < 5)
        printf("low mismatch at %llu\n", (unsigned long long)x);
    }
    checked++;
  }

  /* Pass two. Every perfect square with the value on either side of it.
     Those are the only places the answer changes, so if the algorithm rounds
     the wrong way anywhere it happens here. */
  for (uint64_t r = 0; r <= 65535ULL; r++) {
    uint32_t sq = (uint32_t)(r * r);
    uint32_t around[3] = {sq ? sq - 1 : 0, sq,
                          (r < 65535) ? sq + 1 : 0xFFFFFFFFU};
    for (int k = 0; k < 3; k++) {
      if (isqrt_fast(around[k]) != isqrt_golden(around[k])) {
        bad++;
        if (bad < 5)
          printf("boundary mismatch at %u\n", around[k]);
      }
      checked++;
    }
  }

  /* Pass three. Twenty million values scattered over the whole range, from a
     plain linear congruential generator so the run is repeatable. This is
     the pass that covers the large inputs the first two never reach. */
  uint32_t s = 12345;
  for (long i = 0; i < 20000000L; i++) {
    s = s * 1664525U + 1013904223U;
    if (isqrt_fast(s) != isqrt_golden(s)) {
      bad++;
      if (bad < 5)
        printf("random mismatch at %u\n", s);
    }
    checked++;
  }

  printf("checked %llu values, %llu mismatches\n", (unsigned long long)checked,
         (unsigned long long)bad);

  /* Non zero exit if anything failed, so a script or CI can tell. */
  return bad != 0;
}
