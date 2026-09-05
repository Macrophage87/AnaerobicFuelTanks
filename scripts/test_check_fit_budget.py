#!/usr/bin/env python3
"""RED/GREEN tests for scripts/check_fit_budget.py.

Every case builds a scratch tree, runs the REAL checker as a subprocess with
--root (the interface CI uses), and asserts the exit code PLUS that the printed
reason names the thing that is wrong. A checker that reds without naming the
defect costs a maintainer the hour the defect would have.

HERMETIC: nothing here reads the repository. The repository's own
connectiq/source/DualTankView.mc is asserted by the CI step that runs the
checker with no --root; if that moved in here, a maintainer adding a field
would red a TOOL suite instead of the check that prints the byte table.

Every RED case perturbs ONE thing away from the shared GREEN fixture, so a case
that reds names exactly its own defect: that is the differential, not a
description of one.

The GREEN fixture is the shape of the tree it guards -- RECORD 16 B over five
fields, SESSION 8 B over two -- and the headline RED case is the shape that
actually shipped and could not load: #96's twelve FLOAT config SESSION fields,
48 B on top of 8 B, 56 B against a 32 B quota.

The CROSS-FILE cases exist because round 1 of the review MEASURED the previous
version's blind spot: a literal createField dropped into a second source file
was uncounted, rc 0, with no diagnostic at all. Bytes are per app per message
type, so a byte written from another file is a real byte; these cases pin that
it is counted, that it can push a type over quota on its own, and that an id
re-used across two files is refused.

Run: python3 scripts/test_check_fit_budget.py
"""

import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
CHECKER = os.path.join(HERE, "check_fit_budget.py")

VIEW = "connectiq/source/DualTankView.mc"
OTHER = "connectiq/source/Other.mc"       # a SECOND source file, for the
                                          # cross-file cases below

# (id, name, DATA_TYPE_*, MESG_TYPE_*, extra option text). The live set at the
# pin: RECORD = 4+4+2+2+4 = 16 B, SESSION = 4+4 = 8 B.
FIELDS = [
    (0,  "PCr_J",           "FLOAT",  "RECORD",  ':units => "J"'),
    (1,  "GLY_J",           "FLOAT",  "RECORD",  ':units => "J"'),
    (2,  "PCr_cons",        "SINT16", "RECORD",  ':units => "W"'),
    (3,  "GLY_cons",        "SINT16", "RECORD",  ':units => "W"'),
    (4,  "PCr_depleted_kJ", "FLOAT",  "SESSION", ':units => "kJ"'),
    (5,  "GLY_depleted_kJ", "FLOAT",  "SESSION", ':units => "kJ"'),
    (18, "Deficit_kJ",      "FLOAT",  "RECORD",  ':units => "kJ"'),
]

# #96's twelve config parameters, in the order cfgField() created them. FLOAT
# SESSION, 4 B each: 48 B on top of the 8 B above = 56 B.
CFG_NAMES = ["CP", "Wprime", "fP", "pPmax", "tauP", "tauG",
             "lt1Frac", "eta", "fatK", "gFat", "tauAer", "tauOn"]
CFG_FIELDS = [(6 + i, n, "FLOAT", "SESSION", "")
              for i, n in enumerate(CFG_NAMES)]

CASES = []


def case(name):
    def deco(fn):
        CASES.append((name, fn))
        return fn
    return deco


# --------------------------------------------------------------- the fixture --

def view(fields=None, extra="", literal_ids=False, helper=True):
    """A DualTankView.mc carrying `fields`.

    The real file passes NAMED CONSTANTS as ids (`const FID_PCR_J = 0;` then
    `createField("PCr_J", FID_PCR_J, ...)`); that is the default shape here.
    literal_ids=True writes the integer form instead, so both are exercised.
    `helper` appends the inert cfgField() body -- a createField whose name is a
    VARIABLE -- which must not be counted."""
    fields = FIELDS if fields is None else fields
    out = ["class DualTankView extends WatchUi.DataField {"]
    if not literal_ids:
        for fid, _n, _t, _m, _o in fields:
            out.append("    const FID_%d = %d;" % (fid, fid))
        # A const only mentioned in a comment must not supply a value.
        out.append("    // const FID_99 = 99; (retired)")
    out.append("    function initialize() {")
    for fid, name, dtype, mesg, opt in fields:
        ident = str(fid) if literal_ids else "FID_%d" % fid
        opts = ":mesgType => FitContributor.MESG_TYPE_%s" % mesg
        if opt:
            opts += ", " + opt
        out.append('        mF%d = createField("%s", %s, '
                   'FitContributor.DATA_TYPE_%s,' % (fid, name, ident, dtype))
        out.append('            { %s });' % opts)
    if helper:
        out.append('        return createField(name, id, '
                   'FitContributor.DATA_TYPE_FLOAT, opts);')
    out.append(extra)
    out.append("    }")
    out.append("}")
    return "\n".join(out) + "\n"


def pad(mesg, specs, first_id=100):
    """Extra fields on one message type: specs is a list of DATA_TYPE tokens."""
    return [(first_id + i, "Pad%d" % i, t, mesg, "")
            for i, t in enumerate(specs)]


def tree(**over):
    """The GREEN tree. Each RED case overrides exactly one entry."""
    files = {VIEW: view()}
    files.update(over)
    return files


def run(files):
    """Returns (rc, stdout) with the scratch root replaced by <root> and os.sep
    normalised, so a case can assert an exact path on Windows and Linux alike."""
    with tempfile.TemporaryDirectory() as td:
        for rel, content in files.items():
            path = os.path.join(td, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(content)
        proc = subprocess.run(
            [sys.executable, CHECKER, "--root", td],
            capture_output=True, text=True, timeout=120)
        out = proc.stdout.replace(td, "<root>").replace(os.sep, "/")
        return proc.returncode, out


# ------------------------------------------------------------------ accepted --

@case("the shipping shape passes: RECORD 16 B, SESSION 8 B")
def _():
    rc, out = run(tree())
    return (rc, "16 B of 32 B" in out and "8 B of 32 B" in out
            and "OK:" in out), (0, True)


@case("every total is qualified 'for a data field', on the GREEN path too")
def _():
    # 32 B is the data-field tier; a full app gets 256 B. The green line is the
    # one most likely to be quoted out of context (FACTS.md 6, "the wrong
    # pair"), so the qualifier has to be on it and not only on the FAIL branch.
    rc, out = run(tree())
    return (rc, "for a DATA FIELD" in out
            and "quota for a data field" in out), (0, True)


@case("named-const ids resolve, and each field is listed with its width")
def _():
    rc, out = run(tree())
    return (rc, "id 2   PCr_cons" in out and "SINT16" in out
            and "7 live developer field(s)" in out), (0, True)


@case("integer-literal ids are accepted alongside the const form")
def _():
    rc, out = run(tree(**{VIEW: view(literal_ids=True)}))
    return (rc, "16 B of 32 B" in out and "OK:" in out), (0, True)


@case("a createField whose name is a variable is not counted")
def _():
    # The GREEN fixture always carries the inert cfgField() body. Removing it
    # must not change a single byte, which is what makes "not counted" a
    # measurement rather than an assertion.
    with_helper = run(tree())
    without = run(tree(**{VIEW: view(helper=False)}))
    return (with_helper, without), (without, without)


@case("32 B exactly is within budget -- the quota is inclusive")
def _():
    # 16 B of RECORD + four more FLOAT = 32 B on the nose.
    fields = FIELDS + pad("RECORD", ["FLOAT"] * 4)
    rc, out = run(tree(**{VIEW: view(fields=fields)}))
    return (rc, "32 B of 32 B  ok" in out and "OK:" in out), (0, True)


@case("a :count multiplies the element width")
def _():
    # One UINT8 x 5 = 5 B, taking RECORD from 16 B to 21 B.
    fields = FIELDS + [(100, "Arr", "UINT8", "RECORD", ":count => 5")]
    rc, out = run(tree(**{VIEW: view(fields=fields)}))
    return (rc, "21 B of 32 B" in out), (0, True)


@case("DATA_TYPE_STRING with an explicit :count is 1 B per element")
def _():
    fields = FIELDS + [(100, "Tag", "STRING", "SESSION", ":count => 6")]
    rc, out = run(tree(**{VIEW: view(fields=fields)}))
    return (rc, "14 B of 32 B" in out), (0, True)


# ----------------------------------------------------------- over the quota --

@case("RED: #96's twelve FLOAT config SESSION fields -- 56 B, the shipped crash")
def _():
    rc, out = run(tree(**{VIEW: view(fields=FIELDS + CFG_FIELDS)}))
    return (rc, "MESG_TYPE_SESSION: 14 field(s) totalling 56 B, 24 B over"
            in out and "56 B of 32 B  OVER" in out
            and "uncatchable Out Of Memory Error" in out), (1, True)


@case("RED: 33 B on one message type -- one byte over is over")
def _():
    # 16 B + four FLOAT (32 B) + one UINT8 = 33 B on RECORD. The GREEN case
    # above stops at the four FLOATs, so this pair brackets the boundary.
    fields = FIELDS + pad("RECORD", ["FLOAT"] * 4 + ["UINT8"])
    rc, out = run(tree(**{VIEW: view(fields=fields)}))
    return (rc, "totalling 33 B, 1 B over" in out
            and "1 message type(s) exceed" in out), (1, True)


@case("RED: an over-quota RECORD does not hide behind an under-quota SESSION")
def _():
    fields = FIELDS + pad("RECORD", ["FLOAT"] * 5)
    rc, out = run(tree(**{VIEW: view(fields=fields)}))
    return (rc, "MESG_TYPE_RECORD: 10 field(s) totalling 36 B" in out
            and "SESSION" in out and "8 B of 32 B  ok" in out), (1, True)


@case("RED: both message types over are both reported, not just the first")
def _():
    fields = (FIELDS + pad("RECORD", ["FLOAT"] * 5)
              + pad("SESSION", ["FLOAT"] * 7, first_id=200))
    rc, out = run(tree(**{VIEW: view(fields=fields)}))
    return (rc, "2 message type(s) exceed" in out
            and "MESG_TYPE_RECORD: 10 field(s)" in out
            and "MESG_TYPE_SESSION: 9 field(s)" in out), (1, True)


@case("RED: a message type this checker has never seen still gets its own budget")
def _():
    # MESG_TYPE_LAP is a separate pool (#96's fix option 3). Nothing here
    # enumerates message types, so a new one is budgeted, not ignored.
    fields = FIELDS + pad("LAP", ["FLOAT"] * 9)
    rc, out = run(tree(**{VIEW: view(fields=fields)}))
    return (rc, "MESG_TYPE_LAP: 9 field(s) totalling 36 B" in out), (1, True)


# ------------------------------------------------------------- fail-closed ---

@case("RED: zero createField calls is a failure, not an empty green table")
def _():
    rc, out = run(tree(**{VIEW: view(fields=[], helper=False)}))
    return (rc, "0 createField call(s)" in out
            and "row-count floor" in out), (1, True)


@case("RED: a file whose only createField has a variable name is refused")
def _():
    # The inert helper alone is not a live field set; reporting 0 B green for
    # it would be the same hole as a drifted regex.
    rc, out = run(tree(**{VIEW: view(fields=[], helper=True)}))
    return (rc, "0 createField call(s)" in out), (1, True)


@case("RED: an unknown DATA_TYPE token is refused, not assumed")
def _():
    fields = FIELDS + [(100, "Odd", "BYTE", "RECORD", "")]
    rc, out = run(tree(**{VIEW: view(fields=fields)}))
    return (rc, "DATA_TYPE_BYTE" in out
            and "no byte width in this checker's table" in out), (1, True)


@case("RED: DATA_TYPE_STRING without a :count is refused")
def _():
    fields = FIELDS + [(100, "Tag", "STRING", "SESSION", "")]
    rc, out = run(tree(**{VIEW: view(fields=fields)}))
    return (rc, "DATA_TYPE_STRING with no `:count" in out
            and "not inferable" in out), (1, True)


@case("RED: a missing :mesgType is refused rather than defaulted to RECORD")
def _():
    src = view().replace(
        "{ :mesgType => FitContributor.MESG_TYPE_SESSION, :units => \"kJ\" }",
        "{ :units => \"kJ\" }", 1)
    rc, out = run(tree(**{VIEW: src}))
    return (rc, "carries no `:mesgType" in out
            and "wrong budget" in out), (1, True)


@case("RED: a createField written inside a comment is refused, not resolved")
def _():
    # The raw read sees it and the comment-stripped read does not. Refusing the
    # disagreement is what makes the raw read (the only one that can be fooled)
    # safe to use for the names.
    commented = ('        // was: createField("ghost", 42, '
                 'FitContributor.DATA_TYPE_FLOAT, '
                 '{ :mesgType => FitContributor.MESG_TYPE_SESSION });')
    rc, out = run(tree(**{VIEW: view(extra=commented)}))
    return (rc, "raw and comment-stripped reads" in out
            and "[42]" in out), (1, True)


@case("RED: a literal-named call this parser cannot decompose is named, not skipped")
def _():
    # No options dictionary at all. Skipping it would under-count the budget.
    odd = ('        mOdd = createField("odd", 99, '
           'FitContributor.DATA_TYPE_FLOAT);')
    rc, out = run(tree(**{VIEW: view(extra=odd)}))
    return (rc, "could not be decomposed" in out
            and "never skipped" in out), (1, True)


@case("RED: an id name that resolves to no const in the file is refused")
def _():
    src = view().replace('createField("GLY_J", FID_1,',
                         'createField("GLY_J", FID_UNDECLARED,')
    rc, out = run(tree(**{VIEW: src}))
    return (rc, "'FID_UNDECLARED'" in out
            and "cannot be derived" in out), (1, True)


@case("RED: a const declared only inside a comment does not supply an id")
def _():
    src = view().replace('createField("GLY_J", FID_1,',
                         'createField("GLY_J", FID_99,')
    rc, out = run(tree(**{VIEW: src}))
    return (rc, "'FID_99'" in out and "cannot be derived" in out), (1, True)


@case("RED: a duplicated developer field id is refused, not last-one-wins")
def _():
    fields = FIELDS + [(1, "GLY_J_again", "FLOAT", "RECORD", "")]
    rc, out = run(tree(**{VIEW: view(fields=fields)}))
    return (rc, "declared more than once" in out
            and "unique per field_description" in out), (1, True)


@case("RED: a missing connectiq/source directory is a failure, not 0 B")
def _():
    rc, out = run({})
    return (rc, "connectiq/source is missing or is not a directory" in out
            and "cannot be derived" in out), (1, True)


@case("RED: a source directory holding no .mc file at all is refused")
def _():
    rc, out = run({"connectiq/source/notes.txt": "not Monkey C\n"})
    return (rc, "0 .mc file(s)" in out), (1, True)


# ------------------------------------------------------------- cross-file ---

@case("a createField in a SECOND source file is COUNTED, not silently ignored")
def _():
    # The blind spot measured in review: this exact injection used to report
    # the unchanged 7 fields, rc 0, with no diagnostic. RECORD goes 16 -> 24 B
    # and the second file is named in the table.
    other = view(fields=[(40, "Bloat", "DOUBLE", "RECORD", ':units => "J"')],
                 helper=False)
    rc, out = run(tree(**{OTHER: other}))
    return (rc, "24 B of 32 B" in out and "Other.mc:" in out
            and "8 live developer field(s) in 2 .mc file(s)" in out), (0, True)


@case("RED: a second source file can push a message type over quota on its own")
def _():
    # DualTankView.mc alone is 16 B of 32 B and green. The bytes that break the
    # budget live entirely in the other file -- which is the whole point.
    other = view(fields=pad("RECORD", ["DOUBLE"] * 3, first_id=40),
                 helper=False)
    rc, out = run(tree(**{OTHER: other}))
    return (rc, "MESG_TYPE_RECORD: 8 field(s) totalling 40 B, 8 B over" in out
            and "Other.mc:" in out), (1, True)


@case("RED: one developer field id re-used across two files is refused")
def _():
    other = view(fields=[(1, "GLY_J_elsewhere", "FLOAT", "RECORD", "")],
                 helper=False)
    rc, out = run(tree(**{OTHER: other}))
    return (rc, "id 1 is declared in both" in out
            and "DualTankView.mc" in out and "Other.mc" in out
            and "unique per field_description across the whole app" in out), (1, True)


@case("no filename is pinned: the fields may live in any .mc file")
def _():
    # DualTankView.mc deleted, the same seven fields moved to another file.
    # Nothing in the checker names a file, so the totals are unchanged.
    rc, out = run({OTHER: view()})
    return (rc, "16 B of 32 B" in out and "8 B of 32 B" in out
            and "7 live developer field(s) in 1 .mc file(s)" in out
            and "OK:" in out), (0, True)


@case("RED: deleting the only file that creates fields reds on the row-count floor")
def _():
    rc, out = run({"connectiq/source/TankModel.mc":
                   "class TankModel { function initialize() { } }\n"})
    return (rc, "0 createField call(s)" in out
            and "row-count floor" in out), (1, True)


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
    print("\n%d/%d FIT byte-budget checker tests passed."
          % (len(CASES) - failures, len(CASES)))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
