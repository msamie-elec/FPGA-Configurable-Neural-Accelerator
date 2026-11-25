#!/usr/bin/env python3
"""Fail CI when source trees proliferate or RTL names become ambiguous."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
rtl = root / "rtl"
assert rtl.is_dir(), "Missing authoritative rtl/ directory"
assert not (root / "hardware" / "rtl").exists(), "Duplicated hardware/rtl source tree"
rtl_files = sorted(rtl.rglob("*.sv"))
assert rtl_files, "No SystemVerilog RTL sources found"
names = [f.name for f in rtl_files]
assert len(names) == len(set(names)), "Duplicated RTL basenames"
for folder in ("tb", "constraints", "vivado", "scripts", "docs"):
    assert (root / folder).is_dir(), f"Missing {folder}/"
assert len(list(root.rglob("*.xpr"))) == 0, "Vivado-generated .xpr must not be committed"
print(f"STRUCTURE PASS: {len(rtl_files)} unique RTL sources, one authoritative rtl/ root")
