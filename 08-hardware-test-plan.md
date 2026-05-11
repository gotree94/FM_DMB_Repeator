# 하드웨어 테스트 계획 (Hardware Test Plan)

> FM/DMB 디지털 리피터 — FPGA 보드 + RF Front-End 검증 절차

---

## 1. 테스트 단계 개요

| Phase | 내용 | 기간 | 비고 |
|-------|------|------|------|
| **Phase 0** | 전원 및 기본 동작 검증 | 1일 | Board bring-up |
| **Phase 1** | FPGA 기능 검증 (SPI, Clock, ADC/DAC Loopback) | 2일 | JTAG + Logic Analyzer |
| **Phase 2** | DSP 단위 검증 (DDC, CIC, FIR, AGC) | 3일 | ChipScope ILA |
| **Phase 3** | RF Front-End 검증 (LNA, Mixer, PA) | 2일 | Spectrum Analyzer |
| **Phase 4** | 통합 시스템 검증 (FM 40ch + DMB 6ch) | 3일 | Signal Generator + SA |
| **Phase 5** | 장기 안정성 테스트 (24시간 번인) | 5일 | 온도/VSWR 모니터링 |

---

## 2. Phase 0: Board Bring-Up

### 2.1 전원 시퀀스 검증

| 전압 | 예상 | 측정 | 리플 (50mVpp 이하) |
|------|------|------|-------------------|
| 12V_IN | 12.0V | _____ | _____ |
| 3.3V_FPGA | 3.3V | _____ | _____ |
| 1.8V_FPGA | 1.8V | _____ | _____ |
| 1.0V_CORE | 1.0V | _____ | _____ |
| 2.5V_DDR | 2.5V | _____ | _____ |
| 3.3V_ADC | 3.3V | _____ | _____ |
| 1.8V_ADC | 1.8V | _____ | _____ |
| 5.0V_PA | 5.0V | _____ | _____ |

**전원 시퀀스**: 12V_IN → 3.3V → 1.8V → 1.0V_CORE (100ms 간격)

### 2.2 클록 검증

| 신호 | 주파수 | 예상 | 측정 | 허용 오차 |
|------|--------|------|------|-----------|
| REFCLK (X1) | 10.000 MHz | LVDS | _____ | ±50ppm |
| SYS_CLK (MMCM) | 80.000 MHz | _____ | _____ | ±100ppm |
| IDELAY_CLK | 200.000 MHz | _____ | _____ | ±100ppm |
| SPI_CLK | 100.000 MHz | _____ | _____ | ±100ppm |
| CLK_12M8 | 12.800 MHz | _____ | _____ | ±100ppm |
| ADC_DCO | 80.000 MHz | DDR LVDS | _____ | ±100ppm |

### 2.3 FPGA Configuration

- [ ] JTAG 연결 확인 (Vivado Hardware Manager)
- [ ] MMCM Lock 확인 (LED 또는 SPI read)
- [ ] SPI 통신 확인 (scratch register R/W: 0xA5A5)
- [ ] UART 콘솔 출력 확인 (115200 8N1)

---

## 3. Phase 1: FPGA Functional Verification

### 3.1 SPI Register Test

| 테스트 | 절차 | 기대 결과 |
|--------|------|-----------|
| Scratch R/W | `wr 0x04 0xA5A5` → `rd 0x04` | Readback = 0xA5A5 |
| Boundary | `wr 0x04 0x0000` → `rd 0x04` | Readback = 0x0000 |
| Boundary | `wr 0x04 0xFFFF` → `rd 0x04` | Readback = 0xFFFF |
| Burst read | `rd 0x60` ~ `rd 0x66` | 7 monitoring regs |

### 3.2 ADC Loopback Test

1. ADC 입력에 1MHz sine (500mVpp) 인가 (Signal Generator)
2. ChipScope ILA로 `adc_data[13:0]` 캡처
3. FFT 계산으로 SINAD/ENOB 확인

### 3.3 DAC Loopback Test

1. FPGA 내부 sine generator를 DAC 출력으로 연결
2. DAC 출력을 오실로스코프로 측정
3. SFDR 측정 (12-bit → >60dB 기대)

---

## 4. Phase 2: DSP Unit Verification

### 4.1 DDC (NCO + Mixer)

| 테스트 | 입력 | NCO 주파수 | 기대 출력 |
|--------|------|------------|-----------|
| NCO 정확도 | — | 20 MHz | `phase_inc = 0x40000000` |
| DC 입력 | 0x0000 | 20 MHz | I/Q = 0 |
| CW 입력 | 10 MHz | 10 MHz | I=0x7FFF, Q=0 (DC) |
| CW 입력 | 12 MHz | 10 MHz | I/Q = 2MHz beat |

### 4.2 CIC Decimation

| 테스트 | FM 경로 | DMB 경로 |
|--------|---------|----------|
| Decimation ratio | R=693 | R=5 → R=5 |
| Stages | N=6 | N=5 → N=4 |
| Accumulator width | 56-bit | 28-bit → 24-bit |
| Passband droop (@BW_edge) | <1dB | <0.5dB |
| Aliasing rejection | >60dB | >60dB |

### 4.3 FIR Filter

| 파라미터 | FM | DMB FIR1 | DMB FIR2 |
|----------|-----|----------|----------|
| Taps | — | 47 | 104 |
| Decimation | — | ×2 | ×1 |
| Coefficients | — | SPI-loadable | SPI-loadable |
| Passband ripple | — | <0.1dB | <0.1dB |
| Stopband attenuation | — | >40dB | >60dB |

### 4.4 AGC Loop

| 파라미터 | FM | DMB |
|----------|-----|-----|
| Attack time | <10ms | <5us |
| Release time | <100ms | <10ms |
| Dynamic range | >50dB | >50dB |
| Gain clamp | [0x0080, 0x7FFF] | [0x0080, 0x7FFF] |

**AGC 검증**: 20dB input step → 출력이 90% 정착 시간 측정

---

## 5. Phase 3: RF Front-End Verification

### 5.1 LNA

| 항목 | FM (88~108MHz) | DMB (174~216MHz) |
|------|----------------|-------------------|
| Gain | 15dB | 15dB |
| NF | <2dB | <2dB |
| IIP3 | >10dBm | >10dBm |

### 5.2 Down-Converter

- [ ] LO 주파수 정확도 (±10ppm)
- [ ] 이미지 리젝션 >40dB (SA로 측정)
- [ ] 변환 이득 >5dB
- [ ] I/Q 위상 오차 <5°

### 5.3 Power Amplifier

| 항목 | 조건 | 기대값 |
|------|------|--------|
| 출력 전력 | CW | +10dBm |
| 이득 | — | 20dB |
| OIP3 | f1±f2=1MHz | >+30dBm |
| VSWR 내성 | 개방/단락 | >5:1 |
| 효율 | @Pout=+10dBm | >30% |

---

## 6. Phase 4: Integrated System Test

### 6.1 FM 40채널 동시 처리

| 테스트 | 절차 | 기대 |
|--------|------|------|
| 채널 선택도 | CH0=98.1MHz 입력, 타채널 확인 | 인접채널 >60dB 억압 |
| 다중채널 | 40채널 동시 CW 입력 | 출력 합산 정상 |
| AGC 상호작용 | CH5 입력 -80dBm → -30dBm 스텝 | 타채널 간섭 <1dB |

### 6.2 DMB 6채널 동시 처리

| 테스트 | 절차 | 기대 |
|--------|------|------|
| 채널 선택도 | CH0=184MHz (OFDM) 입력 | 인접채널 >50dB 억압 |
| EVM | OFDM demodulator로 EVM 측정 | <5% (with AGC) |

### 6.3 FM+DMB 동시 동작

- [ ] FM 40ch + DMB 6ch 동시 가동 (총 46채널)
- [ ] FPGA 리소스 모니터링 (온도, 전류)
- [ ] 채널 간 누화 < -70dB
- [ ] DAC 출력 스펙트럼 마스크 준수

---

## 7. Phase 5: 24시간 번인 테스트

### 7.1 조건

| 조건 | 설정 |
|------|------|
| 온도 | 25°C ±5°C (상온) |
| FM 입력 | 98.1MHz, -50dBm (CW) |
| DMB 입력 | 184MHz, -50dBm (OFDM) |
| 출력 부하 | 50Ω, 10W rated |
| 모니터링 | 온도 1초 간격 로깅 |

### 7.2 합격 기준

| 항목 | 기준 |
|------|------|
| FPGA 온도 | <85°C (지속) |
| VSWR | <2.0:1 (지속) |
| 출력 전력 변동 | ±1dB 이내 |
| 알람 발생 | 0회 (아무 알람 없음) |

---

## 8. 테스트 장비 목록

| 장비 | 용도 | 비고 |
|------|------|------|
| Spectrum Analyzer | RF 스펙트럼, SFDR, ACPR | 9kHz~3GHz |
| Signal Generator | CW, OFDM 변조 신호 | 88~216MHz |
| Oscilloscope | ADC/DAC 파형, 클록 | 500MHz, 4ch |
| Logic Analyzer | SPI/UART 디코딩 | — |
| Power Supply | 12V, 3A | 조정 가능 |
| Power Meter | RF 출력 전력 | 1MHz~3GHz |
| VNA (Vector Network Analyzer) | 임피던스 정합, S11 | 선택 사항 |

---

## 9. RF 보드 레이아웃 가이드라인

### 9.1 PCB 적층 (8-layer 권장)

| Layer | 내용 | 비고 |
|-------|------|------|
| L1 (Top) | RF components | 50Ω controlled impedance |
| L2 | GND plane | Solid, no splits |
| L3 | Analog signals | ADC/DAC routing |
| L4 | Power (3.3V, 1.8V) | — |
| L5 | GND plane | — |
| L6 | Digital signals | FPGA routing |
| L7 | Power (1.0V_CORE) | High current |
| L8 (Bottom) | Aux signals, GPIO | — |

### 9.2 RF 설계 규칙

| 항목 | 규칙 |
|------|------|
| 임피던스 | 50Ω ±5% |
| RF trace width | Er=4.5, h=0.2mm → ~0.35mm (microstrip) |
| RF via count | 0 (RF 경로 내 via 금지) |
| Keep-out zone | RF 아래 GND solid, 다른 신호 배선 금지 |
| Isolation | FM ↔ DMB 경로 20dB 분리 |

### 9.3 FPGA 라우팅

| 신호 | 규칙 |
|------|------|
| LVDS (ADC) | Differential impedance 100Ω, 길이 정합 ±5mm |
| DAC data | 최대 5mm 스큐, GND 레퍼런스 |
| SPI | 22Ω series termination near FPGA |
| UART | 100nF bypass near connector |

### 9.4 전원부

- 1.0V_CORE: 3A 이상, 벅 컨버터 (Switching freq >500kHz)
- FPGA 전원 시퀀서 필요 (TPS3808 또는 유사)
- 아날로그/디지털 GND 분리 (Ferrite bead bridge)
- ADC 공급 전원: LC 필터 (10uH + 10uF)

---

## 10. 테스트 결과 기록 양식

```
테스트 일자: _______________
테스트 담당: _______________
보드 리비전: _______________
FPGA 비트스트림: _________
FW 버전: _________________

### Phase 0 결과
- 전원 검증: PASS / FAIL (비고: _______________)
- 클록 검증: PASS / FAIL (비고: _______________)
- FPGA Config: PASS / FAIL (비고: _______________)

### Phase 1 결과
- SPI R/W: PASS / FAIL (비고: _______________)
- ADC Loopback: PASS / FAIL (비고: _______________)
- DAC Loopback: PASS / FAIL (비고: _______________)

### Phase 2~4 (별도 시트)
...

### 종합 판정
[ ] PASS — 모든 기준 충족
[ ] CONDITIONAL PASS — 경미한 이슈 (아이템: _______________)
[ ] FAIL — 중대 이슈 (아이템: _______________)
```

---

> **참고**: Phase 0~1은 FPGA 보드 단독 테스트, Phase 2~4는 RF Front-End 보드 조립 후 진행  
> 모든 테스트는 `07-development-process.md`의 코드 리뷰 체크리스트 통과 후 수행
