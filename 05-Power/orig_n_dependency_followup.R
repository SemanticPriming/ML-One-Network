# Two ways to get a recommended n that isn't just tracking the original
# source study's n_per_item (see orig_n_dependency.R / README for the
# background). Reads orig_n_dependency_data.csv, so rerun that script first
# if the underlying simulations have changed. Run from inside 05-Power/.
#
# Approach 1 - "restrict to comparable originals": only pool dataset runs
#   whose original n_per_item is close to what we can realistically afford
#   (near 30), since those runs' item-SD estimates are about as noisy as
#   what our own study would produce - not noisier, not artificially cleaner.
#
# Approach 2 - "extrapolate the noise away": regress recommended n on
#   1/sqrt(n_per_item) (the rate at which sampling noise in a sample SD
#   shrinks) and read off the intercept, i.e. the recommended n implied by
#   an infinitely-precise original SD estimate. This uses every run instead
#   of discarding most of them, but leans on 1/sqrt(n) being a reasonable
#   model of the noise.

source("run_power_batch.R")
attach_required_packages()

merged <- readr::read_csv("orig_n_dependency_data.csv", show_col_types = FALSE)

variable_labels <- c(
  familiar = "Familiarity", concrete = "Concreteness", valence = "Valence",
  arousal = "Arousal", imagine = "Imageability", aoa = "Age of Acquisition (AoA)"
)

## ---- Approach 1: restrict to runs with n_per_item close to 30 ----

NEAR_30_BAND <- c(25, 35) # inclusive band around the n=30 floor

near_30 <- merged %>% dplyr::filter(n_per_item >= NEAR_30_BAND[1], n_per_item <= NEAR_30_BAND[2])

cat(sprintf(
  "=== Approach 1: dataset runs with n_per_item in [%d, %d] ===\n",
  NEAR_30_BAND[1], NEAR_30_BAND[2]
))
cat(sprintf("Kept %d / %d runs overall.\n\n", nrow(near_30), nrow(merged)))

near_30_summary <- near_30 %>%
  dplyr::group_by(variable) %>%
  dplyr::summarise(
    n_runs = dplyr::n(),
    median_n_precision = stats::median(n_precision, na.rm = TRUE),
    median_n_reliability = stats::median(n_reliability, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  dplyr::mutate(variable = variable_labels[variable]) %>%
  dplyr::arrange(dplyr::desc(median_n_reliability))
print(near_30_summary)

all_runs_summary <- merged %>%
  dplyr::group_by(variable) %>%
  dplyr::summarise(
    n_runs = dplyr::n(),
    median_n_precision = stats::median(n_precision, na.rm = TRUE),
    median_n_reliability = stats::median(n_reliability, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  dplyr::mutate(variable = variable_labels[variable]) %>%
  dplyr::arrange(dplyr::desc(median_n_reliability))

cat("\nFor comparison, the same medians using every run (no filtering):\n")
print(all_runs_summary)

## ---- Approach 2: extrapolate to n_per_item -> infinity via 1/sqrt(n) ----

cat("\n\n=== Approach 2: recommended n extrapolated to an infinitely-precise original SD ===\n")
cat("Fits recommended_n ~ 1/sqrt(n_per_item); the intercept is the recommended n\n")
cat("implied once original-sample noise is regressed out.\n\n")

extrapolate_metric <- function(d, metric) {
  d <- d[is.finite(d[[metric]]) & is.finite(d$n_per_item), ]
  if (nrow(d) < 4) {
    return(tibble::tibble(n_runs = nrow(d), intercept = NA_real_, slope = NA_real_, r_squared = NA_real_))
  }
  fit <- stats::lm(d[[metric]] ~ I(1 / sqrt(n_per_item)), data = d)
  tibble::tibble(
    n_runs = nrow(d),
    intercept = stats::coef(fit)[["(Intercept)"]],
    slope = stats::coef(fit)[["I(1/sqrt(n_per_item))"]],
    r_squared = summary(fit)$r.squared
  )
}

extrap_by_variable <- purrr::map_dfr(unique(merged$variable), function(v) {
  d <- merged %>% dplyr::filter(variable == v)
  dplyr::bind_rows(
    extrapolate_metric(d, "n_precision") %>% dplyr::mutate(metric = "n_precision"),
    extrapolate_metric(d, "n_reliability") %>% dplyr::mutate(metric = "n_reliability")
  ) %>% dplyr::mutate(variable = variable_labels[[v]])
}) %>%
  dplyr::select(variable, metric, n_runs, intercept, slope, r_squared) %>%
  dplyr::arrange(variable, metric)

print(extrap_by_variable %>% dplyr::mutate(dplyr::across(c(intercept, slope, r_squared), ~ round(.x, 2))))

cat("\nPooled across all variables:\n")
pooled_extrap <- dplyr::bind_rows(
  extrapolate_metric(merged, "n_precision") %>% dplyr::mutate(metric = "n_precision"),
  extrapolate_metric(merged, "n_reliability") %>% dplyr::mutate(metric = "n_reliability")
)
print(pooled_extrap %>% dplyr::mutate(dplyr::across(c(intercept, slope, r_squared), ~ round(.x, 2))))

readr::write_csv(near_30_summary, "orig_n_dependency_near30.csv")
readr::write_csv(extrap_by_variable, "orig_n_dependency_extrapolated.csv")
cat("\nWrote orig_n_dependency_near30.csv and orig_n_dependency_extrapolated.csv\n")
