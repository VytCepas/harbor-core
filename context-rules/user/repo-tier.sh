#!/usr/bin/env sh
# repo-tier.sh (harbor#173 · A7) — say so when the session is standing in a tree
# whose rules are not loaded.
#
# THE LOSS THIS REPORTS IS SILENT AND WAS MEASURED ON THIS BOX. injection-rule.sh
# scopes repo packs to the session's PROJECT directory (CLAUDE_PROJECT_DIR, else
# the hook's cwd). A session launched at $HOME and then worked in a worktree has
# a project directory of $HOME and a working directory of the worktree, so the
# repo tier is $HOME's (`$HOME/.claude/context-rules/user` is the BOX pack dir, or the old
# `$HOME/.claude/inject.d` until it moves; `tree_dirs()` drops it as a duplicate), and the tree the session is actually editing governs
# nothing. Measured 2026-08-29 in the session auditing this very question: three
# harbor packs — including the whole merge-governance chain — were not loaded,
# and NOTHING said so. The engine detects the collision and is silent about it,
# which is the same shape as a detector nobody consults.
#
# WHY A PACK AND NOT AN ENGINE CHANGE. The engine's job is to load packs; a
# note about which packs did not load is a note, and notes are data here. This
# also buys the pack the notes suite for free — tests/context/injection-rule/notes.test.sh fails
# unless every tracked id has both a FIRE and a SILENT row.
#
# THE PAYLOAD IS THE ONLY SOURCE FOR "WHERE THE SESSION IS STANDING". The
# harness sends `.cwd` on every event; the engine deliberately does not use it
# for scoping (that would make the governed tree move mid-session). Reading it
# HERE, for a report and never for scoping, keeps that property.
#
# INFORM, NEVER RELOAD. This does not load the missing packs and must not. Which
# tree governs a session is the operator's decision, and a note that quietly
# widened it would be a second, softer scoping rule in a file any box can edit.
set -eu

PAYLOAD="$(cat)"
[ -n "$PAYLOAD" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

CWD="$(printf '%s' "$PAYLOAD" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$CWD" ] || exit 0
[ -d "$CWD" ] || exit 0

# PHYSICAL PATHS ON BOTH SIDES, for the reason project-pointer.sh records: /tmp
# is a symlink to /private/tmp on macOS, so two spellings of one directory
# compare unequal and this would fire on a tree it is already governing.
_phys() { CDPATH='' cd -P -- "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }

# The engine runs `run:` scripts with `cd "$REPO"`, so pwd IS the governed tree.
# Reading it from the environment instead would duplicate the engine's own
# resolution, and a copy of a rule drifts from it.
GOVERNED="$(_phys "$(pwd)")"

# ~ and never an absolute home path (CONSTITUTION §3), same as every other pack.
_rel() { case "$1" in "$HOME") printf '~' ;; "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;; *) printf '%s' "$1" ;; esac; }

# NAME THE RULES, NOT JUST THE DIRECTORY. "some rules are not loaded" is a
# sentence a reader cannot act on; the ids are what tells them whether the loss
# matters for what they are about to do.
#
# AND SAY WHICH ONES CROSSED (harbor#599). A pack that declares `scope: box` is
# delivered by the engine when this call reaches its tree and that tree is
# registered — the engine says which trees those were in HARBOR_CONTEXT_REACHED. Such a
# pack is not lost, so it is named as delivered, and a tree whose every rule
# crossed has lost nothing and is not reported at all.
# Returns 1 when nothing in <tree> is withheld.
_rules() { # <tree>
  sent=''; kept=''; nk=0
  _crossed=0
  case "
${HARBOR_CONTEXT_REACHED:-${HARBOR_REACHED:-}}" in *"
$1
"*) _crossed=1 ;; esac
  # Both layouts for one release, new first, an id once (harbor#1010); the id is derived when id: is absent.
  _ids=' '
  for f in "$1"/context-rules/*/*.md "$1"/.claude/inject.d/*.md; do
    [ -f "$f" ] || continue
    case "$f" in "$1"/context-rules/user/*) continue ;; esac
    i="$(awk '/^---[[:space:]]*$/{n++; next} n==1 && /^id:/{sub(/^id:[[:space:]]*/,""); print; exit}' "$f")"
    [ -n "$i" ] || { i="${f##*/}"; i="${i%.md}"; }
    case "$_ids" in *" $i "*) continue ;; esac
    _ids="$_ids$i "
    s="$(awk '/^---[[:space:]]*$/{n++; next} n==1 && /^scope:/{sub(/^scope:[[:space:]]*/,""); print; exit}' "$f")"
    if [ "$_crossed" = 1 ] && [ "$s" = box ]; then
      sent="$sent $i"
    else
      kept="$kept $i"; nk=$(( nk + 1 ))
    fi
  done
  [ "$nk" -gt 0 ]
}

_say() { # <how the session reached the tree>
  _also=''
  [ -z "$sent" ] || _also=" (delivered anyway, because they declare scope: box:$sent)"
  printf 'REPO RULES NOT LOADED. %s, but the injector scopes repo packs to its PROJECT directory (%s) — a different tree. That tree carries %d rule(s) which therefore do NOT govern this session:%s%s. Treat them as unenforced here, or start the session inside that tree.\n' \
    "$1" "$(_rel "$GOVERNED")" "$nk" "$kept" "$_also"
}

STANDING="$(cd "$CWD" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$STANDING" ]; then
  STANDING="$(_phys "$STANDING")"
  [ "$STANDING" != "$GOVERNED" ] || exit 0
  _rules "$STANDING" || exit 0
  _say "This session is standing in $(_rel "$STANDING")"
  exit 0
fi

# ── STANDING IN NO TREE (harbor#601) ────────────────────────────────────────
# This used to be an `exit 0`: no repo, nothing to report. It was inverted in
# effect. A session standing outside every repository is the one where the most
# rules are unloaded, and it was 272 of 284 real sessions when measured
# 2026-09-21 — launched at $HOME then, at PORT_ROOT now, neither of them a repo.
#
# WHY NOT LIST EVERY TREE BELOW CWD. That note would fire in nearly every
# session, name nine repositories, and be skipped by the second day: a §2.11
# false positive that trains the reader to ignore the true one. It reports the
# tree THIS CALL reaches into, and only when that tree carries rules.
#
# WHICH TREE A CALL REACHES INTO IS THE ENGINE'S ANSWER, NOT THIS FILE'S. The
# definition is written once in contracts/injection-rule.md ("The tree a call touches")
# and computed once, in hooks/injection-rule/injection-rule.sh, which hands it to every `run:` pack
# as HARBOR_CONTEXT_TOUCHED: one physical tree per line. This pack computed it itself
# for one PR (#601); `scope: box` delivery (#599) became the second reader, and
# two readers of one definition is the point at which a copy starts drifting.
# Run by hand, with no engine above it, the variable is empty and the pack is
# silent here, which is the fail-open direction every pack takes.
[ -n "${HARBOR_CONTEXT_TOUCHED:-${HARBOR_TOUCHED:-}}" ] || exit 0
while IFS= read -r _t; do
  [ -n "$_t" ] || continue
  [ "$_t" != "$GOVERNED" ] || continue
  _rules "$_t" || continue
  _say "This call reaches into $(_rel "$_t") from $(_rel "$(_phys "$CWD")"), which is inside no repository"
  exit 0
done <<EOF
${HARBOR_CONTEXT_TOUCHED:-${HARBOR_TOUCHED:-}}
EOF
