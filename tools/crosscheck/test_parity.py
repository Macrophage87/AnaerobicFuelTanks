#!/usr/bin/env python3
"""R <-> Monkey C model cross-check (issue #27, part C).

Drives the Python mirror of the Monkey C `TankModel` (tank_model.py) through the same power
traces the R reference (`simulate_tanks`) was frozen on, and asserts the two agree per second.

Design decisions locked in from the part-C review:
  * IDENTICAL EXPLICIT CONFIG on both sides — the two codebases embed different fallback
    defaults, so the mirror is configured from fixtures/config.csv, the exact settings the R
    generator used. No implicit defaults on either side.
  * COMPARE PER-TANK rP / rG DIRECTLY — not `total = rP + rG - cumsum(deficit)`. R's internal
    deficit D decays during recovery, so a cumulative-deficit invariant overstates it and is
    the wrong contract; the per-tank reserves are the like-for-like quantity vs Monkey C's
    mRP / mRG (which do NOT subtract mDeficit).
  * WARM aerobic start + FULL state init on the mirror side (see tank_model.py) so the
    integrators are comparable from t=0.

Tolerance: |Δreserve| <= 2% of W' (J), the documented contract band. In practice the mirror is
a line-for-line port of the same arithmetic, so the observed max difference is ~float epsilon;
the band exists to absorb float order-of-operations, not to hide a real divergence. If it is
ever exceeded, treat it as a genuine model divergence and localize it — do NOT loosen the band.

Run directly (no pytest needed):  python3 tools/crosscheck/test_parity.py
Exit code 0 = parity holds, 1 = divergence (or missing fixtures — regenerate with
Rscript tools/crosscheck/gen_fixtures.R).
"""

import csv
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tank_model import TankModel  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
FIXDIR = os.path.join(HERE, "fixtures")
TRACES = ["sprint", "supra", "interval"]


def load_config():
    path = os.path.join(FIXDIR, "config.csv")
    cfg = {}
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            cfg[row["param"]] = float(row["value"])
    return cfg


def load_trace(name):
    path = os.path.join(FIXDIR, "%s.csv" % name)
    rows = []
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            rows.append(
                {
                    "power": float(row["power"]),
                    "rP": float(row["rP"]),
                    "rG": float(row["rG"]),
                    "pctP": float(row["pctP"]),
                }
            )
    return rows


def run_trace(cfg, rows):
    """Return the mirror's per-second (rP, rG, pctP)."""
    m = TankModel()
    m.configure(cfg)
    m.reset()
    out = []
    for row in rows:
        pctP = m.step(row["power"])
        out.append((m.mRP, m.mRG, pctP))
    return out


def main():
    if not os.path.isdir(FIXDIR):
        print("ERROR: fixtures missing — run: Rscript tools/crosscheck/gen_fixtures.R")
        return 1

    cfg = load_config()
    wprime = cfg["Wprime"]
    tol_J = 0.02 * wprime                    # reserve tolerance: 2% of W'
    tol_pct = 100.0 * tol_J / (cfg["fP"] * wprime)   # same band expressed in pctP points

    print("config: " + ", ".join("%s=%g" % (k, v) for k, v in sorted(cfg.items())))
    print("tolerance: reserves +/- %.1f J (2%% of W'=%.0f), pctP +/- %.2f pts\n"
          % (tol_J, wprime, tol_pct))

    ok = True
    for name in TRACES:
        try:
            rows = load_trace(name)
        except FileNotFoundError:
            print("[%s] MISSING fixture — run gen_fixtures.R" % name)
            ok = False
            continue

        got = run_trace(cfg, rows)
        max_dP = max_dG = max_dPct = 0.0
        worst_sec = -1
        for i, (row, (rP, rG, pctP)) in enumerate(zip(rows, got)):
            dP = abs(rP - row["rP"])
            dG = abs(rG - row["rG"])
            dPct = abs(pctP - row["pctP"])
            if dP > max_dP:
                max_dP = dP
            if dG > max_dG:
                max_dG = dG
            if max(dP, dG) == max(max_dP, max_dG):
                worst_sec = i + 1
            if dPct > max_dPct:
                max_dPct = dPct

        passed = max_dP <= tol_J and max_dG <= tol_J and max_dPct <= tol_pct
        ok = ok and passed
        print("[%-8s] n=%3d  max|dRP|=%.6g J  max|dRG|=%.6g J  max|dpctP|=%.6g  (worst sec %d)  %s"
              % (name, len(rows), max_dP, max_dG, max_dPct, worst_sec,
                 "OK" if passed else "DIVERGENCE"))

    print("\n%s" % ("PASSED — R and Monkey C models agree" if ok
                    else "FAILED — model divergence exceeds tolerance"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
