# Dual-Tank Parameter Estimator — R Shiny (sketch)
# --------------------------------------------------------------------------
# Upload SEVERAL .FIT files and get one parameter set, picking the best value
# for each parameter across all of them:
#   * CP, W', pPmax  -> combined mean-maximal power curve (best-of-all).
#   * fP, tauP, tauG, eta -> fit the dual-tank model on each variable-power ride
#     by anchoring "reserve = 0" at maximal / cracked moments, then aggregate.
#
# Anchors are set with a CLICK-TO-ANCHOR editor on each ride's reserve trace:
# click to add an anchor, click near one to remove it. Rides with no manual
# anchors fall back to auto-suggested lowest-reserve points.
#
# IDENTIFIABILITY: a single maximal effort obeys t_lim = W'/(P-CP) -> only CP/W'.
# The split/recovery rates appear only across repeated efforts with recovery and
# only where a ride has reserve=0 anchors (final sprint, an attack you couldn't
# follow, the moment you got dropped).
#
# install.packages(c("shiny","ggplot2","DT"))
# remotes::install_github("grimbough/FITfileR")
# --------------------------------------------------------------------------

library(shiny)
library(ggplot2)
suppressWarnings(suppressMessages(library(FITfileR)))

DURATIONS <- c(1,5,10,15,20,30,45,60,90,120,180,240,300,420,600,720,900,1200,1800,2400,3600)
DEFAULTS  <- list(fP = 0.35, pPmax = 300, tauP = 22, tauG = 360,
                  lt1Frac = 0.80, eta = 0.80, fatK = 0.75, tauAer = 25)

read_power <- function(path) {
  ff <- try(readFitFile(path), silent = TRUE); if (inherits(ff, "try-error")) return(NULL)
  recs <- try(records(ff), silent = TRUE);     if (inherits(recs, "try-error")) return(NULL)
  if (is.data.frame(recs)) recs <- list(recs)
  pw <- unlist(lapply(recs, function(df)
    if ("power" %in% names(df)) as.numeric(df$power) else numeric(0)))
  pw <- pw[is.finite(pw)]; if (length(pw) < 2) NULL else pw
}
best_mean_power <- function(p, d) {
  n <- length(p); if (n < d) return(NA_real_)
  cs <- cumsum(c(0, p)); max((cs[(d + 1):(n + 1)] - cs[1:(n - d + 1)]) / d)
}
mmp_curve <- function(power_list, durations = DURATIONS)
  vapply(durations, function(d) {
    v <- vapply(power_list, best_mean_power, numeric(1), d = d)
    if (all(is.na(v))) NA_real_ else max(v, na.rm = TRUE)
  }, numeric(1))
fit_cp <- function(dur, pw, tmin, tmax) {
  keep <- which(dur >= tmin & dur <= tmax & is.finite(pw)); if (length(keep) < 2) return(NULL)
  t <- dur[keep]; W <- pw[keep] * t; f <- lm(W ~ t)
  list(CP = unname(coef(f)[2]), Wprime = unname(coef(f)[1]),
       r2 = summary(f)$r.squared, n = length(keep), t = t, W = W)
}

# ---- dual-tank simulation (mirrors the Connect IQ 1 Hz model) --------------
simulate_tanks <- function(power, cp, par) {
  n <- length(power); cP <- par$fP * par$Wprime; cG <- (1 - par$fP) * par$Wprime
  rP <- cP; rG <- cG; aer <- 0; resTot <- numeric(n); deficit <- numeric(n)
  aP1 <- if (par$tauAer > 0) 1 - exp(-1 / par$tauAer) else 1; bG <- 1 - exp(-1 / par$tauG)
  for (i in seq_len(n)) {
    p <- power[i]
    if (par$tauAer > 0) { tgt <- min(p, cp); aer <- max(0, min(cp, aer + (tgt - aer) * aP1)); supply <- aer }
    else supply <- cp
    delta <- p - supply
    if (delta > 0) {
      need <- delta
      takeP <- min(need, rP, par$pPmax); rP <- rP - takeP; need <- need - takeP
      takeG <- min(need, rG);            rG <- rG - takeG; need <- need - takeG
      deficit[i] <- need
    } else {
      tauPeff <- par$tauP * (1 + par$fatK * (1 - rG / cG))
      rP <- rP + par$eta * (cP - rP) * (1 - exp(-1 / tauPeff))
      lt1 <- par$lt1Frac * cp; if (p < lt1) rG <- rG + ((lt1 - p) / lt1) * (cG - rG) * bG
    }
    rP <- max(0, min(cP, rP)); rG <- max(0, min(cG, rG)); resTot[i] <- rP + rG
  }
  list(total = resTot, deficit = deficit)
}
suggest_marks <- function(power, cp, base) {
  s <- simulate_tanks(power, cp, base); tot <- s$total; n <- length(tot)
  cand <- c(which.min(tot), n)
  lo <- which(tot[-c(1, n)] < 0.20 * base$Wprime) + 1
  if (length(lo)) cand <- c(cand, lo[c(TRUE, diff(lo) > 30)])
  sort(unique(cand))
}
fit_recovery <- function(power, cp, base, marks) {
  Wp <- base$Wprime
  obj <- function(th) {
    par <- base; par$fP <- th[1]; par$tauP <- th[2]; par$tauG <- th[3]; par$eta <- th[4]
    s <- simulate_tanks(power, cp, par)
    5 * mean((s$deficit / Wp) ^ 2) + (if (length(marks)) mean((s$total[marks] / Wp) ^ 2) else 0)
  }
  st <- optim(c(base$fP, base$tauP, base$tauG, base$eta), obj, method = "L-BFGS-B",
              lower = c(0.10, 5, 60, 0.30), upper = c(0.60, 120, 1800, 1.00),
              control = list(maxit = 200))
  list(fP = st$par[1], tauP = st$par[2], tauG = st$par[3], eta = st$par[4],
       obj = st$value, conv = st$convergence, n = length(marks))
}
# per-ride fit, using manual anchors where present (else auto-suggest)
fit_all_rides <- function(power_list, names, cp, base, anchors) {
  rows <- lapply(seq_along(power_list), function(i) {
    p <- power_list[[i]]; man <- anchors[[as.character(i)]]
    src <- if (!is.null(man) && length(man)) "manual" else "auto"
    m <- if (src == "manual") man else suggest_marks(p, cp, base)
    r <- try(fit_recovery(p, cp, base, m), silent = TRUE); if (inherits(r, "try-error")) return(NULL)
    data.frame(file = names[i], anchors = src, n = length(m),
               fP = r$fP, tauP = r$tauP, tauG = r$tauG, eta = r$eta, obj = r$obj, conv = r$conv)
  })
  do.call(rbind, Filter(Negate(is.null), rows))
}

# ===========================================================================
ui <- fluidPage(
  titlePanel("Dual-Tank Parameter Estimator"),
  sidebarLayout(
    sidebarPanel(
      fileInput("files", "FIT files (several rides)", multiple = TRUE, accept = c(".fit", ".FIT")),
      sliderInput("cpwin", "CP fit window (min)", 1, 30, c(2, 12), 1),
      sliderInput("fP", "PCr share of W' (fP) start value", 0.1, 0.6, 0.35, 0.01),
      hr(),
      actionButton("fitall", "Fit fP/tauP/tauG/eta on every ride", class = "btn-primary"),
      radioButtons("agg", "Combine rides by", c("median", "best-fit"), inline = TRUE)
    ),
    mainPanel(tabsetPanel(
      tabPanel("Power-duration", plotOutput("mmp_plot", height = 300), DT::dataTableOutput("mmp_tbl")),
      tabPanel("CP / W' fit", plotOutput("cp_plot", height = 300), verbatimTextOutput("cp_txt")),
      tabPanel("Anchor editor",
        fluidRow(
          column(5, uiOutput("ride_pick")),
          column(3, actionButton("autoone", "Auto-suggest"), actionButton("clearone", "Clear")),
          column(4, verbatimTextOutput("anchor_txt"))),
        helpText("Click the trace to add a maximal/cracked anchor; click near one to remove it."),
        plotOutput("res_plot", height = 300, click = "res_click")),
      tabPanel("Recovery fit (per ride)", DT::dataTableOutput("fit_tbl"), verbatimTextOutput("agg_txt")),
      tabPanel("App parameters", verbatimTextOutput("params"), htmlOutput("caveats"))
    ))
  )
)

# ===========================================================================
server <- function(input, output, session) {
  rv <- reactiveValues(fits = NULL, anchors = list())

  powers <- reactive({
    req(input$files)
    ps <- lapply(input$files$datapath, read_power); keep <- !vapply(ps, is.null, logical(1))
    validate(need(any(keep), "No readable power data."))
    list(p = ps[keep], names = input$files$name[keep])
  })
  mmp   <- reactive(data.frame(duration = DURATIONS, power = mmp_curve(powers()$p)))
  cpfit <- reactive(fit_cp(mmp()$duration, mmp()$power, input$cpwin[1]*60, input$cpwin[2]*60))
  base_par <- reactive({ f <- cpfit(); req(f); modifyList(DEFAULTS, list(Wprime = f$Wprime, fP = input$fP)) })

  agg <- reactive({
    df <- rv$fits; if (is.null(df)) return(NULL)
    ok <- df[df$conv == 0, , drop = FALSE]; if (!nrow(ok)) ok <- df
    if (input$agg == "best-fit") { b <- ok[which.min(ok$obj), ]
      list(fP = b$fP, tauP = b$tauP, tauG = b$tauG, eta = b$eta, src = paste("best-fit:", b$file))
    } else list(fP = median(ok$fP), tauP = median(ok$tauP), tauG = median(ok$tauG),
                eta = median(ok$eta), src = sprintf("median of %d rides", nrow(ok)))
  })

  # ---- best-efforts tabs ----
  output$mmp_plot <- renderPlot({
    m <- mmp(); f <- cpfit()
    g <- ggplot(subset(m, is.finite(power)), aes(duration, power)) +
      geom_line(colour = "grey60") + geom_point(size = 2) + scale_x_log10() +
      labs(x = "duration (s, log)", y = "best mean power (W)") + theme_minimal(base_size = 13)
    if (!is.null(f)) g <- g +
      geom_line(data = data.frame(duration = (tt <- 10^seq(log10(30), log10(3600), length.out = 200)),
                                  power = f$CP + f$Wprime / tt), colour = "#B44DFF", linewidth = 1) +
      geom_hline(yintercept = f$CP, linetype = 2, colour = "#37E85A")
    g
  })
  output$mmp_tbl <- DT::renderDataTable(DT::datatable(
    transform(mmp(), power = round(power)), rownames = FALSE, options = list(pageLength = 8, dom = "tp")))
  output$cp_plot <- renderPlot({
    f <- cpfit(); validate(need(!is.null(f), "Need >=2 efforts in the window."))
    ggplot(data.frame(t = f$t, W = f$W), aes(t, W)) + geom_point(size = 2) +
      geom_abline(intercept = f$Wprime, slope = f$CP, colour = "#B44DFF", linewidth = 1) +
      labs(x = "time (s)", y = "work (J) = CP*t + W'") + theme_minimal(base_size = 13)
  })
  output$cp_txt <- renderText({ f <- cpfit(); req(f)
    sprintf("CP = %.0f W   W' = %.0f J   R^2 = %.3f (n = %d, best across all files)", f$CP, f$Wprime, f$r2, f$n) })

  # ---- anchor editor ----
  output$ride_pick <- renderUI({
    pw <- powers(); selectInput("ride", "Ride", choices = setNames(seq_along(pw$p), pw$names)) })
  ride_idx   <- reactive({ req(input$ride); as.integer(input$ride) })
  ride_power <- reactive({ powers()$p[[ride_idx()]] })

  observeEvent(input$res_click, {
    p <- ride_power(); req(p); x <- round(input$res_click$x)
    if (x < 1 || x > length(p)) return()
    key <- as.character(ride_idx()); cur <- rv$anchors[[key]]; if (is.null(cur)) cur <- integer(0)
    tol <- max(5, round(length(p) * 0.01)); near <- which(abs(cur - x) <= tol)
    rv$anchors[[key]] <- if (length(near)) cur[-near] else sort(c(cur, x))
  })
  observeEvent(input$autoone, {
    f <- cpfit(); p <- ride_power(); req(f, p)
    rv$anchors[[as.character(ride_idx())]] <- suggest_marks(p, f$CP, base_par()) })
  observeEvent(input$clearone, { rv$anchors[[as.character(ride_idx())]] <- integer(0) })

  output$anchor_txt <- renderText({
    a <- rv$anchors[[as.character(ride_idx())]]
    if (is.null(a) || !length(a)) "no manual anchors (auto will be used)" else paste("anchors (s):", paste(a, collapse = ", "))
  })
  output$res_plot <- renderPlot({
    f <- cpfit(); p <- ride_power(); req(f, p)
    par <- base_par(); a <- agg(); if (!is.null(a)) par <- modifyList(par, a[c("fP","tauP","tauG","eta")])
    s <- simulate_tanks(p, f$CP, par)
    df <- data.frame(t = seq_along(p), pct = 100 * s$total / par$Wprime)
    anch <- rv$anchors[[as.character(ride_idx())]]
    g <- ggplot(df, aes(t, pct)) + geom_line(colour = "#B44DFF") + ylim(0, 100) +
      labs(x = "time (s)", y = "total reserve (% W')",
           title = if (is.null(a)) "default params — click to anchor" else "fitted params — click to anchor") +
      theme_minimal(base_size = 13)
    if (!is.null(anch) && length(anch)) g <- g + geom_vline(xintercept = anch, colour = "#FF0000", linetype = 2)
    g
  })

  # ---- fit + results ----
  observeEvent(input$fitall, {
    f <- cpfit(); pw <- powers(); req(f)
    rv$fits <- fit_all_rides(pw$p, pw$names, f$CP, base_par(), rv$anchors)
  })
  output$fit_tbl <- DT::renderDataTable({
    validate(need(!is.null(rv$fits), "Set anchors (Anchor editor), then 'Fit ... on every ride'."))
    d <- rv$fits; num <- c("fP","tauP","tauG","eta","obj"); d[num] <- lapply(d[num], round, 3)
    DT::datatable(d, rownames = FALSE, options = list(pageLength = 10, dom = "tp"))
  })
  output$agg_txt <- renderText({ a <- agg(); if (is.null(a)) return("")
    sprintf("Chosen (%s):  fP = %.2f   tauP = %.0f s   tauG = %.0f s   eta = %.2f", a$src, a$fP, a$tauP, a$tauG, a$eta) })

  output$params <- renderText({
    f <- cpfit(); req(f); m <- mmp(); a <- agg()
    p5 <- m$power[m$duration == 5]; pPmax <- if (is.finite(p5)) max(50, round(p5 - f$CP)) else DEFAULTS$pPmax
    fP <- if (is.null(a)) input$fP else a$fP; tauP <- if (is.null(a)) DEFAULTS$tauP else a$tauP
    tauG <- if (is.null(a)) DEFAULTS$tauG else a$tauG; eta <- if (is.null(a)) DEFAULTS$eta else a$eta
    src <- if (is.null(a)) "default" else a$src
    paste(
      sprintf("CP      = %d        # best across all files", round(f$CP)),
      sprintf("Wprime  = %d      # best across all files", round(f$Wprime)),
      sprintf("pPmax   = %d       # best 5 s across files - CP", pPmax),
      sprintf("fP      = %.2f      # %s", fP, src),
      sprintf("tauP    = %.0f        # %s", tauP, src),
      sprintf("tauG    = %.0f       # %s", tauG, src),
      sprintf("eta     = %.2f      # %s", eta, src),
      sprintf("lt1Frac = %.2f      # default (needs a threshold test)", DEFAULTS$lt1Frac),
      sprintf("fatK    = %.2f      # default", DEFAULTS$fatK),
      sprintf("tauAer  = %d        # default", DEFAULTS$tauAer),
      sep = "\n")
  })
  output$caveats <- renderUI(HTML(paste0(
    "<b>CP, W', pPmax</b> take the best across every file. <b>fP, tauP, tauG, eta</b> are fit per ride ",
    "at your anchors (Anchor editor), then combined by median or best-fit. Anchor efforts with ",
    "<i>different</i> recovery lead-ins to separate fast (PCr) from slow (glycolytic) recovery. A race ",
    "or hard group ride works well &mdash; getting dropped is a natural reserve=0 anchor. <b>lt1Frac, ",
    "fatK, tauAer</b> stay at defaults.")))
}

shinyApp(ui, server)
