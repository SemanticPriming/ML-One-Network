# Are the AIPE-recommended sample sizes (precision, reliability) a function
# of the original source study's n_per_item, rather than a property of the
# item content itself? Run from inside 05-Power/.
#
# Outputs:
#   - orig_n_dependency_data.csv   per dataset-run precision/reliability n's
#                                   merged with the original n_per_item/n_items
#   - orig_n_dependency.html       standalone report with per-variable scatter
#                                   plots (generated from orig_n_dependency_template.html)

source("run_power_batch.R")
attach_required_packages()
load_shared_functions("functions.R")

job_list <- read.csv("power_job_list.csv", stringsAsFactors = FALSE, na.strings = c("", "NA"))
job_list$run_id <- tools::file_path_sans_ext(job_list$dataset)
job_list$n_per_item <- suppressWarnings(as.numeric(job_list$n_per_item))
job_list <- job_list[!is.na(job_list$n_per_item), ]

n_at_precision_per_run <- function(overall_power, target_power = 80) {
  overall_power %>%
    dplyr::group_by(run_id) %>%
    dplyr::mutate(target_power = REFINE_POWER_LEVELS[((dplyr::row_number() - 1) %% length(REFINE_POWER_LEVELS)) + 1]) %>%
    dplyr::ungroup() %>%
    dplyr::filter(target_power == !!target_power) %>%
    dplyr::transmute(run_id, n_precision = corrected_sample_size)
}

n_at_reliability_per_run <- function(overall_rel, target_reliability = 0.80) {
  overall_rel %>%
    dplyr::mutate(reliability_m = as.numeric(reliability_m), sample_size = as.numeric(sample_size)) %>%
    dplyr::filter(is.finite(reliability_m)) %>%
    dplyr::group_by(run_id) %>%
    dplyr::filter(reliability_m >= target_reliability) %>%
    dplyr::arrange(sample_size) %>%
    dplyr::slice_head(n = 1) %>%
    dplyr::ungroup() %>%
    dplyr::transmute(run_id, n_reliability = sample_size)
}

max_reliability_per_run <- function(overall_rel) {
  overall_rel %>%
    dplyr::mutate(reliability_m = as.numeric(reliability_m), sample_size = as.numeric(sample_size)) %>%
    dplyr::filter(is.finite(reliability_m)) %>%
    dplyr::group_by(run_id) %>%
    dplyr::slice_max(sample_size, n = 1, with_ties = FALSE) %>%
    dplyr::ungroup() %>%
    dplyr::transmute(run_id, max_sample_size = sample_size, max_reliability = reliability_m)
}

REFINE_POWER_LEVELS <- c(70, 75, 80, 85, 90, 95)

variable_dirs <- file.path("simulations", VARIABLES, "refined")
names(variable_dirs) <- VARIABLES
available_vars <- VARIABLES[dir.exists(variable_dirs) &
  lengths(purrr::map(variable_dirs, list.files, pattern = "\\.rds$")) > 0]

results_by_variable <- purrr::map(
  setNames(available_vars, available_vars),
  ~ load_and_summarize_simulations(file.path("simulations", .x, "refined"))
)

all_runs <- purrr::imap_dfr(results_by_variable, function(res, v) {
  n_at_precision_per_run(res$overall_power, 80) %>%
    dplyr::full_join(n_at_reliability_per_run(res$overall_rel, 0.80), by = "run_id") %>%
    dplyr::full_join(max_reliability_per_run(res$overall_rel), by = "run_id") %>%
    dplyr::mutate(variable = v)
})

merged <- all_runs %>%
  dplyr::inner_join(
    job_list %>% dplyr::select(run_id, variable, n_items, n_per_item),
    by = c("run_id", "variable")
  )

readr::write_csv(merged, "orig_n_dependency_data.csv")
cat("Wrote orig_n_dependency_data.csv (", nrow(merged), "rows )\n\n")

report_correlations <- function(merged, predictor) {
  for (metric in c("n_precision", "n_reliability", "max_reliability")) {
    d <- merged[is.finite(merged[[metric]]) & is.finite(merged[[predictor]]), ]
    ct_p <- suppressWarnings(stats::cor.test(d[[predictor]], d[[metric]], method = "pearson"))
    ct_s <- suppressWarnings(stats::cor.test(d[[predictor]], d[[metric]], method = "spearman"))
    cat(sprintf(
      "%s ~ %s : n=%d, pearson r=%.3f (p=%.4f), spearman rho=%.3f (p=%.4f)\n",
      metric, predictor, nrow(d), ct_p$estimate, ct_p$p.value, ct_s$estimate, ct_s$p.value
    ))
  }
}

cat("=== Correlations with ORIGINAL n_per_item (raters/item in source study) ===\n")
report_correlations(merged, "n_per_item")

cat("\n=== Correlations with n_items (number of words/items) ===\n")
report_correlations(merged, "n_items")

cat("\n=== Per-variable correlations vs n_per_item ===\n")
per_var <- merged %>%
  dplyr::group_by(variable) %>%
  dplyr::summarise(
    n_precision_n = sum(is.finite(n_precision) & is.finite(n_per_item)),
    precision_rho = suppressWarnings(stats::cor(n_per_item, n_precision, method = "spearman", use = "complete.obs")),
    n_reliability_n = sum(is.finite(n_reliability) & is.finite(n_per_item)),
    reliability_rho = suppressWarnings(stats::cor(n_per_item, n_reliability, method = "spearman", use = "complete.obs")),
    .groups = "drop"
  )
print(per_var)

# --- Build standalone HTML report from the template ---
template_path <- "orig_n_dependency_template.html"
if (file.exists(template_path)) {
  data_json <- jsonlite::toJSON(merged, na = "null", digits = 4, auto_unbox = FALSE)
  template <- paste(readLines(template_path, warn = FALSE), collapse = "\n")
  html <- sub("__DATA_JSON__", data_json, template, fixed = TRUE)
  writeLines(html, "orig_n_dependency.html")
  cat("\nWrote orig_n_dependency.html\n")
} else {
  cat("\nSkipped HTML report: orig_n_dependency_template.html not found\n")
}
