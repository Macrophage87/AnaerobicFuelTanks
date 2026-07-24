# ===========================================================================
# Pure model + FIT/IO functions for the Dual-Tank calibration tool.
#
# Extracted VERBATIM from app.R so the numeric model and FIT decoders can be
# unit-tested (tools/calibrate/tests/) and cross-checked against the Monkey C
# implementation WITHOUT loading Shiny, a device, or the network. Base R only
# (plus stats::lm / stats::optim); no library()/UI at top level.
#
# app.R source()s this file, so it is the single source of truth for these
# definitions — do not re-define them in app.R. read_power() still references
# FITfileR's readFitFile()/records(), but only inside its non-fallback branch,
# so defining it here is harmless when FITfileR is absent (it is resolved lazily
# at call time); the base-R fallback read_power_raw() needs no packages.
#
# This file is part of the deployed bundle (app.R needs it at runtime) and is
# listed in manifest.json. The tests/ tree is NOT deployed (see .rscignore).
# ===========================================================================

DURATIONS <- c(1,5,10,15,20,30,45,60,90,120,180,240,300,420,600,720,900,1200,1800,2400,3600)
DEFAULTS  <- list(fP = 0.25, pPmax = 300, tauP = 27, tauG = 470,
                  lt1Frac = 0.80, eta = 1.00, fatK = 0.75, gFat = 0.00, tauAer = 25, tauOn = 6)
GLY_RATE_FRAC <- 0.5   # glycolytic peak rate as a fraction of PCr peak rate (PCr is the higher-power system)
CP_FLOOR_W <- 50       # CP below this is physically implausible for the tool's use; below 0 it is impossible
SHORT_REC_S <- 45      # #86: an inter-bout recovery valley shorter than this (s) puts the ride in the
                       # sub-minute-recovery intermittent regime the model is NOT validated for -- the hard
                       # CP supply cap over-attributes supra-CP work to the anaerobic tanks and over-drains
                       # them. Sound by ~45-60 s valleys (issue's sweep). See white-paper §7 and issue #86.
SHORT_REC_FRAC <- 0.5  # #86: flag the ride when at least this fraction of its valleys are short (<SHORT_REC_S)
PARAMS <- c("CP","Wprime","pPmax","fP","tauP","tauG","eta")   # the tracked "sprint values"

cv <- function(x) { x <- x[is.finite(x)]; if (length(x) > 1 && mean(x) != 0) sd(x)/abs(mean(x)) else NA_real_ }

# Robustly turn a numeric-ish column into a plain numeric vector (handles the
# integer64 / bit64 that FITfileR uses for timestamps, and POSIXct alike).
as_num <- function(x) {
  if (inherits(x, "POSIXct")) return(as.numeric(x))
  v <- suppressWarnings(as.numeric(x))
  if (all(is.na(v)) && length(x)) suppressWarnings(as.numeric(as.character(x))) else v
}

# Collapse (timestamp, power) samples onto a true 1 Hz timeline. Pauses/gaps
# become 0 W; a corrupt/rollover timestamp that would blow the timeline up to
# millions of zero-filled seconds falls back to the raw contiguous samples.
timeline_from <- function(t, p) {
  ok <- is.finite(t) & is.finite(p); t <- t[ok]; p <- p[ok]
  if (length(t) < 2) return(NULL)
  o <- order(t); t <- t[o]; p <- p[o]
  keep <- !duplicated(t); t <- t[keep]; p <- p[keep]   # one power per second
  sec <- round(t - t[1]); span <- sec[length(sec)]
  if (!is.finite(span) || span < 1) return(p)
  if (span > 50 * length(p) + 86400) return(p)          # rollover guard
  line <- numeric(span + 1); line[sec + 1L] <- p; line
}

# Minimal FIT decoder in base R: pulls (timestamp, power) straight from the record
# messages. Used as a fallback when FITfileR can't read a file -- notably files
# carrying developer data fields (HRV apps: Alpha1/RespirationRate; W'bal fields;
# radar; carbs/fat), which routinely break records(). Developer fields are skipped
# by size; only native power (field 7) and timestamp (field 253) on record messages
# (global message 20) are decoded. Returns a per-second power vector or NULL.
read_power_raw <- function(path) {
  sz <- file.info(path)$size
  if (!is.finite(sz) || sz < 14) return(NULL)
  ib <- as.integer(readBin(path, "raw", n = sz))          # bytes 0..255, 1-based
  hdr <- ib[1]
  data_size <- ib[5] + ib[6] * 256 + ib[7] * 65536 + ib[8] * 16777216
  endp <- min(hdr + data_size, length(ib))
  rdint <- function(off, size, le) {                       # off = 1-based byte index
    b <- ib[off:(off + size - 1L)]; if (!le) b <- rev(b)
    sum(b * 256^(seq_along(b) - 1L))
  }
  defs <- vector("list", 16L)                              # local message types 0..15
  last_ts <- NA_real_
  tsv <- numeric(4096L); pwv <- numeric(4096L); k <- 0L
  add <- function(t, p) {
    k <<- k + 1L
    if (k > length(tsv)) { length(tsv) <<- 2L * length(tsv); length(pwv) <<- length(tsv) }
    tsv[k] <<- t; pwv[k] <<- p
  }
  pos <- hdr + 1L
  while (pos <= endp) {
    rh <- ib[pos]; pos <- pos + 1L
    if (bitwAnd(rh, 0x80L) != 0L) {                        # compressed-timestamp data msg
      lt <- bitwAnd(bitwShiftR(rh, 5L), 0x3L); toff <- bitwAnd(rh, 0x1fL)
      d <- defs[[lt + 1L]]; if (is.null(d)) return(NULL)
      ts <- if (is.finite(last_ts)) last_ts + ((toff - (last_ts %% 32)) %% 32) else NA_real_
      if (!is.na(d$off253)) { v <- rdint(pos + d$off253, d$sz253, d$le); if (v != d$inv253) ts <- v }
      if (d$gnum == 20 && !is.na(d$off7)) {
        pw <- rdint(pos + d$off7, d$sz7, d$le)
        if (pw != d$inv7 && is.finite(ts)) add(ts, pw)
      }
      if (is.finite(ts)) last_ts <- ts
      pos <- pos + d$size
    } else if (bitwAnd(rh, 0x40L) != 0L) {                 # definition msg
      arch <- ib[pos + 1L]; le <- (arch == 0L)
      gnum <- rdint(pos + 2L, 2L, le); nf <- ib[pos + 4L]
      p <- pos + 5L; off <- 0L
      off7 <- NA_integer_; sz7 <- 0L; off253 <- NA_integer_; sz253 <- 0L
      if (nf > 0L) for (j in seq_len(nf)) {
        fnum <- ib[p]; fsz <- ib[p + 1L]
        if (fnum == 7L)   { off7 <- off;   sz7 <- fsz }
        if (fnum == 253L) { off253 <- off; sz253 <- fsz }
        off <- off + fsz; p <- p + 3L
      }
      devsz <- 0L
      if (bitwAnd(rh, 0x20L) != 0L) {                      # developer field section
        ndev <- ib[p]; p <- p + 1L
        if (ndev > 0L) for (j in seq_len(ndev)) { devsz <- devsz + ib[p + 1L]; p <- p + 3L }
      }
      inv <- function(s) if (s == 1L) 255 else if (s == 2L) 65535 else if (s == 4L) 4294967295 else -1
      defs[[bitwAnd(rh, 0xfL) + 1L]] <- list(le = le, gnum = gnum, size = off + devsz,
        off7 = off7, sz7 = sz7, inv7 = inv(sz7), off253 = off253, sz253 = sz253, inv253 = inv(sz253))
      pos <- p
    } else {                                               # normal data msg
      lt <- bitwAnd(rh, 0xfL); d <- defs[[lt + 1L]]; if (is.null(d)) return(NULL)
      ts <- NA_real_
      if (!is.na(d$off253)) { v <- rdint(pos + d$off253, d$sz253, d$le); if (v != d$inv253) ts <- v }
      if (d$gnum == 20 && !is.na(d$off7)) {
        pw <- rdint(pos + d$off7, d$sz7, d$le)
        if (pw != d$inv7 && is.finite(ts)) add(ts, pw)
      }
      if (is.finite(ts)) last_ts <- ts
      pos <- pos + d$size
    }
  }
  if (k < 2L) return(NULL)
  timeline_from(tsv[seq_len(k)], pwv[seq_len(k)])
}

# #31: native sample cadence (median inter-sample seconds) on the cleaned timestamps — used only to
# WARN when a file is not ~1 Hz (a smart-recorded file's zero-filled gaps deflate the MMP / CP-W').
# Parity-inert: not consumed by simulate_tanks or the crosscheck fixtures.
cadence_of <- function(t) {
  t <- sort(unique(t[is.finite(t)]))
  if (length(t) < 2) NA_real_ else stats::median(diff(t))
}

# Returns list(p = <per-second power vector | NULL>, reason = <NULL | message>, cadence = <s | NA>).
# reason is non-NULL only when the file could not be turned into usable power.
read_power <- function(path) {
  fail <- function(msg) list(p = NULL, reason = msg, cadence = NA_real_)
  raw_fallback <- function(why) {
    # base-R decoder; survives developer-field files that break FITfileR
    r <- try(read_power_raw(path), silent = TRUE)
    if (!inherits(r, "try-error") && !is.null(r) && length(r) >= 2) return(list(p = r, reason = NULL, cadence = NA_real_))
    fail(why)
  }
  ff <- try(readFitFile(path), silent = TRUE)
  if (inherits(ff, "try-error")) return(raw_fallback("could not parse FIT (readFitFile failed)"))
  recs <- try(records(ff), silent = TRUE)
  if (inherits(recs, "try-error") || is.null(recs)) return(raw_fallback("records() failed"))
  if (is.data.frame(recs)) recs <- list(recs)
  # FITfileR returns ONE table per distinct record field-signature. A power meter
  # whose optional fields (pedal smoothness, torque effectiveness, respiration,
  # HRV) drop in and out produces MANY such tables. Concatenating them blindly
  # (unlist over the list) scrambles the time axis -- all the hard-pedaling samples
  # from one signature end up contiguous -- and silently drops autopause gaps, so a
  # "1200-sample" MMP window becomes 1200 s of back-to-back efforts. That inflates
  # long-duration MMP and pushes CP far above reality. Merge every sub-table on its
  # timestamp into a true 1 Hz timeline instead. Sub-tables lacking power/timestamp
  # are skipped.
  parts <- lapply(recs, function(df) {
    if (!is.data.frame(df) || !all(c("power", "timestamp") %in% names(df))) return(NULL)
    data.frame(t = as_num(df$timestamp), p = as_num(df$power))
  })
  parts <- do.call(rbind, parts)
  if (is.null(parts) || nrow(parts) < 2) return(raw_fallback("no power field in records"))
  line <- timeline_from(parts$t, parts$p)
  if (is.null(line)) return(raw_fallback("no usable power samples"))
  list(p = line, reason = NULL, cadence = cadence_of(parts$t))
}
best_mean_power <- function(p, d) { n <- length(p); if (n < d) return(NA_real_)
  cs <- cumsum(c(0, p)); max((cs[(d + 1):(n + 1)] - cs[1:(n - d + 1)]) / d) }
mmp_curve <- function(power_list, durations = DURATIONS)
  vapply(durations, function(d) { v <- vapply(power_list, best_mean_power, numeric(1), d = d)
    if (all(is.na(v))) NA_real_ else max(v, na.rm = TRUE) }, numeric(1))
# #87: per-duration provenance — which uploaded file supplied each duration's best mean power.
# Lets fit_cp() flag a CP/W' fit whose in-window efforts all come from ONE session (soft W').
mmp_src <- function(power_list, durations = DURATIONS)
  vapply(durations, function(d) { v <- vapply(power_list, best_mean_power, numeric(1), d = d)
    if (all(is.na(v))) NA_integer_ else which.max(v) }, integer(1))
fit_cp <- function(dur, pw, tmin, tmax, src = NULL) {
  keep <- which(dur >= tmin & dur <= tmax & is.finite(pw)); if (length(keep) < 2) return(NULL)
  # #87: single-session when every in-window effort's best traces to the same file (or only one
  # file was uploaded). W' rested on one session is soft -- the fit can't average out a bad day.
  single_session <- !is.null(src) && length(unique(stats::na.omit(src[keep]))) == 1
  t <- dur[keep]; W <- pw[keep] * t; f <- lm(W ~ t)
  CP <- unname(coef(f)[2]); Wprime <- unname(coef(f)[1])
  # Sanity: the CP asymptote must sit below every finite-duration power in the
  # window (you can't sustain forever more than you held for 12 min). If it doesn't,
  # the power-duration curve is corrupt (bad file parse, scrambled timeline) or the
  # window is too narrow -- flag it rather than reporting an impossible CP.
  minP <- min(pw[keep])
  # Non-physical vs implausible (two tiers). A corrupt/scrambled MMP can yield a
  # downward (or super-linear increasing) work-time fit -> CP <= 0 and/or W' <= 0,
  # which break the downstream math (div-by-zero, sign flip). Flag those as
  # `nonphysical`. A positive-but-suspiciously-low CP is merely `implausible` -- worth
  # warning about but harmless to export. Do NOT clamp/rewrite the returned CP/W':
  # keep them truthful so the user can diagnose the bad source data.
  nonphysical <- !is.finite(CP) || !is.finite(Wprime) || CP <= 0 || Wprime <= 0
  implausible <- is.finite(CP) && CP > 0 && CP < CP_FLOOR_W
  list(CP = CP, Wprime = Wprime, r2 = if (length(keep) < 3) NA_real_ else summary(f)$r.squared,
       n = length(keep), rng = max(t)/min(t), t = t, W = W,
       impossible = is.finite(CP) && is.finite(minP) && CP >= minP,
       nonphysical = nonphysical, implausible = implausible, single_session = single_session)
}
simulate_tanks <- function(power, cp, par) {
  n <- length(power)
  # Defensive: a non-physical CP scalar (<=0, NaN, Inf) must never reach the below-CP
  # recovery gates (which divide by cp) or flip signs. Floor it to a tiny positive.
  if (!is.finite(cp) || cp < 1e-6) cp <- 1e-6
  cP <- par$fP * par$Wprime; cG <- (1 - par$fP) * par$Wprime
  if (cP < 1e-6) cP <- 1e-6; if (cG < 1e-6) cG <- 1e-6   # guard f_p at 0/1 (rate taper divides by cP)
  rP <- cP; rG <- cG; aer <- cp; g <- 0; D <- 0; E <- 0; resTot <- numeric(n); deficit <- numeric(n)
  rPv <- numeric(n); rGv <- numeric(n)   # per-tank reserve series (for the Monkey C cross-check)
  AER_FALL <- 6
  kUp <- if (par$tauAer > 0) 1 - exp(-1 / par$tauAer) else 1
  kDn <- if (par$tauAer > 0) 1 - exp(-1 / (par$tauAer * AER_FALL)) else 1
  bG <- 1 - exp(-1 / par$tauG)
  tauOn <- if (is.null(par$tauOn)) 6 else par$tauOn        # glycolytic activation time constant (s)
  kOn <- if (tauOn > 0) 1 - exp(-1 / tauOn) else 1
  # #86 Phase 2 (gated; eAerMax = 0 -> OFF -> byte-identical to the hard-CP model, which is why the
  # fixtures/parity are untouched). An above-CP aerobic excess E (VO2 slow component) lets aerobic
  # supply exceed CP during/after intervals so short-recovery work isn't over-attributed to the tanks.
  # E rises toward eAerMax while P > CP (TAU_E_ON) and decays toward 0 while P <= CP (TAU_E_OFF).
  eAerMax <- if (is.null(par$eAerMax)) 0 else par$eAerMax
  # #88 Flip-A: tauEon/tauEoff are tunable config params (absent -> 90/120 -> byte-identical to the
  # scaffold constants), so the re-anchor can grid them. On-device settings wiring is deferred to Flip-B.
  tauEon  <- if (is.null(par$tauEon)) 90 else par$tauEon
  tauEoff <- if (is.null(par$tauEoff)) 120 else par$tauEoff
  kEon <- 1 - exp(-1 / tauEon); kEoff <- 1 - exp(-1 / tauEoff)
  for (i in seq_len(n)) {
    p <- power[i]
    if (par$tauAer > 0) {                     # sticky aerobic, floored; below CP aerobic covers demand
      tgt <- min(p, cp); aer <- aer + (tgt - aer) * (if (tgt > aer) kUp else kDn)
      aer <- max(0.5 * cp, min(cp, aer))
      if (eAerMax > 0) {                       # above-CP aerobic excess (gated; see setup above)
        E <- E + ((if (p > cp) eAerMax else 0) - E) * (if (p > cp) kEon else kEoff)
        if (E < 0) E <- 0
        if (E > eAerMax) E <- eAerMax
      }
      supply <- if (p > cp) min(p, aer + E) else p   # E == 0 when off -> min(p, aer) == aer (identical)
    } else supply <- cp
    delta <- p - supply
    if (delta > 0) {
      # PARALLEL draw. Glycolysis has activation inertia (Parolin 1999): it ramps in over
      # ~tauOn s, so at onset PCr (the immediate buffer) covers almost everything and both
      # drain together as g -> 1. TWO distinct roles, deliberately decoupled:
      #  * the SHARE of submaximal demand is capacity-proportional (wP=cP, wG=cG*g) -> at
      #    steady state both tanks track W'bal and empty together at exhaustion;
      #  * the RATE CEILING is the peak-flux cap, tapered with fullness (PCr flux falls as
      #    the store depletes; creatine-kinase equilibrium). The ceiling governs MAXIMAL
      #    efforts (PCr dominance emerges here); it does not distort submaximal sharing.
      # Residual demand the tanks cannot meet is banked as a DEFICIT (energy conservation).
      g <- g + (1 - g) * kOn
      rateP <- par$pPmax * (rP / cP)           # rate ceiling (tapered)
      rateG <- GLY_RATE_FRAC * par$pPmax * g
      # Optional glycolytic flux fatigue (gFat > 0): acidosis inhibits phosphorylase/PFK,
      # so glycolytic flux falls across repeated maximal sprints. Off (0) by default -- it
      # shifts the depletion split, so headline numbers are unchanged unless enabled (§6.10).
      gFat <- if (is.null(par$gFat)) 0 else par$gFat
      if (gFat > 0) rateG <- rateG * (max(0, rG / cG))^gFat
      wP <- cP; wG <- cG * g; totW <- wP + wG   # share weight (capacity-proportional)
      pShare <- if (totW > 1e-9) delta * wP / totW else delta
      gShare <- delta - pShare
      takeP <- min(pShare, rP, rateP)
      takeG <- min(gShare, rG, rateG)
      unmet <- delta - takeP - takeG
      if (unmet > 0) { addG <- min(unmet, rG - takeG, rateG - takeG); takeG <- takeG + addG; unmet <- unmet - addG }
      if (unmet > 0) { addP <- min(unmet, rP - takeP, rateP - takeP); takeP <- takeP + addP; unmet <- unmet - addP }
      rP <- rP - takeP; rG <- rG - takeG
      D <- D + unmet
      deficit[i] <- unmet
    } else {
      g <- g * (1 - kOn)                        # glycolytic deactivation during recovery
      # PCr resynthesis is OXIDATIVE -- it needs aerobic ATP above what the ride itself
      # consumes, so it is gated by the oxidative headroom (CP - P): near-arrested at CP,
      # full at rest. (eta folded into tauP, default 1.)
      gateP <- (cp - p) / cp; if (gateP < 0) gateP <- 0
      tauPeff <- par$tauP * (1 + par$fatK * (1 - rG / cG)); rP <- rP + gateP * par$eta * (cP - rP) * (1 - exp(-1 / tauPeff))
      # Glycolytic tank AND the deficit recover whenever p < CP, at Skiba's intensity-
      # dependent W'bal rate tau_W'(CP-p) = 546*e^(-0.01*(CP-p)) + 316, its amplitude
      # re-anchored so the 20 W passive rate reproduces Ferguson 2010 (as v0.6's linear
      # gate did at that point). Replaces the old linear (LT1-p)/LT1 gate, whose rate went
      # to zero at LT1 (recovery -> infinity) so the model could not complete a 4x4.
      if (p < cp) {
        dcp <- cp - p
        tauW <- 546 * exp(-0.01 * dcp) + 316
        tauWa <- 546 * exp(-0.01 * (cp - 20)) + 316
        gate20 <- (par$lt1Frac * cp - 20) / (par$lt1Frac * cp)
        fG <- max(0, gate20 * tauWa / tauW)
        kG <- min(1, bG * fG)
        rG <- rG + (cG - rG) * kG; D <- D * (1 - kG)
      }
    }
    rP <- max(0, min(cP, rP)); rG <- max(0, min(cG, rG)); resTot[i] <- rP + rG - D
    rPv[i] <- rP; rGv[i] <- rG   # record AFTER the clamp (matches Monkey C clampReserves order)
  }
  list(total = resTot, deficit = deficit, rP = rPv, rG = rGv)
}
suggest_marks <- function(power, cp, base) {
  s <- simulate_tanks(power, cp, base); tot <- s$total; n <- length(tot)
  cand <- c(which.min(tot), n); lo <- which(tot[-c(1, n)] < 0.20 * base$Wprime) + 1
  if (length(lo)) cand <- c(cand, lo[c(TRUE, diff(lo) > 30)]); sort(unique(cand))
}
ride_diag <- function(power, cp, base) {
  r <- rle(power > cp); ends <- cumsum(r$lengths); starts <- ends - r$lengths + 1L
  bouts <- which(r$values & r$lengths >= 5); nb <- length(bouts); mean_rec <- NA_real_; refill <- NA_real_
  short_rec <- NA_real_                           # #86: fraction of inter-bout valleys shorter than SHORT_REC_S
  tot <- simulate_tanks(power, cp, base)$total; Wp <- base$Wprime
  if (!is.finite(Wp) || Wp <= 0) Wp <- 1e-6      # defensive: a non-physical W' must not sign-flip the margin/refill ratios
  margin <- min(tot) / Wp                        # lowest reserve reached, as share of W'
  if (nb >= 2) {
    gaps <- numeric(nb-1); rf <- numeric(nb-1)
    for (k in seq_len(nb-1)) { b1 <- bouts[k]; b2 <- bouts[k+1]; gaps[k] <- starts[b2]-ends[b1]
      after <- tot[ends[b1]]; before <- tot[starts[b2]]; rf[k] <- (before-after)/max(1e-6, Wp-after) }
    mean_rec <- mean(gaps); refill <- median(pmax(0, pmin(1, rf)))
    short_rec <- mean(gaps < SHORT_REC_S)        # #86: per-valley test, NOT a mean_rec threshold -- a
                                                 # long+short mix can average >45 s yet hide an over-drained subset
  }
  list(n_bouts = nb, mean_rec_s = mean_rec, refill = refill, margin = margin, short_rec_frac = short_rec)
}
ride_flag <- function(dg, fit) {
  fl <- character(0)
  if (!is.null(fit) && isTRUE(fit$submax)) fl <- c(fl, "submax-weak")
  if (!is.null(fit) && fit$conv != 0) fl <- c(fl, "no-converge")
  if (!is.null(fit) && isTRUE(fit$boundary)) fl <- c(fl, "boundary-hit")
  if (is.na(dg$n_bouts) || dg$n_bouts < 3) fl <- c(fl, "few-bouts")
  # #86: sub-minute-recovery intermittent regime -- the model over-drains here (hard CP cap), so its
  # reserve trace / "empty" is outside the validated domain. Warn-only: still flagged and shown, but
  # NOT excluded from the aggregate (that is a Phase-2 call). Mutually exclusive with few-bouts (n>=3).
  if (!is.null(dg$short_rec_frac) && !is.na(dg$short_rec_frac) &&
      dg$n_bouts >= 3 && dg$short_rec_frac >= SHORT_REC_FRAC) fl <- c(fl, "short-recovery")
  # A submaximal set is *meant* to leave margin, so "rest-too-long" doesn't apply.
  if (!is.na(dg$refill) && dg$refill > 0.7 && !(!is.null(fit) && isTRUE(fit$submax))) fl <- c(fl, "rest-too-long")
  if (!is.null(fit) && !isTRUE(fit$submax) && fit$obj > 0.05) fl <- c(fl, "poor-fit")
  if (length(fl)) paste(fl, collapse = ";") else "ok"
}
fit_recovery <- function(power, cp, base, marks, submax = FALSE) {
  # eta is degenerate with tauP (it only rescales the effective recovery constant), so it
  # is NOT fitted -- it is held at base$eta (default 1.0) and tauP carries the recovery rate.
  Wp <- base$Wprime; th0 <- c(base$fP, base$tauP, base$tauG)
  obj <- function(th) { par <- base; par$fP <- th[1]; par$tauP <- th[2]; par$tauG <- th[3]
    s <- simulate_tanks(power, cp, par); feas <- 5 * mean((s$deficit/Wp)^2)
    if (submax) {
      # Efforts were NOT to failure -> no reserve=0 anchor. Submaximal repeated bouts
      # only constrain recovery through feasibility (tanks never go negative) plus the
      # quasi-steady reserve the bouts settle into, which is weak; a small ridge prior
      # toward the starting values keeps the optimiser identifiable. Params from these
      # rides are flagged low-confidence rather than trusted like maximal anchors.
      feas + 0.02 * mean(((th - th0) / pmax(1e-6, th0))^2)
    } else feas + (if (length(marks)) mean((s$total[marks]/Wp)^2) else 0) }
  lower <- c(0.10, 5, 60); upper <- c(0.60, 120, 1800)
  mkerr <- function(msg) list(fP = th0[1], tauP = th0[2], tauG = th0[3], eta = base$eta,
                              obj = Inf, conv = 99L, submax = submax,
                              status = "error", err = msg, boundary = FALSE)
  # Deterministic multi-start (th0 + fixed interior points) hardens the L-BFGS-B fit against
  # a poor single start; keep the lowest-objective CONVERGED fit (else the lowest finite one).
  # If optim throws (a non-finite objective aborts L-BFGS-B) or EVERY start is non-finite,
  # return a well-shaped error list: obj = Inf (never NA, so ride_flag's `obj > 0.05` read is
  # safe), conv non-zero, status = "error". fit_all_rides re-throws this into its single
  # fit-error channel, so a failed fit is never presented as a (poor) fit.
  runone <- function(s) tryCatch({
    st <- optim(s, obj, method = "L-BFGS-B", lower = lower, upper = upper, control = list(maxit = 200))
    if (is.finite(st$value)) st else NULL
  }, error = function(e) NULL)
  starts <- c(list(th0), lapply(c(0.5, 0.25, 0.75), function(fr) lower + fr * (upper - lower)))
  fits <- Filter(Negate(is.null), lapply(starts, runone))
  if (!length(fits)) return(mkerr("optim failed for all starts (non-finite objective)"))
  conv0 <- Filter(function(x) x$convergence == 0, fits)
  pool <- if (length(conv0)) conv0 else fits
  st <- pool[[which.min(vapply(pool, function(x) x$value, numeric(1)))]]
  par <- unname(st$par)
  list(fP = par[1], tauP = par[2], tauG = par[3], eta = base$eta,
       obj = st$value, conv = st$convergence, submax = submax,
       status = "ok", err = NA_character_,
       boundary = isTRUE(any(par == lower | par == upper)))
}
fit_all_rides <- function(power_list, names, cp, base, anchors, interval_idx, submax_idx = integer(0)) {
  # ONE fixed 15-column row schema for BOTH good and fit-error rows so do.call(rbind, ...)
  # can never hit a column mismatch. `eta` is dropped as a column (held fixed, not fitted).
  # `status`/`err` are carried on every row. Failed fits become flag = "fit-error" rows.
  mkrow <- function(file, type, src, dg, r, flag, err) data.frame(
    file = file, type = type, anchors = src,
    bouts  = if (is.null(dg)) NA_integer_ else dg$n_bouts,
    rec_s  = if (is.null(dg)) NA_real_ else round(dg$mean_rec_s),
    refill = if (is.null(dg)) NA_real_ else round(dg$refill, 2),
    margin = if (is.null(dg)) NA_real_ else round(dg$margin, 2),
    fP   = if (is.null(r)) NA_real_ else r$fP,
    tauP = if (is.null(r)) NA_real_ else r$tauP,
    tauG = if (is.null(r)) NA_real_ else r$tauG,
    obj  = if (is.null(r)) Inf else r$obj,
    conv = if (is.null(r)) 99L else as.integer(r$conv),
    flag = flag,
    status = if (is.null(r)) "error" else r$status,
    err = err, stringsAsFactors = FALSE)
  rows <- lapply(seq_along(power_list), function(i) {
    p <- power_list[[i]]; man <- anchors[[as.character(i)]]
    is_sub <- i %in% submax_idx; is_int <- (i %in% interval_idx) || is_sub
    type <- if (is_sub) "submax" else if (is_int) "interval" else "variable"
    # The ENTIRE per-ride block (marks + fit + diag) is wrapped, and a fit_recovery that
    # RETURNS status == "error" is re-thrown, so every failure -- thrown or returned -- lands
    # in the single catch handler that builds the one canonical fit-error row.
    tryCatch({
      if (is_sub) { m <- integer(0); src <- "submax (no reserve=0)" }        # not to failure -> no anchor
      else if (!is.null(man) && length(man)) { m <- man; src <- "manual" }
      else if (is_int) { m <- c(which.min(simulate_tanks(p, cp, base)$total), length(p)); src <- "interval-end" }
      else { m <- suggest_marks(p, cp, base); src <- "auto" }
      r <- fit_recovery(p, cp, base, m, submax = is_sub)
      if (isTRUE(r$status == "error")) stop(r$err)
      dg <- ride_diag(p, cp, base)
      mkrow(names[i], type, src, dg, r, ride_flag(dg, r), r$err)
    }, error = function(e) mkrow(names[i], type, NA_character_, NULL, NULL, "fit-error", conditionMessage(e)))
  })
  do.call(rbind, rows)
}
