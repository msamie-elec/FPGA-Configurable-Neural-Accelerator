# Architecture and integration boundaries

**Current implementation — 26 November 2026.** This document describes the actual reusable IP and two demonstrated board integrations. Earlier v0.1 experiments remain in `docs/MLP_V0_2.md` and `docs/SCALABLE_NPU_V0_3.md` as historical milestone records.

## Compute architecture

```text
               Runtime configuration / model writes
                          |             |
             4,096 INT8 weight bytes   128 INT32 bias words
                     |                        |
                8 BRAM banks                  |
                     |  8 signed INT8 samples |
 Input 32 x INT8 -> activation A/B buffers    |
                     |                        |
            8 signed INT8 multiply lanes       |
                     |                        |
              registered pairwise sums         |
                     |                        |
              registered four-way sums         |
                     |                        |
            INT32 neuron accumulation ---------+
                     |
              bias-add register
                     |
       arithmetic shift + INT8 saturation
                     |
         hidden-layer ReLU / output logits
                     |
        activation ping-pong / score latch
                     |
       lowest-index argmax + valid/error
```

- Four computational layers maximum, **32→32→32→32→8**, 3,328 logical active weights and 104 computational neurons at maximum configuration.
- One neuron is evaluated across up to four groups of eight features; multiplier lanes are shared across neurons and layers.
- Weight addressing: `layer*1024 + neuron*32 + input`, 8 banks, 512 byte entries each. Bias addressing: `layer*32 + neuron`.
- Model SRAM is **undefined until programmed**, not cleared/initialised by reset. The core checks topology legality at inference request but **not model completeness**.
- Signed INT32 arithmetic may overflow at its native width; no additional accumulator saturation occurs before shift.
- Synchronous positive-edge clock; no AXI4, DMA, PCIe, Ethernet or streaming sensor frontend.

## The two separately implemented FPGA systems

```text
TRACK A — physical UART/GUI reference       TRACK B — reusable packaged IP
+----------------------------------+        +------------------------------+
| PC Python GUI / benchmark         |        | Vivado consumer stimulus     |
| 115200 baud framed UART           |        | memory programming + reset  |
| npu_uart_bridge                   |        | npu_accelerator_ip (IP-XACT) |
| npu_scalable_core                 |        | npu_scalable_core            |
| Arty A7 UART/NPU top              |        | Arty A7 LED digest top       |
+----------------------------------+        +------------------------------+
           Scores / cycles                           LED outputs (NO UART)
```

Do not mix their bitstreams. The Track A canonical bitstream is `build/bitstream/arty_a7_uart_npu.bit`; Track B produces a distinct `arty_a7_ip_consumer_top.bit` with no serial interface.

## Power verification is a third, separate study

The **post-route OOC NPU core** (IP-9) builds a routed checkpoint plus *matching* functional netlist to capture idle/loading/inference SAIF at 100 MHz. It is not a board top or a physically measured wattage. This experiment produced 55.4% SAIF net matching and High Vivado power confidence; its scope and results are in [Technical Datasheet](TECHNICAL_DATASHEET.md) and [Routed Core Power Workflow](ROUTED_CORE_POWER_WORKFLOW.md).

## Deployment interface for next application

[FPGA Bearing Condition Monitoring](https://github.com/msamie-elec/FPGA-Bearing-Condition-Monitoring) is the **next intended application**. Its software pipeline builds eight features per vibration/current window and plans to produce a trained/quantised 8→16→8→2 model. Integrating that model requires externally validated scale/shift, signed INT8 feature encoding, explicit full model loading into this NPU, and FPGA-vs-Python output parity. This IP does **not** itself acquire sensors, train the model or establish classification accuracy.

See [IP Integration](IP_INTEGRATION.md), [Start Here](START_HERE.md), [Verification](VERIFICATION_REPORT.md) and [Datasheet](TECHNICAL_DATASHEET.md).
