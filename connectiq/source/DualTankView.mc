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
//     in. PCr is the higher-power system (peak rate pPmax > glycolytic peak gPmax);
//     demand is split in proportion to available rate, both tanks rate-capped.
//   - Below supply: PCr recovers (tauP, efficiency eta); glycolytic recovers
//     slowly (tauG) and only below LT1 (lt1Frac * CP).
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
// RENDERING: the layout adapts to the field's aspect ratio —
//   very wide (w >= 3h): two HORIZONTAL bars SIDE BY SIDE (half width each);
//   wide/short (1.5h <= w < 3h): two HORIZONTAL bars STACKED;
//   large portrait single field (w>=200 & h>=240): VERTICAL tanks on top + a summary
//     panel below (per-system depleted kJ and a fatigue level);
//   otherwise square/tall (e.g. a 1x2 cell): two VERTICAL bars SIDE BY SIDE.
//   Foreground color adapts to background luminance, so it reads on light and dark themes.
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
    const FID_PCR_PCT  = 0;
    const FID_GLY_PCT  = 1;
    const FID_PCR_CONS = 2;
    const FID_GLY_CONS = 3;
    const FID_PCR_KJ   = 4;
    const FID_GLY_KJ   = 5;

    // Guard: cap a single pause's recovery to 24 h of rest (clock-change safety).
    const MAX_PAUSE_SEC = 86400;
    // Aerobic off-kinetics are slower than on-kinetics -> a "sticky" aerobic supply
    // so brief eases/coasts don't force a re-ramp. Off tau = tauAer * AER_FALL.
    const AER_FALL = 6.0;
    // Glycolytic peak rate as a fraction of PCr peak rate. PCr is the higher-power
    // system, so glycolysis is rate-capped below it (a modeling assumption; ~0.5).
    const GLY_RATE_FRAC = 0.5;

    // ---- Settings ----
    hidden var mCP, mWprime, mFP, mPPmax, mTauP, mTauG, mLt1Frac, mEta;
    hidden var mFatK;    // PCr recovery fatigue-slowing coefficient (0 = disabled)
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
    hidden var mExhausted;
    hidden var mFlashOn;
    hidden var mStarted;
    hidden var mPaused;         // timer paused/stopped
    hidden var mPauseAt;        // unix seconds when the pause began
    // ---- FIT fields ----
    hidden var mFPcrPct, mFGlyPct, mFPcrCons, mFGlyCons, mFPcrKj, mFGlyKj;
    // ---- Draw resources ----
    hidden var mFontLabel, mFontValue, mFontSmall;

    function initialize() {
        DataField.initialize();
        reloadSettings();

        mRP = mCapP;
        mRG = mCapG;
        mDepP = 0.0;
        mDepG = 0.0;
        mConsP = 0.0;
        mConsG = 0.0;
        mAer = 0.0;
        mG = 0.0;
        mExhausted = false;
        mFlashOn = false;
        mStarted = false;
        mPaused = false;
        mPauseAt = 0;

        // Fonts (also set in onLayout; initialized here so onUpdate is always safe).
        mFontLabel = Graphics.FONT_XTINY;
        mFontValue = Graphics.FONT_TINY;
        mFontSmall = Graphics.FONT_XTINY;

        // Per-second record streams
        mFPcrPct  = createField("PCr_pct",  FID_PCR_PCT,  FitContributor.DATA_TYPE_FLOAT,
            { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "%" });
        mFGlyPct  = createField("GLY_pct",  FID_GLY_PCT,  FitContributor.DATA_TYPE_FLOAT,
            { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "%" });
        mFPcrCons = createField("PCr_cons", FID_PCR_CONS, FitContributor.DATA_TYPE_SINT16,
            { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "W" });
        mFGlyCons = createField("GLY_cons", FID_GLY_CONS, FitContributor.DATA_TYPE_SINT16,
            { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "W" });
        // Session totals (kJ) — finalized at ride save
        mFPcrKj   = createField("PCr_depleted_kJ", FID_PCR_KJ, FitContributor.DATA_TYPE_FLOAT,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "kJ" });
        mFGlyKj   = createField("GLY_depleted_kJ", FID_GLY_KJ, FitContributor.DATA_TYPE_FLOAT,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "kJ" });

        mFPcrPct.setData(100.0);
        mFGlyPct.setData(100.0);
        mFPcrCons.setData(0);
        mFGlyCons.setData(0);
        mFPcrKj.setData(0.0);
        mFGlyKj.setData(0.0);
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
        mTauAer  = propFloat("tauAer", 25.0);
        mTauOn   = propFloat("tauOn", 6.0);

        if (mCP < 1.0)     { mCP = 1.0; }
        if (mWprime < 1.0) { mWprime = 1.0; }
        if (mFP < 0.0)     { mFP = 0.0; }
        if (mFP > 1.0)     { mFP = 1.0; }
        if (mTauP < 1.0)   { mTauP = 1.0; }
        if (mTauG < 1.0)   { mTauG = 1.0; }
        if (mFatK < 0.0)   { mFatK = 0.0; }
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
        mExhausted = false;
    }

    hidden function nowSec() {
        return Time.now().value();
    }

    // On pause/stop: freeze depletion, remember when the pause started.
    hidden function enterPause() {
        if (!mPaused) {
            mPaused = true;
            mPauseAt = nowSec();
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
            mPaused = false;
        }
    }

    // Closed-form recovery over `secs` seconds at rest (power = 0), i.e. the
    // per-second exponential recovery applied N times without a loop:
    //   cap - R_N = (cap - R_0) * (1 - a)^N
    hidden function applyRestRecovery(secs) {
        if (secs <= 0) { return; }
        // Glycolytic first (gate = 1 at rest): b = 1 - e^(-1/tauG)
        var bG = 1.0 - Math.pow(Math.E, -1.0 / mTauG);
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
    }

    function onTimerResume() {
        exitPause();
    }

    function onTimerPause() {
        enterPause();
    }

    function onTimerStop() {
        enterPause();
    }

    function onTimerReset() {
        resetSession();
        mStarted = false;
        mPaused = false;
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
            mFPcrPct.setData(100.0 * mRP / mCapP);
            mFGlyPct.setData(100.0 * mRG / mCapG);
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
            // 1999: phosphorylase ramps in over the first few seconds), so PCr — the
            // immediate buffer — covers almost everything at onset and both systems
            // then drain together as mG -> 1. PCr is the higher-power system, so its
            // peak rate (pPmax) exceeds the glycolytic peak rate (gPmax); demand is
            // split in proportion to available rate (pPmax : gPmax*g). Both tanks are
            // rate-capped AND capacity-limited; shortfall spills to the partner, then
            // to deficit.
            var need = delta * dt;
            var kOn = (mTauOn > 0.0) ? (1.0 - Math.pow(Math.E, -dt / mTauOn)) : 1.0;
            mG += (1.0 - mG) * kOn;

            var pcap = mPPmax * dt;
            var gcap = GLY_RATE_FRAC * mPPmax * dt;
            var totalRate = mPPmax + GLY_RATE_FRAC * mPPmax * mG;
            var pShare = need * (mPPmax / totalRate);
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
            if (unmet > 0.0) {                       // then PCr soaks up glycolytic's, up to its cap
                var addP = unmet;
                if (addP > mRP - takeP) { addP = mRP - takeP; }
                if (addP > pcap - takeP) { addP = pcap - takeP; }
                takeP += addP; unmet -= addP;
            }

            mRP -= takeP;
            mRG -= takeG;
            mDepP += takeP;
            mDepG += takeG;
            mExhausted = (unmet > 0.0);
            mConsP = takeP / dt;
            mConsG = takeG / dt;
        } else {
            // RESTORATION — PCr with fatigue-slowed tau; glycolytic gated below LT1.
            var kOff = (mTauOn > 0.0) ? (1.0 - Math.pow(Math.E, -dt / mTauOn)) : 1.0;
            mG -= mG * kOff;                          // glycolytic deactivation during recovery
            var tauPeff = pcrTau();
            mRP += mEta * (mCapP - mRP) * (1.0 - Math.pow(Math.E, -dt / tauPeff));
            var lt1 = mLt1Frac * mCP;
            if (p < lt1 && lt1 > 0.0) {
                var gate = (lt1 - p) / lt1;
                mRG += gate * (mCapG - mRG) * (1.0 - Math.pow(Math.E, -dt / mTauG));
            }
            mConsP = 0.0;
            mConsG = 0.0;
            mExhausted = false;
        }

        // Clamp
        if (mRP < 0.0) { mRP = 0.0; }
        if (mRP > mCapP) { mRP = mCapP; }
        if (mRG < 0.0) { mRG = 0.0; }
        if (mRG > mCapG) { mRG = mCapG; }

        var pctP = 100.0 * mRP / mCapP;

        // FIT: per-second reserve streams + live consumption
        mFPcrPct.setData(pctP);
        mFGlyPct.setData(100.0 * mRG / mCapG);
        mFPcrCons.setData(mConsP.toNumber());
        mFGlyCons.setData(mConsG.toNumber());
        // FIT: running session totals (kJ) — SDK keeps last value as summary
        mFPcrKj.setData(mDepP / 1000.0);
        mFGlyKj.setData(mDepG / 1000.0);

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

        // Layout by aspect ratio / size:
        //   very wide (w >= 3h): two horizontal bars SIDE BY SIDE (half width each)
        //   wide/short (1.5h <= w < 3h): two horizontal bars STACKED
        //   large portrait single field (w>=200, h>=240): vertical tanks + summary stats
        //   otherwise square/tall (e.g. a 1x2 cell): two VERTICAL bars side by side
        if (w >= h * 3) {
            drawHorizontalPair(dc, w, h, fg, pctP, pctG);
        } else if (w * 2 >= h * 3) {
            drawHorizontal(dc, w, h, fg, pctP, pctG);
        } else if (w >= 200 && h >= 240) {
            drawFull(dc, w, h, fg, pctP, pctG);
        } else {
            drawVertical(dc, w, h, fg, pctP, pctG);
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
