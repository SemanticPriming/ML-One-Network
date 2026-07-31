#!/usr/bin/env Rscript

# Shared setup for the ML-One-Network power analysis pipeline.
# Mirrors the pilot/refine approach used in Maria-Familiarity
# (run_estimate_r_ss_batch.R), adapted to read jobs from
# power_job_list.csv and pull item data from the SPAML
# todo_semanticprimeR completed datasets.
#
# POS / word-length / stroke-count subgroup analyses are not used here -
# only overall (whole-dataset) precision and split-half reliability.

VARIABLES <- c("familiar", "concrete", "valence", "arousal", "imagine", "aoa")

DATA_DIR <- "/Users/erinbuchanan/GitHub/Research/2_projects/SPAML/todo_semanticprimeR/datasets/completed"
JOB_LIST_FILE <- "power_job_list.csv"

attach_required_packages <- function() {
  pkgs <- c("rio", "dplyr", "semanticprimeR", "purrr", "tidyr", "truncnorm", "psych",
            "tibble")

  for (pkg in pkgs) {
    suppressPackageStartupMessages(
      library(pkg, character.only = TRUE)
    )
  }
}

load_shared_functions <- function(path = "functions.R") {
  if (!file.exists(path)) {
    stop("Missing shared functions file: ", path)
  }
  source(path, local = .GlobalEnv)
}

log_line <- function(..., log_file = "power_batch.log") {
  msg <- paste0("[", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "] ", paste(..., collapse = ""))
  cat(msg, "\n")
  cat(msg, "\n", file = log_file, append = TRUE)
}

normalize_percent_below <- function(x) {
  x <- as.numeric(x)
  if (length(x) == 0 || all(is.na(x))) {
    return(x)
  }

  if (max(x, na.rm = TRUE) <= 1.5) {
    return(x * 100)
  }

  x
}

recommend_followup_window <- function(curve,
                                      lower_target = 70,
                                      upper_target = 95,
                                      min_start = 20,
                                      max_stop = 500,
                                      step = 5) {
  if (is.null(curve) || nrow(curve) == 0) {
    return(tibble::tibble(
      lower_target = lower_target,
      upper_target = upper_target,
      start_sample_size = NA_real_,
      stop_sample_size = NA_real_,
      lower_hit_sample_size = NA_real_,
      upper_hit_sample_size = NA_real_,
      max_percent_below = NA_real_
    ))
  }

  curve <- dplyr::arrange(
    dplyr::mutate(
      curve,
      percent_below = normalize_percent_below(percent_below),
      sample_size = as.numeric(sample_size)
    ),
    sample_size
  )

  lower_hit <- dplyr::slice_head(
    dplyr::filter(curve, percent_below >= lower_target),
    n = 1
  )
  upper_hit <- dplyr::slice_head(
    dplyr::filter(curve, percent_below >= upper_target),
    n = 1
  )

  lower_sample <- if (nrow(lower_hit) > 0) lower_hit$sample_size[[1]] else NA_real_
  upper_sample <- if (nrow(upper_hit) > 0) upper_hit$sample_size[[1]] else NA_real_

  start_sample_size <- if (!is.na(lower_sample)) {
    floor(lower_sample / step) * step
  } else {
    min_start
  }
  start_sample_size <- max(min_start, start_sample_size)

  stop_sample_size <- if (!is.na(upper_sample)) {
    ceiling(upper_sample / step) * step
  } else {
    max(curve$sample_size, na.rm = TRUE)
  }
  stop_sample_size <- min(max_stop, stop_sample_size)

  if (stop_sample_size < start_sample_size) {
    stop_sample_size <- min(
      max_stop,
      max(
        start_sample_size,
        ceiling(max(curve$sample_size, na.rm = TRUE) / step) * step
      )
    )
  }

  tibble::tibble(
    lower_target = lower_target,
    upper_target = upper_target,
    start_sample_size = start_sample_size,
    stop_sample_size = stop_sample_size,
    lower_hit_sample_size = lower_sample,
    upper_hit_sample_size = upper_sample,
    max_percent_below = max(curve$percent_below, na.rm = TRUE)
  )
}

extract_overall_curve <- function(run_obj) {
  if (is.list(run_obj) && !is.null(run_obj$overall_curve)) {
    return(run_obj$overall_curve)
  }
  if (is.list(run_obj) && !is.null(run_obj$proportion_summary)) {
    return(run_obj$proportion_summary)
  }
  NULL
}

extract_overall_rel <- function(run_obj) {
  if (is.list(run_obj) && !is.null(run_obj$overall_rel)) {
    return(run_obj$overall_rel)
  }
  NULL
}

# The precision curve (percent_below) drives recommend_followup_window()'s
# start/stop, but split-half reliability often crosses its target at a much
# smaller sample size than precision does - reusing the precision-derived
# window for reliability silently never tests those smaller sizes, so the
# refine stage's "n needed for target reliability" ends up equal to whatever
# the precision window's floor was, not a real crossing point. This finds
# where the *pilot's own* reliability curve (already computed over the full
# 5-500 sweep) first reaches the target - uncapped, so it can report a true
# crossing point below the practical min_start floor (e.g. n=5-15) as a
# sanity check that min_start is comfortably above where reliability
# actually clears the target. build_followup_manifest() still clamps the
# window it derives from this to min_start before using it anywhere.
recommend_reliability_start <- function(rel_curve, target = 80, min_start = 5, step = 5) {
  if (is.null(rel_curve) || nrow(rel_curve) == 0) {
    return(NA_real_)
  }

  rel_curve <- dplyr::arrange(
    dplyr::mutate(
      rel_curve,
      reliability_m = as.numeric(reliability_m),
      sample_size = as.numeric(sample_size)
    ),
    sample_size
  )

  hit <- dplyr::slice_head(
    dplyr::filter(rel_curve, is.finite(reliability_m), reliability_m * 100 >= target),
    n = 1
  )

  if (nrow(hit) == 0) {
    return(NA_real_)
  }

  max(min_start, floor(hit$sample_size[[1]] / step) * step)
}

build_followup_manifest <- function(jobs,
                                    out_dir,
                                    lower_target = 70,
                                    upper_target = 95,
                                    min_start = 20,
                                    max_stop = 500,
                                    step = 5,
                                    reliability_target = 80) {
  purrr::pmap_dfr(
    jobs,
    function(name, data_file, item_col, mean_col, sd_col, n_per_item, min_score, max_score, n_items, output, status) {
      out_file <- file.path(out_dir, output)
      if (!file.exists(out_file)) {
        return(tibble::tibble(
          name = name,
          output = output,
          status = status,
          pilot_file = out_file,
          lower_target = lower_target,
          upper_target = upper_target,
          start_sample_size = NA_real_,
          stop_sample_size = NA_real_,
          lower_hit_sample_size = NA_real_,
          upper_hit_sample_size = NA_real_,
          max_percent_below = NA_real_,
          reliability_hit_sample_size = NA_real_
        ))
      }

      run_obj <- readRDS(out_file)
      curve <- extract_overall_curve(run_obj)
      window <- recommend_followup_window(
        curve = curve,
        lower_target = lower_target,
        upper_target = upper_target,
        min_start = min_start,
        max_stop = max_stop,
        step = step
      )

      # Detect reliability's *true* crossing point uncapped (step-rounded,
      # but not forced up to min_start) so reliability_hit_sample_size can
      # confirm it's comfortably below the practical min_start floor - it's
      # a diagnostic value, not itself a recommendation. start_sample_size
      # (what actually drives the refine-stage window and gets reported) is
      # still never allowed below min_start.
      reliability_start <- recommend_reliability_start(
        rel_curve = extract_overall_rel(run_obj),
        target = reliability_target,
        min_start = step,
        step = step
      )
      window$reliability_hit_sample_size <- reliability_start
      if (!is.na(reliability_start)) {
        window$start_sample_size <- max(min_start, min(window$start_sample_size, reliability_start))
      }

      dplyr::bind_cols(
        tibble::tibble(
          name = name,
          output = output,
          status = status,
          pilot_file = out_file
        ),
        window
      )
    }
  )
}

# Builds the job table for one variable (familiar / concrete / valence /
# arousal / imagine) from power_job_list.csv. Only rows with a filled-in
# n_per_item are runnable - rows still awaiting manual lookup are skipped
# until the CSV is updated.
build_jobs <- function(variable, job_list_file = JOB_LIST_FILE, data_dir = DATA_DIR) {
  if (!variable %in% VARIABLES) {
    stop("Unknown variable: ", variable, " - expected one of ", paste(VARIABLES, collapse = ", "))
  }

  job_list <- utils::read.csv(job_list_file, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  job_list <- job_list[job_list$variable == variable, , drop = FALSE]

  # n_per_item may contain non-numeric placeholders (e.g. "*" for
  # "estimate not yet confirmed") - treat those as not-yet-filled-in.
  job_list$n_per_item <- suppressWarnings(as.numeric(job_list$n_per_item))
  job_list <- job_list[!is.na(job_list$n_per_item), , drop = FALSE]

  if (nrow(job_list) == 0) {
    return(data.frame(
      name = character(), data_file = character(), item_col = character(),
      mean_col = character(), sd_col = character(), n_per_item = numeric(),
      min_score = numeric(), max_score = numeric(), n_items = numeric(),
      output = character(), status = character(), stringsAsFactors = FALSE
    ))
  }

  name <- tools::file_path_sans_ext(job_list$dataset)

  data.frame(
    name = name,
    data_file = file.path(data_dir, job_list$dataset),
    item_col = job_list$word_column,
    mean_col = job_list$mean_column,
    sd_col = job_list$sd_column,
    n_per_item = as.numeric(job_list$n_per_item),
    min_score = as.numeric(job_list$min_score),
    max_score = as.numeric(job_list$max_score),
    n_items = as.numeric(job_list$n_items),
    output = paste0(name, ".rds"),
    status = "ready",
    stringsAsFactors = FALSE
  )
}

# Peak memory for the normal pipeline (run_job()/run_simulation_pipeline())
# scales *roughly* with the sum across every sample-size step, because
# run_population_pipeline() holds every step's simulated samples in one
# list for the whole job (needed again later for reliability) rather than
# freeing each step as it's used. estimate_sim_rows() approximates that
# peak as n_items * nsim * sum(seq(start, stop, increase)) - but this is
# only a rough proxy, not a reliable predictor: Clarke2024 (imagine,
# ~4.2 billion estimated rows) used 85GB and didn't finish, while
# Montefinese2023_en (concrete, ~4.7 billion - a *higher* estimate)
# finished fine in ~12 minutes. Something beyond raw row volume drives the
# actual blowups (possibly internal to semanticprimeR::simulate_samples(),
# which isn't inspectable from here). Since the estimate can't reliably
# separate safe from unsafe jobs, CHUNKED_ROW_BUDGET is set well below
# every observed-safe job (smallest was ~1.9 billion, Raslescu2023) rather
# than at some midpoint - i.e. err heavily toward chunking. Jobs still get
# monitored live and killed/retried if one somehow slips through anyway.
CHUNKED_ROW_BUDGET <- 1.5e9

estimate_sim_rows <- function(n_items, start, stop, increase, nsim) {
  sample_sizes <- seq(start, stop, by = increase)
  n_items * nsim * sum(sample_sizes)
}

needs_chunked_run <- function(n_items, start, stop, increase, nsim,
                              budget = CHUNKED_ROW_BUDGET) {
  is.finite(n_items) &&
    estimate_sim_rows(n_items, start, stop, increase, nsim) > budget
}

run_job <- function(job,
                    skip_existing = TRUE,
                    out_dir = "simulations",
                    start = 20,
                    stop = 100,
                    increase = 5,
                    nsim = 100,
                    power_levels = c(80, 85, 90, 95),
                    max_rows = 1000,
                    log_file = "power_batch.log") {
  out_file <- file.path(out_dir, job$output)

  if (skip_existing && file.exists(out_file)) {
    log_line("skip ", job$name, " -> existing ", out_file, log_file = log_file)
    return(invisible(list(status = "skipped", file = out_file)))
  }

  log_line("start ", job$name, " -> ", out_file, log_file = log_file)

  df <- rio::import(job$data_file)
  on.exit({
    rm(df)
    gc()
  }, add = TRUE)

  log_line("imported ", job$name, " rows: ", nrow(df), log_file = log_file)

  if (!is.null(max_rows) && nrow(df) > max_rows) {
    log_line(
      "sampling ",
      max_rows,
      " rows for ",
      job$name,
      " test run",
      log_file = log_file
    )
    df <- dplyr::slice_sample(df, n = max_rows)
  }

  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  saved_sim <- run_simulation_pipeline(
    df = df,
    item_col = job$item_col,
    mean_col = job$mean_col,
    sd_col = job$sd_col,
    n_per_item = job$n_per_item,
    min_score = job$min_score,
    max_score = job$max_score,
    start = start,
    stop = stop,
    increase = increase,
    nsim = nsim,
    power_levels = power_levels,
    out_file = out_file
  )

  save_data <- build_save_data(saved_sim)
  saveRDS(save_data, out_file)

  rm(saved_sim, save_data)
  gc()

  log_line("done ", job$name, " -> ", out_file, log_file = log_file)
  invisible(list(status = "done", file = out_file))
}

# Same contract as run_job(), but for jobs whose window is large enough
# that run_job()/run_simulation_pipeline() risks exhausting memory (see
# CHUNKED_ROW_BUDGET / needs_chunked_run() above). Delegates to
# run_simulation_pipeline_chunked(), which simulates and summarizes one
# sample size at a time instead of holding every step in memory at once,
# and checkpoints out_file after every step. Only intended to be called
# for jobs needs_chunked_run() flags - normal-sized jobs should keep using
# run_job(), which is simpler and already well-exercised.
run_job_chunked <- function(job,
                            skip_existing = TRUE,
                            out_dir = "simulations",
                            start = 20,
                            stop = 100,
                            increase = 5,
                            nsim = 100,
                            power_levels = c(80, 85, 90, 95),
                            max_rows = 1000,
                            log_file = "power_batch.log") {
  out_file <- file.path(out_dir, job$output)

  if (skip_existing && file.exists(out_file)) {
    log_line("skip ", job$name, " -> existing ", out_file, log_file = log_file)
    return(invisible(list(status = "skipped", file = out_file)))
  }

  log_line("start (chunked) ", job$name, " -> ", out_file, log_file = log_file)

  df <- rio::import(job$data_file)
  on.exit({
    rm(df)
    gc()
  }, add = TRUE)

  log_line("imported ", job$name, " rows: ", nrow(df), log_file = log_file)

  if (!is.null(max_rows) && nrow(df) > max_rows) {
    log_line(
      "sampling ",
      max_rows,
      " rows for ",
      job$name,
      " test run",
      log_file = log_file
    )
    df <- dplyr::slice_sample(df, n = max_rows)
  }

  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  saved_sim <- run_simulation_pipeline_chunked(
    df = df,
    item_col = job$item_col,
    mean_col = job$mean_col,
    sd_col = job$sd_col,
    n_per_item = job$n_per_item,
    min_score = job$min_score,
    max_score = job$max_score,
    start = start,
    stop = stop,
    increase = increase,
    nsim = nsim,
    power_levels = power_levels,
    out_file = out_file,
    log_file = log_file
  )

  rm(saved_sim)
  gc()

  log_line("done ", job$name, " -> ", out_file, log_file = log_file)
  invisible(list(status = "done", file = out_file))
}

run_jobs_stage <- function(jobs,
                           skip_existing = TRUE,
                           out_dir = "simulations",
                           start = 20,
                           stop = 100,
                           increase = 5,
                           nsim = 100,
                           power_levels = c(80, 85, 90, 95),
                           max_rows = 1000,
                           log_file = "power_batch.log") {
  results <- vector("list", nrow(jobs))
  for (i in seq_len(nrow(jobs))) {
    job <- jobs[i, , drop = FALSE]
    results[[i]] <- tryCatch(
      run_job(
        job,
        skip_existing = skip_existing,
        out_dir = out_dir,
        start = start,
        stop = stop,
        increase = increase,
        nsim = nsim,
        power_levels = power_levels,
        max_rows = max_rows,
        log_file = log_file
      ),
      error = function(e) {
        log_line("error ", job$name, ": ", conditionMessage(e), log_file = log_file)
        NULL
      }
    )
  }

  invisible(results)
}
