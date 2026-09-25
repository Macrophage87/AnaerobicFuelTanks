#!/usr/bin/env python3
"""RED/GREEN tests for tools/fielddata/ride_evidence.py.

Every case builds scratch fixtures, runs the REAL tool as a subprocess with
--fixtures/--label (and --check), and asserts the exit code PLUS the printed
line that names the figure or the defect. A refusal that does not say what it
refused costs a maintainer the hour the defect would have.

HERMETIC: nothing here reads the committed ride fixtures. The real ride is
asserted by the CI step that runs `ride_evidence.py --check` against its
evidence note; if that moved in here, a maintainer adding a second ride would
red a TOOL suite instead of the check that names the file and the figure.

THE SYNTHETIC RIDE, built so every expected figure is known by construction
rather than re-computed here (a test that re-implements the arithmetic pins
nothing):
  * two 60-record segments at 1 s, t=0..59 and t=80..139, with a timer
    stop_all at 59 and start at 80: one pause boundary, 118 one-second steps;
  * the resume record (t=80) LATCHES: it repeats the t=59 reserves exactly and
    carries no power, and the rest-recovery refill lands at t=81 -- the shape
    the first v0.8 field ride shows at all 23 of its boundaries;
  * the draw at record t is max(0, P[t-1] - 200) J, split 1:3 PCr:GLY -- a
    one-sample offset by construction, and CP = 200 W. Powers include 200 and
    201 W, so at lag +1 the threshold fit is exactly CP 200 W, 0 misclassified,
    with no tie;
  * capacities 10000 / 30000 J, full at the first record: 40000 J, fP 0.2500.

Pair counts, by construction (a pair needs a present power at the paired time):
  lag -1: 58 + 58 = 116    lag 0: 59 + 59 = 118    lag +1: 59 + 58 = 117
  lag +2 time-keyed: 58 + 57 = 115; index-keyed also pairs d[81] with the
  power of record t=59 across the pause: 116.

Run: python3 tools/fielddata/test_ride_evidence.py
"""

import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "ride_evidence.py")

# Assembled, so this file carries no marker line of its own.
MARK = "RIDE" + "FACT"
LABEL = "syn"
CP = 200
PCR_CAP, GLY_CAP = 10000.0, 30000.0
POWERS = (0, 100, 150, 199, 200, 201, 202, 250, 300, 400)

CASES = []


def case(name):
    def deco(fn):
        CASES.append((name, fn))
        return fn
    return deco


# --------------------------------------------------------------- the fixture --

PROV = [
    "# PROVENANCE -- synthetic, built by tools/fielddata/test_ride_evidence.py",
    "#   source file    synthetic.fit",
    "#   ours           developer_data_index 1, application_id aaaa (manifest id is bbbb)",
]


def ride(latch=True, change_at_next=True):
    """[(t, power or None, PCr, GLY)] for the synthetic ride."""
    rows = []
    pcr, gly = PCR_CAP, GLY_CAP
    prev_p = None
    for seg, ts in enumerate((range(0, 60), range(80, 140))):
        for k, t in enumerate(ts):
            p = POWERS[(t * 7 + t // 3) % len(POWERS)]
            if seg == 1 and k == 0:
                # the resume record: no power, reserves as at the stop (latched)
                if not latch:
                    pcr, gly = pcr + 5.0, gly + 5.0
                rows.append((t, None, pcr, gly))
                prev_p = None
                continue
            if seg == 1 and k == 1:
                # the record after resume: the rest-recovery refill lands here
                if change_at_next:
                    pcr, gly = min(PCR_CAP, pcr + 40.0), min(GLY_CAP, gly + 60.0)
            elif prev_p is not None:
                draw = max(0, prev_p - CP)
                if draw > 0:
                    pcr, gly = pcr - 0.25 * draw, gly - 0.75 * draw
                else:
                    pcr, gly = min(PCR_CAP, pcr + 1.0), min(GLY_CAP, gly + 1.0)
            rows.append((t, p, pcr, gly))
            prev_p = p
    return rows


def f9(x):
    return "%.9g" % x


def series(rows=None, header="t,power,PCr_J,GLY_J", records=None, prov=PROV, extra_row=None):
    rows = ride() if rows is None else rows
    out = list(prov) + [
        "#   values         synthetic records",
        "#   absence        an EMPTY cell means absent",
        "#   cross-checks   records %d; first PCr_J %s, GLY_J %s; last t %d"
        % (len(rows) if records is None else records, f9(rows[0][2]), f9(rows[0][3]), rows[-1][0]),
        header,
    ]
    for t, p, pc, gl in rows:
        out.append("%d,%s,%s,%s" % (t, "" if p is None else p, f9(pc), f9(gl)))
    if extra_row is not None:
        out.insert(len(out) - 10, extra_row)
    return "\n".join(out) + "\n"


def events(prov=PROV, evs=((0, "start"), (59, "stop_all"), (80, "start"), (139, "stop_all"))):
    out = list(prov) + ["#   values         synthetic timer events",
                        "#   cross-checks   %d timer events" % len(evs), "t,event_type"]
    out += ["%d,%s" % e for e in evs]
    return "\n".join(out) + "\n"


# index 0: record 4 + 1, session 2, with an EMPTY units cell and an EMPTY ours
# cell on every row -- the real inventory's shape, which a loader that strips
# whitespace instead of newlines would read as ragged.
INV_ROWS = [
    "0\t0\tAlpha\tfloat32\t4\t\trecord\t",
    "0\t1\tBeta\tuint8\t1\tbpm\trecord\t",
    "0\t2\tGamma\tuint16\t2\tg\tsession\t",
    "1\t0\tPCr_J\tfloat32\t4\tJ\trecord\tyes",
    "1\t1\tGLY_J\tfloat32\t4\tJ\trecord\tyes",
]


def inventory(prov=PROV, rows=INV_ROWS):
    out = list(prov) + ["#   values         synthetic field descriptions",
                        "index\tfield\tname\ttype\tbytes\tunits\tmesg\tours"]
    return "\n".join(out + list(rows)) + "\n"


def fixture(**over):
    files = {"series.csv": series(), "events.csv": events(), "inventory.txt": inventory()}
    files.update(over)
    return files


def run(files, doc=None, crlf=False):
    """Returns (rc, stdout) with the scratch root replaced by <root>."""
    with tempfile.TemporaryDirectory() as td:
        fx = os.path.join(td, "fixtures")
        os.makedirs(fx)
        for suffix, content in files.items():
            with open(os.path.join(fx, "%s.%s" % (LABEL, suffix)), "w", encoding="utf-8",
                      newline="\r\n" if crlf else "\n") as fh:
                fh.write(content)
        args = [sys.executable, TOOL, "--fixtures", fx, "--label", LABEL]
        if doc is not None:
            dp = os.path.join(td, "note.md")
            with open(dp, "w", encoding="utf-8") as fh:
                fh.write(doc)
            args += ["--check", dp]
        proc = subprocess.run(args, capture_output=True, text=True, timeout=120)
        out = (proc.stdout + proc.stderr).replace(td, "<root>").replace(os.sep, "/")
        return proc.returncode, out


def facts(out):
    return [ln for ln in out.splitlines() if ln.startswith(MARK + " ")]


def has(out, line):
    return (MARK + " " + line) in facts(out)


def fact_vals(out, key):
    """The values after '<MARK> <key>' on every line with that key."""
    return [ln.split()[2:] for ln in facts(out) if ln.split()[1] == key]


# ------------------------------------------------------------------ accepted --

@case("the coherent synthetic ride is accepted")
def _():
    rc, out = run(fixture())
    return (rc, has(out, "records 120"), "REFUSED" in out), (0, True, False)


@case("CRLF fixtures (a Windows checkout) give byte-identical figures")
def _():
    rc1, out1 = run(fixture())
    rc2, out2 = run(fixture(), crlf=True)
    return (rc1, rc2, facts(out1) == facts(out2), len(facts(out1)) > 0), (0, 0, True, True)


@case("absence is counted, not read as zero: the resume record's power")
def _():
    rc, out = run(fixture())
    return (rc, has(out, "populated power 119 120"), has(out, "populated PCr_J 120 120")), \
        (0, True, True)


@case("capacity inference and fP from a full first record")
def _():
    rc, out = run(fixture())
    return (rc, has(out, "capacity_first_sum 40000"), has(out, "fP_first 0.2500")), \
        (0, True, True)


@case("declared developer bytes are summed per app and in total, per message")
def _():
    rc, out = run(fixture())
    return (rc, has(out, "devbytes record 0 5"), has(out, "devbytes record 1 8"),
            has(out, "devbytes record total 13 max_app 8"), has(out, "devbytes session 0 2"),
            has(out, "devbytes session 1 0"), has(out, "apps 2 ours 1")), \
        (0, True, True, True, True, True, True)


@case("every field under our index is listed, including one the extractor did not flag")
def _():
    rc, out = run(fixture())
    rows = INV_ROWS + ["1\t18\tDeficit_kJ\tfloat32\t4\tkJ\trecord\t"]
    rc2, out2 = run(fixture(**{"inventory.txt": inventory(rows=rows)}))
    return (rc, has(out, "ours_fields 2 0:PCr_J:float32:J:record 1:GLY_J:float32:J:record"),
            rc2, has(out2, "ours_fields 3 0:PCr_J:float32:J:record 1:GLY_J:float32:J:record "
                           "18:Deficit_kJ:float32:kJ:record")), (0, True, 0, True)


@case("last_change reports the last MOVE, not the last populated record (latch)")
def _():
    rows = ride()
    held = rows[-6]
    rows = rows[:-5] + [(t, p, held[2], held[3]) for t, p, _, _ in rows[-5:]]
    rc, out = run(fixture(**{"series.csv": series(rows)}))
    return (rc, has(out, "last_change PCr_J %d 139" % held[0]),
            has(out, "populated PCr_J 120 120")), (0, True, True)


@case("spacing histogram: 118 one-second steps and one 21 s gap")
def _():
    rc, out = run(fixture())
    return (rc, fact_vals(out, "spacing"), has(out, "draw_steps 118")), \
        (0, [["1", "118"], ["21", "1"]], True)


# ------------------------------------------------------- the resume latch --

@case("a latched resume record is detected, and the change lands at the next record")
def _():
    rc, out = run(fixture())
    return (rc, has(out, "boundaries 1"), has(out, "boundary_latch PCr_J 1 GLY_J 1 both 1 1"),
            has(out, "boundary_change_at_next 1 1"), has(out, "boundary_next_rise PCr_J 1 GLY_J 1 1"),
            has(out, "boundary_power_absent_at_resume 1 1"),
            has(out, "records_inside_pauses 0")), (0, True, True, True, True, True, True)


@case("RED: a resume record that moved is NOT reported as latched")
def _():
    rc, out = run(fixture(**{"series.csv": series(ride(latch=False))}))
    return (rc, has(out, "boundary_latch PCr_J 0 GLY_J 0 both 0 1")), (0, True)


@case("RED: no change at the next record is reported as none")
def _():
    # With the refill removed, t=81 repeats t=80 exactly (ride() applies neither a
    # draw nor a refill there, because the resume record carries no power).
    rc, out = run(fixture(**{"series.csv": series(ride(change_at_next=False))}))
    return (rc, has(out, "boundary_change_at_next 0 1")), (0, True)


@case("a stop with no following start is not a boundary")
def _():
    evs = ((0, "start"), (59, "stop_all"), (80, "start"), (139, "stop_all"), (150, "stop_all"))
    rc, out = run(fixture(**{"events.csv": events(evs=evs)}))
    return (rc, has(out, "boundaries 1"), has(out, "timer_events 5 start 2 stop_all 3")), \
        (0, True, True)


# ------------------------------------------------ the lag and the threshold --

@case("a known 1-sample offset: the threshold fit at lag +1 is CP 200 W, 0 misclassified")
def _():
    rc, out = run(fixture())
    return (rc, has(out, "threshold +1 200 200 0 117")), (0, True)


@case("at lag 0 the same offset misclassifies, and the fit is worse")
def _():
    rc, out = run(fixture())
    v = fact_vals(out, "threshold")
    lag0 = [x for x in v if x[0] == "+0"][0]
    return (rc, lag0[4], int(lag0[3]) > 0), (0, "118", True)


@case("Pearson r peaks at lag +1 on the offset series")
def _():
    rc, out = run(fixture())
    v = {x[0]: float(x[1]) for x in fact_vals(out, "lag_r")}
    return (rc, max(v, key=v.get)), (0, "+1")


@case("pair counts: time-keyed pairs never straddle the pause; index-keyed ones do")
def _():
    rc, out = run(fixture())
    n = {x[0]: x[2] for x in fact_vals(out, "lag_r")}
    ni = {x[0]: x[2] for x in fact_vals(out, "lag_r_index")}
    return (rc, n, ni["+2"]), \
        (0, {"-1": "116", "+0": "118", "+1": "117", "+2": "115"}, "116")


# ------------------------------------------------------------------- refusals --

@case("RED: a ragged series row is refused, naming the line")
def _():
    rc, out = run(fixture(**{"series.csv": series(extra_row="45,210,9000,29000,7")}))
    return (rc, bool(re.search(r"syn\.series\.csv:\d+: ragged row: 5 cell\(s\) where the header "
                               r"has 4", out))), (2, True)


@case("RED: a ragged inventory row (trailing tab lost) is refused")
def _():
    rows = list(INV_ROWS)
    rows[1] = rows[1].rstrip("\t")
    rc, out = run(fixture(**{"inventory.txt": inventory(rows=rows)}))
    return (rc, "syn.inventory.txt" in out and "ragged row: 7 cell(s)" in out), (2, True)


@case("RED: a missing column is refused, naming it")
def _():
    body = series().replace("t,power,PCr_J,GLY_J", "t,power,PCr_J,GLY")
    rc, out = run(fixture(**{"series.csv": body}))
    return (rc, "missing column(s) GLY_J" in out), (2, True)


@case("RED: events from a different ride (provenance mismatch) are refused")
def _():
    other = list(PROV)
    other[1] = "#   source file    another.fit"
    rc, out = run(fixture(**{"events.csv": events(prov=other)}))
    return (rc, "series/syn.events.csv mismatch" in out, "not from the same ride" in out), \
        (2, True, True)


@case("RED: a series cross-checks line that disagrees with the rows is refused")
def _():
    rc, out = run(fixture(**{"series.csv": series(records=121)}))
    return (rc, "cross-checks header says" in out), (2, True)


@case("RED: 'ours' rows under the wrong developer index are refused")
def _():
    rows = [r.replace("1\t0\tPCr_J", "0\t9\tPCr_J") for r in INV_ROWS]
    rc, out = run(fixture(**{"inventory.txt": inventory(rows=rows)}))
    return (rc, "'ours' rows must be exactly PCr_J + GLY_J" in out), (2, True)


@case("RED: a series whose t does not increase is refused")
def _():
    rows = ride()
    rows[10], rows[11] = rows[11], rows[10]
    rc, out = run(fixture(**{"series.csv": series(rows)}))
    return (rc, "t does not increase" in out), (2, True)


# ------------------------------------------------------------------- --check --

def note(lines, prose="An evidence note.\n\n"):
    return prose + "".join("    %s\n" % ln for ln in lines) + "\nMore prose.\n"


@case("--check: a note pinning exactly the computed lines passes")
def _():
    _, out = run(fixture())
    rc, out2 = run(fixture(), doc=note(facts(out)))
    return (rc, "OK: all %d" % len(facts(out)) in out2), (0, True)


@case("RED --check: one altered figure is named")
def _():
    _, out = run(fixture())
    lines = [ln.replace("threshold +1 200 200 0", "threshold +1 201 201 0") for ln in facts(out)]
    rc, out2 = run(fixture(), doc=note(lines))
    return (rc, "pinned, not computed:  %s threshold +1 201 201 0 117" % MARK in out2,
            "computed, not pinned:  %s threshold +1 200 200 0 117" % MARK in out2), (1, True, True)


@case("RED --check: a dropped line is named")
def _():
    _, out = run(fixture())
    lines = [ln for ln in facts(out) if "boundary_latch" not in ln]
    rc, out2 = run(fixture(), doc=note(lines))
    return (rc, "computed, not pinned:  %s boundary_latch" % MARK in out2), (1, True)


@case("RED --check: a note that pins nothing does not pass vacuously")
def _():
    rc, out = run(fixture(), doc="No markers here.\n")
    return (rc, "pins no %s lines" % MARK in out), (1, True)


def main():
    failures = 0
    for name, fn in CASES:
        try:
            got, want = fn()
            ok = got == want
        except Exception as exc:
            print("FAIL %s" % name)
            print("      ! raised %r" % (exc,))
            failures += 1
            continue
        print("%-4s %s" % ("OK" if ok else "FAIL", name))
        if not ok:
            failures += 1
            print("      ! expected = %r" % (want,))
            print("      !      got = %r" % (got,))
    print("\n%d/%d ride-evidence tool tests passed." % (len(CASES) - failures, len(CASES)))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
