/*
 * Task 6: Software PWM via Timer Interrupts
 * Target: STM32F051C8 (UCT Dev Board)
 * Output: PB5 (Byte of LEDs bit D5)
 * Signal: 100 Hz, 30% duty cycle, generated entirely in software
 */
#include "stm32f0xx.h"

// task 6 solution start
// 8 MHz clock. PSC 7 divides it to 1 MHz, ARR 99 divides that to 10 kHz.
// 10 kHz interrupts give 100 steps inside every 100 Hz PWM period
#define TIM16_PSC_VALUE 7
#define TIM16_ARR_VALUE 99
// task 6 solution end

static void GPIO_Init(void);
static void TIM16_Init(void);

int main(void) {
  // task 6 solution start
  GPIO_Init();
  TIM16_Init();
  // task 6 solution end

  while (1) {
    /* All PWM generation happens in the ISR; main loop remains free */
  }
}

static void GPIO_Init(void) {
  // task 6 solution start
  RCC->AHBENR |= RCC_AHBENR_GPIOBEN;

  // PB5 as plain output. clear the two MODER bits then set 01 for output.
  // push pull, medium speed, no pull resistors since we drive it both ways
  GPIOB->MODER &= ~(3U << (5 * 2));
  GPIOB->MODER |= (1U << (5 * 2));
  GPIOB->OTYPER &= ~(1U << 5);
  GPIOB->OSPEEDR &= ~(3U << (5 * 2));
  GPIOB->OSPEEDR |= (1U << (5 * 2));
  GPIOB->PUPDR &= ~(3U << (5 * 2));

  // BRR write forces the pin low so the signal starts in a known state
  GPIOB->BRR = (1U << 5);
  // task 6 solution end
}

static void TIM16_Init(void) {
  // task 6 solution start
  RCC->APB2ENR |= RCC_APB2ENR_TIM16EN;

  // 8 MHz divided by 8 then by 100 gives the 10 kHz update rate
  TIM16->PSC = TIM16_PSC_VALUE;
  TIM16->ARR = TIM16_ARR_VALUE;

  // clear any old update flag so we do not take an interrupt immediately,
  // then enable the update interrupt
  TIM16->SR = 0;
  TIM16->DIER = TIM_DIER_UIE;

  NVIC_SetPriority(TIM16_IRQn, 1);
  NVIC_EnableIRQ(TIM16_IRQn);

  // counter enable, from here the ISR fires every 100 us
  TIM16->CR1 |= TIM_CR1_CEN;
  // task 6 solution end
}

void TIM16_IRQHandler(void) {
  // task 6 solution start
  // counter keeps its value between interrupts because it is static.
  // it counts 0 to 99 which is one full PWM period of 10 ms
  static uint8_t counter = 0;

  if (TIM16->SR & TIM_SR_UIF) {
    // clear the flag first or the interrupt refires forever
    TIM16->SR &= ~TIM_SR_UIF;

    // pin high for the first 30 ticks and low for the other 70.
    // that is 30 percent duty at 100 Hz
    if (counter < 30) {
      GPIOB->BSRR = (1U << 5);
    } else {
      GPIOB->BRR = (1U << 5);
    }

    counter++;
    if (counter >= 100) {
      counter = 0;
    }
  }
  // task 6 solution end
}
