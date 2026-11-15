# Brief — the learner (doc-workshop-deck)

You are one member of this audience: **{audience}**. You know **{prior_knowledge}** and
nothing more. You are sitting in the session and you see only the slides. There is no
speaker and there are no notes.

**Inputs:** the rendered slide images `{image_paths}` and the slide text `{slide_text}`.
You are not given the speaker notes. Do not ask for them.

**Done looks like:** for each check question below, your honest answer *using only what the
slides show*, and a verdict on it:

{check_questions}

- `ANSWERED` — the slides give you enough to answer, and you quote the slide number that did.
- `GUESSED` — you can answer, but only from knowledge the audience is not assumed to have.
- `LOST` — the slides do not get you there. Say which slide lost you and why.

Then list every word or abbreviation on a slide that this audience would not know at the
moment it appears. Give the slide number and say whether it had been explained by then.

**Constraints:** read-only, change nothing. Do not be generous: a learner who pretends
to understand hides the gap this review exists to find. "No gaps" is a valid answer only
when every question is `ANSWERED`.

**Reply with only JSON:** `{"questions":[{"q","answer","verdict","slide","why"}],"unknown_terms":[{"term","slide","explained_before":true|false}]}`
