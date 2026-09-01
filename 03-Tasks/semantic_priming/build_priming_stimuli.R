# Information -------------------------------------------------------------

# Builds semantic priming embedded stimulus files for SPAML deployment.
#
# Two modes:
#   "panel" - 14 static versions, built once before launch.
#             Participants are assigned a version number by the platform.
#             Cycles through the full trial pool across versions so every
#             word pair accumulates data roughly equally.
#
#   "lab"   - 1 version regenerated periodically as data comes in.
#             Prioritises pairs that still need observations (high SE / low N).
#             Stub for now — adaptive logic added once data collection starts.
#
# Trial composition per version (matches Korean SPAML):
#   150 nonword–nonword pairs  → 300 items
#   100 mixed nonword pairs    → 200 items  (nw→word OR word→nw)
#    75 related word pairs     → 150 items
#    75 unrelated word pairs   → 150 items
#   -----------------------------------------------
#   400 pairs total            → 800 items across 8 blocks of 50 pairs each
#
# Inputs (from 05_final_languages/{lang}/):
#   {lang}_trials_final.csv   — 5000 pairs (1000 each type)
#   {lang}_practice_trials.csv — practice pairs (same column format)
#
# Output:
#   builds/{lang}/priming/panel/v1/embedded/{hash}.json  … v14/
#   builds/{lang}/priming/lab/v1/embedded/{hash}.json


# Configuration -----------------------------------------------------------

MODE           <- "panel"   # "panel" or "lab"
LANG           <- "uk"      # language code matching 05_final_languages/{lang}/
NUMBER_FOLDERS <- 14        # number of panel versions
RANDOM_SEED    <- 42        # set to NULL for lab mode truly-random runs

# Paths (relative to this script's location in 03-Tasks/semantic_priming/)
lang_path   <- paste0("../../01-Translation/05_final_languages/", LANG, "/")
builds_path <- paste0("../builds/", LANG, "/priming/")

# Hash filenames — fixed, must match spaml_template.json poolPaths
PRACTICE_HASH <- "db6cc958e11fc3987cebacc1e14b253b95b4de4d05c702ecbb3294775adb3e4b.json"
BLOCK_HASHES  <- c(
  "3cee33bcfe0a7bdac59ec1374ca41a4ea7fe6e772c9b0ab0770f0d1f5cb09e41.json",  # real1
  "ae2c5987efa101760004c66c0da975c7dd75605ada53cabf75ec439ce68a5871.json",   # real2
  "3a95e1234833448efe1e098102f00e2f4bb85d6edd8b6a093f62a93d4dcf4f4e.json",  # real3
  "994ac7a5038c8713adb715e04d6639acda5d02a40abdb81d59c0d39dfea6cf06.json",  # real4
  "9febe5343449a1c79d42f597f494397c595dd944600a7908e38167bbb18234ee.json",  # real5
  "cd99c6e5b4b714268551fce4fc08729821a7bdb4a6f2294152b2e0d5e4ddfb99.json",  # real6
  "c378cfb94011283fa98a84e5e2d34272f4a3134cda08298ed211f9c6c2331757.json",  # real7
  "0d00e4cacc8fbd59aa34a45be41f535ccade17517701d1b3fa6ef139ca8746a3.json"   # real8
)


# Libraries ---------------------------------------------------------------

library(rio)
library(dplyr)
library(jsonlite)


# Functions ---------------------------------------------------------------

# Build the flat JSON string for a block of pairs.
# Each pair emits two items: cue entry then target entry.
pairs_to_json_string <- function(pairs, lang) {
  cue_col    <- paste0(lang, "_cue")
  target_col <- paste0(lang, "_target")

  together <- paste0(
    '{"word": "', pairs[[cue_col]],    '", "class": "', pairs[["cue_type"]],    '"}, ',
    '{"word": "', pairs[[target_col]], '", "class": "', pairs[["target_type"]], '"}'
  )
  paste0("[", paste(together, collapse = ", "), "]")
}

# Write all embedded files for one version folder.
write_version <- function(all_trials, practice_json, folder_path, lang) {
  embedded_dir <- file.path(folder_path, "embedded")
  dir.create(embedded_dir, recursive = TRUE, showWarnings = FALSE)

  writeLines(practice_json, file.path(embedded_dir, PRACTICE_HASH))

  for (b in seq_along(BLOCK_HASHES)) {
    rows       <- ((b - 1) * 50 + 1):(b * 50)
    block_json <- pairs_to_json_string(all_trials[rows, ], lang)
    writeLines(block_json, file.path(embedded_dir, BLOCK_HASHES[b]))
  }

  cat("  written:", folder_path, "\n")
}

# Precompute a cycling index vector long enough for all versions.
# Reshuffles the pool each time it is exhausted so the ordering varies.
make_cycle_idx <- function(pool_n, needed, seed = 42) {
  if (!is.null(seed)) set.seed(seed)
  idx <- sample(pool_n)
  while (length(idx) < needed) {
    idx <- c(idx, sample(pool_n))
  }
  idx[seq_len(needed)]
}

# Verify trial composition (mirrors cat() checks in Korean R script).
check_composition <- function(all_trials, version_num) {
  cat("\nv", version_num, "—", nrow(all_trials), "pairs\n")
  print(table(all_trials$cue_type, all_trials$target_type, dnn = c("cue_type", "target_type")))
}


# Load Data ---------------------------------------------------------------

trials   <- import(paste0(lang_path, LANG, "_trials_final.csv"))
practice <- import(paste0(lang_path, LANG, "_practice_trials.csv"))

cue_col    <- paste0(LANG, "_cue")
target_col <- paste0(LANG, "_target")

# Separate pools by trial type
nn_pool    <- trials %>% filter(cue_type == "nonword", target_type == "nonword")
mixed_pool <- trials %>% filter(xor(cue_type == "nonword", target_type == "nonword"))
rel_pool   <- trials %>% filter(type == "related")
unrel_pool <- trials %>% filter(type == "unrelated")

cat("Pool sizes:\n")
cat("  nn-nonword:", nrow(nn_pool),    "\n")
cat("  mixed:     ", nrow(mixed_pool), "\n")
cat("  related:   ", nrow(rel_pool),   "\n")
cat("  unrelated: ", nrow(unrel_pool), "\n")

practice_json <- pairs_to_json_string(practice, LANG)


# Panel Mode --------------------------------------------------------------

if (MODE == "panel") {

  cat("\n=== PANEL MODE:", NUMBER_FOLDERS, "versions ===\n")

  # Precompute cycling indices across all versions
  nn_idx    <- make_cycle_idx(nrow(nn_pool),    NUMBER_FOLDERS * 150, seed = RANDOM_SEED)
  mixed_idx <- make_cycle_idx(nrow(mixed_pool), NUMBER_FOLDERS * 100, seed = RANDOM_SEED + 1)
  rel_idx   <- make_cycle_idx(nrow(rel_pool),   NUMBER_FOLDERS * 75,  seed = RANDOM_SEED + 2)
  unrel_idx <- make_cycle_idx(nrow(unrel_pool), NUMBER_FOLDERS * 75,  seed = RANDOM_SEED + 3)

  all_versions <- list()

  for (i in seq_len(NUMBER_FOLDERS)) {

    nn_rows    <- nn_idx[   ((i - 1) * 150 + 1):(i * 150)]
    mixed_rows <- mixed_idx[((i - 1) * 100 + 1):(i * 100)]
    rel_rows   <- rel_idx[  ((i - 1) * 75  + 1):(i * 75) ]
    unrel_rows <- unrel_idx[((i - 1) * 75  + 1):(i * 75) ]

    all_trials <- rbind(
      nn_pool[nn_rows, ],
      mixed_pool[mixed_rows, ],
      rel_pool[rel_rows, ],
      unrel_pool[unrel_rows, ]
    )

    set.seed(RANDOM_SEED + i)
    all_trials <- all_trials[sample(nrow(all_trials)), ]

    check_composition(all_trials, i)
    all_versions[[i]] <- all_trials

    folder_path <- file.path(builds_path, "panel", paste0("v", i))
    write_version(all_trials, practice_json, folder_path, LANG)
  }

  # Summary: confirm each pair appears the expected number of times
  all_versions_df <- bind_rows(all_versions)
  pair_col <- paste0(cue_col, "_", target_col)
  all_versions_df$word_combo <- paste0(all_versions_df[[cue_col]], "_", all_versions_df[[target_col]])
  pair_counts <- all_versions_df %>%
    group_by(word_combo) %>%
    summarize(n_versions = n(), .groups = "drop")

  cat("\nPair appearance counts (min/mean/max across", NUMBER_FOLDERS, "versions):\n")
  cat("  min:", min(pair_counts$n_versions),
      " mean:", round(mean(pair_counts$n_versions), 2),
      " max:", max(pair_counts$n_versions), "\n")

}


# Lab Mode (adaptive stub) ------------------------------------------------

if (MODE == "lab") {

  cat("\n=== LAB MODE: adaptive version ===\n")

  # TODO: read collected SQLite data for this language, compute per-pair stats,
  # filter to undone pairs (SE > 0.09 or answered_n < 50), and sample from
  # that pool — falling back to the full pool when undone pairs run low.
  # See ko_summarize_stim.R adaptive section for the reference implementation.
  #
  # data_path <- paste0("/var/www/html/", LANG, "/data/data.sqlite")
  # collected <- processData(data_path)
  # ... compute SE, flag done/undone ...
  # lang_use    <- subset(lang_merged, is.na(done_both) | done_both == FALSE)
  # lang_sample <- subset(lang_merged, done_both == TRUE)

  # For now: random sample from the full pool (same as first panel version)
  message("Lab mode: no collected data path set — using random full-pool sample.")

  set.seed(NULL)  # truly random each run

  nn_v    <- nn_pool[sample(nrow(nn_pool),       150, replace = FALSE), ]
  mixed_v <- mixed_pool[sample(nrow(mixed_pool), 100, replace = FALSE), ]
  rel_v   <- rel_pool[sample(nrow(rel_pool),      75, replace = FALSE), ]
  unrel_v <- unrel_pool[sample(nrow(unrel_pool),  75, replace = FALSE), ]

  all_trials <- rbind(nn_v, mixed_v, rel_v, unrel_v)
  all_trials <- all_trials[sample(nrow(all_trials)), ]

  check_composition(all_trials, "lab")

  folder_path <- file.path(builds_path, "lab", "v1")
  write_version(all_trials, practice_json, folder_path, LANG)

}
