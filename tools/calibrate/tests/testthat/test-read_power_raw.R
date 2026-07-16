test_that("base-R FIT decoder: LE decode + invalid-power sentinel skipped", {
  f <- make_fit(list(list(ts=1000,pw=250), list(ts=1001,pw=300),
                     list(ts=1002,pw=65535), list(ts=1003,pw=200)))  # 65535 = invalid
  expect_equal(read_power_raw(f), c(250,300,0,200))  # 1002 skipped -> zero-filled
})
test_that("developer-field definition bytes are skipped by size", {
  f <- make_fit(list(list(ts=2000,pw=275), list(ts=2001,pw=280)), dev = 3L)
  expect_equal(read_power_raw(f), c(275,280))
})
test_that("garbage / too-small file -> NULL", {
  p <- tempfile(); writeBin(as.raw(rep(0L,8)), p)
  expect_null(read_power_raw(p))
})
