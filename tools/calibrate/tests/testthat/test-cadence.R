# #31 Part B: cadence_of powers the non-1 Hz warn-only signal. Parity-inert — it must never be
# consumed by simulate_tanks / the crosscheck fixtures, only surfaced as a UI warning.
test_that("cadence_of returns the native median sample spacing", {
  expect_equal(cadence_of(c(1000, 1001, 1002, 1003)), 1)   # native 1 Hz
  expect_equal(cadence_of(c(0, 5, 10, 15)), 5)             # 5 s smart recording
  expect_equal(cadence_of(c(2, 0, 1)), 1)                  # unsorted -> sorted before diff
  expect_true(is.na(cadence_of(1)))                        # < 2 finite samples -> NA
  expect_true(is.na(cadence_of(c(NA, NA))))
})
