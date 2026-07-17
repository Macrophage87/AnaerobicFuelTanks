#!/usr/bin/env python3
"""R <-> Python-mirror model cross-check (issue #27, part C).

Drives the Python mirror of the Monkey C `TankModel` (tank_model.py) through the same power
traces the R reference (`simulate_tanks`) was frozen on, and asserts the two agree per second.
This directly guards R == the mirror; the mirror is a line-for-line port of the Monkey C step,
so Monkey C is guarded TRANSITIVELY (the residual mirror<->compiled-Monkey-C gap is tracked in
#61, to be closed by the on-device (:test) run once the headless simulator works).

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

Tolerance: |Δreserve| <= 0.1 J. The mirror is a line-for-line port of the same arithmetic, so
the observed max difference is ~1e-11 J (float order-of-operations only). 0.1 J sits ~9 orders
above that noise floor — enough to absorb float epsilon while catching sub-percent coefficient
drift: fault injection shows tauP +0.1% -> ~0.49 J, +1% -> ~4.8 J, +10% -> ~46 J, all far
above 0.1 J. The earlier 2%-of-W' (400 J) band was self-refuting as a divergence guard — it let
a 10% coefficient drift pass silently. If this band is ever exceeded, treat it as a genuine
model divergence and localize it — do NOT loosen the band.

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
        pctP = m.step(row["power"], 1.0)
        out.append((m.mRP, m.mRG, pctP))
    return out


def main():
    if not os.path.isdir(FIXDIR):
        print("ERROR: fixtures missing — run: Rscript tools/crosscheck/gen_fixtures.R")
        return 1

    cfg = load_config()
    wprime = cfg["Wprime"]
    tol_J = 0.1                              # reserve tolerance (J) — see module docstring
    tol_pct = 100.0 * tol_J / (cfg["fP"] * wprime)   # same band expressed in pctP points

    print("config: " + ", ".join("%s=%g" % (k, v) for k, v in sorted(cfg.items())))
    print("tolerance: reserves +/- %.3f J, pctP +/- %.4f pts (noise floor ~1e-11 J)\n"
          % (tol_J, tol_pct))

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
        worst_sec = -1                       # 1-based second with the largest reserve delta
        for i, (row, (rP, rG, pctP)) in enumerate(zip(rows, got)):
            dP = abs(rP - row["rP"])
            dG = abs(rG - row["rG"])
            dPct = abs(pctP - row["pctP"])
            if max(dP, dG) > max(max_dP, max_dG):
                worst_sec = i + 1
            max_dP = max(max_dP, dP)
            max_dG = max(max_dG, dG)
            max_dPct = max(max_dPct, dPct)

        passed = max_dP <= tol_J and max_dG <= tol_J and max_dPct <= tol_pct
        ok = ok and passed
        print("[%-8s] n=%3d  max|dRP|=%.6g J  max|dRG|=%.6g J  max|dpctP|=%.6g  (worst sec %d)  %s"
              % (name, len(rows), max_dP, max_dG, max_dPct, worst_sec,
                 "OK" if passed else "DIVERGENCE"))

    print("\n%s" % ("PASSED — R and the Python mirror agree (Monkey C guarded transitively)" if ok
                    else "FAILED — model divergence exceeds tolerance"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
