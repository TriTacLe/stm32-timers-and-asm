TARGET = Practical_1A


DEBUG = 1
OPT = -Og


BUILD_DIR = build

C_SOURCES =  \
Core/Src/main.c \
Core/Src/stm32f0xx_it.c \
Core/Src/system_stm32f0xx.c \
Drivers/STM32F0xx_HAL_Driver/Src/stm32f0xx_ll_gpio.c \
Drivers/STM32F0xx_HAL_Driver/Src/stm32f0xx_hal.c \
Drivers/STM32F0xx_HAL_Driver/Src/stm32f0xx_hal_pwr.c \
Drivers/STM32F0xx_HAL_Driver/Src/stm32f0xx_hal_pwr_ex.c \
Drivers/STM32F0xx_HAL_Driver/Src/stm32f0xx_ll_exti.c \
Drivers/STM32F0xx_HAL_Driver/Src/stm32f0xx_ll_rcc.c \
Drivers/STM32F0xx_HAL_Driver/Src/stm32f0xx_hal_cortex.c \
Drivers/STM32F0xx_HAL_Driver/Src/stm32f0xx_hal_dma.c \
Drivers/STM32F0xx_HAL_Driver/Src/stm32f0xx_hal_flash.c \
Drivers/STM32F0xx_HAL_Driver/Src/stm32f0xx_hal_flash_ex.c \
Drivers/STM32F0xx_HAL_Driver/Src/stm32f0xx_hal_gpio.c \
Drivers/STM32F0xx_HAL_Driver/Src/stm32f0xx_hal_i2c.c \
Drivers/STM32F0xx_HAL_Driver/Src/stm32f0xx_hal_i2c_ex.c \
Drivers/STM32F0xx_HAL_Driver/Src/stm32f0xx_hal_tim.c \
Drivers/STM32F0xx_HAL_Driver/Src/stm32f0xx_hal_tim_ex.c \
Drivers/STM32F0xx_HAL_Driver/Src/stm32f0xx_hal_rcc.c \
Drivers/STM32F0xx_HAL_Driver/Src/stm32f0xx_hal_rcc_ex.c \
Core/Src/stm32f0xx_hal_msp.c \
Drivers/STM32F0xx_HAL_Driver/Src/stm32f0xx_ll_utils.c
#Drivers/STM32F0xx_HAL_Driver/Src/stm32f0xx_hal_uart.c \
#Drivers/STM32F0xx_HAL_Driver/Src/stm32f0xx_hal_uart_ex.c \
# ASM sources
ASM_SOURCES =  \
startup_stm32f051x8.s


PREFIX = arm-none-eabi-
ifdef GCC_PATH
CC = $(GCC_PATH)/$(PREFIX)gcc
AS = $(GCC_PATH)/$(PREFIX)gcc -x assembler-with-cpp
CP = $(GCC_PATH)/$(PREFIX)objcopy
SZ = $(GCC_PATH)/$(PREFIX)size
else
CC = $(PREFIX)gcc
AS = $(PREFIX)gcc -x assembler-with-cpp
CP = $(PREFIX)objcopy
SZ = $(PREFIX)size
endif
HEX = $(CP) -O ihex
BIN = $(CP) -O binary -S
 
CPU = -mcpu=cortex-m0

MCU = $(CPU) -mthumb $(FPU) $(FLOAT-ABI)

AS_DEFS = 

C_DEFS =  \
-DSTM32F051x8 \
-DUSE_FULL_LL_DRIVER \
-DHSE_VALUE=8000000 \
-DHSE_STARTUP_TIMEOUT=100 \
-DLSE_STARTUP_TIMEOUT=5000 \
-DLSE_VALUE=32768 \
-DHSI_VALUE=8000000 \
-DLSI_VALUE=40000 \
-DVDD_VALUE=3300 \
-DPREFETCH_ENABLE=1 \
-DINSTRUCTION_CACHE_ENABLE=0 \
-DDATA_CACHE_ENABLE=0


AS_INCLUDES = 

C_INCLUDES =  \
-ICore/Inc \
-IDrivers/STM32F0xx_HAL_Driver/Inc \
-IDrivers/CMSIS/Device/ST/STM32F0xx/Include \
-IDrivers/CMSIS/Include



# compile gcc flags
ASFLAGS = $(MCU) $(AS_DEFS) $(AS_INCLUDES) $(OPT) -Wall -fdata-sections -ffunction-sections

CFLAGS += $(MCU) $(C_DEFS) $(C_INCLUDES) $(OPT) -Wall -fdata-sections -ffunction-sections

ifeq ($(DEBUG), 1)
CFLAGS += -g -gdwarf-2
endif


# Generate dependency information
CFLAGS += -MMD -MP -MF"$(@:%.o=%.d)"


# link script
LDSCRIPT = STM32F051C6Tx_FLASH.ld

# libraries
LIBS = -lc -lm -lnosys 
LIBDIR = 
LDFLAGS = $(MCU) -specs=nano.specs -T$(LDSCRIPT) $(LIBDIR) $(LIBS) -Wl,-Map=$(BUILD_DIR)/$(TARGET).map,--cref -Wl,--gc-sections

# default action: build all
all: $(BUILD_DIR)/$(TARGET).elf $(BUILD_DIR)/$(TARGET).hex $(BUILD_DIR)/$(TARGET).bin


# list of objects
OBJECTS = $(addprefix $(BUILD_DIR)/,$(notdir $(C_SOURCES:.c=.o)))
vpath %.c $(sort $(dir $(C_SOURCES)))
# list of ASM program objects
OBJECTS += $(addprefix $(BUILD_DIR)/,$(notdir $(ASM_SOURCES:.s=.o)))
vpath %.s $(sort $(dir $(ASM_SOURCES)))

$(BUILD_DIR)/%.o: %.c Makefile | $(BUILD_DIR) 
	$(CC) -c $(CFLAGS) -Wa,-a,-ad,-alms=$(BUILD_DIR)/$(notdir $(<:.c=.lst)) $< -o $@

$(BUILD_DIR)/%.o: %.s Makefile | $(BUILD_DIR)
	$(AS) -c $(CFLAGS) $< -o $@

$(BUILD_DIR)/$(TARGET).elf: $(OBJECTS) Makefile
	$(CC) $(OBJECTS) $(LDFLAGS) -o $@
	$(SZ) $@

$(BUILD_DIR)/%.hex: $(BUILD_DIR)/%.elf | $(BUILD_DIR)
	$(HEX) $< $@
	
$(BUILD_DIR)/%.bin: $(BUILD_DIR)/%.elf | $(BUILD_DIR)
	$(BIN) $< $@	
	
$(BUILD_DIR):
	mkdir $@		

clean:
	-rm -fR $(BUILD_DIR)
  
# Keep tools portable: use PATH, GCC_PATH, or override STM32_PROG explicitly.
# STM32CubeIDE debug/flash launches do not use this command-line flash target.
STM32_PROG ?= STM32_Programmer_CLI

task%: main.c%
	cp -f main.c$* Core/Src/main.c
	$(MAKE) all
	$(MAKE) flash

flash: | $(BUILD_DIR)
	$(STM32_PROG) -c port=SWD mode=UR reset=HWrst freq=1000 -w $(BUILD_DIR)/$(TARGET).bin 0x08000000 -v -rst

.PHONY: flash

-include $(wildcard $(BUILD_DIR)/*.d)
