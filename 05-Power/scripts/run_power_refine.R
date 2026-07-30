#!/usr/bin/env Rscript

# Refine stage: for each variable, use the pilot power curves
# (simulations/<variable>/pilot) to pick a narrow start/stop sample-size
# window per dataset, then rerun the AIPE simulation in that window with
# more precision (step 5, 100 sims/step).
#
# Mirrors Maria-Familiarity/run_estimate_r_ss_refine.R, run once per variable.
# Requires run_power_pilot.R to have been run first for that variable.

this_dir <- function() {
  cmd <- commandArgs(trailingOnly = FALSE)
  file_arg <- sub("^--file=", "", cmd[grep("^--file=", cmd)])
  if (length(file_arg) > 0) {
    return(dirname(normalizePath(file_arg[[1]])))
  }
  getwd()
}

setwd(dirname(this_dir()))  # 05-Power/ - scripts reference data/output paths relative to it
source("scripts/run_power_batch.R")

run_refine_for_variable <- function(variable) {
  pilot_dir <- file.path("simulations", variable, "pilot")
  out_dir <- file.path("simulations", variable, "refined")
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  log_file <- file.path(out_dir, "refine.log")
  log_line("=== refine: ", variable, " ===", log_file = log_file)

  jobs <- build_jobs(variable)
  jobs <- jobs[jobs$status != "done", , drop = FALSE]

  if (nrow(jobs) == 0) {
    log_line("no jobs with n_per_item filled in for '", variable, "' - skipping", log_file = log_file)
    return(invisible(NULL))
  }

  if (!dir.exists(pilot_dir)) {
    log_line("no pilot output found at ", pilot_dir, " - run run_power_pilot.R first", log_file = log_file)
    return(invisible(NULL))
  }

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

  manifest <- build_followup_manifest(
    jobs = jobs,
    out_dir = pilot_dir,
    lower_target = 70,
    upper_target = 95,
    min_start = 20,
    max_stop = 500,
    step = 5
  )

  manifest$start_sample_size[is.na(manifest$start_sample_size)] <- 20
  manifest$stop_sample_size[is.na(manifest$stop_sample_size)] <- 500

  # Each dataset runs as its own fresh Rscript subprocess rather than
  # looping in-process, so the OS fully reclaims memory when that job's
  # process exits instead of it accumulating across many sequential jobs
  # inside one long-lived R session (see run_single_refine_job.R).
  rscript_bin <- "/usr/local/bin/Rscript"
  single_job_script <- "scripts/run_single_refine_job.R"

  results <- vector("list", nrow(manifest))
  for (i in seq_len(nrow(manifest))) {
    job <- jobs[i, , drop = FALSE]
    start_size <- manifest$start_sample_size[[i]]
    stop_size <- manifest$stop_sample_size[[i]]

    # Estimate against the same n_items cap run_job()/run_job_chunked()
    # apply (max_rows subsampling), so the estimate matches what actually
    # gets simulated.
    n_items_est <- min(job$n_items, 1000)
    chunked <- needs_chunked_run(
      n_items = n_items_est, start = start_size, stop = stop_size,
      increase = 5, nsim = 500
    )
    run_mode <- if (chunked) "chunked" else "normal"

    log_line(
      "refine ", job$name,
      " using start=", start_size, " stop=", stop_size, " nsim=500 (subprocess, ", run_mode, ")",
      log_file = log_file
    )

    status <- tryCatch(
      system2(
        rscript_bin,
        args = c(
          shQuote(single_job_script),
          shQuote(variable),
          shQuote(job$name),
          shQuote(out_dir),
          as.character(start_size),
          as.character(stop_size),
          "500",
          shQuote(log_file),
          run_mode
        )
      ),
      error = function(e) {
        log_line("error ", job$name, ": ", conditionMessage(e), log_file = log_file)
        NA_integer_
      }
    )

    if (!identical(status, 0L) && !is.na(status)) {
      log_line("subprocess for ", job$name, " exited with status ", status, log_file = log_file)
    }

    results[[i]] <- list(
      status = if (identical(status, 0L)) "done" else "error",
      file = file.path(out_dir, job$output)
    )
  }

  utils::write.csv(
    manifest,
    file = file.path(out_dir, "refine_grid_manifest.csv"),
    row.names = FALSE
  )
  saveRDS(manifest, file = file.path(out_dir, "refine_grid_manifest.rds"))

  invisible(results)
}

main <- function() {
  attach_required_packages()
  load_shared_functions("scripts/functions.R")

  variables_to_run <- Sys.getenv("POWER_VARIABLES", "")
  variables_to_run <- if (nzchar(variables_to_run)) {
    trimws(strsplit(variables_to_run, ",")[[1]])
  } else {
    VARIABLES
  }

  results <- lapply(variables_to_run, run_refine_for_variable)
  names(results) <- variables_to_run
  invisible(results)
}

if (sys.nframe() == 0L) main()
