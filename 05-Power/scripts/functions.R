run_population_pipeline <- function(
  population,
  min_score = 0,
  max_score = 9,
  n_per_item = 68,
  start = 20,
  stop = 100,
  increase = 5,
  nsim = 500,
  power_levels = c(80, 85, 90, 95)
) {
  population <- population %>%
    filter(is.finite(.data[["score"]]))

  cutoff <- calculate_cutoff(
    population = population,
    grouping_items = "item",
    score = "score",
    minimum = min_score,
    maximum = max_score
  )

  cat(sprintf("    [%s] simulate_samples (n_items=%d start=%d stop=%d nsim=%d)\n",
              format(Sys.time(), "%H:%M:%S"),
              n_distinct(population$item), start, stop, nsim))

  samples <- simulate_samples(
    start = start,
    stop = stop,
    increase = increase,
    population = population,
    replace = TRUE,
    nsim = nsim,
    grouping_items = "item"
  )

  samples <- purrr::map(samples, function(sample_dat) {
    sample_dat %>%
      filter(is.finite(.data[["score"]]))
  })

  cat(sprintf("    [%s] calculate_proportion (n_samples=%d)\n",
              format(Sys.time(), "%H:%M:%S"), length(samples)))

  proportion_summary <- calculate_proportion(
    samples = samples,
    cutoff = cutoff$cutoff,
    grouping_items = "item",
    score = "score"
  )

  cat(sprintf("  cutoff: %.3f  prop_var: %.4f  n_items: %d\n",
              cutoff$cutoff, cutoff$prop_var, n_distinct(population$item)))
  cat(sprintf("  proportion_summary rows: %d  prop range: [%.3f, %.3f]\n",
              nrow(proportion_summary),
              if (nrow(proportion_summary) > 0) min(proportion_summary$percent_below, na.rm = TRUE) else NA,
              if (nrow(proportion_summary) > 0) max(proportion_summary$percent_below, na.rm = TRUE) else NA))

  cat(sprintf("    [%s] calculate_correction\n",
              format(Sys.time(), "%H:%M:%S")))

  corrected_summary <- calculate_correction(
    proportion_summary = proportion_summary,
    pilot_sample_size = n_per_item,
    proportion_variability = cutoff$prop_var,
    power_levels = power_levels
  )

  cat(sprintf("  corrected_summary rows: %d\n", nrow(corrected_summary)))

  list(
    cutoff = cutoff,
    samples = samples,
    proportion_summary = proportion_summary,
    corrected_summary = corrected_summary
  )
}

summarise_split_half <- function(dat) {
  if (is.null(dat) || nrow(dat) == 0) {
    return(NULL)
  }

  if ("group" %in% names(dat)) {
    dat %>%
      group_by(sample_size, group) %>%
      summarise(reliability_m = mean(reliability, na.rm = TRUE), .groups = "drop")
  } else {
    dat %>%
      group_by(sample_size) %>%
      summarise(reliability_m = mean(reliability, na.rm = TRUE), .groups = "drop")
  }
}

build_save_data <- function(saved_sim) {
  list(
    overall_power = saved_sim$corrected_summary,
    overall_curve = saved_sim$proportion_summary,
    overall_rel = summarise_split_half(saved_sim$split_half_rel)
  )
}

load_and_summarize_simulations <- function(sim_dir = "simulations") {
  if (!dir.exists(sim_dir)) {
    stop(sprintf("Simulation directory not found: %s", sim_dir))
  }

  sim_files <- list.files(sim_dir, pattern = "\\.rds$", full.names = TRUE)
  sim_files <- sim_files[!grepl("manifest", basename(sim_files), ignore.case = TRUE)]
  if (length(sim_files) == 0) {
    stop(sprintf("No .rds files found in %s", sim_dir))
  }

  run_ids <- tools::file_path_sans_ext(basename(sim_files))
  runs <- purrr::map(sim_files, readRDS)

  extract_overall_power <- function(run_obj) {
    if (is.list(run_obj) && !is.null(run_obj$overall_power)) {
      return(run_obj$overall_power)
    }
    if (is.list(run_obj) && !is.null(run_obj$corrected_summary)) {
      return(run_obj$corrected_summary)
    }
    NULL
  }

  extract_overall_rel <- function(run_obj) {
    if (is.list(run_obj) && !is.null(run_obj$overall_rel)) {
      return(run_obj$overall_rel)
    }
    if (is.list(run_obj) && !is.null(run_obj$split_half_rel)) {
      return(run_obj$split_half_rel)
    }
    NULL
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

  extract_subgroup_power <- function(run_obj, field_name) {
    if (!is.list(run_obj) || is.null(run_obj[[field_name]])) {
      return(tibble::tibble())
    }

    purrr::imap_dfr(run_obj[[field_name]], function(tbl, group_name) {
      if (is.null(tbl) || nrow(tbl) == 0) {
        return(tibble::tibble())
      }

      tbl %>%
        mutate(group = as.character(group_name))
    })
  }

  extract_subgroup_curve <- function(run_obj, field_name) {
    if (!is.list(run_obj) || is.null(run_obj[[field_name]])) {
      return(tibble::tibble())
    }

    purrr::imap_dfr(run_obj[[field_name]], function(tbl, group_name) {
      if (is.null(tbl) || nrow(tbl) == 0) {
        return(tibble::tibble())
      }

      tbl %>%
        mutate(group = as.character(group_name))
    })
  }

  extract_subgroup_rel <- function(run_obj, field_name) {
    if (!is.list(run_obj) || is.null(run_obj[[field_name]])) {
      return(tibble::tibble())
    }

    run_obj[[field_name]]
  }

  ordered_group_levels <- function(x) {
    x <- unique(as.character(x))
    if (all(x %in% c("noun", "modifiers", "verb", "other"))) {
      return(c("noun", "modifiers", "verb", "other")[c("noun", "modifiers", "verb", "other") %in% x])
    }

    x_num <- suppressWarnings(as.numeric(gsub("\\+$", "", x)))
    if (all(!is.na(x_num))) {
      return(x[order(x_num, x)])
    }

    x[order(x)]
  }

  summarize_subgroup_targets <- function(power_tbl, rel_tbl, target_power = 80, target_rel = 0.80) {
    power_summary <- tibble::tibble()
    rel_summary <- tibble::tibble()

    if (!is.null(power_tbl) && nrow(power_tbl) > 0) {
      power_summary <- power_tbl %>%
        mutate(
          percent_below = as.numeric(percent_below),
          corrected_sample_size = as.numeric(corrected_sample_size)
        ) %>%
        filter(percent_below == target_power) %>%
        group_by(group) %>%
        summarise(
          n_runs = sum(!is.na(corrected_sample_size)),
          mean_recommended_sample_size = mean(corrected_sample_size, na.rm = TRUE),
          median_recommended_sample_size = median(corrected_sample_size, na.rm = TRUE),
          recommended_sample_size = ceiling(median_recommended_sample_size),
          sd_recommended_sample_size = sd(corrected_sample_size, na.rm = TRUE),
          .groups = "drop"
        ) %>%
        mutate(target = paste0(target_power, "% power"))
    }

    if (!is.null(rel_tbl) && nrow(rel_tbl) > 0) {
      rel_summary <- rel_tbl %>%
        mutate(
          sample_size = as.numeric(sample_size),
          reliability_m = as.numeric(reliability_m)
        ) %>%
        group_by(group, sample_size) %>%
        summarise(
          median_reliability = median(reliability_m, na.rm = TRUE),
          .groups = "drop"
        ) %>%
        group_by(group) %>%
        filter(median_reliability >= target_rel) %>%
        arrange(sample_size) %>%
        slice_head(n = 1) %>%
        ungroup() %>%
        mutate(
          target = paste0(target_rel * 100, "% reliability"),
          recommended_sample_size = sample_size
        ) %>%
        select(group, target, recommended_sample_size, median_reliability)
    }

    summary_parts <- list()
    if (nrow(power_summary) > 0) {
      summary_parts[[length(summary_parts) + 1]] <- power_summary %>%
        select(group, target, recommended_sample_size)
    }
    if (nrow(rel_summary) > 0) {
      summary_parts[[length(summary_parts) + 1]] <- rel_summary %>%
        select(group, target, recommended_sample_size)
    }

    summary_tbl <- if (length(summary_parts) > 0) {
      bind_rows(summary_parts) %>%
        mutate(group = as.character(group))
    } else {
      tibble::tibble(group = character(), target = character(), recommended_sample_size = numeric())
    }

    plot_tbl <- summary_tbl %>%
      mutate(group = factor(group, levels = ordered_group_levels(group)))

    plot_obj <- NULL
    if (nrow(plot_tbl) > 0) {
      plot_obj <- ggplot2::ggplot(plot_tbl, ggplot2::aes(x = group, y = recommended_sample_size, color = target)) +
        ggplot2::geom_point(position = ggplot2::position_dodge(width = 0.4), size = 2.4) +
        ggplot2::geom_line(ggplot2::aes(group = target), position = ggplot2::position_dodge(width = 0.4), linewidth = 0.8) +
        ggplot2::coord_flip() +
        ggplot2::labs(
          x = NULL,
          y = "Recommended sample size",
          color = NULL
        ) +
        ggplot2::theme_minimal()
    }

    list(
      power_summary = power_summary,
      reliability_summary = rel_summary,
      summary = summary_tbl,
      plot = plot_obj
    )
  }

  overall_power <- purrr::imap_dfr(runs, function(run_obj, i) {
    power_tbl <- extract_overall_power(run_obj)
    if (is.null(power_tbl) || nrow(power_tbl) == 0) {
      return(tibble::tibble())
    }

    power_tbl %>%
      mutate(
        run_id = run_ids[[i]],
        source_file = sim_files[[i]]
      )
  })

  overall_rel <- purrr::imap_dfr(runs, function(run_obj, i) {
    rel_tbl <- extract_overall_rel(run_obj)
    if (is.null(rel_tbl) || nrow(rel_tbl) == 0) {
      return(tibble::tibble())
    }

    rel_tbl %>%
      mutate(
        run_id = run_ids[[i]],
        source_file = sim_files[[i]]
      )
  })

  overall_curve <- purrr::imap_dfr(runs, function(run_obj, i) {
    curve_tbl <- extract_overall_curve(run_obj)
    if (is.null(curve_tbl) || nrow(curve_tbl) == 0) {
      return(tibble::tibble())
    }

    curve_tbl %>%
      mutate(
        run_id = run_ids[[i]],
        source_file = sim_files[[i]]
      )
  })

  pos_power <- purrr::imap_dfr(runs, function(run_obj, i) {
    power_tbl <- extract_subgroup_power(run_obj, "pos_power")
    if (nrow(power_tbl) == 0) return(tibble::tibble())
    power_tbl %>%
      mutate(run_id = run_ids[[i]], source_file = sim_files[[i]])
  })

  pos_curve <- purrr::imap_dfr(runs, function(run_obj, i) {
    curve_tbl <- extract_subgroup_curve(run_obj, "pos_curve")
    if (nrow(curve_tbl) == 0) return(tibble::tibble())
    curve_tbl %>%
      mutate(run_id = run_ids[[i]], source_file = sim_files[[i]])
  })

  pos_rel <- purrr::imap_dfr(runs, function(run_obj, i) {
    rel_tbl <- extract_subgroup_rel(run_obj, "pos_rel")
    if (nrow(rel_tbl) == 0) return(tibble::tibble())
    rel_tbl %>%
      mutate(run_id = run_ids[[i]], source_file = sim_files[[i]])
  })

  length_power <- purrr::imap_dfr(runs, function(run_obj, i) {
    power_tbl <- extract_subgroup_power(run_obj, "length_power")
    if (nrow(power_tbl) == 0) return(tibble::tibble())
    power_tbl %>%
      mutate(run_id = run_ids[[i]], source_file = sim_files[[i]])
  })

  length_curve <- purrr::imap_dfr(runs, function(run_obj, i) {
    curve_tbl <- extract_subgroup_curve(run_obj, "length_curve")
    if (nrow(curve_tbl) == 0) return(tibble::tibble())
    curve_tbl %>%
      mutate(run_id = run_ids[[i]], source_file = sim_files[[i]])
  })

  length_rel <- purrr::imap_dfr(runs, function(run_obj, i) {
    rel_tbl <- extract_subgroup_rel(run_obj, "length_rel")
    if (nrow(rel_tbl) == 0) return(tibble::tibble())
    rel_tbl %>%
      mutate(run_id = run_ids[[i]], source_file = sim_files[[i]])
  })

  stroke_power <- purrr::imap_dfr(runs, function(run_obj, i) {
    power_tbl <- extract_subgroup_power(run_obj, "stroke_power")
    if (nrow(power_tbl) == 0) return(tibble::tibble())
    power_tbl %>%
      mutate(run_id = run_ids[[i]], source_file = sim_files[[i]])
  })

  stroke_curve <- purrr::imap_dfr(runs, function(run_obj, i) {
    curve_tbl <- extract_subgroup_curve(run_obj, "stroke_curve")
    if (nrow(curve_tbl) == 0) return(tibble::tibble())
    curve_tbl %>%
      mutate(run_id = run_ids[[i]], source_file = sim_files[[i]])
  })

  stroke_rel <- purrr::imap_dfr(runs, function(run_obj, i) {
    rel_tbl <- extract_subgroup_rel(run_obj, "stroke_rel")
    if (nrow(rel_tbl) == 0) return(tibble::tibble())
    rel_tbl %>%
      mutate(run_id = run_ids[[i]], source_file = sim_files[[i]])
  })

  if (nrow(overall_power) == 0 && nrow(overall_rel) == 0 &&
      nrow(overall_curve) == 0 &&
      nrow(pos_power) == 0 && nrow(pos_rel) == 0 &&
      nrow(pos_curve) == 0 &&
      nrow(length_power) == 0 && nrow(length_rel) == 0 &&
      nrow(length_curve) == 0 &&
      nrow(stroke_power) == 0 && nrow(stroke_rel) == 0 &&
      nrow(stroke_curve) == 0) {
    return(list(
      files = sim_files,
      runs = runs,
      overall_power = overall_power,
      overall_rel = overall_rel,
      overall_curve = overall_curve,
      pos_power = pos_power,
      pos_curve = pos_curve,
      pos_rel = pos_rel,
      length_power = length_power,
      length_curve = length_curve,
      length_rel = length_rel,
      stroke_power = stroke_power,
      stroke_curve = stroke_curve,
      stroke_rel = stroke_rel,
      recommendation_summary = tibble::tibble(),
      recommendation_plot = NULL
    ))
  }

  if (nrow(overall_power) > 0) {
    recommendation_summary <- overall_power %>%
      mutate(
        percent_below = as.numeric(percent_below),
        corrected_sample_size = as.numeric(corrected_sample_size)
      ) %>%
      group_by(percent_below) %>%
      summarise(
        n_runs = sum(!is.na(corrected_sample_size)),
        mean_recommended_sample_size = mean(corrected_sample_size, na.rm = TRUE),
        median_recommended_sample_size = median(corrected_sample_size, na.rm = TRUE),
        recommended_sample_size = ceiling(median_recommended_sample_size),
        sd_recommended_sample_size = sd(corrected_sample_size, na.rm = TRUE),
        min_recommended_sample_size = min(corrected_sample_size, na.rm = TRUE),
        max_recommended_sample_size = max(corrected_sample_size, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      arrange(percent_below) %>%
      mutate(recommended_sample_size = cummax(recommended_sample_size))

    recommendation_plot <- ggplot2::ggplot(
      overall_power %>% mutate(percent_below = factor(percent_below, levels = as.character(recommendation_summary$percent_below))),
      ggplot2::aes(x = percent_below, y = corrected_sample_size)
    ) +
      ggplot2::geom_boxplot(fill = "#d9e7ff", outlier.alpha = 0.2, width = 0.6) +
      ggplot2::geom_jitter(width = 0.12, alpha = 0.35, size = 1.4) +
      ggplot2::geom_line(
        data = recommendation_summary,
        ggplot2::aes(x = factor(percent_below, levels = as.character(recommendation_summary$percent_below)),
                     y = recommended_sample_size,
                     group = 1),
        color = "#b00020",
        linewidth = 0.9
      ) +
      ggplot2::geom_point(
        data = recommendation_summary,
        ggplot2::aes(x = factor(percent_below, levels = as.character(recommendation_summary$percent_below)),
                     y = recommended_sample_size),
        color = "#b00020",
        size = 2.5
      ) +
      ggplot2::labs(
        x = "Target Power",
        y = "Corrected Sample Size",
        title = "Recommended sample size by target power"
      ) +
      ggplot2::theme_minimal()
  } else {
    recommendation_summary <- tibble::tibble()
    recommendation_plot <- NULL
  }

  if (nrow(overall_rel) > 0) {
    reliability_summary <- overall_rel %>%
      mutate(
        sample_size = as.numeric(sample_size),
        reliability_m = as.numeric(reliability_m)
      ) %>%
      group_by(sample_size) %>%
      summarise(
        n_runs = sum(!is.na(reliability_m)),
        mean_reliability = mean(reliability_m, na.rm = TRUE),
        median_reliability = median(reliability_m, na.rm = TRUE),
        sd_reliability = sd(reliability_m, na.rm = TRUE),
        min_reliability = min(reliability_m, na.rm = TRUE),
        max_reliability = max(reliability_m, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      arrange(sample_size)

    reliability_targets <- c(0.80, 0.85, 0.90, 0.95)
    reliability_recommendation <- purrr::map_dfr(reliability_targets, function(target) {
      hit <- reliability_summary %>%
        filter(median_reliability >= target) %>%
        arrange(sample_size) %>%
        slice_head(n = 1)

      if (nrow(hit) == 0) {
        return(tibble::tibble(
          target_reliability = target,
          recommended_sample_size = NA_real_,
          median_reliability = NA_real_
        ))
      }

      tibble::tibble(
        target_reliability = target,
        recommended_sample_size = hit$sample_size[[1]],
        median_reliability = hit$median_reliability[[1]]
      )
    }) %>%
      mutate(recommended_sample_size = as.numeric(recommended_sample_size))

    reliability_plot <- ggplot2::ggplot(
      reliability_summary,
      ggplot2::aes(x = sample_size, y = median_reliability)
    ) +
      ggplot2::geom_line(color = "#1f4e79", linewidth = 0.9) +
      ggplot2::geom_point(color = "#1f4e79", size = 2) +
      ggplot2::geom_hline(
        data = reliability_recommendation,
        ggplot2::aes(yintercept = target_reliability),
        linetype = "dashed",
        color = "#b00020"
      ) +
      ggplot2::geom_vline(
        data = reliability_recommendation %>% filter(!is.na(recommended_sample_size)),
        ggplot2::aes(xintercept = recommended_sample_size),
        linetype = "dotted",
        color = "#b00020"
      ) +
      ggplot2::labs(
        x = "Sample Size",
        y = "Median Split-Half Reliability",
        title = "Sample size needed to reach target reliability"
      ) +
      ggplot2::theme_minimal()
  } else {
    reliability_summary <- tibble::tibble()
    reliability_recommendation <- tibble::tibble()
    reliability_plot <- NULL
  }

  pos_targets <- summarize_subgroup_targets(pos_power, pos_rel, target_power = 80, target_rel = 0.80)
  length_targets <- summarize_subgroup_targets(length_power, length_rel, target_power = 80, target_rel = 0.80)
  stroke_targets <- summarize_subgroup_targets(stroke_power, stroke_rel, target_power = 80, target_rel = 0.80)

  list(
    files = sim_files,
    runs = runs,
    overall_power = overall_power,
    overall_rel = overall_rel,
    overall_curve = overall_curve,
    pos_power = pos_power,
    pos_curve = pos_curve,
    pos_rel = pos_rel,
    length_power = length_power,
    length_curve = length_curve,
    length_rel = length_rel,
    stroke_power = stroke_power,
    stroke_curve = stroke_curve,
    stroke_rel = stroke_rel,
    recommendation_summary = recommendation_summary,
    recommendation_plot = recommendation_plot,
    reliability_summary = reliability_summary,
    reliability_recommendation = reliability_recommendation,
    reliability_plot = reliability_plot,
    pos_targets = pos_targets,
    length_targets = length_targets,
    stroke_targets = stroke_targets
  )
}

run_simulation_core <- function(
  df,
  item_col,
  mean_col,
  sd_col,
  n_per_item = 68,
  min_score = 0,
  max_score = 9,
  start = 20,
  stop = 100,
  increase = 5,
  nsim = 500,
  power_levels = c(80, 85, 90, 95)
) {
  cat(sprintf("Core run started: %s\n", item_col))
  cat(sprintf("  rows in input: %d\n", nrow(df)))

  items <- df %>%
    mutate(
      item = .data[[item_col]],
      mean = .data[[mean_col]],
      sd   = .data[[sd_col]],
      n    = n_per_item
    ) %>%
    select(item, mean, sd, n, everything()) %>%
    filter(!is.na(item) & !is.na(mean) & !is.na(sd))

  sim_data <- items %>%
    mutate(scores = pmap(list(mean, sd, n),
                         ~ rtruncnorm(..3,
                                      a = min_score,
                                      b = max_score,
                                      mean = ..1,
                                      sd = ..2))) %>%
    unnest(scores) %>%
    mutate(score = round(scores)) %>%
    filter(is.finite(.data[["score"]])) %>%
    select(item, score, any_of(c("pos", "length_bucket", "stroke_bucket")))

  cat(sprintf("  simulated data ready: %d rows\n", nrow(sim_data)))

  pipeline_results <- run_population_pipeline(
    population = sim_data,
    min_score = min_score,
    max_score = max_score,
    n_per_item = n_per_item,
    start = start,
    stop = stop,
    increase = increase,
    nsim = nsim,
    power_levels = power_levels
  )
  cutoff <- pipeline_results$cutoff
  samples <- pipeline_results$samples
  proportion_summary <- pipeline_results$proportion_summary
  corrected_summary <- pipeline_results$corrected_summary

  cat("Core run done\n")

  return(list(
    sim_data = sim_data,
    cutoff = cutoff,
    samples = samples,
    proportion_summary = proportion_summary,
    corrected_summary = corrected_summary
  ))
}

run_simulation_pipeline <- function(
  df,
  item_col,
  mean_col,
  sd_col,
  n_per_item = 68,
  min_score = 0,
  max_score = 9,
  start = 20,
  stop = 100,
  increase = 5,
  nsim = 500,
  power_levels = c(80, 85, 90, 95),
  out_file = NULL
) {
  # POS / word-length / stroke-count subgroup analyses have been removed
  # from this pipeline - only the overall (whole-dataset) precision and
  # split-half reliability results are computed.
  cat(sprintf("Pipeline started: %s\n", item_col))

  save_checkpoint <- function() {
    if (is.null(out_file)) return(invisible(NULL))
    partial <- list(
      corrected_summary  = core_results$corrected_summary,
      proportion_summary = core_results$proportion_summary,
      split_half_rel     = split_half_rel
    )
    saveRDS(build_save_data(partial), out_file)
    cat(sprintf("  [%s] checkpoint saved\n", format(Sys.time(), "%H:%M:%S")))
  }

  core_results <- run_simulation_core(
    df = df,
    item_col = item_col,
    mean_col = mean_col,
    sd_col = sd_col,
    n_per_item = n_per_item,
    min_score = min_score,
    max_score = max_score,
    start = start,
    stop = stop,
    increase = increase,
    nsim = nsim,
    power_levels = power_levels
  )

  sim_data <- core_results$sim_data
  samples <- core_results$samples

  sample_sizes <- rep(seq(start, stop, by = increase), each = nsim)
  sample_sizes <- sample_sizes[1:length(samples)]

  split_half_rel <- data.frame(
    sample_size = sample_sizes,
    reliability = map_dbl(samples, function(sample_dat) {
      split_half_item_rel(
        dat = sample_dat,
        item_col = "item",
        score_col = "score"
      )
    })
  )
  cat("  split-half reliability done\n")
  save_checkpoint()

  cat("Pipeline done\n")

  return(list(
    sim_data = sim_data,
    cutoff = core_results$cutoff,
    samples = samples,
    proportion_summary = core_results$proportion_summary,
    corrected_summary = core_results$corrected_summary,
    split_half_rel = split_half_rel
  ))
}

# Chunked variant of run_simulation_pipeline(), for jobs whose window is
# large enough that materializing every sample-size step at once (as
# run_population_pipeline() does) risks exhausting memory. That function
# holds every step's simulated samples in one `samples` list for the whole
# job - needed again later for reliability - so peak memory scales with
# the *sum* over all steps, not any single step. This version simulates,
# summarizes, and discards one sample size at a time, and checkpoints
# out_file after every step so a killed/crashed job doesn't lose already-
# computed steps. See run_job_chunked() / needs_chunked_run() in
# run_power_batch.R for when this gets used instead of the normal path.
run_simulation_pipeline_chunked <- function(
  df,
  item_col,
  mean_col,
  sd_col,
  n_per_item = 68,
  min_score = 0,
  max_score = 9,
  start = 20,
  stop = 100,
  increase = 5,
  nsim = 500,
  power_levels = c(80, 85, 90, 95),
  out_file = NULL,
  log_file = "power_batch.log"
) {
  cat(sprintf("Chunked pipeline started: %s\n", item_col))
  cat(sprintf("  rows in input: %d\n", nrow(df)))

  items <- df %>%
    mutate(
      item = .data[[item_col]],
      mean = .data[[mean_col]],
      sd   = .data[[sd_col]],
      n    = n_per_item
    ) %>%
    select(item, mean, sd, n, everything()) %>%
    filter(!is.na(item) & !is.na(mean) & !is.na(sd))

  sim_data <- items %>%
    mutate(scores = pmap(list(mean, sd, n),
                         ~ rtruncnorm(..3,
                                      a = min_score,
                                      b = max_score,
                                      mean = ..1,
                                      sd = ..2))) %>%
    unnest(scores) %>%
    mutate(score = round(scores)) %>%
    filter(is.finite(.data[["score"]])) %>%
    select(item, score, any_of(c("pos", "length_bucket", "stroke_bucket")))

  cat(sprintf("  simulated data ready: %d rows\n", nrow(sim_data)))

  population <- sim_data %>% filter(is.finite(.data[["score"]]))

  cutoff <- calculate_cutoff(
    population = population,
    grouping_items = "item",
    score = "score",
    minimum = min_score,
    maximum = max_score
  )
  cat(sprintf("  cutoff: %.3f  prop_var: %.4f  n_items: %d\n",
              cutoff$cutoff, cutoff$prop_var, n_distinct(population$item)))

  sample_sizes <- seq(start, stop, by = increase)
  cat(sprintf("  chunked run: %d step(s) from n=%d to n=%d, nsim=%d/step\n",
              length(sample_sizes), start, stop, nsim))

  proportion_summary_parts <- vector("list", length(sample_sizes))
  split_half_rel_parts <- vector("list", length(sample_sizes))

  save_checkpoint <- function(step_i) {
    if (is.null(out_file)) return(invisible(NULL))
    partial <- list(
      corrected_summary  = NULL,
      proportion_summary = dplyr::bind_rows(proportion_summary_parts[seq_len(step_i)]),
      split_half_rel     = dplyr::bind_rows(split_half_rel_parts[seq_len(step_i)])
    )
    saveRDS(build_save_data(partial), out_file)
  }

  for (i in seq_along(sample_sizes)) {
    n <- sample_sizes[[i]]
    log_line("  [", format(Sys.time(), "%H:%M:%S"), "] chunked step ", i, "/",
             length(sample_sizes), ": n=", n, log_file = log_file)

    step_samples <- simulate_samples(
      start = n,
      stop = n,
      increase = increase,
      population = population,
      replace = TRUE,
      nsim = nsim,
      grouping_items = "item"
    )
    step_samples <- purrr::map(step_samples, function(sample_dat) {
      sample_dat %>%
        filter(is.finite(.data[["score"]]))
    })

    proportion_summary_parts[[i]] <- calculate_proportion(
      samples = step_samples,
      cutoff = cutoff$cutoff,
      grouping_items = "item",
      score = "score"
    )

    split_half_rel_parts[[i]] <- data.frame(
      sample_size = n,
      reliability = map_dbl(step_samples, function(sample_dat) {
        split_half_item_rel(
          dat = sample_dat,
          item_col = "item",
          score_col = "score"
        )
      })
    )

    rm(step_samples)
    gc()

    save_checkpoint(i)
  }

  proportion_summary <- dplyr::bind_rows(proportion_summary_parts)
  split_half_rel <- dplyr::bind_rows(split_half_rel_parts)

  corrected_summary <- calculate_correction(
    proportion_summary = proportion_summary,
    pilot_sample_size = n_per_item,
    proportion_variability = cutoff$prop_var,
    power_levels = power_levels
  )

  cat("  split-half reliability done\n")

  if (!is.null(out_file)) {
    saveRDS(build_save_data(list(
      corrected_summary = corrected_summary,
      proportion_summary = proportion_summary,
      split_half_rel = split_half_rel
    )), out_file)
    cat(sprintf("  [%s] final checkpoint saved\n", format(Sys.time(), "%H:%M:%S")))
  }

  cat("Chunked pipeline done\n")

  list(
    sim_data = sim_data,
    cutoff = cutoff,
    samples = NULL,
    proportion_summary = proportion_summary,
    corrected_summary = corrected_summary,
    split_half_rel = split_half_rel
  )
}

split_half_item_rel <- function(dat, item_col = "item", score_col = "score") {
  dat <- dat %>%
    group_by(.data[[item_col]]) %>%
    mutate(id = row_number()) %>%
    ungroup()

  ids <- unique(dat$id)
  half1_ids <- sample(ids, length(ids) / 2)

  half1 <- dat %>%
    filter(id %in% half1_ids) %>%
    group_by(.data[[item_col]]) %>%
    summarise(mean1 = mean(.data[[score_col]], na.rm = TRUE), .groups = "drop")

  half2 <- dat %>%
    filter(!id %in% half1_ids) %>%
    group_by(.data[[item_col]]) %>%
    summarise(mean2 = mean(.data[[score_col]], na.rm = TRUE), .groups = "drop")

  merged <- inner_join(half1, half2, by = item_col)
  r <- cor(merged$mean1, merged$mean2, use = "complete.obs")
  (2 * r) / (1 + r)
}

