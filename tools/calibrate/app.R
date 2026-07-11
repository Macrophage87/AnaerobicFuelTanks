# Dual-Tank Parameter Estimator — R Shiny (sketch)
# --------------------------------------------------------------------------
# Upload SEVERAL .FIT files (rides, races, interval sets) -> estimate the
# AnaerobicFuelTanks parameters, picking the best value for each across files.
#
#   * CP, W', pPmax        -> combined mean-maximal power curve (best-of-all).
#   * fP, tauP, tauG, eta   -> dual-tank model fit per ride, anchored at maximal
#                              moments, then aggregated (median / best-fit).
#   * INTERVAL SETS         -> constrain recovery only when between-bout refill is
#                              low (short rest). Sets with >70% refill are flagged.
#   * UNCERTAINTY           -> every parameter is flagged when weakly constrained.
#   * EXPORT                -> a dated YAML reading (append-friendly, multi-reading)
#                              and a PDF report explaining where each value stands.
#   * TRENDS                -> supply a history YAML to see each value over time.
#
# install.packages(c("shiny","ggplot2","DT","yaml"))
# remotes::install_github("grimbough/FITfileR")
# --------------------------------------------------------------------------

library(shiny)
library(bslib)
library(ggplot2)
library(yaml)
suppressWarnings(suppressMessages(library(FITfileR)))
# install.packages(c("shiny","bslib","ggplot2","DT","yaml")); remotes::install_github("grimbough/FITfileR")

DURATIONS <- c(1,5,10,15,20,30,45,60,90,120,180,240,300,420,600,720,900,1200,1800,2400,3600)
DEFAULTS  <- list(fP = 0.35, pPmax = 300, tauP = 22, tauG = 360,
                  lt1Frac = 0.80, eta = 0.80, fatK = 0.75, tauAer = 25)
PARAMS <- c("CP","Wprime","pPmax","fP","tauP","tauG","eta")   # the tracked "sprint values"
PARAM_DESC <- c(
  CP      = "Critical power (W): highest sustainable power; linear work model over best 2-12 min efforts.",
  Wprime  = "Anaerobic work capacity above CP (J).",
  pPmax   = "Max PCr (fast) power above CP (W): from the best 5 s sprint across files.",
  fP      = "PCr share of W' (0-1): from the recovery fit across rides, else default.",
  tauP    = "PCr recovery time constant (s): fast reconstitution.",
  tauG    = "Glycolytic recovery time constant (s): slow reconstitution.",
  eta     = "PCr recovery efficiency (0-1).",
  lt1Frac = "Fraction of CP below which glycolytic refills: default (needs a threshold test).",
  fatK    = "Fatigue slowing of PCr recovery: default (needs repeated-bout data).",
  tauAer  = "Aerobic on-ramp time constant (s): default.")
cv <- function(x) { x <- x[is.finite(x)]; if (length(x) > 1 && mean(x) != 0) sd(x)/abs(mean(x)) else NA_real_ }

# ---- dual-tank theme (purple = PCr, green = glycolytic) --------------------
PCR <- "#B44DFF"; PCR_DEEP <- "#6C26A8"; GLY <- "#37E85A"; GLY_DEEP <- "#1A8C3A"
BRASS <- "#C9A227"; PARCH <- "#EDE0C8"; WALNUT <- "#20160E"
# Standard, offline-safe dark bslib theme (no web-font fetch, no heavy custom sass
# that can silently fail to compile on deploy). Purple = PCr, green = glycolytic
# are carried by primary/secondary plus a few accent rules. The sidebar rules keep
# it compact enough to fit on one screen.
app_css <- "
.pcr{color:#B44DFF;font-weight:700;} .gly{color:#37E85A;font-weight:700;}
.guide{max-width:920px;line-height:1.5;} .guide h4{color:#C9A227;margin:16px 0 6px;}
.guide li{margin:5px 0;} .guide code{background:rgba(255,255,255,.08);border-radius:4px;padding:1px 6px;}
.guide table{border-collapse:collapse;margin:8px 0;} .guide th,.guide td{border:1px solid #4a4a4a;padding:5px 11px;text-align:left;}
.guide th{color:#C9A227;background:rgba(255,255,255,.05);}
/* compact sidebar so everything fits without scrolling */
.bslib-sidebar-layout>.sidebar{font-size:13px;}
.sidebar .form-group,.sidebar .shiny-input-container{margin-bottom:.45rem;}
.sidebar .control-label,.sidebar label{margin-bottom:.15rem;font-weight:600;}
.sidebar .btn{padding:.28rem .5rem;}
.sidebar .form-text,.sidebar .help-block{font-size:11px;margin-top:.1rem;}
.sidebar hr{margin:.4rem 0;}
#read_txt{max-height:110px;overflow:auto;font-size:11px;margin:0;padding:.35rem .5rem;}
.sidebar .accordion-button{padding:.35rem .6rem;font-size:13px;}
.sidebar .accordion-body{padding:.4rem .6rem;}
"
tank_theme <- bs_theme(version = 5, bg = "#16191c", fg = "#e6e6e6",
  primary = PCR, secondary = GLY, success = GLY, info = GLY, warning = BRASS)
tank_theme <- bs_add_rules(tank_theme, app_css)

# ggplot theme that blends into the brass-on-walnut cards (screen)
gg_tank <- function() theme_minimal(base_size = 12) + theme(
  plot.background  = element_rect(fill = "transparent", colour = NA),
  panel.background = element_rect(fill = "transparent", colour = NA),
  panel.grid.major = element_line(colour = "#4a3a24"), panel.grid.minor = element_line(colour = "#33281a"),
  text = element_text(colour = PARCH), axis.text = element_text(colour = BRASS),
  strip.text = element_text(colour = BRASS, face = "bold"), plot.title = element_text(colour = BRASS))
# light "aged parchment" theme for the PDF report (dark ink on parchment)
gg_report <- function() theme_minimal(base_size = 11) + theme(
  plot.background  = element_rect(fill = "#EDE0C8", colour = NA),
  panel.background = element_rect(fill = "#EDE0C8", colour = NA),
  panel.grid.major = element_line(colour = "#d8c8a8"), panel.grid.minor = element_line(colour = "#e6dcc4"),
  text = element_text(colour = "#3a2817"), axis.text = element_text(colour = "#6b4f2a"),
  strip.text = element_text(colour = "#6b4f2a", face = "bold"), plot.title = element_text(colour = "#6b4f2a", face = "bold"))

# in-app user guide (rendered in the first tab)
guide_html <- r"[
<div class="guide">
<h4>What this tool does</h4>
<p>Upload your ride files and it estimates the parameters for the <span class="pcr">PCr</span> /
<span class="gly">glycolytic</span> dual-tank Connect IQ data field, flagging anything it cannot pin down.</p>

<h4>Step by step</h4>
<ol>
<li><b>Upload FIT files</b> in the Boiler Room (left): best-effort tests, races, hard group rides, interval sets.</li>
<li>Read <b>CP</b> and <b>W'</b> on the <i>Power-duration</i> and <i>CP / W' fit</i> tabs &mdash; the most reliable numbers.</li>
<li>On <i>Anchor editor</i>, <b>click each ride's reserve trace</b> where you were maximal or cracked
(final sprint, an attack you could not follow, the moment you got dropped). Tick repeated-bout
workouts as <b>interval sets</b> in the sidebar.</li>
<li>Press <b>Fit fP / tauP / tauG / eta on every ride</b>. Per-ride results appear on <i>Recovery fit</i>;
the final set with uncertainty flags is on <i>App parameters</i>.</li>
<li><b>Export</b> (sidebar): a Connect IQ settings file, a dated YAML reading, or a PDF report.</li>
</ol>

<h4>What it can and cannot know</h4>
<table>
<tr><th>Parameter</th><th>Source</th><th>Reliable?</th></tr>
<tr><td>CP, Wprime, pPmax</td><td>best across all files (power-duration curve)</td><td>yes</td></tr>
<tr><td>fP, tauP, tauG, eta</td><td>model fit on rides with maximal anchors</td><td>only with the right data</td></tr>
<tr><td>lt1Frac, fatK, tauAer</td><td>defaults</td><td>need special tests</td></tr>
</table>
<p>A single all-out effort obeys t_lim = W'/(P-CP), so it gives only CP and W'. The tank split and
recovery rates appear only across <b>repeated efforts with recovery</b>, and only where you anchor
maximal moments.</p>

<h4>Anchors &amp; interval sets</h4>
<ul>
<li>An <b>anchor</b> marks a second where your reserve hit zero. Getting dropped is a perfect anchor.</li>
<li><b>Interval sets &mdash; to failure</b>: the last bout drove you to (or near) empty. These get a
reserve&nbsp;=&nbsp;0 anchor and constrain recovery well &mdash; as long as the rest is short (sets with
more than 70% between-bout refill are flagged as uninformative for tauP / tauG).</li>
<li><b>Interval sets &mdash; submaximal</b>: repeated bouts you completed with margin (you could have done
more). Tick these separately. The fit then uses <i>only</i> feasibility and the recovery between bouts &mdash;
no reserve&nbsp;=&nbsp;0 anchor is forced, since you never emptied the tank. The recovery table reports the
<b>reserve margin</b> you kept and flags the numbers <code>submax-weak</code> (low-confidence, excluded from
the combined estimate unless nothing better exists).</li>
</ul>

<h4>Applying the settings</h4>
<p><b>Export Connect IQ settings (JSON)</b> writes a file keyed exactly like the data field's settings.
Type those values into Garmin Connect &rarr; the field's settings (Garmin does not import files), or load
the JSON in the Connect IQ simulator or your own build.</p>

<h4>Colour key</h4>
<p><span class="pcr">Purple = PCr</span> (fast, small tank) &middot;
<span class="gly">Green = glycolytic</span> (slow, large tank). Lines marked <b>uncertain</b> are weakly constrained.</p>
</div>
]"

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

# Returns list(p = <per-second power vector | NULL>, reason = <NULL | message>).
# reason is non-NULL only when the file could not be turned into usable power.
read_power <- function(path) {
  fail <- function(msg) list(p = NULL, reason = msg)
  raw_fallback <- function(why) {
    # base-R decoder; survives developer-field files that break FITfileR
    r <- try(read_power_raw(path), silent = TRUE)
    if (!inherits(r, "try-error") && !is.null(r) && length(r) >= 2) return(list(p = r, reason = NULL))
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
  list(p = line, reason = NULL)
}
best_mean_power <- function(p, d) { n <- length(p); if (n < d) return(NA_real_)
  cs <- cumsum(c(0, p)); max((cs[(d + 1):(n + 1)] - cs[1:(n - d + 1)]) / d) }
mmp_curve <- function(power_list, durations = DURATIONS)
  vapply(durations, function(d) { v <- vapply(power_list, best_mean_power, numeric(1), d = d)
    if (all(is.na(v))) NA_real_ else max(v, na.rm = TRUE) }, numeric(1))
fit_cp <- function(dur, pw, tmin, tmax) {
  keep <- which(dur >= tmin & dur <= tmax & is.finite(pw)); if (length(keep) < 2) return(NULL)
  t <- dur[keep]; W <- pw[keep] * t; f <- lm(W ~ t)
  CP <- unname(coef(f)[2])
  # Sanity: the CP asymptote must sit below every finite-duration power in the
  # window (you can't sustain forever more than you held for 12 min). If it doesn't,
  # the power-duration curve is corrupt (bad file parse, scrambled timeline) or the
  # window is too narrow -- flag it rather than reporting an impossible CP.
  minP <- min(pw[keep])
  list(CP = CP, Wprime = unname(coef(f)[1]), r2 = summary(f)$r.squared,
       n = length(keep), rng = max(t)/min(t), t = t, W = W,
       impossible = is.finite(CP) && is.finite(minP) && CP >= minP)
}
simulate_tanks <- function(power, cp, par) {
  n <- length(power); cP <- par$fP * par$Wprime; cG <- (1 - par$fP) * par$Wprime
  rP <- cP; rG <- cG; aer <- cp; resTot <- numeric(n); deficit <- numeric(n)
  AER_FALL <- 6
  kUp <- if (par$tauAer > 0) 1 - exp(-1 / par$tauAer) else 1
  kDn <- if (par$tauAer > 0) 1 - exp(-1 / (par$tauAer * AER_FALL)) else 1
  bG <- 1 - exp(-1 / par$tauG)
  for (i in seq_len(n)) {
    p <- power[i]
    if (par$tauAer > 0) {                     # sticky aerobic, floored; below CP aerobic covers demand
      tgt <- min(p, cp); aer <- aer + (tgt - aer) * (if (tgt > aer) kUp else kDn)
      aer <- max(0.5 * cp, min(cp, aer)); supply <- if (p > cp) aer else p
    } else supply <- cp
    delta <- p - supply
    if (delta > 0) {
      need <- delta
      takeP <- min(need, rP, par$pPmax); rP <- rP - takeP; need <- need - takeP
      takeG <- min(need, rG);            rG <- rG - takeG; need <- need - takeG
      deficit[i] <- need
    } else {
      tauPeff <- par$tauP * (1 + par$fatK * (1 - rG / cG)); rP <- rP + par$eta * (cP - rP) * (1 - exp(-1 / tauPeff))
      lt1 <- par$lt1Frac * cp; if (p < lt1) rG <- rG + ((lt1 - p) / lt1) * (cG - rG) * bG
    }
    rP <- max(0, min(cP, rP)); rG <- max(0, min(cG, rG)); resTot[i] <- rP + rG
  }
  list(total = resTot, deficit = deficit)
}
suggest_marks <- function(power, cp, base) {
  s <- simulate_tanks(power, cp, base); tot <- s$total; n <- length(tot)
  cand <- c(which.min(tot), n); lo <- which(tot[-c(1, n)] < 0.20 * base$Wprime) + 1
  if (length(lo)) cand <- c(cand, lo[c(TRUE, diff(lo) > 30)]); sort(unique(cand))
}
ride_diag <- function(power, cp, base) {
  r <- rle(power > cp); ends <- cumsum(r$lengths); starts <- ends - r$lengths + 1L
  bouts <- which(r$values & r$lengths >= 5); nb <- length(bouts); mean_rec <- NA_real_; refill <- NA_real_
  tot <- simulate_tanks(power, cp, base)$total; Wp <- base$Wprime
  margin <- min(tot) / Wp                        # lowest reserve reached, as share of W'
  if (nb >= 2) {
    gaps <- numeric(nb-1); rf <- numeric(nb-1)
    for (k in seq_len(nb-1)) { b1 <- bouts[k]; b2 <- bouts[k+1]; gaps[k] <- starts[b2]-ends[b1]
      after <- tot[ends[b1]]; before <- tot[starts[b2]]; rf[k] <- (before-after)/max(1e-6, Wp-after) }
    mean_rec <- mean(gaps); refill <- median(pmax(0, pmin(1, rf)))
  }
  list(n_bouts = nb, mean_rec_s = mean_rec, refill = refill, margin = margin)
}
ride_flag <- function(dg, fit) {
  fl <- character(0)
  if (!is.null(fit) && isTRUE(fit$submax)) fl <- c(fl, "submax-weak")
  if (!is.null(fit) && fit$conv != 0) fl <- c(fl, "no-converge")
  if (is.na(dg$n_bouts) || dg$n_bouts < 3) fl <- c(fl, "few-bouts")
  # A submaximal set is *meant* to leave margin, so "rest-too-long" doesn't apply.
  if (!is.na(dg$refill) && dg$refill > 0.7 && !(!is.null(fit) && isTRUE(fit$submax))) fl <- c(fl, "rest-too-long")
  if (!is.null(fit) && !isTRUE(fit$submax) && fit$obj > 0.05) fl <- c(fl, "poor-fit")
  if (length(fl)) paste(fl, collapse = ";") else "ok"
}
fit_recovery <- function(power, cp, base, marks, submax = FALSE) {
  Wp <- base$Wprime; th0 <- c(base$fP, base$tauP, base$tauG, base$eta)
  obj <- function(th) { par <- base; par$fP <- th[1]; par$tauP <- th[2]; par$tauG <- th[3]; par$eta <- th[4]
    s <- simulate_tanks(power, cp, par); feas <- 5 * mean((s$deficit/Wp)^2)
    if (submax) {
      # Efforts were NOT to failure -> no reserve=0 anchor. Submaximal repeated bouts
      # only constrain recovery through feasibility (tanks never go negative) plus the
      # quasi-steady reserve the bouts settle into, which is weak; a small ridge prior
      # toward the starting values keeps the optimiser identifiable. Params from these
      # rides are flagged low-confidence rather than trusted like maximal anchors.
      feas + 0.02 * mean(((th - th0) / pmax(1e-6, th0))^2)
    } else feas + (if (length(marks)) mean((s$total[marks]/Wp)^2) else 0) }
  st <- optim(th0, obj, method = "L-BFGS-B",
              lower = c(0.10,5,60,0.30), upper = c(0.60,120,1800,1.00), control = list(maxit = 200))
  list(fP = st$par[1], tauP = st$par[2], tauG = st$par[3], eta = st$par[4],
       obj = st$value, conv = st$convergence, submax = submax)
}
fit_all_rides <- function(power_list, names, cp, base, anchors, interval_idx, submax_idx = integer(0)) {
  rows <- lapply(seq_along(power_list), function(i) {
    p <- power_list[[i]]; man <- anchors[[as.character(i)]]
    is_sub <- i %in% submax_idx; is_int <- (i %in% interval_idx) || is_sub
    if (is_sub) { m <- integer(0); src <- "submax (no reserve=0)" }        # not to failure -> no anchor
    else if (!is.null(man) && length(man)) { m <- man; src <- "manual" }
    else if (is_int) { m <- c(which.min(simulate_tanks(p, cp, base)$total), length(p)); src <- "interval-end" }
    else { m <- suggest_marks(p, cp, base); src <- "auto" }
    r <- try(fit_recovery(p, cp, base, m, submax = is_sub), silent = TRUE); if (inherits(r, "try-error")) return(NULL)
    dg <- ride_diag(p, cp, base)
    data.frame(file = names[i], type = if (is_sub) "submax" else if (is_int) "interval" else "variable",
               anchors = src, bouts = dg$n_bouts, rec_s = round(dg$mean_rec_s),
               refill = round(dg$refill, 2), margin = round(dg$margin, 2),
               fP = r$fP, tauP = r$tauP, tauG = r$tauG, eta = r$eta, obj = r$obj, conv = r$conv,
               flag = ride_flag(dg, r), stringsAsFactors = FALSE)
  })
  do.call(rbind, Filter(Negate(is.null), rows))
}

# ===========================================================================
ui <- page_sidebar(
  title = "Dual-Tank Parameter Estimator",
  theme = tank_theme,
  sidebar = sidebar(width = 330, title = "Controls",
    fileInput("files", "FIT files (rides / races / interval sets)", multiple = TRUE, accept = c(".fit", ".FIT")),
    verbatimTextOutput("read_txt"),
    actionButton("fitall", "Fit fP / tauP / tauG / eta", class = "btn-primary w-100"),
    # Secondary controls tucked into collapsed panels so the sidebar fits one screen.
    accordion(id = "opts", open = FALSE, class = "my-2",
      accordion_panel("CP & model", icon = NULL,
        sliderInput("cpwin", "CP fit window (min)", 1, 30, c(2, 12), 1),
        sliderInput("fP", "PCr share of W' (fP) start", 0.1, 0.6, 0.35, 0.01)),
      accordion_panel("Interval sets", icon = NULL, uiOutput("interval_pick")),
      accordion_panel("History (trends)", icon = NULL,
        fileInput("history", "History YAML", accept = c(".yaml", ".yml")))),
    radioButtons("agg", "Combine rides by", c("median", "best-fit"), inline = TRUE),
    hr(),
    downloadButton("dl_ciq", "Connect IQ settings (JSON)", class = "w-100"),
    downloadButton("dl_yaml", "Dated YAML reading", class = "w-100"),
    downloadButton("dl_pdf", "PDF report", class = "w-100")
  ),
  navset_card_tab(
    nav_panel("★ Guide", HTML(guide_html)),
    nav_panel("Power-duration", plotOutput("mmp_plot", height = 300), DT::dataTableOutput("mmp_tbl")),
    nav_panel("CP / W' fit", plotOutput("cp_plot", height = 300), verbatimTextOutput("cp_txt")),
    nav_panel("Anchor editor",
      layout_columns(col_widths = c(5, 3, 4),
        uiOutput("ride_pick"),
        div(actionButton("autoone", "Auto-suggest"), actionButton("clearone", "Clear")),
        verbatimTextOutput("anchor_txt")),
      verbatimTextOutput("diag_txt"),
      helpText("Click the trace to add a maximal/cracked anchor; click near one to remove it."),
      plotOutput("res_plot", height = 300, click = "res_click")),
    nav_panel("Recovery fit", DT::dataTableOutput("fit_tbl"), verbatimTextOutput("agg_txt")),
    nav_panel("App parameters", verbatimTextOutput("params"), htmlOutput("caveats")),
    nav_panel("Trends", plotOutput("trend_plot", height = 380), DT::dataTableOutput("trend_tbl"))
  )
)

# ===========================================================================
server <- function(input, output, session) {
  rv <- reactiveValues(fits = NULL, anchors = list())

  reads <- reactive({ req(input$files)
    res <- lapply(input$files$datapath, read_power)
    list(name = input$files$name,
         p    = lapply(res, `[[`, "p"),
         ok   = vapply(res, function(r) !is.null(r$p), logical(1)),
         n    = vapply(res, function(r) if (is.null(r$p)) 0L else length(r$p), integer(1)),
         reason = vapply(res, function(r) if (is.null(r$reason)) "" else r$reason, character(1))) })
  powers <- reactive({ r <- reads(); keep <- r$ok
    validate(need(any(keep), paste0("No readable power data. ",
      paste(sprintf("%s: %s", r$name[!keep], r$reason[!keep]), collapse = "; "))))
    list(p = r$p[keep], names = r$name[keep]) })
  output$read_txt <- renderText({ r <- reads()
    lines <- sprintf("%s  %s  (%s)", ifelse(r$ok, "✓", "✗"), r$name,
                     ifelse(r$ok, paste0(r$n, " s of power"), r$reason))
    paste(c(sprintf("%d/%d files loaded", sum(r$ok), length(r$ok)), lines), collapse = "\n") })
  mmp   <- reactive(data.frame(duration = DURATIONS, power = mmp_curve(powers()$p)))
  cpfit <- reactive(fit_cp(mmp()$duration, mmp()$power, input$cpwin[1]*60, input$cpwin[2]*60))
  base_par <- reactive({ f <- cpfit(); req(f); modifyList(DEFAULTS, list(Wprime = f$Wprime, fP = input$fP)) })
  interval_idx <- reactive(as.integer(input$intervalrides))
  submax_idx   <- reactive(as.integer(input$submaxrides))
  output$interval_pick <- renderUI({ pw <- powers(); ch <- setNames(seq_along(pw$p), pw$names)
    tagList(
      checkboxGroupInput("intervalrides", "Interval sets — efforts to failure (reserve → 0)", choices = ch),
      checkboxGroupInput("submaxrides", "Interval sets — submaximal (completed with margin)", choices = ch),
      helpText("Tick a submaximal set when the bouts were repeated but NOT all-out. The fit then uses only feasibility + recovery between bouts (no reserve = 0 anchor) and flags the result as low-confidence.")) })

  agg <- reactive({ df <- rv$fits; if (is.null(df)) return(NULL)
    good <- df[!grepl("no-converge|few-bouts|rest-too-long|submax-weak", df$flag), , drop = FALSE]
    constrained <- nrow(good) > 0; use <- if (constrained) good else df
    pick <- function(col) if (input$agg == "best-fit") use[[col]][which.min(use$obj)] else median(use[[col]])
    list(fP = pick("fP"), tauP = pick("tauP"), tauG = pick("tauG"), eta = pick("eta"),
         constrained = constrained, n_used = nrow(use),
         cv = c(fP = cv(use$fP), tauP = cv(use$tauP), tauG = cv(use$tauG), eta = cv(use$eta)),
         src = if (input$agg == "best-fit") paste("best-fit:", use$file[which.min(use$obj)]) else sprintf("median of %d rides", nrow(use))) })

  # ---- unified estimate table (value / source / uncertainty) ----
  est_table <- reactive({
    f <- cpfit(); req(f); m <- mmp(); a <- agg()
    p5 <- m$power[m$duration == 5]; pPmax <- if (is.finite(p5)) max(50, round(p5 - f$CP)) else DEFAULTS$pPmax
    cpWhy <- paste(c(if (isTRUE(f$impossible)) "CP above longest effort - check file/window", if (f$r2 < 0.95) "low R2", if (f$n < 3) "few efforts", if (f$rng < 5) "narrow durations"), collapse = ", ")
    recU <- is.null(a) || !a$constrained
    spread <- function(k) !is.null(a) && a$constrained && is.finite(a$cv[[k]]) && a$cv[[k]] > 0.3
    recWhy <- if (is.null(a)) "not fit (defaults)" else "rest too long / few bouts"
    src_rec <- if (is.null(a)) "default" else a$src
    val <- c(CP = round(f$CP), Wprime = round(f$Wprime), pPmax = pPmax,
             fP = round(if (is.null(a)) input$fP else a$fP, 2),
             tauP = round(if (is.null(a)) DEFAULTS$tauP else a$tauP),
             tauG = round(if (is.null(a)) DEFAULTS$tauG else a$tauG),
             eta = round(if (is.null(a)) DEFAULTS$eta else a$eta, 2),
             lt1Frac = DEFAULTS$lt1Frac, fatK = DEFAULTS$fatK, tauAer = DEFAULTS$tauAer)
    src <- c(CP = "best across files", Wprime = "best across files", pPmax = "best 5s - CP",
             fP = src_rec, tauP = src_rec, tauG = src_rec, eta = src_rec,
             lt1Frac = "default", fatK = "default", tauAer = "default")
    unc <- c(CP = nzchar(cpWhy), Wprime = nzchar(cpWhy), pPmax = (!is.finite(p5) || p5 < 1.4 * f$CP),
             fP = recU || spread("fP"), tauP = recU || spread("tauP"), tauG = recU || spread("tauG"),
             eta = recU || spread("eta"), lt1Frac = TRUE, fatK = TRUE, tauAer = TRUE)
    note <- c(CP = cpWhy, Wprime = cpWhy, pPmax = "no clear maximal sprint",
              fP = if (recU) recWhy else "wide spread across rides", tauP = if (recU) recWhy else "wide spread across rides",
              tauG = if (recU) recWhy else "wide spread across rides", eta = if (recU) recWhy else "wide spread across rides",
              lt1Frac = "needs a threshold test", fatK = "needs repeated-bout data", tauAer = "needs onset-kinetics data")
    ord <- names(PARAM_DESC)
    data.frame(param = ord, value = as.numeric(val[ord]), source = src[ord],
               uncertain = as.logical(unc[ord]), note = note[ord], stringsAsFactors = FALSE)
  })

  # ---- history / readings over time ----
  history_data <- reactive({ if (is.null(input$history)) return(NULL)
    y <- try(yaml::read_yaml(input$history$datapath), silent = TRUE)
    if (inherits(y, "try-error") || is.null(y$readings)) NULL else y$readings })
  current_reading <- reactive({ et <- est_table(); req(et)
    d <- data.frame(date = as.character(Sys.Date()), stringsAsFactors = FALSE)
    for (k in PARAMS) d[[k]] <- et$value[match(k, et$param)]; d })
  readings_df <- reactive({ cur <- current_reading(); hist <- history_data(); rows <- list()
    if (!is.null(hist)) for (r in hist) { d <- data.frame(date = as.character(r$date), stringsAsFactors = FALSE)
      for (k in PARAMS) d[[k]] <- if (!is.null(r[[k]])) as.numeric(r[[k]]) else NA_real_; rows[[length(rows)+1]] <- d }
    rows[[length(rows)+1]] <- cur; df <- do.call(rbind, rows); df$date <- as.Date(df$date); df[order(df$date), ] })

  # ---- ggplot builders (reused by renderPlot AND the PDF export) ----
  mmp_gg <- reactive({ m <- mmp(); f <- cpfit()
    g <- ggplot(subset(m, is.finite(power)), aes(duration, power)) + geom_line(colour = "grey60") +
      geom_point(size = 2) + scale_x_log10() + labs(x = "duration (s, log)", y = "best mean power (W)", title = "Mean-maximal power") + gg_tank()
    if (!is.null(f)) g <- g + geom_line(data = data.frame(duration = (tt <- 10^seq(log10(30), log10(3600), length.out = 200)),
                                  power = f$CP + f$Wprime / tt), colour = "#B44DFF", linewidth = 1) +
      geom_hline(yintercept = f$CP, linetype = 2, colour = "#37E85A"); g })
  cp_gg <- reactive({ f <- cpfit(); if (is.null(f)) return(NULL)
    ggplot(data.frame(t = f$t, W = f$W), aes(t, W)) + geom_point(size = 2) +
      geom_abline(intercept = f$Wprime, slope = f$CP, colour = "#B44DFF", linewidth = 1) +
      labs(x = "time (s)", y = "work (J) = CP*t + W'", title = "CP / W' work-time fit") + gg_tank() })
  trend_gg <- reactive({ df <- readings_df(); if (nrow(df) < 1) return(NULL)
    long <- do.call(rbind, lapply(PARAMS, function(k) data.frame(date = df$date, param = k, value = df[[k]])))
    long$param <- factor(long$param, levels = PARAMS)
    ggplot(long, aes(date, value)) + geom_line(colour = "#B44DFF") + geom_point(size = 1.6) +
      facet_wrap(~param, scales = "free_y") + labs(x = NULL, y = NULL, title = "Estimates over time") + gg_tank() })

  output$mmp_plot <- renderPlot(mmp_gg(), bg = "transparent")
  output$mmp_tbl  <- DT::renderDataTable(DT::datatable(transform(mmp(), power = round(power)), rownames = FALSE, options = list(pageLength = 8, dom = "tp")))
  output$cp_plot  <- renderPlot({ g <- cp_gg(); validate(need(!is.null(g), "Need >=2 efforts in the window.")); g }, bg = "transparent")
  output$cp_txt   <- renderText({ f <- cpfit(); req(f)
    paste0(
      sprintf("CP = %.0f W   W' = %.0f J   R^2 = %.3f (n = %d efforts, %.1fx duration range)", f$CP, f$Wprime, f$r2, f$n, f$rng),
      if (isTRUE(f$impossible)) "\n⚠ CP is at/above the power you held for the longest effort in the window -- physically impossible. Usually a corrupt power-duration curve (odd FIT parse) or too narrow a fit window; widen the CP window or check the file." else "") })

  # ---- anchor editor ----
  output$ride_pick <- renderUI({ pw <- powers(); selectInput("ride", "Ride", choices = setNames(seq_along(pw$p), pw$names)) })
  ride_idx   <- reactive({ req(input$ride); as.integer(input$ride) })
  ride_power <- reactive({ powers()$p[[ride_idx()]] })
  observeEvent(input$res_click, { p <- ride_power(); req(p); x <- round(input$res_click$x); if (x < 1 || x > length(p)) return()
    key <- as.character(ride_idx()); cur <- rv$anchors[[key]]; if (is.null(cur)) cur <- integer(0)
    tol <- max(5, round(length(p) * 0.01)); near <- which(abs(cur - x) <= tol)
    rv$anchors[[key]] <- if (length(near)) cur[-near] else sort(c(cur, x)) })
  observeEvent(input$autoone, { f <- cpfit(); p <- ride_power(); req(f, p); rv$anchors[[as.character(ride_idx())]] <- suggest_marks(p, f$CP, base_par()) })
  observeEvent(input$clearone, { rv$anchors[[as.character(ride_idx())]] <- integer(0) })
  output$anchor_txt <- renderText({ a <- rv$anchors[[as.character(ride_idx())]]
    if (is.null(a) || !length(a)) "no manual anchors (auto/interval-end will be used)" else paste("anchors (s):", paste(a, collapse = ", ")) })
  output$diag_txt <- renderText({ f <- cpfit(); p <- ride_power(); req(f, p); dg <- ride_diag(p, f$CP, base_par())
    warn <- if (!is.na(dg$refill) && dg$refill > 0.7) "  <<= rest too long: does NOT constrain recovery" else ""
    sprintf("bouts>CP: %d | mean recovery: %s s | between-bout refill: %s%s", dg$n_bouts,
            ifelse(is.na(dg$mean_rec_s), "-", round(dg$mean_rec_s)), ifelse(is.na(dg$refill), "-", paste0(round(100*dg$refill), "%")), warn) })
  output$res_plot <- renderPlot({ f <- cpfit(); p <- ride_power(); req(f, p)
    par <- base_par(); a <- agg(); if (!is.null(a)) par <- modifyList(par, a[c("fP","tauP","tauG","eta")])
    s <- simulate_tanks(p, f$CP, par); df <- data.frame(t = seq_along(p), pct = 100 * s$total / par$Wprime)
    anch <- rv$anchors[[as.character(ride_idx())]]
    g <- ggplot(df, aes(t, pct)) + geom_line(colour = "#B44DFF") + ylim(0, 100) +
      labs(x = "time (s)", y = "total reserve (% W')", title = if (is.null(a)) "default params - click to anchor" else "fitted params - click to anchor") + gg_tank()
    if (!is.null(anch) && length(anch)) g <- g + geom_vline(xintercept = anch, colour = "#FF0000", linetype = 2); g }, bg = "transparent")

  # ---- fit + results ----
  observeEvent(input$fitall, { f <- cpfit(); pw <- powers(); req(f); rv$fits <- fit_all_rides(pw$p, pw$names, f$CP, base_par(), rv$anchors, interval_idx(), submax_idx()) })
  output$fit_tbl <- DT::renderDataTable({ validate(need(!is.null(rv$fits), "Set anchors / mark interval sets, then 'Fit ... on every ride'."))
    d <- rv$fits; num <- c("fP","tauP","tauG","eta","obj"); d[num] <- lapply(d[num], round, 3)
    dt <- DT::datatable(d, rownames = FALSE, options = list(pageLength = 10, dom = "tp"))
    DT::formatStyle(dt, "flag", target = "row", backgroundColor = DT::styleEqual("ok", "white", default = "#fff3cd")) })
  output$agg_txt <- renderText({ a <- agg(); if (is.null(a)) return("")
    u <- if (!a$constrained) "  [HIGH UNCERTAINTY: no ride constrained recovery]" else ""
    sprintf("Chosen (%s):  fP = %.2f  tauP = %.0f s  tauG = %.0f s  eta = %.2f%s", a$src, a$fP, a$tauP, a$tauG, a$eta, u) })

  output$params <- renderText({ et <- est_table(); req(et)
    lines <- vapply(seq_len(nrow(et)), function(i) {
      base <- sprintf("%-8s = %s   # %s", et$param[i], format(et$value[i]), et$source[i])
      if (et$uncertain[i]) paste0(base, "   <<= uncertain: ", et$note[i]) else base }, character(1))
    paste(lines, collapse = "\n") })
  output$caveats <- renderUI(HTML(paste0(
    "<b>CP, W', pPmax</b> take the best across every file. <b>fP, tauP, tauG, eta</b> are fit per ride, then combined. ",
    "<b>Interval sets</b> only constrain recovery when between-bout refill is low (short rest); &gt;70% refill is flagged. ",
    "Lines marked <i>uncertain</i> are weakly constrained. Export a dated YAML to build history, then re-supply it for trends.")))

  # ---- trends ----
  output$trend_plot <- renderPlot({ g <- trend_gg(); validate(need(!is.null(g), "Upload rides (and optionally a history YAML).")); g }, bg = "transparent")
  output$trend_tbl  <- DT::renderDataTable(DT::datatable(readings_df(), rownames = FALSE, options = list(pageLength = 10, dom = "tp")))

  # ---- exports ----
  output$dl_ciq <- downloadHandler(
    filename = function() paste0("dualtank_ciq_settings_", Sys.Date(), ".json"),
    content = function(file) {
      et <- est_table(); v <- setNames(et$value, et$param)
      keys <- c("CP","Wprime","fP","pPmax","tauP","tauG","lt1Frac","eta","fatK","tauAer")   # match properties.xml
      body <- paste(vapply(keys, function(k) sprintf('  "%s": %s', k, format(v[[k]], trim = TRUE)), character(1)), collapse = ",\n")
      writeLines(c("{", body, "}"), file)
    })

  output$dl_yaml <- downloadHandler(
    filename = function() paste0("dualtank_readings_", Sys.Date(), ".yaml"),
    content = function(file) {
      cur <- current_reading(); et <- est_table()
      newr <- as.list(cur); newr$flags <- et$param[et$uncertain]
      readings <- c(history_data(), list(newr))
      yaml::write_yaml(list(readings = readings), file) })

  output$dl_pdf <- downloadHandler(
    filename = function() paste0("dualtank_report_", Sys.Date(), ".pdf"),
    content = function(file) {
      et <- est_table()
      pdf(file, width = 8.5, height = 11, bg = "#EDE0C8"); on.exit(if (dev.cur() > 1) dev.off())
      # page 1 — explanations (dark ink on parchment)
      op <- par(mar = c(0,0,0,0)); plot(NA, xlim = c(0,1), ylim = c(0,1), axes = FALSE, xlab = "", ylab = "")
      rect(-0.03, -0.03, 1.03, 1.03, border = "#8a6a2a", lwd = 3, xpd = NA)
      text(0, 0.985, "Dual-Tank Parameter Report", adj = c(0,1), cex = 1.7, font = 2, col = "#6b4f2a", family = "serif")
      text(0, 0.95, paste("Date:", Sys.Date()), adj = c(0,1), cex = 0.9, col = "#3a2817", family = "serif")
      segments(0, 0.935, 1, 0.935, col = "#8a6a2a", lwd = 1)
      y <- 0.90
      for (i in seq_len(nrow(et))) {
        p <- et$param[i]; unc <- et$uncertain[i]
        status <- if (unc) paste0("UNCERTAIN - ", et$note[i]) else "well constrained"
        text(0, y, sprintf("%-8s = %s    [%s]    %s", p, format(et$value[i]), et$source[i], status),
             adj = c(0,1), cex = 0.82, family = "mono", col = if (unc) "#8a2a12" else "#241a10"); y <- y - 0.027
        for (d in strwrap(PARAM_DESC[[p]], width = 96)) { text(0.03, y, d, adj = c(0,1), cex = 0.72, col = "#5a4a30", family = "serif"); y <- y - 0.021 }
        y <- y - 0.007
      }
      par(op)
      # page 2+ — plots on parchment
      print(mmp_gg() + gg_report()); g <- cp_gg(); if (!is.null(g)) print(g + gg_report())
      tg <- trend_gg(); if (!is.null(tg)) print(tg + gg_report())
    })
}

shinyApp(ui, server)
