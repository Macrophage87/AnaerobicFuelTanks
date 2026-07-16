#!/usr/bin/env Rscript
# Deploy the Dual-Tank calibration Shiny app.
# --------------------------------------------------------------------------
# This script is GUARDED: sourcing or `Rscript deploy.R` with no arguments does
# NOTHING but print instructions, so it can never silently (re)write the
# manifest or push a deploy by accident. Ask for an action explicitly:
#
#   Rscript deploy.R manifest      # refresh manifest.json only
#   Rscript deploy.R deploy        # refresh manifest.json AND deploy the app
#   CALIBRATE_DEPLOY=manifest Rscript deploy.R   # env-var equivalent
#
# --------------------------------------------------------------------------
# WHY THE MANIFEST MATTERS. REQUIRED before committing ANY change under
# tools/calibrate/: re-run the `manifest` action and commit the refreshed
# manifest.json. The committed manifest records an md5 checksum of every
# bundled file; a git-backed Posit Connect deploy restores the bundle from it,
# so a stale checksum makes Connect ship a manifest describing a DIFFERENT
# app.R than the one served. CI enforces this — scripts/check_calibrate_manifest.sh
# (in the r-lint job) fails the build if manifest.json no longer matches the
# committed files. (If you have no R handy, that script also tells you exactly
# which checksum drifted; the md5 of the file on disk is the correct value — but
# only writeManifest() also refreshes the pinned packages{} closure.)
#
# The committed manifest.json is already a COMPLETE, version-pinned dependency
# closure (the full transitive set of packages with exact versions + per-file
# md5s). Regenerating it against your own R library REFRESHES those pins and the
# "platform" field to match your environment — it does not turn a partial list
# into a full one.
#
#   install.packages("rsconnect")
#   remotes::install_github("grimbough/FITfileR")   # if not already installed
#
# Notes:
#   - Update "platform" in manifest.json to your R version (R.version.string);
#     writeManifest() sets it from the R that runs this script.
#   - FITfileR is a GitHub package (grimbough/FITfileR); writeManifest records it
#     automatically once it's installed from GitHub. Install it BEFORE running the
#     `manifest` action or the closure won't resolve.
#   - writeManifest() statically scans this directory, so because this deploy.R
#     lives here and calls rsconnect::writeManifest, `rsconnect` (and its deps such
#     as openssl) get pulled into packages{} even from a clean library. To drop the
#     deploy-only tooling from the runtime closure, list deploy.R in a .rscignore
#     file in this directory.
# --------------------------------------------------------------------------

# Resolve the requested action from the command line or CALIBRATE_DEPLOY env var.
args   <- commandArgs(trailingOnly = TRUE)
action <- if (length(args) >= 1) args[[1]] else Sys.getenv("CALIBRATE_DEPLOY", "")

if (!action %in% c("manifest", "deploy")) {
  message(
    "deploy.R: nothing to do (guarded).\n",
    "  Rscript deploy.R manifest   # refresh manifest.json only\n",
    "  Rscript deploy.R deploy     # refresh manifest.json AND deploy the app\n",
    "Run from the tools/calibrate/ directory (or it will be set for you)."
  )
  quit(save = "no", status = 0)
}

# Run from this script's own directory so writeManifest() scans the app bundle.
this_file <- sub("^--file=", "",
                 grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
if (length(this_file) == 1 && nzchar(this_file)) {
  setwd(dirname(normalizePath(this_file)))
}

if (!requireNamespace("rsconnect", quietly = TRUE)) {
  stop("Package 'rsconnect' is not installed. Run install.packages(\"rsconnect\") first.")
}

# 1) (Re)generate an exact manifest.json for Posit Connect (git-backed deploy).
message("Writing manifest.json (full pinned closure) …")
rsconnect::writeManifest(appDir = ".")

if (identical(action, "manifest")) {
  message("manifest.json refreshed. Commit it in the SAME change as your edits.")
  quit(save = "no", status = 0)
}

# 2) Deploy. Provide credentials via the environment — never hardcode them here.
#    Fill these in (or export the equivalent env vars) before running `deploy`:
#
#   rsconnect::setAccountInfo(
#     name   = Sys.getenv("RSCONNECT_NAME"),
#     token  = Sys.getenv("RSCONNECT_TOKEN"),
#     secret = Sys.getenv("RSCONNECT_SECRET")
#   )
#
# Alternatively, push this folder to a Git-backed Posit Connect content item —
# Connect reads manifest.json and restores the packages itself (no token needed).

if (nzchar(Sys.getenv("RSCONNECT_TOKEN"))) {
  rsconnect::setAccountInfo(
    name   = Sys.getenv("RSCONNECT_NAME"),
    token  = Sys.getenv("RSCONNECT_TOKEN"),
    secret = Sys.getenv("RSCONNECT_SECRET")
  )
  message("Deploying app 'dual-tank-calibrate' …")
  rsconnect::deployApp(appDir = ".", appName = "dual-tank-calibrate")
} else {
  stop(
    "Refusing to deploy: no RSCONNECT_TOKEN in the environment.\n",
    "Set RSCONNECT_NAME / RSCONNECT_TOKEN / RSCONNECT_SECRET (or use a git-backed\n",
    "Posit Connect content item). manifest.json has already been refreshed above."
  )
}
