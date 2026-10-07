# Build the URL + confirmation-code list to upload to Clickworker
# ("Create a list of survey URLs" -> "Upload Data").
#
# Works for any language and any of the 7 tasks (priming + the six rating
# tasks): all of them derive their completion code from the URL the same
# way. With ?response_id=<n> in the link (and no bnum/completion_code), the
# end screen shows response_id * bkey, bkey = 98063 (priming:
# semantic_priming/spaml_template.json, Consent Form component; rating tasks:
# <task>/index_consent_demos.html). So no study changes are needed -- each
# row's link carries a random 3-digit response_id and its confirmation_code
# is response_id * 98063. The ids are random (not 1, 2, 3...) so neither a
# worker's link nor their code reveals anyone else's. Keep BKEY in sync with
# those files.
#
# response_id is used rather than bnum because bnum is BeSample's param;
# keeping them separate means Clickworker rows can't be mistaken for (or
# collide with) BeSample participants in the saved data.
#
# Columns match clickworker_template.xlsx (alongside this script):
# ID, url_to_survey, confirmation_code
#
# Run once per link. The base_url differs per task/language, and the rating
# tasks have one JATOS link per list, so call it once per list.
#
# Usage (from the spaml2-private repo root, same sibling-repo convention as
# pipeline/sync_public_repo.R):
#   source("../ML-One-Network/03-Tasks/make_clickworker_urls.R")
#   make_clickworker_urls(n = 30, base_url = "https://psa007.psysciacc.org/uk/",
#                         lang = "uk", task = "priming")
#   make_clickworker_urls(n = 30, base_url = "<jatos link>", lang = "uk",
#                         task = "aoa_list_1")
#
# Output goes to ML-One-Network/03-Tasks/builds/<lang>/clickworker/ as
# clickworker_urls_<task>_<first>-<last>_<date>.csv. The builds/ folders are
# gitignored in ML-One-Network, so the lists (with the codes) are never
# pushed -- which also means git doesn't back them up, so keep a copy of
# each CSV somewhere safe.

BKEY <- 98063
BUILDS_DIR <- file.path(Sys.getenv("ML_ONE_NETWORK_PATH", "../ML-One-Network"),
                        "03-Tasks", "builds")

make_clickworker_urls <- function(n, base_url, lang = "uk", task = "priming", start_id = 1,
                                  exclude = integer(0),
                                  id_range = 100:999,
                                  out_dir = file.path(BUILDS_DIR, lang, "clickworker"),
                                  out_name = NULL) {
  ids <- seq(start_id, length.out = n)
  # `exclude`: response_ids from earlier lists, so batches never collide
  if (n > length(setdiff(id_range, exclude)))
    stop("Not enough unused response_ids in id_range for n = ", n)
  rids <- integer(0)
  while (length(rids) < n) {
    cand <- sample(id_range, n)
    rids <- unique(c(rids, setdiff(cand, c(exclude, rids))))
  }
  rids <- rids[seq_len(n)]
  sep <- ifelse(grepl("?", base_url, fixed = TRUE), "&", "?")
  out <- data.frame(
    ID = ids,
    url_to_survey = paste0(base_url, sep, "response_id=", rids),
    confirmation_code = format(rids * BKEY, scientific = FALSE, trim = TRUE),
    stringsAsFactors = FALSE
  )
  if (is.null(out_name)) out_name <- sprintf("clickworker_urls_%s_%s-%s_%s.csv", task, start_id, max(ids), format(Sys.Date(), "%Y-%m-%d"))
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(out_dir, out_name)
  if (file.exists(path)) stop(path, " already exists; not overwriting")
  write.csv(out, path, row.names = FALSE)
  message("Wrote ", nrow(out), " rows to ", path)
  invisible(out)
}
