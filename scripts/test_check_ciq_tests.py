#!/usr/bin/env python3
"""Offline RED/GREEN tests for scripts/check_ciq_tests.py.

The parser carries the whole PASS/FAIL verdict of the `ciq-test` job, and it is
pure Python -- so unlike the simulator harness it can be proven on a stock
runner with no container, no SDK and no Xvfb. That is why it runs in the
required `test-tooling` job while `ciq-test` itself stays best-effort (#61).

WHAT THIS SUITE ASSERTS, AND WHY IT IS SHAPED THIS WAY
------------------------------------------------------
An earlier version of this file asserted only the checker's EXIT CODE. That is
too weak to be evidence: mutation-testing the parser against it showed most
guards could be deleted outright with the suite still fully green, because a
single malformed transcript trips several guards at once and any one of them is
enough to produce rc=1. A suite that cannot tell a correct parser from a
vacuous one is exactly the failure mode #44 was about.

So every case here declares the EXACT SET OF GUARDS it expects to fire, keyed
off the checker's own diagnostic lines (see GUARDS below). Consequences:

  * deleting any single guard changes some case's fired-set, so the suite goes
    red -- one guard per case wherever a transcript can isolate one;
  * a parser that raises instead of rendering a verdict also goes red, because
    a traceback produces no diagnostic lines to classify (rc=1 alone no longer
    satisfies anything);
  * over-firing is caught too: a guard that reddens a GREEN case shows up as an
    unexpected member of the set.

FIXTURE PROVENANCE
------------------
Two REAL captures are committed, both from `ciq-test` runs of this repository
on 2026-09-05; each file's own header carries the full provenance and the one
transformation applied (the `gh run view --log` line prefix, removed):

  * `scripts/fixtures/monkeydo-green-run.log` -- run 33991598740, commit
    918fbd9: 17 tests, `PASSED (passed=17, failed=0, errors=0)`.
  * `scripts/fixtures/monkeydo-red-run.log` -- run 33990860226, commit b5de5f2:
    the same suite with one `ERROR` row and
    `FAILED (passed=16, failed=0, errors=1)`.

The green capture is the authoritative SHAPE: `Executing test X...` and `PASS`
on SEPARATE lines, separated by 78-dash rules, then one column-aligned RESULTS
table. This file's `transcript()` builder is SYNTHETIC -- it exists because it
can be perturbed one guard at a time, and nothing it produces should be
described as observed output. The red capture is committed because a synthetic
FAIL row cannot prove the parser rejects a REAL failure: this suite wrote it.

Neither capture matches scripts/expected_tests.txt's count, and that is
deliberate -- both come from PR #105's branch (17 tests) while main pins 16.
Fixture cases are judged against a pin derived from the fixture's own rows
(`fx()`, `rx()`), never the live pin, so adding or removing a (:test) cannot
red them.

Run: python3 scripts/test_check_ciq_tests.py
"""

import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
CHECKER = os.path.join(HERE, "check_ciq_tests.py")
# CIQ_TEST_PIN: used by the pin-perturbation meta-check below to re-run this
# suite under a modified pin without touching the tree. Not for normal use.
EXPECTED = os.environ.get("CIQ_TEST_PIN") or os.path.join(HERE, "expected_tests.txt")
REAL_GREEN_LOG = os.path.join(HERE, "fixtures", "monkeydo-green-run.log")
REAL_RED_LOG = os.path.join(HERE, "fixtures", "monkeydo-red-run.log")

# NAMES is DERIVED from the live pin, never hardcoded.
#
# It used to be a frozen 17-entry literal while run_checker passed the LIVE
# expected_tests.txt as --expected-file. The two disagreed the moment anyone
# added a (:test) -- doing exactly what scripts/expected_tests.txt's own header
# and FIX_ROUND.md 5 require ("two edits, in the same commit") reddened this
# suite, and with it `test-tooling` and therefore `ci-required`. Adding a unit
# test must never break the test tooling.
def _load_pin(path):
    names = []
    try:
        with open(path, "r", encoding="utf-8") as fh:
            for line in fh:
                # POSIX [[:space:]], matching check_expected_tests.sh's sed trim
                # and load_expected() exactly -- all three components must agree
                # byte-for-byte on what a pin name is.
                line = line.strip(" \t\r\n\v\f")
                if line and not line.startswith("#"):
                    names.append(line)
    except OSError as exc:
        # Render a verdict, never a traceback -- the rule the checker documents
        # for itself applies to its own test tooling.
        sys.exit("cannot read the pin file %r: %s" % (path, exc))
    return names


NAMES = _load_pin(EXPECTED)
if len(NAMES) < 3:
    # The suite indexes NAMES[0], NAMES[1], NAMES[-1], NAMES[-2] and slices
    # NAMES[:-2]; below three names those collide or raise. Render a verdict
    # instead of a traceback -- same rule the checker documents for itself.
    sys.exit("expected_tests.txt pins only %d name(s); the parser self-suite "
             "needs at least 3 to build its cases." % len(NAMES))
N = len(NAMES)
SUMMARY_OK = "PASSED (passed=%d, failed=0, errors=0)" % N

# Names this suite (and its meta-check) mints synthetically. If a real (:test)
# ever takes one of these names, the cases that rely on it being ABSENT from
# the pin invert -- the original blocker's exact shape, surviving at three
# names -- and the meta-check is green at HEAD so it cannot warn. Refuse
# loudly instead; renaming the real test is the fix.
_SYNTHETIC = ("testZzBrandNew", "testZzSomethingElse",
              "testZzPinPerturbationProbe")
_clashes = [s for s in _SYNTHETIC if s in NAMES] + \
           [n for n in NAMES if n.startswith("testZzMetaSynth")]
# Real pins only: the meta-check's own perturbed pins CONTAIN these literals by
# construction (that is what the probes are), so the guard must not fire on a
# CIQ_TEST_PIN sub-run -- it would red the meta-check it exists to protect.
if _clashes and not os.environ.get("CIQ_TEST_PIN"):
    sys.exit("pinned test name(s) collide with this suite's synthetic "
             "literals: %s -- rename the real test(s)." % ", ".join(_clashes))

# The 17 names run 33991598740 actually reported, frozen. Giving fixture cases a
# fixture-DERIVED pin fixed the add/remove coupling but silently removed the
# only tie between the committed capture and reality: substituting every row
# name in the fixture file still passed the whole suite. This literal restores
# identity; it changes ONLY when a fixture file is regenerated from a new run.
FIXTURE_NAMES_FROZEN = [
    "testHarnessSmoke",
    "testHardPunchThenRecover",
    "testSustainedOverCP",
    "testBelowCPStaysFull",
    "testDeficitBanksThenDecays",
    "testRestRecoveryClosedForm",
    "testStepScalesWithDt",
    "testAerExcess",
    "testValidateBlobAccepts",
    "testValidateBlobRejects",
    "testDecideDropout",
    "testCoerceFiniteFloat",
    "testIsConfigured",
    "testCpWprimeDefaultUnconfigured",
    "testFitRecordSettingCoerces",
    "testWriteFieldNullSafe",
    "testShouldShowNoPower",
]
N_FIXTURE = len(FIXTURE_NAMES_FROZEN)


def summ(passed=None, failed=0, errors=0, verdict="PASSED"):
    """Summary line derived from the live pin size, so synthetic cases do
    not hardcode a count that goes stale the moment a (:test) is added."""
    return "%s (passed=%d, failed=%d, errors=%d)" % (
        verdict, N if passed is None else passed, failed, errors)

# The committed fixture is a FROZEN capture of one real run, so it can only ever
# be green against the name set it actually contains. Judging it against the
# live pin would red every fixture case the next time a test is added -- the
# other half of the same defect. Cases built on the fixture therefore pass
# "<fixture>" as their pin, and run_checker synthesises it from the fixture's
# own RESULTS rows.
_FIXTURE_ROW_RE = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)[ \t]+[A-Z][A-Z0-9_]*[ \t]*$', re.M)


def _names_in(text):
    """Row names of the FIRST RESULTS table in a captured log."""
    header = re.search(r'^Test:\s+Status:\s*$', text, re.M)
    body = text[header.end():] if header else text
    body = body.split("Ran ")[0]
    return _FIXTURE_ROW_RE.findall(body)


def _fixture_names():
    return _names_in(real_green_log())


def _red_fixture_names():
    return _names_in(real_red_log())

# Guard id -> a predicate on one diagnostic line. Every diagnostic the checker
# can print must classify to exactly one id; an unclassified line fails the
# suite loudly rather than being silently ignored (that is how a renamed
# diagnostic gets noticed instead of quietly disabling a case's assertion).
GUARDS = [
    ("bad_pin",       lambda s: "could not be read" in s),
    ("empty_pin",     lambda s: "is empty -- a zero pin" in s),
    ("empty_log",     lambda s: s.startswith("monkeydo log ")),
    ("failed_veto",   lambda s: "'FAILED (passed=' line is present" in s),
    ("no_summary",    lambda s: s.startswith("no test-summary line")),
    ("multi_summary", lambda s: "summary lines; expected exactly one" in s),
    ("verdict",       lambda s: s.startswith("summary verdict is")),
    ("failed_count",  lambda s: s.startswith("failed=")),
    ("errors_count",  lambda s: s.startswith("errors=")),
    ("passed_count",  lambda s: s.startswith("passed=")),
    ("no_ran",        lambda s: s.startswith("no 'Ran N tests'")),
    ("ran_mismatch",  lambda s: s.startswith("'Ran ")),
    ("no_table",      lambda s: s.startswith("no RESULTS table")),
    ("multi_table",   lambda s: "RESULTS tables that disagree" in s),
    ("missing",       lambda s: s.startswith("missing tests")),
    ("unexpected",    lambda s: s.startswith("unexpected tests")),
    ("not_pass",      lambda s: s.startswith("tests not PASS:")),
]


def classify(line):
    """Classify one diagnostic line to its guard id.

    Asserts DISJOINTNESS: a diagnostic matching two predicates would otherwise
    silently credit whichever comes first in GUARDS, so a future rewording that
    collides with another predicate would corrupt fired-sets without any case
    noticing. Failing loudly here turns that into an immediate suite error."""
    hits = [gid for gid, pred in GUARDS if pred(line)]
    if len(hits) > 1:
        raise AssertionError(
            "diagnostic %r matches multiple guard predicates %s -- make GUARDS "
            "disjoint before trusting any fired-set" % (line, hits))
    return hits[0] if hits else None


def real_green_log():
    with open(REAL_GREEN_LOG, "r", encoding="utf-8") as fh:
        return fh.read()


def real_red_log():
    with open(REAL_RED_LOG, "r", encoding="utf-8") as fh:
        return fh.read()


def _fixture_header_line():
    """The RESULTS header line EXACTLY as the capture spells it, with its "\n".

    The column width is the SIMULATOR's (name padded to 36 in run 33991598740),
    not this file's synthetic `%-37s`. The split-table cases below partition the
    capture on this line, and partitioning on a width the capture does not use
    silently returns the whole text as `head` with an empty `tail` -- which
    still produced a plausible-looking red (two summary lines), naming the wrong
    cause. Derive it; never spell it.
    """
    m = re.search(r'^Test:[ \t]+Status:[ \t]*$', real_green_log(), re.M)
    if not m:
        raise AssertionError(
            "no RESULTS header in %s -- the capture is not the shape the "
            "split-table cases assume" % REAL_GREEN_LOG)
    return m.group(0) + "\n"


def _fixture_summary():
    """Summary line matching the FIXTURE's own test count, not the live pin."""
    return "PASSED (passed=%d, failed=0, errors=0)" % len(_fixture_names())


def fx(text, console=""):
    """A case built on the frozen GREEN fixture: judge it against a
    fixture-derived pin so it stays stable when the live pin gains or loses a
    test."""
    return (text, console, "<fixture>")


def rx(text, console=""):
    """The same, for the frozen RED fixture."""
    return (text, console, "<red-fixture>")


def transcript(statuses=None, ran=None, summary=None, extra_rows=(),
               drop_rows=(), drop_header=False, noise=()):
    """SYNTHETIC monkeydo transcript, perturbable one guard at a time.

    Shape is the column-aligned RESULTS table the simulator really emits (see
    the real fixture); the `Executing test` preamble is condensed to one line
    per test, which the parser never reads because it scopes to the table.
    """
    if statuses is None:            # NOT `or`: {} means "a run with no tests"
        statuses = {n: "PASS" for n in NAMES}
    lines = []
    for n in NAMES:
        if n in statuses:
            lines.append("Executing test %s... %s" % (n, statuses[n]))
    lines.append("")
    lines.append("=" * 78)
    lines.append("RESULTS")
    if not drop_header:
        lines.append("%-37s %s" % ("Test:", "Status:"))
    for n in NAMES:
        if n in statuses and n not in drop_rows:
            lines.append("%-37s %s" % (n, statuses[n]))
    lines.extend(noise)
    lines.extend(extra_rows)
    n_ran = len(statuses) if ran is None else ran
    if n_ran is not None:
        lines.append("Ran %d tests" % n_ran)
    lines.append("")
    if summary is None:
        npass = sum(1 for s in statuses.values() if s == "PASS")
        nfail = sum(1 for s in statuses.values() if s == "FAIL")
        nerr = sum(1 for s in statuses.values() if s not in ("PASS", "FAIL"))
        verdict = "PASSED" if (nfail == 0 and nerr == 0) else "FAILED"
        summary = "%s (passed=%d, failed=%d, errors=%d)" % (verdict, npass, nfail, nerr)
    if summary != "":
        lines.append(summary)
    return "\n".join(lines) + "\n"


def bare_table(statuses):
    """A RESULTS table alone -- header, rows, tally. No summary, so a second
    table can be placed in either stream without tripping the summary or
    FAILED-veto checks, isolating the table-ambiguity guard."""
    lines = ["%-37s %s" % ("Test:", "Status:")]
    for n in NAMES:
        if n in statuses:
            lines.append("%-37s %s" % (n, statuses[n]))
    lines.append("Ran %d tests" % len(statuses))
    return "\n".join(lines) + "\n"


def run_checker(monkeydo_text, console_text="", expected_file=EXPECTED,
                harness_status=None):
    with tempfile.TemporaryDirectory() as td:
        mlog = os.path.join(td, "monkeydo.log")
        clog = os.path.join(td, "console.log")
        if monkeydo_text is None:
            # A log FILE that never came to exist (harness died pre-redirect) --
            # distinct from an empty file, and previously unexercised.
            mlog = os.path.join(td, "never-written.log")
        else:
            # newline="" on BOTH: in text mode Python rewrites "\n" to
            # os.linesep, so on Windows the CRLF case's "\r\n" reached the
            # checker as "\r\r\n" and it red for a platform reason rather
            # than a parser one. The cases build their own line endings on
            # purpose; the harness must not touch them.
            with open(mlog, "w", encoding="utf-8", newline="") as fh:
                fh.write(monkeydo_text)
        with open(clog, "w", encoding="utf-8", newline="") as fh:
            fh.write(console_text)
        extra = []
        if harness_status is not None:
            spath = os.path.join(td, "harness-status.txt")
            with open(spath, "w", encoding="utf-8") as fh:
                fh.write(harness_status)
            extra = ["--harness-status", spath]
        if isinstance(expected_file, (list, tuple)):
            # A FULLY SYNTHETIC pin, written from the case's own name list.
            # Needed for cases whose subject is the name SHAPE rather than the
            # repository's contents -- a module-qualified row cannot be built
            # out of the live pin without depending on the live pin containing
            # one, which is a coupling the suite's docstring forbids.
            names = list(expected_file)
            expected_file = os.path.join(td, "synthetic_pin.txt")
            with open(expected_file, "w", encoding="utf-8") as fh:
                fh.write("\n".join(names) + "\n")
        elif expected_file == "<empty>":
            expected_file = os.path.join(td, "empty_pin.txt")
            with open(expected_file, "w", encoding="utf-8") as fh:
                fh.write("# no names at all\n")
        elif expected_file == "<missing>":
            expected_file = os.path.join(td, "does-not-exist.txt")
        elif expected_file == "<nbsp-fixture>":
            # The fixture pin with U+00A0 appended to its first name. NBSP is
            # NOT in load_expected's POSIX strip set, so it must survive into
            # the pinned name and make it mismatch the table.
            expected_file = os.path.join(td, "nbsp_pin.txt")
            fnames = _fixture_names()
            fnames[0] += "\u00a0"
            with open(expected_file, "w", encoding="utf-8") as fh:
                fh.write("\n".join(fnames) + "\n")
        elif expected_file == "<red-fixture>":
            # Pin derived from the RED capture's own rows, for the same reason
            # <fixture> exists: the capture is frozen, the live pin is not.
            expected_file = os.path.join(td, "red_fixture_pin.txt")
            with open(expected_file, "w", encoding="utf-8") as fh:
                fh.write("\n".join(_red_fixture_names()) + "\n")
        elif expected_file == "<fixture>":
            # Pin derived from the frozen fixture itself, so fixture cases stay
            # stable when the live pin gains or loses a test.
            expected_file = os.path.join(td, "fixture_pin.txt")
            with open(expected_file, "w", encoding="utf-8") as fh:
                fh.write("\n".join(_fixture_names()) + "\n")
        proc = subprocess.run(
            [sys.executable, CHECKER, "--monkeydo-log", mlog,
             "--console-log", clog, "--expected-file", expected_file] + extra,
            capture_output=True, text=True)
        return proc.returncode, proc.stdout + proc.stderr


def fired_guards(out):
    """Classify the checker's `  - <diagnostic>` bullets into guard ids."""
    fired, unknown = set(), []
    for line in out.splitlines():
        m = re.match(r'^ {2}- (.*)$', line)
        if not m:
            continue
        gid = classify(m.group(1).strip())
        if gid is None:
            unknown.append(m.group(1).strip())
        else:
            fired.add(gid)
    return fired, unknown


CASES = []


def case(name, guards, mentions=(), forbids=()):
    """guards:   the EXACT set of guard ids this input must trip (empty = green).
    mentions: substrings the diagnostic output must contain (diagnostic quality,
              not just the return code).
    forbids:  substrings the diagnostic must NOT contain (wrong-cause guesses)."""
    def deco(fn):
        CASES.append((name, frozenset(guards), tuple(mentions), tuple(forbids), fn))
        return fn
    return deco


# ---------------------------------------------------------------- GREEN -----

@case("committed fixture still contains EXACTLY run 1's test names", [])
def _():
    # Identity, not just shape: with fixture cases self-pinned, substituting
    # every row name in the committed capture kept the whole suite green.
    # This ties the fixture file to the frozen literal of what run 1 reported.
    got = _fixture_names()
    if sorted(got) != sorted(FIXTURE_NAMES_FROZEN):
        raise AssertionError(
            "scripts/fixtures/monkeydo-green-run.log rows no longer match the "
            "frozen run-1 names; if the fixture was legitimately regenerated, "
            "update FIXTURE_NAMES_FROZEN in the same commit. missing=%s extra=%s"
            % (sorted(set(FIXTURE_NAMES_FROZEN) - set(got)),
               sorted(set(got) - set(FIXTURE_NAMES_FROZEN))))
    return fx(real_green_log())


@case("the REAL committed green-run monkeydo.log passes", [],
      ["OK: %d/%d" % (N_FIXTURE, N_FIXTURE)])
def _():
    return fx(real_green_log())


@case("real log with CRLF line endings passes", [])
def _():
    return fx(real_green_log().replace("\n", "\r\n"))


@case("a summary broken across two lines is not a summary", [])
def _():
    # Pins the [ \t] doctrine in SUMMARY_RE itself: with \s* in its gaps, the
    # regex matches ACROSS the line break below, this transcript then contains
    # two summaries, multi_summary fires, and this green case reds. Same
    # newline-spanning defect class fixed for the veto and the header regexes.
    broken = "PASSED\n(passed=%d, failed=0, errors=0)" % N
    return transcript() + broken + "\n"


@case("a CR-ONLY log is refused -- and this case is what pins newline=''",
      ["no_summary", "no_ran", "no_table"])
def _():
    # Nothing in this pipeline emits lone-\r line endings (monkeydo on a Linux
    # container does not even emit CRLF), so refusing them costs no real input.
    # The case's REAL job is to pin read()'s newline="" open: remove that and
    # Python's universal-newline translation turns every \r into \n before any
    # regex runs -- this transcript then parses green, this case reds, and the
    # CRLF case above silently returns to being vacuous (its \r?$ anchors dead).
    return fx(real_green_log().replace("\n", "\r"))


@case("real log with a trailing blank-padded table passes", [])
def _():
    return fx(real_green_log().replace("Ran %d tests" % N_FIXTURE,
                                       "\nRan %d tests" % N_FIXTURE))


@case("synthetic column-aligned transcript passes", [])
def _():
    return transcript()


@case("RESULTS table only in the console log still passes", [])
def _():
    # The summary must come from monkeydo; the table may be resolved across both.
    t = real_green_log()
    head, sep, tail = t.partition("=" * 78)
    return fx(head + _fixture_summary() + "\n", sep + tail)


@case("table header in monkeydo but rows in console still passes", [])
def _():
    # A split table has NEVER been observed -- all 14 non-cancelled run-tests
    # executions produced monkeydo's contiguous header+rows+tally block, the
    # authoritative shape (measured in review, round 7). This case and the one
    # below survive as defense-in-depth on the WINDOW logic, not as realistic
    # inputs. This half omits monkeydo's own `Ran N tests` line, which is the
    # only way to isolate the `{}`-still-recovers (vs `is None`) behaviour.
    t = real_green_log()
    hdr = _fixture_header_line()
    head, _sep, tail = t.partition(hdr)
    return fx(head + hdr + _fixture_summary() + "\n", tail)


@case("split table where monkeydo KEEPS its own 'Ran N tests' line passes", [])
def _():
    # Same synthetic-split family as above (never observed live; see there).
    # With monkeydo's own tally line present, a parse anchored on monkeydo's
    # header used to break at that tally before ever reaching the console rows
    # (round 5) -- and the round-7 rework must keep this window green while
    # refusing DISAGREEING tables, so it pins that the recovered rows are not
    # misread as a second, conflicting table.
    t = real_green_log()
    hdr = _fixture_header_line()
    head, _sep, tail = t.partition(hdr)
    monkeydo_half = (head + hdr + "Ran %d tests\n" % len(_fixture_names())
                     + _fixture_summary() + "\n")
    return fx(monkeydo_half, tail)


@case("a non-row simulator notice inside the table does not red a green run", [])
def _():
    # Regression: `(\S+) (\S+)` read this as test `WARNING:` status `gc-pressure`.
    return transcript(noise=["WARNING: gc-pressure", "-- 3 warnings --"])


# The row regex narrows BOTH halves (identifier-shaped name AND all-caps status).
# The `gc-pressure` fixture above is rejected by EITHER half alone, so it cannot
# tell the two apart: mutating one half back to `\S+` leaves it green. These two
# cases isolate them -- each is rejected by exactly one half.
@case("row-shaped noise with a valid status but non-identifier name stays green", [])
def _():
    # `WARNING:` is not identifier-shaped; `GC_PRESSURE` IS a valid status token,
    # so only the NAME half of the regex rejects this row.
    return transcript(noise=["WARNING: GC_PRESSURE"])


@case("row-shaped noise with a valid name but lowercase status stays green", [])
def _():
    # `SIMULATOR` is identifier-shaped; `ready` is not an all-caps status token,
    # so only the STATUS half rejects this row.
    return transcript(noise=["SIMULATOR ready"])


# ---- Anchor pins. Independent mutation testing showed the survivors cluster
# on regex anchors: RAN_RE's ^ and \b, RESULTS_HEADER_RE's ^ and its (formerly
# newline-spanning) separator, FAILED_VETO's (formerly newline-spanning) gap,
# and RESULTS_ROW_RE's tail. Each case below stays green with the anchor intact
# and reds if it is loosened -- turning "anchoring makes the parser
# trustworthy" from a thesis into an assertion.

@case("mid-line and prefixed 'Ran N tests' chatter is not the tally", [])
def _():
    # Kills: RAN_RE without ^ (matches inside "Also Ran 3 tests...") and
    # without \b (matches the "tests" prefix of "testsuites").
    return transcript(noise=["Also Ran 3 tests earlier in this session",
                             "Ran 99 testsuites in total today"])


@case("a 'Pre-Test: Status:' line and a split Test:/Status: pair are not headers", [])
def _():
    # Kills: RESULTS_HEADER_RE without ^ (tail-matches "Pre-Test: Status:") and
    # with a newline-spanning separator (a "Test:" line followed by a "Status:"
    # line formed a PHANTOM header before the real one, promoting the chatter
    # between them to phantom rows).
    t = transcript()
    return ("Pre-Test: Status:\nSIMULATOR PASS\nTest:\nStatus:\nWIDGET LOADED\n" + t)


@case("prose 'FAILED' at line end + '(passed=' at next line start is not a veto", [])
def _():
    # Kills: FAILED_VETO_RE with \s* instead of [ \t]* -- \s spans the newline
    # and vetoed a green run over two adjacent prose lines in the console log.
    return fx(real_green_log(),
              "the previous attempt FAILED\n(passed= counts shown above)\n")


@case("a row followed by trailing words is not a row", [])
def _():
    # Kills: RESULTS_ROW_RE without its end anchor -- "nothing else" is the
    # comment's whole claim, and without the tail this line becomes a row.
    return transcript(noise=["testZzExtra PASS but with trailing words"])


@case("ANSI-coloured status tokens do not red a green run", [])
def _():
    return fx(real_green_log().replace("PASS", "\x1b[32mPASS\x1b[0m"))


@case("simulator chatter BEFORE the table header is not read as a row", [])
def _():
    # Why the parse is scoped to the table at all: anything row-shaped that the
    # simulator prints on its way up would otherwise become a phantom test.
    return fx("SIMULATOR READY\nDEVICE FR965\n" + real_green_log())


@case("output AFTER the 'Ran N' tally is not read as a row", [])
def _():
    # Why the parse stops at the tally: trailing shutdown chatter is row-shaped.
    return fx(real_green_log() + "SHUTDOWN OK\nSIMULATOR EXIT\n")


# ----------------------------------------------------- RED, one guard -------

@case("a SKIP row with a clean 17/17 summary is caught", ["not_pass"],
      ["%s=SKIP" % NAMES[-2]])
def _():
    # The "executed but mis-tallied" case: the summary and the tally both still
    # claim a clean 17/17, and ONLY the per-test status disagrees. This is the
    # entire reason the not-PASS check exists, and nothing used to test it.
    st = {n: "PASS" for n in NAMES}
    st[NAMES[-2]] = "SKIP"
    return transcript(st, ran=N, summary=SUMMARY_OK)


@case("a non-PASS ERROR row with a clean summary is caught", ["not_pass"],
      ["%s=ERROR" % NAMES[-1]])
def _():
    st = {n: "PASS" for n in NAMES}
    st[NAMES[-1]] = "ERROR"
    return transcript(st, ran=N, summary=SUMMARY_OK)


@case("duplicate rows for one test are ambiguous and fail",
      ["not_pass"], ["DUPLICATE_ROW(FAIL,PASS)"])
def _():
    # FAIL first, PASS second -- the exact order a plain dict overwrite used to
    # resolve GREEN, in a parser whose contract is that ambiguity fails. (The
    # fix is order-independent; this case builds the dangerous order, and its
    # earlier name claimed "in either order" while building only one -- called
    # out in review.) The composite status names both conflicting rows, so the
    # diagnostic is actionable rather than a bare marker.
    st = {n: "PASS" for n in NAMES}
    st[NAMES[0]] = "FAIL"
    return transcript(st, ran=N, summary=SUMMARY_OK,
                      extra_rows=["%-37s %s" % (NAMES[0], "PASS")])


@case("two RESULTS tables that DISAGREE across the streams fail as ambiguous",
      ["multi_table"], ["refusing to pick one", "%s: 'PASS' vs 'SKIP'" % NAMES[1]])
def _():
    # The round-7 false green: a stale all-PASS table first, a table carrying
    # a real SKIP second. First-table-wins silently kept the stale one and
    # printed OK on a run whose later table said otherwise. Tables now get the
    # same ambiguity doctrine as summaries and duplicate rows.
    st_bad = {n: "PASS" for n in NAMES}
    st_bad[NAMES[1]] = "SKIP"
    return (transcript(), bare_table(st_bad))


@case("two DISAGREEING tables inside monkeydo ALONE fail as ambiguous",
      ["multi_table"])
def _():
    # The same defect with no split at all -- both tables in monkeydo.log
    # under one clean summary. This variant is what proves the bug was never
    # about round 5's split-table fallback: it lives in first-table-wins.
    st_bad = {n: "PASS" for n in NAMES}
    st_bad[NAMES[-1]] = "SKIP"
    return transcript() + bare_table(st_bad)


@case("an IDENTICAL table echoed to both streams stays green", [])
def _():
    # Duplicate tables that AGREE are not ambiguity -- refusing them would
    # false-red any future path that tees the block to both logs.
    return (transcript(), bare_table({n: "PASS" for n in NAMES}))


@case("the REAL committed red-run monkeydo.log is rejected, by name",
      ["failed_veto", "verdict", "errors_count", "passed_count", "not_pass"],
      ["testFitRecordSettingCoerces=ERROR", "summary verdict is FAILED",
       "errors=1"])
def _():
    # The other half of the fixture pair. A synthetic FAIL row proves only that
    # the parser rejects what this suite wrote; this proves it rejects the bytes
    # a real failing run emitted -- run 33990860226, PR #105's deliberate red,
    # which the simulator reported as one ERROR row under an otherwise clean
    # `Ran 17 tests`.
    #
    # Identity, as for the green capture: the red capture is the SAME suite (PR
    # #105's 17 names) with exactly one non-PASS row. If it is ever regenerated
    # from a different run, this assertion says so instead of the case quietly
    # testing something else.
    names = _red_fixture_names()
    if sorted(names) != sorted(FIXTURE_NAMES_FROZEN):
        raise AssertionError(
            "scripts/fixtures/monkeydo-red-run.log rows no longer match the "
            "frozen name set; missing=%s extra=%s"
            % (sorted(set(FIXTURE_NAMES_FROZEN) - set(names)),
               sorted(set(names) - set(FIXTURE_NAMES_FROZEN))))
    return rx(real_red_log())


@case("the REAL red run cannot pass even with its summary doctored to PASSED",
      ["not_pass"], ["testFitRecordSettingCoerces=ERROR"])
def _():
    # THE FALSE-PASS THIS WHOLE PARSER EXISTS TO KILL, on real bytes: swap the
    # capture's `FAILED (passed=16, failed=0, errors=1)` for a clean PASSED
    # summary with the right count, so the summary, the tally and the veto are
    # all satisfied and ONLY the per-test row disagrees. The gate the job used
    # before this parser counted `PASSED` lines and would have accepted it.
    doctored = real_red_log().replace(
        "FAILED (passed=%d, failed=0, errors=1)" % (N_FIXTURE - 1),
        "PASSED (passed=%d, failed=0, errors=0)" % N_FIXTURE)
    if "FAILED (passed=" in doctored:
        raise AssertionError("the red capture's summary line did not substitute "
                             "-- the fixture shape changed")
    return rx(doctored)


@case("a stray FAILED line in the CONSOLE log vetoes a green monkeydo run",
      ["failed_veto"])
def _():
    return fx(real_green_log(), "FAILED (passed=15, failed=2, errors=0)\n")


@case("the FAILED veto is whitespace-tolerant, not a literal substring",
      ["failed_veto"])
def _():
    # `FAILED  (passed=` with two spaces used to slip past the literal veto
    # even though SUMMARY_RE itself tolerates the extra space.
    return fx(real_green_log(), "FAILED  (passed=15, failed=2, errors=0)\n")


@case("missing summary line, everything else intact", ["no_summary"],
      ["Expected a line like"])
def _():
    return transcript(summary="")


@case("summary with leading text on the line is not accepted", ["no_summary"])
def _():
    return transcript(summary="sim: " + SUMMARY_OK)


@case("duplicate summary lines are refused as ambiguous", ["multi_summary"])
def _():
    return transcript() + SUMMARY_OK + "\n"


@case("summary reporting failed>0 is caught", ["failed_count"], ["failed=2"])
def _():
    return transcript(ran=N, summary=summ(failed=2))


@case("summary reporting errors>0 is caught", ["errors_count"], ["errors=2"])
def _():
    return transcript(ran=N, summary=summ(errors=2))


@case("summary passed count below the pin is caught", ["passed_count"],
      ["passed=%d but %d tests are expected" % (N - 1, N)])
def _():
    return transcript(ran=N, summary=summ(N - 1))


@case("missing 'Ran N tests' line is caught", ["no_ran"])
def _():
    return transcript(ran=None, summary=SUMMARY_OK).replace("Ran %d tests\n" % N, "")


@case("'Ran N' disagreeing with the pin is caught", ["ran_mismatch"],
      ["'Ran %d tests' but %d are expected" % (N - 1, N)])
def _():
    return transcript(ran=N - 1, summary=SUMMARY_OK)


@case("missing RESULTS table header is caught", ["no_table"])
def _():
    return transcript(drop_header=True, ran=N, summary=SUMMARY_OK)


@case("a test in the pin but absent from the table is caught", ["missing"],
      [NAMES[0]])
def _():
    return transcript(drop_rows=(NAMES[0],), ran=N, summary=SUMMARY_OK)


@case("a test in the table but not in the pin is caught", ["unexpected"],
      ["testZzBrandNew"])
def _():
    return transcript(extra_rows=["%-37s %s" % ("testZzBrandNew", "PASS")],
                      ran=N, summary=SUMMARY_OK)


@case("a renamed/substituted test is caught as both missing and extra",
      ["missing", "unexpected"],
      [NAMES[1], "testZzSomethingElse"])
def _():
    return transcript(ran=N, summary=SUMMARY_OK).replace(
        NAMES[1], "testZzSomethingElse" + " " * max(1, len(NAMES[1]) - 21))


@case("an empty pin file can never reach a pass", ["empty_pin"])
def _():
    # No rows either, so the name-set checks stay silent and the zero-pin guard
    # is the only thing standing between an empty pin and a green run.
    return (transcript(statuses={}, ran=0, summary="PASSED (passed=0, failed=0, errors=0)"),
            "", "<empty>")


@case("an unreadable pin file fails closed instead of tracebacking",
      ["bad_pin", "unexpected"], ["could not be read"])
def _():
    return (real_green_log(), "", "<missing>")


@case("a pin name with a trailing U+00A0 is preserved, not silently trimmed",
      ["missing", "unexpected"], ["\u00a0"])
def _():
    # Pins load_expected's POSIX-exact strip set, asserted byte-identical to
    # the shell's [[:space:]] trim in three separate comments and -- until this
    # case -- tested by zero of them (found in review, round 5). With a bare
    # .strip() the NBSP is eaten, the doctored pin silently matches the table,
    # and this case reds because neither guard fires. The mention pins the
    # NBSP surviving into the diagnostic itself, where the mismatch is visible.
    return (real_green_log(), "", "<nbsp-fixture>")


# --------------------------------------------- RED, deliberately compound ---

@case("empty monkeydo log (sim produced no output at all)",
      ["empty_log", "no_summary", "no_ran", "no_table"],
      ["hung and killed by timeout"])
def _():
    return ""


@case("a monkeydo log FILE that never existed fails like an empty one",
      ["empty_log", "no_summary", "no_ran", "no_table"])
def _():
    # Harness died before the redirect ever created the file. read() treats a
    # missing path as "", so this must behave exactly like empty content -- but
    # the missing-FILE path itself was previously unexercised, so pin it.
    return None


@case("a harness breadcrumb replaces the guessed cause, it does not add to it",
      ["empty_log", "no_summary", "no_ran", "no_table"],
      # The parenthesised form appears ONLY in the diagnostic bullet's
      # interpolation; the bare form is also printed by the Harness-status echo
      # block above the verdict, so a bare mention was satisfied without the
      # diagnostic ever interpolating the breadcrumb (reproduced in review).
      mentions=["(harness_error=compile_failed:3)", "aborted before"],
      forbids=["hung and killed by timeout", "crashed at launch"])
def _():
    # The pre-monkeydo abort paths. Guessing "hung / crashed at launch / never
    # started" here names three causes that are all wrong, because on this path
    # the simulator was never launched at all.
    return ("", "", EXPECTED, "harness_error=compile_failed:3\n")


@case("truncated mid-run", ["no_summary", "no_ran", "no_table"])
def _():
    return fx("\n".join(real_green_log().splitlines()[:8]) + "\n")


@case("FAILED glued onto the end of a PASSED line",
      ["no_summary", "failed_veto"])
def _():
    # SUMMARY_RE is anchored to end-of-line, so NEITHER summary matches and the
    # run cannot pass on the strength of the leading PASSED.
    return transcript(summary=SUMMARY_OK + " FAILED (passed=15, failed=2, errors=0)")


@case("a genuine two-test failure run",
      ["failed_veto", "verdict", "failed_count", "passed_count", "not_pass"],
      ["%s=FAIL" % NAMES[0], "%s=FAIL" % NAMES[1], "summary verdict is FAILED"])
def _():
    # Positional, like the SKIP/ERROR cases: hardcoding two specific test names
    # here meant REMOVING either of those tests (with its pin line, exactly as
    # documented) silently dropped its row while the summary still counted it,
    # reddening this case for an unrelated-looking reason.
    st = {n: "PASS" for n in NAMES}
    st[NAMES[0]] = "FAIL"
    st[NAMES[1]] = "FAIL"
    return transcript(st)


@case("fewer tests run than pinned",
      ["passed_count", "ran_mismatch", "missing"])
def _():
    # NAMES[:-2], never a fixed slice: `NAMES[:15]` was "all of them" the moment
    # the pin shrank to 15, so the transcript was complete, the checker correctly
    # passed, and this rc=1 case reddened test-tooling on ANY two-test removal.
    return transcript({n: "PASS" for n in NAMES[:-2]})



# ------------------------------------------- module-scoped test names -------
# A (:test) declared inside `module M { ... }` runs exactly like a file-scope
# one, and MEASURED on fr965 / SDK 9.2.0 the simulator prints its row as
# "M.test_foo". The previous row pattern could not match that line, so the row
# was DROPPED -- and a dropped row does not produce a clear error, it produces
# the "executed but mis-tallied" complaint, which names the wrong cause. Module
# scope is what keeps this repository able to add tests for the fenix6 family
# at all (see the globals-limit note in list_tests.py), so these two cases pin
# both directions of the widened pattern.

@case("module-qualified rows parse and match a module-qualified pin", [])
def _():
    names = ["Mod.test_alpha", "Mod.test_beta", "test_bare"]
    lines = ["=" * 78, "RESULTS", "%-37s %s" % ("Test:", "Status:")]
    for n in names:
        lines.append("%-37s %s" % (n, "PASS"))
    lines.append("Ran %d tests" % len(names))
    lines.append("")
    lines.append("PASSED (passed=%d, failed=0, errors=0)" % len(names))
    return ("\n".join(lines) + "\n", "", names)


@case("a malformed dotted token is still not a row",
      ["missing", "passed_count", "ran_mismatch"],
      mentions=["Mod.test_beta"])
def _():
    # The widened pattern admits dot-SEPARATED identifiers and nothing looser.
    # A leading dot, a trailing dot and a doubled dot must all still be
    # unparseable, or the anchor that rejects `WARNING: gc-pressure` has been
    # traded away for the convenience of module names.
    names = ["Mod.test_alpha", "Mod.test_beta"]
    lines = ["=" * 78, "RESULTS", "%-37s %s" % ("Test:", "Status:")]
    lines.append("%-37s %s" % ("Mod.test_alpha", "PASS"))
    lines.append("%-37s %s" % (".test_beta", "PASS"))       # leading dot
    lines.append("%-37s %s" % ("Mod..test_beta", "PASS"))   # doubled dot
    lines.append("%-37s %s" % ("Mod.test_beta.", "PASS"))   # trailing dot
    lines.append("Ran 1 tests")
    lines.append("")
    lines.append("PASSED (passed=1, failed=0, errors=0)")
    return ("\n".join(lines) + "\n", "", names)


def main():
    failures = 0
    for name, want_guards, mentions, forbids, fn in CASES:
        # A case (or classify()'s disjointness assertion) that raises must
        # become a clean FAIL line with the message, never a traceback that
        # replaces the score -- the same always-render-a-verdict rule the
        # checker documents for itself.
        try:
            produced = fn()
            if isinstance(produced, tuple):
                rc, out = run_checker(*produced)
            else:
                rc, out = run_checker(produced)
            got_guards, unknown = fired_guards(out)
        except Exception as exc:
            print("FAIL %s" % name)
            print("      ! raised %s: %s" % (type(exc).__name__, exc))
            failures += 1
            continue
        want_rc = 1 if want_guards else 0
        errs = []
        if rc != want_rc:
            errs.append("expected rc=%d got rc=%d" % (want_rc, rc))
        if got_guards != set(want_guards):
            errs.append("guards fired %s, expected %s"
                        % (sorted(got_guards) or "{}", sorted(want_guards) or "{}"))
        if unknown:
            errs.append("unclassified diagnostic(s) -- add them to GUARDS: %s" % unknown)
        for frag in mentions:
            if frag not in out:
                errs.append("diagnostic never mentions %r" % frag)
        for frag in forbids:
            if frag in out:
                errs.append("diagnostic wrongly claims %r" % frag)

        print("%-4s %s" % ("OK" if not errs else "FAIL", name))
        if errs:
            failures += 1
            for e in errs:
                print("      ! " + e)
            for line in out.splitlines():
                print("      | " + line)

    print("\n%d/%d parser self-tests passed." % (len(CASES) - failures, len(CASES)))
    if failures:
        return 1

    # ---- Pin-perturbation meta-check -------------------------------------
    # The whole suite must be PIN-AGNOSTIC: adding or removing a (:test) is
    # documented as "two edits, nothing else", and that property was declared
    # verified -- manually -- twice, and was wrong both times (a frozen NAMES
    # list, then a frozen slice and two frozen name strings). So it is now
    # asserted mechanically on every run: re-run this suite under a pin with a
    # name appended and a pin with two names removed; both must pass. Skipped
    # when we ARE the perturbed run (CIQ_TEST_PIN set), so it cannot recurse.
    if not os.environ.get("CIQ_TEST_PIN"):
        with tempfile.TemporaryDirectory() as td:
            variants = [
                ("added", NAMES + ["testZzPinPerturbationProbe"]),
                # Fully synthetic names, same count: the strongest probe. Any
                # case hardcoding a REAL test name (the second half of the
                # round-3 blocker -- a middle-of-the-list literal survives the
                # removed-two variant) references a name absent from this pin
                # and reds immediately.
                ("renamed", ["testZzMetaSynth%02d" % i
                             for i in range(len(NAMES))]),
            ]
            if len(NAMES) >= 5:
                # The -2 probe drives the sub-run's pin to len(NAMES)-2, which
                # must stay >= its own 3-name minimum -- at a real pin of 3 or 4
                # this variant would red with "suite is not pin-agnostic", a
                # false cause (found in review). Skip it, say so, and keep the
                # other two probes, which work down to 3.
                variants.insert(1, ("removed-two", NAMES[:-2]))
            else:
                print("meta-check: pin has %d names; skipping the removed-two "
                      "probe (it would drive the sub-run below its 3-name "
                      "minimum and red for a false cause)." % len(NAMES))
            for label, pin_names in variants:
                pin = os.path.join(td, "pin-%s.txt" % label)
                with open(pin, "w", encoding="utf-8") as fh:
                    fh.write("\n".join(pin_names) + "\n")
                env = dict(os.environ, CIQ_TEST_PIN=pin)
                proc = subprocess.run([sys.executable, os.path.abspath(__file__)],
                                      capture_output=True, text=True, env=env)
                if proc.returncode != 0:
                    print("META-FAIL: suite is not pin-agnostic -- reruns red "
                          "under a pin with a test %s. Adding/removing a (:test) "
                          "would red test-tooling again. Output tail:" % label)
                    for line in (proc.stdout + proc.stderr).splitlines()[-15:]:
                        print("      | " + line)
                    return 1
            print("pin-perturbation meta-check: suite green under %s pins."
                  % ", ".join(label for label, _ in variants))
    return 0


if __name__ == "__main__":
    sys.exit(main())
