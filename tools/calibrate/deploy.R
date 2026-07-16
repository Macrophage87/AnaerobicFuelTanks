# Deploy the Dual-Tank calibration Shiny app.
# --------------------------------------------------------------------------
# REQUIRED before committing ANY change under tools/calibrate/: re-run
#   rsconnect::writeManifest(appDir = ".")
# as the final step, and commit the refreshed manifest.json. The committed
# manifest records an md5 checksum of every bundled file; a git-backed Posit
# Connect deploy restores the bundle from it, so a stale checksum makes Connect
# ship a manifest describing a DIFFERENT app.R than the one served. CI enforces
# this — scripts/check_calibrate_manifest.sh (in the r-lint job) fails the build
# if manifest.json no longer matches the committed files. (If you have no R
# handy, that script also tells you exactly which checksum drifted; the md5 of
# the file on disk is the correct value — but only writeManifest() also refreshes
# the pinned packages{} closure.)
#
# The committed manifest.json lists the DIRECT dependencies as a starting point.
# For a reproducible deploy, regenerate it locally so it pins exact versions and
# the full dependency closure from YOUR R library, then deploy.
#
#   install.packages("rsconnect")
#   remotes::install_github("grimbough/FITfileR")   # if not already installed
#   setwd("tools/calibrate")
#
# 1) (Re)generate an exact manifest.json for Posit Connect (git-backed deploy):
rsconnect::writeManifest(appDir = ".")
#
# 2a) Deploy to shinyapps.io / Posit Connect via rsconnect:
#   rsconnect::setAccountInfo(name = "<acct>", token = "<token>", secret = "<secret>")
#   rsconnect::deployApp(appDir = ".", appName = "dual-tank-calibrate")
#
# 2b) Or push this folder to a Git-backed Posit Connect content item — Connect
#     reads manifest.json and restores the packages itself.
#
# Notes:
#   - Update "platform" in manifest.json to your R version (R.version.string).
#   - FITfileR is a GitHub package (grimbough/FITfileR); writeManifest records it
#     automatically once it's installed from GitHub. Install it BEFORE running
#     writeManifest() or the closure won't resolve.
#   - writeManifest() statically scans this directory, so because this deploy.R
#     lives here and calls rsconnect::writeManifest, `rsconnect` (and its deps such
#     as openssl) get pulled into packages{} even from a clean library. To drop the
#     deploy-only tooling from the runtime closure, list deploy.R in a .rscignore
#     file in this directory.
