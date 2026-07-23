# #87: mmp_src() gives per-duration provenance (which file supplied each best), and fit_cp() flags a
# CP/W' fit whose in-window efforts all trace to ONE file (soft, single-session W'). Parity-inert.

test_that("mmp_src returns the argmax file index per duration, NA when no file is long enough", {
  hi <- rep(400, 200); lo <- rep(300, 200)
  expect_equal(mmp_src(list(hi, lo), durations = c(30, 120)), c(1L, 1L))   # file 1 dominates
  expect_equal(mmp_src(list(lo, hi), durations = c(30, 120)), c(2L, 2L))   # file 2 dominates
  # a duration longer than every file -> NA index (not a spurious 1).
  expect_equal(mmp_src(list(rep(400, 100), rep(300, 100)), durations = c(30, 300)), c(1L, NA_integer_))
})

test_that("fit_cp flags single-session only when every in-window effort is from one file", {
  dur <- c(60, 120, 300, 600, 1200); pw <- c(500, 420, 360, 330, 300)
  # window 120-720 keeps durations 120/300/600. All from file 1 -> single-session.
  f_one <- fit_cp(dur, pw, 120, 720, src = c(2L, 1L, 1L, 1L, 2L))
  expect_true(f_one$single_session)
  # in-window bests split across files -> not single-session.
  f_mix <- fit_cp(dur, pw, 120, 720, src = c(2L, 1L, 2L, 1L, 2L))
  expect_false(f_mix$single_session)
  # no provenance supplied -> FALSE (never a spurious flag).
  f_nosrc <- fit_cp(dur, pw, 120, 720)
  expect_false(f_nosrc$single_session)
})
