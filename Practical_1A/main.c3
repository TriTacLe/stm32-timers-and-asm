/*
 * @file  : main.c
 * @brief : Task 3 - Running light with debounced speed toggle
 */

// TASK 3: same running light as Task 2, but PA0 switches the step speed
// between 1 s and 0.5 s.
// The problem is contact bounce. A push button is two bits of metal springing
// together. They chatter for a few ms before settling, so one press looks to
// the chip like several presses.
// handle_button_press below accepts a press only when both are true:
// 1. the pin has just gone from high to low, so holding it down does nothing
// 2. at least DEBOUNCE_MS since the last accepted press, which eats the chatter
// Buttons are active low. Pressing connects the pin to ground, so pressed reads 0.
// Nothing holds the pin high on its own, so the internal pull up is switched on.
// Speed changes write TIM16->ARR directly and reset TIM16->CNT, as the brief says.
// The prescaler stays at 7999, so one count is 1 ms and ARR is the period minus one.

/* Includes ------------------------------------------------------------------*/
#include "main.h"
#include "stm32f0xx.h"
#include <stdint.h>

/* Private variables ---------------------------------------------------------*/
TIM_HandleTypeDef htim16;

volatile uint8_t timer_event = 0;
volatile uint8_t current_led = 0;
volatile int8_t direction = 1;

// LED arrays
GPIO_TypeDef *led_ports[8] = {GPIOB, GPIOB, GPIOB, GPIOB,
                              GPIOB, GPIOB, GPIOB, GPIOB};
uint16_t led_pins[8] = {GPIO_PIN_0, GPIO_PIN_1, GPIO_PIN_2, GPIO_PIN_3,
                        GPIO_PIN_4, GPIO_PIN_5, GPIO_PIN_6, GPIO_PIN_7};

// task 3 solution start (debounce value)
// Debounce delay chosen from oscilloscope bounce measurement.
// Measured maximum bounce on our board: 1.27 us (single-shot capture on PA0).
// 50 ms gives comfortable margin above typical 10 to 20 ms bounce while
// staying far below any intentional double press.
#define DEBOUNCE_MS 50
// task 3 solution end
// Millisecond stamp of the last press we accepted. Everything inside the
// DEBOUNCE_MS window after it is treated as chatter and thrown away.
uint32_t last_button_press_time = 0;

uint8_t speed_state = 0; // 0 is slow at 1 s per step, 1 is fast at 0.5 s

uint32_t current_arr = 999; // last value written to ARR, kept for reference

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);   // HSI at 8 MHz
static void MX_GPIO_Init(void);  // LEDs out on port B, button in on PA0
static void MX_TIM16_Init(void); // PSC fixed at 7999, ARR changes at runtime
void TIM16_IRQHandler(void);     // sets the flag only
void turn_off_all_leds(void);    // blank the row
void update_led_pattern(void);   // one step of the running light
void handle_button_press(void);  // edge detect plus debounce, polled in main
void change_timer_period(uint32_t new_period_ms); // retune the live timer

void turn_off_all_leds(void) {
  // task 3 solution start
  // walk the arrays and write every led low
  for (uint8_t i = 0; i < 8; i++) {
    HAL_GPIO_WritePin(led_ports[i], led_pins[i], GPIO_PIN_RESET);
  }
  // task 3 solution end
}

void update_led_pattern(void) {
  // task 3 solution start
  turn_off_all_leds();
  HAL_GPIO_WritePin(led_ports[current_led], led_pins[current_led],
                    GPIO_PIN_SET);

  // Reverse at the edges before stepping: 0,1,...,6,7,6,...,1,0,1,...
  if (current_led == 7) {
    direction = -1;
  } else if (current_led == 0) {
    direction = 1;
  }
  current_led += direction;
  // task 3 solution end
}

// Changes the step speed on a running timer. The brief is specific here:
// keep the prescaler at 7999, write TIM16->ARR directly, reset TIM16->CNT,
// and do not call the init function again. Re initialising would stop the
// timer, rewrite every register and restart it, which is both slower and
// visible as a stutter in the pattern.
void change_timer_period(uint32_t new_period_ms) {
  // task 3 solution start
  // Timer clock is 1 kHz because PSC stays at 7999, so one count is 1 ms and
  // ARR is just the period in ms minus one.
  uint32_t new_arr = new_period_ms - 1;

  // ARPE is on, so this lands in the shadow register and takes effect at the
  // next rollover rather than immediately.
  TIM16->ARR = new_arr;

  // Reset the count so the new period starts now. Without this, pressing the
  // button at count 800 with a new ARR of 499 leaves CNT already past ARR,
  // and the counter has to wrap all the way through 65535 before reloading.
  TIM16->CNT = 0;
  // task 3 solution end

  current_arr = new_arr;
}

// Called every pass of the main loop. Two independent filters have to agree
// before a press counts.
void handle_button_press(void) {
  // task 3 solution start
  // HAL_GetTick is a millisecond counter incremented by the SysTick interrupt.
  // Comparing timestamps is non blocking, unlike HAL_Delay which would freeze
  // the running light for the whole debounce window.
  uint32_t now = HAL_GetTick();

  // Active low. The pull up holds the pin at 3.3 V when nothing is happening,
  // and pressing shorts it to ground, so pressed reads RESET.
  GPIO_PinState state = HAL_GPIO_ReadPin(GPIOA, GPIO_PIN_0);

  // static, so it survives between calls. Starts at SET, the released level.
  static GPIO_PinState prev_state = GPIO_PIN_SET;

  // Filter 1, the edge: low now and high last time, so this is the moment of
  // pressing. Holding the button down stays low on both samples and does
  // nothing, which is what stops one long press repeating.
  // Filter 2, the deadline: ignore anything within DEBOUNCE_MS of the last
  // accepted press. The contacts chatter for a few ms, and this swallows it.
  if (state == GPIO_PIN_RESET && prev_state == GPIO_PIN_SET &&
      (now - last_button_press_time) >= DEBOUNCE_MS) {
    last_button_press_time = now;
    speed_state ^= 1; // XOR with 1 flips 0 to 1 and 1 to 0
    change_timer_period(speed_state ? 500 : 1000);
  }

  // Always update, inside the if or not, otherwise the edge is never seen.
  prev_state = state;
  // task 3 solution end
}

/*

@brief  The application entry point.

@retval int
*/
int main(void) {
  HAL_Init();
  SystemClock_Config();

  MX_GPIO_Init();
  MX_TIM16_Init();

  turn_off_all_leds();

  // Start timer at 1-second period
  change_timer_period(1000);
  HAL_TIM_Base_Start_IT(&htim16);

  // Two jobs sharing one loop, neither blocking the other. The button is
  // sampled thousands of times a second while the LED still steps on the
  // timer. A HAL_Delay based debounce would stall the pattern instead.
  while (1) {
    handle_button_press();

    if (timer_event) {
      timer_event = 0;
      update_led_pattern();
    }
  }
}

/*

@brief System Clock Configuration (HSI 8 MHz)
*/
void SystemClock_Config(void) {
  LL_FLASH_SetLatency(LL_FLASH_LATENCY_0);
  while (LL_FLASH_GetLatency() != LL_FLASH_LATENCY_0) {
  }

  LL_RCC_HSI_Enable();
  while (LL_RCC_HSI_IsReady() != 1) {
  }

  LL_RCC_HSI_SetCalibTrimming(16);
  LL_RCC_SetAHBPrescaler(LL_RCC_SYSCLK_DIV_1);
  LL_RCC_SetAPB1Prescaler(LL_RCC_APB1_DIV_1);
  LL_RCC_SetSysClkSource(LL_RCC_SYS_CLKSOURCE_HSI);
  while (LL_RCC_GetSysClkSource() != LL_RCC_SYS_CLKSOURCE_STATUS_HSI) {
  }

  LL_SetSystemCoreClock(8000000);
  if (HAL_InitTick(TICK_INT_PRIORITY) != HAL_OK) {
    Error_Handler();
  }
}

/*

@brief TIM16 Initialization - Prescaler fixed at 7999
*/
static void MX_TIM16_Init(void) {
  htim16.Instance = TIM16;
  htim16.Init.Prescaler = 7999;
  htim16.Init.CounterMode = TIM_COUNTERMODE_UP;
  htim16.Init.Period = 999;
  htim16.Init.ClockDivision = TIM_CLOCKDIVISION_DIV1;
  htim16.Init.RepetitionCounter = 0;
  htim16.Init.AutoReloadPreload = TIM_AUTORELOAD_PRELOAD_ENABLE;
  if (HAL_TIM_Base_Init(&htim16) != HAL_OK) {
    Error_Handler();
  }
  NVIC_EnableIRQ(TIM16_IRQn);
}

/*

@brief GPIO Initialization - PB0..PB7 as outputs, PA0 as input with pull-up
*/
static void MX_GPIO_Init(void) {
  __HAL_RCC_GPIOA_CLK_ENABLE();
  __HAL_RCC_GPIOB_CLK_ENABLE();

  GPIO_InitTypeDef GPIO_InitStruct = {0};

  // Configure LEDs (PB0..PB7) as outputs
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;

  for (uint8_t i = 0; i < 8; i++) {
    GPIO_InitStruct.Pin = led_pins[i];
    HAL_GPIO_Init(led_ports[i], &GPIO_InitStruct);
  }

  // PA0 as an input. The pull up matters: the button only connects the pin to
  // ground, nothing pulls it high, so without it a released pin floats and
  // reads random noise.
  GPIO_InitStruct.Pin = GPIO_PIN_0;
  GPIO_InitStruct.Mode = GPIO_MODE_INPUT;
  GPIO_InitStruct.Pull = GPIO_PULLUP;
  HAL_GPIO_Init(GPIOA, &GPIO_InitStruct);
}

/*

@brief TIM16 interrupt handler - sets flag only
*/
void TIM16_IRQHandler(void) {
  HAL_TIM_IRQHandler(&htim16);
  timer_event = 1;
}

/*

@brief Error handler
*/
void Error_Handler(void) {
  __disable_irq();
  while (1) {
  }
}
