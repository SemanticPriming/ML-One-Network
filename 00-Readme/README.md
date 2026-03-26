## Folders and Processes

`01-Translation`: 

- translate_stimuli.ipynb: 
    - uses `en_words.csv` to translate stimuli into the first start for each language not translated during the SPAML project
    - creates individual folders for each language using three letter facebook language codes with `{lang}_word_pairs.csv` as the starter file
    - these files are then copied over to the `02-Stimuli` folder

- translate_experiment.ipynb:
    - uses `task_translation_template.xlsx` to go from English to the target language (which includes all the rating tasks, semantic priming is a separate set of files)
    - outputs into `translation/{lang}/` for the translated instructions - both forward and backward
    - these are checked for consistency before being using to build jzip versions  

`02-Stimuli`:

- folders for each language using the same three letter language codes
    - `{lang}_word_pairs_update.csv`: stimuli file updated after investigating for cue-target matches and other weird words from the translation file
    - `{lang}_variables_normed.csv`: a true/false file that indicates which words should be normed for each task based on previous data available 
    - `{lang}.Rmd`: the file used to create the norming file before the study and the final combined dataset for each language after the study 
- create_stimuli.ipynb:
    - uses the variables normed and pairs update file to create the stimuli sets 
    - they are separated into 400 word buckets for giving out links to the experiment
    - they are first selected from words we don't have normed already and the filled in when we need to complete a set 

`03-Tasks`:

- Includes folders for each study as templates in JATOS format to create the language specific versions
- translate_build_experiment.ipynb:
    - uses the `01-Translation` folder experiment files to build the html files for each experiment
    - uses the `02-Stimuli` folder to grab the stimuli lists for each task 
    - creates the separate .jas files for each experiment
    - creates the .jzip for importing 