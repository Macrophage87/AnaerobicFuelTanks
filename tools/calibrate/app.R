# Dual-Tank Parameter Estimator — R Shiny (sketch)
# --------------------------------------------------------------------------
# Upload several .FIT files -> build a mean-maximal power (MMP) curve across
# them -> estimate the parameters that feed the AnaerobicFuelTanks Connect IQ
# data field.
#
# IDENTIFIABILITY (read the README): from single maximal efforts only CP and W'
# are identifiable (t_lim = W'/(P-CP)). Pmax gives a practical pPmax. The
# PCr/glycolytic split (fP) and the recovery constants (tauP, tauG, eta, ...)
# do NOT affect a single all-out effort and are therefore DEFAULTED here; they
# need an intermittent / repeated-effort protocol to fit (see README).
#
# install.packages(c("shiny","zoo","ggplot2","DT"))
# remotes::install_github("grimbough/FITfileR")
# --------------------------------------------------------------------------

library(shiny)
library(zoo)
library(ggplot2)
suppressWarnings(suppressMessages(library(FITfileR)))

# ---- durations (s) sampled for the power-duration curve --------------------
DURATIONS <- c(1,5,10,15,20,30,45,60,90,120,180,240,300,420,600,720,900,1200,1800,2400,3600)

# ---- FIT -> 1 Hz power vector ---------------------------------------------
read_power <- function(path) {
  ff <- try(readFitFile(path), silent = TRUE)
  if (inherits(ff, "try-error")) return(NULL)
  recs <- try(records(ff), silent = TRUE)
  if (inherits(recs, "try-error")) return(NULL)
  if (is.data.frame(recs)) recs <- list(recs)
  pw <- unlist(lapply(recs, function(df)
    if ("power" %in% names(df)) as.numeric(df$power) else numeric(0)))
  pw <- pw[is.finite(pw)]
  if (length(pw) < 2) NULL else pw
}

# ---- best mean power over a window of d seconds (cumsum trick) -------------
best_mean_power <- function(p, d) {
  n <- length(p)
  if (n < d) return(NA_real_)
  cs <- cumsum(c(0, p))
  max((cs[(d + 1):(n + 1)] - cs[1:(n - d + 1)]) / d)
}

# ---- MMP curve = best power per duration across all files -----------------
mmp_curve <- function(power_list, durations = DURATIONS) {
  vapply(durations, function(d) {
    vals <- vapply(power_list, best_mean_power, numeric(1), d = d)
    if (all(is.na(vals))) NA_real_ else max(vals, na.rm = TRUE)
  }, numeric(1))
}

# ---- CP / W' via the linear work model  W = CP*t + W' ---------------------
fit_cp <- function(dur, pw, tmin, tmax) {
  keep <- which(dur >= tmin & dur <= tmax & is.finite(pw))
  if (length(keep) < 2) return(NULL)
  t <- dur[keep]; W <- pw[keep] * t
  f <- lm(W ~ t)
  list(CP = unname(coef(f)[2]), Wprime = unname(coef(f)[1]),
       r2 = summary(f)$r.squared, n = length(keep),
       t = t, W = W, fit = f)
}

# ---- defaults for the parameters best efforts cannot identify -------------
DEFAULTS <- list(tauP = 22, tauG = 360, lt1Frac = 0.80, eta = 0.80,
                 fatK = 0.75, tauAer = 25)

# ===========================================================================
ui <- fluidPage(
  titlePanel("Dual-Tank Parameter Estimator"),
  sidebarLayout(
    sidebarPanel(
      fileInput("files", "FIT files (several rides / best-effort tests)",
                multiple = TRUE, accept = c(".fit", ".FIT")),
      helpText("Include your best short sprint and best 3-15 min efforts."),
      hr(),
      sliderInput("cpwin", "CP fit window (min)", min = 1, max = 30,
                  value = c(2, 12), step = 1),
      helpText("Fit CP/W' on maximal efforts in this window (2-12 min is typical)."),
      sliderInput("fP", "PCr share of W' (fP) — NOT from data",
                  min = 0.1, max = 0.6, value = 0.35, step = 0.01),
      helpText("Defaulted: single efforts can't resolve the split. See notes."),
      hr(),
      downloadButton("dl_mmp", "Download MMP curve (CSV)")
    ),
    mainPanel(
      tabsetPanel(
        tabPanel("Power-duration",
          plotOutput("mmp_plot", height = 320),
          DT::dataTableOutput("mmp_tbl")),
        tabPanel("CP / W' fit",
          plotOutput("cp_plot", height = 320),
          verbatimTextOutput("cp_txt")),
        tabPanel("App parameters",
          h4("Paste these into the Connect IQ field settings"),
          verbatimTextOutput("params"),
          tags$hr(),
          htmlOutput("caveats"))
      )
    )
  )
)

# ===========================================================================
server <- function(input, output, session) {

  powers <- reactive({
    req(input$files)
    ps <- lapply(input$files$datapath, read_power)
    ps <- Filter(Negate(is.null), ps)
    validate(need(length(ps) > 0, "No readable power data in those files."))
    ps
  })

  mmp <- reactive({
    data.frame(duration = DURATIONS, power = mmp_curve(powers()))
  })

  cpfit <- reactive({
    m <- mmp()
    fit_cp(m$duration, m$power, input$cpwin[1] * 60, input$cpwin[2] * 60)
  })

  # --- power-duration curve + model overlay ---
  output$mmp_plot <- renderPlot({
    m <- mmp(); f <- cpfit()
    g <- ggplot(subset(m, is.finite(power)), aes(duration, power)) +
      geom_line(colour = "grey60") + geom_point(size = 2) +
      scale_x_log10() + labs(x = "duration (s, log)", y = "best mean power (W)") +
      theme_minimal(base_size = 13)
    if (!is.null(f)) {
      tt <- 10 ^ seq(log10(30), log10(3600), length.out = 200)
      g <- g + geom_line(data = data.frame(duration = tt,
                       power = f$CP + f$Wprime / tt),
                       aes(duration, power), colour = "#B44DFF", linewidth = 1) +
        geom_hline(yintercept = f$CP, linetype = 2, colour = "#37E85A")
    }
    g
  })

  output$mmp_tbl <- DT::renderDataTable(
    DT::datatable(transform(mmp(), power = round(power)), rownames = FALSE,
                  options = list(pageLength = 8, dom = "tp")))

  # --- work-time regression ---
  output$cp_plot <- renderPlot({
    f <- cpfit(); validate(need(!is.null(f), "Need >=2 efforts in the fit window."))
    ggplot(data.frame(t = f$t, W = f$W), aes(t, W)) +
      geom_point(size = 2) +
      geom_abline(intercept = f$Wprime, slope = f$CP, colour = "#B44DFF", linewidth = 1) +
      labs(x = "time (s)", y = "work above 0 (J)  |  W = CP*t + W'") +
      theme_minimal(base_size = 13)
  })

  output$cp_txt <- renderText({
    f <- cpfit(); req(f)
    sprintf("CP     = %.0f W\nW'     = %.0f J\nR^2    = %.3f  (n = %d efforts)",
            f$CP, f$Wprime, f$r2, f$n)
  })

  # --- parameter block for the app ---
  output$params <- renderText({
    f <- cpfit(); req(f)
    m <- mmp()
    p5 <- m$power[m$duration == 5]
    pPmax <- if (is.finite(p5)) max(50, round(p5 - f$CP)) else 300
    d <- DEFAULTS
    paste(
      sprintf("CP      = %d", round(f$CP)),
      sprintf("Wprime  = %d", round(f$Wprime)),
      sprintf("fP      = %.2f      # default (not from best efforts)", input$fP),
      sprintf("pPmax   = %d       # from 5 s peak power - CP", pPmax),
      sprintf("tauP    = %d        # default", d$tauP),
      sprintf("tauG    = %d       # default", d$tauG),
      sprintf("lt1Frac = %.2f      # default", d$lt1Frac),
      sprintf("eta     = %.2f      # default", d$eta),
      sprintf("fatK    = %.2f      # default", d$fatK),
      sprintf("tauAer  = %d        # default", d$tauAer),
      sep = "\n")
  })

  output$caveats <- renderUI(HTML(paste0(
    "<b>What is estimated vs defaulted</b><br>",
    "&bull; <b>CP, W'</b> &mdash; fit from your best efforts (reliable).<br>",
    "&bull; <b>pPmax</b> &mdash; from 5 s peak power minus CP (practical proxy).<br>",
    "&bull; <b>fP, tauP, tauG, eta, lt1Frac, fatK, tauAer</b> &mdash; DEFAULTED. A single ",
    "maximal effort satisfies t_lim = W'/(P-CP), independent of the tank split and ",
    "recovery rates, so best efforts cannot identify them. To fit these, add an ",
    "intermittent protocol (e.g. repeated 15-30 s sprints with fixed recoveries, or ",
    "on/off intervals) and fit the model's reconstitution to the observed recovery.")))

  output$dl_mmp <- downloadHandler(
    filename = "mmp_curve.csv",
    content = function(file) write.csv(mmp(), file, row.names = FALSE))
}

shinyApp(ui, server)
