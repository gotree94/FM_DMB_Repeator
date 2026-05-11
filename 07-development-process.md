# 개발 프로세스 정의 (Development Process Definition)

> FM/DMB 디지털 리피터 FPGA + STM32 펌웨어 개발 방법론  
> V-Model + Agile Hybrid Approach

---

## 1. 개발 방법론 개요

본 프로젝트는 V-Model의 체계적인 검증 단계와 Agile의 반복적 개발을 결합한 **하이브리드 방법론**을 적용한다.

### 1.1 V-Model 단계 (수직 축)

```
요구사항 분석 ────────────────── 시스템 인수 테스트
     │                                │
     ▼                                ▼
아키텍처 설계 ────────────────── 통합 테스트
     │                                │
     ▼                                ▼
상세 설계 ────────────────────── 단위 테스트
     │                                │
     ▼                                ▼
     └──────── 구현 ─────────┘
```

### 1.2 Agile 반복 (수평 축)

각 V-Model 단계는 1~2주 Sprint로 세분화:
- **Sprint 0**: 환경 설정, 코딩 표준 정의
- **Sprint 1~N**: Wave 기반 FPGA 모듈 구현
- **Sprint N+1**: 통합 및 검증

---

## 2. 코딩 표준

### 2.1 Verilog RTL 코딩 표준

#### 명명 규칙
| 항목 | 규칙 | 예시 |
|------|------|------|
| 포트 (input) | `i_` 접두사 + snake_case | `i_clk`, `i_rst_n` |
| 포트 (output) | `o_` 접두사 + snake_case | `o_data`, `o_valid` |
| 포트 (inout) | `io_` 접두사 + snake_case | `io_sda` |
| 내부 wire | snake_case | `fifo_wr_en`, `data_valid` |
| 내부 reg | snake_case | `state_reg`, `acc_reg` |
| 파라미터 | UPPER_SNAKE_CASE | `CIC_R`, `ACCUM_WIDTH` |
| 로컬파라미터 | UPPER_SNAKE_CASE | `IDLE`, `WAIT_STATE` |
| 모듈 이름 | snake_case | `cic_decimation`, `spi_slave` |
| 파일 이름 | 모듈명과 동일 | `cic_decimation.v` |

#### 코딩 규칙
1. **동기식 리셋 사용** — 비동기 리셋 금지
2. **Blocking assignment (=)**: 조합 논리(always @*)에만 사용
3. **Non-blocking assignment (<=)**: 순차 논리(always @(posedge clk))에만 사용
4. **Latch 금지**: 모든 `always @*` 블록은 모든 조건에서 모든 출력 할당 필수
5. **FSM**: 3 always 블록 방식 (상태 천이, 다음 상태, 출력)
6. **CDC (Clock Domain Crossing)**: 2-FF synchronizer 또는 async FIFO (Gray Code) 필수
7. **레지스터**: SPI/UART를 통해 접근 가능한 레지스터는 `o_reg_*` 형태로顶层(top)까지 연결
8. **Generate**: 반복 구조는 `generate for` 사용, 하드코딩 금지
9. **매직 넘버 금지**: 모든 상수는 `localparam`으로 정의

#### 금지 패턴
- `as any`, `@ts-ignore` (해당 없음 — Verilog)
- Latch 생성 코드
- `#delay` 시뮬레이션 전용 — 합성 가능 코드에서는 사용 금지
- incomplete sensitivity list

### 2.2 C 언어 (STM32) 코딩 표준

#### 명명 규칙
| 항목 | 규칙 | 예시 |
|------|------|------|
| 함수 | snake_case | `spi_write_reg`, `cli_process` |
| 변수 | snake_case | `reg_value`, `timeout_ms` |
| 상수/매크로 | UPPER_SNAKE_CASE | `SPI_TIMEOUT_MS`, `FPGA_NCO_FREQ` |
| 타입 정의 | `_t` 접미사 | `spi_status_t`, `alarm_callback_t` |
| 파일 이름 | snake_case | `spi_driver.c`, `fpga_regs.h` |
| 전역 변수 | `g_` 접두사 | `g_fpga_ready`, `g_alarm_flags` |

#### 규칙
1. **MISRA-C 준수** (필수 규칙: 8.2, 10.1, 11.3, 13.2, 14.4, 15.5, 16.7, 17.4, 18.4)
2. **동적 메모리 할당 금지** (malloc/free 사용 금지)
3. **HAL 드라이버 기반** — 레지스터 직접 접근 금지
4. **인터럽트 서비스 루틴 (ISR)**: 최소 처리, 플래그 설정만 수행
5. **Blocking wait 금지**: 폴링은 TIM 타임아웃 기반
6. **assert() 사용**: 계약에 의한 설계 (Design by Contract)
7. **전역 변수 최소화**: 모듈별로 파일 static 변수 사용
8. **함수 길이**: 60라인 이내 (예외: main 초기화)

---

## 3. 모듈 계층 구조

### 3.1 FPGA 모듈 계층 (Dependency Order)

```
Wave 1 — 독립 모듈 (타 모듈 의존 없음)
├── clk_manager.v       — MMCM/PLL 클록 생성
├── adc_interface.v     — ADC LVDS 수신 + CDC
├── dac_interface.v     — DAC 드라이버
├── spi_slave.v        — SPI 슬레이브 프로토콜
├── uart_debug.v       — UART + CLI 엔진
└── sys_monitor.v      — I2C 센서 + VSWR + 알람

Wave 2 — DSP 코어 모듈
├── ddc.v              — DDS NCO + Complex Mixer
├── cic_decimation.v   — CIC 데시메이션 (파라미터화)
├── fir_filter.v       — 대칭 FIR (프로그래머블 계수)
├── isop.v             — CIC 처짐 보상 필터
├── agc.v              — RMS + IIR 이득 제어
├── duc.v              — CIC 보간 + NCO 상향변환
└── channel_sum.v      — 다채널 가산기

Wave 3 — 통합 모듈
├── fm_channel.v       — FM 체인: DDC→CIC→ISOP→AGC
├── dmb_channel.v      — DMB 체인: DDC→CIC→CIC→FIR→FIR→ISOP→AGC
└── repeater_top.v     — ★ 최상위 통합 (40 FM + 6 DMB)

Testbench
└── tb_repeater_top.v  — FPGA 전체 시뮬레이션
```

### 3.2 STM32 SW 모듈 계층

```
Application Layer
├── main.c             — Init + Main Loop
├── cli.c / cli.h      — CLI 명령어 처리
└── sensor.c / sensor.h— 센서 폴링 + 알람

HAL Abstraction Layer
├── spi_driver.c / spi_driver.h  — SPI 통신
└── fpga_regs.h                   — FPGA 레지스터 맵

HAL (STM32 HAL Library)
├── SPI2               — FPGA 제어 인터페이스
├── USART3             — CLI 디버그 포트
├── TIM6               — 100ms 폴링 타이머
└── I2C1               — (예비) 온칩 센서
```

---

## 4. 코드 리뷰 체크리스트

### 4.1 Author Self-Review (작성자, 제출 전)

#### Verilog
- [ ] Lint clean (Verilator, no warnings)
- [ ] 모든 `always @*` 블록이 모든 경로에서 출력을 할당하는가? (Latch 여부)
- [ ] `always @(posedge clk)` 블록에 `<=` 사용 확인
- [ ] CDC 경로 식별 및 2-FF synchronizer 적용 확인
- [ ] FSM의 모든 상태 천이가 도달 가능한가? (Dead state 없음)
- [ ] 내부 신호 폭(Signal width)이 모든 연산에 충분한가? (Overflow 고려)
- [ ] Parameter overflow: CIC accumulator width 확인
- [ ] Module port map 순서가 정의와 일치하는가? (.name() 연결 권장)
- [ ] `default` 문법 오류 없음

#### C (STM32)
- [ ] 컴파일 경고 없음 (Wall -Wextra)
- [ ] HAL 함수 반환 값 검사 (HAL_OK 확인)
- [ ] 포인터 NULL 검사 (함수 인자)
- [ ] 배열 경계 검사 (strncpy, snprintf 사용)
- [ ] 블로킹 코드 없음 (타임아웃 설정 확인)
- [ ] MISRA-C 위반 항목 기록

### 4.2 Peer Review (동료, PR 단위)

#### Verilog
- [ ] 네이밍 컨벤션 일치 (i_/o_, snake_case)
- [ ] Latch 가능성 2차 검토
- [ ] CDC 검증 (Synopsys CDC 또는 수동 검증)
- [ ] 리소스 사용량 검토 (슬라이스, DSP48, BRAM)
- [ ] 타이밍 크리티컬 패스 식별
- [ ] State machine encoding (One-hot vs Binary) 적절성

#### C
- [ ] 정적 분석 (Cppcheck) 통과
- [ ] 매직 넘버 사용 검토
- [ ] 코드 중복 (DRY 원칙)
- [ ] 함수 복잡도 (Cyclomatic complexity < 10)
- [ ] 리소스 사용량 (Stack, Code size)

### 4.3 Integration Walkthrough (팀, 통합 전)

- [ ] Top-level port map 일관성
- [ ] 레지스터 주소 맵 conflict 없음
- [ ] SPI 프로토콜 호환성 (FPGA ↔ STM32)
- [ ] 시스템 타이밍 예산 (Setup/Hold)
- [ ] 전력 소모 추정
- [ ] 비기능 요구사항 만족 (온도, VSWR, 알람)

---

## 5. 실행 순서 (Wave 기반)

### Wave 1: Independent Modules
```
Step 1: clk_manager.v — Verify MMCM lock, all clock outputs
Step 2: adc_interface.v — Verify IDELAY calibration, FIFO CDC
Step 3: dac_interface.v — Verify pipeline, underrun detect
Step 4: spi_slave.v — Verify r/w protocol, register file access
Step 5: uart_debug.v — Verify baud rate, CLI commands
Step 6: sys_monitor.v — Verify I2C bit-bang, VSWR calculation
```

### Wave 2: DSP Core Modules
```
Step 7: ddc.v — Verify NCO frequency accuracy, SFDR
Step 8: cic_decimation.v — Verify frequency response, droop
Step 9: fir_filter.v — Verify coefficient loading, filter response
Step 10: isop.v — Verify droop compensation, pipeline
Step 11: agc.v — Verify attack/release time, loop stability
Step 12: duc.v — Verify interpolation, image rejection
Step 13: channel_sum.v — Verify adder tree, saturation
```

### Wave 3: Integration
```
Step 14: fm_channel.v — Verify FM chain end-to-end
Step 15: dmb_channel.v — Verify DMB chain end-to-end
Step 16: repeater_top.v — Full system simulation
Step 17: tb_repeater_top.v — Run testbench, verify all channels
```

---

## 6. 정적 분석 도구

| 도구 | 대상 | 적용 시점 | 주요 검출 항목 |
|------|------|-----------|-------------|
| **Verilator** | Verilog RTL | Lint (wave 단위) | 상수 폭 mismatch, 미할당 신호, Latch |
| **Vivado xvlog** | Verilog RTL | 합성 전 | 문법 오류, 포트 불일치 |
| **ModelSim vcom** | VHDL (필요시) | — | — |
| **Cppcheck** | C 코드 | PR 전 | 버퍼 오버런, 널 포인터, MISRA 위반 |
| **PC-Lint** | C 코드 | 정기적 | MISRA-C 전체 규칙 |
| **GCC -Wall -Wextra** | C 코드 | 빌드 시 | 모든 경고 |

---

## 7. 시뮬레이션 및 검증 방법

### 7.1 단위 시뮬레이션 (Wave 1)
- 각 모듈별 자체 testbench
- 클록/리셋 시퀀스
- 경계값 테스트
- 코드 커버리지 90% 이상 목표

### 7.2 통합 시뮬레이션 (Wave 3)
- `tb_repeater_top.v` — 전체 채널 동시 시뮬레이션
- ADC DCO DDR 모사
- SPI write/read 시퀀스
- CIC 주파수 응답 검증
- AGC 루프 안정성 검증

### 7.3 HIL (Hardware-in-the-Loop)
- FPGA 보드 + STM32 보드 연결
- 실제 RF 신호 입력 (Signal Generator)
- 스펙트럼 분석기로 출력 검증
- 장시간 안정성 테스트 (24시간)

---

## 8. 산출물 구조

```
D:\github\FM_DMB_Repeator\
├── 01-hardware-design.md          # 하드웨어 설계
├── 02-component-selection.md      # 부품 BOM
├── 03-market-analysis.md          # 시장 분석
├── 04-system-topology.md          # 시스템 구성도
├── 05-reverse-engineering-bom.md  # 역설계 비교표
├── 06-fpga-prototype-cost-estimate.md  # 비용 견적
├── 07-development-process.md      # ★ 개발 프로세스 (이 파일)
├── README.md                      # 프로젝트 개요
├── fpga/
│   ├── rtl/                       # FPGA RTL (17개 모듈)
│   └── sim/                       # Testbench
├── sw/
│   └── Core/
│       ├── Inc/                   # STM32 헤더
│       └── Src/                   # STM32 소스
├── tools/
│   ├── monitor_gui.py             # PC 모니터링 GUI
│   └── requirements.txt           # Python 의존성
└── .sisyphus/                     # Sisyphus 작업 계획
```

---

## 9. 문서 변경 이력

| Rev | 일자 | 변경 내용 | 작성자 |
|-----|------|-----------|--------|
| 1.0 | 2026-05-12 | 최초 작성 — V-Model + Agile, 코딩 표준, 리뷰 체크리스트 | Sisyphus |
