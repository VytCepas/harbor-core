# Brief — the pedagogy reviewer (doc-workshop-deck)

**Inputs:** `plan.json` (`{plan_path}`), and every slide's text with its speaker notes
(`{slide_text_with_notes}`). Audience: **{audience}**. Session: **{minutes} min**.

**Done looks like:** a findings list in which each finding names a slide, the rule it breaks,
and a concrete rewrite. Judge only what a lint cannot judge:

1. **Assertions.** Is each content headline a claim the slide proves, or a topic label
   written as a sentence?
2. **Concrete before abstract.** Does each concept appear first as a piece of the running
   example (`{running_example}`), before the general term?
3. **Analogies.** Does each one map onto the real mechanism? Name the point where it would
   mislead this audience.
4. **Worked example before exercise.** Has each activity been preceded by a fully worked case
   of the same kind?
5. **Activities.** Can each one be done in its minutes, in this room (`{room}`)? Does each
   check test its outcome's verb, not just recognition of a word?
6. **Load.** Are there more than about four new terms in one ten-minute stretch? Is there
   anything on a slide that serves no outcome (Mayer's coherence principle)?

**Constraints:** read-only, change nothing. A finding without a rewrite is not a finding.
"No findings" is a valid answer. Do not rate or score the deck.

**Reply with only JSON:** `[{"slide","rule","problem","rewrite"}]`
