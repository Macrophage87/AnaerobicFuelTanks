#!/usr/bin/env python3
"""RED/GREEN tests for scripts/check_agent_facts.py.

Every case builds a scratch tree, runs the REAL checker as a subprocess with
--root (the interface CI uses), and asserts the exit code PLUS that the printed
reason names the thing that is wrong. A checker that reds without naming the
defect costs a maintainer the hour the defect would have.

HERMETIC: nothing here reads the repository. The repository's own FACTS.md is
asserted by the CI step that runs the checker with no --root; if that moved in
here, a maintainer editing a real fact would red a TOOL suite instead of the
check that prints the file and the figure.

The marker word is assembled rather than written, so nothing in this file can
be picked up as a real marker line.

Every RED case perturbs ONE thing away from the shared GREEN fixture, so a case
that reds names exactly its own defect: that is the differential, not a
description of one.

Run: python3 scripts/test_check_agent_facts.py
"""

import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
CHECKER = os.path.join(HERE, "check_agent_facts.py")

MARK = "AGENT" + "FACT"
CEIL = "CEI" + "LING"

DIGEST = "sha256:" + "a" * 64

# The fixture's fields: a short stand-in for the real map, including a gap in
# the id sequence (the real map has one too: ids 6-17 are reserved constants
# with no live createField call).
FIELDS = [(0, "PCr_J"), (1, "GLY_J"), (18, "Deficit_kJ")]

CASES = []


def case(name):
    def deco(fn):
        CASES.append((name, fn))
        return fn
    return deco


# --------------------------------------------------------------- the fixture --

def ci_yml(digests=(DIGEST, DIGEST)):
    """A workflow with one container job per digest given (the real workflow
    carries the same digest on two jobs and has no YAML anchor)."""
    body = ["name: CI", "jobs:"]
    for i, d in enumerate(digests):
        body.append("  job%d:" % i)
        body.append("    container:")
        body.append("      image: ghcr.io/x/y@%s # v2.8.0" % d)
    body.append("  plain:")
    body.append("    runs-on: ubuntu-latest")
    return "\n".join(body) + "\n"


def manifest(devices=("edge1050", "fenix6pro")):
    rows = "\n".join('        <iq:product id="%s"/>' % d for d in devices)
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<iq:manifest xmlns:iq="http://www.garmin.com/xml/connectiq" '
            'version="3">\n'
            '    <iq:application id="d2b7f4a19c6e4e0a93f5c1802a6b7de3">\n'
            '        <iq:products>\n%s\n        </iq:products>\n'
            '    </iq:application>\n</iq:manifest>\n' % rows)


def expected_tests(names=("testA", "testB")):
    return ("# a comment line, ignored\n\n"
            + "".join("%s\n" % n for n in names))


def view(fields=None, extra="", literal_ids=False):
    """The real file passes NAMED CONSTANTS as ids (`const FID_PCR_J = 0;` then
    `createField("PCr_J", FID_PCR_J, ...)`); that is the default shape here.
    literal_ids=True writes the integer form instead, so both are exercised."""
    fields = FIELDS if fields is None else fields
    out = ["class DualTankView extends WatchUi.DataField {"]
    if not literal_ids:
        for fid, name in fields:
            out.append("    const FID_%d = %d;" % (fid, fid))
        # A const only mentioned in a comment must not supply a value.
        out.append("    // const FID_99 = 99; (retired)")
    out.append("    function initialize() {")
    for fid, name in fields:
        ident = str(fid) if literal_ids else "FID_%d" % fid
        out.append('        mF%d = createField("%s", %s, '
                   'FitContributor.DATA_TYPE_FLOAT,' % (fid, name, ident))
        out.append('            { :mesgType => FitContributor.MESG_TYPE_RECORD });')
    # The inert helper: a createField whose name is a VARIABLE is not a live
    # binding and must not be counted (it is how the real file spells cfgField).
    out.append('        return createField(name, id, FitContributor.DATA_TYPE_FLOAT, opts);')
    out.append(extra)
    out.append("    }")
    out.append("}")
    return "\n".join(out) + "\n"


def ceiling_note(anchor="30b2b99", used=27, limit=253, free=226,
                 nth=227, suffix="th"):
    return ("// %s %s fenix6pro: %d used of %d, %d free -- the %d%s file-scope "
            "(:test) added reds\n" % (CEIL, anchor, used, limit, free, nth,
                                      suffix))


def facts(container=DIGEST, devices=2, tests=2,
          ceiling=("30b2b99", 27, 253, 226), fields=None,
          drop=(), extra_lines=()):
    """The marker-line section of a FACTS.md, plus a little prose around it."""
    fields = FIELDS if fields is None else fields
    lines = ["# Canonical facts", "", "Prose the checker never reads.", ""]
    if "ci-container" not in drop:
        lines.append("    %s ci-container %s" % (MARK, container))
    if "manifest-devices" not in drop:
        lines.append("    %s manifest-devices %d" % (MARK, devices))
    if "pinned-tests" not in drop:
        lines.append("    %s pinned-tests %d" % (MARK, tests))
    if "ceiling" not in drop:
        lines.append("    %s ceiling %s %d %d %d" % ((MARK,) + tuple(ceiling)))
    if "devfield" not in drop:
        for fid, name in fields:
            lines.append("    %s devfield %d %s" % (MARK, fid, name))
    lines.extend("    " + x for x in extra_lines)
    return "\n".join(lines) + "\n"


def tree(**over):
    """The GREEN tree. Each RED case overrides exactly one entry."""
    files = {
        ".github/workflows/ci.yml": ci_yml(),
        "connectiq/manifest.xml": manifest(),
        "scripts/expected_tests.txt": expected_tests(),
        "connectiq/source/DualTankView.mc": view(),
        "connectiq/source/Tests.mc": ceiling_note(),
        "docs/agents/FACTS.md": facts(),
    }
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

@case("the coherent fixture passes")
def _():
    rc, out = run(tree())
    return (rc, "OK:" in out), (0, True)


@case("a gap in the developer field id sequence is not a defect")
def _():
    # The real map skips 2-17 after the #97 removal. An id set is not required
    # to be contiguous, only to be unique and to match the file.
    rc, out = run(tree())
    return (rc, "devfield" in out), (0, False)


@case("the same digest on several container jobs is one pin, not two")
def _():
    rc, out = run(tree(**{".github/workflows/ci.yml":
                          ci_yml(digests=(DIGEST, DIGEST, DIGEST))}))
    return (rc, "OK:" in out), (0, True)


@case("integer-literal ids are accepted alongside the const form")
def _():
    rc, out = run(tree(**{"connectiq/source/DualTankView.mc":
                          view(literal_ids=True)}))
    return (rc, "OK:" in out), (0, True)


@case("RED: an id name that resolves to no const in the file is refused")
def _():
    src = view().replace("createField(\"GLY_J\", FID_1,",
                         "createField(\"GLY_J\", FID_UNDECLARED,")
    rc, out = run(tree(**{"connectiq/source/DualTankView.mc": src}))
    return (rc, "'FID_UNDECLARED'" in out
            and "cannot be derived" in out), (1, True)


@case("a createField whose name is a variable is not counted as a binding")
def _():
    # The fixture's view() always carries one; the map must still be exactly
    # FIELDS. If the variable form were counted the regex would not match a
    # quoted name and this would surface as a stripped/raw disagreement.
    rc, out = run(tree())
    return (rc, "disagree" in out), (0, False)


@case("prose, blank lines and indentation around the markers are ignored")
def _():
    body = facts() + "\nMore prose. A sentence mentioning ci-container.\n"
    rc, out = run(tree(**{"docs/agents/FACTS.md": body}))
    return (rc, "OK:" in out), (0, True)


# ------------------------------------------------------- the five derivations --

@case("RED: the container digest moves in the workflow and not in FACTS.md")
def _():
    other = "sha256:" + "b" * 64
    rc, out = run(tree(**{".github/workflows/ci.yml":
                          ci_yml(digests=(other, other))}))
    return (rc, "ci-container" in out and other in out), (1, True)


@case("RED: a device is removed from the manifest")
def _():
    rc, out = run(tree(**{"connectiq/manifest.xml":
                          manifest(devices=("edge1050",))}))
    return (rc, "manifest-devices" in out and "'1'" in out), (1, True)


@case("RED: a (:test) is added to the pin file")
def _():
    rc, out = run(tree(**{"scripts/expected_tests.txt":
                          expected_tests(("testA", "testB", "testC"))}))
    return (rc, "pinned-tests" in out and "'3'" in out), (1, True)


@case("RED: the ceiling anchor FACTS.md quotes no longer exists in the tree")
def _():
    rc, out = run(tree(**{"connectiq/source/Tests.mc":
                          ceiling_note(anchor="some-later-commit")}))
    return (rc, "30b2b99" in out and "anchor" in out), (1, True)


@case("RED: the ceiling headroom in FACTS.md disagrees with the note")
def _():
    # The note is re-measured in source and FACTS.md keeps the old figures --
    # the exact way a quoted measurement goes stale.
    rc, out = run(tree(**{"connectiq/source/Tests.mc":
                          ceiling_note(used=28, free=225, nth=226,
                                       suffix="th")}))
    return (rc, "ceiling" in out and "28 used" in out), (1, True)


@case("RED: a developer field is renamed in the source")
def _():
    renamed = [(0, "PCr_J"), (1, "gly_j"), (18, "Deficit_kJ")]
    rc, out = run(tree(**{"connectiq/source/DualTankView.mc":
                          view(fields=renamed)}))
    return (rc, "devfield 1" in out and "'gly_j'" in out), (1, True)


@case("RED: a developer field exists in the source and not in FACTS.md")
def _():
    plus = FIELDS + [(2, "PCr_cons")]
    rc, out = run(tree(**{"connectiq/source/DualTankView.mc":
                          view(fields=plus)}))
    return (rc, "2 (PCr_cons)" in out
            and "not listed in FACTS.md" in out), (1, True)


@case("RED: FACTS.md lists a developer field the source does not declare")
def _():
    body = facts(fields=FIELDS + [(6, "CP")])
    rc, out = run(tree(**{"docs/agents/FACTS.md": body}))
    return (rc, "6 (CP)" in out
            and "no createField call declares" in out), (1, True)


# ------------------------------------------------------------- fail-closed ---

@case("RED: FACTS.md is missing entirely")
def _():
    files = tree()
    del files["docs/agents/FACTS.md"]
    rc, out = run(files)
    return (rc, "docs/agents/FACTS.md" in out
            and "pointers dangle" in out), (1, True)


@case("RED: deleting a marker line does not silently disable its check")
def _():
    rc, out = run(tree(**{"docs/agents/FACTS.md":
                          facts(drop=("ci-container",))}))
    return (rc, "0 " + MARK + " ci-container line(s)" in out
            and "exactly one is required" in out), (1, True)


@case("RED: deleting every devfield line does not silently disable the map")
def _():
    rc, out = run(tree(**{"docs/agents/FACTS.md": facts(drop=("devfield",))}))
    return (rc, "no " + MARK + " devfield line" in out), (1, True)


@case("RED: a duplicated marker line is refused, not last-one-wins")
def _():
    body = facts(extra_lines=["%s pinned-tests 99" % MARK])
    rc, out = run(tree(**{"docs/agents/FACTS.md": body}))
    return (rc, "2 " + MARK + " pinned-tests line(s)" in out), (1, True)


@case("RED: a typo in a key is named, not silently unchecked")
def _():
    body = facts(extra_lines=["%s pinned-test 16" % MARK])
    rc, out = run(tree(**{"docs/agents/FACTS.md": body}))
    return (rc, "unrecognised" in out and "'pinned-test'" in out), (1, True)


@case("RED: two DIFFERENT digests in the workflow are refused, not resolved")
def _():
    # The digest is the pin. Two container jobs on two different digests are
    # two pins that can drift apart, which is worse than none, so the checker
    # refuses to pick one.
    other = "sha256:" + "b" * 64
    rc, out = run(tree(**{".github/workflows/ci.yml":
                          ci_yml(digests=(DIGEST, other))}))
    return (rc, "2 distinct container digests" in out), (1, True)


@case("RED: no digest-pinned image line at all is refused")
def _():
    rc, out = run(tree(**{".github/workflows/ci.yml":
                          "name: CI\njobs:\n  x:\n    runs-on: ubuntu-latest\n"}))
    return (rc, "0 `image: <ref>@sha256:...` line(s)" in out), (1, True)


@case("RED: a duplicated developer field id in the source is named")
def _():
    dupe = FIELDS + [(1, "GLY_J_again")]
    rc, out = run(tree(**{"connectiq/source/DualTankView.mc":
                          view(fields=dupe)}))
    return (rc, "more than once" in out and "silently re-labels" in out), (1, True)


@case("RED: a createField written inside a comment is refused, not resolved")
def _():
    # The raw read sees it and the comment-stripped read does not. The checker
    # refuses the disagreement rather than picking a winner -- the raw read is
    # the only one that can be fooled, so a silent preference for either is a
    # hole. This is also the case that proves the two reads are really two.
    commented = ('        // was: createField("ghost", 42, '
                 'FitContributor.DATA_TYPE_FLOAT,')
    rc, out = run(tree(**{"connectiq/source/DualTankView.mc":
                          view(extra=commented)}))
    return (rc, "raw and comment-stripped reads" in out
            and "[42]" in out), (1, True)


@case("RED: connectiq/source/DualTankView.mc missing is a failure, not an empty map")
def _():
    files = tree()
    del files["connectiq/source/DualTankView.mc"]
    rc, out = run(files)
    return (rc, "DualTankView.mc is missing" in out), (1, True)


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
    print("\n%d/%d agent-facts checker tests passed."
          % (len(CASES) - failures, len(CASES)))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
