using Toybox.Test;

// Placeholder smoke test so the CI "Run No Evil" (:test) harness has something to
// execute and the compile + unit-test gate is exercised end-to-end on every device
// in the matrix. (:test) functions are excluded from release builds, so this adds
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
