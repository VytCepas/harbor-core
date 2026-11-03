#!/usr/bin/env sh
# skill-catalog.sh — generate the skill catalog, the index that makes invoked-only skills findable (harbor#155, harbor#1149, harbor#1010).
#   Renamed from skill-book.sh (harbor#1010); the old name is retired.
#   EVERY ROW CARRIES A TIER, derived from where the skill lives and never typed: core (skills/), vendored (vendor/skills/),
#   pack (an installed pack's manifest in <config dir>/.harbor-packs lists it), box (installed, and nothing here tracks it); a
#   tool in ~/.local/bin is tier cli. An executable that is no tool (contracts/catalog-non-tools.tsv) is not a row.
#   sh bin/skill-catalog.sh --coverage   the commands and tools section only: exit 1 when a `harbor` verb or a script contracts/cli.md marks Agent-facing has no row in
#                                     contracts/agent-tools.tsv, or a row names a verb or script that does not exist (harbor#1010); 3 when there is nothing to judge
#   sh bin/skill-catalog.sh [--check]    the TRACKED book, skills/skill-catalog/SKILL.md: only the skills the export ships (skills/; vendor/skills/ is dev-layer); --check diffs instead of writing (lint T9)
#   sh bin/skill-catalog.sh install [--check] [--apply] (--live | --dir PATH)
#   sh bin/skill-catalog.sh install --manifest (--live | --dir PATH)
#                                     the MANIFEST DRIFT CHECK (harbor#1010): exit 1 when an installed skill has no row in <config dir>/.harbor-manifest or a pack's
#                                     manifest in .harbor-packs, or a manifest row names a skill dir that is gone; 3 when there is no manifest to judge by
#                                     the INSTALLED book, <config dir>/skills/skill-catalog/SKILL.md: every skill installed there, the box's and the packs' included, and the CLIs in ~/.local/bin; a dry run unless --apply; --check exits 1 when it is not current
#
# THE BOOK ALSO LISTS COMMANDS (harbor#1010): every `harbor <verb>` and every bin/ script contracts/cli.md marks `**Agent-facing.**`, each with its
# USE WHEN and invocation from contracts/agent-tools.tsv, so one grep answers "is there a tool for this". A verb or mark with no row (or a row with
# nothing behind it) is a DEFECT like a broken skill; `--coverage` is the check lint skill.catalog-covers-tools runs.
# Two books, two questions (harbor#1149). The tracked book answers "what does THIS repo ship": the same bytes
# on every machine, reading nothing outside the checkout, so `--check` is a pure function of the tree. The
# installed book answers "what can a session on THIS box reach" (tracked skills plus packs, private layer and
# operator additions); deploy.sh runs `install --apply --live` after the packs.
# Removed notes: docs/explanation/code-cases/bin-skill-catalog.md
#
# Regeneration (harbor#158, decided 2026-10-31), one trigger per book and neither is a session event:
#   tracked book    by hand, `sh bin/skill-catalog.sh`, after a skill under skills/ changes; lint T9 detects staleness.
#   installed book  by `deploy.sh`; lint X8 asks `install --check` whether it still matches the installed skills.
# A SessionStart hook was rejected: it would rewrite the instruction surface (the B8 pin watches it) every session,
# race concurrent sessions, and fail silently. Accepted cost: a hand-copied skill is missing from the installed
# book until X8 reports it.
#
# Generated, not written: a hand-kept index drifts the moment a skill is added or renamed, and an index that lies is trusted.
#
# DEFECTS ARE LOUD, NOT BLANK (harbor#158). A skill with no frontmatter, description or name, a name that is not its
# directory's, or a collision (skills/ vs vendor/skills/, case-only, shared `name:`) is listed in a DEFECTS section
# above every table. Tracked book: write exits 1, `--check` exits 3. Installed book: warns only, a box with one broken skill must still deploy.
#
# `--check` diffs instead of writing, so a lint rule can flag a stale book (T9 is advisory; nothing fails CI on it yet).
#
# `--check` HAS THREE ANSWERS (harbor#1149): 0 current, 1 STALE (regenerate), 3 the generator could not say (an unreadable
# router row, no skills dir). A bad row once exited 1 and was reported as STALE. Every other mode keeps 1 for a refusal; 2 is usage.
#
# Why: `disable-model-invocation: true` removes a skill from the model's listing entirely, so most skills are
# invisible. The book is itself a skill, so one `description` line lists them, and it carries PATHS because a
# hidden skill cannot be invoked but its SKILL.md can always be read.
#
# Triggers are task-shaped, not meta-shaped (harbor#173 A5): they name the work a hidden skill covers, because meta
# triggers ("list skills") only surface the book for an inventory, never mid-task. The meta triggers are kept.
#
# THE "START HERE" TABLE IS DATA (harbor#1149): contracts/skill-book-router.tsv, one row per situation, and a row is
# printed only when its skill is in the book being written, so the tracked book never routes to a skill the repo does
# not ship. On the box, <private layer>/skill-book-router.tsv (contracts/private-layer.md) replaces the text of a row in
# place, or appends a row for a skill core does not route. Only `install` reads it.
set -eu

# --help before any work (S4, harbor#140): first executable line, so a flag is never taken for a request to do work.
# The text is this header, read at runtime, so it cannot drift from the script.
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
# Glob order is LC_COLLATE-dependent; pin it or two boxes generate different books and --check flaps.
LC_ALL=C
export LC_ALL

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
. "$ROOT/bin/library-log.sh"; log_init skill-catalog
. "$ROOT/bin/deploy-install-lib.sh"
TAB='	'
LOCAL_BIN="${HARBOR_SCOPE_LOCAL_BIN:-$HOME/.local/bin}"
OUT="$ROOT/skills/skill-catalog/SKILL.md"
ROUTER="$ROOT/contracts/skill-book-router.tsv"
AGENTTOOLS="$ROOT/contracts/agent-tools.tsv"
NONTOOLS="$ROOT/contracts/catalog-non-tools.tsv"

# An unrecognised argument must not fall through to the write branch (`--chekc` once overwrote the file it was asked to verify).
MODE=tracked; CHECK=0; MANIFEST=0; COVERAGE=0
if [ "${1:-}" = install ]; then MODE=install; shift; fi
il_opt() { case "$1" in --check) CHECK=1; IL_TAKE=1 ;; --manifest) MANIFEST=1; IL_TAKE=1 ;; *) IL_TAKE=0 ;; esac; }
if [ "$MODE" = install ]; then
  il_parse "$@"
else
  case "${1:-}" in
    --check) CHECK=1 ;;
    --coverage) COVERAGE=1 ;;
    '') ;;
    *) printf 'usage: skill-catalog.sh [--check|--coverage] | install [--check|--manifest] [--apply] (--live | --dir PATH)\n' >&2; exit 2 ;;
  esac
  [ "$#" -le 1 ] || { printf 'usage: skill-catalog.sh [--check] | install [--check] [--apply] (--live | --dir PATH)\n' >&2; exit 2; }
fi

# What a book that cannot be generated exits: 3 when --check is asking, because 1 there already means STALE.
RC_BROKEN=1; [ "$CHECK" -eq 0 ] && [ "$MANIFEST" -eq 0 ] && [ "$COVERAGE" -eq 0 ] || RC_BROKEN=3

WORK="$(mktemp -d "${TMPDIR:-/tmp}/skill-catalog.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT INT TERM

# The tracked book names the INSTALL path, not the path it was generated from; otherwise a scan of any other
# directory wrote a scratch path prefix into a tracked file.
if [ "$MODE" = install ]; then
  il_target
  SKILL_DIR="$IL_TARGET/skills"
  # shellcheck disable=SC2088  # the literal text `~`: a row tells a session to read this path, and a session expands it
  if [ "$IL_LIVE" -eq 1 ]; then SHOWN='~/.claude/skills'
  else
    SHOWN="$SKILL_DIR"
    for _h in "$HOME" "$(CDPATH='' cd -P -- "$HOME" 2>/dev/null && pwd -P || printf '%s' "$HOME")"; do
      case "$SHOWN" in "$_h"/*) SHOWN="~${SHOWN#"$_h"}"; break ;; esac
    done
  fi
  PRIV="$(sh "$ROOT/bin/scope-roots.sh" --private 2>/dev/null || :)"
  [ -d "$SKILL_DIR" ] || { log_fail "no skills dir at $SKILL_DIR"; log_nofix "the header of bin/skill-catalog.sh"; log_end || :; exit "$RC_BROKEN"; }
  if [ "$MANIFEST" -eq 1 ]; then
    # Every installed skill is owned by a recorded install (the deploy manifest, or a pack's). A dir with neither, or a row
    # with no dir, is drift; the second is the one nothing else reports.
    IM="$IL_TARGET/.harbor-manifest"
    [ -f "$IM" ] || { log_fail "no $IM: no install has been recorded here, so no skill can be judged"; log_fix "sh bin/deploy.sh --apply --only skills $(il_spell)"; log_end || :; exit 3; }
    : > "$WORK/orphans"; _mn=0
    for _d in "$SKILL_DIR"/*/; do
      [ -f "$_d/SKILL.md" ] || continue
      _n="$(basename "$_d")"; _mn=$((_mn + 1))
      awk -v p="skills/$_n/SKILL.md" '$3 == p { f = 1 } END { exit !f }' "$IM" && continue
      awk -F'\t' -v p="skills/$_n/" 'index($2, p) == 1 { f = 1 } END { exit !f }' "$IL_TARGET"/.harbor-packs/*.tsv 2>/dev/null && continue
      printf 'installed skill %s has no row in %s or in a pack manifest\t%s\n' "$_n" ".harbor-manifest" \
        "sh bin/deploy.sh --apply --only skills $(il_spell) records it; or remove the skill dir if nothing should own it" >> "$WORK/orphans"
    done
    awk '$3 ~ /^skills\/[^\/]+\/SKILL\.md$/ { split($3, a, "/"); print a[2] }' "$IM" | while IFS= read -r _n; do
      [ -f "$SKILL_DIR/$_n/SKILL.md" ] && continue
      # A shipped skill is reinstalled; one the checkout no longer ships has only a stale row, which the prune drops.
      if [ -d "$ROOT/skills/$_n" ] || [ -d "$ROOT/vendor/skills/$_n" ]; then _mf="sh bin/deploy.sh --apply --only skills $(il_spell) $_n"
      else _mf="sh bin/deploy.sh --prune --apply $(il_spell)"; fi
      printf 'the manifest row for skill %s names a skill that is not installed\t%s\n' "$_n" "$_mf" >> "$WORK/orphans"
    done
    if [ -s "$WORK/orphans" ]; then
      while IFS='	' read -r _e _f; do log_fail "$_e"; log_fix "$_f"; done < "$WORK/orphans"
      log_end || :; exit 1
    fi
    log_ok "every one of the $_mn installed skill(s) has a manifest row, and every skill row names an installed skill"; log_end; exit $?
  fi
else
  # shellcheck disable=SC2088
  SHOWN='~/.claude/skills'
  PRIV=''
fi

# The frontmatter ONLY: scanning the whole file misfiled any skill whose body mentioned the key at column 0.
frontmatter() {
  awk 'NR==1 && $0 !~ /^---[[:space:]]*$/ { exit }
       NR>1  && $0 ~  /^---[[:space:]]*$/ { exit }
       NR>1' "$1"
}

is_hidden() { frontmatter "$1" | grep -q '^disable-model-invocation:[[:space:]]*true'; }

# field <file> <key> — a frontmatter scalar, quotes stripped. Returns empty for
# a folded/literal block (`>-`, `|`), which the caller reports rather than
# printing the block indicator as if it were the value.
field() {
  frontmatter "$1" \
    | awk -v k="^$2:[[:space:]]*" '$0 ~ k { sub(k, ""); print; exit }' \
    | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//"
}

# Escape the one character that would break out of a markdown table cell.
cell() { printf '%s' "$1" | sed 's/|/\\|/g'; }

# Truncate on whole words, never a byte offset: `substr()` split multibyte sequences and awk aborted under UTF-8.
clip() {
  printf '%s' "$2" | awk -v max="$1" '
    { out = ""
      for (i = 1; i <= NF; i++) {
        cand = (out == "" ? $i : out " " $i)
        if (length(cand) > max) { out = out "…"; break }
        out = cand
      }
      # A single word over the budget is printed whole: over-wide beats a bare ellipsis, and it still cannot split a character.
      if (out == "…" || out == "") out = $1
      print out }'
}

# The purpose, plus the NOT FOR clause that disambiguates confusable siblings. USE WHEN is stripped here
# (not NOT FOR, which was once lost with it) because a reader already inside the book does not need triggers.
purpose() {
  printf '%s' "$1" | sed -e 's/[[:space:]]*USE WHEN.*//' -e 's/[[:space:]]*NOT FOR.*//'
}
# The triggers ARE what a reader arrives with: the tables strip them, so a subject-vocabulary `grep` over the book
# returned nothing. The path goes on the SAME LINE as the triggers because grep returns one line.
triggers() {
  printf '%s' "$1" | sed -n 's/.*USE WHEN[[:space:]]*\(.*\)/\1/p' | sed 's/[[:space:]]*NOT FOR.*//'
}
notfor() {
  printf '%s' "$1" | sed -n 's/.*\(NOT FOR.*\)/\1/p'
}

describe() {
  d_raw=$(field "$1" description)
  case "$d_raw" in
    '')   printf '**⚠ no description in frontmatter** — the skill is unusable from a listing'; return 0 ;;
    '>'*|'|'*) printf '**⚠ description is a folded YAML block** — rewrite it as a single scalar'; return 0 ;;
  esac
  d_p=$(clip 105 "$(purpose "$d_raw")")
  d_n=$(notfor "$d_raw")
  if [ -n "$d_n" ]; then
    printf '%s<br>_%s_' "$(cell "$d_p")" "$(cell "$(clip 95 "$d_n")")"
  else
    printf '%s' "$(cell "$d_p")"
  fi
}

# sib_path <repo-id> [<file>] — a sibling repo's path via the registry (harbor#966), `~`-shortened,
# or nothing when a registry exists on this box and lacks it.
sib_path() {
  __sp="$(sh "$ROOT/bin/scope-roots.sh" --repo "$1" 2>/dev/null)" && [ -n "$__sp" ] || return 1
  case "$__sp" in "$HOME"/*) __sp="~${__sp#"$HOME"}" ;; esac
  printf '%s/%s' "$__sp" "${2:-}"
}
# sib_cell <repo-id> <file> <suffix> — the contract cell, or a plain note when the repo is absent.
sib_cell() {
  if __sc="$(sib_path "$1" "$2")"; then printf '`%s`%s' "$__sc" "$3"
  else printf '_repo `%s` not registered on this box_' "$1"; fi
}

# A tool with no contract is listed AS A GAP, not omitted (an absent row reads as "no such tool"). A sibling's
# tool is the private layer's cli-contracts.tsv (harbor#1273), read first; core names harbor's own.
contract_for() {
  __cr="$(awk -F'\t' -v t="$1" '$1 == t { print $2 "\t" $3 "\t" $4; exit }' "$WORK/clis")"
  if [ -n "$__cr" ]; then
    __crepo="${__cr%%"$TAB"*}"; __cr="${__cr#*"$TAB"}"; __cfile="${__cr%%"$TAB"*}"; __cnote="${__cr#*"$TAB"}"
    [ "$__cfile" != - ] || __cfile=''
    [ "$__cnote" != - ] || __cnote=''
    if [ "$__crepo" = - ]; then printf '%s' "$__cnote"; else sib_cell "$__crepo" "$__cfile" "${__cnote:+ $__cnote}"; fi
    return 0
  fi
  # The fleet CLI's name is its roots row (contracts/roots.tsv), so a renamed fleet keeps its contract (harbor#999).
  [ -n "${HARBOR_SKILL_FLEET_CLI+x}" ] || { HARBOR_SKILL_FLEET_CLI="$(sh "$ROOT/bin/scope-roots.sh" --get HARBOR_SCOPE_FLEET_CONTROLLER_BIN 2>/dev/null || :)"; HARBOR_SKILL_FLEET_CLI="${HARBOR_SKILL_FLEET_CLI##*/}"; }
  if [ -n "$HARBOR_SKILL_FLEET_CLI" ] && [ "$1" = "$HARBOR_SKILL_FLEET_CLI" ]; then printf '`~/port/harbor/contracts/fleet-controller-json.md`'; return 0; fi
  case "$1" in
    harbor)                 printf '`~/port/harbor/contracts/cli.md`' ;;
    memory)                 printf '`~/port/harbor/contracts/memory-format.md`' ;;
    claude)                 printf '— the harness itself' ;;
    *)                      printf '**none yet**' ;;
  esac
}

# tier_of <skill> — where the skill comes from, derived. The tracked catalog lists skills/ alone, so it is all core.
tier_of() {
  if [ -d "$ROOT/skills/$1" ]; then printf core
  elif [ -d "$ROOT/vendor/skills/$1" ]; then printf vendored
  elif [ "$MODE" = install ] && awk -F'\t' -v p="skills/$1/" 'index($2, p) == 1 { f = 1 } END { exit !f }' "$IL_TARGET"/.harbor-packs/*.tsv 2>/dev/null; then printf pack
  else printf box; fi
}

# non_tool <executable name> — is it listed in contracts/catalog-non-tools.tsv (a glob, then why)? Such a name leaves the CLI table.
non_tool() {
  [ -f "$NONTOOLS" ] || return 1
  awk -F'\t' -v n="$1" '
    /^[ \t]*#/ || /^[ \t]*$/ || $1 == "glob" { next }
    { g = $1; gsub(/[.]/, "[.]", g); gsub(/[*]/, ".*", g); if (n ~ ("^" g "$")) f = 1 }
    END { exit !f }' "$NONTOOLS"
}

# list_skills — "<name> TAB <SKILL.md>" per skill, in name order. Tracked: skills/ only, so the bytes match in the dev
# checkout and in the export (vendor/skills/ is dev-layer; the installed book lists what it installs). Installed: the config dir.
list_skills() {
  if [ "$MODE" = install ]; then
    for _d in "$SKILL_DIR"/*/; do
      [ -f "$_d/SKILL.md" ] || continue
      printf '%s\t%s\n' "$(basename "$_d")" "$_d/SKILL.md"
    done
    # The book lists itself, and a first install must write the bytes a second one would: with no copy there yet, the
    # tracked file stands in (same frontmatter), or the second run finds the row the first one lacked and calls it stale.
    if [ ! -f "$SKILL_DIR/skill-catalog/SKILL.md" ] && [ -f "$ROOT/skills/skill-catalog/SKILL.md" ]; then
      printf 'skill-catalog\t%s\n' "$ROOT/skills/skill-catalog/SKILL.md"
    fi
  else
    for _d in "$ROOT"/skills/*/; do
      [ -f "$_d/SKILL.md" ] || continue
      printf '%s\t%s\n' "$(basename "$_d")" "$_d/SKILL.md"
    done
  fi | awk -F'\t' '!seen[$1]++' | sort -t "$TAB" -k1,1
}

# router_rows — the "Start here" rows as "<skill> TAB <situation>": core's, then the private layer's (install only).
# A private row for a skill core already routes replaces that row's text in place; any other is appended. A row that
# cannot be read refuses the whole read (exit 1, nothing printed): skipping it would answer "no route" for a situation
# that is only mistyped.
router_rows() {
  _rr_in="$ROUTER"
  if [ "$MODE" = install ] && [ -n "$PRIV" ] && [ -f "$PRIV/skill-book-router.tsv" ]; then _rr_in="$ROUTER $PRIV/skill-book-router.tsv"; fi
  # shellcheck disable=SC2086
  awk -F'\t' '
    function bad(m) { printf "E\t%s line %d: %s\n", FILENAME, FNR, m }
    FNR == 1 { hdr = 0; stop = 0 }
    { sub(/\r$/, "") }
    /^[ \t]*#/ || /^[ \t]*$/ { next }
    !hdr { hdr = 1; if ($0 != "skill\tsituation") { bad("the header is not skill, situation"); stop = 1 }; next }
    stop { next }
    NF != 2 { bad("expected 2 columns, got " NF); next }
    $1 !~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/ { bad("the skill is not [A-Za-z0-9][A-Za-z0-9._-]*"); next }
    $2 == "" { bad("the situation is empty"); next }
    ($1 SUBSEP FILENAME) in seen { bad("repeats the skill of line " seen[$1, FILENAME]); next }
    { seen[$1, FILENAME] = FNR
      if (!($1 in text)) order[++n] = $1
      text[$1] = $2 }
    END { for (i = 1; i <= n; i++) printf "R\t%s\t%s\n", order[i], text[order[i]] }' $_rr_in
}

# have <skill> — is it in the book being written?
have() { awk -F'\t' -v s="$1" '$1 == s { f = 1 } END { exit !f }' "$WORK/list"; }

emit() {
  cat <<'HEAD'
---
name: skill-catalog
description: "The index of every skill, `harbor` verb, agent-facing bin tool and credentialed CLI on this box, each with the path or exact command; most are hidden from your listing and this is the only route to them. USE WHEN you are about to wait on CI or a PR, run a suite, push, merge or do any scripted chore by hand, or do reasoning work by hand: design an eval or a pass^k study, run a red-team pass, chase a root cause, reason from first principles, get independent perspectives, write or optimise a prompt, extract a paper, generate options. ALSO WHEN what skills do I have, list skills, find a tool, is there a harbor command for this, how do I wait on CI, skill-book (its old name). NOT FOR invoking a skill already in your listing."
---

<!-- generated-by: sh bin/skill-catalog.sh -->

# Skill catalog

Generated by `bin/skill-catalog.sh` — **do not edit by hand**, lint rule T9
regenerates and diffs it.

**Two access paths, and the difference matters.** A skill in the model's
listing can be called with the Skill tool. A skill carrying the
model-invocation-disabled flag is removed from that listing entirely — the
model cannot invoke it and only the operator can, by typing `/<name>`. **A
session can still `Read` its SKILL.md at the path below**, which is why this
book carries paths rather than names alone.

Each row keeps the skill's own **NOT FOR** clause where it has one. That clause
is the disambiguator between confusable siblings, and for a hidden skill this
book is the only place a reader will see it.

**Tier says where a row comes from, and it is derived, never typed:** `core`
(tracked in `skills/`), `vendored` (`vendor/skills/`), `pack` (an installed
pack's manifest lists it), `box` (installed, tracked nowhere in this checkout),
`cli` (an executable on `$PATH`).

**Archived skills exist** in `vendor/skills-archive/` (not installed, not listed here; `vendor/skills-archive/PROVENANCE.md` names them and how to restore one).

HEAD
  # A defect is printed ABOVE every table: a broken skill that only shows as a row's ⚠ cell is found by reading all of them.
  if [ -s "$WORK/defects" ]; then
    printf '## DEFECTS — %s skill(s) are broken or collide; fix these first\n\n' "$(wc -l < "$WORK/defects" | tr -d ' ')"
    while IFS="$TAB" read -r _dk _dm; do printf -- '- **%s** — %s\n' "$_dk" "$(cell "$_dm")"; done < "$WORK/defects"
    printf '\n'
  fi
  printf '## Start here — which skill for which situation\n\n'
  # The worked example names two siblings, so it is printed only when both are in this book.
  printf 'Situation first, because a keyword match is what sends a reader to the wrong\nsibling.'
  if have measurement-debug && have reporting-apis; then
    printf ' `measurement-debug` and `reporting-apis` both look right for "the ad\nplatform number disagrees with analytics"; only one of them owns it.'
  fi
  printf '\n\n| The situation you are actually in | Load |\n|---|---|\n'
  printf '| I do not know what exists for this yet | you are reading it — scan the tables below |\n'
  while IFS="$TAB" read -r _tag _sk _sit; do
    [ "$_tag" = R ] && have "$_sk" || continue
    printf '| %s | `%s` |\n' "$(cell "$_sit")" "$_sk"
  done < "$WORK/router"
  cat <<'HEAD2'

**This table is generated with the rest of the file.** It lives in
`contracts/skill-book-router.tsv`, not in the output — a hand-written block here
would be destroyed by the next regeneration, which is exactly why the book was
called unusable as a router. Editing the data fixes that; editing the book does
not.

## Slice it — do not read it end to end

This file grows with the roster. Four commands answer almost every question
without loading the whole thing; `B=~/.claude/skills/skill-catalog/SKILL.md`.

```sh
grep -i 'consent' "$B"                        # which skill owns a subject
sed -n '/^## Find by trigger/,$p' "$B"        # the trigger index alone
sed -n '/^## Start here/,/^## Skills/p' "$B"  # the situation table alone
awk -F'`' '/^- `/ { print $2 }' "$B"          # every skill, verb and tool name, one per line
sed -n '/^## Commands and tools/,/^## Credentialed/p' "$B"  # the harbor verbs and bin tools alone
```

The first is the one that matters: search with the vocabulary the task arrives
with, not with a skill's name, because you do not know the name yet. The same
goes for a chore: `grep -i 'wait' "$B"` finds `harbor event ci` and `ci-wait.sh` before you write a poll loop.

HEAD2

  printf '## Skills you CANNOT see — read them by path\n\n'
  printf 'Invisible to the model and easy for the operator to forget. This\n'
  printf 'section is the only thing standing between them and being lost.\n\n'
  printf '| Skill | Tier | What it is for | Read |\n|---|---|---|---|\n'
  while IFS="$TAB" read -r n f; do
    is_hidden "$f" || continue
    printf '| `%s` | %s | %s | `%s` |\n' "$(cell "$n")" "$(tier_of "$n")" "$(describe "$f")" "$SHOWN/$n/SKILL.md"
  done < "$WORK/list"

  printf '\n## Skills already in your listing — invoke them\n\n'
  printf 'Listed for the operator, who does not get the model'"'"'s skill listing.\n\n'
  printf '| Skill | Tier | What it is for |\n|---|---|---|\n'
  while IFS="$TAB" read -r n f; do
    is_hidden "$f" && continue
    printf '| `%s` | %s | %s |\n' "$(cell "$n")" "$(tier_of "$n")" "$(describe "$f")"
  done < "$WORK/list"

  if [ "$AGENT_ON" -eq 1 ]; then
    cat <<'CMDS'

## Commands and tools — `harbor <verb>` and the `bin/` scripts agents call directly

Not skills and in no listing, so a session hand-rolls what already exists (it polled CI by hand while `harbor event ci` waits on
the event bus). Rows are generated from `contracts/agent-tools.tsv`; the verbs are bin/harbor's table, the tools are the scripts
`contracts/cli.md` marks Agent-facing, and a verb or marked tool with no row is a DEFECT above. `bin/` paths are the harbor
checkout (`~/port/harbor`) or your worktree of it.

CMDS
    printf '### `harbor` verbs\n\n| Verb | Use when | Run |\n|---|---|---|\n'
    awk -F'\t' '$1 == "verb" { gsub(/\|/, "\\|"); printf "| `harbor %s` | %s | `%s` |\n", $2, $3, $4 }' "$WORK/agent"
    printf '\n### `bin/` tools\n\n| Tool | Use when | Run |\n|---|---|---|\n'
    awk -F'\t' '$1 == "tool" { gsub(/\|/, "\\|"); printf "| `%s` | %s | `%s` |\n", $2, $3, $4 }' "$WORK/agent"
  fi

  cat <<'TOOLS'

## Credentialed CLIs — not skills, and in no listing at all

Binaries on `$PATH`. Nothing announces them to a session, so this table is
their only discovery route. **Read the contract before the source**: each is
written to be the verb surface, the auth story and the traps on one page.

**Enumerated from `~/.local/bin`, not typed here.** The hand-written version of
this table named seven tools of thirteen and pointed at one that no longer
resolves — drift in the half of a generated document that was not generated.

TOOLS

  if [ "$MODE" = tracked ]; then
    printf '_The tracked book lists none: `~/.local/bin` is the box'"'"'s, not the repo'"'"'s. `sh bin/skill-catalog.sh install` writes the table into the installed book._\n'
  else
    printf '| Tool | Tier | Contract to read first | State |\n|---|---|---|---|\n'
    : > "$WORK/skipped"
    if [ -d "$LOCAL_BIN" ]; then
      for t in "$LOCAL_BIN"/*; do
        [ -e "$t" ] || [ -L "$t" ] || continue
        [ -d "$t" ] && continue  # a directory is not a CLI: __pycache__ got a row (harbor#646)
        tn=$(basename "$t")
        if non_tool "$tn"; then printf '%s\n' "$tn" >> "$WORK/skipped"; continue; fi
        if [ -L "$t" ] && [ ! -e "$t" ]; then
          state='**⚠ BROKEN** — symlink target is missing'
        elif [ -x "$t" ]; then
          state='ok'
        else
          state='**⚠ not executable**'
        fi
        printf '| `%s` | cli | %s | %s |\n' "$(cell "$tn")" "$(contract_for "$tn")" "$state"
      done
    fi
    if [ -s "$WORK/skipped" ]; then
      printf '\n_Not tools, so not rows (contracts/catalog-non-tools.tsv): %s._\n' "$(sed 's/.*/`&`/' "$WORK/skipped" | paste -sd, - | sed 's/,/, /g')"
    fi
  fi

  printf '\n## Find by trigger — grep this section, not the tables\n\n'
  printf 'One line per skill, carrying the words a task actually arrives with and\n'
  printf 'the path on the SAME line, because grep returns a line and a hit that\n'
  printf 'does not carry the path sends you back to the top.\n\n'
  while IFS="$TAB" read -r n f; do
    _t="$(triggers "$(field "$f" description)")"
    [ -n "$_t" ] || _t="(no USE WHEN clause — this skill cannot be found by subject)"
    printf -- '- `%s` — `%s` — %s\n' "$n" "$SHOWN/$n/SKILL.md" "$_t"
  done < "$WORK/list"
  if [ "$AGENT_ON" -eq 1 ]; then
    awk -F'\t' '{ nm = ($1 == "verb") ? "harbor " $2 : $2
      printf "- `%s` — %s — `%s`\n", nm, $3, $4 }' "$WORK/agent"
  fi
  cat <<'FOOT'

**None of them has a delete verb, and that is a decision** — nothing they touch
is recoverable from a session.
FOOT
}

# The inputs, once: the skills to list, the private CLI contracts (install only) and the router rows to print.
list_skills > "$WORK/list"
: > "$WORK/clis"
if [ "$MODE" = install ] && [ -n "$PRIV" ] && [ -f "$PRIV/cli-contracts.tsv" ]; then
  # tool TAB repo TAB file TAB note, `-` for none; a row that cannot be read refuses the book, as a router row does.
  if ! awk -F'\t' -v f="$PRIV/cli-contracts.tsv" '
      { sub(/\r$/, "") } /^[ \t]*#/ || /^[ \t]*$/ { next }
      !hdr { hdr = 1; if ($0 != "tool\trepo\tfile\tnote") { printf "%s line %d: the header is not tool, repo, file, note\n", f, FNR > "/dev/stderr"; bad = 1 }; next }
      NF != 4 || $1 !~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/ || $2 !~ /^([A-Za-z0-9][A-Za-z0-9._-]*|-)$/ || $3 == "" || $4 == "" || ($2 == "-" && $4 == "-") {
        printf "%s line %d: expected tool, repo (or -), file (or -), note (or -)\n", f, FNR > "/dev/stderr"; bad = 1; next }
      { print } END { exit bad }' "$PRIV/cli-contracts.tsv" > "$WORK/clis" 2> "$WORK/clis.err"; then
    while IFS= read -r _e; do log_fail "$_e"; done < "$WORK/clis.err"
    log_fix "fix the row it names in the private layer's cli-contracts.tsv (contracts/private-layer.md)"
    log_end || :; exit "$RC_BROKEN"
  fi
fi

# THE SILENT FAILURES, MADE LOUD (harbor#158). A skill with no usable frontmatter used to render a blank or
# misleading cell ("this skill does nothing") and two skills with one directory name collapsed into one row (`awk !seen`
# in list_skills, and the installer takes skills/ before vendor/skills/ without saying so). Now each is a line of
# "$WORK/defects": printed in a DEFECTS section above the tables, and in the tracked book a failure (see below).
#   malformed  no frontmatter, no single-scalar description, no name, or a name that is not the directory's
#   collision  one directory name in skills/ AND vendor/skills/, two names differing only by case (one directory
#              on a case-insensitive disk), or two directories declaring the same `name:`
: > "$WORK/defects"
defect() { printf '%s\t%s\n' "$1" "$2" >> "$WORK/defects"; }
: > "$WORK/dirs"
scan_dir() { # <dir> <label>
  for _d in "$1"/*/; do
    [ -f "$_d/SKILL.md" ] || continue
    printf '%s\t%s\t%s\t%s\n' "$2" "$(basename "$_d")" "$(field "$_d/SKILL.md" name)" "$_d/SKILL.md" >> "$WORK/dirs"
  done
}
if [ "$MODE" = install ]; then scan_dir "$SKILL_DIR" "$SHOWN"; else scan_dir "$ROOT/skills" skills; scan_dir "$ROOT/vendor/skills" vendor/skills; fi
while IFS="$TAB" read -r _n _f; do
  _w="skills/$_n"
  [ "$(head -n 1 "$_f")" = '---' ] || { defect malformed "$_w/SKILL.md has no YAML frontmatter, so it has no description, name or flags"; continue; }
  case "$(field "$_f" description)" in
    '') defect malformed "$_w has no single-line description in its frontmatter (missing, or a folded or literal block)" ;;
  esac
  _fn="$(field "$_f" name)"
  if [ -z "$_fn" ]; then defect malformed "$_w has no name: in its frontmatter"
  elif [ "$_fn" != "$_n" ]; then defect malformed "$_w declares name: $_fn, which is not its directory's name"; fi
done < "$WORK/list"
awk -F'\t' '
  { low = tolower($2); key[NR] = low; where[low] = where[low] (where[low] == "" ? "" : ", ") $1 "/" $2
    cnt[low]++
    if ($3 != "") { nc[$3]++; nw[$3] = nw[$3] (nw[$3] == "" ? "" : ", ") $1 "/" $2 } }
  END { for (k in cnt) if (cnt[k] > 1) printf "collision\tthe directory name %s is taken more than once: %s\n", k, where[k]
        for (k in nc) if (nc[k] > 1) printf "collision\ttwo directories declare name: %s: %s\n", k, nw[k] }' "$WORK/dirs" | sort >> "$WORK/defects"

# THE COMMANDS AND TOOLS (harbor#1010). Rows come from contracts/agent-tools.tsv; what MUST have a row is derived, not typed: every
# verb of bin/harbor's table and every script contracts/cli.md marks `**Agent-facing.**`. A hole is a defect line (kind uncovered or
# dangling), so it is loud in the book and fails the write, and `--coverage` reports only these. No tsv, no section.
: > "$WORK/agent"
AGENT_ON=0
if [ -f "$AGENTTOOLS" ]; then
  AGENT_ON=1
  _cli="$ROOT/contracts/cli.md"; _disp="$ROOT/bin/harbor"
  : > "$WORK/verbs"; : > "$WORK/marked"
  [ ! -f "$_disp" ] || awk -F'\t' '/^VERBS="/{f=1;next} /^"$/{f=0} f && NF >= 4 { print $1 }' "$_disp" > "$WORK/verbs"
  [ ! -f "$_cli" ] || sed -n 's/^| `\([A-Za-z0-9._-][A-Za-z0-9._-]*\)` | \*\*Agent-facing\.\*\*.*/\1/p' "$_cli" > "$WORK/marked"
  awk -F'\t' -v f="$AGENTTOOLS" -v bin="$ROOT/bin" -v vf="$WORK/verbs" -v mf="$WORK/marked" -v good="$WORK/agent" -v hasverbs="$([ -s "$WORK/verbs" ] && echo 1 || echo 0)" -v hascli="$([ -f "$_cli" ] && echo 1 || echo 0)" '
    function bad(k, m) { printf "%s\t%s\n", k, m > "/dev/stderr"; nbad++ }
    FILENAME == vf { verbs[$1] = 1; next }
    FILENAME == mf { marked[$1] = 1; next }
    { sub(/\r$/, "") }
    /^[ \t]*#/ || /^[ \t]*$/ { next }
    !hdr { hdr = 1; if ($0 != "kind\tname\tuse_when\tinvocation") { bad("malformed", f " line " FNR ": the header is not kind, name, use_when, invocation"); stop = 1 }; next }
    stop { next }
    NF != 4 || $2 == "" || $3 == "" || $4 == "" { bad("malformed", "contracts/agent-tools.tsv line " FNR ": expected kind, name, use_when, invocation (4 non-empty columns)"); next }
    ($1 SUBSEP $2) in seen { bad("malformed", "contracts/agent-tools.tsv line " FNR ": " $1 " " $2 " repeats line " seen[$1, $2]); next }
    $1 != "verb" && $1 != "tool" { bad("malformed", "contracts/agent-tools.tsv line " FNR ": kind " $1 " is not verb or tool"); next }
    { seen[$1, $2] = FNR; k = $1; n = $2
      if (k == "verb") { split(n, a, " "); v = a[1]; rows_verb[v] = 1
        if (n == v) top[v] = 1
        if (hasverbs && !(v in verbs)) { bad("dangling", "contracts/agent-tools.tsv row `harbor " n "`: " v " is not a verb of bin/harbor"); next }
        if (index($4, "harbor " n) == 0) { bad("dangling", "contracts/agent-tools.tsv row `harbor " n "`: its invocation does not run `harbor " n "`"); next } }
      else { rows_tool[n] = 1
        if (system("test -f \"" bin "/" n "\"") != 0) { bad("dangling", "contracts/agent-tools.tsv row `" n "`: bin/" n " does not exist"); next }
        b = n; sub(/\.sh$/, "", b)
        if (index($4, b) == 0) { bad("dangling", "contracts/agent-tools.tsv row `" n "`: its invocation does not run " b); next }
        if (hascli && !(n in marked)) { bad("dangling", "contracts/agent-tools.tsv row `" n "`: contracts/cli.md does not mark it Agent-facing"); next } }
      print > good }
    END { for (v in verbs) if (!(v in top)) bad("uncovered", "the harbor verb `" v "` has no row in contracts/agent-tools.tsv")
          for (m in marked) { if (!(m in rows_tool)) bad("uncovered", "`" m "` is marked Agent-facing in contracts/cli.md and has no row in contracts/agent-tools.tsv")
            if (system("test -f \"" bin "/" m "\"") != 0) bad("dangling", "contracts/cli.md marks `" m "` Agent-facing, and bin/" m " does not exist") } }' \
    "$WORK/verbs" "$WORK/marked" "$AGENTTOOLS" 2> "$WORK/agent.err" || :
  sort -u "$WORK/agent.err" >> "$WORK/defects"
fi
if [ "$COVERAGE" -eq 1 ]; then
  [ "$AGENT_ON" -eq 1 ] || { log_fail "no contracts/agent-tools.tsv: nothing to judge"; log_nofix "the header of bin/skill-catalog.sh"; log_end || :; exit 3; }
  _nc=0
  while IFS="$TAB" read -r _dk _dm; do
    case "$_dk" in uncovered|dangling|malformed) ;; *) continue ;; esac
    _nc=$((_nc + 1)); log_fail "$_dk: $_dm"
    log_fix "add or correct the row in contracts/agent-tools.tsv (USE WHEN and exact invocation), then: sh bin/skill-catalog.sh"
  done < "$WORK/defects"
  [ "$_nc" -eq 0 ] || { log_end || :; exit 1; }
  log_ok "every harbor verb and every Agent-facing tool has a row, and every row has a verb or script behind it ($(wc -l < "$WORK/agent" | tr -d ' ') rows)"
  log_end; exit $?
fi

router_rows > "$WORK/router"
if grep -q '^E' "$WORK/router"; then
  awk -F'\t' '$1 == "E" { print $2 }' "$WORK/router" > "$WORK/router.err"
  while IFS= read -r _e; do log_fail "$_e"; done < "$WORK/router.err"
  log_fix "fix the row it names: contracts/skill-book-router.tsv, or the private layer's skill-book-router.tsv (contracts/private-layer.md)"
  log_end || :; exit "$RC_BROKEN"
fi
emit > "$WORK/book"
_ndef=$(wc -l < "$WORK/defects" | tr -d ' ')
# The installed book is written with its DEFECTS section and only warns: a box with a broken skill must still deploy. The
# tracked book is a pure function of the repo, so a defect there fails (3 under --check, where 1 already means STALE).
defects_fail() {
  while IFS="$TAB" read -r _dk _dm; do
    log_fail "$_dk: $_dm"
    log_fix "fix the skill it names (its frontmatter, or the duplicate directory); the DEFECTS section of the book lists every one"
  done < "$WORK/defects"
}
defects_warn() { while IFS="$TAB" read -r _dk _dm; do log_warn "$_dk: $_dm"; done < "$WORK/defects"; }

# ── THE TRACKED BOOK ────────────────────────────────────────────────────────
if [ "$MODE" = tracked ]; then
  if [ "$_ndef" -gt 0 ] && [ "$CHECK" = "1" ]; then
    defects_fail
    log_end || :; exit "$RC_BROKEN"
  fi
  if [ "$CHECK" = "1" ]; then
    if cmp -s "$WORK/book" "$OUT"; then
      log_ok "current — ${OUT#"$ROOT/"} matches the skills this checkout tracks"; log_end; exit $?
    else
      # A truncated diff must say it is truncated: `head -40` alone hid every row past the fortieth and a check came back
      # "absent" for rows that were there. The cap stays; the suppressed count is stated.
      diff "$OUT" "$WORK/book" > "$WORK/diff" 2>/dev/null || true
      head -40 "$WORK/diff" >&2
      _sb_n=$(wc -l < "$WORK/diff" | tr -d ' ')
      if [ "${_sb_n:-0}" -gt 40 ]; then
        # Name a command that still works after this exits: the temp copy is deleted. The book is tracked, so regenerate and let git show it.
        log_note "$((_sb_n - 40)) more diff line(s) suppressed; for the whole change: sh bin/skill-catalog.sh && git diff -- ${OUT#"$ROOT/"}"
      fi
      log_fail "STALE — ${OUT#"$ROOT/"} differs from what the skills this checkout tracks generate"
      log_fix "sh bin/skill-catalog.sh"
      log_end; exit 1
    fi
  else
    mkdir -p "$(dirname "$OUT")"
    cp "$WORK/book" "$OUT"
    log_ok "wrote ${OUT#"$ROOT"/}"
    if [ "$_ndef" -gt 0 ]; then
      defects_fail
      log_end || :; exit 1
    fi
    log_end; exit $?
  fi
fi

# ── THE INSTALLED BOOK ──────────────────────────────────────────────────────
[ "$_ndef" -eq 0 ] || defects_warn
DEST="$SKILL_DIR/skill-catalog/SKILL.md"
if [ -f "$DEST" ] && cmp -s "$WORK/book" "$DEST"; then _cur=1; else _cur=0; fi
if [ "$CHECK" = "1" ]; then
  if [ "$_cur" = 1 ]; then log_ok "current — $DEST lists the $(wc -l < "$WORK/list" | tr -d ' ') skill(s) installed in $SKILL_DIR"; log_end; exit $?; fi
  [ ! -f "$DEST" ] || { diff "$DEST" "$WORK/book" 2>/dev/null | head -20 >&2 || :; }
  log_fail "STALE — $DEST differs from what the skills installed in $SKILL_DIR generate"
  log_fix "sh $IL_SELF install --apply $(il_spell)"
  log_end; exit 1
fi
il_source "$ROOT"
if [ "$IL_APPLY" -eq 0 ]; then
  if [ "$_cur" = 1 ]; then log_ok "installed book: current"; else log_note "installed book: would update (drifted) — $DEST"; fi
  il_apply_next skills --all
  log_end; exit $?
fi
if [ "$_cur" = 0 ]; then
  il_backup "$DEST" || { log_end || :; exit 1; }
  mkdir -p "$SKILL_DIR/skill-catalog"
  # A temp beside the destination keeps its mode, and mv replaces it whole: a reader never sees half a book.
  _tmp="$DEST.tmp.$$"
  if [ -f "$DEST" ]; then cp -p "$DEST" "$_tmp"; else : > "$_tmp"; fi
  if ! cat "$WORK/book" > "$_tmp" || ! mv -f "$_tmp" "$DEST" || ! cmp -s "$WORK/book" "$DEST"; then
    rm -f "$_tmp"
    log_fail "could not write $DEST — the pre-run copy is in $IL_BK"
    log_nofix "the error above"
    log_end || :; exit 1
  fi
  log_ok "installed book: written, verified — $DEST lists the $(wc -l < "$WORK/list" | tr -d ' ') skill(s) installed in $SKILL_DIR"
else
  log_ok "installed book: current"
fi
il_manifest_drop skills/skill-catalog; il_manifest skills/skill-catalog
il_manifest_write || { log_end || :; exit 1; }
log_end; exit $?
