#!/usr/bin/env python3
"""Cluster Vivado full timing paths without changing timing semantics."""

from __future__ import annotations

import argparse
import csv
import re
from collections import Counter, defaultdict
from pathlib import Path


FIELD_PATTERNS = {
    "slack": re.compile(r"^Slack \((?:VIOLATED|MET)\)\s*:\s*([-0-9.]+)ns"),
    "source": re.compile(r"^\s*Source:\s+(\S+)"),
    "destination": re.compile(r"^\s*Destination:\s+(\S+)"),
    "clock": re.compile(r"^\s*Path Group:\s+(\S+)"),
    "levels": re.compile(r"^\s*Logic Levels:\s+(\d+)"),
    "primitive_summary": re.compile(r"^\s*Logic Levels:\s+\d+\s*(?:\(([^)]*)\))?"),
    "delay": re.compile(
        r"^\s*Data Path Delay:\s*([-0-9.]+)ns\s+"
        r"\(logic\s+([-0-9.]+)ns.*route\s+([-0-9.]+)ns"
    ),
}


def normalized_hierarchy(pin: str) -> str:
    cell = pin.rsplit("/", 1)[0]
    return re.sub(r"\[\d+\]", "[]", cell)


def parse_paths(report: Path) -> list[dict[str, object]]:
    paths: list[dict[str, object]] = []
    current: dict[str, object] | None = None
    for line in report.read_text(encoding="utf-8", errors="replace").splitlines():
        match = FIELD_PATTERNS["slack"].match(line)
        if match:
            if current:
                paths.append(current)
            current = {
                "slack": float(match.group(1)),
                "source": "",
                "destination": "",
                "clock": "",
                "levels": 0,
                "logic_delay": 0.0,
                "route_delay": 0.0,
                "primitive_summary": "",
                "high_fanout_nets": [],
                "resources": set(),
            }
            continue
        if current is None:
            continue
        for field in ("source", "destination", "clock", "levels"):
            match = FIELD_PATTERNS[field].match(line)
            if match:
                current[field] = int(match.group(1)) if field == "levels" else match.group(1)
                if field == "levels":
                    primitive_match = FIELD_PATTERNS["primitive_summary"].match(line)
                    current["primitive_summary"] = (
                        primitive_match.group(1) if primitive_match and primitive_match.group(1) else ""
                    )
                break
        else:
            match = FIELD_PATTERNS["primitive_summary"].match(line)
            if match:
                current["primitive_summary"] = match.group(1) or ""
                continue
            match = FIELD_PATTERNS["delay"].match(line)
            if match:
                current["logic_delay"] = float(match.group(2))
                current["route_delay"] = float(match.group(3))
                continue
            net_match = re.search(r"net \(fo=(\d+), routed\).*\s(\S+)$", line)
            if net_match:
                fanout = int(net_match.group(1))
                resource = net_match.group(2)
                current["resources"].add(resource)
                if fanout >= 64:
                    current["high_fanout_nets"].append(f"{resource}(fo={fanout})")
                continue
            resource_match = re.search(r"\s(\S+/(?:[A-Z][A-Z0-9]*|[A-Z][A-Z0-9]*\[[^]]+\]))$", line)
            if resource_match:
                current["resources"].add(resource_match.group(1))
    if current:
        paths.append(current)
    return paths


def path_cluster(source: str, destination: str) -> tuple[str, str, str]:
    combined = f"{source} {destination}"
    if "pattern_index_reg" in destination:
        return "A", "pattern_index next-state feedback", "parallelize sum and modulo candidates; use a final borrow/select mux"
    if any(name in destination for name in ("remaining_rel_q_reg", "phase_relation_q_reg")):
        return "B", "word-geometry descriptor feedback", "split descriptor comparisons and latch sequence-static fields"
    if "txdata_reg" in destination and any(
        name in combined for name in (
            "pattern_base", "phase_offset", "pattern_index", "rotate_sequence",
            "len_active", "mode"
        )
    ):
        return "C", "pattern base/index to output-word dynamic selection", "separate 63/127 networks and select mode only at the final mux"
    if any(name in combined for name in ("mode", "gap", "valid", "remaining", "advance")):
        return "D", "mode/phase/gap/remaining control or fanout", "locally register/replicate control fields inside pattern_tx_engine"
    if "ila_" in combined or "dbg_" in combined:
        return "E", "ILA/debug fanout", "drive debug from local debug registers rather than critical combinational nodes"
    return "F", "other new path", "review the primitive-level datapath before selecting an RTL change"


def primitive_counts(summary: str) -> Counter[str]:
    counts: Counter[str] = Counter()
    for primitive, count in re.findall(r"([A-Z0-9]+)=(\d+)", summary):
        counts[primitive] += int(count)
    return counts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--hold-report", type=Path)
    parser.add_argument("--summary", type=Path)
    args = parser.parse_args()

    paths = [path for path in parse_paths(args.report) if float(path["slack"]) < 0.0]
    clusters: dict[tuple[str, str, str, str], list[dict[str, object]]] = defaultdict(list)
    for path in paths:
        category, _, _ = path_cluster(str(path["source"]), str(path["destination"]))
        key = (
            category,
            str(path["clock"]),
            normalized_hierarchy(str(path["source"])),
            normalized_hierarchy(str(path["destination"])),
        )
        clusters[key].append(path)

    total_tns = sum(-float(path["slack"]) for path in paths)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as output:
        writer = csv.writer(output)
        writer.writerow(
            [
                "cluster_id",
                "path_count",
                "startpoint",
                "endpoint",
                "start_hierarchy",
                "end_hierarchy",
                "clock",
                "worst_slack_ns",
                "cluster_tns_ns",
                "tns_share_percent",
                "logic_levels",
                "logic_delay_ns",
                "route_delay_ns",
                "high_fanout_nets",
                "dominant_primitives",
                "classification",
                "suggested_action",
            ]
        )
        for index, (key, group) in enumerate(
            sorted(clusters.items(), key=lambda item: min(float(p["slack"]) for p in item[1])),
            start=1,
        ):
            category, clock, start, end = key
            worst = min(group, key=lambda path: float(path["slack"]))
            _, cause, action = path_cluster(str(worst["source"]), str(worst["destination"]))
            cluster_tns = sum(-float(path["slack"]) for path in group)
            primitives: Counter[str] = Counter()
            high_fanout: set[str] = set()
            for path in group:
                primitives.update(primitive_counts(str(path["primitive_summary"])))
                high_fanout.update(str(net) for net in path["high_fanout_nets"])
            writer.writerow(
                [
                    f"cluster_{index}",
                    len(group),
                    worst["source"],
                    worst["destination"],
                    start,
                    end,
                    clock,
                    f"{min(float(p['slack']) for p in group):.3f}",
                    f"{-cluster_tns:.3f}",
                    f"{(100.0 * cluster_tns / total_tns) if total_tns else 0.0:.1f}",
                    max(int(p["levels"]) for p in group),
                    f"{max(float(p['logic_delay']) for p in group):.3f}",
                    f"{max(float(p['route_delay']) for p in group):.3f}",
                    ";".join(sorted(high_fanout)),
                    ";".join(f"{name}={count}" for name, count in primitives.most_common()),
                    f"{category}: {cause}",
                    action,
                ]
            )
    if args.summary:
        top10 = sorted(paths, key=lambda path: float(path["slack"]))[:10]
        top10_classes = [path_cluster(str(p["source"]), str(p["destination"]))[0] for p in top10]
        hold_paths = parse_paths(args.hold_report) if args.hold_report else []
        setup_resources = set().union(*(p["resources"] for p in paths)) if paths else set()
        hold_resources = set().union(*(p["resources"] for p in hold_paths[:50])) if hold_paths else set()
        shared = sorted(
            resource for resource in setup_resources & hold_resources
            if "txusrclk" not in resource and "BUFG" not in resource
        )
        args.summary.parent.mkdir(parents=True, exist_ok=True)
        args.summary.write_text(
            "\n".join(
                [
                    f"setup_failing_endpoints={len({str(p['destination']) for p in paths})}",
                    f"setup_top100_negative_paths={len(paths)}",
                    f"setup_tns_ns={-total_tns:.3f}",
                    f"top10_classifications={','.join(top10_classes)}",
                    f"top10_single_classification={int(len(set(top10_classes)) == 1)}",
                    f"setup_hold_shared_nonclock_resources={len(shared)}",
                    f"setup_hold_shared_resource_list={';'.join(shared)}",
                ]
            ) + "\n",
            encoding="utf-8",
        )
    print(f"parsed_paths={len(paths)} clusters={len(clusters)} output={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
