# #86 Phase 2: the gated above-CP aerobic-excess term in simulate_tanks. OFF (eAerMax absent / 0) is
# byte-identical to the hard-CP model (the crosscheck fixtures also prove this); ON (eAerMax > 0) lets
# aerobic supply exceed CP during supra-CP work, so the combined reserve depletes less.
base <- modifyList(DEFAULTS, list(Wprime = 20000))
cp <- 250
trace <- rep(400, 300)   # 5 min at 400 W (supra-CP)

test_that("eAerMax absent == eAerMax 0 (gated off, no behaviour change)", {
  off_absent <- simulate_tanks(trace, cp, base)                              # par$eAerMax NULL -> 0
  off_zero   <- simulate_tanks(trace, cp, modifyList(base, list(eAerMax = 0)))
  expect_equal(off_absent$total, off_zero$total)
  expect_equal(off_absent$rP, off_zero$rP)
  expect_equal(off_absent$rG, off_zero$rG)
})

test_that("eAerMax > 0 lets supply exceed CP, so the tanks deplete less", {
  off <- simulate_tanks(trace, cp, base)
  on  <- simulate_tanks(trace, cp, modifyList(base, list(eAerMax = 30)))
  # more combined reserve remaining at the end (the excess covered part of the supra-CP demand).
  expect_gt(tail(on$total, 1), tail(off$total, 1))
  # and it holds per-tank on the fast reserve too (some supra-CP work no longer charged to PCr).
  expect_gt(tail(on$rP, 1), tail(off$rP, 1))
})
