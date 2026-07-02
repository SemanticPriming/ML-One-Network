# Power

Sample-size (AIPE-based) power simulations for the semanticprimeR norming variables, run over the finalized SPAML `todo_semanticprimeR` completed datasets. This mirrors the pilot/refine approach used in `Maria-Familiarity` (`run_estimate_r_ss_pilot.R` / `run_estimate_r_ss_refine.R`), adapted to read jobs from `power_job_list.csv`. Only overall (whole-dataset) precision and split-half reliability are used — POS/word-length/stroke-count subgroup analyses are not run here.

## Files

-   `power_job_list.csv` — one row per dataset/variable combination (`familiar`, `concrete`, `valence`, `arousal`, `imagine`), with the source CSV, column names, item count, min/max score range, and `n_per_item`. Only rows with a numeric `n_per_item` are runnable; rows with a placeholder (e.g. `*`) are skipped until filled in.
-   `datasets_with_power_variables.csv` — reference list of which datasets contain which power-eligible variables.
-   `functions.R` — the AIPE simulation functions used by the pipeline.
-   `run_power_batch.R` — shared setup and helpers (`build_jobs`, `run_job`, `run_jobs_stage`, manifest builders). Not run directly; sourced by the pilot and refine scripts.
-   `run_power_pilot.R` — stage 1, broad sweep.
-   `run_power_refine.R` — stage 2, narrow/precise rerun.

## Running the pipeline

Run from inside `05-Power/`:

```bash
cd 05-Power

# Stage 1: pilot — coarse sweep (n = 20-500, step 10, 10 sims/step)
# per dataset/variable, used to pick a narrower sample-size window.
Rscript run_power_pilot.R

# Stage 2: refine — reruns each dataset in its narrowed window
# with more precision (step 5, 100 sims/step). Requires the pilot
# stage to have completed first (reads its manifest).
Rscript run_power_refine.R
```

Output for each stage goes to `simulations/<variable>/pilot/` and `simulations/<variable>/refined/`, one `.rds` per dataset plus a `*_grid_manifest.csv`/`.rds` summarizing the recommended sample-size window per dataset. Both stages skip datasets that already have output, so they're safe to resume/re-run.

### Options

-   **Run only specific variables**: `POWER_VARIABLES=familiar,concrete Rscript run_power_pilot.R`
-   **Shard across parallel processes**: set `SHARD_TOTAL`/`SHARD_INDEX`, e.g. `SHARD_TOTAL=4 SHARD_INDEX=1 Rscript run_power_pilot.R`

### Requirements

-   R packages: `rio`, `dplyr`, `semanticprimeR`, `purrr`, `tidyr`, `truncnorm`, `psych`, `tibble`.
-   `run_power_batch.R` points `DATA_DIR` at the local `SPAML/todo_semanticprimeR/datasets/completed` checkout — update that path if your `SPAML` clone lives elsewhere.

### Known issue

`run_job()` in `run_power_batch.R` subsamples any dataset over 100 rows down to 100 rows before simulating (logged as "test run"). Confirm whether this is intended before treating refined-stage output as final for larger datasets.
