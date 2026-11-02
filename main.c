
#include "main.h"
#include "stm32f4xx_hal.h"
#include <stdint.h>
#include <stdio.h>
#include <math.h>

/* Sampling configuration */
#define SAMPLE_RATE_HZ       5000U
#define DMA_BUFFER_SIZE      2048U
#define HALF_BUFFER_SIZE     (DMA_BUFFER_SIZE / 2U)
#define ADC_MAX_VALUE        4095U
#define ADC_REFERENCE_MV     3300U
#define UART_TIMEOUT_MS      100U

/* Voice pitch search range: approximately 50 to 500 Hz */
#define MIN_PITCH_LAG        10U
#define MAX_PITCH_LAG        100U
#define MIN_CORRELATION      0.25f

ADC_HandleTypeDef hadc1;
DMA_HandleTypeDef hdma_adc1;
UART_HandleTypeDef huart2;

static uint16_t adc_buffer[DMA_BUFFER_SIZE];

static volatile uint8_t half_ready = 0;
static volatile uint8_t full_ready = 0;
static volatile uint8_t capture_error = 0;

void SystemClock_Config(void);
static void MX_GPIO_Init(void);
static void MX_DMA_Init(void);
static void MX_ADC1_Init(void);
static void MX_TIM2_Init(void);
static void MX_USART2_UART_Init(void);
static void ADC1_DMA_Link(void);
void Error_Handler(void);

#define TIM2_START()  (TIM2->CR1 |= TIM_CR1_CEN)
#define TIM2_STOP()   (TIM2->CR1 &= ~TIM_CR1_CEN)

/* ADC DMA callbacks */
void HAL_ADC_ConvHalfCpltCallback(ADC_HandleTypeDef *hadc)
{
    if (hadc->Instance == ADC1) {
        half_ready = 1;
    }
}

void HAL_ADC_ConvCpltCallback(ADC_HandleTypeDef *hadc)
{
    if (hadc->Instance == ADC1) {
        full_ready = 1;
    }
}

void HAL_ADC_ErrorCallback(ADC_HandleTypeDef *hadc)
{
    if (hadc->Instance == ADC1) {
        capture_error = 1;
    }
}

/* Print text through USART2 */
static void UART_Print(const char *message)
{
    HAL_UART_Transmit(
        &huart2,
        (uint8_t *)message,
        (uint16_t)snprintf(NULL, 0, "%s", message),
        UART_TIMEOUT_MS
    );
}

/*
 * Analyze one 1024-sample window.
 * Prints peak-to-peak voltage and estimated voice pitch.
 */
static void Analyze_Audio_Window(const uint16_t *source)
{
    uint16_t minimum = ADC_MAX_VALUE;
    uint16_t maximum = 0U;
    uint32_t sum = 0U;

    /* Calculate mean, minimum and maximum ADC values */
    for (uint32_t i = 0; i < HALF_BUFFER_SIZE; i++) {
        uint16_t sample = source[i];

        sum += sample;

        if (sample < minimum) {
            minimum = sample;
        }

        if (sample > maximum) {
            maximum = sample;
        }
    }

    float mean = (float)sum / (float)HALF_BUFFER_SIZE;

    /* Convert ADC peak-to-peak counts to millivolts */
    uint32_t vpp_counts = (uint32_t)(maximum - minimum);

    uint32_t vpp_mV =
        (vpp_counts * ADC_REFERENCE_MV + ADC_MAX_VALUE / 2U)
        / ADC_MAX_VALUE;

    /*
     * Estimate the fundamental voice pitch using normalized
     * autocorrelation. The signal mean is removed mathematically.
     */
    float best_correlation = -1.0f;
    uint32_t best_lag = 0U;

    for (uint32_t lag = MIN_PITCH_LAG;
         lag <= MAX_PITCH_LAG;
         lag++) {

        float cross = 0.0f;
        float energy1 = 0.0f;
        float energy2 = 0.0f;

        for (uint32_t i = 0; i < HALF_BUFFER_SIZE - lag; i++) {
            float a = (float)source[i] - mean;
            float b = (float)source[i + lag] - mean;

            cross += a * b;
            energy1 += a * a;
            energy2 += b * b;
        }

        float denominator = sqrtf(energy1 * energy2);

        if (denominator > 0.0f) {
            float correlation = cross / denominator;

            if (correlation > best_correlation) {
                best_correlation = correlation;
                best_lag = lag;
            }
        }
    }

    uint32_t pitch_hz = 0U;

    if ((best_lag > 0U) &&
        (best_correlation >= MIN_CORRELATION)) {
        pitch_hz = SAMPLE_RATE_HZ / best_lag;
    }

    /* Avoid printf floating-point formatting */
    char message[128];

    if (pitch_hz > 0U) {
        int length = snprintf(
            message,
            sizeof(message),
            "Vpp: %lu mV | Estimated voice pitch: %lu Hz\r\n",
            (unsigned long)vpp_mV,
            (unsigned long)pitch_hz
        );

        if (length > 0) {
            if (HAL_UART_Transmit(
                    &huart2,
                    (uint8_t *)message,
                    (uint16_t)length,
                    UART_TIMEOUT_MS) != HAL_OK) {
                capture_error = 1;
            }
        }
    } else {
        int length = snprintf(
            message,
            sizeof(message),
            "Vpp: %lu mV | Voice pitch: no clear periodic signal\r\n",
            (unsigned long)vpp_mV
        );

        if (length > 0) {
            if (HAL_UART_Transmit(
                    &huart2,
                    (uint8_t *)message,
                    (uint16_t)length,
                    UART_TIMEOUT_MS) != HAL_OK) {
                capture_error = 1;
            }
        }
    }
}

int main(void)
{
    HAL_Init();
    SystemClock_Config();

    MX_GPIO_Init();
    MX_DMA_Init();
    MX_ADC1_Init();
    ADC1_DMA_Link();
    MX_TIM2_Init();
    MX_USART2_UART_Init();

    const char *banner =
        "\r\nMAX4466 Audio Measurement Started\r\n"
        "Sampling rate: 5000 Hz\r\n"
        "Window size: 1024 samples\r\n"
        "-----------------------------------\r\n";

    HAL_UART_Transmit(
        &huart2,
        (uint8_t *)banner,
        (uint16_t)snprintf(NULL, 0, "%s", banner),
        UART_TIMEOUT_MS
    );

    /* Start ADC with circular DMA */
    if (HAL_ADC_Start_DMA(
            &hadc1,
            (uint32_t *)adc_buffer,
            DMA_BUFFER_SIZE) != HAL_OK) {
        Error_Handler();
    }

    /* Start timer-triggered ADC sampling */
    TIM2_START();

    while (1) {
        if (capture_error) {
            TIM2_STOP();
            HAL_ADC_Stop_DMA(&hadc1);
            Error_Handler();
        }

        if (half_ready) {
            __disable_irq();
            half_ready = 0;
            __enable_irq();

            Analyze_Audio_Window(&adc_buffer[0]);
        }

        if (full_ready && !capture_error) {
            __disable_irq();
            full_ready = 0;
            __enable_irq();

            Analyze_Audio_Window(&adc_buffer[HALF_BUFFER_SIZE]);
        }
    }
}

/* System clock: HSI -> PLL -> 84 MHz */
void SystemClock_Config(void)
{
    RCC_OscInitTypeDef RCC_OscInitStruct = {0};
    RCC_ClkInitTypeDef RCC_ClkInitStruct = {0};

    __HAL_RCC_PWR_CLK_ENABLE();
    __HAL_PWR_VOLTAGESCALING_CONFIG(
        PWR_REGULATOR_VOLTAGE_SCALE2
    );

    RCC_OscInitStruct.OscillatorType = RCC_OSCILLATORTYPE_HSI;
    RCC_OscInitStruct.HSIState = RCC_HSI_ON;
    RCC_OscInitStruct.HSICalibrationValue =
        RCC_HSICALIBRATION_DEFAULT;

    RCC_OscInitStruct.PLL.PLLState = RCC_PLL_ON;
    RCC_OscInitStruct.PLL.PLLSource = RCC_PLLSOURCE_HSI;
    RCC_OscInitStruct.PLL.PLLM = 16;
    RCC_OscInitStruct.PLL.PLLN = 336;
    RCC_OscInitStruct.PLL.PLLP = RCC_PLLP_DIV4;
    RCC_OscInitStruct.PLL.PLLQ = 7;

    if (HAL_RCC_OscConfig(&RCC_OscInitStruct) != HAL_OK) {
        Error_Handler();
    }

    RCC_ClkInitStruct.ClockType =
        RCC_CLOCKTYPE_HCLK |
        RCC_CLOCKTYPE_SYSCLK |
        RCC_CLOCKTYPE_PCLK1 |
        RCC_CLOCKTYPE_PCLK2;

    RCC_ClkInitStruct.SYSCLKSource = RCC_SYSCLKSOURCE_PLLCLK;
    RCC_ClkInitStruct.AHBCLKDivider = RCC_SYSCLK_DIV1;
    RCC_ClkInitStruct.APB1CLKDivider = RCC_HCLK_DIV2;
    RCC_ClkInitStruct.APB2CLKDivider = RCC_HCLK_DIV1;

    if (HAL_RCC_ClockConfig(
            &RCC_ClkInitStruct,
            FLASH_LATENCY_2) != HAL_OK) {
        Error_Handler();
    }
}

/* ADC1: PA0 / ADC channel 0 */
static void MX_ADC1_Init(void)
{
    ADC_ChannelConfTypeDef sConfig = {0};

    hadc1.Instance = ADC1;
    hadc1.Init.ClockPrescaler = ADC_CLOCK_SYNC_PCLK_DIV4;
    hadc1.Init.Resolution = ADC_RESOLUTION_12B;
    hadc1.Init.ScanConvMode = DISABLE;
    hadc1.Init.ContinuousConvMode = DISABLE;
    hadc1.Init.DiscontinuousConvMode = DISABLE;
    hadc1.Init.ExternalTrigConvEdge =
        ADC_EXTERNALTRIGCONVEDGE_RISING;
    hadc1.Init.ExternalTrigConv = ADC_EXTERNALTRIGCONV_T2_TRGO;
    hadc1.Init.DataAlign = ADC_DATAALIGN_RIGHT;
    hadc1.Init.NbrOfConversion = 1;
    hadc1.Init.DMAContinuousRequests = ENABLE;
    hadc1.Init.EOCSelection = ADC_EOC_SINGLE_CONV;

    if (HAL_ADC_Init(&hadc1) != HAL_OK) {
        Error_Handler();
    }

    sConfig.Channel = ADC_CHANNEL_0;
    sConfig.Rank = 1;
    sConfig.SamplingTime = ADC_SAMPLETIME_84CYCLES;

    if (HAL_ADC_ConfigChannel(&hadc1, &sConfig) != HAL_OK) {
        Error_Handler();
    }
}

/* TIM2 update event triggers ADC at 5 kHz */
static void MX_TIM2_Init(void)
{
    __HAL_RCC_TIM2_CLK_ENABLE();

    TIM2->CR1 = 0;
    TIM2->PSC = 83;          /* 84 MHz / 84 = 1 MHz */
    TIM2->ARR = 199;         /* 1 MHz / 200 = 5 kHz */
    TIM2->CR2 = TIM_CR2_MMS_1;
    TIM2->EGR = TIM_EGR_UG;
    TIM2->SR = 0;
    TIM2->CNT = 0;
}

static void MX_USART2_UART_Init(void)
{
    huart2.Instance = USART2;
    huart2.Init.BaudRate = 115200;
    huart2.Init.WordLength = UART_WORDLENGTH_8B;
    huart2.Init.StopBits = UART_STOPBITS_1;
    huart2.Init.Parity = UART_PARITY_NONE;
    huart2.Init.Mode = UART_MODE_TX_RX;
    huart2.Init.HwFlowCtl = UART_HWCONTROL_NONE;
    huart2.Init.OverSampling = UART_OVERSAMPLING_16;

    if (HAL_UART_Init(&huart2) != HAL_OK) {
        Error_Handler();
    }
}

static void MX_DMA_Init(void)
{
    __HAL_RCC_DMA2_CLK_ENABLE();

    HAL_NVIC_SetPriority(DMA2_Stream0_IRQn, 0, 0);
    HAL_NVIC_EnableIRQ(DMA2_Stream0_IRQn);
}

/* DMA2 Stream0 Channel0: ADC1 */
static void ADC1_DMA_Link(void)
{
    if (hadc1.DMA_Handle != NULL) {
        return;
    }

    __HAL_RCC_DMA2_CLK_ENABLE();

    hdma_adc1.Instance = DMA2_Stream0;
    hdma_adc1.Init.Channel = DMA_CHANNEL_0;
    hdma_adc1.Init.Direction = DMA_PERIPH_TO_MEMORY;
    hdma_adc1.Init.PeriphInc = DMA_PINC_DISABLE;
    hdma_adc1.Init.MemInc = DMA_MINC_ENABLE;
    hdma_adc1.Init.PeriphDataAlignment = DMA_PDATAALIGN_HALFWORD;
    hdma_adc1.Init.MemDataAlignment = DMA_MDATAALIGN_HALFWORD;
    hdma_adc1.Init.Mode = DMA_CIRCULAR;
    hdma_adc1.Init.Priority = DMA_PRIORITY_HIGH;
    hdma_adc1.Init.FIFOMode = DMA_FIFOMODE_DISABLE;

    if (HAL_DMA_Init(&hdma_adc1) != HAL_OK) {
        Error_Handler();
    }

    __HAL_LINKDMA(&hadc1, DMA_Handle, hdma_adc1);
}

static void MX_GPIO_Init(void)
{
    GPIO_InitTypeDef GPIO_InitStruct = {0};

    __HAL_RCC_GPIOA_CLK_ENABLE();

    HAL_GPIO_WritePin(GPIOA, GPIO_PIN_5, GPIO_PIN_RESET);

    GPIO_InitStruct.Pin = GPIO_PIN_5;
    GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
    GPIO_InitStruct.Pull = GPIO_NOPULL;
    GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;

    HAL_GPIO_Init(GPIOA, &GPIO_InitStruct);
}

void DMA2_Stream0_IRQHandler(void)
{
    HAL_DMA_IRQHandler(&hdma_adc1);
}

void Error_Handler(void)
{
    __disable_irq();

    while (1) {
        HAL_GPIO_TogglePin(GPIOA, GPIO_PIN_5);

        for (volatile uint32_t i = 0;
             i < 1000000U;
             i++) {
        }
    }
}
