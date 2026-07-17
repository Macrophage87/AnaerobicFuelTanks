using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Activity;
using Toybox.Application;
using Toybox.FitContributor;
using Toybox.Math;
using Toybox.Time;
using Toybox.Lang;
using Toybox.System;

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
//     banked as a deficit D, REPORTED as a separate third quantity (the Deficit_kJ FIT
//     stream) and NOT re-drained from the tanks (white paper §4.3/§6.9) — so the COMBINED
//     readout (Rp + Rg - D) stays energy-conserving, while the two bars may read slightly full.
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
// #52: while reserves are BELOW full, force a save at least this often even without a
// material (>=STATE_EPS_J) change, so the persisted SLOT_SAVEDAT stays a fresh "last active"
// marker. An unpaused reboot's off-gap recovery credit subtracts this window, so it can never
// credit rest for on-device sub-epsilon minutes. Skipped at full tanks -> #21's zero-write
// steady full-tank riding is preserved (a full tank has nothing to over-credit).
const IDLE_SAVE_SEC = 60;
// #51: max compute() ticks to wait for the activity identity to resolve before a TENTATIVE
// restore (identity null at initialize) fails safe to full tanks — bounds the window in which
// an unconfirmable foreign snapshot could otherwise run as the current ride.
const RESTORE_CONFIRM_TICKS = 8;
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
// #57: pure dropout-decision outcomes, so decideDropout() can be exercised from a (:test) with
// no DataField/Activity context (mirrors the validateBlob()/shouldShowNoPower() seams).
const DROPOUT_USE    = 0;   // valid sample: use it, reset the miss counter, arm mHaveValidP
const DROPOUT_BRIDGE = 1;   // missing sample within the bridge window: reuse mLastP
const DROPOUT_FREEZE = 2;   // no valid sample yet, or dropout outlasted BRIDGE_SEC: hold reserves
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

    // #32: banked deficit D as kJ — the "third quantity" the white paper (§4.3/§6.9) prescribes:
    // work booked to neither tank, decayed on recovery, REPORTED (not re-drained). Highest FID,
    // and created LAST, so if the FIT field budget is exhausted (#34) it's this OPTIONAL field's
    // handle that comes back null and degrades — never a core reserve/config stream.
    const FID_DEFICIT_KJ  = 18;

    // Guard: cap a single pause's recovery to 24 h of rest (clock-change safety).
    const MAX_PAUSE_SEC = 86400;


    // ---- Physiology model (settings + derived capacities + reserve/deficit state +
    //      the per-second physics step). All numeric model concerns live here; the view
    //      delegates to it and keeps only DataField / FIT / rendering / persistence /
    //      lifecycle. Constructed in initialize() before reloadSettings(). ----
    hidden var mModel;
    hidden var mFlashOn;
    hidden var mTimerOn;        // #36: cached live Activity.timerState==ON, refreshed each compute();
                               // drives the pre-start freeze + NO POWER hint. Transient, never serialized.
    hidden var mStarted;
    hidden var mConfigured;     // #42: true once CP AND W' are both provided (>0) via settings;
                                // drives the reachable "SET CP/W'" guard in onUpdate()
    hidden var mPaused;         // timer paused/stopped
    hidden var mPauseAt;        // unix seconds (WALL clock) when the pause began
    hidden var mPauseAtMono;    // #41: System.getTimer() ms at pause start; -1 when not set this
                                // process (e.g. a restore across reboot -> use the wall-clock delta).
                                // MONOTONIC, immune to clock jumps; NEVER serialized.
    // ---- Deferred-restore identity confirm (#51; transient, NEVER serialized) ----
    hidden var mRestorePending; // true when a snapshot was TENTATIVELY restored because the live
                                // activity id was null at initialize(); confirmed/rolled back in compute()
    hidden var mRestoreSess;    // the tentatively-restored snapshot's SLOT_SESS, to confirm identity against
    hidden var mRestoreTicks;   // compute() ticks spent pending; fail safe to full tanks past RESTORE_CONFIRM_TICKS
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
    hidden var mFDeficit;   // #32: Deficit_kJ record stream (optional; created last)
    hidden var mLastTimerTime;   // #31: previous info.timerTime (ms) for the real-dt step; null until first tick
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
        // #41/#51 transient bookkeeping — seed BEFORE restoreState() so a tentative restore can
        // set mRestorePending/mRestoreSess and the "always reset" block below won't clobber them.
        mPauseAtMono = -1;
        mRestorePending = false;
        mRestoreSess = null;
        mRestoreTicks = 0;

        // Restore a mid-ride snapshot if one exists and is valid; otherwise fall back to
        // full-tank defaults. restoreState() REPLACES the default block (it doesn't run
        // after it) so an accepted restore isn't clobbered by the defaults.
        if (!restoreState()) {
            resetToFullTanks();
        }
        // Derived / live / visual state is always reset regardless of which path ran —
        // it is recomputed each second and is never persisted.
        mModel.mConsP = 0.0;
        mModel.mConsG = 0.0;
        // Dropout bridge/freeze state (#22). mHaveValidP=false on EVERY path (fresh or
        // restored) so a missing sample before the first valid reading — including right
        // after a depleted-tank restore — freezes rather than bridging at the 0.0 seed.
        mLastP = 0.0;
        mMissCount = 0;
        mHaveValidP = false;
        mFlashOn = false;
        // #36: seed false so onUpdate()'s NO POWER gate is null-safe on the first frame (before the
        // first compute() has cached the live timerState). A field starts pre-start / not recording.
        mTimerOn = false;
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

        // Config parameters -> FIT session message. Created ONCE here (a field can't be created
        // twice); the values are written by writeCfgFields() and RE-written on any live settings
        // change (#33), so the recorded config reflects the end-of-ride effective settings, not the
        // init-time snapshot. Field names match the settings keys.
        mCfgFields = [
            cfgField("CP",      FID_CFG_CP,      "W"),
            cfgField("Wprime",  FID_CFG_WPRIME,  "J"),
            cfgField("fP",      FID_CFG_FP,      null),
            cfgField("pPmax",   FID_CFG_PPMAX,   "W"),
            cfgField("tauP",    FID_CFG_TAUP,    "s"),
            cfgField("tauG",    FID_CFG_TAUG,    "s"),
            cfgField("lt1Frac", FID_CFG_LT1FRAC, null),
            cfgField("eta",     FID_CFG_ETA,     null),
            cfgField("fatK",    FID_CFG_FATK,    null),
            cfgField("gFat",    FID_CFG_GFAT,    null),
            cfgField("tauAer",  FID_CFG_TAUAER,  "s"),
            cfgField("tauOn",   FID_CFG_TAUON,   "s")
        ];
        writeCfgFields();   // #33: initial write now that the fields exist (reloadSettings ran earlier)

        // #32: create the optional Deficit_kJ record stream LAST (highest FID), so on FIT-field
        // budget exhaustion (#34) it's this handle that comes back null and degrades — never a core
        // field. Per-second kJ (mDeficit is J); written every compute() so the stream has no gaps.
        mFDeficit = createField("Deficit_kJ", FID_DEFICIT_KJ, FitContributor.DATA_TYPE_FLOAT,
            { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "kJ" });

        // Seed from current (possibly RESTORED) state so the session-total kJ fields
        // resume from the running total rather than restarting at 0 after a reload.
        // All writes go through writeField (#34) so a null handle can't fault init.
        writeField(mFPcrJ, mModel.mRP);
        writeField(mFGlyJ, mModel.mRG);
        writeField(mFPcrCons, 0);
        writeField(mFGlyCons, 0);
        writeField(mFPcrKj, mModel.mDepP / 1000.0);
        writeField(mFGlyKj, mModel.mDepG / 1000.0);
        writeField(mFDeficit, mModel.mDeficit / 1000.0);   // #32: seed the deficit stream
    }

    // #34: createField() returns null when the FIT field budget/memory is exhausted; a bare
    // handle.setData() then throws and can take down compute()/onTimerStart/initialize. Route
    // EVERY write through this null-safe helper so a null handle just skips (that one field
    // doesn't record) instead of faulting — each field is guarded independently, so partial
    // recording survives. value may be a Float or an Int; both are valid setData payloads.
    // Static (no instance state) so a (:test) can exercise the null path without a DataField.
    static function writeField(f, value) {
        if (f != null) { f.setData(value); }
    }

    // #33: (re)write the 12 config SESSION fields from the CURRENT model values. Split from
    // creation (cfgField, once in initialize()) so a live onSettingsChanged -> reloadSettings()
    // keeps the recorded config in sync instead of reporting the init-time snapshot. SESSION
    // fields keep only their final value, so re-writing is cheap and the saved config reflects
    // the end-of-ride effective settings. Guarded because reloadSettings() runs from initialize()
    // BEFORE the fields exist. Index order matches the mCfgFields build below.
    hidden function writeCfgFields() {
        if (mCfgFields == null) { return; }
        writeField(mCfgFields[0],  mModel.mCP);
        writeField(mCfgFields[1],  mModel.mWprime);
        writeField(mCfgFields[2],  mModel.mFP);
        writeField(mCfgFields[3],  mModel.mPPmax);
        writeField(mCfgFields[4],  mModel.mTauP);
        writeField(mCfgFields[5],  mModel.mTauG);
        writeField(mCfgFields[6],  mModel.mLt1Frac);
        writeField(mCfgFields[7],  mModel.mEta);
        writeField(mCfgFields[8],  mModel.mFatK);
        writeField(mCfgFields[9],  mModel.mGFat);
        writeField(mCfgFields[10], mModel.mTauAer);
        writeField(mCfgFields[11], mModel.mTauOn);
    }

    // #33/#34: create (only) a SESSION field for a config parameter; the value is written
    // separately by writeCfgFields() so it can be re-emitted on live settings changes. A field
    // must be created exactly once (creating twice is invalid), so this stays in initialize().
    // units may be null for dimensionless parameters (fP, eta, ...).
    hidden function cfgField(name, id, units) {
        var opts = { :mesgType => FitContributor.MESG_TYPE_SESSION };
        if (units != null) { opts[:units] = units; }
        return createField(name, id, FitContributor.DATA_TYPE_FLOAT, opts);
    }

    // #64: coerce a settings value to a FINITE Float, or null if it is null / non-numeric /
    // non-finite (NaN or ±Inf). This is the single settings choke point: a NaN would otherwise
    // pass every comparison clamp in reloadSettings() (NaN < lo and NaN > hi are both false) and
    // reach mModel.configure(...), propagating into reserves, pctP and the FIT streams. Static and
    // pure (no Properties, no members) so it is unit-testable directly. NaN is caught with f != f;
    // ±Inf with a FINITE SENTINEL — the f/f != f/f idiom would misfire on a legitimate 0.0
    // (0/0 = NaN) and reject it, so it is deliberately NOT used. Number/Long can't be non-finite.
    static function coerceFiniteFloat(v) {
        var f;
        if (v instanceof Lang.Float)       { f = v; }
        else if (v instanceof Lang.Double) { f = v.toFloat(); }
        else if (v instanceof Lang.Number) { return v.toFloat(); }
        else if (v instanceof Lang.Long)   { return v.toFloat(); }
        else { return null; }
        if (f != f) { return null; }                     // NaN
        if (f > 3.4e38 || f < -3.4e38) { return null; }  // ±Inf (beyond finite 32-bit float range)
        return f;
    }

    // #42: like propFloat but returns null when the key is unset / non-numeric / non-finite, so
    // reloadSettings() can tell "the user actually provided CP/W'" from "defaulted" — the numeric
    // clamps force CP,W' >= 1 and propFloat substitutes defaults, which is exactly why the old
    // mCP<=0 SET CP/W' guard was unreachable (#42).
    hidden function propFloatOrNull(key) {
        return coerceFiniteFloat(Application.Properties.getValue(key));
    }

    hidden function propFloat(key, dflt) {
        var f = propFloatOrNull(key);
        return (f == null) ? dflt : f;
    }

    // #42: true only when the rider has actually PROVIDED both CP and W' — present, finite, and > 0.
    // Static + pure so the mConfigured==false case is unit-testable without device Properties. Treats
    // BOTH null (unset key, once properties.xml drops the defaults) AND a present <=0 as not-provided,
    // so the guard is correct whether the SDK returns null or 0 for an unset property. A present
    // below-floor value (e.g. CP=0.5) still counts as provided; the reloadSettings() clamps then keep
    // the mCapP/mCapG denominators safe.
    static function isConfigured(rawCP, rawWprime) {
        return (rawCP != null && rawCP > 0.0 && rawWprime != null && rawWprime > 0.0);
    }

    // Public so the app can push live settings changes.
    function reloadSettings() {
        // #42: CP and W' via the null-returning form so we can tell "provided" from "defaulted".
        // properties.xml defaults these two to the sentinel 0 (numeric properties require a default),
        // so an unconfigured rider reads 0 -> isConfigured() is false and the "SET CP/W'" guard shows
        // (the former 250/20000 defaults made it always-configured and the guard dead). A 0/unset
        // (or null) value maps to the model's safe 250/20000 fallback so the FIT streams stay sane
        // while unconfigured; #64 already dropped any NaN/±Inf to null upstream.
        var rawCP     = propFloatOrNull("CP");
        var rawWprime = propFloatOrNull("Wprime");
        mConfigured   = isConfigured(rawCP, rawWprime);
        var cp      = (rawCP == null     || rawCP <= 0.0)     ? 250.0   : rawCP;
        var wprime  = (rawWprime == null || rawWprime <= 0.0) ? 20000.0 : rawWprime;
        var fP      = propFloat("fP", 0.25);
        var pPmax   = propFloat("pPmax", 300.0);
        var tauP    = propFloat("tauP", 27.0);
        var tauG    = propFloat("tauG", 470.0);
        var lt1Frac = propFloat("lt1Frac", 0.80);
        var eta     = propFloat("eta", 1.00);
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
        // pPmax / lt1Frac / eta are bounded by the settings UI but were never clamped in
        // code (#23) — a defensive floor/ceiling against corrupt storage or sideloaded
        // properties. pPmax: strictly-positive flux ceiling, upper bound mirrors the UI max
        // (1500 W) so a corrupt value can't push mConsP past the SINT16 PCr_cons stream
        // (#35). lt1Frac >= 0.05 keeps lt1Frac*CP strictly positive so the recovery anchor
        // (mLt1Frac*mCP - 20)/(mLt1Frac*mCP) in stepModel()/applyRestRecovery() can't divide
        // by zero; <= 1.0 since LT1 cannot exceed CP. eta is a recovery-efficiency fraction
        // [0,1] — eta < 0 would drain PCr in the live restoration branch while P < CP.
        if (pPmax < 1.0)    { pPmax = 1.0; }
        if (pPmax > 1500.0) { pPmax = 1500.0; }
        if (lt1Frac < 0.05) { lt1Frac = 0.05; }
        if (lt1Frac > 1.0)  { lt1Frac = 1.0; }
        if (eta < 0.0)      { eta = 0.0; }
        if (eta > 1.0)      { eta = 1.0; }

        // Capacity derivation + reserve re-clamp live in the model now.
        mModel.configure([cp, wprime, fP, pPmax, tauP, tauG, lt1Frac, eta, fatK, gFat, tauAer, tauOn]);
        // #33: re-emit the config SESSION fields so a live settings change is reflected in the FIT
        // record. No-op while called from initialize() (fields not built yet; writeCfgFields guards).
        writeCfgFields();
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

    // Non-identity acceptance checks: everything validateBlob() gates EXCEPT the live-activity
    // id match — the blob is a well-formed, current-version, started, non-stale snapshot that
    // carries a KNOWN savedSess. Pure (no Storage/Activity). Used both by validateBlob() and by
    // restoreState()'s #51 tentative path (restore when liveSess is momentarily null, pending an
    // identity confirm).
    static function blobRestorable(blob, nowSec) {
        if (!(blob instanceof Lang.Array))              { return false; }
        if (blob.size() != STATE_LEN)                   { return false; }
        if (blob[SLOT_VERSION] != STATE_VERSION)        { return false; }
        if (blob[SLOT_STARTED] != true)                 { return false; }  // never ran -> don't restore
        if ((nowSec - blob[SLOT_SAVEDAT]) > MAX_RESTORE_AGE_SEC) { return false; }  // stale (secondary guard)
        if (blob[SLOT_SESS] == null)                    { return false; }  // saved id unknown
        return true;
    }

    // Pure acceptance gate for a persisted snapshot, extracted so the persistence rules
    // can be exercised from a (:test) with no Storage/Activity context. Returns true only
    // when the blob is well-formed/current/started/non-stale (blobRestorable) AND belongs to
    // the currently recording activity (identity known and equal). Callers pass the wall clock
    // (nowSec) and the live activity identity (liveSess) in — deterministic given its arguments.
    static function validateBlob(blob, nowSec, liveSess) {
        if (!blobRestorable(blob, nowSec)) { return false; }
        // Activity-identity gate (PRIMARY guard): the live id must be known and equal.
        if (liveSess == null || blob[SLOT_SESS] != liveSess) { return false; }
        return true;
    }

    // Fresh-ride full-tank defaults for initialize()'s no-restore path. (The #51 tentative-restore
    // rollback in compute() uses restoreRollback() instead — it must re-seed the dropout/derived
    // state and choose mStarted per its caller, which these bare field defaults do not.)
    hidden function resetToFullTanks() {
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

    // #51: a tentatively-restored snapshot did not confirm as this ride. Reset to FRESH full tanks
    // (resetSession() also re-seeds the dropout/derived state) and drop the stale blob. The two
    // callers need OPPOSITE mStarted, so it's a parameter — collapsing them (as an earlier revision
    // did) re-opens #36 on the deadline path:
    //   - startedAfter=true  — confirmed-foreign (identity RESOLVED to a different id): a ride is
    //     genuinely recording, so keep persistence alive for it. mStarted=false here would make
    //     blobRestorable()'s started!=true check reject every save for the rest of the ride.
    //   - startedAfter=false — deadline-exceeded (identity NEVER resolved within
    //     RESTORE_CONFIRM_TICKS): the usual cause is the timer hasn't actually started yet, so fail
    //     fully safe and let the real onTimerStart() run resetSession() at the true start. Leaving
    //     mStarted=true would make that onTimerStart() take the resume branch and skip the reset,
    //     carrying pre-start depletion into the ride (#36).
    hidden function restoreRollback(startedAfter) {
        resetSession();          // full tanks + reseeded mLastP/mMissCount/mHaveValidP
        mStarted = startedAfter;
        mPaused = false;
        mPauseAt = 0;
        mRestoreSess = null;
        clearState();            // drop the unconfirmed snapshot
    }

    // Restore a persisted snapshot into the model state. Returns true on an accepted OR a
    // TENTATIVE restore (#51: live activity id momentarily null); on a hard reject
    // (missing/corrupt/stale/pre-start blob, a known-mismatched id, or any exception) returns
    // false so initialize() falls back to full-tank defaults. Any partial assignment before a
    // thrown error is harmless: the default block overwrites every persisted field.
    hidden function restoreState() {
        try {
            var blob = Application.Storage.getValue(STATE_KEY);
            var now  = nowSec();
            var live = sessIdNow();

            // Only resume a snapshot that belongs to the currently recording activity (identity
            // gate) — a previous ride the user never reset would otherwise bleed into a new one
            // inside the staleness window. TWO accept paths:
            //   (a) identity known & matching -> committed restore;
            //   (b) #51: identity momentarily UNKNOWN at initialize() (getActivityInfo().startTime
            //       not yet populated on a mid-ride reboot) but the blob is otherwise restorable ->
            //       TENTATIVELY restore and confirm/roll-back in compute() once the id resolves.
            // A KNOWN-mismatched id, or a non-restorable blob, hard-rejects -> full tanks.
            var identityOk    = validateBlob(blob, now, live);
            var indeterminate = (live == null) && blobRestorable(blob, now);
            if (!identityOk && !indeterminate) { return false; }

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

            // #51: tentative restore — remember the snapshot's id and confirm it in compute().
            if (indeterminate) {
                mRestoreSess = blob[SLOT_SESS];
                mRestorePending = true;
            }

            // #52: an UNPAUSED reload/reboot (dead-battery crash mid-effort — the feature's
            // primary case) previously resumed at the pre-crash DEPLETED reserves with NO recovery
            // for the unrecorded off-gap. Credit the closed-form rest recovery for the gap the
            // device was DEMONSTRABLY OFF, using the persisted WALL-CLOCK save time (SLOT_SAVEDAT)
            // — the monotonic clock (#41) can't cross a reboot, so this path bounds itself.
            //
            // SAFETY (review-blocking fix): SLOT_SAVEDAT is the last SAVE, not the last active
            // instant, and saves are epsilon+throttle gated — but the IDLE_SAVE_SEC heartbeat in
            // compute() keeps it <= IDLE_SAVE_SEC stale WHILE depleted. So the device was provably
            // recording until at least savedAt, and possibly up to IDLE_SAVE_SEC longer. Crediting
            // only (now - savedAt - IDLE_SAVE_SEC) therefore NEVER over-credits rest (the earlier
            // now-savedAt form could phantom-refill minutes of on-device sub-epsilon grind). A short
            // reboot (< IDLE_SAVE_SEC off) credits ~0 (negligible); a long dead-battery off credits
            // nearly the whole gap. Bounded independently to [0, MAX_PAUSE_SEC].
            // Do NOT zero mAer/mG/mDeficit here (those effort-state resets belong to an intentional
            // pause via exitPause(), not a crash gap). NOTE: the closed-form applyRestRecovery omits
            // the live loop's mDeficit decay, so any banked deficit is carried across the gap
            // (conservative — errs toward LESS recovered). A PAUSED reload is unchanged (recovery
            // still flows through exitPause() on resume).
            if (mPaused != true) {
                var gap = (now - blob[SLOT_SAVEDAT]) - IDLE_SAVE_SEC;
                if (gap < 0) { gap = 0; }
                if (gap > MAX_PAUSE_SEC) { gap = MAX_PAUSE_SEC; }
                if (gap > 0) { mModel.applyRestRecovery(gap); }
            }
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
        // #51: never persist a TENTATIVELY-restored (identity-unconfirmed) snapshot. Otherwise
        // onTimerStart()'s immediate flush could stamp a FOREIGN ride's tanks under the NEW ride's
        // now-resolved id (a valid-looking but wrong snapshot). Saves resume once compute() confirms
        // or rolls back the pending restore (a few ticks at most).
        if (mRestorePending) { return; }
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
            mPauseAtMono = System.getTimer();   // #41: monotonic stamp (ms), immune to clock jumps
            mDirty = true;
        }
    }

    // On resume: recover the tanks for the WHOLE elapsed pause (closed form),
    // without having accumulated any depletion while paused.
    hidden function exitPause() {
        if (mPaused) {
            // #41: prefer the MONOTONIC elapsed-pause (System.getTimer, ms since boot) — immune to
            // GPS/DST/manual wall-clock corrections mid-pause. Fall back to the wall-clock delta when
            // the monotonic stamp isn't from this process (mPauseAtMono < 0, e.g. a restore across
            // reboot, where the pre-pause getTimer() epoch is gone) or reads out of range.
            var el = nowSec() - mPauseAt;                // wall-clock fallback
            if (el < 0) { el = 0; }
            if (mPauseAtMono >= 0) {
                var elMono = (System.getTimer() - mPauseAtMono) / 1000;
                if (elMono >= 0 && elMono <= MAX_PAUSE_SEC) { el = elMono; }
            }
            if (el > MAX_PAUSE_SEC) { el = MAX_PAUSE_SEC; }
            mModel.applyRestRecovery(el);
            mModel.mAer = 0.0;         // aerobic supply has decayed to rest during the pause
            mModel.mG = 0.0;           // glycolytic activation has relaxed during the pause
            mModel.mDeficit = 0.0;     // debt repaid over the pause
            // #58: reset the dropout-bridge guard so the first post-resume MISSING sample FREEZES
            // instead of bridging at pre-pause mLastP (which would over-deplete right after recovery
            // was credited). The paused early-return in compute() sits before the #22 dropout block,
            // so these otherwise carry pre-pause values across the pause. mLastP is intentionally
            // left as-is — it's moot: mHaveValidP=false forces the freeze branch before mLastP is read.
            mHaveValidP = false;
            mMissCount = 0;
            mPauseAtMono = -1;
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
        // A manual reset ends any tentative #51 restore outright (a fresh ride can't be confirming
        // a prior snapshot). These self-clear on the next resolved compute() tick, but clearing them
        // here keeps the fresh-ride state unambiguous and can't leave a stale pending-restore.
        mRestorePending = false;
        mRestoreTicks = 0;
        mRestoreSess = null;
        clearState();      // fresh ride -> drop the snapshot so the next activity starts full
    }

    function onLayout(dc) {
        mFontLabel = Graphics.FONT_XTINY;
        mFontValue = Graphics.FONT_TINY;
        mFontSmall = Graphics.FONT_XTINY;
    }

    // #52: keep SLOT_SAVEDAT a fresh "last-active" marker while the device is recording-and-depleted,
    // then persist it (throttled + dirty-gated, flash-wear safe). Called on the normal per-second
    // compute() path AND before its dropout-freeze early-return — a sustained sensor dropout is still
    // active on-device time (the activity timer runs; a paused ride returns earlier), so its
    // SLOT_SAVEDAT must not freeze, or a dropout-then-reboot would credit the frozen span as rest.
    // The IDLE_SAVE_SEC heartbeat fires only while below full: at capacity applyRestRecovery is a
    // no-op so there is nothing to over-credit, and #21's zero-write steady full-tank ride is kept.
    // Cost is bounded — at most ~one extra write per IDLE_SAVE_SEC (60 s) while depleted.
    hidden function markActiveIfDepleted() {
        if (!mDirty && (nowSec() - mLastSaveSec >= IDLE_SAVE_SEC)
                && (mModel.mRP < mModel.mCapP || mModel.mRG < mModel.mCapG || mModel.mDeficit > 0.0)) {
            mDirty = true;
        }
        if (mDirty && (nowSec() - mLastSaveSec >= SAVE_EVERY_SEC)) {
            saveState();
        }
    }

    //------------------------------------------------------------------
    // Model step — called once per second by the system.
    //------------------------------------------------------------------
    function compute(info) {
        // #36: cache the LIVE activity timer state for this tick (used by the pre-start freeze below
        // and onUpdate()'s NO POWER hint). Null-safe: an unknown info/timerState reads as "not on",
        // which fails safe to the frozen pre-start view. TIMER_STATE_ON is available on all targets.
        mTimerOn = (info != null && info.timerState == Activity.TIMER_STATE_ON);
        // #31: activity-timer time (ms) for this tick; drives the real elapsed dt at the step below.
        // Reseeded on every freeze/early-return so the first live step after a freeze isn't a giant gap.
        var tnow = (info != null) ? info.timerTime : null;

        // #51: if the restore was TENTATIVE (activity id was null at initialize()), confirm or
        // roll it back now that identity may be available. Runs before everything else so a
        // foreign snapshot can't accrue a second of depletion/recovery before being discarded.
        if (mRestorePending) {
            var liveNow = sessIdNow();
            if (liveNow != null) {
                mRestorePending = false;
                mRestoreTicks = 0;
                if (liveNow != mRestoreSess) {
                    // Foreign activity: the snapshot belongs to a DIFFERENT ride that IS recording
                    // -> start fresh but keep mStarted=true so persistence stays alive for it.
                    restoreRollback(true);
                }
                // else: identity confirmed -> keep the tentatively-restored state.
            } else {
                // Identity still unavailable: bound the wait so an UNCONFIRMABLE foreign snapshot
                // can't run as this ride indefinitely. Past the deadline the usual cause is the timer
                // hasn't started yet, so fail FULLY safe (mStarted=false) and let the real
                // onTimerStart() reset at the true start -> no pre-start depletion carried in (#36).
                mRestoreTicks += 1;
                if (mRestoreTicks > RESTORE_CONFIRM_TICKS) {
                    mRestorePending = false;
                    restoreRollback(false);
                }
            }
        }

        // While paused/stopped: freeze depletion (no accumulation). Recovery for
        // the pause is applied in one shot on resume (see exitPause()).
        if (mPaused) {
            mModel.mConsP = 0.0;
            mModel.mConsG = 0.0;
            writeField(mFPcrJ, mModel.mRP);
            writeField(mFGlyJ, mModel.mRG);
            writeField(mFPcrCons, 0);
            writeField(mFGlyCons, 0);
            writeField(mFDeficit, mModel.mDeficit / 1000.0);   // #32: gap-free deficit stream (held)
            if (tnow != null) { mLastTimerTime = tnow; }   // #31: reseed so post-resume dt isn't the whole pause
            return 100.0 * mModel.mRP / mModel.mCapP;
        }

        // #36: hold the tanks until the activity timer is actually running. Before the first start
        // (or after a stop), timerState != ON, so warm-up pedaling — or a data field added before the
        // start press — doesn't deplete from a wrong baseline. Derived from the LIVE timerState every
        // tick (mTimerOn), NOT a sticky flag, so it self-releases the instant recording begins: a
        // field added mid-ride or a mid-ride reboot (neither fires onTimerStart) is never stranded
        // frozen. HOLDS the current reserves (mirrors the paused / #22 dropout freeze); #67's
        // onTimerStart->resetSession still resets to full at the real start. A user pause is handled
        // by the mPaused branch above (which also credits recovery on resume), so it never reaches here.
        // Gated on info != null: a null-info tick is an ACTIVE-recording dropout to the #22/#52 code,
        // so it must fall through to the #22 handler below (which refreshes SLOT_SAVEDAT via
        // markActiveIfDepleted) — otherwise a null-info dropout on a depleted ride would freeze that
        // #52 heartbeat and a reboot could re-credit the frozen span as rest.
        if (info != null && !mTimerOn) {
            mModel.mConsP = 0.0;
            mModel.mConsG = 0.0;
            writeField(mFPcrJ, mModel.mRP);
            writeField(mFGlyJ, mModel.mRG);
            writeField(mFPcrCons, 0);
            writeField(mFGlyCons, 0);
            writeField(mFDeficit, mModel.mDeficit / 1000.0);   // #32: gap-free deficit stream (held)
            if (tnow != null) { mLastTimerTime = tnow; }   // #31: reseed so the first post-start dt is one tick
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
        // #57: the bridge/freeze DECISION is delegated to the pure decideDropout() seam; the state
        // mutations, effective-power selection, and the freeze early-return stay here so behavior is
        // byte-identical. On a missing sample mMissCount is incremented BEFORE decideDropout() so the
        // POST-increment value drives the `> BRIDGE_SEC` boundary exactly as the original inline code.
        if (cp != null) {
            p = cp.toFloat();                 // decideDropout(true, ...) == DROPOUT_USE
            mLastP = p;
            mMissCount = 0;
            mHaveValidP = true;
        } else {
            mMissCount += 1;
            if (decideDropout(false, mMissCount, mHaveValidP) == DROPOUT_FREEZE) {
                // Freeze — no valid sample yet (cold start OR first sample after a depleted-tank
                // restore, where bridging the 0.0 seed would inject phantom recovery), or the dropout
                // outlasted the bridge window. Mirror the paused early-return: hold reserves, zero
                // consumption, keep the FIT streams gap-free, and DON'T touch mAer/mG/mDeficit. This
                // IS active on-device time, so markActiveIfDepleted() still refreshes SLOT_SAVEDAT
                // while depleted so a multi-minute dropout can't be credited as rest (#52).
                mModel.mConsP = 0.0;
                mModel.mConsG = 0.0;
                writeField(mFPcrJ, mModel.mRP);
                writeField(mFGlyJ, mModel.mRG);
                writeField(mFPcrCons, 0);
                writeField(mFGlyCons, 0);
                writeField(mFDeficit, mModel.mDeficit / 1000.0);   // #32: gap-free deficit stream (held)
                if (tnow != null) { mLastTimerTime = tnow; }   // #31: reseed so post-dropout dt isn't the whole gap
                markActiveIfDepleted();
                return 100.0 * mModel.mRP / mModel.mCapP;
            }
            p = mLastP;   // DROPOUT_BRIDGE: reuse last valid power, fall through to normal compute
        }

        // #31: real elapsed timestep from the activity timer (ms), clamped to [0,5] s. First live
        // step / null timerTime -> dt = 1.0 (seed only). A non-positive delta (timer reset or a
        // duplicate compute() tick) -> dt = 0.0 and we SKIP the step: stepModel's mConsP = takeP/dt
        // would divide by zero, and a reset must never inject phantom joules. The [0,5] clamp absorbs
        // smart-recording / GPS-stall coalescing (a longer real gap is clamped here; the R calibration
        // tool warns on non-1 Hz files — #31 Part B). Compute dt from the PREVIOUS stamp, then reseed.
        var dt = 1.0;
        if (tnow != null && mLastTimerTime != null) {
            dt = (tnow - mLastTimerTime) / 1000.0;
            if (dt < 0.0) { dt = 0.0; }
            if (dt > 5.0) { dt = 5.0; }
        }
        if (tnow != null) { mLastTimerTime = tnow; }
        if (dt <= 0.0) {
            mModel.mConsP = 0.0;
            mModel.mConsG = 0.0;
            writeField(mFPcrJ, mModel.mRP);
            writeField(mFGlyJ, mModel.mRG);
            writeField(mFPcrCons, 0);
            writeField(mFGlyCons, 0);
            writeField(mFDeficit, mModel.mDeficit / 1000.0);   // #32: keep the deficit stream gap-free on a skipped tick
            return 100.0 * mModel.mRP / mModel.mCapP;
        }

        // Delegate the entire per-second physics step to the model (pure, testable).
        var pctP = mModel.stepModel(p, dt);

        // FIT: per-second reserve streams (joules remaining) + live consumption
        writeField(mFPcrJ, mModel.mRP);
        writeField(mFGlyJ, mModel.mRG);
        writeField(mFPcrCons, mModel.mConsP.toNumber());
        writeField(mFGlyCons, mModel.mConsG.toNumber());
        // FIT: running session totals (kJ) — SDK keeps last value as summary
        writeField(mFPcrKj, mModel.mDepP / 1000.0);
        writeField(mFGlyKj, mModel.mDepG / 1000.0);
        writeField(mFDeficit, mModel.mDeficit / 1000.0);   // #32: banked deficit D as a live kJ stream

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

        // #52 heartbeat + throttled, dirty-gated persist (flash-wear safe). Factored into
        // markActiveIfDepleted() so the dropout-freeze early-return above refreshes the same
        // "last-active" marker — otherwise a long depleted dropout freezes SLOT_SAVEDAT and a
        // reboot right after over-credits the frozen span as rest. Sits after the mPaused
        // early-return, so paused seconds don't write.
        markActiveIfDepleted();

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

    // #36: pure predicate for onUpdate()'s NO POWER hint — show only when the timer is running
    // (recording), not paused (covers the resume transient where timerState is briefly ON while
    // mPaused is still set), not in the #51 restore-confirm window, no valid power ever seen, and
    // past the #22 grace (so a cold start / 1-frame gap doesn't flash). Static + pure so the gate
    // logic is unit-testable without a DataField/Activity context.
    static function shouldShowNoPower(timerOn, paused, restorePending, haveValidP, missCount) {
        return timerOn && !paused && !restorePending && !haveValidP && missCount > BRIDGE_SEC;
    }

    // #57: pure bridge/freeze decision for a power sample (mirrors validateBlob/shouldShowNoPower —
    // no self/Activity context, deterministic given its args) so the #22 dropout boundaries are
    // (:test)-assertable without a live DataField. compute() keeps the state mutations, the
    // effective-power selection, and the freeze early-return; this returns ONLY the decision.
    // IMPORTANT: `missCount` is the POST-increment value — compute() does `mMissCount += 1` BEFORE
    // calling on a missing sample, so `missCount > BRIDGE_SEC` matches the original inline logic
    // exactly. Passing the pre-increment value would shift every boundary by one second.
    static function decideDropout(valid, missCount, haveValidP) {
        if (valid) { return DROPOUT_USE; }
        if (!haveValidP || missCount > BRIDGE_SEC) { return DROPOUT_FREEZE; }
        return DROPOUT_BRIDGE;
    }

    function onUpdate(dc) {
        var bg = getBackgroundColor();
        var fg = contrastColor(bg);
        dc.setColor(bg, bg);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        // #42: reachable now — mConfigured is false until the user actually provides CP AND W'
        // (the old mCP<=0/mWprime<=0 test was dead: reloadSettings() clamps both to >= 1). A
        // never-configured user sees the prompt instead of misleading full-looking tanks.
        if (!mConfigured) {
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2, mFontValue, "SET CP/W'",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        // #36: no power meter (or none seen yet) while recording -> tell the rider instead of showing
        // full-looking tanks forever. Keyed on the LIVE timerState (mTimerOn), NOT mStarted, so a field
        // added mid-ride (which never gets onTimerStart) also surfaces the hint. !mPaused covers the
        // resume transient (timerState briefly ON while mPaused is still set, before exitPause runs);
        // !mRestorePending the #51 confirm window; mMissCount > BRIDGE_SEC reuses the #22 grace so a
        // cold start or a 1-frame gap doesn't flash. A late-arriving sample latches mHaveValidP and
        // clears the hint. Sits AFTER the SET CP/W' guard (config prompt takes precedence).
        // #76 (unconfigured disposition): mConfigured is already true here; an unconfigured ride is
        // caught by the guard above. A configured ride with no power meter shows this instead.
        if (shouldShowNoPower(mTimerOn, mPaused, mRestorePending, mHaveValidP, mMissCount)) {
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2, mFontValue, "NO POWER",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var pctP = 100.0 * mModel.mRP / mModel.mCapP;
        var pctG = 100.0 * mModel.mRG / mModel.mCapG;

        // Round-display safety (#25): when THIS field fills a SQUARE round screen, inset the
        // vertical/full layouts to the largest inscribed square so tank tops/bottoms and the
        // PCr/GLY/percentage labels aren't clipped by the bezel. The inset is gated on the
        // field actually FILLING the screen (not merely on device shape) so round grid /
        // multi-field slots — the common case — are left untouched. For rectangular devices,
        // round grid slots, and null/unknown settings, the rect is (0,0,w,h) so every layout
        // is pixel-identical to before. Branch SELECTION below is unchanged (raw-pixel gates).
        var sx = 0;
        var sy = 0;
        var sw = w;
        var sh = h;
        var ds = System.getDeviceSettings();
        if (ds != null && w == h) {
            var round = false;
            if (ds.screenShape != null) {
                round = (ds.screenShape == System.SCREEN_SHAPE_ROUND
                      || ds.screenShape == System.SCREEN_SHAPE_SEMI_ROUND);
            }
            var fills = false;
            if (ds.screenWidth != null && ds.screenHeight != null) {
                fills = (w >= ds.screenWidth - 2 && h >= ds.screenHeight - 2);
            }
            if (round && fills) {
                // m = ceil((1 - 1/sqrt(2))/2 * d) as pure integer math (d == w == h). The
                // largest axis-aligned square inscribed in the disc; ceil keeps every corner
                // strictly inside the circle (a floor would leave corners a sub-pixel out).
                var m = (293 * w + 1999) / 2000;
                sx = m;
                sy = m;
                sw = w - 2 * m;
                sh = h - 2 * m;
            }
        }

        // VERTICAL tanks are the standard look on most layouts; only a genuinely short
        // strip (too short for a legible vertical bar) falls back to horizontal bars:
        //   large single field (w>=200, h>=240): vertical tanks on top + summary stats
        //   any field tall enough (h>=74): two VERTICAL tanks side by side  <-- default
        //   short & wide strip (w>=2h): two HORIZONTAL bars side by side
        //   short strip: two HORIZONTAL bars stacked
        // Selection keys on raw w/h (unchanged); drawFull/drawVertical render within the
        // safe rect (sx,sy,sw,sh), which equals (0,0,w,h) except on a full-screen round field.
        if (w >= 200 && h >= 240) {
            drawFull(dc, sx, sy, sw, sh, fg, pctP, pctG);
        } else if (h >= 74) {
            drawVertical(dc, sx, sy, sw, sh, fg, pctP, pctG);
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
    hidden function drawVertical(dc, sx, sy, sw, sh, fg, pctP, pctG) {
        drawVerticalIn(dc, sx, sy, sw, sh, fg, pctP, pctG);
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
    hidden function drawFull(dc, sx, sy, sw, sh, fg, pctP, pctG) {
        var topH = sy + sh * 3 / 5;           // ~60% for the two tanks (within the safe rect)
        drawVerticalIn(dc, sx, sy, sw, topH - sy, fg, pctP, pctG);

        // divider
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(sx + 6, topH, sx + sw - 6, topH);

        // distribute the three stat rows across the panel below the divider. half == w/2
        // (the safe rect is centered), so on the rectangular path (sx=sy=0, sw=w, sh=h)
        // every expression below is byte-identical to the original w/2 / half/2 / half+half/2.
        var half = sx + sw / 2;
        var avail = (sy + sh) - topH;
        var yHdr = topH + avail * 16 / 100;
        var yKj  = topH + avail * 46 / 100;
        var yFat = topH + avail * 78 / 100;
        var ctr = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.drawText(half, yHdr, mFontSmall, "DEPLETED (kJ)", ctr);
        dc.drawText(half / 2, yKj, mFontValue,
            "PCr " + (mModel.mDepP / 1000.0).format("%.1f"), ctr);
        dc.drawText(half + half / 2, yKj, mFontValue,
            "GLY " + (mModel.mDepG / 1000.0).format("%.1f"), ctr);
        dc.drawText(half, yFat, mFontValue,
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
