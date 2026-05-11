# FM/DMB Repeater — 하드웨어 설계 데이터 초안

> FPGA 기반 디지털 신호 처리를 통한 다채널 FM(40ch) + DMB(6ch) 중계기 설계

---

## 1. 시스템 요구사항 및 사양 정의

### 1.1 동작 주파수 대역

| 항목 | FM | T-DMB |
|---|---|---|
| 주파수 대역 | 88 ~ 108 MHz | 174 ~ 216 MHz (Band-III) |
| 채널 대역폭 | 150 kHz | 1.536 MHz |
| 변조 방식 | FM (주파수 변조) | OFDM (DQPSK) |
| 표준 | — | ETSI EN 300 401 (DAB 기반), IEC 62516-1 |

### 1.2 성능 목표

| 파라미터 | 목표값 | 비고 |
|---|---|---|
| 동시 처리 채널 수 | FM 40ch + DMB 6ch | FPGA 기반 |
| RF 입력 레벨 범위 | -85 ~ -40 dBm | |
| 출력 전력 | +10 dBm (Driver) / 외부 PA로 확장 | |
| NF (Noise Figure) | < 5 dB (전체 경로) | LNA NF < 1.5 dB |
| AGC 동적 범위 | > 50 dB | |
| 인접 채널 선택도 | > 60 dB | CIC + FIR + ISOP 필터 |
| 지연 시간 | < 20 μs | FPGA 처리 |
| 임피던스 | 50Ω (전 구간) | |

### 1.3 한국 전파법 준수

- **특정소출력 무선기기** 기준: FM 88-108MHz, 출력 10mW 이하
- 10mW 초과 중계기는 **무선국 허가** 필요
- KC 인증 (적합성평가) 필수
- 재난방송 중계기 성능평가시험: **한국전파진흥협회(RAPA)**

---

## 2. 시스템 블록도

```
[수신 안테나] → [BPF] → [LNA] → [Down-Converter] → [ADC]
                                                        ↓
                                              [FPGA (Digital Core)]
                                              ┌──────────────────────┐
                                              │  DDC → CIC/FIR/ISOP  │
                                              │  → AGC → DUC         │
                                              │  (40 FM + 6 DMB ch)  │
                                              └──────────────────────┘
                                                        ↓
[송신 안테나] ← [BPF] ← [PA] ← [Up-Converter] ← [DAC]
```

### 2.1 세부 기능 블록

#### RF 프론트엔드 (RF Front-End)

| 블록 | 기능 |
|---|---|
| **수신 BPF** | 대역 외 신호 제거 (FM: 88-108MHz, DMB: 174-216MHz) |
| **LNA** | 저잡음 증폭, NF < 1.5dB @ 각 대역 |
| **RF Down-Converter** | IF (20MHz) 또는 Zero-IF로 주파수 하향 변환 |
| **ADC** | 14-bit, 80MSPS, IF 샘플링 |

#### 디지털 신호 처리부 (Digital Core — FPGA)

| 블록 | 기능 |
|---|---|
| **DDC (Digital Down Converter)** | NCO 기반 주파수 하향 변환 |
| **CIC 필터 (Cascaded Integrator Comb)** | 데시메이션 (FM: R=693, DMB: R=5) |
| **FIR 필터** | 채널 선택 필터링 (DMB: 47 tap / 104 tap) |
| **ISOP 필터** | 통과대역 처짐 보상 |
| **AGC (Automatic Gain Controller)** | 출력 레벨 일정 유지 |
| **DUC (Digital Up Converter)** | 주파수 상향 변환 |

#### RF 송신부 (RF Transmit Chain)

| 블록 | 기능 |
|---|---|
| **DAC** | 12-bit, 210MSPS, 디지털→아날로그 변환 |
| **RF Up-Converter** | 송신 주파수로 상향 변환 |
| **PA (Power Amplifier)** | 전력 증폭 (+10dBm Driver → 외부 PA) |
| **송신 BPF** | 고조파 제거 (7차 Chebyshev LPF) |

---

## 3. FPGA 디지털 신호 처리 상세

### 3.1 FPGA 리소스 예상 사용량 (Xilinx Kintex-7 XC7K325T)

| 리소스 | 사용 예상량 | 가용량 | 사용률 |
|---|---|---|---|
| Slice Registers | 120,000 | 408,000 | 29% |
| Slice LUTs | 100,000 | 204,000 | 49% |
| DSP48E1 | 480 | 840 | 57% |
| Block RAM (36Kb) | 180 | 445 | 40% |
| MMCM/PLL | 3 | 6 | 50% |

> **소규모 대안**: Artix-7 XC7A200T (비용 절감) | **SoC 대안**: Zynq-7000 (CPU 내장)

### 3.2 디지털 필터 파라미터

| 용도 | 필터 | R (Decimation/Interpolation) | 스테이지 수 | Tap 수 | 비고 |
|---|---|---|---|---|---|
| FM | CIC | 693 | 6 | — | 큰 감쇠, 단일 스테이지 |
| DMB | CIC1 | 5 | 5 | — | 1차 데시메이션 |
| DMB | CIC2 | 5 | 4 | — | 2차 데시메이션 |
| DMB | FIR1 | 2 | — | 47 | 정밀 채널 선택 |
| DMB | FIR2 | 1 | — | 104 | 통과대역 평탄화 |
| FM+DMB | ISOP | 1 | 2 | — | 처짐 보상 (계수=-10) |

> 참고: MDPI Electronics (2019) — "Efficient Implementation of Multichannel FM and T-DMB Repeater in FPGA with Automatic Gain Controller"

### 3.3 AGC 설계 파라미터

| 항목 | FM | DMB |
|---|---|---|
| 출력 목표 레벨 | -10 dBm (고정) | -10 dBm (고정) |
| 동적 범위 | 0 ~ -60 dB 입력 대응 | 0 ~ -50 dB 입력 대응 |
| Attack Time | < 10 ms | < 5 μs (null symbol 활용) |
| Release Time | < 100 ms | < 10 ms |
| 측정 방식 | RMS 레벨 | OFDM 심볼 파워 |

### 3.4 클록 구조

```
┌──────────┐    10MHz Ref
│ Si5338   ├──────────→ FPGA (MMCM → 80MHz ADC CLK)
│ (PLL)    ├──────────→ ADC CLK (80MHz)
│          ├──────────→ DAC CLK (80MHz)
│          ├──────────→ Ethernet PHY (25MHz)
└──────────┘
```

---

## 4. PCB 레이아웃 가이드라인

| 항목 | 내용 |
|---|---|
| **레이어** | 6층 (Top-GND-Signal-PWR-GND-Bot) |
| **임피던스** | 50Ω 마이크로스트립 (FR4, εr=4.5, 두께 1.6mm → 선폭 약 0.6mm) |
| **RF 분리** | RF 섹션(FM / DMB / 송신 / 수신)을 쉴딩 캔으로 물리 분리 |
| **아날로그-디지털 분리** | ADC/DAC 주변 아날로그 영역과 FPGA 디지털 영역 슬롯 분리 |
| **전원 분리** | RF 전원(LDO)과 디지털 전원(DC-DC) 개별 레귤레이션 스테이지 |
| **열 관리** | FPGA + PA 히트싱크, 시스템 팬 강제 공랭 |
| **접지** | 스타 접지 방식, RF GND 플레인 완전 분리 후 싱글 포인트 연결 |

---

## 5. 시험 및 검증 계획

### 5.1 측정 항목

| 항목 | 장비 | 목표 |
|---|---|---|
| 주파수 응답 | VNA (Vector Network Analyzer) | ±1dB 이내 평탄도 |
| 출력 전력 | Spectrum Analyzer + Power Meter | 설계값 ±0.5dB |
| NF (잡음지수) | Noise Figure Meter | < 5dB |
| EVM (DMB) | Vector Signal Analyzer | < 5% |
| THD/IMD | Spectrum Analyzer | -40dBc 이하 |
| AGC 특성 | Signal Generator + Scope | 레벨 안정화 ±1dB |

### 5.2 EMC/EMI

- 전도 방출: CISPR 22 / EN 55022 Class B
- 방사 방출: CISPR 22 / EN 55022 Class B
- 내성: IEC 61000-4-2 (ESD), IEC 61000-4-4 (EFT)

---

## 6. 개발 로드맵

```
Phase 1: 설계 검증 (4-6주)
  ├── RF Front-End 시뮬레이션 (ADS, Genesys)
  ├── FPGA DSP 알고리즘 (MATLAB → Simulink HDL Coder)
  └── 부품 샘플 확보

Phase 2: 프로토타입 (8-10주)
  ├── PCB 설계 (Altium / KiCad / OrCAD)
  ├── FPGA RTL 구현 (Verilog HDL)
  └── 기구 설계 (함체 및 냉각)

Phase 3: 시험 및 인증 (4-6주)
  ├── RF 성능 측정
  ├── EMC/EMI 시험
  └── KC 전파법 인증

Phase 4: 양산 (6-8주)
  ├── 최종 BOM 확정
  ├── 조립 공정 설계
  └── 생산 테스트 장비 구축
```

---

## 7. 주요 리스크 및 고려사항

| 리스크 | 대응 방안 |
|---|---|
| **FPGA 설계 난이도** | Xilinx Vivado + IP Core (FIR, NCO/DDS) 활용 |
| **RF 레이아웃** | ADS/HFSS 시뮬레이션 선행, 경험자 검토 |
| **법적 사항** | KC 인증 / RAPA 성능평가 조기 진행 |
| **열 관리** | PA 출력에 따른 방열 설계 (공랭/수랭) |
| **비용** | 소규모: Artix-7 + RA30H1317M PA 모듈 대체 가능 |

---

> **참고 문헌**
> - MDPI Electronics 2019, "Efficient Implementation of Multichannel FM and T-DMB Repeater in FPGA with Automatic Gain Controller"
> - BBC R&D WHP120, "On-channel repeater for DAB"
> - NXP MRFE6VP61K25H FM Broadcast Reference Design
