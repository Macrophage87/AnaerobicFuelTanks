using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Activity;
using Toybox.Application;
using Toybox.FitContributor;
using Toybox.Math;
using Toybox.Time;
using Toybox.Lang;

//======================================================================
// Dual-Tank Anaerobic Reserve data field.
//
// UNITS / ASSUMPTIONS
//   - Energies are in JOULES; power in WATTS; dt = 1 s = one compute() call.
//   - W' is split into a fast PCr tank (cP) and a slow glycolytic tank (cG);
//     fP (the split) is a MODELING CHOICE, not a measured quantity.
//   - Demand above the aerobic supply is met by BOTH tanks in parallel. Glycolysis
//     has activation inertia (tauOn ~6 s, Parolin 1999), so PCr — the immediate
//     buffer — covers most of the onset and both drain together as glycolysis ramps
//     in. The SHARE of submaximal demand is capacity-proportional (both tanks track
//     W'bal in steady effort); the peak-flux RATE CEILING (pPmax, tapered with
//     fullness) governs maximal efforts, where PCr dominance emerges. Unmet demand is
//     banked as a deficit so combined W'bal stays energy-conserving.
//   - Below supply: PCr recovers (tauP, efficiency eta); glycolytic (and the
//     deficit) recover whenever P < CP at Skiba's intensity-dependent W'bal rate
//     tau_W'(CP-P), amplitude anchored to Ferguson 2010 at 20 W.
//
// REALISM TERMS (from white paper, tunable via settings):
//   - Aerobic ramp: BELOW CP the aerobic system covers demand (no anaerobic draw, so
//     PCr does not deplete below CP); ABOVE CP a sticky, floored aerobic tracker ramps
//     toward CP with tauAer, so the onset of a hard effort incurs an O2 deficit the
//     tanks cover. Set tauAer = 0 for a hard CP boundary.
//   - Fatigue-slowed PCr recovery: tauPeff = tauP * (1 + fatK * (1 - rG/cG)), so PCr
//     resynthesis slows as the glycolytic tank empties. Set fatK = 0 to disable.
//
// PAUSE/RESUME: depletion is frozen while paused; on resume the tanks are recovered
//   in closed form for the entire elapsed pause (rest recovery), with no depletion
//   accumulated during the pause.
//
// RENDERING: VERTICAL tanks are the standard look; the layout only falls back to
//   horizontal bars for a short strip too thin for a legible vertical bar —
//   large single field (w>=200 & h>=240): VERTICAL tanks on top + a summary;
//   any field tall enough (h>=74): two VERTICAL tanks side by side (the default);
//   short & wide strip (w>=2h): two HORIZONTAL bars SIDE BY SIDE;
//   short strip: two HORIZONTAL bars STACKED.
//   The large single field's summary panel shows per-system depleted kJ and a fatigue level.
// On-screen tank labels show reserve % ; the raw reserve in JOULES is written to the FIT
//   file (PCr_J / GLY_J record streams). Foreground color adapts to background luminance,
//   so it reads on light and dark themes.
//
// Implements the model in docs/white-paper-dual-tank-anaerobic-model.md.
//
// TEST TRACES (expected behaviour):
//   - 5 s @ 800 W then 60 s @ 100 W (CP 250): PCr bar drops sharply & bright,
//     GLY barely moves; PCr back to ~full (dull) within ~45-60 s.
//   - 3 min @ 300 W: PCr empties in ~20-40 s, then GLY bleeds; both low at end.
//   - 8x(20 s @ 400 / 40 s @ 120): PCr sawtooths; GLY trends down across the set.
//   - 20 min @ 150 W: both stay ~full; GLY slowly tops off since P < LT1.
//======================================================================
class DualTankView extends WatchUi.DataField {

    // ---- Colors (hue = system, brightness = draining now, red = empty) ----
    const COL_PCR_DULL   = 0x5A3A6E;  // muted purple  (idle / recovering)
    const COL_PCR_BRIGHT = 0xB44DFF;  // bright purple (actively depleting)
    const COL_GLY_DULL   = 0x2E5A3A;  // muted green
    const COL_GLY_BRIGHT = 0x37E85A;  // bright green
    const COL_RED        = 0xFF0000;  // depleted, flashing

    // ---- FIT field ids ----
    const FID_PCR_J  = 0;
    const FID_GLY_J  = 1;
    const FID_PCR_CONS = 2;
    const FID_GLY_CONS = 3;
    const FID_PCR_KJ   = 4;
    const FID_GLY_KJ   = 5;
    // Config parameters written to the FIT session message (so the settings the ride
    // ran with can be pulled back out and adjusted). IDs 6..17.
    const FID_CFG_CP      = 6;
    const FID_CFG_WPRIME  = 7;
    const FID_CFG_FP      = 8;
    const FID_CFG_PPMAX   = 9;
    const FID_CFG_TAUP    = 10;
    const FID_CFG_TAUG    = 11;
    const FID_CFG_LT1FRAC = 12;
    const FID_CFG_ETA     = 13;
    const FID_CFG_FATK    = 14;
    const FID_CFG_GFAT    = 15;
    const FID_CFG_TAUAER  = 16;
    const FID_CFG_TAUON   = 17;

    // Guard: cap a single pause's recovery to 24 h of rest (clock-change safety).
    const MAX_PAUSE_SEC = 86400;
    // Aerobic off-kinetics are slower than on-kinetics -> a "sticky" aerobic supply
    // so brief eases/coasts don't force a re-ramp. Off tau = tauAer * AER_FALL.
    const AER_FALL = 6.0;
    // Glycolytic peak rate as a fraction of PCr peak rate. PCr is the higher-power
    // system, so glycolysis is rate-capped below it (a modeling assumption; ~0.5).
    const GLY_RATE_FRAC = 0.5;

    // ---- State persistence (survives reboot / battery swap / CIQ reload mid-ride) ----
    const STATE_KEY      = "state";  // Application.Storage key for the snapshot blob
    const STATE_VERSION  = 2;        // schema version; bump on layout change (v2 adds sessId)
    const SAVE_EVERY_SEC = 10;       // min seconds between throttled compute() writes
    // Restore staleness cap, matched to MAX_PAUSE_SEC (24 h): a mid-activity pause that
    // outlives a reload still hands off to exitPause() (which itself caps recovery at
    // MAX_PAUSE_SEC and floors negative elapsed), so restoring mPaused/mPauseAt credits
    // closed-form recovery over the whole wall-clock off-gap without new exposure beyond
    // what MAX_PAUSE_SEC already guards. Secondary defense only — the primary guard against
    // a stale/foreign snapshot is the activity-identity (sessId) match in restoreState().
    const MAX_RESTORE_AGE_SEC = 86400;
    // Only a change of at least this many joules in any reserve/deficit/total marks the
    // state dirty. Without it, the sub-CP restoration branch drifts mRG/mDeficit by a
    // fraction of a joule every second, keeping the field permanently dirty and writing
    // every SAVE_EVERY_SEC for the rest of a ride that ever touched the glycolytic tank.
    const STATE_EPS_J = 25.0;
    // Fixed-order snapshot Array layout (lower alloc/serialize cost than a Dictionary).
    // sessId (the activity's start-time, unix s) keys the snapshot to ONE activity so a
    // previous ride's blob can't bleed into a new one within the staleness window:
    //   [version, savedAt, sessId, mRP, mRG, mDepP, mDepG, mAer, mG, mDeficit, mPaused, mPauseAt, mStarted]
    const STATE_LEN = 13;

    // ---- Settings ----
    hidden var mCP, mWprime, mFP, mPPmax, mTauP, mTauG, mLt1Frac, mEta;
    hidden var mFatK;    // PCr recovery fatigue-slowing coefficient (0 = disabled)
    hidden var mGFat;    // glycolytic flux fatigue exponent, rate_g *= (rG/cG)^gFat (0 = off)
    hidden var mTauAer;  // aerobic ramp time constant, s (0 = disabled -> hard CP)
    hidden var mTauOn;   // glycolytic activation time constant, s (~6, Parolin 1999)
    // ---- Derived capacities ----
    hidden var mCapP, mCapG;
    // ---- State ----
    hidden var mRP, mRG;        // reserves (J)
    hidden var mDepP, mDepG;    // session totals depleted per system (J)
    hidden var mConsP, mConsG;  // live draw (W)
    hidden var mAer;            // aerobic supply (W), when ramp enabled
    hidden var mG;              // glycolytic activation (0..1): ramps in over tauOn
    hidden var mDeficit;        // energy debt (J): supra-CP work the rate caps couldn't place
    hidden var mExhausted;      // genuine exhaustion: both reserves at/near zero (drives red flash)
    hidden var mRateLimited;    // producing power beyond the tanks' flux (unmet > 0) — usually a stale P1s
    hidden var mFlashOn;
    hidden var mStarted;
    hidden var mPaused;         // timer paused/stopped
    hidden var mPauseAt;        // unix seconds when the pause began
    // ---- Persistence bookkeeping (never serialized) ----
    hidden var mLastSaveSec;    // unix seconds of the last successful save (never null after initialize)
    hidden var mDirty;          // true when model state materially changed since the last save
    // Reserve/deficit/total values as of the last save (or baseline), for the epsilon
    // dirty-check — a change smaller than STATE_EPS_J is not worth a flash write.
    hidden var mSavRP, mSavRG, mSavDepP, mSavDepG, mSavDeficit;
    // ---- FIT fields ----
    hidden var mFPcrJ, mFGlyJ, mFPcrCons, mFGlyCons, mFPcrKj, mFGlyKj;
    hidden var mCfgFields;   // retained config session fields (CP, W', taus, ...)
    // ---- Draw resources ----
    hidden var mFontLabel, mFontValue, mFontSmall;

    function initialize() {
        DataField.initialize();
        reloadSettings();

        // Persistence bookkeeping must be non-null on EVERY path below (including the
        // corrupt/missing-blob fallback), or the first throttle check in compute() would
        // do arithmetic on null and crash. Set them before attempting a restore.
        mLastSaveSec = nowSec();
        mDirty = false;

        // Restore a mid-ride snapshot if one exists and is valid; otherwise fall back to
        // full-tank defaults. restoreState() REPLACES the default block (it doesn't run
        // after it) so an accepted restore isn't clobbered by the defaults.
        if (!restoreState()) {
            mRP = mCapP;
            mRG = mCapG;
            mDepP = 0.0;
            mDepG = 0.0;
            mAer = 0.0;
            mG = 0.0;
            mDeficit = 0.0;
            mStarted = false;
            mPaused = false;
            mPauseAt = 0;
        }
        // Derived / live / visual state is always reset regardless of which path ran —
        // it is recomputed each second and is never persisted.
        mConsP = 0.0;
        mConsG = 0.0;
        mExhausted = false;
        mRateLimited = false;
        mFlashOn = false;
        markSaved();   // seed the epsilon baseline so a restore doesn't read as dirty

        // Fonts (also set in onLayout; initialized here so onUpdate is always safe).
        mFontLabel = Graphics.FONT_XTINY;
        mFontValue = Graphics.FONT_TINY;
        mFontSmall = Graphics.FONT_XTINY;

        // Per-second record streams
        // Reserve energy remaining per tank, in joules (raw; divide by tank capacity for %)
        mFPcrJ  = createField("PCr_J",  FID_PCR_J,  FitContributor.DATA_TYPE_FLOAT,
            { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "J" });
        mFGlyJ  = createField("GLY_J",  FID_GLY_J,  FitContributor.DATA_TYPE_FLOAT,
            { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "J" });
        mFPcrCons = createField("PCr_cons", FID_PCR_CONS, FitContributor.DATA_TYPE_SINT16,
            { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "W" });
        mFGlyCons = createField("GLY_cons", FID_GLY_CONS, FitContributor.DATA_TYPE_SINT16,
            { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "W" });
        // Session totals (kJ) — finalized at ride save
        mFPcrKj   = createField("PCr_depleted_kJ", FID_PCR_KJ, FitContributor.DATA_TYPE_FLOAT,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "kJ" });
        mFGlyKj   = createField("GLY_depleted_kJ", FID_GLY_KJ, FitContributor.DATA_TYPE_FLOAT,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "kJ" });

        // Config parameters -> FIT session message. Written once (settings are fixed for
        // the ride); the values reflect exactly what the model ran with, so a post-ride
        // tool can read them back and adjust. Field names match the settings keys.
        mCfgFields = [
            cfgField("CP",      FID_CFG_CP,      mCP,      "W"),
            cfgField("Wprime",  FID_CFG_WPRIME,  mWprime,  "J"),
            cfgField("fP",      FID_CFG_FP,      mFP,      null),
            cfgField("pPmax",   FID_CFG_PPMAX,   mPPmax,   "W"),
            cfgField("tauP",    FID_CFG_TAUP,    mTauP,    "s"),
            cfgField("tauG",    FID_CFG_TAUG,    mTauG,    "s"),
            cfgField("lt1Frac", FID_CFG_LT1FRAC, mLt1Frac, null),
            cfgField("eta",     FID_CFG_ETA,     mEta,     null),
            cfgField("fatK",    FID_CFG_FATK,    mFatK,    null),
            cfgField("gFat",    FID_CFG_GFAT,    mGFat,    null),
            cfgField("tauAer",  FID_CFG_TAUAER,  mTauAer,  "s"),
            cfgField("tauOn",   FID_CFG_TAUON,   mTauOn,   "s")
        ];

        // Seed from current (possibly RESTORED) state so the session-total kJ fields
        // resume from the running total rather than restarting at 0 after a reload.
        mFPcrJ.setData(mRP);
        mFGlyJ.setData(mRG);
        mFPcrCons.setData(0);
        mFGlyCons.setData(0);
        mFPcrKj.setData(mDepP / 1000.0);
        mFGlyKj.setData(mDepG / 1000.0);
    }

    // Create a SESSION field for a config parameter and write its current value.
    // units may be null for dimensionless parameters (fP, eta, ...).
    hidden function cfgField(name, id, value, units) {
        var opts = { :mesgType => FitContributor.MESG_TYPE_SESSION };
        if (units != null) { opts[:units] = units; }
        var f = createField(name, id, FitContributor.DATA_TYPE_FLOAT, opts);
        f.setData(value);   // value is a settings Float (propFloat); FLOAT field
        return f;
    }

    // Read a numeric property, coerced to Float; dflt if unset/non-numeric.
    hidden function propFloat(key, dflt) {
        var v = Application.Properties.getValue(key);
        if (v instanceof Lang.Float)  { return v; }
        if (v instanceof Lang.Double) { return v.toFloat(); }
        if (v instanceof Lang.Number) { return v.toFloat(); }
        if (v instanceof Lang.Long)   { return v.toFloat(); }
        return dflt;
    }

    // Public so the app can push live settings changes.
    function reloadSettings() {
        mCP      = propFloat("CP", 250.0);
        mWprime  = propFloat("Wprime", 20000.0);
        mFP      = propFloat("fP", 0.25);
        mPPmax   = propFloat("pPmax", 300.0);
        mTauP    = propFloat("tauP", 22.0);
        mTauG    = propFloat("tauG", 360.0);
        mLt1Frac = propFloat("lt1Frac", 0.80);
        mEta     = propFloat("eta", 0.80);
        mFatK    = propFloat("fatK", 0.75);
        mGFat    = propFloat("gFat", 0.0);
        mTauAer  = propFloat("tauAer", 25.0);
        mTauOn   = propFloat("tauOn", 6.0);

        if (mCP < 1.0)     { mCP = 1.0; }
        if (mWprime < 1.0) { mWprime = 1.0; }
        if (mFP < 0.0)     { mFP = 0.0; }
        if (mFP > 1.0)     { mFP = 1.0; }
        if (mTauP < 1.0)   { mTauP = 1.0; }
        if (mTauG < 1.0)   { mTauG = 1.0; }
        if (mFatK < 0.0)   { mFatK = 0.0; }
        if (mGFat < 0.0)   { mGFat = 0.0; }
        if (mTauAer < 0.0) { mTauAer = 0.0; }
        if (mTauOn < 0.0)  { mTauOn = 0.0; }

        mCapP = mFP * mWprime;
        mCapG = (1.0 - mFP) * mWprime;
        if (mCapP < 1.0) { mCapP = 1.0; }
        if (mCapG < 1.0) { mCapG = 1.0; }

        // Re-clamp existing reserves to any new capacities (locals for null-narrowing;
        // mRP/mRG are null on the first call, made from initialize()).
        var rp = mRP;
        if (rp != null && rp > mCapP) { mRP = mCapP; }
        var rg = mRG;
        if (rg != null && rg > mCapG) { mRG = mCapG; }
    }

    // Fresh-ride initialization: full tanks, zeroed session totals.
    hidden function resetSession() {
        mRP = mCapP;
        mRG = mCapG;
        mDepP = 0.0;
        mDepG = 0.0;
        mConsP = 0.0;
        mConsG = 0.0;
        mAer = 0.0;
        mG = 0.0;
        mDeficit = 0.0;
        mExhausted = false;
        mRateLimited = false;
    }

    hidden function nowSec() {
        return Time.now().value();
    }

    // Stable per-activity identity: the recording activity's start time (unix seconds),
    // or null if no activity is recording yet. A reload/reboot of the SAME activity keeps
    // this value (the system persists the in-progress activity); a brand-new activity gets
    // a different start time. Used to key a snapshot to one ride.
    hidden function sessIdNow() {
        var info = Activity.getActivityInfo();
        if (info != null && info.startTime != null) {
            return info.startTime.value();
        }
        return null;
    }

    // Snapshot the current reserve/total/deficit values as the epsilon-dirty baseline.
    hidden function markSaved() {
        mSavRP = mRP;
        mSavRG = mRG;
        mSavDepP = mDepP;
        mSavDepG = mDepG;
        mSavDeficit = mDeficit;
    }

    hidden function absf(x) {
        return (x < 0.0) ? -x : x;
    }

    // Restore a persisted snapshot into the model state. Returns true only on an
    // accepted restore; on a missing/corrupt/stale/pre-start blob (or any exception)
    // returns false so initialize() falls back to full-tank defaults. Any partial
    // assignment before a thrown error is harmless: the default block overwrites every
    // persisted field.
    hidden function restoreState() {
        try {
            var blob = Application.Storage.getValue(STATE_KEY);
            if (!(blob instanceof Lang.Array)) { return false; }
            if (blob.size() != STATE_LEN)      { return false; }
            if (blob[0] != STATE_VERSION)      { return false; }
            var savedAt   = blob[1];
            var savedSess = blob[2];
            var started   = blob[12];
            if (started != true)                            { return false; }  // never ran -> don't restore
            if ((nowSec() - savedAt) > MAX_RESTORE_AGE_SEC) { return false; }  // stale (secondary guard)
            // Activity-identity gate (PRIMARY guard). Only resume a snapshot that belongs to
            // the currently recording activity. A previous ride the user never reset would
            // otherwise bleed into a new one inside the staleness window: restored
            // mStarted=true makes onTimerStart take the resume branch and skip resetSession(),
            // so the new ride runs on the old depleted tanks. Requiring both ids known and
            // equal fails safe to full tanks when the activity can't be identified.
            var liveSess = sessIdNow();
            if (savedSess == null || liveSess == null || savedSess != liveSess) { return false; }

            mRP      = blob[3];
            mRG      = blob[4];
            mDepP    = blob[5];
            mDepG    = blob[6];
            mAer     = blob[7];
            mG       = blob[8];
            mDeficit = blob[9];
            mPaused  = blob[10];
            mPauseAt = blob[11];
            mStarted = started;

            // Re-clamp reserves to current capacities in case settings (CP/W'/fP)
            // changed between sessions (same idiom as reloadSettings()/compute()).
            if (mRP > mCapP) { mRP = mCapP; }
            if (mRP < 0.0)   { mRP = 0.0; }
            if (mRG > mCapG) { mRG = mCapG; }
            if (mRG < 0.0)   { mRG = 0.0; }

            // DELIBERATE LIMITATION: a reload/reboot while UNPAUSED (mPaused==false) — e.g. a
            // dead-battery crash mid-effort, the feature's primary case — resumes the tanks at
            // their pre-crash depleted level. No rest recovery is credited for the unrecorded
            // off-gap here: exitPause() is mPaused-guarded, and crediting it would be a model
            // change beyond this issue's "persist state only" scope. The error is conservative
            // (understates reserve, never overstates). A reload while PAUSED still recovers
            // correctly — restored mPaused/mPauseAt hand off to exitPause() on the next resume.
            return true;
        } catch (e) {
            return false;
        }
    }

    // Persist the model state. Coalesced: writes only when dirty, so a steady ride at
    // full tanks produces no redundant flash writes. Public so DualTankApp.onStop can
    // force a final flush. Resets the throttle/dirty bookkeeping on a successful write
    // so a following periodic compute() write isn't double-fired.
    function saveState() {
        if (!mDirty) { return; }
        try {
            var blob = [
                STATE_VERSION, nowSec(), sessIdNow(),
                mRP, mRG, mDepP, mDepG, mAer, mG, mDeficit,
                mPaused, mPauseAt, mStarted
            ];
            Application.Storage.setValue(STATE_KEY, blob);
            mLastSaveSec = nowSec();
            mDirty = false;
            markSaved();   // reset the epsilon baseline to what we just persisted
        } catch (e) {
            // Storage full or unavailable: keep running; retry on the next flush.
        }
    }

    // Drop any persisted snapshot (fresh ride) so the next activity starts full.
    hidden function clearState() {
        try {
            Application.Storage.deleteValue(STATE_KEY);
        } catch (e) {
        }
        mDirty = false;
        markSaved();   // caller has reset the model; re-baseline so it isn't re-dirtied
    }

    // On pause/stop: freeze depletion, remember when the pause started.
    hidden function enterPause() {
        if (!mPaused) {
            mPaused = true;
            mPauseAt = nowSec();
            mDirty = true;
        }
    }

    // On resume: recover the tanks for the WHOLE elapsed pause (closed form),
    // without having accumulated any depletion while paused.
    hidden function exitPause() {
        if (mPaused) {
            var el = nowSec() - mPauseAt;
            if (el < 0) { el = 0; }
            if (el > MAX_PAUSE_SEC) { el = MAX_PAUSE_SEC; }
            applyRestRecovery(el);
            mAer = 0.0;         // aerobic supply has decayed to rest during the pause
            mG = 0.0;           // glycolytic activation has relaxed during the pause
            mDeficit = 0.0;     // debt repaid over the pause
            mPaused = false;
            mDirty = true;
        }
    }

    // Closed-form recovery over `secs` seconds at rest (power = 0), i.e. the
    // per-second exponential recovery applied N times without a loop:
    //   cap - R_N = (cap - R_0) * (1 - a)^N
    hidden function applyRestRecovery(secs) {
        if (secs <= 0) { return; }
        // Glycolytic at rest (P = 0): Skiba rate at CP-0, anchored to Ferguson at 20 W,
        // matching the live-loop recovery law. b = (1 - e^(-1/tauG)) * f(0).
        var tauW0 = 546.0 * Math.pow(Math.E, -0.01 * mCP) + 316.0;
        var tauWa = 546.0 * Math.pow(Math.E, -0.01 * (mCP - 20.0)) + 316.0;
        var g20 = (mCP > 0.0) ? (mLt1Frac * mCP - 20.0) / (mLt1Frac * mCP) : 1.0;
        var f0 = g20 * tauWa / tauW0;
        if (f0 < 0.0) { f0 = 0.0; }
        var bG = (1.0 - Math.pow(Math.E, -1.0 / mTauG)) * f0;
        if (bG < 0.0) { bG = 0.0; }
        if (bG > 1.0) { bG = 1.0; }
        mRG = mCapG - (mCapG - mRG) * Math.pow(1.0 - bG, secs);
        if (mRG < 0.0) { mRG = 0.0; }
        if (mRG > mCapG) { mRG = mCapG; }
        // PCr with fatigue-slowed tau, evaluated at the (now largely recovered)
        // glycolytic fill: a = eta * (1 - e^(-1/tauPeff))
        var tauPeff = pcrTau();
        var aP = mEta * (1.0 - Math.pow(Math.E, -1.0 / tauPeff));
        if (aP < 0.0) { aP = 0.0; }
        if (aP > 1.0) { aP = 1.0; }
        mRP = mCapP - (mCapP - mRP) * Math.pow(1.0 - aP, secs);
        if (mRP < 0.0) { mRP = 0.0; }
        if (mRP > mCapP) { mRP = mCapP; }
    }

    // Fatigue-slowed PCr recovery time constant:
    //   tauPeff = tauP * (1 + fatK * (1 - rG/cG))   (slows as glycolytic empties)
    hidden function pcrTau() {
        var fillG = mRG / mCapG;
        if (fillG < 0.0) { fillG = 0.0; }
        if (fillG > 1.0) { fillG = 1.0; }
        var t = mTauP * (1.0 + mFatK * (1.0 - fillG));
        if (t < 1.0) { t = 1.0; }
        return t;
    }

    function onTimerStart() {
        if (!mStarted) {
            resetSession();
            mStarted = true;
            mPaused = false;
        } else {
            exitPause();   // resume from a stopped (but not reset) timer
        }
        mDirty = true;
        saveState();       // flush immediately so a reboot right after start restores mStarted
    }

    function onTimerResume() {
        exitPause();       // sets mDirty when it actually resumes
        saveState();
    }

    function onTimerPause() {
        enterPause();      // sets mDirty when it actually pauses
        saveState();
    }

    function onTimerStop() {
        enterPause();
        saveState();
    }

    function onTimerReset() {
        resetSession();
        mStarted = false;
        mPaused = false;
        clearState();      // fresh ride -> drop the snapshot so the next activity starts full
    }

    function onLayout(dc) {
        mFontLabel = Graphics.FONT_XTINY;
        mFontValue = Graphics.FONT_TINY;
        mFontSmall = Graphics.FONT_XTINY;
    }

    //------------------------------------------------------------------
    // Model step — called once per second by the system.
    //------------------------------------------------------------------
    function compute(info) {
        // While paused/stopped: freeze depletion (no accumulation). Recovery for
        // the pause is applied in one shot on resume (see exitPause()).
        if (mPaused) {
            mConsP = 0.0;
            mConsG = 0.0;
            mFPcrJ.setData(mRP);
            mFGlyJ.setData(mRG);
            mFPcrCons.setData(0);
            mFGlyCons.setData(0);
            return 100.0 * mRP / mCapP;
        }

        var p = 0.0;
        if (info != null) {
            var cp = info.currentPower;   // Number or null
            if (cp != null) { p = cp.toFloat(); }
        }

        var dt = 1.0;

        // Aerobic supply.
        //   Below CP: the aerobic system covers demand (supply = P) -> no anaerobic
        //     draw, so PCr does NOT deplete while you ride below CP.
        //   Above CP: a sticky, floored aerobic tracker ramps toward CP with tauAer,
        //     so the ONSET of a hard effort incurs an oxygen deficit the tanks cover,
        //     tapering to (P - CP) as aerobic catches up. Off-kinetics are slower
        //     (AER_FALL) so brief eases don't reset the ramp and churn PCr.
        //   tauAer <= 0 disables the ramp (hard CP boundary).
        var supply = mCP;
        if (mTauAer > 0.0) {
            var tgt = (p < mCP) ? p : mCP;
            var kA = (tgt > mAer)
                ? (1.0 - Math.pow(Math.E, -dt / mTauAer))
                : (1.0 - Math.pow(Math.E, -dt / (mTauAer * AER_FALL)));
            mAer += (tgt - mAer) * kA;
            var floorA = 0.5 * mCP;
            if (mAer < floorA) { mAer = floorA; }
            if (mAer > mCP) { mAer = mCP; }
            supply = (p > mCP) ? mAer : p;
        } else {
            mAer = mCP;
        }

        var delta = p - supply;
        var takeP = 0.0;
        var takeG = 0.0;

        if (delta > 0.0) {
            // DEPLETION — PARALLEL draw. Glycolysis has activation inertia (Parolin
            // 1999), so PCr — the immediate buffer — covers almost everything at onset
            // and both drain together as mG -> 1. TWO distinct roles, decoupled: the
            // SHARE of submaximal demand is capacity-proportional (wP=cP, wG=cG*g) so at
            // steady state both tanks track W'bal and empty together at exhaustion; the
            // RATE CEILING is the peak-flux cap, tapered with fullness (PCr flux falls as
            // the store depletes). The ceiling governs MAXIMAL efforts (PCr dominance
            // emerges there) without distorting submaximal sharing. Residual demand the
            // tanks cannot place is banked as a DEFICIT so combined W'bal is conserved.
            var need = delta * dt;
            var kOn = (mTauOn > 0.0) ? (1.0 - Math.pow(Math.E, -dt / mTauOn)) : 1.0;
            mG += (1.0 - mG) * kOn;

            var rateP = mPPmax * (mRP / mCapP);      // rate ceiling (tapered)
            var rateG = GLY_RATE_FRAC * mPPmax * mG;
            // Optional glycolytic flux fatigue (mGFat > 0): acidosis inhibits phosphorylase
            // /PFK, so glycolytic flux falls across repeated maximal sprints. Off (0) by
            // default — it shifts the depletion split, so headline behaviour is unchanged
            // unless enabled. See white paper §6.10.
            if (mGFat > 0.0 && mCapG > 0.0) {
                var fillG2 = mRG / mCapG;
                if (fillG2 < 0.0) { fillG2 = 0.0; }
                rateG *= Math.pow(fillG2, mGFat);
            }
            var pcap = rateP * dt;
            var gcap = rateG * dt;
            var wP = mCapP;                           // share weight (capacity-proportional)
            var wG = mCapG * mG;
            var totW = wP + wG;
            var pShare = (totW > 1e-9) ? need * (wP / totW) : need;
            var gShare = need - pShare;

            takeP = pShare;
            if (takeP > mRP) { takeP = mRP; }
            if (takeP > pcap) { takeP = pcap; }
            takeG = gShare;
            if (takeG > mRG) { takeG = mRG; }
            if (takeG > gcap) { takeG = gcap; }

            var unmet = need - takeP - takeG;
            if (unmet > 0.0) {                       // glycolytic soaks up PCr's shortfall (rate-capped)
                var addG = unmet;
                if (addG > mRG - takeG) { addG = mRG - takeG; }
                if (addG > gcap - takeG) { addG = gcap - takeG; }
                takeG += addG; unmet -= addG;
            }
            if (unmet > 0.0) {                       // then PCr soaks up glycolytic's, up to its (tapered) cap
                var addP = unmet;
                if (addP > mRP - takeP) { addP = mRP - takeP; }
                if (addP > pcap - takeP) { addP = pcap - takeP; }
                takeP += addP; unmet -= addP;
            }

            mRP -= takeP;
            mRG -= takeG;
            mDeficit += unmet;                       // bank the debt (energy conservation)
            mDepP += takeP;
            mDepG += takeG;
            // Two distinct states: genuine exhaustion (tanks empty) drives the red flash;
            // rate-limited (unmet>0 with tanks non-empty) means "power beyond my flux caps",
            // usually a stale P1s rather than a spent rider.
            mExhausted = ((mRP + mRG) <= 1.0);
            mRateLimited = (unmet > 0.0);
            mConsP = takeP / dt;
            mConsG = takeG / dt;
        } else {
            // RESTORATION — PCr with fatigue-slowed tau; glycolytic gated below LT1.
            var kOff = (mTauOn > 0.0) ? (1.0 - Math.pow(Math.E, -dt / mTauOn)) : 1.0;
            mG -= mG * kOff;                          // glycolytic deactivation during recovery
            // PCr resynthesis is OXIDATIVE: it needs aerobic ATP above what the ride itself
            // consumes, so it is gated by the oxidative headroom (CP - P) — near-arrested at
            // CP, full at rest. Without this the "punch" bar refills while still under load.
            var gateP = (mCP - p) / mCP;
            if (gateP < 0.0) { gateP = 0.0; }
            var tauPeff = pcrTau();
            mRP += gateP * mEta * (mCapP - mRP) * (1.0 - Math.pow(Math.E, -dt / tauPeff));
            // Glycolytic tank AND the deficit recover whenever P < CP, at Skiba's
            // intensity-dependent W'bal rate tau_W'(CP-P) = 546*e^(-0.01*(CP-P)) + 316,
            // its amplitude re-anchored so the 20 W passive rate reproduces Ferguson 2010
            // (as v0.6 did). This REPLACES the old linear (LT1-P)/LT1 gate, whose rate went
            // to zero at LT1 (recovery -> infinity), which made the model unable to complete
            // a standard 4x4. Skiba's form is bounded and was fitted across recovery powers.
            if (p < mCP && mCP > 0.0) {
                var dcp = mCP - p;
                var tauW = 546.0 * Math.pow(Math.E, -0.01 * dcp) + 316.0;
                var tauWanchor = 546.0 * Math.pow(Math.E, -0.01 * (mCP - 20.0)) + 316.0;
                var gate20 = (mLt1Frac * mCP - 20.0) / (mLt1Frac * mCP);
                var fG = gate20 * tauWanchor / tauW;
                if (fG < 0.0) { fG = 0.0; }
                var kG = (1.0 - Math.pow(Math.E, -dt / mTauG)) * fG;
                if (kG < 0.0) { kG = 0.0; }
                if (kG > 1.0) { kG = 1.0; }
                mRG += (mCapG - mRG) * kG;
                mDeficit -= mDeficit * kG;
            }
            mConsP = 0.0;
            mConsG = 0.0;
            mExhausted = ((mRP + mRG) <= 1.0);
            mRateLimited = false;
        }

        // Clamp
        if (mRP < 0.0) { mRP = 0.0; }
        if (mRP > mCapP) { mRP = mCapP; }
        if (mRG < 0.0) { mRG = 0.0; }
        if (mRG > mCapG) { mRG = mCapG; }

        var pctP = 100.0 * mRP / mCapP;

        // FIT: per-second reserve streams (joules remaining) + live consumption
        mFPcrJ.setData(mRP);
        mFGlyJ.setData(mRG);
        mFPcrCons.setData(mConsP.toNumber());
        mFGlyCons.setData(mConsG.toNumber());
        // FIT: running session totals (kJ) — SDK keeps last value as summary
        mFPcrKj.setData(mDepP / 1000.0);
        mFGlyKj.setData(mDepG / 1000.0);

        // Epsilon dirty-check: flag dirty only on a MATERIAL change (>= STATE_EPS_J in any
        // reserve / session total / deficit) since the last save. Without this, the sub-CP
        // restoration branch drifts mRG/mDeficit by a fraction of a joule every second and
        // keeps the field permanently dirty on any ride that ever used the glycolytic tank.
        // (Pause/resume/start still set mDirty explicitly — those aren't reserve changes.)
        if (!mDirty) {
            if (absf(mRP - mSavRP) >= STATE_EPS_J ||
                absf(mRG - mSavRG) >= STATE_EPS_J ||
                absf(mDepP - mSavDepP) >= STATE_EPS_J ||
                absf(mDepG - mSavDepG) >= STATE_EPS_J ||
                absf(mDeficit - mSavDeficit) >= STATE_EPS_J) {
                mDirty = true;
            }
        }

        // Persist the model state, throttled AND dirty-checked (flash-wear safe): at most
        // once per SAVE_EVERY_SEC, and only when state materially changed. Sits after the
        // mPaused early-return above, so paused seconds don't write. saveState() re-checks
        // mDirty and resets the throttle + epsilon baseline on a successful write.
        if (mDirty && (nowSec() - mLastSaveSec >= SAVE_EVERY_SEC)) {
            saveState();
        }

        // Drive the depleted-bar blink (toggles at 1 Hz -> ~0.5 Hz visible).
        mFlashOn = !mFlashOn;

        return pctP;
    }

    //------------------------------------------------------------------
    // Rendering — two stacked horizontal bars.
    //------------------------------------------------------------------
    // Readable foreground for ANY background (black, white, gray, or custom color),
    // chosen by luminance so the field works on light and dark themes alike.
    hidden function contrastColor(bg) {
        if (bg == Graphics.COLOR_TRANSPARENT) { return Graphics.COLOR_WHITE; }
        var r = (bg >> 16) & 0xFF;
        var g = (bg >> 8) & 0xFF;
        var b = bg & 0xFF;
        var lum = (r * 30 + g * 59 + b * 11) / 100;   // ~perceived brightness 0..255
        return (lum > 140) ? Graphics.COLOR_BLACK : Graphics.COLOR_WHITE;
    }

    function onUpdate(dc) {
        var bg = getBackgroundColor();
        var fg = contrastColor(bg);
        dc.setColor(bg, bg);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        if (mCP <= 0.0 || mWprime <= 0.0) {
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2, mFontValue, "SET CP/W'",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var pctP = 100.0 * mRP / mCapP;
        var pctG = 100.0 * mRG / mCapG;

        // VERTICAL tanks are the standard look on most layouts; only a genuinely short
        // strip (too short for a legible vertical bar) falls back to horizontal bars:
        //   large single field (w>=200, h>=240): vertical tanks on top + summary stats
        //   any field tall enough (h>=74): two VERTICAL tanks side by side  <-- default
        //   short & wide strip (w>=2h): two HORIZONTAL bars side by side
        //   short strip: two HORIZONTAL bars stacked
        if (w >= 200 && h >= 240) {
            drawFull(dc, w, h, fg, pctP, pctG);
        } else if (h >= 74) {
            drawVertical(dc, w, h, fg, pctP, pctG);
        } else if (w >= h * 2) {
            drawHorizontalPair(dc, w, h, fg, pctP, pctG);
        } else {
            drawHorizontal(dc, w, h, fg, pctP, pctG);
        }
    }

    // --- very wide slot: two horizontal bars side by side (PCr | GLY) ---
    hidden function drawHorizontalPair(dc, w, h, fg, pctP, pctG) {
        var pad = 4;
        var gap = 8;
        var labelW = 30;
        var valueW = 42;
        var halfW = (w - gap) / 2;
        var barH = h - 2 * pad;
        if (barH > 60) { barH = 60; }
        if (barH < 6)  { barH = 6; }
        var y = (h - barH) / 2;

        var lBarX = pad + labelW;
        var lBarW = halfW - labelW - valueW - pad;
        if (lBarW < 10) { lBarW = 10; }
        drawBarH(dc, lBarX, y, lBarW, barH, pctP, true, fg);

        var rx = halfW + gap;
        var rBarX = rx + labelW;
        var rBarW = w - rBarX - valueW - pad;
        if (rBarW < 10) { rBarW = 10; }
        drawBarH(dc, rBarX, y, rBarW, barH, pctG, false, fg);

        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(pad, y + barH / 2, mFontLabel, "PCr",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(halfW, y + barH / 2, mFontValue, fmtPct(pctP),
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(rx, y + barH / 2, mFontLabel, "GLY",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(w - pad, y + barH / 2, mFontValue, fmtPct(pctG),
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // --- wide/short slot: two horizontal bars stacked ---
    hidden function drawHorizontal(dc, w, h, fg, pctP, pctG) {
        var pad = 4;
        var labelW = 30;
        var valueW = 42;
        var barH = (h - 3 * pad) / 2;
        if (barH > 34) { barH = 34; }
        if (barH < 6)  { barH = 6; }
        var yTop = pad;
        var yBot = h - pad - barH;
        var xBar = pad + labelW;
        var barW = w - xBar - valueW - pad;
        if (barW < 10) { barW = 10; }

        drawBarH(dc, xBar, yTop, barW, barH, pctP, true, fg);
        drawBarH(dc, xBar, yBot, barW, barH, pctG, false, fg);

        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(pad, yTop + barH / 2, mFontLabel, "PCr",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(pad, yBot + barH / 2, mFontLabel, "GLY",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(w - pad, yTop + barH / 2, mFontValue, fmtPct(pctP),
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(w - pad, yBot + barH / 2, mFontValue, fmtPct(pctG),
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // --- two vertical bars side by side, within the rect (x0,y0,w,hh) ---
    hidden function drawVerticalIn(dc, x0, y0, w, hh, fg, pctP, pctG) {
        var pad = 4;
        var gap = 6;
        var labelH = dc.getFontHeight(mFontLabel);
        var valueH = dc.getFontHeight(mFontValue);
        var colW = (w - 2 * pad - gap) / 2;
        if (colW < 8) { colW = 8; }
        var barTop = y0 + pad + labelH;
        var barBot = y0 + hh - pad - valueH;
        var barH = barBot - barTop;
        if (barH < 10) { barH = 10; }
        var lx = x0 + pad;
        var rx = x0 + pad + colW + gap;

        drawBarV(dc, lx, barTop, colW, barH, pctP, true, fg);
        drawBarV(dc, rx, barTop, colW, barH, pctG, false, fg);

        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(lx + colW / 2, y0 + pad, mFontLabel, "PCr", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(rx + colW / 2, y0 + pad, mFontLabel, "GLY", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(lx + colW / 2, barBot, mFontValue, fmtPct(pctP), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(rx + colW / 2, barBot, mFontValue, fmtPct(pctG), Graphics.TEXT_JUSTIFY_CENTER);
    }

    // --- square/tall slot: two vertical bars filling the whole field ---
    hidden function drawVertical(dc, w, h, fg, pctP, pctG) {
        drawVerticalIn(dc, 0, 0, w, h, fg, pctP, pctG);
    }

    // Current fatigue level (%): how much PCr recovery is slowed right now, driven
    // by glycolytic depletion — tauPeff/tauP - 1 = fatK*(1 - rG/cG).
    hidden function fatiguePct() {
        var fillG = mRG / mCapG;
        if (fillG < 0.0) { fillG = 0.0; }
        if (fillG > 1.0) { fillG = 1.0; }
        var f = mFatK * (1.0 - fillG) * 100.0;
        if (f < 0.0) { f = 0.0; }
        return f;
    }

    // --- large single-field screen: vertical tanks on top, summary stats below ---
    hidden function drawFull(dc, w, h, fg, pctP, pctG) {
        var topH = h * 3 / 5;                 // ~60% for the two tanks
        drawVerticalIn(dc, 0, 0, w, topH, fg, pctP, pctG);

        // divider
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(6, topH, w - 6, topH);

        // distribute the three stat rows across the panel below the divider
        var half = w / 2;
        var avail = h - topH;
        var yHdr = topH + avail * 16 / 100;
        var yKj  = topH + avail * 46 / 100;
        var yFat = topH + avail * 78 / 100;
        var ctr = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.drawText(w / 2, yHdr, mFontSmall, "DEPLETED (kJ)", ctr);
        dc.drawText(half / 2, yKj, mFontValue,
            "PCr " + (mDepP / 1000.0).format("%.1f"), ctr);
        dc.drawText(half + half / 2, yKj, mFontValue,
            "GLY " + (mDepG / 1000.0).format("%.1f"), ctr);
        dc.drawText(w / 2, yFat, mFontValue,
            "Fatigue " + fatiguePct().toNumber().toString() + "%", ctr);
    }

    // Tank value label shown on-screen: reserve as a percentage of tank capacity.
    // (The raw reserve in joules is written to the FIT file — PCr_J / GLY_J.)
    hidden function fmtPct(v) {
        return v.toNumber().toString() + "%";
    }

    // pick fill color by state; returns null when the depleted "off" flash frame
    // should draw no fill at all.
    hidden function fillColor(isPcr, depleted, draining) {
        if (depleted) {
            if (!mFlashOn) { return null; }
            return COL_RED;
        }
        if (draining) { return isPcr ? COL_PCR_BRIGHT : COL_GLY_BRIGHT; }
        return isPcr ? COL_PCR_DULL : COL_GLY_DULL;
    }

    // rounded-rectangle "tank" fill helper (radius clamped to fit)
    hidden function fillTank(dc, col, x, y, w, h, r) {
        if (w <= 0 || h <= 0) { return; }
        var rr = r - 1;
        if (rr > w / 2) { rr = w / 2; }
        if (rr > h / 2) { rr = h / 2; }
        if (rr < 1) { rr = 1; }
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, w, h, rr);
    }

    // horizontal bar: rounded "tank" filling left -> right
    hidden function drawBarH(dc, x, y, bw, bh, pct, isPcr, fg) {
        var r = bh / 3; if (r < 2) { r = 2; }
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x, y, bw, bh, r);

        var depleted = (pct <= 3.0);
        var draining = isPcr ? (mConsP > 0.0) : (mConsG > 0.0);
        var col = fillColor(isPcr, depleted, draining);
        if (col == null) { return; }

        var fillW;
        if (depleted) {
            fillW = bw - 2;
        } else {
            fillW = ((bw - 2) * pct / 100.0).toNumber();
            if (fillW < 0) { fillW = 0; }
            if (fillW > bw - 2) { fillW = bw - 2; }
        }
        fillTank(dc, col, x + 1, y + 1, fillW, bh - 2, r);

        if (draining && !depleted) {
            var wtxt = "-" + (isPcr ? mConsP : mConsG).toNumber().toString() + "W";
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + bw - 3, y + bh / 2, mFontSmall, wtxt,
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // vertical bar: rounded "tank" filling bottom -> top
    hidden function drawBarV(dc, x, y, bw, bh, pct, isPcr, fg) {
        var r = bw / 3; if (r < 2) { r = 2; }
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x, y, bw, bh, r);

        var depleted = (pct <= 3.0);
        var draining = isPcr ? (mConsP > 0.0) : (mConsG > 0.0);
        var col = fillColor(isPcr, depleted, draining);
        if (col == null) { return; }

        var fillH;
        if (depleted) {
            fillH = bh - 2;
        } else {
            fillH = ((bh - 2) * pct / 100.0).toNumber();
            if (fillH < 0) { fillH = 0; }
            if (fillH > bh - 2) { fillH = bh - 2; }
        }
        fillTank(dc, col, x + 1, y + bh - 1 - fillH, bw - 2, fillH, r);

        if (draining && !depleted) {
            var wtxt = "-" + (isPcr ? mConsP : mConsG).toNumber().toString() + "W";
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + bw / 2, y + 2, mFontSmall, wtxt, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}
