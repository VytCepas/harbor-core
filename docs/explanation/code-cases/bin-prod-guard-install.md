---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/prod-guard-install.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/prod-guard-install.sh, lines 6-29 (before this edit)

```text
WHY. yard's prod_guard.py owns the cloud/data destruction corpus by
contract (bin/admission-bash.sh:6-8 — the floor's Bash guard omits that class on
the understanding that this guard covers it). Measured machine-wide
(harbor#56): the number of settings files that wire prod_guard is ZERO. The
template wires it (templates/base/dot_agents/settings.json.tmpl:61); no
rendered repo on this box does. So every gcloud/bq/gsutil/terraform/kubectl
call has run with no guard from either layer, and the contract's
complementarity was one-sided in practice. This is the wiring that makes it
true.

WHAT IT INSTALLS, AND WHY IT COPIES RATHER THAN POINTS AT bin/:
  $DIR/hooks/prod_guard.py         ← byte copy of the AUTHORITATIVE prod_guard
                                     (source repo preferred over the mirror —
                                     see the source-selection note below)
  $DIR/bin/prod-guard-ambient.sh   ← the deferral shim
A hook wired at a git working tree changes meaning on `git checkout`, which
would make the global guard depend on which branch happens to be out. Both
copies land in the config dir, the same reasoning deploy-runtime-install.sh uses.

IT WIRES ONE PreToolUse HOOK, which admission-install.sh's gate does not cover and
should not: eval-pass-score.sh blocks the FLOOR (six guards, exit-2 vetoes). This is
one `ask`-posture guard whose corpus the floor deliberately excludes, and
harbor#56 argues at length why it is not a floor guard. Its blast radius is a
prompt on ~0.4% of Bash calls (46 of 11,505 historical).
```

## bin/prod-guard-install.sh, lines 41-55 (before this edit)

```text
SOURCE SELECTION IS A SECURITY DECISION, not a path convenience.

The first version of this installer copied from the marketplace clone, and that
clone is a MIRROR that goes stale silently. Measured: its HEAD is c2b81b1
(2026-07-13, release 1.1.7) while the PI-903 symlink refusal landed upstream in
ac85947 (2026-07-26, yard#904). All three installed plugin copies —
marketplace, its templates, and the 0.8.0 cache — are 266 lines with ZERO
`is_symlink` occurrences. So this installer would have deployed, ambiently and
machine-wide, exactly the version a planted symlink defeats: `.agents` pointing
anywhere supplies its own `safety.allow` and switches the destructive-command
deny table off wholesale.

The fix exists upstream and reaches nothing, because the distribution channel
between them is stale. Preferring the source repo when it is present is the
only ordering that cannot install a known-vulnerable guard.
```

## bin/prod-guard-install.sh, lines 79-85 (before this edit)

```text
REFUSE TO INSTALL A GUARD THAT A SYMLINK DEFEATS. This is not a style check on
the source: `_find_config` locates the file `safety.allow` is read from, so a
copy without the refusal lets an allowlist planted outside the repo disable the
whole deny table. Installing that ambiently would spread the bypass to every
directory on the machine rather than close it — worse than not installing.
Asserted on the CONTENT of whatever copy was selected, so it holds no matter
which source won above or how the channel drifts later.
```

## bin/prod-guard-install.sh, lines 91-92 (before this edit)

```text
Verified at install time so the runtime never has to: the shim's own
python3-missing path exists for a machine that breaks LATER, not for this one.
```

## bin/prod-guard-install.sh, lines 101-102 (before this edit)

```text
Wired as floor-install wires its vetoes, onFailure included: a prod_guard that times out otherwise lets
the call through (harbor#1277). A hook already wired gains the key.
```

## bin/prod-guard-install.sh, lines 110-112 (before this edit)

```text
Name the channel's staleness rather than let it pass silently: it is the defect
that made the refusal above necessary, and it is invisible from here otherwise.
This installer is now safe from it; anything SCAFFOLDED from the mirror is not.
```

## bin/prod-guard-install.sh, lines 117-118 (before this edit)

```text
The mirror is what an update WOULD install; the copy Claude Code loads is the installed one, and a
current mirror over a stale install read green (harbor#925). One line per install path.
```

## bin/prod-guard-install.sh, lines 121-122 (before this edit)

```text
Fields split on \037, never a tab: IFS merges empty tab fields, and @tsv escapes a tab in a path
(review #932). Every field is non-empty, and an entry with no installPath names nothing to compare.
```

## bin/prod-guard-install.sh, lines 179-184 (before this edit)

```text
RE-PIN, for the reason deploy-runtime-install.sh:139 gives and this installer originally
missed: it just wrote settings.json, so the teeth pin is stale BY OUR OWN HAND.
Leaving it would hand the operator a drift alarm caused by the tool that told them
to run it — the statusline flips floor✓ → floor DRIFT — and would make B6, once
installed, block every session. A false alarm is a defect, not caution (§2.11).
--repin adds no deny entry, so a withdrawn entry stays withdrawn.
```
