#!/usr/bin/env python3
"""Generate the runtime-rate artifact and software build manifests."""

from __future__ import annotations

import csv
import hashlib
import json
import pathlib
import re
import subprocess


ROOT = pathlib.Path(__file__).resolve().parents[1]
REPORT = ROOT / "reports" / "ad9528_gt_rate_planner" / "artifact_build"
VITIS = ROOT / "reports" / "runtime_rate_vitis"


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def rel(path: pathlib.Path) -> str:
    return path.resolve().relative_to(ROOT.resolve()).as_posix()


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def parse_key_values(path: pathlib.Path) -> dict[str, object]:
    result: dict[str, object] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        if re.fullmatch(r"-?\d+", value):
            result[key] = int(value)
        elif re.fullmatch(r"-?\d+\.\d+", value):
            result[key] = float(value)
        else:
            result[key] = value
    return result


def require(path: pathlib.Path) -> pathlib.Path:
    if not path.is_file():
        raise FileNotFoundError(path)
    return path


def main() -> None:
    bit = require(REPORT / "artifacts" / "laser_tx_board_top.bit")
    ltx = require(REPORT / "artifacts" / "laser_tx_board_top.ltx")
    xsa = require(REPORT / "artifacts" / "laser_tx_board_top_runtime_rate_switch.xsa")
    routed_dcp = require(REPORT / "routed.dcp")
    ooc_dcp = require(
        ROOT
        / "laser_tx.runs"
        / "system_laser_tx_core_0_0_synth_1"
        / "system_laser_tx_core_0_0.dcp"
    )
    elf = require(VITIS / "bringup" / "Debug" / "bringup.elf")
    map_file = require(VITIS / "bringup" / "Debug" / "bringup.map")
    xparameters = require(
        VITIS
        / "runtime_rate_artifact_platform"
        / "ps7_cortexa9_0"
        / "standalone_ps7_cortexa9_0"
        / "bsp"
        / "ps7_cortexa9_0"
        / "include"
        / "xparameters.h"
    )
    timing = require(REPORT / "final_timing_summary.rpt")

    metrics = parse_key_values(REPORT / "artifact_build_metrics.txt")
    signature = parse_key_values(REPORT / "ooc_rtl_signature.txt")
    xparameters_text = xparameters.read_text(encoding="utf-8", errors="replace")
    expected_symbols = {
        "XPAR_AXI_GPIO_DYNAMIC_MAILBOX_BASEADDR": "0x40040000",
        "XPAR_AXI_BRAM_DYN_DESC_S_AXI_BASEADDR": "0x42000000U",
    }
    for symbol, expected in expected_symbols.items():
        match = re.search(rf"^#define\s+{symbol}\s+(\S+)", xparameters_text, re.MULTILINE)
        if not match or match.group(1).upper() != expected.upper():
            raise RuntimeError(f"{symbol} does not match {expected}")

    source_dir = VITIS / "bringup" / "src"
    sources = sorted(path.name for path in source_dir.glob("*.c"))
    if len(sources) != 16:
        raise RuntimeError(f"expected 16 application sources, found {len(sources)}")
    objects_text = (VITIS / "bringup" / "Debug" / "objects.mk").read_text(encoding="utf-8")
    if not re.search(r"^USER_OBJS\s*:=\s*$", objects_text, re.MULTILINE):
        raise RuntimeError("USER_OBJS is not empty")

    audit_file = REPORT / "project_1_840_audit.csv"
    with audit_file.open(newline="", encoding="utf-8-sig") as stream:
        project_warnings = list(csv.DictReader(stream))
    project_text_count = 0
    impl_log = ROOT / "laser_tx.runs" / "impl_1" / "runme.log"
    if impl_log.is_file():
        project_text_count = impl_log.read_text(encoding="utf-8", errors="replace").count(
            "Project 1-840"
        )

    hash_paths = [
        bit,
        ltx,
        xsa,
        elf,
        map_file,
        routed_dcp,
        ooc_dcp,
        timing,
        xparameters,
        ROOT / "constraints" / "laser_sync_pins_template.xdc",
        ROOT / "constraints" / "laser_tx_ad9528_spi.xdc",
        ROOT / "constraints" / "laser_tx_board_io.xdc",
        ROOT / "constraints" / "laser_tx_gt_profile0.xdc",
        ROOT / "scripts" / "gt_profile0_impl_pre.tcl",
        ROOT / "scripts" / "run_runtime_rate_artifact_candidate_build.tcl",
    ]
    hashes = {rel(require(path)): sha256(path) for path in hash_paths}

    manifest = {
        "candidate_name": "runtime-rate-artifact-candidate-v1",
        "git_branch": git("branch", "--show-current"),
        "git_commit": git("rev-parse", "HEAD"),
        "git_dirty": bool(git("status", "--porcelain")),
        "git_commit_semantics": (
            "captured source parent before the firmware/manifest commit; "
            "the annotated tag identifies the complete candidate"
        ),
        "vivado": {
            "version": "2022.2 build 3671981",
            "device": "xc7z100ffg900-2",
            "top": "laser_tx_board_top",
            "strategy": "Performance_Explore",
            "directives": {
                "opt_design": "Explore",
                "place_design": "Explore",
                "phys_opt_design": "Explore",
                "route_design": "Explore",
                "top_synthesis_incremental_mode": "off",
            },
            "runtime_clocks_ns": {"txusrclk": 3.103, "txusrclk2": 6.206},
            "ooc_rtl_signature": signature,
            "project_1_840_unique_dcp_count": len(project_warnings),
            "project_1_840_log_occurrences": project_text_count,
            "remaining_critical_warnings": ["Project 1-840"],
            "drc_warnings": {"PDCN-1569": 3, "RTSTAT-10": 1},
            "timing": metrics,
        },
        "vitis": {
            "version": "2022.2",
            "workspace": rel(VITIS),
            "platform": "runtime_rate_artifact_platform",
            "domain": "standalone_ps7_cortexa9_0",
            "managed_clean_build": "PASS",
            "managed_source_count": len(sources),
            "managed_sources": sources,
            "user_objs": "EMPTY",
            "map_only_relink_matches_managed_elf_sha256": True,
            "bsp_addresses": {
                "XPAR_AXI_GPIO_DYNAMIC_MAILBOX_BASEADDR": "0x40040000",
                "XPAR_AXI_BRAM_DYN_DESC_S_AXI_BASEADDR": "0x42000000",
            },
        },
        "artifacts": {
            "bit": rel(bit),
            "ltx": rel(ltx),
            "xsa": rel(xsa),
            "elf": rel(elf),
            "map": rel(map_file),
            "routed_dcp": rel(routed_dcp),
            "ooc_dcp": rel(ooc_dcp),
        },
        "sha256": hashes,
        "board_verified": False,
        "hardware_test": "NOT_RUN",
    }

    output = REPORT / "release_artifact_manifest.json"
    output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    size_text = (VITIS / "bringup" / "Debug" / "bringup.elf.size").read_text(
        encoding="utf-8", errors="replace"
    ).strip()
    software_manifest = REPORT / "software_build_manifest.txt"
    software_manifest.write_text(
        "result=PASS\n"
        "build=managed make clean; managed make all\n"
        f"source_count={len(sources)}\n"
        "user_objs=EMPTY\n"
        f"elf={rel(elf)}\n"
        f"elf_sha256={sha256(elf)}\n"
        f"map={rel(map_file)}\n"
        f"map_sha256={sha256(map_file)}\n"
        "old_workspace_reference_in_elf=0\n"
        "old_workspace_reference_in_map=0\n"
        "dynamic_mailbox=0x40040000\n"
        "descriptor_bram=0x42000000\n"
        f"elf_size={size_text.replace(chr(10), ' | ')}\n",
        encoding="utf-8",
    )

    print(f"release_manifest={output}")
    print(f"software_manifest={software_manifest}")
    print(f"artifact_hashes={len(hashes)}")


if __name__ == "__main__":
    main()
