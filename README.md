# ML One Network

This repository contains the materials, stimuli, and tasks for the ML One Network project — a many-languages extension of the SPAML semantic priming project.

## Folders

**[01-Translation](01-Translation/README.md)** — Stimuli selection, translation pipeline, and finalized word pairs for each language. Start here to understand how cue-target pairs were chosen and translated.

**[02-Stimuli](02-Stimuli/)** — Per-language norming files and scripts for creating the final stimuli sets used in the experiment.

**[03-Tasks](03-Tasks/)** — JATOS experiment templates and build scripts for each task, organized by study.

**[04-Ethics](04-Ethics/)** — IRB application, approval, and ethics packet.

**[05-Power](05-Power/README.md)** — AIPE-based sample-size power simulations for the semanticprimeR norming variables, run against the finalized SPAML datasets.

**[06-Data](06-Data/)** — Collected data (stored externally; see folder for access details).

## Notes

**R environment**: This project uses `renv` for reproducible package management. Run `renv::restore()` after cloning to install all packages. `sylly.fr` is sourced from a custom repository (`https://undocumeantit.github.io/repos/l10n/`) and is included in the lockfile.

**subs2vec downloads**: The stimuli creation pipeline downloads word frequency and vector files from subs2vec. As of June 2026 these require a login and cannot be run automatically. Three languages (Japanese, Chinese Simplified, Chinese Traditional) also required hand-created vector files not available via subs2vec. See [01-Translation/README.md](01-Translation/README.md) for details.
