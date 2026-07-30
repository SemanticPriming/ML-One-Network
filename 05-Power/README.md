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

Precision and split-half reliability don't reach their target at the same sample size — reliability generally gets there much earlier. **n=20 is a fixed floor**: the recommended/refined sample size never drops below it, no matter how early reliability crosses 80%, because 20 is a practical floor for the study design, not a search-grid artifact.

The pilot sweep runs from **n=5** (not just n=20) up to 500 purely to confirm that floor is safe — `recommend_reliability_start()` in `run_power_batch.R` reads the pilot's reliability curve and reports the true, uncapped crossing point as a diagnostic (`reliability_hit_sample_size` in the manifest), so we can see reliability clears 80% well before n=20 rather than assuming it. It's a sanity check, not a recommendation: `build_followup_manifest()` still clamps `start_sample_size` to `max(20, ...)` before it goes anywhere.

That 5-500 sweep only happens once, at pilot resolution (step 10, 10 sims/step) — it isn't repeated at refine resolution. `run_simulation_pipeline()` computes precision and reliability from the same simulated samples, so the refine stage's reliability curve only covers the `[start_sample_size, stop_sample_size]` window derived from the pilot's *precision* curve (floored at 20). `reliability_hit_sample_size` is carried into the manifest as a diagnostic; it never widens the refine window.

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
