test_that("contiguous 1 Hz round-trips", {
  p <- c(100,150,200,120); expect_equal(timeline_from(1000 + 0:3, p), p)
})
test_that("gap zero-fills (pause -> 0 W)", {
  expect_equal(timeline_from(c(0,1,5,6), c(100,110,120,130)),
               c(100,110,0,0,0,120,130))
})
test_that("out-of-order sorted; duplicate timestamps keep one/sec", {
  expect_equal(timeline_from(c(2,0,1,1), c(30,10,20,999)), c(10,20,30))
})
test_that("rollover guard falls back to raw p", {
  p <- c(100,110,120); expect_equal(timeline_from(c(0,1,1e9), p), p)
})
test_that("<2 finite samples -> NULL", {
  expect_null(timeline_from(1, 100))
  expect_null(timeline_from(c(NA,NA), c(1,2)))
})
