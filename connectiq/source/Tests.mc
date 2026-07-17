using Toybox.Test;
using Toybox.Lang;

// Unit / regression tests for the dual-tank model.
//
// These COMPILE on the CI compile gate (monkeyc -t) and EXECUTE under the headless
// simulator (xvfb) in the issue #27 test harness. (:test) functions are excluded from
// release builds, so the test cases here never ship in the data field.
//
// The physiology tests drive a pure TankModel (no DataField/FitContributor/Activity/
// Storage context), and the persistence tests exercise the pure DualTankView.validateBlob
// seam with plain Lang arrays. Tolerances are physiology-appropriate: the traces assert
// the documented QUALITATIVE behaviour (which tank drains, recovers, empties first), not
// bit-exact joules.

// ---- Shared helpers ----
//
// These are PLAIN functions, not (:test) functions: the headless (:test) runner invokes
// every (:test) symbol as a test case with a single Logger argument, so a tagged helper
// with a different arity would fault. Plain helpers still compile under the -t test build
// (they are only pruned from RELEASE builds, and this whole file is test-only) while being
// callable with their real signatures.

// Build a model at the documented default settings (CP=250), full tanks.
// Settings order matches TankModel.configure(cp, wprime, fP, pPmax, tauP, tauG,
// lt1Frac, eta, fatK, gFat, tauAer, tauOn).
function tmMake() {
    var m = new TankModel();
    m.configure([250.0, 20000.0, 0.25, 300.0, 27.0, 470.0, 0.80, 1.00, 0.75, 0.0, 25.0, 6.0]);
    m.resetTanks();
    return m;
}

// Run a scripted trace: an array of [watts, seconds] segments. Each second is one
// stepModel() call at the segment's constant power. Returns the last pctP.
function tmRun(m, trace) {
    var pctP = 100.0;
    for (var i = 0; i < trace.size(); i += 1) {
        var seg = trace[i];
        var w = seg[0];
        var secs = seg[1];
        for (var s = 0; s < secs; s += 1) {
            pctP = m.stepModel(w);
        }
    }
    return pctP;
}

// ---- Existing CI smoke test ----

(:test)
function testHarnessSmoke(logger) {
    logger.debug("CI (:test) harness reached");
    return 2 + 2 == 4;
}

// ---- Documented-trace physiology tests ----

// 5 s @ 800 W then 60 s @ 100 W: PCr drops sharply, GLY barely moves, PCr recovers
// toward full during the easy spin.
(:test)
function testHardPunchThenRecover(logger) {
    var m = tmMake();
    var capP = m.mCapP;
    var capG = m.mCapG;

    tmRun(m, [[800.0, 5]]);
    var rpAfterEffort = m.mRP;
    var rgAfterEffort = m.mRG;
    logger.debug("after 5s@800: rP=" + rpAfterEffort + " rG=" + rgAfterEffort);

    // PCr drops sharply; GLY barely moves (PCr is the immediate buffer, glycolysis lags).
    Test.assert(rpAfterEffort < 0.80 * capP);
    Test.assert(rgAfterEffort > 0.95 * capG);

    tmRun(m, [[100.0, 60]]);
    logger.debug("after 60s@100: rP=" + m.mRP);
    // PCr recovers toward full during the easy spin: not just non-decreasing, but a
    // meaningful refill — strictly more than 5% of capacity above where the effort left it.
    Test.assert(m.mRP > rpAfterEffort + 0.05 * capP);
    Test.assert(m.mRP > 0.70 * capP);
    return true;
}

// ~180 s @ 300 W: PCr empties first (lower fill %) and GLY also declines.
(:test)
function testSustainedOverCP(logger) {
    var m = tmMake();
    var capP = m.mCapP;
    var capG = m.mCapG;

    tmRun(m, [[300.0, 180]]);
    var fillP = m.mRP / capP;
    var fillG = m.mRG / capG;
    logger.debug("after 180s@300: fillP=" + fillP + " fillG=" + fillG);

    Test.assert(m.mRP < 0.90 * capP);   // PCr noticeably depleted
    Test.assert(m.mRG < capG);          // GLY declined
    Test.assert(fillP < fillG);         // PCr empties first
    return true;
}

// 20 min @ 150 W (below CP): both tanks stay full, GLY never decreases.
(:test)
function testBelowCPStaysFull(logger) {
    var m = tmMake();
    var capP = m.mCapP;
    var capG = m.mCapG;

    var prevRG = m.mRG;
    var minRG = m.mRG;
    for (var s = 0; s < 1200; s += 1) {
        m.stepModel(150.0);
        // GLY never decreases below CP.
        Test.assert(m.mRG >= prevRG - 1e-6);
        prevRG = m.mRG;
        if (m.mRG < minRG) { minRG = m.mRG; }
    }
    logger.debug("below-CP: rP=" + m.mRP + " rG=" + m.mRG + " minRG=" + minRG);

    Test.assert(m.mRP > 0.99 * capP);
    Test.assert(m.mRG > 0.99 * capG);
    Test.assert(minRG >= capG - 1e-6);
    return true;
}

// Tiny pPmax throttles the tanks' flux: supra-CP demand banks as a deficit, which then
// decays once the rider drops below CP.
(:test)
function testDeficitBanksThenDecays(logger) {
    var m = new TankModel();
    m.configure([250.0, 20000.0, 0.25, 5.0, 27.0, 470.0, 0.80, 1.00, 0.75, 0.0, 25.0, 6.0]);
    m.resetTanks();

    tmRun(m, [[800.0, 20]]);
    var deficitPeak = m.mDeficit;
    logger.debug("deficit after effort=" + deficitPeak);
    Test.assert(deficitPeak > 0.0);   // demand the flux caps couldn't place was banked

    tmRun(m, [[0.0, 120]]);
    logger.debug("deficit after recovery=" + m.mDeficit);
    Test.assert(m.mDeficit < deficitPeak);   // repaid over the sub-CP recovery
    return true;
}

// Pause/resume closed form: applyRestRecovery(N) must match N single-second recovery
// steps (applyRestRecovery(1) x N) within a physiology-appropriate tolerance. Two models
// driven through the same deterministic deplete trace are in identical state, so any
// difference is purely the closed-form-vs-iterated recovery path.
(:test)
function testRestRecoveryClosedForm(logger) {
    var a = tmMake();
    var b = tmMake();
    var deplete = [[600.0, 40]];
    tmRun(a, deplete);
    tmRun(b, deplete);
    // Sanity: identical state after the identical trace.
    Test.assert(a.mRP == b.mRP);
    Test.assert(a.mRG == b.mRG);

    var n = 60;
    a.applyRestRecovery(n);            // one closed-form call over N seconds
    for (var s = 0; s < n; s += 1) {   // N single-second recovery steps
        b.applyRestRecovery(1);
    }
    logger.debug("closed rP=" + a.mRP + " iter rP=" + b.mRP);
    logger.debug("closed rG=" + a.mRG + " iter rG=" + b.mRG);

    // Glycolytic rest rate is state-independent, so those match to float precision;
    // PCr's tau depends on the (slowly recovering) glycolytic fill, so allow a small
    // absolute joule tolerance.
    Test.assert(absClose(a.mRG, b.mRG, 1.0));
    Test.assert(absClose(a.mRP, b.mRP, 50.0));
    return true;
}

function absClose(x, y, tol) {
    var d = x - y;
    if (d < 0.0) { d = -d; }
    return d <= tol;
}

// ---- validateBlob persistence-seam tests ----

// Build a well-formed, acceptable snapshot: version 2, started, fresh, matching sessId.
// STATE_LEN == 13; slots follow DualTankView's SLOT_* layout.
function makeValidBlob(nowSec, sess) {
    var blob = new [13];
    blob[0]  = 2;          // SLOT_VERSION == STATE_VERSION
    blob[1]  = nowSec;     // SLOT_SAVEDAT
    blob[2]  = sess;       // SLOT_SESS
    blob[3]  = 4000.0;     // SLOT_RP
    blob[4]  = 12000.0;    // SLOT_RG
    blob[5]  = 1000.0;     // SLOT_DEPP
    blob[6]  = 3000.0;     // SLOT_DEPG
    blob[7]  = 0.0;        // SLOT_AER
    blob[8]  = 0.0;        // SLOT_G
    blob[9]  = 0.0;        // SLOT_DEFICIT
    blob[10] = false;      // SLOT_PAUSED
    blob[11] = 0;          // SLOT_PAUSEAT
    blob[12] = true;       // SLOT_STARTED
    return blob;
}

(:test)
function testValidateBlobAccepts(logger) {
    var now = 1000000;
    var sess = 12345;
    var blob = makeValidBlob(now, sess);
    Test.assert(DualTankView.validateBlob(blob, now, sess));
    // Still fresh at the 24 h staleness boundary.
    Test.assert(DualTankView.validateBlob(blob, now + 86400, sess));
    return true;
}

(:test)
function testValidateBlobRejects(logger) {
    var now = 1000000;
    var sess = 12345;

    // Wrong size: a version-2, started, fresh, matching-sess blob that is one slot short,
    // so only the length check can reject it (isolates STATE_LEN from the other gates).
    var wrongSize = [2, now, sess, 4000.0, 12000.0, 1000.0, 3000.0, 0.0, 0.0, 0.0, false, 0];
    Test.assert(!DualTankView.validateBlob(wrongSize, now, sess));

    // Not an array.
    Test.assert(!DualTankView.validateBlob("not-an-array", now, sess));

    // Wrong version.
    var badVer = makeValidBlob(now, sess);
    badVer[0] = 1;
    Test.assert(!DualTankView.validateBlob(badVer, now, sess));

    // Never started.
    var notStarted = makeValidBlob(now, sess);
    notStarted[12] = false;
    Test.assert(!DualTankView.validateBlob(notStarted, now, sess));

    // Stale: saved more than 24 h before now.
    var stale = makeValidBlob(now, sess);
    Test.assert(!DualTankView.validateBlob(stale, now + 86401, sess));

    // sessId mismatch.
    var blob = makeValidBlob(now, sess);
    Test.assert(!DualTankView.validateBlob(blob, now, 99999));

    // Live sessId unknown (null).
    Test.assert(!DualTankView.validateBlob(blob, now, null));

    // Saved sessId unknown (null).
    var noSess = makeValidBlob(now, null);
    Test.assert(!DualTankView.validateBlob(noSess, now, sess));

    return true;
}

// ---- #64: settings finiteness gate (coerceFiniteFloat) ----
//
// Drives the pure static seam behind propFloat/propFloatOrNull with plain Lang values, so it
// runs without device Properties. A NaN would otherwise pass every comparison clamp in
// reloadSettings() and reach the model; ±Inf comes from a Float overflow. The 0.0 case is the
// regression guard for the rejected f/f != f/f idiom (0/0 = NaN would have dropped a legit 0.0).
(:test)
function testCoerceFiniteFloat(logger) {
    // Finite values pass through unchanged.
    Test.assert(DualTankView.coerceFiniteFloat(250.0) == 250.0);
    Test.assert(DualTankView.coerceFiniteFloat(-5.0) == -5.0);
    Test.assert(DualTankView.coerceFiniteFloat(0.0) == 0.0);    // MUST survive (legit gFat/fP=0.0)
    Test.assert(DualTankView.coerceFiniteFloat(300) == 300.0);  // Number -> Float

    // Unset / non-numeric -> null.
    Test.assert(DualTankView.coerceFiniteFloat(null) == null);
    Test.assert(DualTankView.coerceFiniteFloat("250") == null);

    // Build Float +Inf / -Inf / NaN by IEEE overflow (3.0e38 is in-range; its square is not).
    var fmax = (3.0e38).toFloat();
    var inf  = fmax * fmax;    // +Inf
    var nan  = inf - inf;      // NaN

    Test.assert(DualTankView.coerceFiniteFloat(inf) == null);     // +Inf -> null
    Test.assert(DualTankView.coerceFiniteFloat(-inf) == null);    // -Inf -> null
    Test.assert(DualTankView.coerceFiniteFloat(nan) == null);     // NaN  -> null

    return true;
}

// ---- #42: SET CP/W' guard reachability (isConfigured) ----
//
// Exercises mConfigured == false directly (the case the inert-guard regression hid): the pure
// seam behind reloadSettings()'s mConfigured. An unconfigured rider reads the sentinel 0 default
// from properties.xml; the guard must reject <=0 (and null, defensively) so an unset CP/W' shows
// the "SET CP/W'" prompt instead of running on the generic defaults.
(:test)
function testIsConfigured(logger) {
    // Both provided and positive -> configured.
    Test.assert(DualTankView.isConfigured(250.0, 20000.0));
    Test.assert(DualTankView.isConfigured(0.5, 1000.0));    // below-floor but PROVIDED -> configured

    // Sentinel 0 (unconfigured default) -> NOT configured; the SET CP/W' prompt stays up.
    Test.assert(!DualTankView.isConfigured(0.0, 20000.0));
    Test.assert(!DualTankView.isConfigured(250.0, 0.0));
    Test.assert(!DualTankView.isConfigured(0.0, 0.0));
    Test.assert(!DualTankView.isConfigured(-5.0, 20000.0)); // negative also rejected

    // null (defensive: unset/non-numeric via propFloatOrNull) -> NOT configured.
    Test.assert(!DualTankView.isConfigured(null, 20000.0));
    Test.assert(!DualTankView.isConfigured(250.0, null));
    Test.assert(!DualTankView.isConfigured(null, null));

    return true;
}
