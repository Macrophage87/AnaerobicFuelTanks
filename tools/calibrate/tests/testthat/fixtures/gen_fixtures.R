# Regenerate golden fixtures that pin the CURRENT model output. Run from repo root:
#   Rscript tools/calibrate/tests/testthat/fixtures/gen_fixtures.R
# When the model is INTENTIONALLY changed, re-run this in the SAME commit and note it.
here <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
sys.source(file.path(here, "..", "..", "..", "R", "model.R"), envir = environment())
base <- modifyList(DEFAULTS, list(Wprime = 20000)); cp <- 250
traces <- list(
  sprint = c(rep(800, 5), rep(100, 60)),
  supra  = rep(300, 180)
)
for (nm in names(traces)) {
  s <- simulate_tanks(traces[[nm]], cp, base)
  df <- data.frame(sec = seq_along(s$total), total = s$total, deficit = s$deficit)
  write.csv(df, file.path(here, sprintf("sim_%s.csv", nm)), row.names = FALSE)
  cat("wrote sim_", nm, ".csv (", nrow(df), " rows)\n", sep = "")
}
