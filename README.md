# FM/DMB Repeater — FPGA 기반 디지털 중계기

> **지상파 DMB(174~216MHz) + FM 라디오(88~108MHz) 중계기**  
> FPGA 기반 디지털 신호 처리 (Xilinx Kintex-7 XC7K325T)  
> 40 FM 채널 + 6 DMB 채널 동시 처리

---

## 프로젝트 개요

본 프로젝트는 방송공동수신설비(헤드엔드)에서 전송된 신호를 수신하여 지하주차장, 지하상가, 터널 등 **전파 음영 지역**에 무선 재전송하는 FM/DMB 디지털 중계기의 **설계, 분석, FPGA RTL, 임베디드 SW**를 모두 포함하는 종합 설계 패키지입니다.

> **전파법 기준**: 특정소출력 무선기기 (FM: 10mW 이하)  
> **핵심 기술**: FPGA 기반 디지털 필터링 (CIC + FIR + ISOP) + AGC

---

## 전체 산출물 구조

### 설계 문서

| 파일 | 내용 |
|------|------|
| [`01-hardware-design.md`](01-hardware-design.md) | 하드웨어 설계 데이터 초안 — 시스템 블록도, FPGA 리소스, 필터 파라미터, PCB 가이드라인 |
| [`02-component-selection.md`](02-component-selection.md) | 부품 선정 및 BOM — FPGA, RF Front-End, ADC/DAC, PA, 전원부 ($595 BOM) |
| [`03-market-analysis.md`](03-market-analysis.md) | 국내 FM/DMB 리피터 시장 분석 — 15개 제품 비교, 5 Forces, 진입 전략 |
| [`04-system-topology.md`](04-system-topology.md) | 최상위 시스템 구성도 — 5계층 구조, 3가지 적용 예시, NMS, 법령 |
| [`05-reverse-engineering-bom.md`](05-reverse-engineering-bom.md) | 역설계(BOM 역추적) 비교표 — 3개 등급 부품 구성, 아날로그 vs FPGA BOM 비교 |
| [`06-fpga-prototype-cost-estimate.md`](06-fpga-prototype-cost-estimate.md) | FPGA 프로토타입 제작 비용 견적 — Phase 1~6, 총개발비 $73K~$135K |
| [`07-development-process.md`](07-development-process.md) | **개발 프로세스 정의** — V-Model + Agile, 코딩 표준, 3단계 코드 리뷰 체크리스트 |

### FPGA RTL 코드 (Verilog)

```
fpga/
├── rtl/
│   ├── clk_manager.v          # MMCM/PLL 클록 생성 (10MHz→80/200/100/25MHz)
│   ├── adc_interface.v        # AD9649 LVDS 수신 + IDELAYE2 + IDDR + CDC
│   ├── dac_interface.v        # AD9742 듀얼 DAC 드라이버
│   ├── spi_slave.v            # SPI 슬레이브 (Mode 0, 32-bit frame)
│   ├── uart_debug.v           # UART 115200 + CLI 프로세서
│   ├── sys_monitor.v          # I2C 온도센서 + VSWR + 알람
│   ├── ddc.v                  # DDS NCO + Complex Mixer
│   ├── cic_decimation.v       # CIC 데시메이션 필터 (파라미터화)
│   ├── fir_filter.v           # 대칭 FIR 필터 (프로그래머블 계수)
│   ├── isop.v                 # CIC 처짐 보상 필터
│   ├── agc.v                  # RMS 검출 + IIR 이득 제어
│   ├── duc.v                  # CIC 보간 + NCO 상향변환
│   ├── channel_sum.v          # 다채널 가산기 (최대 46ch)
│   ├── fm_channel.v           # FM 단일채널: DDC→CIC(693)→ISOP→AGC
│   ├── dmb_channel.v          # DMB 단일채널: DDC→CIC1→CIC2→FIR1→FIR2→ISOP→AGC
│   └── repeater_top.v         # ★ 최상위 통합 (40 FM + 6 DMB 채널)
├── sim/
│   └── tb_repeater_top.v      # FPGA 전체 시뮬레이션 testbench
```

### 임베디드 SW (STM32F429)

```
sw/
├── Core/Inc/
│   ├── fpga_regs.h            # FPGA 레지스터 맵 + NCO 주파수 계산
│   ├── spi_driver.h           # SPI 통신 드라이버
│   ├── cli.h                  # CLI 명령어 정의
│   └── sensor.h               # 센서 모니터링
├── Core/Src/
│   ├── main.c                 # 시스템 초기화 + 메인 루프
│   ├── spi_driver.c           # SPI 프레임 전송 구현
│   ├── cli.c                  # CLI 파서 + 9개 명령어
│   └── sensor.c               # 100ms 폴링 + 알람 처리
└── README.md
```

### PC 도구 (Python)

```
tools/
├── monitor_gui.py             # PyQt5 모니터링 대시보드
├── requirements.txt           # Python 의존성
└── test_scripts/
    └── README.md              # 테스트 스크립트 안내
```

---

## 시스템 핵심 사양

| 항목 | FM | T-DMB |
|------|:---:|:-----:|
| 주파수 대역 | 88 ~ 108 MHz | 174 ~ 216 MHz (Band-III) |
| 채널 대역폭 | 150 kHz | 1.536 MHz |
| 변조 방식 | FM | OFDM (DQPSK) |
| 동시 처리 채널 | **40 ch** | **6 ch** |
| 샘플링 | 14-bit @ 80 MSPS (AD9649) | |
| 출력 전력 | +10 dBm Driver / 외부 PA 확장 | |
| AGC 동적 범위 | > 50 dB | |
| AGC Attack/Release | < 10 ms / < 100 ms | < 5 us / < 10 ms |
| 필터 | CIC(R=693,N=6) + ISOP | CIC1+CIC2 + FIR1(47t) + FIR2(104t) + ISOP |
| FPGA 리소스 (추정) | Reg 29%, LUT 49%, DSP 57%, BRAM 40% | |
| 임피던스 | 50Ω (전 구간) | |

## FPGA 디지털 신호 처리 블록도

```
[수신 안테나] → [BPF] → [LNA] → [Down-Converter] → [ADC 14bit 80MSPS]
                                                         ↓
                                              [FPGA Kintex-7]
                                              ┌────────────────────────────┐
                                              │  40× FM Channel           │
                                              │    DDC→CIC(693)→ISOP→AGC  │ → FM SUM
                                              │                           │
                                              │   6× DMB Channel          │
                                              │    DDC→CIC1→CIC2→FIR1→    │ → DMB SUM
                                              │    FIR2→ISOP→AGC          │
                                              └────────────────────────────┘
                                                         ↓
[송신 안테나] ← [BPF] ← [PA] ← [Up-Converter] ← [DAC 12bit 210MSPS]
```

## 핵심 접근 방식

- **FPGA 기반 디지털 신호 처리** — 아날로그 단순 증폭 방식이 아닌 FPGA(CIC+FIR+ISOP) 기반 채널별 정밀 필터링
- **디지털 AGC** — RMS 검출 기반 이득 자동 제어 (FM: 10ms/100ms, DMB: 5us/10ms)
- **40 FM + 6 DMB 채널** — 단일 Kintex-7 FPGA에서 generate loop로 병렬 처리
- **SPI + UART 이중 제어 인터페이스** — STM32 MCU가 SPI로 고속 제어, UART CLI로 디버그

## 주요 설계 결정

| 결정 | 내용 |
|------|------|
| **FPGA 칩** | Xilinx Kintex-7 XC7K325T (326K LUT, 840 DSP, 445 BRAM) |
| **ADC** | AD9649 (14-bit, 80 MSPS, LVDS) — IF 샘플링 |
| **DAC** | AD9742 (12-bit, 210 MSPS) × 2 (FM/DMB 각각) |
| **프로토타입 BOM** | ~$595 (PCB NRE 제외, 양산 시 $350~$500) |
| **SPI 프로토콜** | 32-bit frame [CMD:8][ADDR:8][DATA:16], Mode 0, 12.5MHz |
| **개발 프로세스** | V-Model + Agile 하이브리드, 3단계 코드 리뷰 (Self/Peer/Walkthrough) |

## 시장 현황 (요약)

- **주력 가격대**: 33~45만원 (제품 간 기술 격차 거의 없음)
- **10개 이상 제조사** 경쟁 중인 레드오션
- **정부 규제 강화** (터널 재난방송 의무화 2025)로 시장 지속 성장
- **FPGA 디지털 리피터는 시장에 전무** — 차별화 포인트 확보 가능
- **BOM 부품비 대비 소비자가 비율**: 기존 제품 3~5% vs FPGA 방식 20~25%

## 코드 리뷰 요약

`07-development-process.md` 문서에 상세히 정의된 코드 리뷰 체계:

| 레벨 | 대상 | 주요 항목 |
|------|------|---------|
| **Self-Review** | 작성자 | Lint 통과, FSM reachable, CDC 검증, 시뮬레이션 통과 |
| **Peer Review** | 동료 | 네이밍/할당 규칙, Latch 여부, Saturation/Overflow, 파라미터화 |
| **Walkthrough** | 팀 | 주요 모듈(DDC, CIC, AGC) 전체 검토, 이슈 등록 |

> **도구**: Verilator, Vivado xvlog, ModelSim, Cppcheck, PC-Lint/MISRA-C

---

> **프로젝트 현황**: 설계 문서 7종 + FPGA RTL 16개 모듈 + Testbench 1개 + STM32 FW 8개 파일 + PC GUI 2개 (총 34개 파일)
>
> **차기 작업**:
> 1. Vivado 프로젝트 생성 → .xdc constraint → 합성/타이밍 검증
> 2. STM32CubeIDE .ioc 프로젝트 설정 → HAL 코드 생성
> 3. Python FIR 필터 계수 생성 (fdatool / Python 스크립트)
> 4. ModelSim/Vivado Sim 시뮬레이션 (CIC 주파수 응답, AGC 루프 안정성)
> 5. 하드웨어 테스트 계획 문서 (`08-hardware-test-plan.md`)
