#!/usr/bin/env python3
"""Create a traceable audit for Vivado Project 1-840 diagnostics.

The script is deliberately read-only.  It records the generated implementation
script which adds each child-IP checkpoint and the managed OOC run expected to
produce the same checkpoint.  It does not suppress or reclassify diagnostics.
"""

from __future__ import annotations

import csv
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUN_LOG = ROOT / "laser_tx.runs" / "impl_1" / "runme.log"
IMPL_TCL = ROOT / "laser_tx.runs" / "impl_1" / "laser_tx_board_top.tcl"
OUT = (
    ROOT
    / "reports"
    / "ad9528_gt_rate_planner"
    / "artifact_build"
    / "project_1_840_audit.csv"
)

WARNING_RE = re.compile(
    r"^(CRITICAL WARNING: \[Project 1-840\].*?'([^']+\.dcp)'.*)$"
)


def normalized(path: str) -> str:
    return path.replace("\\", "/")


def main() -> None:
    log_lines = RUN_LOG.read_text(encoding="utf-8", errors="replace").splitlines()
    impl_text = IMPL_TCL.read_text(encoding="utf-8", errors="replace")
    rows: list[dict[str, str | int]] = []
    seen_paths: set[str] = set()

    for line in log_lines:
        match = WARNING_RE.match(line.strip())
        if not match:
            continue
        warning_text, dcp_path = match.groups()
        dcp_path = normalized(dcp_path)
        if dcp_path in seen_paths:
            continue
        seen_paths.add(dcp_path)
        source_ip = Path(dcp_path).stem
        if source_ip.endswith(".dcp"):
            source_ip = source_ip[:-4]
        source_run = f"{source_ip}_synth_1"
        referenced = normalized(dcp_path) in normalized(impl_text)
        rows.append(
            {
                "warning_index": len(rows) + 1,
                "warning_text": warning_text,
                "dcp_path": dcp_path,
                "source_ip": source_ip,
                "source_run": source_run,
                "referencing_script_or_property": (
                    "laser_tx.runs/impl_1/laser_tx_board_top.tcl:add_files "
                    "(Vivado-generated managed implementation script)"
                    if referenced
                    else "NOT_FOUND_IN_GENERATED_IMPL_TCL"
                ),
                "root_cause": (
                    "Vivado 2022.2 managed BD composite flow adds the generated "
                    "child-IP DCP directly to the in-memory implementation design"
                ),
                "planned_fix": (
                    "create/rebuild the managed OOC run, regenerate BD targets, "
                    "require generated/run DCP SHA-256 equality, then accept the "
                    "diagnostic only when freshness evidence passes"
                ),
            }
        )

    if len(rows) != 13:
        raise SystemExit(f"expected 13 Project 1-840 warnings, found {len(rows)}")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", newline="", encoding="utf-8-sig") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(f"PROJECT_1_840_AUDIT_ROWS={len(rows)}")
    print(f"PROJECT_1_840_AUDIT={OUT}")


if __name__ == "__main__":
    main()
