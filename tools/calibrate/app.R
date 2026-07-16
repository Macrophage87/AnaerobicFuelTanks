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

# ---------------------------------------------------------------------------
# Pure model + FIT/IO functions live in R/model.R (single source of truth) so
# they can be unit-tested and cross-checked without loading Shiny/a device.
# Shiny runs app.R with the app directory as the working directory.
# ---------------------------------------------------------------------------
source(file.path("R", "model.R"), local = FALSE)
PARAM_DESC <- c(
  CP      = "Critical power (W): highest sustainable power; linear work model over best 2-12 min efforts.",
  Wprime  = "Anaerobic work capacity above CP (J).",
  pPmax   = "Max PCr (fast) power above CP (W): the immediate rate cap, from the best 1 s power across files.",
  fP      = "PCr share of W' (0-1): weakly identified; recovery fit across rides, else default (~0.25).",
  tauP    = "PCr recovery time constant (s): fast reconstitution.",
  tauG    = "Glycolytic recovery time constant (s): slow reconstitution.",
  eta     = "PCr recovery-rate efficiency (0-1): rescales tauP (degenerate with it), not a true hysteresis.",
  lt1Frac = "LT1 as a fraction of CP: set from a MEASURED LT1 test, not left at the 0.80 default.",
  fatK    = "Fatigue slowing of PCr recovery: default (needs repeated-bout data).",
  gFat    = "Glycolytic flux fatigue exponent: rate_g *= (rG/cG)^gFat. Optional (0 = off); shifts repeated-sprint partition toward the biopsy direction (§6.10).",
  tauAer  = "Aerobic on-ramp time constant (s): default.",
  tauOn   = "Glycolytic activation time constant (s): how fast glycolysis ramps in at effort onset (~6 s, Parolin 1999); default.")

# ---- dual-tank theme (purple = PCr, green = glycolytic) --------------------
PCR <- "#B44DFF"; PCR_DEEP <- "#6C26A8"; GLY <- "#37E85A"; GLY_DEEP <- "#1A8C3A"
BRASS <- "#C9A227"; PARCH <- "#EDE0C8"; WALNUT <- "#20160E"
# Standard, offline-safe dark bslib theme (no web-font fetch, no heavy custom sass
# that can silently fail to compile on deploy). Purple = PCr, green = glycolytic
# are carried by primary/secondary plus a few accent rules. The sidebar rules keep
# it compact enough to fit on one screen.
app_css <- "
.pcr{color:#B44DFF;font-weight:700;} .gly{color:#37E85A;font-weight:700;}
.guide{max-width:920px;line-height:1.5;} .guide h4{color:#C9A227;margin:16px 0 6px;}
.guide li{margin:5px 0;} .guide code{background:rgba(255,255,255,.08);border-radius:4px;padding:1px 6px;}
.guide table{border-collapse:collapse;margin:8px 0;} .guide th,.guide td{border:1px solid #4a4a4a;padding:5px 11px;text-align:left;}
.guide th{color:#C9A227;background:rgba(255,255,255,.05);}
/* compact sidebar so everything fits without scrolling */
.bslib-sidebar-layout>.sidebar{font-size:13px;}
.sidebar .form-group,.sidebar .shiny-input-container{margin-bottom:.45rem;}
.sidebar .control-label,.sidebar label{margin-bottom:.15rem;font-weight:600;}
.sidebar .btn{padding:.28rem .5rem;}
.sidebar .form-text,.sidebar .help-block{font-size:11px;margin-top:.1rem;}
.sidebar hr{margin:.4rem 0;}
#read_txt{max-height:110px;overflow:auto;font-size:11px;margin:0;padding:.35rem .5rem;}
.sidebar .accordion-button{padding:.35rem .6rem;font-size:13px;}
.sidebar .accordion-body{padding:.4rem .6rem;}
"
tank_theme <- bs_theme(version = 5, bg = "#16191c", fg = "#e6e6e6",
  primary = PCR, secondary = GLY, success = GLY, info = GLY, warning = BRASS)
tank_theme <- bs_add_rules(tank_theme, app_css)

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
<tr><td>lt1Frac, fatK, gFat, tauAer, tauOn</td><td>defaults (tauOn ~6 s, Parolin 1999; gFat off)</td><td>need special tests / not power-identifiable</td></tr>
</table>
<p>A single all-out effort obeys t_lim = W'/(P-CP), so it gives only CP and W'. The tank split and
recovery rates appear only across <b>repeated efforts with recovery</b>, and only where you anchor
maximal moments.</p>

<h4>Anchors &amp; interval sets</h4>
<ul>
<li>An <b>anchor</b> marks a second where your reserve hit zero. Getting dropped is a perfect anchor.</li>
<li><b>Interval sets &mdash; to failure</b>: the last bout drove you to (or near) empty. These get a
reserve&nbsp;=&nbsp;0 anchor and constrain recovery well &mdash; as long as the rest is short (sets with
more than 70% between-bout refill are flagged as uninformative for tauP / tauG).</li>
<li><b>Interval sets &mdash; submaximal</b>: repeated bouts you completed with margin (you could have done
more). Tick these separately. The fit then uses <i>only</i> feasibility and the recovery between bouts &mdash;
no reserve&nbsp;=&nbsp;0 anchor is forced, since you never emptied the tank. The recovery table reports the
<b>reserve margin</b> you kept and flags the numbers <code>submax-weak</code> (low-confidence, excluded from
the combined estimate unless nothing better exists).</li>
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





# ===========================================================================
ui <- page_sidebar(
  title = "Dual-Tank Parameter Estimator",
  theme = tank_theme,
  sidebar = sidebar(width = 330, title = "Controls",
    fileInput("files", "FIT files (rides / races / interval sets)", multiple = TRUE, accept = c(".fit", ".FIT")),
    verbatimTextOutput("read_txt"),
    actionButton("fitall", "Fit fP / tauP / tauG / eta", class = "btn-primary w-100"),
    # Secondary controls tucked into collapsed panels so the sidebar fits one screen.
    accordion(id = "opts", open = FALSE, class = "my-2",
      accordion_panel("CP & model", icon = NULL,
        sliderInput("cpwin", "CP fit window (min)", 1, 30, c(2, 12), 1),
        sliderInput("fP", "PCr share of W' (fP) start", 0.1, 0.6, 0.25, 0.01)),
      accordion_panel("Interval sets", icon = NULL, uiOutput("interval_pick")),
      accordion_panel("History (trends)", icon = NULL,
        fileInput("history", "History YAML", accept = c(".yaml", ".yml")))),
    radioButtons("agg", "Combine rides by", c("median", "best-fit"), inline = TRUE),
    hr(),
    downloadButton("dl_ciq", "Connect IQ settings (JSON)", class = "w-100"),
    downloadButton("dl_yaml", "Dated YAML reading", class = "w-100"),
    downloadButton("dl_pdf", "PDF report", class = "w-100")
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

  reads <- reactive({ req(input$files)
    res <- lapply(input$files$datapath, read_power)
    list(name = input$files$name,
         p    = lapply(res, `[[`, "p"),
         ok   = vapply(res, function(r) !is.null(r$p), logical(1)),
         n    = vapply(res, function(r) if (is.null(r$p)) 0L else length(r$p), integer(1)),
         reason = vapply(res, function(r) if (is.null(r$reason)) "" else r$reason, character(1))) })
  powers <- reactive({ r <- reads(); keep <- r$ok
    validate(need(any(keep), paste0("No readable power data. ",
      paste(sprintf("%s: %s", r$name[!keep], r$reason[!keep]), collapse = "; "))))
    list(p = r$p[keep], names = r$name[keep]) })
  output$read_txt <- renderText({ r <- reads()
    lines <- sprintf("%s  %s  (%s)", ifelse(r$ok, "✓", "✗"), r$name,
                     ifelse(r$ok, paste0(r$n, " s of power"), r$reason))
    paste(c(sprintf("%d/%d files loaded", sum(r$ok), length(r$ok)), lines), collapse = "\n") })
  mmp   <- reactive(data.frame(duration = DURATIONS, power = mmp_curve(powers()$p)))
  cpfit <- reactive(fit_cp(mmp()$duration, mmp()$power, input$cpwin[1]*60, input$cpwin[2]*60))
  base_par <- reactive({ f <- cpfit(); req(f); modifyList(DEFAULTS, list(Wprime = f$Wprime, fP = input$fP)) })
  interval_idx <- reactive(as.integer(input$intervalrides))
  submax_idx   <- reactive(as.integer(input$submaxrides))
  output$interval_pick <- renderUI({ pw <- powers(); ch <- setNames(seq_along(pw$p), pw$names)
    tagList(
      checkboxGroupInput("intervalrides", "Interval sets — efforts to failure (reserve → 0)", choices = ch),
      checkboxGroupInput("submaxrides", "Interval sets — submaximal (completed with margin)", choices = ch),
      helpText("Tick a submaximal set when the bouts were repeated but NOT all-out. The fit then uses only feasibility + recovery between bouts (no reserve = 0 anchor) and flags the result as low-confidence.")) })

  agg <- reactive({ df <- rv$fits; if (is.null(df)) return(NULL)
    good <- df[!grepl("no-converge|few-bouts|rest-too-long|submax-weak", df$flag), , drop = FALSE]
    constrained <- nrow(good) > 0; use <- if (constrained) good else df
    pick <- function(col) if (input$agg == "best-fit") use[[col]][which.min(use$obj)] else median(use[[col]])
    list(fP = pick("fP"), tauP = pick("tauP"), tauG = pick("tauG"), eta = pick("eta"),
         constrained = constrained, n_used = nrow(use),
         cv = c(fP = cv(use$fP), tauP = cv(use$tauP), tauG = cv(use$tauG), eta = cv(use$eta)),
         src = if (input$agg == "best-fit") paste("best-fit:", use$file[which.min(use$obj)]) else sprintf("median of %d rides", nrow(use))) })

  # ---- unified estimate table (value / source / uncertainty) ----
  est_table <- reactive({
    f <- cpfit(); req(f); m <- mmp(); a <- agg()
    # pPmax is the PCr immediate rate cap: at the very first instant glycolysis is
    # inactive (g=0), so the instantaneous ceiling is CP + pPmax -> use best 1 s power.
    p1 <- m$power[m$duration == 1]; pPmax <- if (is.finite(p1)) max(50, round(p1 - f$CP)) else DEFAULTS$pPmax
    cpWhy <- paste(c(
      if (isTRUE(f$nonphysical)) "non-physical CP/W' (<= 0) - fit is corrupt, check files/window",
      if (isTRUE(f$implausible)) sprintf("CP implausibly low (< %d W) - verify files/window", CP_FLOOR_W),
      if (isTRUE(f$impossible))  "CP above longest effort - check file/window",
      if (f$r2 < 0.95) "low R2", if (f$n < 3) "few efforts", if (f$rng < 5) "narrow durations"),
      collapse = ", ")
    recU <- is.null(a) || !a$constrained
    spread <- function(k) !is.null(a) && a$constrained && is.finite(a$cv[[k]]) && a$cv[[k]] > 0.3
    recWhy <- if (is.null(a)) "not fit (defaults)" else "rest too long / few bouts"
    src_rec <- if (is.null(a)) "default" else a$src
    val <- c(CP = round(f$CP), Wprime = round(f$Wprime), pPmax = pPmax,
             fP = round(if (is.null(a)) input$fP else a$fP, 2),
             tauP = round(if (is.null(a)) DEFAULTS$tauP else a$tauP),
             tauG = round(if (is.null(a)) DEFAULTS$tauG else a$tauG),
             eta = round(if (is.null(a)) DEFAULTS$eta else a$eta, 2),
             lt1Frac = DEFAULTS$lt1Frac, fatK = DEFAULTS$fatK, gFat = DEFAULTS$gFat, tauAer = DEFAULTS$tauAer, tauOn = DEFAULTS$tauOn)
    src <- c(CP = "best across files", Wprime = "best across files", pPmax = "best 1s - CP",
             fP = src_rec, tauP = src_rec, tauG = src_rec, eta = src_rec,
             lt1Frac = "default", fatK = "default", gFat = "default (off)", tauAer = "default", tauOn = "default (Parolin 1999)")
    unc <- c(CP = nzchar(cpWhy), Wprime = nzchar(cpWhy), pPmax = (!is.finite(p1) || p1 < 1.6 * f$CP),
             fP = recU || spread("fP"), tauP = recU || spread("tauP"), tauG = recU || spread("tauG"),
             eta = recU || spread("eta"), lt1Frac = TRUE, fatK = TRUE, gFat = TRUE, tauAer = TRUE, tauOn = TRUE)
    note <- c(CP = cpWhy, Wprime = cpWhy, pPmax = "no clear maximal sprint",
              fP = if (recU) recWhy else "wide spread across rides", tauP = if (recU) recWhy else "wide spread across rides",
              tauG = if (recU) recWhy else "wide spread across rides", eta = if (recU) recWhy else "wide spread across rides",
              lt1Frac = "needs a threshold test", fatK = "needs repeated-bout data", gFat = "optional realism term; off by default (§6.10)",
              tauAer = "needs onset-kinetics data", tauOn = "literature default ~6 s; not power-identifiable")
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
    paste0(
      sprintf("CP = %.0f W   W' = %.0f J   R^2 = %.3f (n = %d efforts, %.1fx duration range)", f$CP, f$Wprime, f$r2, f$n, f$rng),
      if (isTRUE(f$nonphysical)) "\n⚠ CP/W' are non-physical (<= 0) -- the power-duration fit is corrupt (bad FIT parse / scrambled MMP) or the window is wrong. Export to device is blocked. Check the files or widen the CP window." else "",
      if (isTRUE(f$implausible)) sprintf("\n⚠ CP is implausibly low (< %d W) -- verify the files and CP window.", CP_FLOOR_W) else "",
      if (isTRUE(f$impossible)) "\n⚠ CP is at/above the power you held for the longest effort in the window -- physically impossible. Usually a corrupt power-duration curve (odd FIT parse) or too narrow a fit window; widen the CP window or check the file." else "") })

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
  observeEvent(input$fitall, { f <- cpfit(); pw <- powers(); req(f); rv$fits <- fit_all_rides(pw$p, pw$names, f$CP, base_par(), rv$anchors, interval_idx(), submax_idx()) })
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
      # Never write a non-physical CP/W' to a real device. validate(need(...)) inside a
      # downloadHandler raises a silent condition (no output slot renders it), so pair the
      # block with a visible showNotification before aborting the write.
      f <- cpfit()
      if (isTRUE(f$nonphysical))
        showNotification("Connect IQ export blocked: CP/W' are non-physical (<= 0). The power-duration fit is corrupt - check the source files or widen the CP fit window.", type = "error", duration = NULL)
      validate(need(!isTRUE(f$nonphysical),
        "Cannot export Connect IQ settings: CP/W' are non-physical (<= 0). The power-duration fit is corrupt - check the source files or widen the CP fit window."))
      et <- est_table(); v <- setNames(et$value, et$param)
      keys <- c("CP","Wprime","fP","pPmax","tauP","tauG","lt1Frac","eta","fatK","gFat","tauAer","tauOn")   # match properties.xml
      body <- paste(vapply(keys, function(k) sprintf('  "%s": %s', k, format(v[[k]], trim = TRUE)), character(1)), collapse = ",\n")
      writeLines(c("{", body, "}"), file)
    })

  output$dl_yaml <- downloadHandler(
    filename = function() paste0("dualtank_readings_", Sys.Date(), ".yaml"),
    content = function(file) {
      cur <- current_reading(); et <- est_table()
      newr <- as.list(cur); newr$flags <- et$param[et$uncertain]
      # Record the hard non-physical condition explicitly so it round-trips through history
      # (change to est_table already puts CP/Wprime in flags when non-physical).
      if (isTRUE(cpfit()$nonphysical)) newr$flags <- union(newr$flags, "nonphysical")
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
