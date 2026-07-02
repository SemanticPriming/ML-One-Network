#!/usr/bin/env Rscript

# Pilot stage: for each variable (familiar, concrete, valence, arousal,
# imagine), run a broad AIPE simulation sweep (20-500 participants, step
# 10, 10 sims/step) over every dataset in power_job_list.csv that has that
# variable and a filled-in n_per_item. The resulting power curves are used
# to pick a narrower start/stop sample-size window for the refine stage.
#
# Mirrors Maria-Familiarity/run_estimate_r_ss_pilot.R, run once per variable.

this_dir <- function() {
  cmd <- commandArgs(trailingOnly = FALSE)
  file_arg <- sub("^--file=", "", cmd[grep("^--file=", cmd)])
  if (length(file_arg) > 0) {
    return(dirname(normalizePath(file_arg[[1]])))
  }
  getwd()
}

setwd(this_dir())
source("run_power_batch.R")

run_pilot_for_variable <- function(variable) {
  out_dir <- file.path("simulations", variable, "pilot")
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  log_file <- file.path(out_dir, "pilot.log")
  log_line("=== pilot: ", variable, " ===", log_file = log_file)

  jobs <- build_jobs(variable)
  jobs <- jobs[jobs$status != "done", , drop = FALSE]

  if (nrow(jobs) == 0) {
    log_line("no jobs with n_per_item filled in for '", variable, "' - skipping", log_file = log_file)
    return(invisible(NULL))
  }

  log_line(nrow(jobs), " job(s) ready for '", variable, "'", log_file = log_file)

  shard_total <- as.integer(Sys.getenv("SHARD_TOTAL", "1"))
  shard_index <- as.integer(Sys.getenv("SHARD_INDEX", "1"))
  if (!is.na(shard_total) && shard_total > 1) {
    if (is.na(shard_index) || shard_index < 1 || shard_index > shard_total) {
      stop("Set SHARD_INDEX to a value between 1 and SHARD_TOTAL.")
    }
    keep <- ((seq_len(nrow(jobs)) - 1L) %% shard_total) + 1L == shard_index
    jobs <- jobs[keep, , drop = FALSE]
    log_line(
      "using shard ", shard_index, "/", shard_total, " with ", nrow(jobs), " jobs",
      log_file = log_file
    )
  }

  run_jobs_stage(
    jobs = jobs,
    skip_existing = TRUE,
    out_dir = out_dir,
    start = 20,
    stop = 500,
    increase = 10,
    nsim = 10,
    power_levels = c(70, 75, 80, 85, 90, 95),
    log_file = log_file
  )

  manifest <- build_followup_manifest(
    jobs = jobs,
    out_dir = out_dir,
    lower_target = 70,
    upper_target = 95,
    min_start = 20,
    max_stop = 500,
    step = 5
  )

  utils::write.csv(
    manifest,
    file = file.path(out_dir, "pilot_grid_manifest.csv"),
    row.names = FALSE
  )
  saveRDS(manifest, file = file.path(out_dir, "pilot_grid_manifest.rds"))

  log_line("pilot manifest written for '", variable, "'", log_file = log_file)
  invisible(manifest)
}

main <- function() {
  attach_required_packages()
  load_shared_functions("functions.R")

  variables_to_run <- Sys.getenv("POWER_VARIABLES", "")
  variables_to_run <- if (nzchar(variables_to_run)) {
    trimws(strsplit(variables_to_run, ",")[[1]])
  } else {
    VARIABLES
  }

  results <- lapply(variables_to_run, run_pilot_for_variable)
  names(results) <- variables_to_run
  invisible(results)
}

if (sys.nframe() == 0L) main()
