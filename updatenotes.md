# Update Notes

## Stimuli Creation — Hand-Created Vector Files

During the original SPAML stimuli creation process, three languages required word vector files that were created by hand rather than downloaded via `subs2vec`. These files are **not** in the repository (they are large) and must be sourced separately before the relevant chunks in `stimuli_creation.Rmd` can be run.

### Files needed and where to place them

| Language | File | Location in project |
|---|---|---|
| Japanese | `ja_300_5_sg_wxd.csv` | `01-Translation/01_stimuli_selection/subs_vec/ja/` |
| Chinese Simplified | `zh_300_5_sg_wxd.csv` | `01-Translation/01_stimuli_selection/subs_vec/zh_cn/` |
| Chinese Traditional | `tw_300_5_sg_wxd.csv` | `01-Translation/01_stimuli_selection/subs_vec/zh_tw/` |

These are word2vec-style CSV files with a `word` column followed by 300 embedding dimensions.

### Vietnamese

Vietnamese (`vi`) was also handled differently — both the word count and vector files were pre-populated rather than downloaded via `import_other()` (those calls are commented out in the Rmd). The zip files should be placed at:

- `01-Translation/01_stimuli_selection/subs_count/vi/vi.zip`
- `01-Translation/01_stimuli_selection/subs_vec/vi/vi.zip`

The `vi` vector zip should unzip to `subs.vi.1e6.vec`, consistent with the standard subs2vec format used for other languages.

### subs2vec downloads (all other languages)

The remaining languages use files downloaded from subs2vec (`https://github.com/jvparidon/subs2vec`). As of June 2026, these require a login to download, making that portion of the pipeline not fully reproducible without credentials. The `subs_count/`, `subs_vec/`, `wiki_count/`, and `wiki_vec/` folders exist in the project as empty placeholders (`.gitkeep`).

### Final Stimuli Set chunk

The `Final Stimuli Set` chunk in `stimuli_creation.Rmd` (line ~3470) depends on `finalstimuli`, which is built in the `eval=F` chunk above it. This chunk must be run interactively before the Final Stimuli Set chunk will work when knitting.
