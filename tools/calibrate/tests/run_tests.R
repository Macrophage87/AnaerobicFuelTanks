#!/usr/bin/env Rscript
# Run the calibration-tool unit tests. From the repo root:
#   Rscript tools/calibrate/tests/run_tests.R
# Requires ONLY base R + testthat (no FITfileR / shiny / network / device).
here <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
sys.source(file.path(here, "..", "R", "model.R"), envir = globalenv())
suppressPackageStartupMessages(library(testthat))
test_dir(file.path(here, "testthat"), stop_on_failure = TRUE)
