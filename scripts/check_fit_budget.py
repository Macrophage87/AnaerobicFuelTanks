#!/usr/bin/env python3
"""Fail-closed guard on the FIT developer-field BYTE BUDGET (#96, #98 item 2).

WHY THIS EXISTS. Connect IQ caps developer fields at 32 BYTES PER MESSAGE TYPE
for a data field (a full app gets 256) -- confirmed on hardware in #96, where
12 FLOAT config SESSION fields (48 B) plus the two *_depleted_kJ SESSION fields
(8 B) came to 56 B, and the create that crossed the line raised an UNCATCHABLE
`Out Of Memory Error` ("New Field out of memory for FIT data") inside
initialize(), on every target, deterministically. The shipped v0.6 could not
load at all.

Nothing in CI saw it. The compile matrix is green on a build that cannot load,
because createField failure is a RUNTIME condition; no (:test) can obtain a
Session, so the suite cannot reach createField either; and ciq-test is
best-effort and skips green (#61). The arithmetic, however, is static -- the
call sites carry the type and the message type as literal tokens. So the
arithmetic is what this script re-derives, on every run of the required
manifest-lint job.

The re-land vector is concrete: #95 wires a 13th config parameter, and #99
(PR-B) restores config recording to the SESSION message. Either can re-breach
the quota in one line.

WHAT IS DERIVED, and how. Every `createField(` call site in
connectiq/source/DualTankView.mc whose NAME is a string literal:

  * the name       -- from the RAW text (strip_comments blanks literal bodies);
  * the id         -- an integer literal, or a `const NAME = <int>;` declared in
                      the same file. The resolution is IMPORTED from
                      scripts/check_agent_facts.py, not re-implemented: a
                      second id resolver is a second thing to get wrong;
  * the FIT type   -- the `FitContributor.DATA_TYPE_*` token;
  * the message    -- the `:mesgType => FitContributor.MESG_TYPE_*` option;
  * the element    -- the `:count => <int>` option, 1 when absent.
    count

read TWICE -- once raw, once through scripts/list_tests.py's comment-stripping
lexer (the repository's ONE Monkey C lexer) -- and required to AGREE. The raw
read is the one that can be fooled by a call written inside a comment; the
stripped read is the one that cannot see the literal name. A disagreement is
REFUSED rather than resolved, because a silent preference for either read is
the hole. That is check_agent_facts.py's pattern, followed here deliberately.

Bytes per element, from the FIT base types:

    UINT8  SINT8                 1
    UINT16 SINT16                2
    UINT32 SINT32 FLOAT          4
    UINT64 SINT64 DOUBLE         8
    STRING                       1 per element -- and REFUSED unless the call
                                 gives an explicit `:count`, because the width
                                 of a string field is not inferable from the
                                 call site.

FAIL-CLOSED, in every direction a regex can drift:

  * ZERO call sites parsed is a FAILURE, not an empty green table. A regex that
    stops matching must red, not pass;
  * an UNKNOWN `DATA_TYPE_*` token is a failure (no default width is guessed);
  * a MISSING `:mesgType` is a failure. The SDK defaults it to RECORD; guessing
    a message type would charge the bytes to the wrong budget, so it is
    refused;
  * a call whose name is a literal but whose call site this parser cannot
    decompose is a failure naming the line -- it is never skipped quietly;
  * an id that resolves to no integer const is a failure;
  * a duplicated id is a failure (the totals are keyed by id, and an id is
    unique per field_description anyway);
  * a missing DualTankView.mc is a failure.

WHAT THIS CANNOT CHECK, stated so nobody reads more into a green run.

  * IT RUNS NOTHING. It compiles nothing, executes nothing and decodes nothing.
    It cannot tell you that a device accepted the fields, that a decoder sees
    them, or that any of them was ever populated. Only a record-and-save
    session on hardware answers that (#98 item 1).
  * IT SEES ONE FILE. A createField called from any other source file is
    invisible here. connectiq/source/DualTankView.mc is where every one of this
    app's fields is created today; that is a fact about the tree, not a
    guarantee this checker enforces.
  * A createField whose NAME IS A VARIABLE is not counted -- that is the inert
    `cfgField(name, id, units)` helper, which creates nothing while mCfgFields
    stays null. If #99 (PR-B) revives it, ITS FIELDS ARE NOT IN THESE TOTALS,
    and this checker has to grow before that lands, not after.
  * The 32 B figure is the data-field tier. It is not re-derived from
    connectiq/manifest.xml's `type=` here; it is the quota confirmed on
    hardware in #96 and stated as a constant below.
  * Field-COUNT limits, RAM limits and per-activity behaviour are all out of
    scope. This is a byte sum, nothing more.

Usage:
  check_fit_budget.py [--root DIR]

Exit 0 = every message type is within budget, 1 = at least one is not, or the
call sites could not be read with confidence.
"""

import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

# The repository's ONE Monkey C lexer, reused rather than copied.
from list_tests import strip_comments                         # noqa: E402
# The `const NAME = <int>;` scanner and the id resolver, imported for the same
# reason -- check_agent_facts.py already had to solve exactly this.
from check_agent_facts import CONST_RE, resolve_field_id      # noqa: E402

VIEW_REL = os.path.join("connectiq", "source", "DualTankView.mc")

# Connect IQ's developer-field quota for a DATA FIELD, per message type, in
# bytes. Confirmed on hardware in #96 (a full app gets 256). Not derived from
# the manifest here -- see the docstring.
QUOTA_BYTES = 32

# Bytes per ELEMENT of each FIT base type. STRING is deliberately absent: its
# width is refused unless the call site gives an explicit :count.
FIT_TYPE_BYTES = {
    "UINT8": 1, "SINT8": 1,
    "UINT16": 2, "SINT16": 2,
    "UINT32": 4, "SINT32": 4, "FLOAT": 4,
    "UINT64": 8, "SINT64": 8, "DOUBLE": 8,
}
STRING_ELEMENT_BYTES = 1

_ID = r'(?P<id>\d+|[A-Za-z_][A-Za-z0-9_]*)'
# ONE regex for both reads: on the comment-stripped text the name capture comes
# back empty by construction (strip_comments blanks literal BODIES and keeps
# the delimiters), which is exactly why the two reads are complementary.
CALL_RE = re.compile(
    r'createField\(\s*"(?P<name>[^"]*)"\s*,\s*' + _ID +
    r'\s*,\s*FitContributor\.DATA_TYPE_(?P<dtype>[A-Za-z_][A-Za-z0-9_]*)'
    r'\s*,\s*\{(?P<opts>[^{}]*)\}\s*\)')

# Every call site, decomposable or not, so a literal-named call this parser
# cannot read reds instead of vanishing.
HEAD_RE = re.compile(r'createField\(\s*(?P<lead>"|[A-Za-z_0-9])')

MESG_RE = re.compile(r':mesgType\s*=>\s*FitContributor\.MESG_TYPE_'
                     r'(?P<mesg>[A-Za-z_][A-Za-z0-9_]*)')
COUNT_RE = re.compile(r':count\s*=>\s*(?P<count>\d+)')

# Record layout, by index, for the tuples below.
R_ID, R_NAME, R_TYPE, R_MESG, R_COUNT, R_BYTES, R_LINE = range(7)


def read_text(path):
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        return fh.read()


def _lineno(text, offset):
    return text.count("\n", 0, offset) + 1


def parse_one(text, shown, consts, m, problems):
    """One matched call -> a record tuple, or None if it cannot be trusted."""
    where = "%s:%d" % (shown, _lineno(text, m.start()))
    fid = resolve_field_id(m.group("id"), consts, shown, problems)
    dtype = m.group("dtype")
    name = m.group("name")
    opts = m.group("opts")

    mm = MESG_RE.search(opts)
    if mm is None:
        problems.append(
            "%s: createField(%r, ...) carries no `:mesgType => "
            "FitContributor.MESG_TYPE_*` option. The SDK defaults it to "
            "RECORD; guessing would charge the bytes to the wrong budget, so "
            "it is refused." % (where, name))
        mesg = None
    else:
        mesg = mm.group("mesg")

    cm = COUNT_RE.search(opts)
    count = int(cm.group("count")) if cm else None

    if dtype == "STRING":
        if count is None:
            problems.append(
                "%s: createField(%r, ...) is DATA_TYPE_STRING with no `:count "
                "=> <int>`. A string field's width is not inferable from the "
                "call site, so no byte total can be computed for it."
                % (where, name))
            nbytes = None
        else:
            nbytes = STRING_ELEMENT_BYTES * count
    elif dtype in FIT_TYPE_BYTES:
        nbytes = FIT_TYPE_BYTES[dtype] * (1 if count is None else count)
    else:
        problems.append(
            "%s: createField(%r, ...) uses FitContributor.DATA_TYPE_%s, which "
            "has no byte width in this checker's table (%s). An unknown type "
            "is refused rather than assumed, because assuming one would "
            "under-count the very budget this guards."
            % (where, name, dtype,
               ", ".join(sorted(FIT_TYPE_BYTES) + ["STRING"])))
        nbytes = None

    if fid is None or mesg is None or nbytes is None:
        return None
    return (fid, name, dtype, mesg, count, nbytes,
            _lineno(text, m.start()))


def parse_read(text, shown, consts, label, problems, check_heads):
    """{id: record} for one read of `text`, or None if it cannot be trusted."""
    if check_heads:
        parsed_at = {m.start() for m in CALL_RE.finditer(text)}
        orphans = sorted(_lineno(text, h.start())
                         for h in HEAD_RE.finditer(text)
                         if h.group("lead") == '"' and h.start() not in parsed_at)
        if orphans:
            problems.append(
                "%s: %d createField call(s) with a string-literal name could "
                "not be decomposed, at line(s) %s. A live call has to read "
                "`createField(\"name\", <id>, FitContributor.DATA_TYPE_X, "
                "{ :mesgType => FitContributor.MESG_TYPE_Y, ... })`. A call "
                "this parser cannot read is refused, never skipped -- skipping "
                "one would under-count the budget silently."
                % (shown, len(orphans), ", ".join(str(n) for n in orphans)))
            return None

    out = {}
    dupes = []
    bad = False
    for m in CALL_RE.finditer(text):
        rec = parse_one(text, shown, consts, m, problems)
        if rec is None:
            bad = True
            continue
        if rec[R_ID] in out:
            dupes.append(rec[R_ID])
        out[rec[R_ID]] = rec
    if dupes:
        problems.append(
            "%s: developer field id(s) %s are declared more than once (%s "
            "read). An id is unique per field_description, and the byte totals "
            "are keyed by it."
            % (shown, ", ".join(str(d) for d in sorted(set(dupes))), label))
        return None
    return None if bad else out


def collect(root, problems):
    """{id: record} for every live developer field, or None."""
    path = os.path.join(root, VIEW_REL)
    shown = VIEW_REL.replace(os.sep, "/")
    if not os.path.isfile(path):
        problems.append(
            "%s is missing; the FIT byte budget cannot be derived. Every "
            "developer field this app creates is created there." % shown)
        return None
    text = read_text(path)
    stripped = strip_comments(text)
    consts = {m.group("name"): int(m.group("val"))
              for m in CONST_RE.finditer(stripped)}

    # The comment-stripped read is the authoritative LIVE set, so it is the one
    # whose un-decomposable call sites are a failure. The raw read exists to
    # supply the names and to catch a call written inside a comment.
    live = parse_read(stripped, shown, consts, "comment-stripped", problems,
                      check_heads=True)
    raw = parse_read(text, shown, consts, "raw", problems, check_heads=False)
    if live is None or raw is None:
        return None

    if set(live) != set(raw):
        only_raw = sorted(set(raw) - set(live))
        only_live = sorted(set(live) - set(raw))
        problems.append(
            "%s: the raw and comment-stripped reads of createField disagree "
            "(raw-only ids %s, stripped-only ids %s). The raw read is the one "
            "that can see a call written inside a comment, so a disagreement "
            "is refused rather than resolved."
            % (shown, only_raw or "none", only_live or "none"))
        return None

    for fid in sorted(live):
        a = live[fid][R_TYPE:R_COUNT + 1]
        b = raw[fid][R_TYPE:R_COUNT + 1]
        if a != b:
            problems.append(
                "%s: developer field id %d reads as %r in the comment-stripped "
                "text and %r in the raw text. The two reads must agree on "
                "type, message type and count before any byte total is "
                "trusted." % (shown, fid, a, b))
            return None

    if not raw:
        problems.append(
            "%s: 0 createField call(s) with a string-literal name were found. "
            "A row-count floor is the point: a regex that has drifted out of "
            "step with the source matches nothing, and would otherwise report "
            "an empty, green byte table for an app that creates fields."
            % shown)
        return None
    return raw


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    args = ap.parse_args()

    shown = VIEW_REL.replace(os.sep, "/")
    problems = []
    fields = collect(args.root, problems)
    if fields is None or problems:
        print("FAIL: %d problem(s) reading the developer fields in %s."
              % (len(problems), shown))
        for p in problems:
            print("  - %s" % p)
        return 1

    per_mesg = {}
    for fid in sorted(fields):
        per_mesg.setdefault(fields[fid][R_MESG], []).append(fields[fid])
    totals = {k: sum(r[R_BYTES] for r in v) for k, v in per_mesg.items()}

    print("FIT developer-field bytes per message type (%s), quota %d B:"
          % (shown, QUOTA_BYTES))
    for mesg in sorted(per_mesg):
        print("  MESG_TYPE_%-10s %2d field(s)  %3d B of %d B  %s"
              % (mesg, len(per_mesg[mesg]), totals[mesg], QUOTA_BYTES,
                 "OVER" if totals[mesg] > QUOTA_BYTES else "ok"))
        for r in sorted(per_mesg[mesg], key=lambda r: r[R_ID]):
            print("      id %-3d %-20s %-7s %3d B  (line %d)"
                  % (r[R_ID], r[R_NAME], r[R_TYPE], r[R_BYTES], r[R_LINE]))

    over = sorted(m for m in totals if totals[m] > QUOTA_BYTES)
    if over:
        print("FAIL: %d message type(s) exceed the %d B developer-field quota "
              "for a data field." % (len(over), QUOTA_BYTES))
        for mesg in over:
            print("  - MESG_TYPE_%s: %d field(s) totalling %d B, %d B over the "
                  "%d B quota. On a device the create that crosses the line "
                  "raises an uncatchable Out Of Memory Error inside "
                  "initialize() and the field never loads (#96)."
                  % (mesg, len(per_mesg[mesg]), totals[mesg],
                     totals[mesg] - QUOTA_BYTES, QUOTA_BYTES))
        return 1

    worst = max(sorted(totals), key=lambda k: totals[k])
    print("OK: %d live developer field(s) across %d message type(s); every "
          "type is within the %d B quota (largest: MESG_TYPE_%s at %d B)."
          % (len(fields), len(per_mesg), QUOTA_BYTES, worst, totals[worst]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
