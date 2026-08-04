"""Fail-closed structural check for the self-maintained GT adapter."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
GOLDEN = ROOT / "laser_tx.srcs/sources_1/imports/sources_1/ip/gtwizard_0/gtwizard_0.v"
ADAPTER = ROOT / "laser_tx.srcs/sources_1/new/gtwizard_0_adapter.v"
GT = ROOT / "laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0_gt.v"
XCI = ROOT / "laser_tx.srcs/sources_1/ip/gtwizard_0/gtwizard_0.xci"

PORT_RE = re.compile(r"\b(input|output)\s+(?:wire\s+)?(\[[^]]+\]\s+)?([A-Za-z0-9_]+)")


def ports(path: Path, module: str):
    text = path.read_text(encoding="utf-8", errors="ignore")
    start = text.index("module " + module)
    body = text[start:text.index(");", start) + 2]
    result = {}
    for direction, width, name in PORT_RE.findall(body):
        result[name] = (direction, (width or "").strip())
    return result


def require(condition, message):
    if not condition:
        raise SystemExit("GTWIZARD_ADAPTER_EQUIVALENCE_FAIL: " + message)


golden = ports(GOLDEN, "gtwizard_0")
adapter = ports(ADAPTER, "gtwizard_0_adapter")
require(golden == adapter, f"top port signature differs; missing={sorted(set(golden)-set(adapter))}, extra={sorted(set(adapter)-set(golden))}")

adapter_text = ADAPTER.read_text(encoding="utf-8", errors="ignore")
gt_text = GT.read_text(encoding="utf-8", errors="ignore")
xci_text = XCI.read_text(encoding="utf-8", errors="ignore")
require(".cpllrefclksel_in      (gt0_cpllrefclksel_in)" in adapter_text,
        "runtime CPLLREFCLKSEL is not forwarded by adapter")
require(".CPLLREFCLKSEL                  (cpllrefclksel_in)" in gt_text,
        "generated lower primitive does not expose CPLLREFCLKSEL")
require("GTNORTHREFCLK0                 (gtnorthrefclk0_in)" in gt_text,
        "generated lower primitive north refclk is not connected")
require('"advanced_clocking": [ { "value": "true"' in xci_text,
        "local XCI is not configured with Advanced Clocking")
require('"gt0_val_tx_refclk": [ { "value": "REFCLK0_Q0"' in xci_text,
        "local XCI reference-clock enum is not REFCLK0_Q0")

attrs = {
    "TX_DATA_WIDTH": "TX_DATA_WIDTH bound to: 64",
    "TX_INT_DATAWIDTH": "TX_INT_DATAWIDTH bound to: 1",
    "TXOUT_DIV": "TXOUT_DIV bound to: 8",
    "CPLL_REFCLK_DIV": "CPLL_REFCLK_DIV bound to: 1",
    "CPLL_FBDIV": "CPLL_FBDIV bound to: 4",
}
for name, _ in attrs.items():
    require(name in gt_text, f"generated lower HDL missing {name}")

print("GTWIZARD_ADAPTER_EQUIVALENCE_PASS")
print(f"ports={len(adapter)} generated_lower={GT}")
print("CPLLREFCLKSEL=runtime; GTNORTHREFCLK0=forwarded; QPLL shared clocks=forwarded")
