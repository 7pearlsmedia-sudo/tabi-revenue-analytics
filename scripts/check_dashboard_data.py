"""Verify that dashboard/data/*.json matches what is committed in git.

Run after scripts/export_dashboard.py. Numbers are compared with a small
relative tolerance, because floating-point sums can differ in the last digits
between machines. Exits non-zero if the published figures would change.
"""

from __future__ import annotations

import json
import math
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "dashboard" / "data"
REL_TOL = 1e-6


def committed(path: Path):
    rel = path.relative_to(ROOT).as_posix()
    out = subprocess.run(["git", "show", f"HEAD:{rel}"], cwd=ROOT, capture_output=True, text=True)
    if out.returncode != 0:
        return None
    return json.loads(out.stdout)


def diff(a, b, where: str) -> list[str]:
    if isinstance(a, dict) and isinstance(b, dict):
        if a.keys() != b.keys():
            return [f"{where}: keys differ"]
        return [d for k in a for d in diff(a[k], b[k], f"{where}.{k}")]
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            return [f"{where}: length {len(a)} != {len(b)}"]
        return [d for i, (x, y) in enumerate(zip(a, b)) for d in diff(x, y, f"{where}[{i}]")]
    if isinstance(a, (int, float)) and isinstance(b, (int, float)) and not isinstance(a, bool):
        if math.isclose(a, b, rel_tol=REL_TOL, abs_tol=1e-6):
            return []
        return [f"{where}: {b} -> {a}"]
    return [] if a == b else [f"{where}: {b!r} -> {a!r}"]


def main() -> int:
    problems: list[str] = []
    for path in sorted(DATA.glob("*.json")):
        old = committed(path)
        if old is None:
            problems.append(f"{path.name}: not committed")
            continue
        problems += diff(json.loads(path.read_text(encoding="utf-8")), old, path.name)
    if problems:
        print("Dashboard data differs from the committed copy:")
        for p in problems[:50]:
            print("  " + p)
        return 1
    print(f"Dashboard data reproduced exactly (rel. tolerance {REL_TOL}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
