# Δ1 (single fit-error channel): a failed fit -- whether fit_recovery RETURNS status=="error"
# or any per-ride step THROWS -- must become exactly ONE bare "fit-error" row, so
# n_failed = sum(df$flag == "fit-error") is exact and every row shares one 15-column schema.
test_that("fit_all_rides emits a single bare 'fit-error' row for an unfittable ride", {
  base <- modifyList(DEFAULTS, list(Wprime = 20000))
  bad  <- c(rep(400, 60), NaN, rep(120, 60))   # NaN power -> non-finite objective -> optim errors
  df <- fit_all_rides(list(bad), "bad.fit", 250, base, list(), integer(0))
  expect_equal(nrow(df), 1L)
  expect_identical(df$flag, "fit-error")        # bare flag -> `== "fit-error"` counts it
  expect_identical(df$status, "error")
  expect_true(is.infinite(df$obj))              # Inf sentinel, never NA (ride_flag reads obj bare)
  expect_false(is.na(df$err))
  expect_true(is.na(df$fP))
})

test_that("fit_all_rides mixes good + failed rides under one 15-column schema", {
  base <- modifyList(DEFAULTS, list(Wprime = 20000))
  good <- rep(c(rep(400, 20), rep(120, 40)), 5)
  bad  <- c(rep(400, 60), NaN, rep(120, 60))
  df <- fit_all_rides(list(good, bad), c("good.fit", "bad.fit"), 250, base, list(), integer(0))
  expect_equal(nrow(df), 2L)                    # rbind succeeded => identical columns on both rows
  expect_setequal(df$status, c("ok", "error"))
  expect_equal(sum(df$flag == "fit-error"), 1L)
  expect_true(all(c("status", "err", "flag") %in% names(df)))
  expect_false("eta" %in% names(df))            # eta dropped as a fitted column
})

# fit_cp returns r2 = NA for < 3 efforts (so a 2-point "perfect" lm can't read as confident).
test_that("fit_cp yields NA r2 below 3 efforts, real r2 at >= 3", {
  dur <- c(120, 300, 600); pw <- 250 + 20000 / dur
  expect_true(is.na(fit_cp(dur[1:2], pw[1:2], 60, 900)$r2))
  expect_false(is.na(suppressWarnings(fit_cp(dur, pw, 60, 900))$r2))
})
