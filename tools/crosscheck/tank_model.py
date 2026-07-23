"""Python mirror of the Monkey C `TankModel` (connectiq/source/TankModel.mc).

This is a line-for-line port of `TankModel.stepModel` / `pcrTau` / `clampReserves`, used
as a CI-side stand-in for the compiled Monkey C model so the R <-> Monkey C physics
equivalence (issue #27, part C) can be enforced deterministically WITHOUT a Connect IQ SDK
or simulator. The on-device `(:test)` run (the `ciq-test` job) exercises the real compiled
model; this mirror guarantees the *arithmetic* the R reference and the Monkey C source agree
on, on every push.

Keep this in lock-step with TankModel.mc: if the Monkey C physics changes, change it here in
the SAME commit and regenerate the fixtures from R.

Deliberate test-only difference from production Monkey C: `reset()` starts the aerobic
tracker WARM (`aer = mCP`) to match R `simulate_tanks` (`aer <- cp`). Production
`DualTankView`/`TankModel.resetTanks()` start `mAer = 0.0` and ramp from a 0.5*CP floor; that
cold-start ramp is a separate concern the on-device test covers. Aligning the initial aerobic
STATE (not a setting) is what makes the two integrators comparable — see part C1.
"""

import math

AER_FALL = 6.0
GLY_RATE_FRAC = 0.5
TAU_E_ON = 90.0    # #86 Phase 2: above-CP aerobic-excess rise time constant (s)
TAU_E_OFF = 120.0  # #86 Phase 2: above-CP aerobic-excess decay time constant (s)


class TankModel:
    # ---- settings ----
    # mCP, mWprime, mFP, mPPmax, mTauP, mTauG, mLt1Frac, mEta, mFatK, mGFat, mTauAer, mTauOn
    # ---- derived ---- mCapP, mCapG
    # ---- state ---- mRP, mRG, mDepP, mDepG, mConsP, mConsG, mAer, mG, mDeficit

    def configure(self, cfg):
        """cfg: dict with keys cp, Wprime, fP, pPmax, tauP, tauG, lt1Frac, eta, fatK,
        gFat, tauAer, tauOn (exactly the tools/crosscheck/fixtures/config.csv rows)."""
        self.mCP = cfg["cp"]
        self.mWprime = cfg["Wprime"]
        self.mFP = cfg["fP"]
        self.mPPmax = cfg["pPmax"]
        self.mTauP = cfg["tauP"]
        self.mTauG = cfg["tauG"]
        self.mLt1Frac = cfg["lt1Frac"]
        self.mEta = cfg["eta"]
        self.mFatK = cfg["fatK"]
        self.mGFat = cfg["gFat"]
        self.mTauAer = cfg["tauAer"]
        self.mTauOn = cfg["tauOn"]
        self.mEAerMax = cfg.get("eAerMax", 0.0)   # #86 Phase 2: above-CP aerobic excess cap (0 = off)

        self.mCapP = self.mFP * self.mWprime
        self.mCapG = (1.0 - self.mFP) * self.mWprime
        if self.mCapP < 1.0:
            self.mCapP = 1.0
        if self.mCapG < 1.0:
            self.mCapG = 1.0

    def reset(self):
        """Full tanks, zeroed totals/live state. Warm aerobic start (aer=mCP) to match R."""
        self.mRP = self.mCapP
        self.mRG = self.mCapG
        self.mDepP = 0.0
        self.mDepG = 0.0
        self.mConsP = 0.0
        self.mConsG = 0.0
        self.mAer = self.mCP        # WARM (test-only) — see module docstring / part C1
        self.mG = 0.0
        self.mDeficit = 0.0
        self.mE = 0.0               # #86 Phase 2: above-CP aerobic excess (0 until eAerMax > 0)

    def clamp_reserves(self):
        if self.mRP < 0.0:
            self.mRP = 0.0
        if self.mRP > self.mCapP:
            self.mRP = self.mCapP
        if self.mRG < 0.0:
            self.mRG = 0.0
        if self.mRG > self.mCapG:
            self.mRG = self.mCapG

    def pcr_tau(self):
        fillG = self.mRG / self.mCapG
        if fillG < 0.0:
            fillG = 0.0
        if fillG > 1.0:
            fillG = 1.0
        t = self.mTauP * (1.0 + self.mFatK * (1.0 - fillG))
        if t < 1.0:
            t = 1.0
        return t

    def step(self, power, dt=1.0):
        p = power

        # Defensive dt<=0 guard (mirror of TankModel.stepModel): a non-positive step integrates
        # nothing and must not reach the mConsP = takeP/dt division (0/0 -> NaN). Kept in lock-step
        # with the Monkey C model; parity paths always pass dt=1 so this never fires there.
        if dt <= 0.0:
            self.mConsP = 0.0
            self.mConsG = 0.0
            return 100.0 * self.mRP / self.mCapP

        # Aerobic supply.
        supply = self.mCP
        if self.mTauAer > 0.0:
            tgt = p if p < self.mCP else self.mCP
            if tgt > self.mAer:
                kA = 1.0 - math.exp(-dt / self.mTauAer)
            else:
                kA = 1.0 - math.exp(-dt / (self.mTauAer * AER_FALL))
            self.mAer += (tgt - self.mAer) * kA
            floorA = 0.5 * self.mCP
            if self.mAer < floorA:
                self.mAer = floorA
            if self.mAer > self.mCP:
                self.mAer = self.mCP
            if self.mEAerMax > 0.0:   # #86 Phase 2: above-CP aerobic excess (gated; 0 -> identical)
                tgtE = self.mEAerMax if p > self.mCP else 0.0
                kE = (1.0 - math.exp(-dt / TAU_E_ON)) if p > self.mCP else (1.0 - math.exp(-dt / TAU_E_OFF))
                self.mE += (tgtE - self.mE) * kE
                if self.mE < 0.0:
                    self.mE = 0.0
                if self.mE > self.mEAerMax:
                    self.mE = self.mEAerMax
            supply = min(p, self.mAer + self.mE) if p > self.mCP else p   # mE==0 off -> == mAer (identical)
        else:
            self.mAer = self.mCP

        delta = p - supply
        takeP = 0.0
        takeG = 0.0

        if delta > 0.0:
            need = delta * dt
            kOn = (1.0 - math.exp(-dt / self.mTauOn)) if self.mTauOn > 0.0 else 1.0
            self.mG += (1.0 - self.mG) * kOn

            rateP = self.mPPmax * (self.mRP / self.mCapP)
            rateG = GLY_RATE_FRAC * self.mPPmax * self.mG
            if self.mGFat > 0.0 and self.mCapG > 0.0:
                fillG2 = self.mRG / self.mCapG
                if fillG2 < 0.0:
                    fillG2 = 0.0
                rateG *= math.pow(fillG2, self.mGFat)
            pcap = rateP * dt
            gcap = rateG * dt
            wP = self.mCapP
            wG = self.mCapG * self.mG
            totW = wP + wG
            pShare = need * (wP / totW) if totW > 1e-9 else need
            gShare = need - pShare

            takeP = pShare
            if takeP > self.mRP:
                takeP = self.mRP
            if takeP > pcap:
                takeP = pcap
            takeG = gShare
            if takeG > self.mRG:
                takeG = self.mRG
            if takeG > gcap:
                takeG = gcap

            unmet = need - takeP - takeG
            if unmet > 0.0:
                addG = unmet
                if addG > self.mRG - takeG:
                    addG = self.mRG - takeG
                if addG > gcap - takeG:
                    addG = gcap - takeG
                takeG += addG
                unmet -= addG
            if unmet > 0.0:
                addP = unmet
                if addP > self.mRP - takeP:
                    addP = self.mRP - takeP
                if addP > pcap - takeP:
                    addP = pcap - takeP
                takeP += addP
                unmet -= addP

            self.mRP -= takeP
            self.mRG -= takeG
            self.mDeficit += unmet
            self.mDepP += takeP
            self.mDepG += takeG
            self.mConsP = takeP / dt
            self.mConsG = takeG / dt
        else:
            kOff = (1.0 - math.exp(-dt / self.mTauOn)) if self.mTauOn > 0.0 else 1.0
            self.mG -= self.mG * kOff
            gateP = (self.mCP - p) / self.mCP
            if gateP < 0.0:
                gateP = 0.0
            tauPeff = self.pcr_tau()
            self.mRP += gateP * self.mEta * (self.mCapP - self.mRP) * (1.0 - math.exp(-dt / tauPeff))
            if p < self.mCP and self.mCP > 0.0:
                dcp = self.mCP - p
                tauW = 546.0 * math.exp(-0.01 * dcp) + 316.0
                tauWanchor = 546.0 * math.exp(-0.01 * (self.mCP - 20.0)) + 316.0
                gate20 = (self.mLt1Frac * self.mCP - 20.0) / (self.mLt1Frac * self.mCP)
                fG = gate20 * tauWanchor / tauW
                if fG < 0.0:
                    fG = 0.0
                kG = (1.0 - math.exp(-dt / self.mTauG)) * fG
                if kG < 0.0:
                    kG = 0.0
                if kG > 1.0:
                    kG = 1.0
                self.mRG += (self.mCapG - self.mRG) * kG
                self.mDeficit -= self.mDeficit * kG
            self.mConsP = 0.0
            self.mConsG = 0.0

        self.clamp_reserves()
        return 100.0 * self.mRP / self.mCapP
