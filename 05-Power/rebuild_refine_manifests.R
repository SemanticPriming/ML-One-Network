#!/usr/bin/env Rscript

# Each sharded run_power_refine.R process only sees its own 1/4 slice of
# jobs and writes refine_grid_manifest.csv/.rds from that slice alone, so
# whichever shard finishes a variable last leaves an incomplete manifest
# behind. This rebuilds the full per-variable manifest from every job (not
# sharded) against the now-complete refined/*.rds output - cheap, since it
# only reads existing pilot/refined .rds files, no simulation.

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
attach_required_packages()

for (variable in VARIABLES) {
  jobs <- build_jobs(variable)
  jobs <- jobs[jobs$status != "done", , drop = FALSE]
  if (nrow(jobs) == 0) next

  pilot_dir <- file.path("simulations", variable, "pilot")
  out_dir <- file.path("simulations", variable, "refined")
  if (!dir.exists(pilot_dir) || !dir.exists(out_dir)) next

  manifest <- build_followup_manifest(
    jobs = jobs,
    out_dir = pilot_dir,
    lower_target = 70,
    upper_target = 95,
    min_start = 20,
    max_stop = 500,
    step = 5
  )

  utils::write.csv(manifest, file = file.path(out_dir, "refine_grid_manifest.csv"), row.names = FALSE)
  saveRDS(manifest, file = file.path(out_dir, "refine_grid_manifest.rds"))
  cat(sprintf("rebuilt manifest for %s (%d jobs)\n", variable, nrow(jobs)))
}
