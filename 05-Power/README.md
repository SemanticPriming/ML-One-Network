# Power

Sample-size (AIPE-based) power simulations for the semanticprimeR norming variables, run over the finalized SPAML `todo_semanticprimeR` completed datasets. This mirrors the pilot/refine approach used in `Maria-Familiarity` (`run_estimate_r_ss_pilot.R` / `run_estimate_r_ss_refine.R`), adapted to read jobs from `power_job_list.csv`. Only overall (whole-dataset) precision and split-half reliability are used — POS/word-length/stroke-count subgroup analyses are not run here.

## Layout

-   `scripts/` — all pipeline code (see below). Run these from inside `05-Power/`, e.g. `Rscript scripts/run_power_pilot.R`.
-   `simulations/<variable>/pilot/` and `simulations/<variable>/refined/` — one `.rds` per dataset plus a `*_grid_manifest.csv`/`.rds` summarizing the recommended sample-size window per dataset, for each of `familiar`, `concrete`, `valence`, `arousal`, `imagine`, `aoa`.
-   `power_job_list.csv` — one row per dataset/variable combination, with the source CSV, column names, item count, min/max score range, and `n_per_item`. Only rows with a numeric `n_per_item` are runnable; rows with a placeholder (e.g. `*`) are skipped until filled in.
-   `datasets_with_power_variables.csv` — reference list of which datasets contain which power-eligible variables.
-   `power_analysis.Rmd` / `power_analysis.html` — the main report: recommended sample sizes by target power/reliability, pooled across all refined runs.

## `scripts/`

-   `functions.R` — the AIPE simulation functions used by the pipeline.
-   `run_power_batch.R` — shared setup and helpers (`build_jobs`, `run_job`, `run_jobs_stage`, manifest builders). Not run directly; sourced by the other scripts.
-   `run_power_pilot.R` — stage 1, broad sweep.
-   `run_power_refine.R` — stage 2, narrow/precise rerun. Spawns `run_single_refine_job.R` as a fresh subprocess per dataset (see below).
-   `run_single_refine_job.R` — runs exactly one refine-stage dataset job, then exits. Not run directly; spawned by `run_power_refine.R`.
-   `rebuild_refine_manifests.R` — rebuilds a variable's full `refine_grid_manifest.csv`/`.rds` from existing pilot/refined `.rds` output (no simulation). Needed after a sharded refine run, since each shard only writes its own partial manifest.

## Finding the reliability "spot"

Precision and split-half reliability don't reach their target at the same sample size — reliability generally gets there much earlier. The pilot sweep runs from **n=5** (not just n=20) up to 500 so it can locate exactly where each dataset's own reliability curve crosses the 80% target, instead of assuming that crossing never happens below some arbitrary floor. `recommend_reliability_start()` in `run_power_batch.R` reads the pilot's reliability curve and reports that true crossing point uncapped (it's a diagnostic value, `reliability_hit_sample_size` in the manifest) — mainly as a sanity check that reliability comfortably clears its target well before n=20.

The recommended/refined sample size itself never drops below **n=20** regardless of where that crossing falls — 20 is a practical floor for the study design, not just a search-grid artifact, so `build_followup_manifest()` clamps the refine-stage window's `start_sample_size` to `max(20, ...)` even if reliability crosses much earlier. In short: search down to n=5 to confirm the floor is safe, but never recommend or refine below n=20.

(An earlier version of this pipeline started the sweep at n=20 and only checked reliability's true crossing point indirectly, by correlating recommended-N against each dataset's original source-study sample size — that exploratory detour has been removed now that the sweep itself starts low enough to check directly.)

## Running the pipeline

Run from inside `05-Power/`:

```bash
cd 05-Power

# Stage 1: pilot — coarse sweep (n = 5-500, step 10, 10 sims/step)
# per dataset/variable, used to pick a narrower sample-size window
# and to locate where reliability crosses its target.
Rscript scripts/run_power_pilot.R

# Stage 2: refine — reruns each dataset in its narrowed window
# (which covers the reliability floor found in stage 1) with more
# precision (step 5, 100 sims/step). Requires the pilot stage to
# have completed first (reads its manifest).
Rscript scripts/run_power_refine.R
```

Both stages skip datasets that already have output, so they're safe to resume/re-run. To rerun the main report after new simulation output (e.g. extended/updated reliability numbers):

```bash
Rscript -e 'rmarkdown::render("power_analysis.Rmd")'
```

### Options

-   **Run only specific variables**: `POWER_VARIABLES=familiar,concrete Rscript scripts/run_power_pilot.R`
-   **Shard across parallel processes**: set `SHARD_TOTAL`/`SHARD_INDEX`, e.g. `SHARD_TOTAL=4 SHARD_INDEX=1 Rscript scripts/run_power_pilot.R`. After a sharded refine run, rebuild the combined per-variable manifests with `Rscript scripts/rebuild_refine_manifests.R` (each shard only writes its own partial manifest).
-   **Unattended overnight runs**: the refine stage can take hours; running it via `caffeinate -dimsu -w $$ &` keeps the machine from sleeping mid-run. Prefer 1-2 shards — more concurrent R sessions on large datasets has triggered memory-pressure kernel panics before.

### Requirements

-   R packages: `rio`, `dplyr`, `semanticprimeR`, `purrr`, `tidyr`, `truncnorm`, `psych`, `tibble`, plus `rmarkdown`, `ggplot2`, `DT` for the report.
-   `scripts/run_power_batch.R` points `DATA_DIR` at the local `SPAML/todo_semanticprimeR/datasets/completed` checkout — update that path if your `SPAML` clone lives elsewhere.

### Known issue

`run_job()` in `scripts/run_power_batch.R` subsamples any dataset over 1000 rows down to 1000 rows before simulating (logged as "test run"). Confirm whether this is intended before treating refined-stage output as final for larger datasets.
