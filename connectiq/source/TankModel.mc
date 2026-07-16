using Toybox.Math;
using Toybox.Lang;

//======================================================================
// Pure dual-tank physiology model.
//
// This class holds the ENTIRE numeric model — settings, derived capacities,
// reserve/deficit state, and the per-second physics step — with NO dependency on
// WatchUi / FitContributor / Activity / Application / Storage. That makes it
// constructible and drivable from a (:test) with no DataField context:
//   var m = new TankModel();
//   m.configure([250.0, 20000.0, 0.25, 300.0, 27.0, 470.0, 0.80, 1.00, 0.75, 0.0, 25.0, 6.0]);
//   m.resetTanks();
//   var pctP = m.stepModel(800.0);   // one 1 s step at 800 W
//
// DualTankView owns an instance of this class and DELEGATES all physics to it;
// the view keeps only DataField / FIT / rendering / persistence / lifecycle concerns.
// Every expression here is a byte-for-byte move from the original DualTankView so the
// arithmetic (and thus the documented test traces) is preserved exactly.
//
// UNITS: energies in JOULES, power in WATTS, dt = 1 s = one stepModel() call.
//======================================================================
class TankModel {

    // Aerobic off-kinetics are slower than on-kinetics -> a "sticky" aerobic supply
    // so brief eases/coasts don't force a re-ramp. Off tau = tauAer * AER_FALL.
    const AER_FALL = 6.0;
    // Glycolytic peak rate as a fraction of PCr peak rate. PCr is the higher-power
    // system, so glycolysis is rate-capped below it (a modeling assumption; ~0.5).
    const GLY_RATE_FRAC = 0.5;

    // ---- Settings (public so DualTankView and tests can read/write them) ----
    var mCP, mWprime, mFP, mPPmax, mTauP, mTauG, mLt1Frac, mEta;
    var mFatK;    // PCr recovery fatigue-slowing coefficient (0 = disabled)
    var mGFat;    // glycolytic flux fatigue exponent, rate_g *= (rG/cG)^gFat (0 = off)
    var mTauAer;  // aerobic ramp time constant, s (0 = disabled -> hard CP)
    var mTauOn;   // glycolytic activation time constant, s (~6, Parolin 1999)
    // ---- Derived capacities ----
    var mCapP, mCapG;
    // ---- State ----
    var mRP, mRG;        // reserves (J)
    var mDepP, mDepG;    // session totals depleted per system (J)
    var mConsP, mConsG;  // live draw (W)
    var mAer;            // aerobic supply (W), when ramp enabled
    var mG;              // glycolytic activation (0..1): ramps in over tauOn
    var mDeficit;        // energy debt (J): supra-CP work the rate caps couldn't place
    var mExhausted;      // genuine exhaustion: both reserves at/near zero (drives red flash)
    var mRateLimited;    // producing power beyond the tanks' flux (unmet > 0) — usually a stale P1s

    function initialize() {
    }

    // Set the 12 settings and derive mCapP/mCapG. Takes ONE fixed-order array (not 12
    // positional params) because Monkey C caps method arity low on older devices
    // (fenix6pro allows only 9). Order:
    //   [cp, wprime, fP, pPmax, tauP, tauG, lt1Frac, eta, fatK, gFat, tauAer, tauOn]
    // Mirrors the capacity derivation + reserve re-clamp formerly in reloadSettings();
    // the property reads + per-field clamps stay in the view (which passes already-
    // clamped values in). Callers with no Application.Properties (tests) pass literals.
    function configure(s) {
        mCP      = s[0];
        mWprime  = s[1];
        mFP      = s[2];
        mPPmax   = s[3];
        mTauP    = s[4];
        mTauG    = s[5];
        mLt1Frac = s[6];
        mEta     = s[7];
        mFatK    = s[8];
        mGFat    = s[9];
        mTauAer  = s[10];
        mTauOn   = s[11];

        mCapP = mFP * mWprime;
        mCapG = (1.0 - mFP) * mWprime;
        if (mCapP < 1.0) { mCapP = 1.0; }
        if (mCapG < 1.0) { mCapG = 1.0; }

        // Re-clamp existing reserves to any new capacities (locals for null-narrowing;
        // mRP/mRG are null before the first resetTanks()/restore).
        var rp = mRP;
        if (rp != null && rp > mCapP) { mRP = mCapP; }
        var rg = mRG;
        if (rg != null && rg > mCapG) { mRG = mCapG; }
    }

    // Fresh-ride initialization: full tanks, zeroed session totals + derived/live state.
    // (Mirrors DualTankView.resetSession() for the fields that live on the model.)
    function resetTanks() {
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

    // Clamp both reserves into [0, capacity]. Called only when mRP/mRG are non-null.
    function clampReserves() {
        if (mRP < 0.0)   { mRP = 0.0; }
        if (mRP > mCapP) { mRP = mCapP; }
        if (mRG < 0.0)   { mRG = 0.0; }
        if (mRG > mCapG) { mRG = mCapG; }
    }

    // Closed-form recovery over `secs` seconds at rest (power = 0), i.e. the
    // per-second exponential recovery applied N times without a loop:
    //   cap - R_N = (cap - R_0) * (1 - a)^N
    function applyRestRecovery(secs) {
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
    function pcrTau() {
        var fillG = mRG / mCapG;
        if (fillG < 0.0) { fillG = 0.0; }
        if (fillG > 1.0) { fillG = 1.0; }
        var t = mTauP * (1.0 + mFatK * (1.0 - fillG));
        if (t < 1.0) { t = 1.0; }
        return t;
    }

    //------------------------------------------------------------------
    // Model step — one second of physics. `power` is a plain Float watt value
    // (already unwrapped by the caller). Returns pctP = 100 * mRP / mCapP.
    //------------------------------------------------------------------
    function stepModel(power) {
        var p = power;
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
        clampReserves();

        var pctP = 100.0 * mRP / mCapP;
        return pctP;
    }
}
