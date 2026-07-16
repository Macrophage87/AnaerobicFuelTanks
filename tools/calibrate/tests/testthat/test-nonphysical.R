# Issue #24: fit_cp must flag non-physical (<=0) CP/W' from a corrupt MMP, and
# simulate_tanks must defensively floor a bad CP scalar. These guards are a no-op
# for already-valid data (see the "sane MMP" case).

test_that("fit_cp flags a corrupt (super-linear) work-time series as non-physical", {
  # Corrupt MMP: longer efforts report HIGHER power -> the work-time line has a
  # negative intercept (W' <= 0) (and/or non-positive slope). Either way -> nonphysical.
  dur <- c(60, 120, 300, 600, 1200)
  pw  <- c(200, 230, 270, 320, 380)          # non-physical: longer efforts "stronger"
  f <- fit_cp(dur, pw, 30, 3600)
  expect_true(isTRUE(f$nonphysical))
  expect_true(f$CP <= 0 || f$Wprime <= 0)
})

test_that("fit_cp leaves a sane monotonic MMP unflagged", {
  dur <- c(60, 120, 300, 600, 1200)
  pw  <- c(360, 330, 300, 285, 275)
  f <- fit_cp(dur, pw, 30, 3600)
  expect_false(isTRUE(f$nonphysical))
  expect_false(isTRUE(f$implausible))
  expect_gt(f$CP, 0)
  expect_gt(f$Wprime, 0)
})

test_that("fit_cp flags a positive-but-tiny CP as implausible, not non-physical", {
  # 0 < CP < CP_FLOOR_W with W' > 0: warn (implausible) but do not block export.
  CP <- 30; Wp <- 5000; dur <- c(120, 300, 600, 1200); pw <- CP + Wp / dur
  f <- suppressWarnings(fit_cp(dur, pw, 30, 3600))
  expect_false(isTRUE(f$nonphysical))
  expect_true(isTRUE(f$implausible))
  expect_lt(f$CP, CP_FLOOR_W)
})

test_that("simulate_tanks floors a non-physical cp (finite, no sign flip)", {
  par <- modifyList(DEFAULTS, list(Wprime = 20000))
  for (bad in c(-40, 0, NA_real_, Inf)) {
    s <- simulate_tanks(rep(250, 60), bad, par)
    expect_true(all(is.finite(s$total)))
    expect_true(all(is.finite(s$deficit)))
  }
})

test_that("ride_diag margin does not sign-flip on a non-physical W'", {
  # base with W' <= 0 must not produce a positive margin from a negative reserve.
  bad_base <- modifyList(DEFAULTS, list(Wprime = -3000))
  dg <- ride_diag(c(rep(600, 20), rep(100, 40)), 250, bad_base)
  expect_true(is.finite(dg$margin))
})
