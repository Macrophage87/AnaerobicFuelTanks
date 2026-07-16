base_par <- function(...) modifyList(modifyList(DEFAULTS, list(Wprime = 20000)), list(...))
test_that("below-CP steady ride: reserves ~full, no deficit", {
  s <- simulate_tanks(rep(150,300), 250, base_par())
  expect_true(all(s$deficit == 0))
  expect_gt(min(s$total), 0.98 * 20000)
})
test_that("supra-CP sprint drains then recovers", {
  s <- simulate_tanks(c(rep(800,5), rep(100,120)), 250, base_par())
  expect_lt(s$total[5], 0.9 * 20000)
  expect_gt(s$total[125], s$total[5])
})
test_that("fP=0 and fP=1 do not divide-by-zero; total finite", {
  for (fp in c(0,1)) {
    s <- simulate_tanks(c(rep(600,20), rep(100,40)), 250, base_par(fP = fp))
    expect_true(all(is.finite(s$total)))
  }
})
test_that("tiny pPmax banks a deficit that decays under recovery", {
  s <- simulate_tanks(c(rep(900,10), rep(100,60)), 250, base_par(pPmax = 5))
  expect_gt(max(s$deficit), 0)
  expect_gt(s$total[70], s$total[10])
})
test_that("golden: matches committed fixture (regression pin)", {
  for (nm in c("sprint","supra")) {
    fx <- read.csv(test_path("fixtures", sprintf("sim_%s.csv", nm)))
    trace <- if (nm == "sprint") c(rep(800,5), rep(100,60)) else rep(300,180)
    s <- simulate_tanks(trace, 250, base_par())
    expect_equal(s$total,   fx$total,   tolerance = 1e-9)
    expect_equal(s$deficit, fx$deficit, tolerance = 1e-9)
  }
})
