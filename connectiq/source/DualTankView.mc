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
//   - Demand above the aerobic supply is met PCr-first (rate-limited), glycolytic-second.
//   - Below supply: PCr recovers (tauP, efficiency eta); glycolytic recovers
//     slowly (tauG) and only below LT1 (lt1Frac * CP).
//
// REALISM TERMS (from white paper, tunable via settings):
//   - Aerobic ramp: aerobic supply is a first-order response toward min(P,CP) with
//     time constant tauAer (default 25 s), so the tanks cover the onset O2 deficit.
//     Set tauAer = 0 to fall back to a hard CP boundary.
//   - Fatigue-slowed PCr recovery: tauPeff = tauP * (1 + fatK * (1 - rG/cG)), so PCr
//     resynthesis slows as the glycolytic tank empties. Set fatK = 0 to disable.
//
// PAUSE/RESUME: depletion is frozen while paused; on resume the tanks are recovered
//   in closed form for the entire elapsed pause (rest recovery), with no depletion
//   accumulated during the pause.
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

    // ---- Settings ----
    hidden var mCP, mWprime, mFP, mPPmax, mTauP, mTauG, mLt1Frac, mEta;
    hidden var mFatK;    // PCr recovery fatigue-slowing coefficient (0 = disabled)
    hidden var mTauAer;  // aerobic ramp time constant, s (0 = disabled -> hard CP)
    // ---- Derived capacities ----
    hidden var mCapP, mCapG;
    // ---- State ----
    hidden var mRP, mRG;        // reserves (J)
    hidden var mDepP, mDepG;    // session totals depleted per system (J)
    hidden var mConsP, mConsG;  // live draw (W)
    hidden var mAer;            // aerobic supply (W), when ramp enabled
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
        mFP      = propFloat("fP", 0.35);
        mPPmax   = propFloat("pPmax", 300.0);
        mTauP    = propFloat("tauP", 22.0);
        mTauG    = propFloat("tauG", 360.0);
        mLt1Frac = propFloat("lt1Frac", 0.80);
        mEta     = propFloat("eta", 0.80);
        mFatK    = propFloat("fatK", 0.75);
        mTauAer  = propFloat("tauAer", 25.0);

        if (mCP < 1.0)     { mCP = 1.0; }
        if (mWprime < 1.0) { mWprime = 1.0; }
        if (mFP < 0.0)     { mFP = 0.0; }
        if (mFP > 1.0)     { mFP = 1.0; }
        if (mTauP < 1.0)   { mTauP = 1.0; }
        if (mTauG < 1.0)   { mTauG = 1.0; }
        if (mFatK < 0.0)   { mFatK = 0.0; }
        if (mTauAer < 0.0) { mTauAer = 0.0; }

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
            mPaused = false;
        }
    }

    // Closed-form recovery over `secs` seconds at rest (power = 0), i.e. the
    // per-second exponential recovery applied N times without a loop:
    //   cap - R_N = (cap - R_0) * (1 - a)^N
    hidden function applyRestRecovery(secs) {
        if (secs <= 0) { return; }
        // Glycolytic first (gate = 1 at rest): b = 1 - e^(-1/tauG)
        var bG = 1.0 - Math.exp(-1.0 / mTauG);
        if (bG < 0.0) { bG = 0.0; }
        if (bG > 1.0) { bG = 1.0; }
        mRG = mCapG - (mCapG - mRG) * Math.pow(1.0 - bG, secs);
        if (mRG < 0.0) { mRG = 0.0; }
        if (mRG > mCapG) { mRG = mCapG; }
        // PCr with fatigue-slowed tau, evaluated at the (now largely recovered)
        // glycolytic fill: a = eta * (1 - e^(-1/tauPeff))
        var tauPeff = pcrTau();
        var aP = mEta * (1.0 - Math.exp(-1.0 / tauPeff));
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

        // Aerobic supply: first-order ramp toward min(P, CP) with tauAer, so the
        // anaerobic tanks cover the onset "oxygen deficit". tauAer <= 0 disables
        // the ramp and falls back to a hard CP boundary.
        var supply = mCP;
        if (mTauAer > 0.0) {
            var tgt = (p < mCP) ? p : mCP;
            mAer += (tgt - mAer) * (1.0 - Math.exp(-dt / mTauAer));
            if (mAer < 0.0) { mAer = 0.0; }
            if (mAer > mCP) { mAer = mCP; }
            supply = mAer;
        } else {
            mAer = mCP;
        }

        var delta = p - supply;
        var takeP = 0.0;
        var takeG = 0.0;

        if (delta > 0.0) {
            // DEPLETION — PCr first (rate-limited), glycolytic covers the remainder.
            var need = delta * dt;

            takeP = need;
            if (takeP > mRP) { takeP = mRP; }
            var pcap = mPPmax * dt;
            if (takeP > pcap) { takeP = pcap; }
            mRP -= takeP;
            need -= takeP;

            takeG = need;
            if (takeG > mRG) { takeG = mRG; }
            mRG -= takeG;
            need -= takeG;

            mDepP += takeP;
            mDepG += takeG;
            mExhausted = (need > 0.0);
            mConsP = takeP / dt;
            mConsG = takeG / dt;
        } else {
            // RESTORATION — PCr with fatigue-slowed tau; glycolytic gated below LT1.
            var tauPeff = pcrTau();
            mRP += mEta * (mCapP - mRP) * (1.0 - Math.exp(-dt / tauPeff));
            var lt1 = mLt1Frac * mCP;
            if (p < lt1 && lt1 > 0.0) {
                var gate = (lt1 - p) / lt1;
                mRG += gate * (mCapG - mRG) * (1.0 - Math.exp(-dt / mTauG));
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

        drawBar(dc, xBar, yTop, barW, barH, pctP, true, fg);
        drawBar(dc, xBar, yBot, barW, barH, pctG, false, fg);

        // Labels (left) and percentages (right)
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

    hidden function fmtPct(v) {
        return v.toNumber().toString() + "%";
    }

    hidden function drawBar(dc, x, y, bw, bh, pct, isPcr, fg) {
        // Empty-track outline so 0% is still visible.
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(x, y, bw, bh);

        var depleted = (pct <= 3.0);
        var draining = isPcr ? (mConsP > 0.0) : (mConsG > 0.0);

        var col = isPcr ? COL_PCR_DULL : COL_GLY_DULL;
        var fillW;
        if (depleted) {
            if (!mFlashOn) { return; }   // blink: skip fill on the "off" frame
            col = COL_RED;
            fillW = bw - 2;              // full-width red flash when the tank is spent
        } else {
            if (draining) { col = isPcr ? COL_PCR_BRIGHT : COL_GLY_BRIGHT; }
            fillW = ((bw - 2) * pct / 100.0).toNumber();
            if (fillW < 0) { fillW = 0; }
            if (fillW > bw - 2) { fillW = bw - 2; }
        }
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x + 1, y + 1, fillW, bh - 2);

        // Live consumption readout while draining.
        if (draining && !depleted) {
            var wtxt = "-" + (isPcr ? mConsP : mConsG).toNumber().toString() + "W";
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + bw - 3, y + bh / 2, mFontSmall, wtxt,
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }
}
