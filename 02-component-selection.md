# FM/DMB Repeater — 부품 선정 및 BOM

> FPGA 기반 디지털 중계기의 부품별 비교 분석과 상세 BOM

---

## 1. FPGA (디지털 신호 처리 Core)

### 선정: Xilinx Kintex-7 (XC7K325T-FFG676)

| 이유 | 설명 |
|---|---|
| DSP 성능 | 840 DSP slices, 최대 160MHz 클록 |
| 로직 용량 | 326K logic cells, 445 I/O |
| 트랜시버 | 16× 12.5Gbps GTX — 향후 광링크 대비 |
| 검증 실적 | MDPI Electronics 2019 연구에서 FM 40ch + DMB 6ch 동시 처리 검증 |
| 대안 | Artix-7 XC7A200T (저가형), Zynq-7000 (CPU 내장형) |

### FPGA 주변 회로

| 부품 | 용도 |
|---|---|
| **MT25QL256ABA** (256Mb SPI NOR Flash) | Configuration 메모리 |
| **Si5338** (4채널 클록 제너레이터, 저지터) | 시스템 클록 생성 (10MHz Ref → 80MHz ADC/DAC CLK) |
| **TPS54620** (4.5-17V 입력, 6A 출력) | FPGA 코어 전압 (1.0V) |
| **TPS62150** | FPGA I/O 전압 (3.3V, 5A) |

---

## 2. RF 프론트엔드

### 2.1 FM Band LNA (88-108 MHz)

#### 추천: BGA2818 (NXP) — MMIC 광대역 LNA

| 파라미터 | 값 |
|---|---|
| 주파수 범위 | DC ~ 2.2 GHz |
| 이득 | 26 dB (100 MHz 기준) |
| NF | 3.2 dB |
| 전원 | 3.3V, 14 mA |
| 특징 | MMIC, 외부 정합 최소화, 초소형 |

#### 대안: MAX2180A (Maxim)

| 파라미터 | 값 |
|---|---|
| 주파수 범위 | 0.15 ~ 162.5 MHz |
| NF | < 2.75 dB (75Ω) |
| 이득 | 6 dB |
| 전원 | 6 ~ 24 V |
| 특징 | AM/FM 차량용 안테나 LNA |

### 2.2 T-DMB Band LNA (174-216 MHz)

#### 추천: MAX2371 / MAX2373 (Maxim)

| 파라미터 | 값 |
|---|---|
| 주파수 범위 | 100 ~ 1000 MHz |
| 이득 | 15 dB (고이득 모드) |
| NF | 1.15 dB (MAX2371) / 1.3 dB (MAX2373) |
| VGA | 20dB 감쇠기 + 45dB VGA 내장 |
| 전원 | 2.5 ~ 3.3 V |

#### 통합 수신 칩 대안

| 부품 | 특징 |
|---|---|
| **RDA5876** (RDA Micro) | T-DMB/DAB 수신기, 저전력, 소형 |
| **TDA18273** (NXP) | 실리콘 튜너, 42-1002MHz, DVB-T/T2/DAB |
| **GDM7004** (GCT) | RF Tuner + 채널디코더 단일칩, <100mW |

### 2.3 RF Down-Converter (수신)

#### IF 방식 (20MHz IF)

| 부품 | 설명 |
|---|---|
| **ADL5355** (ADI) | RF Downconverter, 75~3700MHz, NF=8.5dB, IIP3=20dBm |
| **AD8343** (ADI) | Up/Down Mixer, 2.5GHz 대역, 변환 손실 7dB |

#### Zero-IF 방식 (직접 변환)

| 부품 | 설명 |
|---|---|
| **ADL5380** (ADI) | I/Q Demodulator, RF 400~6000MHz |
| **AD8346** (ADI) | Quadrature Modulator, RF 800~2500MHz |

> FM(88-108MHz) 대역은 Zero-IF 방식이 더 유리할 수 있음

---

## 3. ADC / DAC

### 3.1 ADC (Analog-to-Digital Converter)

#### 추천: AD9649 (Analog Devices)

| 파라미터 | 값 |
|---|---|
| 분해능 | 14-bit |
| 샘플링 속도 | 80 MSPS (Nyquist 40MHz — IF 샘플링) |
| SNR | 75 dB @ 20MHz |
| SFDR | 90 dBc |
| 인터페이스 | 병렬 CMOS/LVDS |
| 전력 | 84 mW @ 80MSPS |
| 이유 | 참고 논문에서 14-bit 80MSPS IF 샘플링 사용 검증 |

### 3.2 DAC (Digital-to-Analog Converter)

#### 추천: AD9742 (Analog Devices)

| 파라미터 | 값 |
|---|---|
| 분해능 | 12-bit |
| 업데이트율 | 210 MSPS |
| SFDR | 75 dBc @ 5MHz 출력 |
| 전원 | 3.0 ~ 3.6 V |
| 전력 | 165 mW |
| 이유 | 충분한 분해능, 저전력, FPGA 인터페이스 용이 |

---

## 4. 송신 전력 증폭기 (Power Amplifier)

### 4.1 Driver 단 (0dBm → +10dBm)

| 부품 | 설명 |
|---|---|
| **GALI-39+** (Mini-Circuits) | 50Ω, DC~7GHz, Gain 18.9dB, P1dB=15dBm |

### 4.2 고출력 PA (외장형, 모듈식)

| 부품 | 출력 | 주파수 | 전압 | 특징 |
|---|---|---|---|---|
| **MRFE6VP61K25H** (NXP) | 1.25kW | 87.5-108MHz | 50V | FM 방송 기준 설계, LDMOS |
| **BLF647** (NXP) | 250W | VHF | 50V | Class-AB, 방송용 |
| **BLF188A** (NXP) | 600W | HF/VHF | 50V | FM 대역 |
| **RA30H1317M** (Mitsubishi) | 30W | 1.3-1.7GHz | 12.5V | UHF 대역 (소출력 DMB) |
| **RD70HVF1** (Mitsubishi) | 70W | HF/VHF | 12V/50V | FM 대역 |

> **초기 설계**: 소출력 (10~30W) 목표로 시작. RA30H1317M VHF 대응 모듈 또는 BLF188A 검토.
>
> **⚠️ 전파법 주의**: 특정소출력 무선기기는 FM 88-108MHz 출력 10mW 이하. 초과 시 무선국 허가 필요.

---

## 5. 필터

### 5.1 수신 BPF (사전 선택)

| 대역 | 부품 | 특징 |
|---|---|---|
| FM (88-108MHz) | **SF2381E** (Murata) SAW BPF | 88-108MHz, IL<3.5dB, 50Ω |
| T-DMB (174-216MHz) | **B1740** (Mini-Circuits) LC BPF | 165-220MHz, IL<1dB |
| T-DMB (174-216MHz) | 175-210MHz SAW Filter (Tai-Saw) | IL<3dB, 고선택도 |

### 5.2 송신 BPF (고조파 제거)

- **7차 Chebyshev LPF**: 차단주파수 113MHz (FM) / 220MHz (DMB)
- **커패시터**: ATC100B 시리즈 (ATC — RF 세라믹)
- **인덕터**: Coilcraft 1812SMS 시리즈

---

## 6. 전원부

| IC | 용도 | 특징 |
|---|---|---|
| **TPS54620** | FPGA 코어 1.0V / 6A | SWIFT DC-DC 컨버터 |
| **TPS62150** | FPGA I/O 3.3V / 5A | 고효율 DC-DC |
| **LMZM23601** | RF IC 3.3V / 1A | 모듈형 DC-DC, 저잡음 |
| **LT1764A** | ADC 전원 1.8V / 3A | 저잡음 LDO |
| **LTC6655** | ADC/DAC 기준전압 2.5V | 0.25ppm/°C 정밀도 |
| **Mean Well RS-150-12** | 시스템 주전원 AC→12V/12.5A | 산업용 SMPS |

---

## 7. 시스템 관리

| 기능 | 부품 | 설명 |
|---|---|---|
| 시스템 MCU | **STM32F429** (ST) | ARM Cortex-M4, Ethernet, USB, 시스템 제어 |
| 온도 센서 | **LM75A** (NXP) | I²C 디지털 온도 센서 |
| 팬 제어 | **MAX31760** | 정밀 팬 속도 컨트롤러 |
| VSWR 보호 | **ADL5920** (ADI) | 9kHz~7GHz 방향성 검출기 + VSWR 모니터 |
| 이더넷 PHY | **LAN8720A** | RMII 인터페이스, 10/100Mbps |

---

## 8. 예상 BOM (Bill of Materials)

> 프로토타입 1대 기준, 2025년 Digikey/Mouser 공시가 기준

### 8.1 주요 능동부품

| # | 부품명 | 수량 | 단가(추정) | 공급사 | 용도 |
|---|---|---|---|---|---|
| 1 | XC7K325T-FFG676 | 1 | ~$180 | Xilinx / AMD | FPGA |
| 2 | MT25QL256ABA | 1 | ~$6 | Micron | FPGA Config Flash |
| 3 | Si5338A | 1 | ~$8 | Silicon Labs | 클록 제너레이터 |
| 4 | AD9649BCPZ-80 | 1 | ~$25 | Analog Devices | ADC 14-bit 80MSPS |
| 5 | AD9742ARUZ | 1 | ~$15 | Analog Devices | DAC 12-bit 210MSPS |
| 6 | MAX2371 | 1 | ~$5 | Maxim / ADI | DMB LNA |
| 7 | BGA2818 | 1 | ~$3 | NXP | FM LNA |
| 8 | ADL5355 | 1 | ~$7 | Analog Devices | Down-Converter |
| 9 | ADL5380 | 1 | ~$8 | Analog Devices | I/Q Demodulator (ZIF) |
| 10 | GALI-39+ | 2 | ~$3 | Mini-Circuits | Driver PA |
| 11 | BLF188A | 1 | ~$45 | NXP | PA TR (고출력) |
| 12 | STM32F429ZIT6 | 1 | ~$10 | STMicroelectronics | 시스템 MCU |
| 13 | ADL5920 | 1 | ~$12 | Analog Devices | VSWR 모니터 |
| 14 | LAN8720A | 1 | ~$3 | Microchip | Ethernet PHY |
| 15 | LM75A | 2 | ~$1.5 | NXP | 온도 센서 |

### 8.2 전원부

| # | 부품명 | 수량 | 단가(추정) | 용도 |
|---|---|---|---|---|
| 16 | TPS54620RGYR | 2 | ~$4 | FPGA 1.0V / 6A |
| 17 | TPS62150RGT | 2 | ~$3 | FPGA I/O 3.3V |
| 18 | LMZM23601SIR | 1 | ~$5 | RF 3.3V 모듈 |
| 19 | LT1764AEQ | 2 | ~$5 | 저잡음 LDO 1.8V |
| 20 | LTC6655BHMS8-2.5 | 1 | ~$8 | 정밀 전압 기준 |
| 21 | Mean Well RS-150-12 | 1 | ~$45 | AC→DC 주전원 |

### 8.3 수동부품 및 기타

| # | 부품명 | 수량 | 단가(추정) | 용도 |
|---|---|---|---|---|
| 22 | SF2381E (SAW BPF) | 1 | ~$2 | FM 수신 필터 |
| 23 | 175-210MHz SAW BPF | 1 | ~$2 | DMB 수신 필터 |
| 24 | ATC100B 시리즈 커패시터 | 30 | ~$2 | RF 커패시터 |
| 25 | Coilcraft 1812SMS 인덕터 | 10 | ~$3 | RF 인덕터 |
| 26 | SMA 커넥터 (Female) | 6 | ~$3 | Amphenol |
| 27 | PCB (6층, 임피던스 제어) | 1 | ~$80 | PCB Fab |
| 28 | 함체 (19" 1U Rack) | 1 | ~$50 | — |
| 29 | 히트싱크 + 팬 | 1set | ~$25 | 열 관리 |

### 8.4 총 BOM 요약

| 구분 | 금액 |
|---|---|
| 능동부품 합계 | **~$345** |
| 전원부 합계 | **~$75** |
| 수동부품 및 기타 | **~$175** |
| **프로토타입 총 부품비** | **~$595** (약 80만원) |

> **양산 시 예상 단가**: 약 $350~450 (50만~60만원) — 부품 대량 할인 및 PCB/조립 최적화 반영
>
> **참고**: 기존 제품의 시장 가격이 33만~88만원인 점을 고려할 때, FPGA 기반 디지털 제품은 부품비만으로도 기존 제품 소비자가를 상회. **프리미엄 전략** 필요.
