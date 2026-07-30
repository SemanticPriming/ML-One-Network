#!/usr/bin/env Rscript

# Runs exactly one refine-stage dataset job, then exits. run_power_refine.R
# spawns one of these as a fresh subprocess per dataset instead of looping
# many jobs inside a single long-lived R session - rm()/gc() only reclaims
# memory for R's own heap to reuse, it doesn't hand pages back to the OS, so
# a session working through dozens of sequential jobs can accumulate enough
# resident memory to trigger real trouble (a JetsamEvent + kernel panic was
# observed with the old in-process loop). A fresh process per job guarantees
# the OS reclaims everything when that job's process exits.
#
# Usage:
#   Rscript run_single_refine_job.R <variable> <job_name> <out_dir> <start> <stop> <nsim> <log_file> [mode]
#
# <mode> is "normal" (default, if omitted) or "chunked". "chunked" routes
# to run_job_chunked(), which simulates/summarizes one sample size at a
# time instead of holding the whole window in memory at once - for jobs
# whose window is large enough that the normal path risks exhausting
# memory. See needs_chunked_run() in run_power_batch.R.

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
attach_required_packages()
load_shared_functions("scripts/functions.R")

args <- commandArgs(trailingOnly = TRUE)
if (!length(args) %in% c(7, 8)) {
  stop("Usage: Rscript run_single_refine_job.R <variable> <job_name> <out_dir> <start> <stop> <nsim> <log_file> [mode]")
}

variable   <- args[[1]]
job_name   <- args[[2]]
out_dir    <- args[[3]]
start_size <- as.numeric(args[[4]])
stop_size  <- as.numeric(args[[5]])
nsim       <- as.numeric(args[[6]])
log_file   <- args[[7]]
mode       <- if (length(args) >= 8) args[[8]] else "normal"

if (!mode %in% c("normal", "chunked")) {
  stop("mode must be 'normal' or 'chunked', got: ", mode)
}

jobs <- build_jobs(variable)
job <- jobs[jobs$name == job_name, , drop = FALSE]

if (nrow(job) == 0) {
  stop("job '", job_name, "' not found for variable '", variable, "'")
}

run_fn <- if (mode == "chunked") run_job_chunked else run_job

run_fn(
  job = job,
  skip_existing = TRUE,
  out_dir = out_dir,
  start = start_size,
  stop = stop_size,
  increase = 5,
  nsim = nsim,
  power_levels = c(70, 75, 80, 85, 90, 95),
  log_file = log_file
)
