test_that("fit_cp recovers known CP and W'", {
  CP <- 250; Wp <- 20000; dur <- c(120,180,240,300,600); pw <- CP + Wp/dur
  f <- suppressWarnings(fit_cp(dur, pw, 120, 600))  # exact linear fit -> summary.lm perfect-fit note
  expect_false(is.null(f))
  expect_equal(f$CP, CP, tolerance = 1e-6)
  expect_equal(f$Wprime, Wp, tolerance = 1e-6)
  expect_gt(f$r2, 0.999)
  expect_false(f$impossible)
})
test_that("fit_cp window filtering + <2 in-window -> NULL", {
  dur <- c(30,120,300,3600); pw <- 250 + 20000/dur
  expect_equal(fit_cp(dur, pw, 100, 600)$n, 2)   # only 120 & 300 in window
  expect_null(fit_cp(dur, pw, 130, 200))         # zero durations in window -> NULL
})
test_that("fit_cp flags impossible when CP >= min in-window power", {
  dur <- c(60,120,180); pw <- c(300,400,500)     # longer effort higher power => CP inflated
  expect_true(fit_cp(dur, pw, 30, 600)$impossible)
})
