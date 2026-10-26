#!/usr/bin/env sh
# skill-catalog.sh — generate the skill catalog, the index that makes invoked-only skills findable (harbor#155, harbor#1149, harbor#1010).
#   Renamed from skill-book.sh (harbor#1010): bin/skill-book.sh stays for one release as an alias that runs this file and says so on stderr.
#   EVERY ROW CARRIES A TIER, derived from where the skill lives and never typed: core (skills/), vendored (vendor/skills/),
#   pack (an installed pack's manifest in <config dir>/.harbor-packs lists it), box (installed, and nothing here tracks it); a
#   tool in ~/.local/bin is tier cli. An executable that is no tool (CONTRACTS/catalog-non-tools.tsv) is not a row.
#   sh bin/skill-catalog.sh [--check]    the TRACKED book, skills/skill-catalog/SKILL.md: only the skills the export ships (skills/; vendor/skills/ is dev-layer); --check diffs instead of writing (lint T9)
#   sh bin/skill-catalog.sh install [--check] [--apply] (--live | --dir PATH)
#   sh bin/skill-catalog.sh install --manifest (--live | --dir PATH)
#                                     the MANIFEST DRIFT CHECK (harbor#1010): exit 1 when an installed skill has no row in <config dir>/.harbor-manifest or a pack's
#                                     manifest in .harbor-packs, or a manifest row names a skill dir that is gone; 3 when there is no manifest to judge by
#                                     the INSTALLED book, <config dir>/skills/skill-catalog/SKILL.md: every skill installed there, the box's and the packs' included, and the CLIs in ~/.local/bin; a dry run unless --apply; --check exits 1 when it is not current
#
# TWO BOOKS BECAUSE THERE ARE TWO QUESTIONS (harbor#1149). The tracked book answers "what does THIS repo ship", and it is
# the same bytes on every machine: it reads nothing outside the checkout (not the config dir, not ~/.local/bin, not the
# private layer), so `--check` is a pure function of the tree and can fail CI. The installed book answers "what can a
# session on THIS box reach", which is the tracked skills plus whatever a pack, the private layer or the operator put in
# the config dir. It used to be the only book, written INTO the tracked file from the live box, so every client skill
# and the operator's address on the box landed in git and in the public export. deploy.sh runs `install --apply --live`
# after the packs, so the installed book lists every installed skill; the tracked file is no longer rewritten by a deploy.
#
# WHY THIS IS GENERATED AND NOT WRITTEN. An index of this many skills maintained
# by hand drifts the moment one is added, renamed or hidden, and an index that
# lies is worse than no index because it is trusted. Same reasoning that makes
# STATUS.md generated and lint rules T1/T2 forbid a hand-typed count — including
# in this comment, which said "33 skills" while the box had 36.
#
# `--check` diffs instead of writing, so a lint rule can flag a stale book. T9 is advisory, so nothing fails
# CI on a stale book yet (this header once claimed the opposite, until an adversarial pass pointed out that
# nothing anywhere fails on one); the tracked book is deterministic now, so a rule could.
#
# `--check` HAS THREE ANSWERS, NOT TWO (harbor#1149): 0 current, 1 STALE (regenerate it), 3 the generator could not say (a
# router row it cannot read, no skills dir to scan). A bad row once exited 1 like a stale book, so T9 and X8 called a
# malformed router file STALE and sent the reader to a regenerate that fails with the real error. Every other mode keeps the
# install standard's 1 for a refusal (so does the target gate refusing a --dir that names the live dir), and 2 is usage.
#
# WHAT PROBLEM IT SOLVES. `disable-model-invocation: true` removes a skill from
# the model's listing ENTIRELY — most skills on this box carry it — so they are
# invisible to a session and effectively invisible to the operator, who has to
# remember they exist. Listing them costs one `description` line, because the
# book is itself a skill: its body loads only when opened.
#
# AND WHY IT CARRIES PATHS, NOT JUST NAMES. A hidden skill cannot be invoked by
# the model at all. But a SKILL.md is a markdown file, so a path makes it
# readable even when it is unreachable — which is the whole trick.
#
# THE TRIGGERS ARE TASK-SHAPED, NOT META-SHAPED (harbor#173 · A5), and this file
# shipped the opposite first. Every trigger in the description below used to ask
# ABOUT skills — "what skills do I have", "list skills", "I forgot the name of
# that skill" — so the book surfaced when the operator wanted an inventory and
# never when a session was doing the work a hidden skill covers. The evidence is
# this repo's own: the session that ran a pass^k reliability study by hand had an
# `Evals` skill on the box whose triggers include `pass@k`, and it never
# surfaced. That is 11,639 B of trigger vocabulary reachable only by asking the
# one question nobody asks mid-task. The meta triggers are kept — they were not
# wrong, only insufficient.
#
# THE "START HERE" TABLE IS DATA (harbor#1149): CONTRACTS/skill-book-router.tsv, one row per situation, and a row is
# printed only when its skill is in the book being written, so the tracked book never routes to a skill the repo does
# not ship. On the box, <private layer>/skill-book-router.tsv (CONTRACTS/private-layer.md) replaces the text of a row in
# place, or appends a row for a skill core does not route. Only `install` reads it.
set -eu

# --help BEFORE ANY WORK (S4, harbor#140). Placed immediately after strict mode
# so it is the first executable line: a --help that reaches an argument parser is
# a --help that a script with no parser ignores, and this file had none. Measured
# 2026-08-20: a sweep of `bin/*.sh --help` ran past five minutes because at least
# one script treated the flag as a request to do work, and five of the scripts
# with no --help at all are mutators. The text is the header, read out of THIS
# file at runtime, so a help message cannot drift from what the script says it is.
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
# Glob order is LC_COLLATE-dependent: under en_US.UTF-8 the list case-folds and
# interleaves, under C it does not. Two boxes then generate two different books
# from identical input and --check flaps forever, which is how a guard gets
# switched off. Pin the collation rather than trusting the caller's environment.
LC_ALL=C
export LC_ALL

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
. "$ROOT/bin/log-lib.sh"; log_init skill-catalog
. "$ROOT/bin/install-lib.sh"
TAB='	'
LOCAL_BIN="${HARBOR_LOCAL_BIN:-$HOME/.local/bin}"
OUT="$ROOT/skills/skill-catalog/SKILL.md"
ROUTER="$ROOT/CONTRACTS/skill-book-router.tsv"
NONTOOLS="$ROOT/CONTRACTS/catalog-non-tools.tsv"

# An unrecognised argument must NOT fall through to the write branch. `--chekc`
# used to overwrite the very file it was asked to verify and exit 0 — the exact
# shape that makes a gate vacuous, since a typo in a hook "passes" by destroying
# the evidence.
MODE=tracked; CHECK=0; MANIFEST=0
if [ "${1:-}" = install ]; then MODE=install; shift; fi
il_opt() { case "$1" in --check) CHECK=1; IL_TAKE=1 ;; --manifest) MANIFEST=1; IL_TAKE=1 ;; *) IL_TAKE=0 ;; esac; }
if [ "$MODE" = install ]; then
  il_parse "$@"
else
  case "${1:-}" in
    --check) CHECK=1 ;;
    '') ;;
    *) printf 'usage: skill-catalog.sh [--check] | install [--check|--manifest] [--apply] (--live | --dir PATH)\n' >&2; exit 2 ;;
  esac
  [ "$#" -le 1 ] || { printf 'usage: skill-catalog.sh [--check] | install [--check] [--apply] (--live | --dir PATH)\n' >&2; exit 2; }
fi

# What a book that cannot be generated exits: 3 when --check is asking, because 1 there already means STALE.
RC_BROKEN=1; [ "$CHECK" -eq 0 ] && [ "$MANIFEST" -eq 0 ] || RC_BROKEN=3

WORK="$(mktemp -d "${TMPDIR:-/tmp}/skill-catalog.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT INT TERM

# THE TRACKED BOOK NAMES THE INSTALL PATH, NOT A PATH IT WAS GENERATED FROM. This file used to build every row's path
# from the directory it scanned, and a scan of any directory but the live one wrote a scratch path into a tracked file
# (measured 2026-09-07: `--check` reported 36 rows differing only in their path prefix, and nothing else would have
# caught it). The tracked book scans the checkout and says where an install puts the skills, so there is no path to get
# wrong; the installed book scans the config dir it is written into, and says that dir.
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
  PRIV="$(sh "$ROOT/bin/roots.sh" --private 2>/dev/null || :)"
  [ -d "$SKILL_DIR" ] || { log_fail "no skills dir at $SKILL_DIR"; log_nofix "the header of bin/skill-catalog.sh"; log_end || :; exit "$RC_BROKEN"; }
  if [ "$MANIFEST" -eq 1 ]; then
    # Every installed skill is owned by a recorded install: core and vendored skills by a row of the deploy's manifest, a pack's by
    # that pack's manifest. A dir with neither was put there by hand or by an installer that did not record it, and a row with no dir
    # is an install that was undone by hand: both are drift, and the second is the one nothing else reports.
    IM="$IL_TARGET/.harbor-manifest"
    [ -f "$IM" ] || { log_fail "no $IM: no install has been recorded here, so no skill can be judged"; log_fix "sh bin/deploy.sh --apply --only skills $(il_spell)"; log_end || :; exit 3; }
    : > "$WORK/orphans"; _mn=0
    for _d in "$SKILL_DIR"/*/; do
      [ -f "$_d/SKILL.md" ] || continue
      _n="$(basename "$_d")"; _mn=$((_mn + 1))
      awk -v p="skills/$_n/SKILL.md" '$3 == p { f = 1 } END { exit !f }' "$IM" && continue
      awk -F'\t' -v p="skills/$_n/" 'index($2, p) == 1 { f = 1 } END { exit !f }' "$IL_TARGET"/.harbor-packs/*.tsv 2>/dev/null && continue
      printf 'installed skill %s has no row in %s or in a pack manifest\n' "$_n" ".harbor-manifest" >> "$WORK/orphans"
    done
    awk '$3 ~ /^skills\/[^\/]+\/SKILL\.md$/ { split($3, a, "/"); print a[2] }' "$IM" | while IFS= read -r _n; do
      [ -f "$SKILL_DIR/$_n/SKILL.md" ] || printf 'the manifest row for skill %s names a skill that is not installed\n' "$_n" >> "$WORK/orphans"
    done
    if [ -s "$WORK/orphans" ]; then
      while IFS= read -r _e; do log_fail "$_e"; done < "$WORK/orphans"
      log_fix "sh bin/deploy.sh --apply --only skills $(il_spell) records it; or remove the skill dir (or the manifest row) if nothing should own it"
      log_end || :; exit 1
    fi
    log_ok "every one of the $_mn installed skill(s) has a manifest row, and every skill row names an installed skill"; log_end; exit $?
  fi
else
  # shellcheck disable=SC2088
  SHOWN='~/.claude/skills'
  PRIV=''
fi

# The frontmatter ONLY — everything between the opening `---` and the next one.
# Scanning the whole file misfiled any skill whose BODY mentioned the key at
# column 0, and this generator's own output discusses that key, so the book was
# one prose reflow away from classifying itself as hidden.
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

# Truncate on WHOLE WORDS, never a byte offset. `substr()` split multibyte
# sequences: awk aborted with a conversion failure under a UTF-8 locale (empty
# cell, status discarded by the surrounding $( )) and wrote invalid UTF-8 under
# C. Concatenating whole words cannot split a character.
clip() {
  printf '%s' "$2" | awk -v max="$1" '
    { out = ""
      for (i = 1; i <= NF; i++) {
        cand = (out == "" ? $i : out " " $i)
        if (length(cand) > max) { out = out "…"; break }
        out = cand
      }
      # A single word longer than the budget would otherwise leave the cell as
      # a bare ellipsis, which reads as "this skill has no purpose". Print the
      # word whole: over-wide beats uninformative, and it still cannot split a
      # multibyte character.
      if (out == "…" || out == "") out = $1
      print out }'
}

# The purpose, plus the NOT FOR clause that disambiguates confusable siblings.
#
# The first cut stripped everything after `USE WHEN`, which killed `NOT FOR`
# too — measured at 33 of 36 skills, 27 of which name a specific sibling. For a
# hidden skill the book is the ONLY disambiguator, so it was deleting the one
# sentence that prevents picking the wrong tool. It also truncated at the first
# full stop, which erased mail-cal's APPROVAL-GATED warning. USE WHEN triggers
# go instead: a reader already inside the book does not need them.
purpose() {
  printf '%s' "$1" | sed -e 's/[[:space:]]*USE WHEN.*//' -e 's/[[:space:]]*NOT FOR.*//'
}
# THE TRIGGERS ARE WHAT A READER ARRIVES WITH, AND THE BOOK DELETED THEM.
# `purpose()` above strips `USE WHEN` on purpose and that is still right for the
# tables: a reader already inside a row does not need the trigger phrases. But
# it meant the WHOLE book carried none of them — measured 2026-08-28, `grep -i`
# for a warehouse, `datalayer` and `red team` each returned zero over the generated
# file, while four skill trees name those subjects. Someone looking for the skill
# that owns a subject searches with the subject's own vocabulary, so an index
# with the vocabulary stripped answers every such search with silence.
# The path goes on the SAME LINE as the triggers because grep returns one line,
# and a hit that does not carry the path sends the reader back to the top.
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
  __sp="$(sh "$ROOT/bin/roots.sh" --repo "$1" 2>/dev/null)" && [ -n "$__sp" ] || return 1
  case "$__sp" in "$HOME"/*) __sp="~${__sp#"$HOME"}" ;; esac
  printf '%s/%s' "$__sp" "${2:-}"
}
# sib_cell <repo-id> <file> <suffix> — the contract cell, or a plain note when the repo is absent.
sib_cell() {
  if __sc="$(sib_path "$1" "$2")"; then printf '`%s`%s' "$__sc" "$3"
  else printf '_repo `%s` not registered on this box_' "$1"; fi
}

# contract_for <tool> — where to read before touching it. A tool with no
# contract is listed AS A GAP rather than omitted: an absent row reads as "no
# such tool", a row saying "none" reads as work.
# A sibling's tool is the private layer's cli-contracts.tsv (harbor#1273), read first; core names harbor's own.
contract_for() {
  __cr="$(awk -F'\t' -v t="$1" '$1 == t { print $2 "\t" $3 "\t" $4; exit }' "$WORK/clis")"
  if [ -n "$__cr" ]; then
    __crepo="${__cr%%"$TAB"*}"; __cr="${__cr#*"$TAB"}"; __cfile="${__cr%%"$TAB"*}"; __cnote="${__cr#*"$TAB"}"
    [ "$__cfile" != - ] || __cfile=''
    [ "$__cnote" != - ] || __cnote=''
    if [ "$__crepo" = - ]; then printf '%s' "$__cnote"; else sib_cell "$__crepo" "$__cfile" "${__cnote:+ $__cnote}"; fi
    return 0
  fi
  case "$1" in
    harbor)                 printf '`~/port/harbor/CONTRACTS/cli.md`' ;;
    memory)                 printf '`~/port/harbor/CONTRACTS/memory-format.md`' ;;
    projects-orchestrator)  printf '`~/port/harbor/CONTRACTS/orchestrator-json.md`' ;;
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

# non_tool <executable name> — is it listed in CONTRACTS/catalog-non-tools.tsv (a glob, then why)? Such a name leaves the CLI table.
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
description: "The index of every skill and credentialed CLI on this box, with the path to read each one — most are hidden from your listing and this is the only route to them. USE WHEN you are about to do reasoning work by hand: design an eval or a pass^k study, run a red-team or adversarial pass, chase a root cause, reason from first principles, get independent perspectives on a decision, write or optimise a prompt, extract the substance of a paper or a long document, generate options. ALSO WHEN what skills do I have, list skills, find a tool, which tool reads email/calendar/tickets/tags, I forgot the name of that skill, skill-book (its name before harbor#1010). NOT FOR invoking a skill already in your listing — this is for the ones you cannot see."
---

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

## Start here — which skill for which situation

HEAD
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
`CONTRACTS/skill-book-router.tsv`, not in the output — a hand-written block here
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
awk -F'`' '/^- `/ { print $2 }' "$B"          # every skill name, one per line
```

The first is the one that matters: search with the vocabulary the task arrives
with, not with a skill's name, because you do not know the name yet.

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
      printf '\n_Not tools, so not rows (CONTRACTS/catalog-non-tools.tsv): %s._\n' "$(sed 's/.*/`&`/' "$WORK/skipped" | paste -sd, - | sed 's/,/, /g')"
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
    log_fix "fix the row it names in the private layer's cli-contracts.tsv (CONTRACTS/private-layer.md)"
    log_end || :; exit "$RC_BROKEN"
  fi
fi
router_rows > "$WORK/router"
if grep -q '^E' "$WORK/router"; then
  awk -F'\t' '$1 == "E" { print $2 }' "$WORK/router" > "$WORK/router.err"
  while IFS= read -r _e; do log_fail "$_e"; done < "$WORK/router.err"
  log_fix "fix the row it names: CONTRACTS/skill-book-router.tsv, or the private layer's skill-book-router.tsv (CONTRACTS/private-layer.md)"
  log_end || :; exit "$RC_BROKEN"
fi
emit > "$WORK/book"

# ── THE TRACKED BOOK ────────────────────────────────────────────────────────
if [ "$MODE" = tracked ]; then
  if [ "$CHECK" = "1" ]; then
    if cmp -s "$WORK/book" "$OUT"; then
      log_ok "current — ${OUT#"$ROOT/"} matches the skills this checkout tracks"; log_end; exit $?
    else
      # A TRUNCATED DIFF THAT DOES NOT SAY IT IS TRUNCATED PRODUCES FALSE
      # NEGATIVES, and this one did. `head -40` alone hid every row past the
      # fortieth, so on 2026-09-07 a check of whether two newly-installed skills
      # appeared in the book came back "absent" — the rows were there, forty lines
      # further down. Four tool calls were spent on a defect that did not exist,
      # and the same shape would let a reviewer approve a book missing whatever sat
      # below the cut. The cap stays (a 200-line diff in a terminal is not read
      # either); what changes is that the suppressed count is stated, so an
      # absence found here is known to be provisional.
      diff "$OUT" "$WORK/book" > "$WORK/diff" 2>/dev/null || true
      head -40 "$WORK/diff" >&2
      _sb_n=$(wc -l < "$WORK/diff" | tr -d ' ')
      if [ "${_sb_n:-0}" -gt 40 ]; then
        # NAME A COMMAND THAT STILL WORKS AFTER THIS EXITS. The obvious line here
        # is `diff $OUT $tmp`, and the temp copy is deleted when this exits — a remedy that
        # cannot run is worse than none, because it costs the reader a round trip
        # to discover that. The book is tracked, so regenerate and let git show it.
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
    log_end; exit $?
  fi
fi

# ── THE INSTALLED BOOK ──────────────────────────────────────────────────────
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
