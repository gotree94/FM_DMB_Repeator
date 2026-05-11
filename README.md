# FM/DMB Repeater — Hardware Design & Market Analysis

> **DMB·FM 중계기** 하드웨어 설계 데이터 초안 및 국내 시장 분석 자료

## 📋 프로젝트 개요

본 프로젝트는 **지상파 DMB(174~216MHz) 및 FM 라디오(88~108MHz) 중계기(Repeater)** 의 하드웨어 설계와 국내 시장 분석을 목적으로 합니다.

중계기는 방송공동수신설비(헤드엔드)에서 전송된 신호를 수신하여 지하주차장, 지하상가, 터널 등 **전파 음영 지역**에 무선 재전송하는 장치입니다.

> **전파법 기준**: 특정소출력 무선기기 (FM: 10mW 이하)

## 📁 문서 구조

| 파일 | 내용 |
|---|---|
| [`README.md`](README.md) | 프로젝트 개요 (이 파일) |
| [`01-hardware-design.md`](01-hardware-design.md) | 하드웨어 설계 데이터 초안 — 시스템 블록도, 상세 규격, PCB 가이드라인 |
| [`02-component-selection.md`](02-component-selection.md) | 부품 선정 및 BOM — FPGA, RF Front-End, ADC/DAC, PA, 전원부 |
| [`03-market-analysis.md`](03-market-analysis.md) | 국내 FM/DMB 리피터 시장 분석 — 제조사, 가격, 경쟁 구도, 진입 전략 |
| [`04-system-topology.md`](04-system-topology.md) | 최상위 시스템 구성도 — 5계층 구조, 안테나~단말 전 구간 |
| [`05-reverse-engineering-bom.md`](05-reverse-engineering-bom.md) | 역설계(BOM 역추적) 비교표 — 경쟁 제품 3개 등급 부품 구성 분석 |
| [`06-fpga-prototype-cost-estimate.md`](06-fpga-prototype-cost-estimate.md) | FPGA 디지털 리피터 프로토타입 제작 비용 견적 — Phase 1~6, BOM, 일정 |

## ⚙️ 시스템 핵심 사양

| 항목 | FM | T-DMB |
|---|---|---|
| 주파수 대역 | 88 ~ 108 MHz | 174 ~ 216 MHz (Band-III) |
| 채널 대역폭 | 150 kHz | 1.536 MHz |
| 변조 방식 | FM | OFDM (DQPSK) |
| 동시 처리 채널 | 40 ch | 6 ch |
| 출력 전력 | +10 dBm (Driver) / 외부 PA 확장 |
| AGC 동적 범위 | > 50 dB |
| 임피던스 | 50Ω (전 구간) |

## 🔧 핵심 접근 방식

- **FPGA 기반 디지털 신호 처리** (Xilinx Kintex-7)
- CIC + FIR + ISOP 필터를 통한 정밀 채널 선택
- 디지털 AGC를 통한 출력 레벨 자동 유지
- Zero-IF 또는 Low-IF 구조

## 📊 시장 현황 (요약)

- **주력 가격대**: 33~45만원 (제품 간 기술 격차 거의 없음)
- **10개 이상 제조사**가 경쟁 중인 **레드오션**
- **정부 규제 강화**로 시장 지속 성장 중 (터널 재난방송 의무화, 2025)
- **디지털 DSP 기반 차별화 제품**의 시장 공백 상태
