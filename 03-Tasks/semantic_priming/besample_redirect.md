# Adding the BeSample redirect back to the priming task

The rating tasks (`03-Tasks/<task>/thank_you.html`) send BeSample participants
back to BeSample when they finish. The priming task **does not**, because the
uk priming study isn't recruited through BeSample's new redirect flow. It was
added in `c1def1a` and taken back out afterwards. To add it back for a future
language, make these three edits to `spaml_template.json`, then rebuild
(`build_priming_spaml()` in `translate_build_experiment.ipynb`), re-export the
bundle from the lab.js builder, and `pull_priming_build("<lang>")` in
spaml2-private.

The redirect only triggers when `battempt` is in the study link, so non-BeSample
participants see the normal end screen either way.

## 1. Consent Form (component `21`) — build the return URL

In the `before:prepare` message handler, right after
`window.completion_code = completion_code`, add:

```js
// BeSample participants (battempt in the URL) get sent back to BeSample
// with their completion code from the end screen
window.besample_redirect_url = battempt !== null
  ? 'https://step.besample.app/study/other/redirect?battempt=' +
    encodeURIComponent(battempt) + '&completion_code=' +
    encodeURIComponent(completion_code)
  : null
window.besample_display = window.besample_redirect_url ? 'block' : 'none'
```

## 2. End of Experiment (component `8`) — fallback link

In `content`, after the paragraph ending
`...to show you completed the experiment.</p>`, add:

```html
<div style="display: ${ window.besample_display };">
<p class="text-left">You will be returned to BeSample in a few seconds.</p>
<p class="text-left">If you are not redirected automatically, <a href="${ window.besample_redirect_url }">click here to return to BeSample</a>.</p>
</div>
```

## 3. End of Experiment (component `8`) — automatic redirect

Replace its empty `messageHandlers` entry with a `run` handler:

```json
{
  "title": "BeSample redirect",
  "message": "run",
  "code": "// Short delay so the Transmit plugin can flush the last trials to\n// backend.php before we navigate away\nif (window.besample_redirect_url) {\n  setTimeout(function () {\n    window.location.href = window.besample_redirect_url\n  }, 5000)\n}"
}
```

## Translations

The end-screen text needs rows in
`01-Translation/05_final_languages/<lang>/<lang>_experiment.csv`:

- `You will be returned to BeSample in a few seconds.`
- `If you are not redirected automatically,`
- `click here to return to BeSample`

The Ukrainian rows are already there (the last two are shared with the rating
tasks).
