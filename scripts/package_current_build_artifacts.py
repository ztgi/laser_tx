#!/usr/bin/env python3
"""Package explicitly selected FPGA/Vitis artifacts with provenance.

This tool intentionally never searches for the newest artifact.  Every input
path must be supplied by the caller, and existing bundle/archive paths are
rejected to prevent silent replacement of a known-good package.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path


ARTIFACT_NAMES = {
    "bit": "hardware/{stem}.bit",
    "ltx": "hardware/{stem}.ltx",
    "xsa": "hardware/{stem}.xsa",
    "elf": "software/laser_tx_udp_bringup.elf",
}

REPORT_NAMES = {
    "timing": "reports/timing_summary.rpt",
    "drc": "reports/drc.rpt",
    "route": "reports/route_status.rpt",
    "debug_cores": "reports/debug_cores.rpt",
    "utilization": "reports/utilization.rpt",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", required=True, type=Path)
    parser.add_argument("--output-root", required=True, type=Path)
    parser.add_argument("--bundle-name", required=True)
    parser.add_argument("--archive-stem", required=True)
    parser.add_argument("--artifact-stem", required=True)
    parser.add_argument("--bit", required=True, type=Path)
    parser.add_argument("--ltx", required=True, type=Path)
    parser.add_argument("--xsa", required=True, type=Path)
    parser.add_argument("--elf", required=True, type=Path)
    parser.add_argument("--timing", required=True, type=Path)
    parser.add_argument("--drc", required=True, type=Path)
    parser.add_argument("--route", required=True, type=Path)
    parser.add_argument("--debug-cores", required=True, type=Path)
    parser.add_argument("--utilization", required=True, type=Path)
    parser.add_argument("--readme-template", required=True, type=Path)
    parser.add_argument("--source-git-branch", required=True)
    parser.add_argument("--source-git-commit", required=True)
    parser.add_argument("--hardware-git-commit", required=True)
    parser.add_argument("--software-git-commit", required=True)
    parser.add_argument("--source-git-dirty", choices=("true", "false"), required=True)
    parser.add_argument("--source-dirty-file", action="append", default=[])
    parser.add_argument("--vivado-version", required=True)
    parser.add_argument("--vitis-version", required=True)
    parser.add_argument("--top-module", required=True)
    parser.add_argument("--implementation-run", required=True)
    parser.add_argument("--hardware-validation-state", required=True)
    parser.add_argument("--board-verified", choices=("true", "false"), required=True)
    parser.add_argument("--board-test-planned", choices=("true", "false"), required=True)
    parser.add_argument("--bit-ltx-same-implementation", choices=("true", "false"), required=True)
    parser.add_argument("--elf-built-from-bundle-xsa", choices=("true", "false"), required=True)
    parser.add_argument("--setup-wns-ns", type=float)
    parser.add_argument("--hold-whs-ns", type=float)
    parser.add_argument("--tns-ns", type=float)
    parser.add_argument("--ths-ns", type=float)
    parser.add_argument("--drc-errors", type=int)
    parser.add_argument("--route-errors", type=int)
    parser.add_argument("--note", action="append", default=[])
    return parser.parse_args()


def checked_file(path: Path, label: str) -> Path:
    resolved = path.expanduser().resolve()
    if not resolved.is_file():
        raise RuntimeError(f"{label} does not exist or is not a file: {resolved}")
    if resolved.stat().st_size == 0:
        raise RuntimeError(f"{label} is empty: {resolved}")
    return resolved


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def git_text(repo_root: Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(repo_root), *args], text=True, encoding="utf-8"
    ).strip()


def file_entry(kind: str, source: Path, bundle_path: Path) -> dict[str, object]:
    stat = source.stat()
    return {
        "type": kind,
        "bundle_path": bundle_path.as_posix(),
        "original_path": str(source),
        "sha256": sha256(source),
        "size_bytes": stat.st_size,
        "generated_at": datetime.fromtimestamp(stat.st_mtime, timezone.utc).isoformat(),
    }


def main() -> int:
    args = parse_args()
    repo_root = args.repo_root.resolve()
    output_root = args.output_root.resolve()
    bundle_dir = output_root / args.bundle_name
    archive_path = output_root / f"{args.archive_stem}.zip"
    archive_sha_path = output_root / f"{args.archive_stem}.zip.sha256"

    if bundle_dir.exists() or archive_path.exists() or archive_sha_path.exists():
        raise RuntimeError(
            "Refusing to overwrite existing package output: "
            f"{bundle_dir}, {archive_path}, or {archive_sha_path}"
        )

    source_paths = {
        "bit": checked_file(args.bit, "bit"),
        "ltx": checked_file(args.ltx, "ltx"),
        "xsa": checked_file(args.xsa, "xsa"),
        "elf": checked_file(args.elf, "elf"),
    }
    report_paths = {
        "timing": checked_file(args.timing, "timing report"),
        "drc": checked_file(args.drc, "DRC report"),
        "route": checked_file(args.route, "route report"),
        "debug_cores": checked_file(args.debug_cores, "debug-core report"),
        "utilization": checked_file(args.utilization, "utilization report"),
    }
    readme_template = checked_file(args.readme_template, "README template")

    packaging_commit = git_text(repo_root, "rev-parse", "HEAD")
    packaging_branch = git_text(repo_root, "branch", "--show-current")
    packaging_dirty = bool(git_text(repo_root, "status", "--porcelain"))
    packaging_dirty_files = [
        line for line in git_text(repo_root, "status", "--short").splitlines() if line
    ]

    bundle_dir.mkdir(parents=True)
    copied_entries: list[dict[str, object]] = []
    for kind, source in source_paths.items():
        relative = Path(ARTIFACT_NAMES[kind].format(stem=args.artifact_stem))
        destination = bundle_dir / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        copied_entries.append(file_entry(kind, source, relative))

    report_entries: list[dict[str, object]] = []
    for kind, source in report_paths.items():
        relative = Path(REPORT_NAMES[kind])
        destination = bundle_dir / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        report_entries.append(file_entry(kind, source, relative))

    shutil.copy2(readme_template, bundle_dir / "README.md")

    manifest = {
        "bundle_name": args.bundle_name,
        "git_branch": args.source_git_branch,
        "git_commit": args.source_git_commit,
        "git_dirty": args.source_git_dirty == "true",
        "source_dirty_files": args.source_dirty_file,
        "hardware_git_commit": args.hardware_git_commit,
        "software_git_commit": args.software_git_commit,
        "packaging_git_branch": packaging_branch,
        "packaging_git_commit": packaging_commit,
        "packaging_git_dirty": packaging_dirty,
        "packaging_dirty_files": packaging_dirty_files,
        "vivado_version": args.vivado_version,
        "vitis_version": args.vitis_version,
        "top_module": args.top_module,
        "implementation_run": args.implementation_run,
        "hardware_validation_state": args.hardware_validation_state,
        "board_verified": args.board_verified == "true",
        "board_test_planned": args.board_test_planned == "true",
        "files": copied_entries,
        "reports": report_entries,
        "bit_ltx_same_implementation": args.bit_ltx_same_implementation == "true",
        "elf_built_from_bundle_xsa": args.elf_built_from_bundle_xsa == "true",
        "timing": {
            "setup_wns_ns": args.setup_wns_ns,
            "hold_whs_ns": args.hold_whs_ns,
            "tns_ns": args.tns_ns,
            "ths_ns": args.ths_ns,
        },
        "drc_errors": args.drc_errors,
        "route_errors": args.route_errors,
        "notes": args.note,
    }
    (bundle_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    with zipfile.ZipFile(archive_path, "x", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(bundle_dir.rglob("*")):
            if path.is_file():
                archive.write(path, Path(args.bundle_name) / path.relative_to(bundle_dir))

    archive_hash = sha256(archive_path)
    archive_sha_path.write_text(
        f"{archive_hash}  {archive_path.name}\n", encoding="ascii"
    )
    print(json.dumps({
        "bundle_dir": str(bundle_dir),
        "archive": str(archive_path),
        "archive_sha256": archive_hash,
        "manifest": str(bundle_dir / "manifest.json"),
    }, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # concise CLI failure with non-zero exit
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
