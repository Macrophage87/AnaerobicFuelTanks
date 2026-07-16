# Generate the R-reference fixtures for the R <-> Monkey C model cross-check (issue #27,
# part C). The R implementation (tools/calibrate/R/model.R :: simulate_tanks) is the
# trustworthy reference — it is guarded by the required r-test testthat suite. This script
# freezes its per-second per-tank output (rP, rG, pctP) for a few canonical power traces so
# the Python mirror of the Monkey C TankModel (tools/crosscheck/tank_model.py) can be
# asserted equal to it in CI WITHOUT a Connect IQ SDK / simulator.
#
# Run from the repo root (re-run in the SAME commit whenever the model is intentionally
# changed on either side):
#   Rscript tools/crosscheck/gen_fixtures.R
#
# Outputs (tools/crosscheck/fixtures/):
#   config.csv          the EXACT settings both sides must use (param,value). The two
#                       codebases embed DIFFERENT fallback defaults (R eta=1.00/tauP=27/
#                       tauG=470 vs MC 0.80/22/360), so the cross-check must feed both the
#                       same explicit values — Python reads them straight from this file.
#   <trace>.csv         sec,power,rP,rG,pctP per second (rP/rG recorded AFTER the clamp).
#
# Dependency-free (base R only: no jsonlite) so it runs on the stock r-base-core CI image.

here <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
sys.source(file.path(here, "..", "calibrate", "R", "model.R"), envir = environment())

outdir <- file.path(here, "fixtures")
dir.create(outdir, showWarnings = FALSE, recursive = TRUE)

# ---- Canonical config: the R defaults, made explicit. BOTH sides use exactly this. ----
cp  <- 250
par <- modifyList(DEFAULTS, list(Wprime = 20000))
cP  <- par$fP * par$Wprime   # PCr capacity (J), for pctP

# Written in the fixed order the Monkey C TankModel.configure() array expects, plus cp.
config <- c(
  cp      = cp,
  Wprime  = par$Wprime,
  fP      = par$fP,
  pPmax   = par$pPmax,
  tauP    = par$tauP,
  tauG    = par$tauG,
  lt1Frac = par$lt1Frac,
  eta     = par$eta,
  fatK    = par$fatK,
  gFat    = par$gFat,
  tauAer  = par$tauAer,
  tauOn   = par$tauOn
)
write.csv(data.frame(param = names(config), value = as.numeric(config)),
          file.path(outdir, "config.csv"), row.names = FALSE)
cat("wrote config.csv\n")

# ---- Canonical traces: cover depletion, refill, sustained supra-CP, and intervals. ----
traces <- list(
  sprint   = c(rep(800, 5), rep(100, 60)),                 # hard punch then easy spin
  supra    = rep(300, 180),                                # sustained over CP (GLY bleeds)
  interval = rep(c(rep(400, 20), rep(120, 40)), 8)         # sawtooth
)

for (nm in names(traces)) {
  power <- traces[[nm]]
  s <- simulate_tanks(power, cp, par)
  df <- data.frame(
    sec   = seq_along(power),
    power = power,
    rP    = s$rP,
    rG    = s$rG,
    pctP  = 100 * s$rP / cP
  )
  write.csv(df, file.path(outdir, sprintf("%s.csv", nm)), row.names = FALSE)
  cat("wrote ", nm, ".csv (", nrow(df), " rows)\n", sep = "")
}
