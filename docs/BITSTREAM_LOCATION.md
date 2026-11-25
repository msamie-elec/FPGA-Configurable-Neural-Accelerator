# One authoritative Arty A7 bitstream

## Official programming location

`build/bitstream/arty_a7_uart_npu.bit` — the **only file path to program** in Vivado Hardware Manager. The accompanying `build/bitstream/build_info.txt` documents source flow, path, publishing time and routed setup/hold slack. Files under ignored `build/` are local build outputs, **not committed binaries**.

The GUI's own file `build/uart_npu_project/uart_npu.runs/impl_1/arty_a7_uart_npu_top.bit` is an implementation-run intermediate managed by Vivado. It is not the canonical programming path. The non-project flow previously emitted `build/uart_npu/arty_a7_uart_npu.bit`; the batch script now publishes instead to the canonical location.

## Existing GUI build (no new synthesis needed)

Open the matching `uart_npu.xpr` in Vivado, then in its Tcl Console (current directory is repository root):

```tcl
source vivado/publish_existing_gui_bitstream.tcl
```

The script opens `impl_1`, checks WNS/WHS >=0, and copies its existing bitstream to `build/bitstream/arty_a7_uart_npu.bit`. This also works for a GUI project generated before the automatic hook was installed. Do not publish an old implementation after modifying RTL.

## Future builds

- GUI: recreate project with `source vivado/create_uart_npu_project.tcl`; the script registers a **post-write_bitstream Tcl hook** which automatically copies the GUI-generated bitstream into the canonical location after Generate Bitstream and verifies timing. Existing GUI projects need the one-time command above or a refreshed hook.
- Batch: `source vivado/build_uart_npu.tcl` builds and directly writes the canonical file after routed timing passes.

Only one output is designated for programming, although Vivado may keep internal project implementation files. Those internal artifacts are required by Vivado and should not be deleted manually.

## Version checks

The bitstream's **build_info.txt must match your latest design build**. For clock-cycle telemetry, RTL must include UART command `0x54`; otherwise `--fpga-cycles` will fail even if the older bitstream performs correct NN inference. The host benchmark does not identify firmware cryptographically, so reprogram the canonical latest bitstream whenever RTL changes.
