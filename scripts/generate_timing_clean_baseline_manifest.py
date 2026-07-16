#!/usr/bin/env python3
"""Generate the Iteration 7 timing-clean baseline manifest from reports."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports" / "ad9528_gt_rate_planner" / "timing_iteration7_split_output_network"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def key_values(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()
    return values


def git(*args: str) -> str:
    return subprocess.check_output(
        ["git", *args], cwd=ROOT, text=True, encoding="utf-8"
    ).strip()


def relative(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT.resolve()).as_posix()
    except ValueError:
        return path.resolve().as_posix()


def require(path: Path) -> Path:
    if not path.is_file():
        raise FileNotFoundError(path)
    return path


metadata = key_values(require(OUT / "project_run_metadata.txt"))
metrics = key_values(require(OUT / "audit_metrics.txt"))
signature = key_values(require(OUT / "ooc_rtl_signature.txt"))

routed_dcp = require(OUT / "iteration7_split_output_network_routed.dcp")
runtime_hook = require(Path(metadata["runtime_clock_hook"]))
timing_summary = require(OUT / "timing_summary.rpt")
regression_log = require(OUT / "pattern_engine_regression.log")
ooc_dcp = require(Path(signature["ooc_dcp"]))
route_status = require(OUT / "route_status.rpt").read_text(encoding="utf-8", errors="replace")
drc_text = require(OUT / "drc.rpt").read_text(encoding="utf-8", errors="replace")

if "PATTERN_TX_ENGINE_TIMING_REGRESSION_PASS" not in regression_log.read_text(
    encoding="utf-8", errors="replace"
):
    raise RuntimeError("pattern engine regression PASS marker is missing")

route_match = re.search(r"# of nets with routing errors\.*\s*:\s*(\d+)\s*:", route_status)
if not route_match:
    raise RuntimeError("cannot parse routing-error count")

drc_errors = len(re.findall(r"(?m)^\S[^\r\n]*#\d+ Error\s*$", drc_text))

constraint_files = []
for line in require(OUT / "active_implementation_xdc.txt").read_text(
    encoding="utf-8", errors="replace"
).splitlines():
    if not line.strip():
        continue
    path = require(Path(line.strip()))
    constraint_files.append({"path": relative(path), "sha256": sha256(path)})

hash_files = [runtime_hook, timing_summary, regression_log, ooc_dcp]

manifest = {
    "baseline_name": "TIMING_CLEAN_RTL_BASELINE",
    "git_branch": git("branch", "--show-current"),
    # This is the source commit being captured. The manifest commit is created
    # afterwards and is identified by the annotated tag.
    "git_commit": git("rev-parse", "HEAD"),
    "git_dirty": bool(git("status", "--porcelain")),
    "git_commit_semantics": "captured RTL source commit before manifest commit",
    "vivado_version": metadata["vivado_version"],
    "device": metadata["device"],
    "top": metadata["top"],
    "strategy": metadata["strategy"],
    "directives": {
        "opt_design": metadata["opt_design"],
        "place_design": metadata["place_design"],
        "phys_opt_design": metadata["phys_opt_design"],
        "route_design": metadata["route_design"],
    },
    "runtime_clocks": {
        "txusrclk_period_ns": float(metrics["txusrclk_period_ns"]),
        "txusrclk2_period_ns": float(metrics["txusrclk2_period_ns"]),
    },
    "routed_dcp": {"path": relative(routed_dcp), "sha256": sha256(routed_dcp)},
    "constraint_files": constraint_files,
    "file_hashes": [
        {"path": relative(path), "sha256": sha256(path)} for path in hash_files
    ],
    "ooc_rtl_signature": {
        key: int(signature[key])
        for key in (
            "pattern_index_reg",
            "pattern_mode_63_active",
            "pattern_cursor_reg",
            "len_active_reg",
            "next_phase_pattern_base_q",
            "cross_next_valid_count_q",
            "current_pattern_q",
            "rotated_pattern_reg",
        )
    },
    "timing": {
        "wns_ns": float(metrics["setup_wns_ns"]),
        "tns_ns": float(metrics["setup_tns_ns"]),
        "whs_ns": float(metrics["hold_whs_ns"]),
        "ths_ns": float(metrics["hold_ths_ns"]),
        "setup_failing_endpoints": int(metrics["setup_failing_endpoints"]),
        "hold_failing_endpoints": int(metrics["hold_failing_endpoints"]),
    },
    "route": {"unrouted_nets": int(route_match.group(1))},
    "drc_errors": drc_errors,
    "functional_regression": {
        "result": "PATTERN_TX_ENGINE_TIMING_REGRESSION_PASS",
        "pipeline_latency": 0,
    },
}

manifest_path = OUT / "timing_clean_rtl_baseline_manifest.json"
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(manifest_path)
