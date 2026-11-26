# Reliability verification — Arty A7 UART/NPU

## Existing physically observed evidence

- Original 25 November physical benchmark: **300/300** exact matches, 100 each for the small/medium/large reference networks.
- Subsequent user-reported repeatability: **3,000/3,000** exact matches (1,000 each topology) with UART p95 times 16.284 ms / 16.317 ms / 15.504 ms.
- Neither observation is a full field-reliability, environmental or lifetime qualification. The complete 3,000-case raw CSV and summary JSON are not yet checked into GitHub.
- The **repeat-model-loading** endurance script was later run successfully on the physical board for **3,000/3,000** reported comparisons with reprogramming every 250 operations, but its full per-transaction JSONL and campaign summary have **not** been archived. This does not replace resetting/power-cycling fault testing.

## Test suite A — protocol fault injection in simulation

Run `bash scripts/test.sh` on Linux/WSL. New testbench `tb/tb_npu_uart_robustness.sv` operates the actual UART RX/TX serializer and accelerator controller, checking:
1. Corrupted XOR packet for model weight: explicit rejection; subsequent inference confirms weight unchanged.
2. Unknown opcode: explicit status=2.
3. Invalid topology: inference reports error; valid configuration recovery still produces expected scores.
4. Partial command followed by **hardware reset**: parser returns to working command/reply operation.

These tests exercise control errors, not packet noise on the physical board. The bridge **does not implement an incomplete-frame timeout**. A truncated packet that is not followed by reset can leave the parser awaiting bytes. Protocol XOR has known multi-bit collision weaknesses; we do not claim industrial noise immunity.

## Test suite B — physical endurance

Requires **UART/NPU Track A** bitstream with telemetry command 0x54, Arty A7 and an unused COM port. Do NOT program the autonomous consumer IP bitstream for this test.

Run in PowerShell from repository root:

```powershell
py host/reliability_campaign.py --port COM4 --model all --count 1000 --reload-every 250 --output build/reliability
```

The run loads deterministic test weights and reprogrammes each model after every 250 inferences; it checks **all eight actual available scores up to the selected network output width**, class and optionally FPGA cycles. Test seed, topology, expected versus actual values, UART times and error status are retained.

Output files:

```text
build/reliability/
  small_events.jsonl
  medium_events.jsonl
  large_events.jsonl
  small_summary.json
  medium_summary.json
  large_summary.json
  campaign_summary.json
```

**Pass criteria:** every requested test completed; all scores and classes bit-exact; no transport exception; no missing cycle telemetry if enabled. If a UART timeout occurs, the script **aborts and preserves partial evidence**; do not blindly retransmit a packet while the device might be out of frame alignment. Investigate/reset/reprogramme before a fresh campaign. The command exits nonzero for any incomplete or failing run.

To run longer, increase `--count`; repeat across resets, board power cycles and operating conditions **as distinct labelled sessions**. Counts alone do not prove a guaranteed mean-time-between-failures figure.

For raw 3,000-case archival input, retain `build/benchmarks/benchmark_summary.json` and all three `*_transactions.csv` files from the already completed earlier benchmark. These are generated local files, deliberately not shipped in GitHub ZIP.

## Important limitation of automated test B

The physical endurance command does **not** force a pushbutton reset, power cycle, inject malformed UART frames or simulate cable disconnection. Those are additional experiments requiring explicit instrumentation and a controlled recovery procedure. They must not be marked as physically passed because simulation passed.

## Release evidence status

| Gate | Status |
|---|---|
| Independent numeric RTL oracle, 48 cases | PASS |
| Original 300/300 FPGA test | PASS |
| Later 3,000/3,000 FPGA user-reported test | PASS (original results not yet archived) |
| UART fault simulation (checksum/unknown/invalid/reset) | PASS in GitHub CI |
| Extended campaign using new tool | 3,000/3,000 **user-reported physical PASS with periodic reloading**; raw logs unavailable |
| Physical reset during operation | NOT YET VERIFIED |
| Partial-packet timeout/recovery without reset | UNSUPPORTED BY CURRENT UART RTL |
| Power rail and energy/inference | NOT YET MEASURED |

See [consolidated verification report](VERIFICATION_REPORT.md).
