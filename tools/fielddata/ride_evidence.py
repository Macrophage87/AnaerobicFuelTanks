#!/usr/bin/env python3
"""Regenerate every figure this repository publishes from one field ride, from the
committed text fixtures alone (docs/agents/rituals/FIELD_DATA.md section 1: a
recording is not evidence until something committed can regenerate every figure
taken from it).

INPUT. The three fixtures tools/fielddata/extract_ride_fixture.py writes for one
ride label:
  <label>.series.csv     t,power,PCr_J,GLY_J -- one row per record message
  <label>.events.csv     t,event_type        -- timer events
  <label>.inventory.txt  tab-separated field_description inventory, every app
Columns are read BY NAME. The loader REFUSES (exit 2, "REFUSED: ...") a ragged
row, a missing or duplicated column, a malformed cell, a non-increasing series
time, a cross-checks header line that disagrees with the rows, an inventory whose
"ours" rows are not exactly PCr_J + GLY_J under the provenance's index, and three
files whose shared provenance block differs (a series and events file from two
different rides must never be analysed together).

ABSENCE. An empty cell is an absent field, never zero (the fixture header says
so). Absent values are counted, and excluded from every statistic that needs
them; nothing is filled.

OUTPUT. A human-readable line per figure, and a machine-readable line
    RIDEFACT <key> <value...>
per figure. `--check <doc>` compares the RIDEFACT lines in <doc> with the ones
computed now, as an ordered list, and exits 1 naming every disagreement: the
evidence note cannot drift from the fixtures silently.

DEFINITIONS (FIELD_DATA.md section 5: publish the definition with the number).
  spacing       seconds between consecutive records.
  boundary      a timer stop event immediately followed by a start event, with a
                record at/before the stop and a record at/after the start. "before"
                is the last record at t <= stop, "after" the first at t >= start,
                "next" the record after "after". latch = after's value equals
                before's exactly (float equality of the 9-significant-digit
                values, which round-trip float32 exactly).
  draw d[t]     max(0, PCr[t-1] - PCr[t]) + max(0, GLY[t-1] - GLY[t]), defined only
                where the record at t follows the previous record by exactly 1 s
                and all four reserve values are present.
  lag_r L       Pearson r between power at time t-L and d[t], pairs keyed by TIME
                (a record must exist at t-L with power present). This is the
                primary definition: a pair can never straddle a pause.
  lag_r_index L the same, keyed by RECORD INDEX (power of record i-L). Printed as
                the alternative definition because it is what a naive array shift
                computes; at L=+2 it pairs power from before a pause with the draw
                after it.
  threshold L   over integer CP from 0 to the maximum paired power, misclassified =
                #(d > 0.5 J and power <= CP) + #(d <= 0.5 J and power > CP), on the
                time-keyed pairs. Best CP is the LOWEST CP attaining the minimum; the
                highest CP attaining it is printed too, so a tie is visible.

Stdlib only. Usage:
  python3 tools/fielddata/ride_evidence.py [--fixtures DIR] [--label LABEL]
  python3 tools/fielddata/ride_evidence.py --check docs/fielddata/<label>.md
"""

import argparse
import bisect
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_FIXTURES = os.path.join(HERE, "fixtures")
DEFAULT_LABEL = "ride-2026-09-20-edge1050"
OURS = ("PCr_J", "GLY_J")
MARK = "RIDEFACT"
DRAW_THRESHOLD_J = 0.5
LAGS = (-1, 0, 1, 2)

SERIES_COLS = ("t", "power", "PCr_J", "GLY_J")
EVENTS_COLS = ("t", "event_type")
INVENTORY_COLS = ("index", "field", "name", "type", "bytes", "units", "mesg", "ours")


class Refused(Exception):
    pass


# ------------------------------------------------------------------ loading --

def read_table(path, sep, required):
    """Returns (comment_lines, rows as dicts keyed by column name). Refuses a
    missing file, no header, a duplicated or missing required column, and any
    row whose cell count differs from the header's."""
    if not os.path.isfile(path):
        raise Refused("%s: no such fixture" % path)
    comments, header, rows = [], None, []
    # Text mode with universal newlines: the fixtures land CRLF on a Windows
    # checkout (core.autocrlf=true, FACTS.md 4.1) and LF in CI.
    with open(path, encoding="utf-8") as fh:
        for lineno, raw in enumerate(fh, 1):
            line = raw.rstrip("\r\n")
            if header is None:
                if line.startswith("#"):
                    comments.append(line)
                    continue
                header = line.split(sep)
                dup = sorted({c for c in header if header.count(c) > 1})
                if dup:
                    raise Refused("%s:%d: duplicated column(s) %s" % (path, lineno, ", ".join(dup)))
                missing = [c for c in required if c not in header]
                if missing:
                    raise Refused("%s:%d: missing column(s) %s (header is %r)"
                                  % (path, lineno, ", ".join(missing), line))
                continue
            cells = line.split(sep)
            if len(cells) != len(header):
                raise Refused("%s:%d: ragged row: %d cell(s) where the header has %d"
                              % (path, lineno, len(cells), len(header)))
            row = dict(zip(header, cells))
            row["_line"] = lineno
            rows.append(row)
    if header is None:
        raise Refused("%s: no header line" % path)
    return comments, rows


def cell_int(row, col, path):
    try:
        return int(row[col])
    except ValueError:
        raise Refused("%s:%d: column %s is not an integer: %r" % (path, row["_line"], col, row[col]))


def cell_opt(row, col, path, conv):
    """Empty cell -> None (absent); otherwise conv, refusing a malformed or
    non-finite value."""
    v = row[col]
    if v == "":
        return None
    try:
        x = conv(v)
    except ValueError:
        raise Refused("%s:%d: column %s is malformed: %r" % (path, row["_line"], col, v))
    if isinstance(x, float) and not math.isfinite(x):
        raise Refused("%s:%d: column %s is not finite: %r" % (path, row["_line"], col, v))
    return x


def provenance(comments, path):
    """The block of header lines shared by all three fixtures: everything before
    the first '#   values' line."""
    block = []
    for c in comments:
        if c.startswith("#   values"):
            break
        block.append(c)
    if not block or len(block) == len(comments):
        raise Refused("%s: no provenance block ahead of a '#   values' line" % path)
    return block


def cross_checks(comments, path):
    for c in comments:
        if c.startswith("#   cross-checks"):
            return c[len("#   cross-checks"):].strip()
    raise Refused("%s: no '#   cross-checks' header line" % path)


def fmt(x):
    """float32 values as the fixture spells them: 9 significant digits."""
    return "%.9g" % x


def load(fixtures, label):
    base = os.path.join(fixtures, label)
    sp, ep, ip = base + ".series.csv", base + ".events.csv", base + ".inventory.txt"
    sc, srows = read_table(sp, ",", SERIES_COLS)
    ec, erows = read_table(ep, ",", EVENTS_COLS)
    ic, irows = read_table(ip, "\t", INVENTORY_COLS)

    prov = provenance(sc, sp)
    for path, com in ((ep, ec), (ip, ic)):
        other = provenance(com, path)
        if other != prov:
            first = next((i for i in range(max(len(prov), len(other)))
                          if i >= len(prov) or i >= len(other) or prov[i] != other[i]), 0)
            raise Refused("series/%s mismatch: the provenance blocks differ at header line %d "
                          "(%r vs %r) -- these fixtures are not from the same ride"
                          % (os.path.basename(path), first + 1,
                             prov[first] if first < len(prov) else None,
                             other[first] if first < len(other) else None))

    # series
    t = [cell_int(r, "t", sp) for r in srows]
    if not t:
        raise Refused("%s: no records" % sp)
    for i in range(1, len(t)):
        if t[i] <= t[i - 1]:
            raise Refused("%s:%d: t does not increase (%d after %d)"
                          % (sp, srows[i]["_line"], t[i], t[i - 1]))
    power = [cell_opt(r, "power", sp, int) for r in srows]
    pcr = [cell_opt(r, "PCr_J", sp, float) for r in srows]
    gly = [cell_opt(r, "GLY_J", sp, float) for r in srows]
    m = re.fullmatch(r"records (\d+); first PCr_J (\S*), GLY_J (\S*); last t (-?\d+)",
                     cross_checks(sc, sp))
    if not m:
        raise Refused("%s: cross-checks line not in the extractor's shape" % sp)
    got = (str(len(t)), "" if pcr[0] is None else fmt(pcr[0]),
           "" if gly[0] is None else fmt(gly[0]), str(t[-1]))
    if m.groups() != got:
        raise Refused("%s: cross-checks header says %r, the rows give %r" % (sp, m.groups(), got))

    # events
    et = [cell_int(r, "t", ep) for r in erows]
    etype = [r["event_type"] for r in erows]
    for i, e in enumerate(etype):
        if not e:
            raise Refused("%s:%d: empty event_type" % (ep, erows[i]["_line"]))
    for i in range(1, len(et)):
        if et[i] < et[i - 1]:
            raise Refused("%s:%d: event t decreases (%d after %d)"
                          % (ep, erows[i]["_line"], et[i], et[i - 1]))
    m = re.fullmatch(r"(\d+) timer events", cross_checks(ec, ep))
    if not m or int(m.group(1)) != len(et):
        raise Refused("%s: cross-checks header disagrees with the %d event rows" % (ep, len(et)))

    # inventory
    inv = []
    for r in irows:
        if r["ours"] not in ("", "yes"):
            raise Refused("%s:%d: ours must be empty or 'yes', not %r" % (ip, r["_line"], r["ours"]))
        inv.append({"index": cell_int(r, "index", ip), "field": cell_int(r, "field", ip),
                    "name": r["name"], "type": r["type"], "bytes": cell_int(r, "bytes", ip),
                    "units": r["units"], "mesg": r["mesg"], "ours": r["ours"] == "yes"})
    m = re.search(r"developer_data_index (\d+), application_id ([0-9a-f]*) "
                  r"\(manifest id is ([0-9a-f]*)\)", "\n".join(prov))
    if not m:
        raise Refused("%s: provenance has no 'ours' line naming the index and application ids" % sp)
    our_idx, app_id, manifest_id = int(m.group(1)), m.group(2), m.group(3)
    ours = [d for d in inv if d["ours"]]
    if sorted(d["name"] for d in ours) != sorted(OURS) or {d["index"] for d in ours} != {our_idx}:
        raise Refused("%s: the 'ours' rows must be exactly %s under developer_data_index %d; got %r"
                      % (ip, " + ".join(OURS), our_idx,
                         [(d["index"], d["name"]) for d in ours]))

    return {"t": t, "power": power, "PCr_J": pcr, "GLY_J": gly,
            "ev_t": et, "ev_type": etype, "inv": inv,
            "our_idx": our_idx, "app_id": app_id, "manifest_id": manifest_id}


# ------------------------------------------------------------- the figures --

def pearson(xs, ys):
    n = len(xs)
    if n < 2:
        return float("nan")
    mx, my = sum(xs) / n, sum(ys) / n
    sxy = sum((a - mx) * (b - my) for a, b in zip(xs, ys))
    sxx = sum((a - mx) ** 2 for a in xs)
    syy = sum((b - my) ** 2 for b in ys)
    if sxx == 0 or syy == 0:
        return float("nan")
    return sxy / math.sqrt(sxx * syy)


def draws(R):
    """d[i] for every record i on a 1 s step with all four reserve values present."""
    t, p, g = R["t"], R["PCr_J"], R["GLY_J"]
    d = {}
    for i in range(1, len(t)):
        if t[i] - t[i - 1] != 1:
            continue
        if None in (p[i - 1], p[i], g[i - 1], g[i]):
            continue
        d[i] = max(0.0, p[i - 1] - p[i]) + max(0.0, g[i - 1] - g[i])
    return d


def lag_pairs(R, d, lag, keyed):
    t, pw = R["t"], R["power"]
    bytime = {tt: i for i, tt in enumerate(t)}
    xs, ys = [], []
    for i in sorted(d):
        if keyed == "time":
            j = bytime.get(t[i] - lag)
        else:
            j = i - lag if 0 <= i - lag < len(t) else None
        if j is None or pw[j] is None:
            continue
        xs.append(pw[j])
        ys.append(d[i])
    return xs, ys


def threshold_fit(xs, ys):
    """Returns (lowest best CP, misclassified, n, highest best CP)."""
    best, lo, hi = None, None, None
    for cp in range(0, max(xs) + 1):
        mis = sum(1 for x, y in zip(xs, ys) if (y > DRAW_THRESHOLD_J) != (x > cp))
        if best is None or mis < best:
            best, lo, hi = mis, cp, cp
        elif mis == best:
            hi = cp
    return lo, best, len(xs), hi


def boundaries(R):
    t, pcr, gly, pw = R["t"], R["PCr_J"], R["GLY_J"], R["power"]
    et, ety = R["ev_t"], R["ev_type"]
    out = []
    for k in range(len(et) - 1):
        if not (ety[k].startswith("stop") and ety[k + 1] == "start"):
            continue
        ts, tr = et[k], et[k + 1]
        ib = bisect.bisect_right(t, ts) - 1
        ia = bisect.bisect_left(t, tr)
        if ib < 0 or ia >= len(t):
            continue
        inside = ia - ib - 1  # records strictly inside (ts, tr)
        nx = ia + 1 if ia + 1 < len(t) else None
        b = {"stop": ts, "start": tr, "tb": t[ib], "ta": t[ia], "inside": inside,
             "pw_after": pw[ia], "tn": None, "dP": None, "dG": None}
        for name, s in (("P", pcr), ("G", gly)):
            b["eq" + name] = (s[ib] is not None and s[ia] is not None and s[ia] == s[ib])
            if nx is not None and s[nx] is not None and s[ia] is not None:
                b["d" + name] = s[nx] - s[ia]
        if nx is not None:
            b["tn"] = t[nx]
        out.append(b)
    return out


def figures(R):
    """Returns [(human line, RIDEFACT line or None)]."""
    F = []

    def fact(human, *vals):
        F.append((human, "%s %s" % (MARK, " ".join(str(v) for v in vals))))

    t, n = R["t"], len(R["t"])
    fact("records: %d" % n, "records", n)
    for col in ("power",) + OURS:
        pop = sum(1 for v in R[col] if v is not None)
        fact("%s populated on %d of %d records" % (col, pop, n), "populated", col, pop, n)
    for col in OURS:
        vals = [v for v in R[col] if v is not None]
        s = R[col]
        first = next((v for v in s if v is not None), None)
        last = next((v for v in reversed(s) if v is not None), None)
        if vals:
            fact("%s min %s max %s first %s last %s" % (col, fmt(min(vals)), fmt(max(vals)),
                                                         fmt(first), fmt(last)),
                 "range", col, "min", fmt(min(vals)), "max", fmt(max(vals)),
                 "first", fmt(first), "last", fmt(last))
        neg = sum(1 for v in vals if v < 0)
        fact("%s negative samples: %d" % (col, neg), "negatives", col, neg)
        # A latched field is "populated" to the end even if nothing wrote it
        # (FACTS.md 3.3); the last record at which the value MOVED is what shows
        # the model was still stepping.
        moved = [t[i] for i in range(1, n)
                 if s[i] is not None and s[i - 1] is not None and s[i] != s[i - 1]]
        fact("%s last changes at t=%s (last record t=%d)"
             % (col, moved[-1] if moved else "NA", t[-1]),
             "last_change", col, moved[-1] if moved else "NA", t[-1])

    p0, g0 = R["PCr_J"][0], R["GLY_J"][0]
    if p0 is not None and g0 is not None and p0 + g0 > 0:
        fact("first-record PCr_J + GLY_J = %s J (= W' only if both tanks are full at the first "
             "record)" % fmt(p0 + g0), "capacity_first_sum", fmt(p0 + g0))
        fact("fP = PCr/(PCr+GLY) at the first record = %.4f" % (p0 / (p0 + g0)),
             "fP_first", "%.4f" % (p0 / (p0 + g0)))

    # developer-field declarations
    inv = R["inv"]
    idxs = sorted({d["index"] for d in inv})
    fact("developer_data_index values declaring fields: %d (%s); ours is %d"
         % (len(idxs), " ".join(map(str, idxs)), R["our_idx"]),
         "apps", len(idxs), "ours", R["our_idx"])
    fact("application_id in the file %s; manifest id %s; %s"
         % (R["app_id"], R["manifest_id"], "DIFFERENT" if R["app_id"] != R["manifest_id"] else "same"),
         "app_id", "file", R["app_id"] or "-", "manifest", R["manifest_id"] or "-",
         "differ" if R["app_id"] != R["manifest_id"] else "same")
    fact("field_descriptions declared: %d, ours %d" % (len(inv), sum(1 for d in inv if d["ours"])),
         "field_descriptions", len(inv), "ours", sum(1 for d in inv if d["ours"]))
    # EVERY row under our index, flagged or not: a third definition there (a
    # retired id, say) must show up here even though the extractor only flags
    # PCr_J and GLY_J.
    mine = sorted((d for d in inv if d["index"] == R["our_idx"]), key=lambda d: d["field"])
    spec = ["%d:%s:%s:%s:%s" % (d["field"], d["name"], d["type"], d["units"] or "-", d["mesg"])
            for d in mine]
    fact("field_descriptions under our index %d: %d (%s)" % (R["our_idx"], len(mine), ", ".join(spec)),
         "ours_fields", len(mine), *spec)
    for mesg in sorted({d["mesg"] for d in inv} | {"record", "session"}):
        tot = 0
        per = []
        for ix in idxs:
            b = sum(d["bytes"] for d in inv if d["index"] == ix and d["mesg"] == mesg)
            per.append(b)
            tot += b
            fact("declared %s developer bytes, index %d: %d" % (mesg, ix, b),
                 "devbytes", mesg, ix, b)
        fact("declared %s developer bytes, all apps: %d (largest single app %d)"
             % (mesg, tot, max(per) if per else 0),
             "devbytes", mesg, "total", tot, "max_app", max(per) if per else 0)

    # spacing
    hist = {}
    for i in range(1, n):
        s = t[i] - t[i - 1]
        hist[s] = hist.get(s, 0) + 1
    for s in sorted(hist):
        fact("record spacing %d s: %d step(s)" % (s, hist[s]), "spacing", s, hist[s])

    # timer events and pause boundaries
    ety = R["ev_type"]
    kinds = sorted(set(ety))
    fact("timer events: %d (%s)" % (len(ety), ", ".join("%s %d" % (k, ety.count(k)) for k in kinds)),
         "timer_events", len(ety), *[x for k in kinds for x in (k, ety.count(k))])
    B = boundaries(R)
    nb = len(B)
    fact("pause boundaries (stop then start, a record each side): %d" % nb, "boundaries", nb)
    for k, b in enumerate(B, 1):
        def num(x):
            return "NA" if x is None else "%.3f" % x
        fact("boundary %d: stop %d start %d; before t=%d after t=%d (records inside %d); latch "
             "PCr %s GLY %s; power at resume %s; next t=%s dPCr %s dGLY %s"
             % (k, b["stop"], b["start"], b["tb"], b["ta"], b["inside"],
                "eq" if b["eqP"] else "ne", "eq" if b["eqG"] else "ne",
                "NA" if b["pw_after"] is None else b["pw_after"],
                "NA" if b["tn"] is None else b["tn"], num(b["dP"]), num(b["dG"])),
             "boundary", k, b["stop"], b["start"], b["tb"], b["ta"], b["inside"],
             "eq" if b["eqP"] else "ne", "eq" if b["eqG"] else "ne",
             "NA" if b["pw_after"] is None else b["pw_after"],
             "NA" if b["tn"] is None else b["tn"], num(b["dP"]), num(b["dG"]))
    fact("records strictly inside a pause: %d" % sum(b["inside"] for b in B),
         "records_inside_pauses", sum(b["inside"] for b in B))
    fact("first post-resume record equals the pre-pause record: PCr_J %d/%d, GLY_J %d/%d, both %d/%d"
         % (sum(b["eqP"] for b in B), nb, sum(b["eqG"] for b in B), nb,
            sum(b["eqP"] and b["eqG"] for b in B), nb),
         "boundary_latch", "PCr_J", sum(b["eqP"] for b in B), "GLY_J", sum(b["eqG"] for b in B),
         "both", sum(b["eqP"] and b["eqG"] for b in B), nb)
    chg = sum(1 for b in B if (b["dP"] or 0) != 0 or (b["dG"] or 0) != 0)
    fact("a reserve changes at the record after the post-resume record: %d/%d" % (chg, nb),
         "boundary_change_at_next", chg, nb)
    fact("reserve rises at that next record: PCr_J %d/%d, GLY_J %d/%d"
         % (sum(1 for b in B if (b["dP"] or 0) > 0), nb, sum(1 for b in B if (b["dG"] or 0) > 0), nb),
         "boundary_next_rise", "PCr_J", sum(1 for b in B if (b["dP"] or 0) > 0),
         "GLY_J", sum(1 for b in B if (b["dG"] or 0) > 0), nb)
    fact("post-resume record carries no power: %d/%d" % (sum(b["pw_after"] is None for b in B), nb),
         "boundary_power_absent_at_resume", sum(b["pw_after"] is None for b in B), nb)

    # the #100 lag
    d = draws(R)
    fact("reconstructed draw defined on %d one-second steps" % len(d), "draw_steps", len(d))
    for keyed, key in (("time", "lag_r"), ("index", "lag_r_index")):
        for lag in LAGS:
            xs, ys = lag_pairs(R, d, lag, keyed)
            r = pearson(xs, ys)
            fact("Pearson r(power[t-L], d[t]) at L=%+d, %s-keyed: %.3f on %d pairs"
                 % (lag, keyed, r, len(xs)),
                 key, "%+d" % lag, "%.3f" % r, len(xs))
    for lag in LAGS:
        xs, ys = lag_pairs(R, d, lag, "time")
        if not xs:
            continue
        cp, mis, npairs, cp_hi = threshold_fit(xs, ys)
        fact("threshold fit (d > %.1f J vs power > CP) at lag %+d: best CP %d W (tied to %d W), "
             "%d/%d misclassified" % (DRAW_THRESHOLD_J, lag, cp, cp_hi, mis, npairs),
             "threshold", "%+d" % lag, cp, cp_hi, mis, npairs)
    return F


# ------------------------------------------------------------------- driver --

def doc_facts(path):
    if not os.path.isfile(path):
        raise Refused("%s: no such evidence note" % path)
    with open(path, encoding="utf-8") as fh:
        lines = [ln.strip() for ln in fh]
    return [ln for ln in lines if ln == MARK or ln.startswith(MARK + " ")]


def check(doc, computed):
    pinned = doc_facts(doc)
    if not pinned:
        print("FAIL: %s pins no %s lines -- nothing would be checked" % (doc, MARK))
        return 1
    if pinned == computed:
        print("OK: all %d %s lines in %s agree with the fixtures" % (len(pinned), MARK, doc))
        return 0
    print("FAIL: %s disagrees with the fixtures" % doc)
    ps, cs = set(pinned), set(computed)
    for ln in pinned:
        if ln not in cs:
            print("  pinned, not computed:  %s" % ln)
    for ln in computed:
        if ln not in ps:
            print("  computed, not pinned:  %s" % ln)
    if ps == cs:
        print("  same lines, different order or multiplicity")
    return 1


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--fixtures", default=DEFAULT_FIXTURES)
    ap.add_argument("--label", default=DEFAULT_LABEL)
    ap.add_argument("--check", metavar="DOC",
                    help="compare the %s lines in DOC with the fixtures; exit 1 on any difference"
                    % MARK)
    a = ap.parse_args(argv)
    try:
        R = load(a.fixtures, a.label)
        F = figures(R)
        computed = [f for _, f in F]
        if a.check:
            return check(a.check, computed)
    except Refused as exc:
        print("REFUSED: %s" % exc)
        return 2
    for human, f in F:
        print("# " + human)
        print(f)
    return 0


if __name__ == "__main__":
    sys.exit(main())
