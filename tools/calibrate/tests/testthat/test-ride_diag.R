# #86 Phase 1: ride_diag reports the short-recovery-valley fraction, and ride_flag raises a
# "short-recovery" flag for the sub-minute-recovery intermittent regime the model is not validated
# for (hard CP cap -> anaerobic over-drain). Warn-only: flagged + surfaced, not excluded from agg.
base <- modifyList(DEFAULTS, list(Wprime = 20000))
CP <- 250

test_that("short_rec_frac is the fraction of inter-bout valleys shorter than SHORT_REC_S", {
  # 5 x [30 s @ 300 W / 15 s @ 100 W]: four 15 s valleys, all < 45 s -> frac 1.0, 5 bouts.
  short <- rep(c(rep(300, 30), rep(100, 15)), 5)
  dg <- ride_diag(short, CP, base)
  expect_equal(dg$n_bouts, 5)
  expect_equal(dg$short_rec_frac, 1)

  # 4 x [30 s @ 300 W / 180 s @ 100 W]: three 180 s valleys, none < 45 s -> frac 0.
  long <- rep(c(rep(300, 30), rep(100, 180)), 4)
  dgl <- ride_diag(long, CP, base)
  expect_equal(dgl$short_rec_frac, 0)

  # < 2 bouts -> undefined (NA), never a spurious 0.
  expect_true(is.na(ride_diag(rep(100, 60), CP, base)$short_rec_frac))
})

test_that("ride_flag raises short-recovery only in the short-valley intermittent regime", {
  short <- rep(c(rep(300, 30), rep(100, 15)), 5)
  expect_match(ride_flag(ride_diag(short, CP, base), NULL), "short-recovery")

  # Long recoveries: not short-recovery (may be rest-too-long, which is a different flag).
  long <- rep(c(rep(300, 30), rep(100, 180)), 4)
  expect_false(grepl("short-recovery", ride_flag(ride_diag(long, CP, base), NULL)))

  # < 3 bouts is "few-bouts", never "short-recovery" (mutually exclusive).
  two <- rep(c(rep(300, 30), rep(100, 15)), 2)
  fl2 <- ride_flag(ride_diag(two, CP, base), NULL)
  expect_false(grepl("short-recovery", fl2))
  expect_match(fl2, "few-bouts")
})

test_that("detection is per-valley, not a mean_rec_s threshold (the review's requirement)", {
  # Valleys [15, 15, 120] s: mean = 50 s (> 45, would PASS a mean test) but 2/3 are short, so the
  # per-valley fraction (0.67 >= 0.5) still flags the over-drained short-recovery subset.
  mixed <- c(rep(300, 30), rep(100, 15), rep(300, 30), rep(100, 15), rep(300, 30), rep(100, 120), rep(300, 30))
  dg <- ride_diag(mixed, CP, base)
  expect_equal(dg$n_bouts, 4)
  expect_gt(dg$mean_rec_s, SHORT_REC_S)            # a bare mean_rec_s test would miss it
  expect_equal(dg$short_rec_frac, 2 / 3)
  expect_match(ride_flag(dg, NULL), "short-recovery")
})
