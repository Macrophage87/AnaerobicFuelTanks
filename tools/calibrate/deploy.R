# Deploy the Dual-Tank calibration Shiny app.
# --------------------------------------------------------------------------
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
#     automatically once it's installed from GitHub.
