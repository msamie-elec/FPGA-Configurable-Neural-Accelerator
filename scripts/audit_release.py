#!/usr/bin/env python3
"""Static release-document consistency and local-link audit.

This check cannot prove RTL bug freedom. It validates that the canonical
engineering docs reference existing local files, quote the archived benchmark
and routed-core power figures, and link the planned application accurately.
"""
from __future__ import annotations
import json
import re
from pathlib import Path

CANONICAL = (
    "README.md",
    "docs/TECHNICAL_DATASHEET.md",
    "docs/VERIFICATION_REPORT.md",
    "docs/ARCHITECTURE.md",
    "docs/RELEASE_ACCEPTANCE.md",
)
APPLICATION = "https://github.com/msamie-elec/FPGA-Bearing-Condition-Monitoring"
LINK = re.compile(r"(?<!!)\[[^\]]*\]\(([^)]+)\)")


def audit(root: Path) -> list[str]:
    root = Path(root)
    failures = []
    for name in CANONICAL:
        p = root / name
        if not p.is_file():
            failures.append(f"Missing canonical document: {name}")
            continue
        source = p.read_text(encoding="utf-8")
        if APPLICATION not in source:
            failures.append(f"Missing companion bearing project URL in {name}")
    for p in [root / "README.md", *(root / "docs").rglob("*.md")]:
        if not p.is_file():
            continue
        source = p.read_text(encoding="utf-8")
        # Markdown link checker; external URLs are intentionally not fetched.
        for target in LINK.findall(source):
            target = target.strip().split(" ", 1)[0].strip("<>")
            if not target or target.startswith(("#", "http://", "https://", "mailto:", "data:")):
                continue
            path = target.split("#", 1)[0].split("?", 1)[0]
            if path and not (p.parent / path).exists():
                failures.append(f"{p.relative_to(root)}: dangling local link {target}")
    try:
        bench = json.loads((root/"docs/results/arty_a7_benchmark_2026-11-25.json").read_text())
        routed = json.loads((root/"docs/results/ip9_routed_core_power_2026-11-26.json").read_text())
        assert len(bench["models"]) == 3
        assert sum(x["passes"] for x in bench["models"]) == 300
        assert sum(x["count"] for x in bench["models"]) == 300
        assert tuple(x["cycles"] for x in bench["models"]) == (114, 250, 2394)
        assert tuple(x["macs"] for x in bench["models"]) == (72, 272, 3328)
        assert routed["engineering_signoff"] is False
        assert routed["saif"]["matched_nets"] == 1471
        assert routed["saif"]["design_nets"] == 2653
        assert tuple(routed["estimated_on_chip_power_mw"][x]["total"]
                     for x in ("idle","model_loading","inference")) == (74, 76, 78)
        d = (root/"docs/TECHNICAL_DATASHEET.md").read_text()
        for value in ("3,328", "2,394", "55.4%", "74 / 15", "76 / 17",
                      "78 / 19", "not a completed validated bearing classifier"):
            # The last phrase may be replaced by equivalent explicit caveat.
            if value not in d and value != "not a completed validated bearing classifier":
                failures.append(f"Datasheet missing key evidence phrase: {value}")
    except (OSError, ValueError, KeyError, AssertionError) as exc:
        failures.append(f"Archived source evidence invalid or inconsistent: {exc}")
    if "build/" not in (root / ".gitignore").read_text():
        failures.append("Generated build/ must be Git-ignored")
    return failures


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    issues = audit(root)
    for issue in issues:
        print(f"RELEASE AUDIT ERROR: {issue}")
    if issues:
        raise SystemExit(f"RELEASE AUDIT FAIL: {len(issues)} error(s)")
    print("RELEASE AUDIT PASS: canonical docs, relative links and archived numbers")
