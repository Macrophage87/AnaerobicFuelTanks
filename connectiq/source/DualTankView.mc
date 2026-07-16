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
// ---- Module-scope persistence constants ----------------------------------
// At MODULE scope (not class members) so the pure `static` DualTankView.validateBlob()
// can reference them — a static method has no `self`, so class-level consts are not
// visible to it. Instance methods resolve these by bare name via module scope too.
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
// Power-dropout bridge window (#22). On a MISSING power sample (info/currentPower null —
// an ANT+/BLE dropout, NOT a valid 0 W coast) we reuse the last valid power for up to this
// many consecutive seconds so a brief glitch keeps depleting at the real load, then FREEZE
// (hold reserves) rather than collapse to 0 W and trip the model's restoration branch.
// Kept small so a stale value can't over-deplete before the freeze takes over.
const BRIDGE_SEC = 3;
// Fixed-order snapshot Array layout (lower alloc/serialize cost than a Dictionary).
// sessId (the activity's start-time, unix s) keys the snapshot to ONE activity so a
// previous ride's blob can't bleed into a new one within the staleness window.
// Both saveState() and restoreState() index EXCLUSIVELY via these SLOT_* constants,
// so the writer and reader can't silently desync. TO ADD A FIELD: append a new SLOT_*
// before STATE_LEN, bump STATE_LEN and STATE_VERSION, and set/read it in both methods.
const SLOT_VERSION = 0;
const SLOT_SAVEDAT = 1;
const SLOT_SESS    = 2;
const SLOT_RP      = 3;
const SLOT_RG      = 4;
const SLOT_DEPP    = 5;
const SLOT_DEPG    = 6;
const SLOT_AER     = 7;
const SLOT_G       = 8;
const SLOT_DEFICIT = 9;
const SLOT_PAUSED  = 10;
const SLOT_PAUSEAT = 11;
const SLOT_STARTED = 12;
const STATE_LEN    = 13;

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


    // ---- Physiology model (settings + derived capacities + reserve/deficit state +
    //      the per-second physics step). All numeric model concerns live here; the view
    //      delegates to it and keeps only DataField / FIT / rendering / persistence /
    //      lifecycle. Constructed in initialize() before reloadSettings(). ----
    hidden var mModel;
    hidden var mFlashOn;
    hidden var mStarted;
    hidden var mPaused;         // timer paused/stopped
    hidden var mPauseAt;        // unix seconds when the pause began
    // ---- Power-dropout bridge/freeze state (#22; derived, per-second, NEVER serialized) ----
    hidden var mLastP;          // last VALID power (W); reused during the bridge window
    hidden var mMissCount;      // consecutive missing-sample seconds
    hidden var mHaveValidP;     // false until a valid sample is seen this session (cold-start
                                // / post-restore guard: a missing sample then FREEZES, so it
                                // can't bridge at the mLastP=0.0 seed and inject phantom recovery)
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
        mModel = new TankModel();   // must exist before reloadSettings() calls configure()
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
            mModel.mRP = mModel.mCapP;
            mModel.mRG = mModel.mCapG;
            mModel.mDepP = 0.0;
            mModel.mDepG = 0.0;
            mModel.mAer = 0.0;
            mModel.mG = 0.0;
            mModel.mDeficit = 0.0;
            mStarted = false;
            mPaused = false;
            mPauseAt = 0;
        }
        // Derived / live / visual state is always reset regardless of which path ran —
        // it is recomputed each second and is never persisted.
        mModel.mConsP = 0.0;
        mModel.mConsG = 0.0;
        mModel.mExhausted = false;
        mModel.mRateLimited = false;
        // Dropout bridge/freeze state (#22). mHaveValidP=false on EVERY path (fresh or
        // restored) so a missing sample before the first valid reading — including right
        // after a depleted-tank restore — freezes rather than bridging at the 0.0 seed.
        mLastP = 0.0;
        mMissCount = 0;
        mHaveValidP = false;
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
            cfgField("CP",      FID_CFG_CP,      mModel.mCP,      "W"),
            cfgField("Wprime",  FID_CFG_WPRIME,  mModel.mWprime,  "J"),
            cfgField("fP",      FID_CFG_FP,      mModel.mFP,      null),
            cfgField("pPmax",   FID_CFG_PPMAX,   mModel.mPPmax,   "W"),
            cfgField("tauP",    FID_CFG_TAUP,    mModel.mTauP,    "s"),
            cfgField("tauG",    FID_CFG_TAUG,    mModel.mTauG,    "s"),
            cfgField("lt1Frac", FID_CFG_LT1FRAC, mModel.mLt1Frac, null),
            cfgField("eta",     FID_CFG_ETA,     mModel.mEta,     null),
            cfgField("fatK",    FID_CFG_FATK,    mModel.mFatK,    null),
            cfgField("gFat",    FID_CFG_GFAT,    mModel.mGFat,    null),
            cfgField("tauAer",  FID_CFG_TAUAER,  mModel.mTauAer,  "s"),
            cfgField("tauOn",   FID_CFG_TAUON,   mModel.mTauOn,   "s")
        ];

        // Seed from current (possibly RESTORED) state so the session-total kJ fields
        // resume from the running total rather than restarting at 0 after a reload.
        mFPcrJ.setData(mModel.mRP);
        mFGlyJ.setData(mModel.mRG);
        mFPcrCons.setData(0);
        mFGlyCons.setData(0);
        mFPcrKj.setData(mModel.mDepP / 1000.0);
        mFGlyKj.setData(mModel.mDepG / 1000.0);
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
        var cp      = propFloat("CP", 250.0);
        var wprime  = propFloat("Wprime", 20000.0);
        var fP      = propFloat("fP", 0.25);
        var pPmax   = propFloat("pPmax", 300.0);
        var tauP    = propFloat("tauP", 22.0);
        var tauG    = propFloat("tauG", 360.0);
        var lt1Frac = propFloat("lt1Frac", 0.80);
        var eta     = propFloat("eta", 0.80);
        var fatK    = propFloat("fatK", 0.75);
        var gFat    = propFloat("gFat", 0.0);
        var tauAer  = propFloat("tauAer", 25.0);
        var tauOn   = propFloat("tauOn", 6.0);

        if (cp < 1.0)     { cp = 1.0; }
        if (wprime < 1.0) { wprime = 1.0; }
        if (fP < 0.0)     { fP = 0.0; }
        if (fP > 1.0)     { fP = 1.0; }
        if (tauP < 1.0)   { tauP = 1.0; }
        if (tauG < 1.0)   { tauG = 1.0; }
        if (fatK < 0.0)   { fatK = 0.0; }
        if (gFat < 0.0)   { gFat = 0.0; }
        if (tauAer < 0.0) { tauAer = 0.0; }
        if (tauOn < 0.0)  { tauOn = 0.0; }

        // Capacity derivation + reserve re-clamp live in the model now.
        mModel.configure([cp, wprime, fP, pPmax, tauP, tauG, lt1Frac, eta, fatK, gFat, tauAer, tauOn]);
    }

    // Fresh-ride initialization: full tanks, zeroed session totals.
    hidden function resetSession() {
        mModel.resetTanks();
        // Re-baseline the dropout bridge/freeze state (#22) for the fresh session. These are
        // VIEW members, not model state, so resetTanks() cannot clear them — miss this and
        // mHaveValidP survives an onTimerReset, letting a post-reset dropout bridge on stale
        // power instead of freezing. (Not caught by the compile gate — must be seeded here.)
        mLastP = 0.0;
        mMissCount = 0;
        mHaveValidP = false;
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
        mSavRP = mModel.mRP;
        mSavRG = mModel.mRG;
        mSavDepP = mModel.mDepP;
        mSavDepG = mModel.mDepG;
        mSavDeficit = mModel.mDeficit;
    }

    hidden function absf(x) {
        return (x < 0.0) ? -x : x;
    }

    // Pure acceptance gate for a persisted snapshot, extracted so the persistence rules
    // can be exercised from a (:test) with no Storage/Activity context. Returns true only
    // when the blob is a well-formed, current-version, started, non-stale snapshot that
    // belongs to the currently recording activity. Callers pass the wall clock (nowSec)
    // and the live activity identity (liveSess) in — this touches no Storage/Activity/model
    // state, so it is deterministic given its arguments.
    static function validateBlob(blob, nowSec, liveSess) {
        if (!(blob instanceof Lang.Array))       { return false; }
        if (blob.size() != STATE_LEN)            { return false; }
        if (blob[SLOT_VERSION] != STATE_VERSION) { return false; }
        var savedAt   = blob[SLOT_SAVEDAT];
        var savedSess = blob[SLOT_SESS];
        var started   = blob[SLOT_STARTED];
        if (started != true)                            { return false; }  // never ran -> don't restore
        if ((nowSec - savedAt) > MAX_RESTORE_AGE_SEC)   { return false; }  // stale (secondary guard)
        // Activity-identity gate (PRIMARY guard): both ids must be known and equal.
        if (savedSess == null || liveSess == null || savedSess != liveSess) { return false; }
        return true;
    }

    // Restore a persisted snapshot into the model state. Returns true only on an
    // accepted restore; on a missing/corrupt/stale/pre-start blob (or any exception)
    // returns false so initialize() falls back to full-tank defaults. Any partial
    // assignment before a thrown error is harmless: the default block overwrites every
    // persisted field.
    hidden function restoreState() {
        try {
            var blob = Application.Storage.getValue(STATE_KEY);
            // Activity-identity gate (PRIMARY guard) + version/size/started/staleness checks
            // are the pure validateBlob() seam. Only resume a snapshot that belongs to the
            // currently recording activity: a previous ride the user never reset would
            // otherwise bleed into a new one inside the staleness window (restored
            // mStarted=true makes onTimerStart take the resume branch and skip resetSession(),
            // so the new ride runs on the old depleted tanks). Fails safe to full tanks when
            // the activity can't be identified.
            if (!validateBlob(blob, nowSec(), sessIdNow())) { return false; }

            mModel.mRP      = blob[SLOT_RP];
            mModel.mRG      = blob[SLOT_RG];
            mModel.mDepP    = blob[SLOT_DEPP];
            mModel.mDepG    = blob[SLOT_DEPG];
            mModel.mAer     = blob[SLOT_AER];
            mModel.mG       = blob[SLOT_G];
            mModel.mDeficit = blob[SLOT_DEFICIT];
            mPaused  = blob[SLOT_PAUSED];
            mPauseAt = blob[SLOT_PAUSEAT];
            mStarted = blob[SLOT_STARTED];

            // Re-clamp reserves to current capacities in case settings (CP/W'/fP)
            // changed between sessions.
            mModel.clampReserves();

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

    // Persist the model state. Coalesced: writes only when dirty, so it drops to zero
    // writes on steady full-tank riding and to at most one per SAVE_EVERY_SEC while a
    // depleted tank is actively recovering (genuine >= STATE_EPS_J changes). Public so
    // DualTankApp.onStop can force a final flush. Resets the throttle/dirty bookkeeping on
    // a successful write so a following periodic compute() write isn't double-fired.
    function saveState() {
        if (!mDirty) { return; }
        try {
            var blob = new [STATE_LEN];   // indexed via SLOT_* so writer/reader can't desync
            blob[SLOT_VERSION] = STATE_VERSION;
            blob[SLOT_SAVEDAT] = nowSec();
            blob[SLOT_SESS]    = sessIdNow();
            blob[SLOT_RP]      = mModel.mRP;
            blob[SLOT_RG]      = mModel.mRG;
            blob[SLOT_DEPP]    = mModel.mDepP;
            blob[SLOT_DEPG]    = mModel.mDepG;
            blob[SLOT_AER]     = mModel.mAer;
            blob[SLOT_G]       = mModel.mG;
            blob[SLOT_DEFICIT] = mModel.mDeficit;
            blob[SLOT_PAUSED]  = mPaused;
            blob[SLOT_PAUSEAT] = mPauseAt;
            blob[SLOT_STARTED] = mStarted;
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
            mModel.applyRestRecovery(el);
            mModel.mAer = 0.0;         // aerobic supply has decayed to rest during the pause
            mModel.mG = 0.0;           // glycolytic activation has relaxed during the pause
            mModel.mDeficit = 0.0;     // debt repaid over the pause
            mPaused = false;
            mDirty = true;
        }
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
            mModel.mConsP = 0.0;
            mModel.mConsG = 0.0;
            mFPcrJ.setData(mModel.mRP);
            mFGlyJ.setData(mModel.mRG);
            mFPcrCons.setData(0);
            mFGlyCons.setData(0);
            return 100.0 * mModel.mRP / mModel.mCapP;
        }

        // #22: distinguish a MISSING power sample (info null or currentPower null — an
        // ANT+/BLE dropout) from a valid 0 W coast. A missing sample must never collapse to
        // p=0.0 and trip the model's restoration branch (gateP=(mCP-0)/mCP=1.0 -> phantom PCr/
        // GLY/deficit recovery), and post-#47 that phantom value must not reach the snapshot.
        // Bridge-then-freeze: reuse the last VALID power for up to BRIDGE_SEC seconds, then
        // freeze (hold reserves) — but never bridge before a valid sample has been seen.
        var cp = null;
        if (info != null) {
            cp = info.currentPower;   // Number or null
        }
        var p;
        if (cp != null) {
            p = cp.toFloat();
            mLastP = p;
            mMissCount = 0;
            mHaveValidP = true;
        } else {
            mMissCount += 1;
            // Freeze if no valid sample yet (cold start OR first sample after a depleted-tank
            // restore — bridging at the 0.0 seed would inject phantom recovery), or once the
            // dropout outlasts the bridge window. Mirror the paused early-return (502-510):
            // hold reserves, zero consumption, keep the FIT streams gap-free, DON'T set mDirty
            // (so no snapshot is written) and DON'T touch mAer/mG/mDeficit (don't relax effort).
            if (!mHaveValidP || mMissCount > BRIDGE_SEC) {
                mModel.mConsP = 0.0;
                mModel.mConsG = 0.0;
                mFPcrJ.setData(mModel.mRP);
                mFGlyJ.setData(mModel.mRG);
                mFPcrCons.setData(0);
                mFGlyCons.setData(0);
                return 100.0 * mModel.mRP / mModel.mCapP;
            }
            p = mLastP;   // bridge: reuse last valid power, fall through to normal compute
        }

        // Delegate the entire per-second physics step to the model (pure, testable).
        var pctP = mModel.stepModel(p);

        // FIT: per-second reserve streams (joules remaining) + live consumption
        mFPcrJ.setData(mModel.mRP);
        mFGlyJ.setData(mModel.mRG);
        mFPcrCons.setData(mModel.mConsP.toNumber());
        mFGlyCons.setData(mModel.mConsG.toNumber());
        // FIT: running session totals (kJ) — SDK keeps last value as summary
        mFPcrKj.setData(mModel.mDepP / 1000.0);
        mFGlyKj.setData(mModel.mDepG / 1000.0);

        // Epsilon dirty-check: flag dirty only on a MATERIAL change (>= STATE_EPS_J in any
        // reserve / session total / deficit) since the last save. Without this, the sub-CP
        // restoration branch drifts mRG/mDeficit by a fraction of a joule every second and
        // keeps the field permanently dirty on any ride that ever used the glycolytic tank.
        // (Pause/resume/start still set mDirty explicitly — those aren't reserve changes.)
        if (!mDirty) {
            if (absf(mModel.mRP - mSavRP) >= STATE_EPS_J ||
                absf(mModel.mRG - mSavRG) >= STATE_EPS_J ||
                absf(mModel.mDepP - mSavDepP) >= STATE_EPS_J ||
                absf(mModel.mDepG - mSavDepG) >= STATE_EPS_J ||
                absf(mModel.mDeficit - mSavDeficit) >= STATE_EPS_J) {
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

        if (mModel.mCP <= 0.0 || mModel.mWprime <= 0.0) {
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2, mFontValue, "SET CP/W'",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var pctP = 100.0 * mModel.mRP / mModel.mCapP;
        var pctG = 100.0 * mModel.mRG / mModel.mCapG;

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
        var fillG = mModel.mRG / mModel.mCapG;
        if (fillG < 0.0) { fillG = 0.0; }
        if (fillG > 1.0) { fillG = 1.0; }
        var f = mModel.mFatK * (1.0 - fillG) * 100.0;
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
            "PCr " + (mModel.mDepP / 1000.0).format("%.1f"), ctr);
        dc.drawText(half + half / 2, yKj, mFontValue,
            "GLY " + (mModel.mDepG / 1000.0).format("%.1f"), ctr);
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
        var draining = isPcr ? (mModel.mConsP > 0.0) : (mModel.mConsG > 0.0);
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
            var wtxt = "-" + (isPcr ? mModel.mConsP : mModel.mConsG).toNumber().toString() + "W";
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
        var draining = isPcr ? (mModel.mConsP > 0.0) : (mModel.mConsG > 0.0);
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
            var wtxt = "-" + (isPcr ? mModel.mConsP : mModel.mConsG).toNumber().toString() + "W";
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + bw / 2, y + 2, mFontSmall, wtxt, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}
