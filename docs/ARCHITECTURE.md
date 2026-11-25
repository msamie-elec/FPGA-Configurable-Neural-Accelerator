# Architecture contract (fresh baseline)

## System partition

```text
PC GUI + trained model compiler (future)
              |
       UART protocol (future)
              |
   FPGA controller + memories (future)
              |
     NPU compute subsystem
              |
  Arty A7 physical integration
```

**Current implementation:** standalone signed INT8 4→2 dense engine and slide-switch/button/LED demonstration. All code lives in `rtl/`, not mirrored beneath a hardware or Vivado folder.

## v0.1 computation

`score[j] = sum(i=0..3, signed_int8(input[i]) * signed_int8(weight[j][i]))`.

This baseline implements no bias, activation, scaling, or multiple layers. Each score accumulates in signed INT32. Class is 1 only if `score1 > score0` (ties return 0). The input is latched upon `start`. Writes are accepted only in IDLE; simultaneous write/start gives priority to write. `valid` pulses for one cycle at the end. Reset loads demonstration weights (see RTL). This simplified contract is deliberate and will change under versioned model protocols in later stages.

## Future architecture boundaries

- `rtl/compute/`: MAC array, pipelining, requantisation.
- `rtl/control/`: command decoding, layer sequencing, status.
- `rtl/memory/`: inferred BRAM input/weight/activation storage.
- `rtl/interfaces/`: UART transport, framing, error checks.
- `rtl/top/`: single named FPGA top that integrates the above.

These directories **do not exist until they contain functioning sources**. The v0.1 flat RTL directory avoids premature hierarchy.

## Acceptance gates

1. Self-checking simulation green.
2. Synthesis with no inferred latches or multi-driver nets.
3. Post-route 100 MHz setup timing met.
4. Hardware switches/buttons/LEDs agree with simulation.
5. Add model loading, reference Python oracle, GUI and randomised testing under separate milestone gates.

Never publish performance claims without attached commands, version, device, clock, source commit and reports.
