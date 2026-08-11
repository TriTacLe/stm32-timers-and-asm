/* USER CODE BEGIN Header /
/*

@file           : main.c

@brief          : Task 2 - Running light with debounced speed toggle

/*
/ USER CODE END Header */

/* Includes ------------------------------------------------------------------*/
#include "main.h"
#include "stm32f0xx.h"
#include <stdint.h>

/* Private variables ---------------------------------------------------------*/
TIM_HandleTypeDef htim16;

/* USER CODE BEGIN PV */
volatile uint8_t timer_event = 0;
volatile uint8_t current_led = 0;
volatile int8_t direction = 1;

// LED arrays
GPIO_TypeDef *led_ports[8] = {GPIOB, GPIOB, GPIOB, GPIOB,
                              GPIOB, GPIOB, GPIOB, GPIOB};
uint16_t led_pins[8] = {GPIO_PIN_0, GPIO_PIN_1, GPIO_PIN_2, GPIO_PIN_3,
                        GPIO_PIN_4, GPIO_PIN_5, GPIO_PIN_6, GPIO_PIN_7};

// Debounce delay chosen from oscilloscope bounce measurement.
// Measured maximum bounce on our board: ___ ms (fill in from Task 3 capture).
// 50 ms gives comfortable margin above typical 10 to 20 ms bounce while
// staying far below any intentional double press.
#define DEBOUNCE_MS 50
uint32_t last_button_press_time = 0;

// Speed state: 0 = slow (1s), 1 = fast (0.5s)
uint8_t speed_state = 0;

// Current ARR value (stored for reference)
uint32_t current_arr = 999;
/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
static void MX_GPIO_Init(void);
static void MX_TIM16_Init(void);
void TIM16_IRQHandler(void);
void turn_off_all_leds(void);
void update_led_pattern(void);
void handle_button_press(void);
void change_timer_period(uint32_t new_period_ms);

/* USER CODE BEGIN 0 */
void turn_off_all_leds(void) {
  for (uint8_t i = 0; i < 8; i++) {
    HAL_GPIO_WritePin(led_ports[i], led_pins[i], GPIO_PIN_RESET);
  }
}

void update_led_pattern(void) {
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
}

void change_timer_period(uint32_t new_period_ms) {
  // Timer clock is 1000 Hz (prescaler fixed at 7999), so one count = 1 ms:
  // ARR = period_ms - 1
  uint32_t new_arr = new_period_ms - 1;

  TIM16->ARR = new_arr; // written to the preload register (ARPE = 1)
  TIM16->CNT = 0;       // restart the current cycle from zero

  // Store the new ARR value for reference
  current_arr = new_arr;
}

void handle_button_press(void) {
  uint32_t now = HAL_GetTick();

  // PA0 is active low (pressed = GPIO_PIN_RESET)
  GPIO_PinState state = HAL_GPIO_ReadPin(GPIOA, GPIO_PIN_0);

  // Remember the previous sample so only the press edge triggers, not holding
  static GPIO_PinState prev_state = GPIO_PIN_SET;

  if (state == GPIO_PIN_RESET && prev_state == GPIO_PIN_SET &&
      (now - last_button_press_time) >= DEBOUNCE_MS) {
    last_button_press_time = now;
    speed_state ^= 1;
    change_timer_period(speed_state ? 500 : 1000);
  }
  prev_state = state;
}
/* USER CODE END 0 */

/*

@brief  The application entry point.

@retval int
*/
int main(void) {
  HAL_Init();
  SystemClock_Config();

  MX_GPIO_Init();
  MX_TIM16_Init();

  /* USER CODE BEGIN 2 */
  turn_off_all_leds();

  // Start timer at 1-second period
  change_timer_period(1000);
  HAL_TIM_Base_Start_IT(&htim16);
  /* USER CODE END 2 */

  while (1) {
    /* USER CODE BEGIN WHILE */
    // Handle button press (debounced)
    handle_button_press();

    // Handle timer event
    if (timer_event) {
      timer_event = 0;
      update_led_pattern();
    }
    /* USER CODE END WHILE */
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

  // Configure PA0 as input with pull-up (button active low)
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
