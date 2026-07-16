# Coverage for read_power()'s multi-sub-table merge — the highest-risk extracted
# path (blindly concatenating FITfileR sub-tables scrambles the time axis and
# inflates long-duration MMP). FITfileR is NOT installed; we mock its entry points
# (readFitFile/records) in the global env, where model.R's read_power resolves them.

test_that("read_power merges interleaved sub-tables onto an ordered 1 Hz timeline", {
  readFitFile <<- function(path) "FAKE"
  records <<- function(ff) list(
    data.frame(timestamp = c(1000, 1002), power = c(100, 120)),  # gap at 1001
    data.frame(timestamp = c(1001),       power = c(110)),       # a later sub-table fills it
    data.frame(timestamp = c(1000, 1001), cadence = c(80, 82))   # no power -> skipped
  )
  on.exit(rm(readFitFile, records, envir = globalenv()), add = TRUE)
  out <- read_power(tempfile())
  expect_null(out$reason)
  expect_equal(out$p, c(100, 110, 120))   # time-ordered, NOT concatenated (100,120,110)
})

test_that("read_power falls back to read_power_raw when records() has no power", {
  fit <- make_fit(list(list(ts = 5000, pw = 210), list(ts = 5001, pw = 220)))
  readFitFile <<- function(path) "FAKE"
  records <<- function(ff) list(data.frame(timestamp = c(5000, 5001), cadence = c(80, 81)))
  on.exit(rm(readFitFile, records, envir = globalenv()), add = TRUE)
  out <- read_power(fit)                    # no power field -> base-R decoder reads the real bytes
  expect_null(out$reason)
  expect_equal(out$p, c(210, 220))
})

test_that("read_power reports a reason when neither path yields power", {
  bad <- tempfile(); writeBin(as.raw(rep(0L, 8)), bad)   # too small for the raw decoder
  readFitFile <<- function(path) stop("unreadable")
  on.exit(rm(readFitFile, envir = globalenv()), add = TRUE)
  out <- read_power(bad)
  expect_null(out$p)
  expect_false(is.null(out$reason))
})
