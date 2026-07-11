# Dual-Tank Parameter Estimator — R Shiny (sketch)
# --------------------------------------------------------------------------
# Upload SEVERAL .FIT files (rides, races, interval sets) -> estimate the
# AnaerobicFuelTanks parameters, picking the best value for each across files.
#
#   * CP, W', pPmax        -> combined mean-maximal power curve (best-of-all).
#   * fP, tauP, tauG, eta   -> dual-tank model fit per ride, anchored at maximal
#                              moments, then aggregated (median / best-fit).
#   * INTERVAL SETS         -> constrain recovery only when between-bout refill is
#                              low (short rest). Sets with >70% refill are flagged.
#   * UNCERTAINTY           -> every parameter is flagged when weakly constrained.
#   * EXPORT                -> a dated YAML reading (append-friendly, multi-reading)
#                              and a PDF report explaining where each value stands.
#   * TRENDS                -> supply a history YAML to see each value over time.
#
# install.packages(c("shiny","ggplot2","DT","yaml"))
# remotes::install_github("grimbough/FITfileR")
# --------------------------------------------------------------------------

library(shiny)
library(bslib)
library(ggplot2)
library(yaml)
suppressWarnings(suppressMessages(library(FITfileR)))
# install.packages(c("shiny","bslib","ggplot2","DT","yaml")); remotes::install_github("grimbough/FITfileR")

DURATIONS <- c(1,5,10,15,20,30,45,60,90,120,180,240,300,420,600,720,900,1200,1800,2400,3600)
DEFAULTS  <- list(fP = 0.35, pPmax = 300, tauP = 22, tauG = 360,
                  lt1Frac = 0.80, eta = 0.80, fatK = 0.75, tauAer = 25)
PARAMS <- c("CP","Wprime","pPmax","fP","tauP","tauG","eta")   # the tracked "sprint values"
PARAM_DESC <- c(
  CP      = "Critical power (W): highest sustainable power; linear work model over best 2-12 min efforts.",
  Wprime  = "Anaerobic work capacity above CP (J).",
  pPmax   = "Max PCr (fast) power above CP (W): from the best 5 s sprint across files.",
  fP      = "PCr share of W' (0-1): from the recovery fit across rides, else default.",
  tauP    = "PCr recovery time constant (s): fast reconstitution.",
  tauG    = "Glycolytic recovery time constant (s): slow reconstitution.",
  eta     = "PCr recovery efficiency (0-1).",
  lt1Frac = "Fraction of CP below which glycolytic refills: default (needs a threshold test).",
  fatK    = "Fatigue slowing of PCr recovery: default (needs repeated-bout data).",
  tauAer  = "Aerobic on-ramp time constant (s): default.")
cv <- function(x) { x <- x[is.finite(x)]; if (length(x) > 1 && mean(x) != 0) sd(x)/abs(mean(x)) else NA_real_ }

# ---- steampunk dual-tank theme (purple = PCr, green = glycolytic) ----------
PCR <- "#B44DFF"; PCR_DEEP <- "#6C26A8"; GLY <- "#37E85A"; GLY_DEEP <- "#1A8C3A"
BRASS <- "#C9A227"; PARCH <- "#EDE0C8"; WALNUT <- "#20160E"
steampunk_css <- "
:root{--pcr:#B44DFF;--gly:#37E85A;--brass:#C9A227;--parch:#EDE0C8;}
body{background:radial-gradient(1200px 800px at 30% -10%,#3a2817 0%,#20160E 60%,#150e07 100%);color:var(--parch);}
h1,h2,h3,h4,.navbar-brand,.card-header{font-family:'Cinzel',serif;color:var(--brass);letter-spacing:.04em;text-shadow:0 1px 0 #000;}
.card{border:2px solid var(--brass);border-radius:12px;background:linear-gradient(180deg,#2b1e12,#1a120a);
  box-shadow:inset 0 0 0 1px rgba(201,162,39,.25),0 8px 22px rgba(0,0,0,.55);}
.card-header{background:linear-gradient(180deg,#3a2817,#241a10);border-bottom:1px solid var(--brass);}
.nav-tabs .nav-link{color:var(--parch);}
.nav-tabs .nav-link.active{color:#20160E;background:var(--brass);border-color:var(--brass);}
.bslib-sidebar-layout>.sidebar{background:linear-gradient(180deg,#241a10,#150e07);border-right:2px solid var(--brass);}
.btn-primary{background:linear-gradient(180deg,#8a3ecf,#4e1c78);border:1px solid var(--brass);color:#fff;}
.btn-primary:hover{background:linear-gradient(180deg,#9d55e0,#5c2490);}
.btn{border:1px solid var(--brass);color:var(--parch);background:linear-gradient(180deg,#2b1e12,#1a120a);}
.form-control,.selectize-input,.form-select,.selectize-dropdown{background:#160f08!important;color:var(--parch)!important;border:1px solid var(--brass)!important;}
.irs-bar,.irs-single,.irs-from,.irs-to{background:var(--pcr)!important;border-color:var(--pcr)!important;}
.irs-handle{border:2px solid var(--brass)!important;background:#2b1e12!important;}
pre{background:#160f08;color:var(--parch);border:1px solid var(--brass);border-radius:8px;}
a{color:var(--gly);} hr{border-top:1px solid var(--brass);opacity:.5;}
.form-check-input:checked{background-color:var(--gly);border-color:var(--gly);}
table.dataTable{color:var(--parch);} .dataTables_wrapper{color:var(--parch);}
.guide{max-width:920px;line-height:1.5;}
.guide h4{color:var(--brass);margin:16px 0 6px;letter-spacing:.05em;}
.guide li{margin:5px 0;} .guide code{background:#160f08;border:1px solid var(--brass);border-radius:4px;padding:1px 6px;color:var(--parch);}
.guide table{border-collapse:collapse;margin:8px 0;} .guide th,.guide td{border:1px solid var(--brass);padding:5px 11px;text-align:left;}
.guide th{color:var(--brass);background:rgba(0,0,0,.25);}
.guide .pcr{color:var(--pcr);font-weight:bold;} .guide .gly{color:var(--gly);font-weight:bold;}
"
tank_theme <- bs_theme(version = 5, bg = WALNUT, fg = PARCH, primary = PCR, secondary = GLY,
  success = GLY, info = BRASS, warning = BRASS,
  base_font = font_google("EB Garamond"), heading_font = font_google("Cinzel"),
  code_font = font_google("IM Fell English SC"))
tank_theme <- bs_add_rules(tank_theme, steampunk_css)

# ggplot theme that blends into the brass-on-walnut cards (screen)
gg_tank <- function() theme_minimal(base_size = 12) + theme(
  plot.background  = element_rect(fill = "transparent", colour = NA),
  panel.background = element_rect(fill = "transparent", colour = NA),
  panel.grid.major = element_line(colour = "#4a3a24"), panel.grid.minor = element_line(colour = "#33281a"),
  text = element_text(colour = PARCH), axis.text = element_text(colour = BRASS),
  strip.text = element_text(colour = BRASS, face = "bold"), plot.title = element_text(colour = BRASS))
# light "aged parchment" theme for the PDF report (dark ink on parchment)
gg_report <- function() theme_minimal(base_size = 11) + theme(
  plot.background  = element_rect(fill = "#EDE0C8", colour = NA),
  panel.background = element_rect(fill = "#EDE0C8", colour = NA),
  panel.grid.major = element_line(colour = "#d8c8a8"), panel.grid.minor = element_line(colour = "#e6dcc4"),
  text = element_text(colour = "#3a2817"), axis.text = element_text(colour = "#6b4f2a"),
  strip.text = element_text(colour = "#6b4f2a", face = "bold"), plot.title = element_text(colour = "#6b4f2a", face = "bold"))

# in-app user guide (rendered in the first tab)
guide_html <- r"[
<div class="guide">
<h4>What this tool does</h4>
<p>Upload your ride files and it estimates the parameters for the <span class="pcr">PCr</span> /
<span class="gly">glycolytic</span> dual-tank Connect IQ data field, flagging anything it cannot pin down.</p>

<h4>Step by step</h4>
<ol>
<li><b>Upload FIT files</b> in the Boiler Room (left): best-effort tests, races, hard group rides, interval sets.</li>
<li>Read <b>CP</b> and <b>W'</b> on the <i>Power-duration</i> and <i>CP / W' fit</i> tabs &mdash; the most reliable numbers.</li>
<li>On <i>Anchor editor</i>, <b>click each ride's reserve trace</b> where you were maximal or cracked
(final sprint, an attack you could not follow, the moment you got dropped). Tick repeated-bout
workouts as <b>interval sets</b> in the sidebar.</li>
<li>Press <b>Fit fP / tauP / tauG / eta on every ride</b>. Per-ride results appear on <i>Recovery fit</i>;
the final set with uncertainty flags is on <i>App parameters</i>.</li>
<li><b>Export</b> (sidebar): a Connect IQ settings file, a dated YAML reading, or a PDF report.</li>
</ol>

<h4>What it can and cannot know</h4>
<table>
<tr><th>Parameter</th><th>Source</th><th>Reliable?</th></tr>
<tr><td>CP, Wprime, pPmax</td><td>best across all files (power-duration curve)</td><td>yes</td></tr>
<tr><td>fP, tauP, tauG, eta</td><td>model fit on rides with maximal anchors</td><td>only with the right data</td></tr>
<tr><td>lt1Frac, fatK, tauAer</td><td>defaults</td><td>need special tests</td></tr>
</table>
<p>A single all-out effort obeys t_lim = W'/(P-CP), so it gives only CP and W'. The tank split and
recovery rates appear only across <b>repeated efforts with recovery</b>, and only where you anchor
maximal moments.</p>

<h4>Anchors &amp; interval sets</h4>
<ul>
<li>An <b>anchor</b> marks a second where your reserve hit zero. Getting dropped is a perfect anchor.</li>
<li><b>Interval sets</b> only constrain recovery when the rest is short &mdash; sets with more than 70%
between-bout refill are flagged as uninformative for tauP / tauG.</li>
</ul>

<h4>Applying the settings</h4>
<p><b>Export Connect IQ settings (JSON)</b> writes a file keyed exactly like the data field's settings.
Type those values into Garmin Connect &rarr; the field's settings (Garmin does not import files), or load
the JSON in the Connect IQ simulator or your own build.</p>

<h4>Colour key</h4>
<p><span class="pcr">Purple = PCr</span> (fast, small tank) &middot;
<span class="gly">Green = glycolytic</span> (slow, large tank). Lines marked <b>uncertain</b> are weakly constrained.</p>
</div>
]"

read_power <- function(path) {
  ff <- try(readFitFile(path), silent = TRUE); if (inherits(ff, "try-error")) return(NULL)
  recs <- try(records(ff), silent = TRUE);     if (inherits(recs, "try-error")) return(NULL)
  if (is.data.frame(recs)) recs <- list(recs)
  pw <- unlist(lapply(recs, function(df) if ("power" %in% names(df)) as.numeric(df$power) else numeric(0)))
  pw <- pw[is.finite(pw)]; if (length(pw) < 2) NULL else pw
}
best_mean_power <- function(p, d) { n <- length(p); if (n < d) return(NA_real_)
  cs <- cumsum(c(0, p)); max((cs[(d + 1):(n + 1)] - cs[1:(n - d + 1)]) / d) }
mmp_curve <- function(power_list, durations = DURATIONS)
  vapply(durations, function(d) { v <- vapply(power_list, best_mean_power, numeric(1), d = d)
    if (all(is.na(v))) NA_real_ else max(v, na.rm = TRUE) }, numeric(1))
fit_cp <- function(dur, pw, tmin, tmax) {
  keep <- which(dur >= tmin & dur <= tmax & is.finite(pw)); if (length(keep) < 2) return(NULL)
  t <- dur[keep]; W <- pw[keep] * t; f <- lm(W ~ t)
  list(CP = unname(coef(f)[2]), Wprime = unname(coef(f)[1]), r2 = summary(f)$r.squared,
       n = length(keep), rng = max(t)/min(t), t = t, W = W)
}
simulate_tanks <- function(power, cp, par) {
  n <- length(power); cP <- par$fP * par$Wprime; cG <- (1 - par$fP) * par$Wprime
  rP <- cP; rG <- cG; aer <- cp; resTot <- numeric(n); deficit <- numeric(n)
  AER_FALL <- 6
  kUp <- if (par$tauAer > 0) 1 - exp(-1 / par$tauAer) else 1
  kDn <- if (par$tauAer > 0) 1 - exp(-1 / (par$tauAer * AER_FALL)) else 1
  bG <- 1 - exp(-1 / par$tauG)
  for (i in seq_len(n)) {
    p <- power[i]
    if (par$tauAer > 0) {                     # sticky aerobic, floored; below CP aerobic covers demand
      tgt <- min(p, cp); aer <- aer + (tgt - aer) * (if (tgt > aer) kUp else kDn)
      aer <- max(0.5 * cp, min(cp, aer)); supply <- if (p > cp) aer else p
    } else supply <- cp
    delta <- p - supply
    if (delta > 0) {
      need <- delta
      takeP <- min(need, rP, par$pPmax); rP <- rP - takeP; need <- need - takeP
      takeG <- min(need, rG);            rG <- rG - takeG; need <- need - takeG
      deficit[i] <- need
    } else {
      tauPeff <- par$tauP * (1 + par$fatK * (1 - rG / cG)); rP <- rP + par$eta * (cP - rP) * (1 - exp(-1 / tauPeff))
      lt1 <- par$lt1Frac * cp; if (p < lt1) rG <- rG + ((lt1 - p) / lt1) * (cG - rG) * bG
    }
    rP <- max(0, min(cP, rP)); rG <- max(0, min(cG, rG)); resTot[i] <- rP + rG
  }
  list(total = resTot, deficit = deficit)
}
suggest_marks <- function(power, cp, base) {
  s <- simulate_tanks(power, cp, base); tot <- s$total; n <- length(tot)
  cand <- c(which.min(tot), n); lo <- which(tot[-c(1, n)] < 0.20 * base$Wprime) + 1
  if (length(lo)) cand <- c(cand, lo[c(TRUE, diff(lo) > 30)]); sort(unique(cand))
}
ride_diag <- function(power, cp, base) {
  r <- rle(power > cp); ends <- cumsum(r$lengths); starts <- ends - r$lengths + 1L
  bouts <- which(r$values & r$lengths >= 5); nb <- length(bouts); mean_rec <- NA_real_; refill <- NA_real_
  if (nb >= 2) {
    tot <- simulate_tanks(power, cp, base)$total; Wp <- base$Wprime; gaps <- numeric(nb-1); rf <- numeric(nb-1)
    for (k in seq_len(nb-1)) { b1 <- bouts[k]; b2 <- bouts[k+1]; gaps[k] <- starts[b2]-ends[b1]
      after <- tot[ends[b1]]; before <- tot[starts[b2]]; rf[k] <- (before-after)/max(1e-6, Wp-after) }
    mean_rec <- mean(gaps); refill <- median(pmax(0, pmin(1, rf)))
  }
  list(n_bouts = nb, mean_rec_s = mean_rec, refill = refill)
}
ride_flag <- function(dg, fit) {
  fl <- character(0)
  if (!is.null(fit) && fit$conv != 0) fl <- c(fl, "no-converge")
  if (is.na(dg$n_bouts) || dg$n_bouts < 3) fl <- c(fl, "few-bouts")
  if (!is.na(dg$refill) && dg$refill > 0.7) fl <- c(fl, "rest-too-long")
  if (!is.null(fit) && fit$obj > 0.05) fl <- c(fl, "poor-fit")
  if (length(fl)) paste(fl, collapse = ";") else "ok"
}
fit_recovery <- function(power, cp, base, marks) {
  Wp <- base$Wprime
  obj <- function(th) { par <- base; par$fP <- th[1]; par$tauP <- th[2]; par$tauG <- th[3]; par$eta <- th[4]
    s <- simulate_tanks(power, cp, par); 5 * mean((s$deficit/Wp)^2) + (if (length(marks)) mean((s$total[marks]/Wp)^2) else 0) }
  st <- optim(c(base$fP, base$tauP, base$tauG, base$eta), obj, method = "L-BFGS-B",
              lower = c(0.10,5,60,0.30), upper = c(0.60,120,1800,1.00), control = list(maxit = 200))
  list(fP = st$par[1], tauP = st$par[2], tauG = st$par[3], eta = st$par[4], obj = st$value, conv = st$convergence)
}
fit_all_rides <- function(power_list, names, cp, base, anchors, interval_idx) {
  rows <- lapply(seq_along(power_list), function(i) {
    p <- power_list[[i]]; man <- anchors[[as.character(i)]]; is_int <- i %in% interval_idx
    if (!is.null(man) && length(man)) { m <- man; src <- "manual" }
    else if (is_int) { m <- c(which.min(simulate_tanks(p, cp, base)$total), length(p)); src <- "interval-end" }
    else { m <- suggest_marks(p, cp, base); src <- "auto" }
    r <- try(fit_recovery(p, cp, base, m), silent = TRUE); if (inherits(r, "try-error")) return(NULL)
    dg <- ride_diag(p, cp, base)
    data.frame(file = names[i], type = if (is_int) "interval" else "variable", anchors = src,
               bouts = dg$n_bouts, rec_s = round(dg$mean_rec_s), refill = round(dg$refill, 2),
               fP = r$fP, tauP = r$tauP, tauG = r$tauG, eta = r$eta, obj = r$obj, conv = r$conv,
               flag = ride_flag(dg, r), stringsAsFactors = FALSE)
  })
  do.call(rbind, Filter(Negate(is.null), rows))
}

# ===========================================================================
ui <- page_sidebar(
  title = "⚙ Dual-Tank Parameter Estimator ⚙",
  theme = tank_theme,
  sidebar = sidebar(width = 330, title = "Boiler room",
    fileInput("files", "FIT files (rides / races / interval sets)", multiple = TRUE, accept = c(".fit", ".FIT")),
    sliderInput("cpwin", "CP fit window (min)", 1, 30, c(2, 12), 1),
    sliderInput("fP", "PCr share of W' (fP) start value", 0.1, 0.6, 0.35, 0.01),
    uiOutput("interval_pick"),
    fileInput("history", "History YAML (optional, for trends)", accept = c(".yaml", ".yml")),
    hr(),
    actionButton("fitall", "Fit fP/tauP/tauG/eta on every ride", class = "btn-primary"),
    radioButtons("agg", "Combine rides by", c("median", "best-fit"), inline = TRUE),
    hr(),
    downloadButton("dl_ciq", "Export Connect IQ settings (JSON)"),
    downloadButton("dl_yaml", "Export dated YAML reading"),
    downloadButton("dl_pdf", "Export PDF report")
  ),
  navset_card_tab(
    nav_panel("★ Guide", HTML(guide_html)),
    nav_panel("Power-duration", plotOutput("mmp_plot", height = 300), DT::dataTableOutput("mmp_tbl")),
    nav_panel("CP / W' fit", plotOutput("cp_plot", height = 300), verbatimTextOutput("cp_txt")),
    nav_panel("Anchor editor",
      layout_columns(col_widths = c(5, 3, 4),
        uiOutput("ride_pick"),
        div(actionButton("autoone", "Auto-suggest"), actionButton("clearone", "Clear")),
        verbatimTextOutput("anchor_txt")),
      verbatimTextOutput("diag_txt"),
      helpText("Click the trace to add a maximal/cracked anchor; click near one to remove it."),
      plotOutput("res_plot", height = 300, click = "res_click")),
    nav_panel("Recovery fit", DT::dataTableOutput("fit_tbl"), verbatimTextOutput("agg_txt")),
    nav_panel("App parameters", verbatimTextOutput("params"), htmlOutput("caveats")),
    nav_panel("Trends", plotOutput("trend_plot", height = 380), DT::dataTableOutput("trend_tbl"))
  )
)

# ===========================================================================
server <- function(input, output, session) {
  rv <- reactiveValues(fits = NULL, anchors = list())

  powers <- reactive({ req(input$files)
    ps <- lapply(input$files$datapath, read_power); keep <- !vapply(ps, is.null, logical(1))
    validate(need(any(keep), "No readable power data.")); list(p = ps[keep], names = input$files$name[keep]) })
  mmp   <- reactive(data.frame(duration = DURATIONS, power = mmp_curve(powers()$p)))
  cpfit <- reactive(fit_cp(mmp()$duration, mmp()$power, input$cpwin[1]*60, input$cpwin[2]*60))
  base_par <- reactive({ f <- cpfit(); req(f); modifyList(DEFAULTS, list(Wprime = f$Wprime, fP = input$fP)) })
  interval_idx <- reactive(as.integer(input$intervalrides))
  output$interval_pick <- renderUI({ pw <- powers()
    checkboxGroupInput("intervalrides", "Interval-set rides (repeated bouts)", choices = setNames(seq_along(pw$p), pw$names)) })

  agg <- reactive({ df <- rv$fits; if (is.null(df)) return(NULL)
    good <- df[!grepl("no-converge|few-bouts|rest-too-long", df$flag), , drop = FALSE]
    constrained <- nrow(good) > 0; use <- if (constrained) good else df
    pick <- function(col) if (input$agg == "best-fit") use[[col]][which.min(use$obj)] else median(use[[col]])
    list(fP = pick("fP"), tauP = pick("tauP"), tauG = pick("tauG"), eta = pick("eta"),
         constrained = constrained, n_used = nrow(use),
         cv = c(fP = cv(use$fP), tauP = cv(use$tauP), tauG = cv(use$tauG), eta = cv(use$eta)),
         src = if (input$agg == "best-fit") paste("best-fit:", use$file[which.min(use$obj)]) else sprintf("median of %d rides", nrow(use))) })

  # ---- unified estimate table (value / source / uncertainty) ----
  est_table <- reactive({
    f <- cpfit(); req(f); m <- mmp(); a <- agg()
    p5 <- m$power[m$duration == 5]; pPmax <- if (is.finite(p5)) max(50, round(p5 - f$CP)) else DEFAULTS$pPmax
    cpWhy <- paste(c(if (f$r2 < 0.95) "low R2", if (f$n < 3) "few efforts", if (f$rng < 5) "narrow durations"), collapse = ", ")
    recU <- is.null(a) || !a$constrained
    spread <- function(k) !is.null(a) && a$constrained && is.finite(a$cv[[k]]) && a$cv[[k]] > 0.3
    recWhy <- if (is.null(a)) "not fit (defaults)" else "rest too long / few bouts"
    src_rec <- if (is.null(a)) "default" else a$src
    val <- c(CP = round(f$CP), Wprime = round(f$Wprime), pPmax = pPmax,
             fP = round(if (is.null(a)) input$fP else a$fP, 2),
             tauP = round(if (is.null(a)) DEFAULTS$tauP else a$tauP),
             tauG = round(if (is.null(a)) DEFAULTS$tauG else a$tauG),
             eta = round(if (is.null(a)) DEFAULTS$eta else a$eta, 2),
             lt1Frac = DEFAULTS$lt1Frac, fatK = DEFAULTS$fatK, tauAer = DEFAULTS$tauAer)
    src <- c(CP = "best across files", Wprime = "best across files", pPmax = "best 5s - CP",
             fP = src_rec, tauP = src_rec, tauG = src_rec, eta = src_rec,
             lt1Frac = "default", fatK = "default", tauAer = "default")
    unc <- c(CP = nzchar(cpWhy), Wprime = nzchar(cpWhy), pPmax = (!is.finite(p5) || p5 < 1.4 * f$CP),
             fP = recU || spread("fP"), tauP = recU || spread("tauP"), tauG = recU || spread("tauG"),
             eta = recU || spread("eta"), lt1Frac = TRUE, fatK = TRUE, tauAer = TRUE)
    note <- c(CP = cpWhy, Wprime = cpWhy, pPmax = "no clear maximal sprint",
              fP = if (recU) recWhy else "wide spread across rides", tauP = if (recU) recWhy else "wide spread across rides",
              tauG = if (recU) recWhy else "wide spread across rides", eta = if (recU) recWhy else "wide spread across rides",
              lt1Frac = "needs a threshold test", fatK = "needs repeated-bout data", tauAer = "needs onset-kinetics data")
    ord <- names(PARAM_DESC)
    data.frame(param = ord, value = as.numeric(val[ord]), source = src[ord],
               uncertain = as.logical(unc[ord]), note = note[ord], stringsAsFactors = FALSE)
  })

  # ---- history / readings over time ----
  history_data <- reactive({ if (is.null(input$history)) return(NULL)
    y <- try(yaml::read_yaml(input$history$datapath), silent = TRUE)
    if (inherits(y, "try-error") || is.null(y$readings)) NULL else y$readings })
  current_reading <- reactive({ et <- est_table(); req(et)
    d <- data.frame(date = as.character(Sys.Date()), stringsAsFactors = FALSE)
    for (k in PARAMS) d[[k]] <- et$value[match(k, et$param)]; d })
  readings_df <- reactive({ cur <- current_reading(); hist <- history_data(); rows <- list()
    if (!is.null(hist)) for (r in hist) { d <- data.frame(date = as.character(r$date), stringsAsFactors = FALSE)
      for (k in PARAMS) d[[k]] <- if (!is.null(r[[k]])) as.numeric(r[[k]]) else NA_real_; rows[[length(rows)+1]] <- d }
    rows[[length(rows)+1]] <- cur; df <- do.call(rbind, rows); df$date <- as.Date(df$date); df[order(df$date), ] })

  # ---- ggplot builders (reused by renderPlot AND the PDF export) ----
  mmp_gg <- reactive({ m <- mmp(); f <- cpfit()
    g <- ggplot(subset(m, is.finite(power)), aes(duration, power)) + geom_line(colour = "grey60") +
      geom_point(size = 2) + scale_x_log10() + labs(x = "duration (s, log)", y = "best mean power (W)", title = "Mean-maximal power") + gg_tank()
    if (!is.null(f)) g <- g + geom_line(data = data.frame(duration = (tt <- 10^seq(log10(30), log10(3600), length.out = 200)),
                                  power = f$CP + f$Wprime / tt), colour = "#B44DFF", linewidth = 1) +
      geom_hline(yintercept = f$CP, linetype = 2, colour = "#37E85A"); g })
  cp_gg <- reactive({ f <- cpfit(); if (is.null(f)) return(NULL)
    ggplot(data.frame(t = f$t, W = f$W), aes(t, W)) + geom_point(size = 2) +
      geom_abline(intercept = f$Wprime, slope = f$CP, colour = "#B44DFF", linewidth = 1) +
      labs(x = "time (s)", y = "work (J) = CP*t + W'", title = "CP / W' work-time fit") + gg_tank() })
  trend_gg <- reactive({ df <- readings_df(); if (nrow(df) < 1) return(NULL)
    long <- do.call(rbind, lapply(PARAMS, function(k) data.frame(date = df$date, param = k, value = df[[k]])))
    long$param <- factor(long$param, levels = PARAMS)
    ggplot(long, aes(date, value)) + geom_line(colour = "#B44DFF") + geom_point(size = 1.6) +
      facet_wrap(~param, scales = "free_y") + labs(x = NULL, y = NULL, title = "Estimates over time") + gg_tank() })

  output$mmp_plot <- renderPlot(mmp_gg(), bg = "transparent")
  output$mmp_tbl  <- DT::renderDataTable(DT::datatable(transform(mmp(), power = round(power)), rownames = FALSE, options = list(pageLength = 8, dom = "tp")))
  output$cp_plot  <- renderPlot({ g <- cp_gg(); validate(need(!is.null(g), "Need >=2 efforts in the window.")); g }, bg = "transparent")
  output$cp_txt   <- renderText({ f <- cpfit(); req(f)
    sprintf("CP = %.0f W   W' = %.0f J   R^2 = %.3f (n = %d efforts, %.1fx duration range)", f$CP, f$Wprime, f$r2, f$n, f$rng) })

  # ---- anchor editor ----
  output$ride_pick <- renderUI({ pw <- powers(); selectInput("ride", "Ride", choices = setNames(seq_along(pw$p), pw$names)) })
  ride_idx   <- reactive({ req(input$ride); as.integer(input$ride) })
  ride_power <- reactive({ powers()$p[[ride_idx()]] })
  observeEvent(input$res_click, { p <- ride_power(); req(p); x <- round(input$res_click$x); if (x < 1 || x > length(p)) return()
    key <- as.character(ride_idx()); cur <- rv$anchors[[key]]; if (is.null(cur)) cur <- integer(0)
    tol <- max(5, round(length(p) * 0.01)); near <- which(abs(cur - x) <= tol)
    rv$anchors[[key]] <- if (length(near)) cur[-near] else sort(c(cur, x)) })
  observeEvent(input$autoone, { f <- cpfit(); p <- ride_power(); req(f, p); rv$anchors[[as.character(ride_idx())]] <- suggest_marks(p, f$CP, base_par()) })
  observeEvent(input$clearone, { rv$anchors[[as.character(ride_idx())]] <- integer(0) })
  output$anchor_txt <- renderText({ a <- rv$anchors[[as.character(ride_idx())]]
    if (is.null(a) || !length(a)) "no manual anchors (auto/interval-end will be used)" else paste("anchors (s):", paste(a, collapse = ", ")) })
  output$diag_txt <- renderText({ f <- cpfit(); p <- ride_power(); req(f, p); dg <- ride_diag(p, f$CP, base_par())
    warn <- if (!is.na(dg$refill) && dg$refill > 0.7) "  <<= rest too long: does NOT constrain recovery" else ""
    sprintf("bouts>CP: %d | mean recovery: %s s | between-bout refill: %s%s", dg$n_bouts,
            ifelse(is.na(dg$mean_rec_s), "-", round(dg$mean_rec_s)), ifelse(is.na(dg$refill), "-", paste0(round(100*dg$refill), "%")), warn) })
  output$res_plot <- renderPlot({ f <- cpfit(); p <- ride_power(); req(f, p)
    par <- base_par(); a <- agg(); if (!is.null(a)) par <- modifyList(par, a[c("fP","tauP","tauG","eta")])
    s <- simulate_tanks(p, f$CP, par); df <- data.frame(t = seq_along(p), pct = 100 * s$total / par$Wprime)
    anch <- rv$anchors[[as.character(ride_idx())]]
    g <- ggplot(df, aes(t, pct)) + geom_line(colour = "#B44DFF") + ylim(0, 100) +
      labs(x = "time (s)", y = "total reserve (% W')", title = if (is.null(a)) "default params - click to anchor" else "fitted params - click to anchor") + gg_tank()
    if (!is.null(anch) && length(anch)) g <- g + geom_vline(xintercept = anch, colour = "#FF0000", linetype = 2); g }, bg = "transparent")

  # ---- fit + results ----
  observeEvent(input$fitall, { f <- cpfit(); pw <- powers(); req(f); rv$fits <- fit_all_rides(pw$p, pw$names, f$CP, base_par(), rv$anchors, interval_idx()) })
  output$fit_tbl <- DT::renderDataTable({ validate(need(!is.null(rv$fits), "Set anchors / mark interval sets, then 'Fit ... on every ride'."))
    d <- rv$fits; num <- c("fP","tauP","tauG","eta","obj"); d[num] <- lapply(d[num], round, 3)
    dt <- DT::datatable(d, rownames = FALSE, options = list(pageLength = 10, dom = "tp"))
    DT::formatStyle(dt, "flag", target = "row", backgroundColor = DT::styleEqual("ok", "white", default = "#fff3cd")) })
  output$agg_txt <- renderText({ a <- agg(); if (is.null(a)) return("")
    u <- if (!a$constrained) "  [HIGH UNCERTAINTY: no ride constrained recovery]" else ""
    sprintf("Chosen (%s):  fP = %.2f  tauP = %.0f s  tauG = %.0f s  eta = %.2f%s", a$src, a$fP, a$tauP, a$tauG, a$eta, u) })

  output$params <- renderText({ et <- est_table(); req(et)
    lines <- vapply(seq_len(nrow(et)), function(i) {
      base <- sprintf("%-8s = %s   # %s", et$param[i], format(et$value[i]), et$source[i])
      if (et$uncertain[i]) paste0(base, "   <<= uncertain: ", et$note[i]) else base }, character(1))
    paste(lines, collapse = "\n") })
  output$caveats <- renderUI(HTML(paste0(
    "<b>CP, W', pPmax</b> take the best across every file. <b>fP, tauP, tauG, eta</b> are fit per ride, then combined. ",
    "<b>Interval sets</b> only constrain recovery when between-bout refill is low (short rest); &gt;70% refill is flagged. ",
    "Lines marked <i>uncertain</i> are weakly constrained. Export a dated YAML to build history, then re-supply it for trends.")))

  # ---- trends ----
  output$trend_plot <- renderPlot({ g <- trend_gg(); validate(need(!is.null(g), "Upload rides (and optionally a history YAML).")); g }, bg = "transparent")
  output$trend_tbl  <- DT::renderDataTable(DT::datatable(readings_df(), rownames = FALSE, options = list(pageLength = 10, dom = "tp")))

  # ---- exports ----
  output$dl_ciq <- downloadHandler(
    filename = function() paste0("dualtank_ciq_settings_", Sys.Date(), ".json"),
    content = function(file) {
      et <- est_table(); v <- setNames(et$value, et$param)
      keys <- c("CP","Wprime","fP","pPmax","tauP","tauG","lt1Frac","eta","fatK","tauAer")   # match properties.xml
      body <- paste(vapply(keys, function(k) sprintf('  "%s": %s', k, format(v[[k]], trim = TRUE)), character(1)), collapse = ",\n")
      writeLines(c("{", body, "}"), file)
    })

  output$dl_yaml <- downloadHandler(
    filename = function() paste0("dualtank_readings_", Sys.Date(), ".yaml"),
    content = function(file) {
      cur <- current_reading(); et <- est_table()
      newr <- as.list(cur); newr$flags <- et$param[et$uncertain]
      readings <- c(history_data(), list(newr))
      yaml::write_yaml(list(readings = readings), file) })

  output$dl_pdf <- downloadHandler(
    filename = function() paste0("dualtank_report_", Sys.Date(), ".pdf"),
    content = function(file) {
      et <- est_table()
      pdf(file, width = 8.5, height = 11, bg = "#EDE0C8"); on.exit(if (dev.cur() > 1) dev.off())
      # page 1 — explanations (dark ink on parchment)
      op <- par(mar = c(0,0,0,0)); plot(NA, xlim = c(0,1), ylim = c(0,1), axes = FALSE, xlab = "", ylab = "")
      rect(-0.03, -0.03, 1.03, 1.03, border = "#8a6a2a", lwd = 3, xpd = NA)
      text(0, 0.985, "Dual-Tank Parameter Report", adj = c(0,1), cex = 1.7, font = 2, col = "#6b4f2a", family = "serif")
      text(0, 0.95, paste("Date:", Sys.Date()), adj = c(0,1), cex = 0.9, col = "#3a2817", family = "serif")
      segments(0, 0.935, 1, 0.935, col = "#8a6a2a", lwd = 1)
      y <- 0.90
      for (i in seq_len(nrow(et))) {
        p <- et$param[i]; unc <- et$uncertain[i]
        status <- if (unc) paste0("UNCERTAIN - ", et$note[i]) else "well constrained"
        text(0, y, sprintf("%-8s = %s    [%s]    %s", p, format(et$value[i]), et$source[i], status),
             adj = c(0,1), cex = 0.82, family = "mono", col = if (unc) "#8a2a12" else "#241a10"); y <- y - 0.027
        for (d in strwrap(PARAM_DESC[[p]], width = 96)) { text(0.03, y, d, adj = c(0,1), cex = 0.72, col = "#5a4a30", family = "serif"); y <- y - 0.021 }
        y <- y - 0.007
      }
      par(op)
      # page 2+ — plots on parchment
      print(mmp_gg() + gg_report()); g <- cp_gg(); if (!is.null(g)) print(g + gg_report())
      tg <- trend_gg(); if (!is.null(tg)) print(tg + gg_report())
    })
}

shinyApp(ui, server)
