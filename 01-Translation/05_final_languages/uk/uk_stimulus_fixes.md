# Ukrainian priming stimulus fixes (2026-10-18)

These target words had very low "word" accuracy in the live priming data, so
they were replaced in `uk_trials_final.csv`. The replacements match the words
used in the SPAML Russian data, so items line up across datasets. No pairs
were dropped. Each word was replaced in every trial it appears in (related,
unrelated, and mixed word/nonword), 20 trials in total.

| English | Old Ukrainian | New Ukrainian | SPAML Russian |
|---|---|---|---|
| ming → ling | мін → лін | рік → кіт | год → кот |
| illusion → hallucination | галюкування | галюцинація | галлюцинация |
| kilo → gram | гран | грам | грамм |
| crack → hole | отворити | діра | дыра |
| palace → castle | замку | замок | замок |
| key → lock | замок | засув | задвижка |

мера (mayor) and черевний (abdominal) were also on the low side (about 57–59%
correct), but they were left alone because the samples are still small.

The copy the pipeline reads, `spaml2-private/R/wordLists/uk_trials_final.csv`,
was updated to match.

## Expected in the Shiny app

In the priming pairs table, the old pairs (for example мін → лін and
палац → замку) no longer appear, because the summary is matched on cue+target.
The new pairs start at 0 answered with no M Z. Responses to the old pairs are
still in the raw data but no longer count.

## Still to do

- **Norm the new words in the rating tasks.** рік, кіт, галюцинація, грам,
  діра, замок (as "castle") and засув were not in the original Ukrainian
  rating lists, so they need full norms.
- Cosine values on the changed related pairs still belong to the old words.
- The nonword partners (гавскування, грлі, заожу, отвотати, усн) were built
  from the old spellings. They still work as nonwords, but are less closely
  matched to the new words.
