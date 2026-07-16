test_that("best_mean_power rolling best; d>length -> NA", {
  p <- c(100,200,300,100)
  expect_equal(best_mean_power(p, 2), 250)
  expect_equal(best_mean_power(p, 4), 175)
  expect_true(is.na(best_mean_power(p, 5)))
})
test_that("mmp_curve best-of-all across a list", {
  m <- mmp_curve(list(c(100,400,100), c(300,300,300)), durations = c(1,3))
  expect_equal(m[1], 400)
  expect_equal(m[2], 300)
})
