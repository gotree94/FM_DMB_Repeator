# Vivado IP Integration Notes

## DDS Compiler IP vs. Current RTL NCO

### Current Implementation (ddc.v, duc.v)
- Pure Verilog NCO with phase accumulator + quadrant-based sine approximation
- 32-bit phase width, 10-bit LUT address, 14-bit output
- Resource: ~32 LUT + 1 DSP48 per instance
- Latency: 3 cycles (pipeline)
- Limitation: Low SFDR (~48 dB) due to simplified LUT

### Xilinx DDS Compiler IP (Recommended for Production)
- Higher SFDR (>80 dB) with Taylor series correction or dithering
- Resource: ~1 BRAM + ~2 DSP48 per instance
- Latency: 6 cycles (configurable)
- Phase Increment: Streaming mode supports per-cycle update

### Recommendation
| Use Case | Approach | Reason |
|----------|----------|--------|
| Prototype | Current RTL NCO | Zero IP dependency, quick simulation |
| Production | DDS Compiler IP | Higher SFDR for OFDM (DMB) performance |
| FM only (40 ch) | Current RTL NCO | 48 dB SFDR sufficient for FM |
| DMB (6 ch) | DDS Compiler IP | Recommend BRAM-based DDS for DMB path |

### Implementation Plan (Production)
1. Create DDS Compiler IP: `create_ip -name dds_compiler -vendor xilinx.com -library ip -version 6.0`
2. Configure: Phase Width=32, Output Width=14, Sine+Cosine, Block ROM, 6-cycle latency
3. Replace NCO in ddc.v and duc.v with IP instantiation
4. Update .xdc with DDS IP output clock constraints

## Other IP Candidates
| IP | Module | When Needed |
|----|--------|-------------|
| FIFO Generator | adc_interface async FIFO | If distributed RAM FIFO insufficient |
| Block Memory Gen | fir_filter coefficients | If >1024 words coefficient storage |
| IOBUF | spi_slave MISO tristate | Already implemented in RTL |
