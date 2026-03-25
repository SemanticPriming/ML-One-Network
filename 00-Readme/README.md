## Folders and Processes

`01-Translation`: 

- translate_stimuli.ipynb: 
    - uses `en_words.csv` to translate stimuli into the first start for each language not translated during the SPAML project
    - creates individual folders for each language using three letter facebook language codes with `{lang}_word_pairs.csv` as the starter file
    - these files are then copied over to the `02-Stimuli` folder

- translate_experiment.ipynb:
    - 

`02-Stimuli`:

- folders for each language using two letter codes from ISO
    - `{lang}_word_pairs_update.csv`: stimuli file updated after investigating for cue-target matches and other weird words from the translation file
    - `{lang}_variables_normed.csv`: a true/false file that indicates which words should be normed for each task based on previous data available 
    - `{lang}.Rmd`: the file used to create the norming file before the study and the final combined dataset for each language after the study 

`03-Tasks`:

- Includes folders for each study as templates in JATOS format to create the language specific versions