using Toybox.Test;

// Placeholder (:test) so the CI compile gate builds the unit-test sources too
// (monkeyc -t) on every device in the matrix. CI currently COMPILES this but does
// not execute it — running (:test) needs the headless simulator, which is wired up
// in issue #27. (:test) functions are excluded from release builds, so this adds
// nothing to the shipped data field.
//
// Real numerical-model regression tests (the W = CP*t + W' fit, per-second model
// step, pause/resume recovery, FIT rebuild, ...) are tracked by issue #27 — expand
// this module there.
(:test)
function testHarnessSmoke(logger) {
    logger.debug("CI (:test) harness reached");
    return 2 + 2 == 4;
}
