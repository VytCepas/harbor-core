---
description: Everything installed, which tier it is in, and whether the box has drifted from the repo
allowed-tools: Bash(sh ~/port/harbor/bin/skills-install.sh:*), Bash(sh ~/port/harbor/bin/skill-catalog.sh:*), Bash(grep:*), Bash(ls:*)
---

Install state of every tracked skill — what is current, drifted, nested or
absent:

!`sh ~/port/harbor/bin/skills-install.sh --live 2>&1`

Whether the generated indexes are current. The tracked book lists the skills this
checkout ships; the installed book lists every skill installed on the box, the
packs' and the box's own included:

!`sh ~/port/harbor/bin/skill-catalog.sh --check 2>&1 | tail -8`

!`sh ~/port/harbor/bin/skill-catalog.sh install --check --live 2>&1 | tail -8`

Report:

1. **Anything `NESTED` first, and treat it as a live defect.** It means an
   earlier hand-typed `cp -R` without the trailing `/.` created
   `<name>/<name>/` and **the original files are still the ones serving**.
   Nothing errors in that state, which is why it survives.
2. **Any `DRIFTED` row with its direction.** Never advise reinstalling until the
   direction is known — on 2026-08-06 a reinstall was one keystroke from
   deleting 38 lines of newer work that existed only on the box. If lint X8
   calls the direction undecidable, say so and read the diff.
3. **Whether either book is stale**, and if so the command to regenerate it —
   `sh ~/port/harbor/bin/skill-catalog.sh` for the tracked one, and for the installed
   one the deploy of the skills component (the operator's act; the check above
   prints its command) — never a copy in either direction. They are generated;
   capturing the live copy into the repo destroys content. The installer composes
   the installed book rather than copying the tracked one over it, so the listing
   above calls it `current` when it is what the generator writes for this box.

Nothing here writes. Installing is `--apply --live`, it changes what every
future session loads, and the B8 re-pin afterwards is the operator's act from
their own terminal.

Every path here is absolute on purpose: a slash command runs in whatever cwd the
session has, and `sh bin/…` resolved to nothing from anywhere but the repo root.
