test_that("as_num coerces POSIXct, numeric-ish strings, and non-numeric", {
  expect_equal(as_num(as.POSIXct(1000, origin = "1970-01-01", tz = "UTC")), 1000)
  expect_equal(as_num(c("100", "200")), c(100, 200))
  expect_true(all(is.na(as_num(c("x", "y")))))   # exercises the as.character() fallback branch
})
