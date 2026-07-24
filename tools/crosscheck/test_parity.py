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
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tank_model import TankModel  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
FIXDIR = os.path.join(HERE, "fixtures")
TRACES = ["sprint", "supra", "interval", "aer_excess"]
# #88 Flip-A: per-trace config routing. `aer_excess` uses its OWN config (config_eaer.csv, with
# eAerMax/tauE baked in) so the E>0 path is exercised R<->Python WITHOUT turning E on for the other
# traces — dropping eAerMax>0 into the shared config.csv would break the OFF-path byte-identical parity.
TRACE_CONFIG = {"aer_excess": "config_eaer"}


def load_config(name="config"):
    path = os.path.join(FIXDIR, "%s.csv" % name)
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


def check_dt(cfg):
    """#83: exercise the dt != 1 path the parity/fixture traces (all dt=1) never touch.

    Every rate/energy term in step() scales with dt (need=delta*dt, pcap/gcap=rate*dt,
    kOn/kA/kG=1-exp(-dt/tau), mConsP=takeP/dt) and the caller guards dt<=0. By conservation the
    COMBINED depletion (rP draw + rG draw + banked deficit) equals the demanded need=(P-CP)*dt
    regardless of how step() splits it, so it must scale exactly linearly with dt. reset() starts
    the aerobic tracker warm (aer=cp), so supply==cp and delta==(P-CP) is dt-independent.
    Returns True iff every dt property holds.
    """
    P = cfg["cp"] + 200.0                    # supra-CP: demand the tanks must cover
    u = P - cfg["cp"]                        # need per second = delta

    def dep_after(dt, steps=1):
        m = TankModel()
        m.configure(cfg)
        m.reset()
        for _ in range(steps):
            m.step(P, dt)
        dep = (m.mCapP - m.mRP) + (m.mCapG - m.mRG) + m.mDeficit
        return dep, m

    d1, _ = dep_after(1.0)
    d2, m2 = dep_after(2.0)
    d05, m05 = dep_after(0.5)
    d11, _ = dep_after(1.0, steps=2)         # one 2 s step must equal two 1 s steps
    tol = 1e-6
    checks = [
        ("dep(1s)==need", abs(d1 - u) <= tol),
        ("dep(2s)==2*need", abs(d2 - 2.0 * u) <= tol),
        ("dep(.5s)==need/2", abs(d05 - 0.5 * u) <= tol),
        ("2s==two 1s", abs(d2 - d11) <= tol),
        ("consP finite@dt=.5", math.isfinite(m05.mConsP) and m05.mConsP > 0.0),
    ]

    # dt<=0 guard: integrate nothing, zero the live draw, stay finite — never divide by dt.
    mz = TankModel()
    mz.configure(cfg)
    mz.reset()
    rp0, rg0, def0 = mz.mRP, mz.mRG, mz.mDeficit
    r0 = mz.step(P, 0.0)
    checks += [
        ("dt=0 holds state", mz.mRP == rp0 and mz.mRG == rg0 and mz.mDeficit == def0),
        ("dt=0 zero draw", mz.mConsP == 0.0 and mz.mConsG == 0.0),
        ("dt=0 finite pctP", math.isfinite(r0)),
    ]

    passed = all(ok for _, ok in checks)
    print("[dt-scale] " + "  ".join("%s:%s" % (n, "OK" if ok else "FAIL") for n, ok in checks))
    return passed


def check_eaer(cfg):
    """#86 Phase 2: the gated above-CP aerobic-excess term. OFF (eAerMax=0) is byte-identical to the
    hard-CP model (the fixtures already prove that). ON (eAerMax>0) lets aerobic supply exceed CP
    during supra-CP work, so the combined reserve depletes LESS. This mirrors the R simulate_tanks
    term line-for-line; test-aer_excess.R guards R and Tests.mc::testAerExcess guards Monkey C.
    """
    P = cfg["cp"] + 150.0                    # supra-CP so the excess ramps in

    def run(eaer):
        c = dict(cfg)
        c["eAerMax"] = eaer
        m = TankModel()
        m.configure(c)
        m.reset()
        for _ in range(300):                 # 5 min above CP
            m.step(P, 1.0)
        dep = (m.mCapP - m.mRP) + (m.mCapG - m.mRG) + m.mDeficit
        return dep, m

    d_off, m_off = run(0.0)
    d_on, m_on = run(30.0)
    checks = [
        ("off: E stays 0", m_off.mE == 0.0),
        ("on: E ramps up", m_on.mE > 0.0),
        ("on: E capped", m_on.mE <= 30.0 + 1e-9),
        ("on depletes less", d_on < d_off),
    ]
    passed = all(ok for _, ok in checks)
    print("[eaer]     " + "  ".join("%s:%s" % (n, "OK" if ok else "FAIL") for n, ok in checks))
    return passed


def main():
    if not os.path.isdir(FIXDIR):
        print("ERROR: fixtures missing — run: Rscript tools/crosscheck/gen_fixtures.R")
        return 1

    base = load_config()                     # config.csv — the OFF-path config for the canonical traces
    tol_J = 0.1                              # reserve tolerance (J) — see module docstring

    _configs = {"config": base}
    def cfg_for(name):                       # #88 Flip-A: route each trace to its config (default off)
        cname = TRACE_CONFIG.get(name, "config")
        if cname not in _configs:
            _configs[cname] = load_config(cname)
        return _configs[cname]

    print("config: " + ", ".join("%s=%g" % (k, v) for k, v in sorted(base.items())))
    print("tolerance: reserves +/- %.3f J (noise floor ~1e-11 J)\n" % tol_J)

    ok = True
    for name in TRACES:
        try:
            rows = load_trace(name)
        except FileNotFoundError:
            print("[%s] MISSING fixture — run gen_fixtures.R" % name)
            ok = False
            continue

        cfg = cfg_for(name)
        tol_pct = 100.0 * tol_J / (cfg["fP"] * cfg["Wprime"])   # pctP band for THIS trace's config
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

    # #83: dt-scaling / dt<=0 guard on the mirror (the fixtures only ever run dt=1).
    ok = check_dt(base) and ok
    # #86 Phase 2: the gated above-CP aerobic-excess term on the mirror (fixtures keep it off).
    ok = check_eaer(base) and ok

    print("\n%s" % ("PASSED — R and the Python mirror agree (Monkey C guarded transitively)" if ok
                    else "FAILED — model divergence exceeds tolerance"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
