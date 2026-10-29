#!/usr/bin/env sh
# project-pointer.sh (harbor#173 · A6) — buy back the reach repo-scoping costs.
# Run by hooks/injection-rule/injection-rule.sh at SessionStart with cwd = the session's repo.
#
# THIS HEADER USED TO CALL IT "the ~230 bytes" AND THAT WAS A COPIED CONSTANT
# ABOUT SOMETHING ELSE. 230 B is E7's SINGLE-ENTRY pointer arm. What this script
# emits is its own fixed prose plus one row per project — measured on the shipped
# registry at 728 B for four projects, about 92 B per row after a ~450 B floor.
# The repo's own doctrine (lint T1/T2/T3) is that a number living somewhere else
# must be derived, not restated, and an adversarial pass caught this file
# breaking it. Run the script to see the real figure; the registry's own header
# is where the "keep it short" instruction belongs, and it is there.
#
# THE TRADE THIS IMPLEMENTS, MEASURED (docs/reports/evals.md E7). Skill descriptions stack
# with projects: twelve ambient skills cost 5,710 B of every session, and at ten
# projects a box-level layout costs 35,770 B in descriptions alone — 149% of the
# whole context ceiling before CLAUDE.md exists. Repo-scoping makes that slope
# flat, and it is not free: from OUTSIDE the repo a session scored 1/4 at 17.5
# turns, because it no longer knew the capability existed. A pointer of about 230
# bytes restored 4/4 at 3.0 turns. So the pointer is not a nicety on top of
# repo-scoping — it is the half that makes repo-scoping affordable.
#
# A REGISTRY, NOT A HARDCODED LIST. `projects.tsv` sits next to this file and the
# operator edits it; a new project is one line. Hardcoding the three that exist
# today would make the fourth an edit to a shell script inside an installed
# floor, which is the shape nobody performs and everybody works around.
#
# THE CURRENT REPO IS OMITTED. Its own skills are already loaded, and pack 40
# names the hidden ones. Telling a session where it already is, is the kind of
# always-true line that trains a reader to skim the whole channel.
set -eu

# harbor#813: no dirname fork. A failed or unresolvable $(dirname) left SELF_DIR at the cwd, reading ./projects.tsv from it.
case "$0" in */*) SELF_DIR="${0%/*}" ;; *) SELF_DIR=. ;; esac
REG="$SELF_DIR/projects.tsv"
[ -f "$REG" ] || exit 0

# PHYSICAL PATHS ON BOTH SIDES, and this was a real defect before the suite found
# it. `git rev-parse --show-toplevel` resolves symlinks; the registry's row for the measurement repo (resolved through the repo registry)
# does not. On any box where the home or the project sits behind a link — which
# on macOS includes every temp dir, `/tmp` being a symlink to `/private/tmp` —
# the two spellings of one directory compared unequal and the pointer told a
# session, at length, about the repo it was already standing in. Lint D2 exists
# because the identical string-vs-physical mistake let an installer past a live
# gate; it is the same bug wearing different clothes.
_phys() { CDPATH='' cd -P -- "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }
HERE="$(_phys "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"

# A LINKED WORKTREE IS THE SAME PROJECT, AND THE WORKING-TREE PATH SAYS IT IS
# NOT. This is the third spelling of one directory to fool this comparison —
# after the /tmp symlink above, and lint D2's trailing slash — and it is the one
# that had teeth, because the whole of this box's harbor work happens in
# worktrees. Measured 2026-08-28: five harbor worktrees on this box, and every
# session in the four linked ones was told "YOU ARE NOT IN A REGISTERED
# PROJECT", then handed `harbor (~/harbor)` in the list of projects it does NOT
# carry. The session governing harbor was told to go and read harbor.
#
# `--git-common-dir` IS THE IDENTITY. It resolves to the SAME `<main>/.git` from
# every worktree of a repository, which is precisely the equivalence wanted:
# `.git` (relative) in the main checkout, an absolute `<main>/.git` in a linked
# one. Empty for a non-repo directory, which stays its own identity.
_repo_root() {
  _c="$(cd "$1" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null)" || return 1
  [ -n "$_c" ] || return 1
  case "$_c" in /*) : ;; *) _c="$1/$_c" ;; esac
  _phys "$(dirname -- "$_c")"
}
HERE_ID="$(_repo_root "$(pwd)" || printf '%s' "$HERE")"

# ── WHERE THE SESSION IS STANDING, AND WHETHER IT SPANS REPOS ───────────────
# The pointer used to say only what was ELSEWHERE, never where the session was.
# That is fine inside a repo — pack 40 covers it — but a session launched at
# $HOME is inside NO project, and it is the case with the widest blast radius:
# nothing it writes is covered by a project's own gates, memory or skills, and
# a multi-repo session carries conclusions between trees that were only ever
# derived in one. Measured on 2026-08-25: a session launched at ~ spent a full
# day writing across ~/<repo>, ~/harbor and a second workload repo while the pointer named
# four projects, it not among them (it was unregistered), and said nothing
# about the session's own location. Both halves of that are fixed here.
#
# ONE ROW PER LINE, not a semicolon run-on. Nine registered projects on one line
# is a wall a reader skims; the registry is a list and it now reads as one.
out=''
n=0
here_name=''
here_main=''
while IFS='	' read -r name path covers; do
  case "$name" in ''|'#'*) continue ;; esac
  [ -n "$path" ] || continue
  # ~ is expanded here rather than in the file, so the registry stays readable
  # and carries no absolute home path (CONSTITUTION §3).
  case "$path" in '~/'*) path="$HOME/${path#'~/'}" ;; esac
  [ -d "$path" ] || continue
  # TWO WAYS TO BE THE CURRENT PROJECT: the working tree IS the registered path,
  # or both resolve to one repository. The second is guarded by requiring the
  # registered path to be its own repo root — without that, registering a
  # SUBDIRECTORY of a repo would silently claim every session anywhere in it.
  _pid="$(_repo_root "$path" 2>/dev/null || true)"
  if [ "$(_phys "$path")" = "$HERE" ] || \
     { [ -n "$_pid" ] && [ "$_pid" = "$HERE_ID" ] && [ "$_pid" = "$(_phys "$path")" ]; }
  then here_name="$name"; here_main="$_pid"; continue; fi
  out="$out
  - $name (~/${path#"$HOME"/}) — $covers"
  n=$(( n + 1 ))
done < "$REG"

[ "$n" -gt 0 ] || exit 0

# The location line. `~` and never an absolute home, same §3 reason as above.
case "$HERE" in
  "$HOME")   here_rel='~' ;;
  "$HOME"/*) here_rel="~/${HERE#"$HOME"/}" ;;
  *)         here_rel="$HERE" ;;
esac

if [ -n "$here_name" ]; then
  # NAME THE WORKTREE WHEN IT IS ONE. "YOU ARE IN: harbor (~/port/harbor)" read from a
  # linked worktree would be a second, quieter lie — the branch and the working
  # tree are not the main checkout's, and a session that assumes otherwise
  # commits to the wrong one.
  _wt=''
  [ -n "${here_main:-}" ] && [ "$here_main" != "$HERE" ] && _wt=' — a linked worktree, NOT the main checkout, so its branch and working tree are its own'
  loc="YOU ARE IN: $here_name ($here_rel)$_wt. Its own skills and memory are already loaded."
else
  loc="YOU ARE NOT IN A REGISTERED PROJECT — cwd is $here_rel. Nothing you write from here is covered by a project's gates, memory or skills. If this session touches a project, say which one in the work itself; if it touches SEVERAL, keep them separate — re-derive a conclusion in each tree rather than carrying it across, and never leave one repo's uncommitted work sitting in another's branch."
fi

# "REGISTERED", AND THE WORD IS THE FIX (harbor#181). This said "%d project(s) on
# this box", which counts the REGISTRY and reads as a count of the ESTATE. On
# 2026-08-21 the box carried ELEVEN governed repositories and the registry named
# four, so the line stated "4 projects on this box" to every session while seven
# went unmentioned — six of them carrying `.claude/skills` nobody outside could
# see. A number that is a copy of one list, presented as a fact about another, is
# T2's defect delivered into every session's prefix.
#
# The count is not hedged, because a hedge ("there may be others") is a sentence
# that never becomes false and so never gets fixed. It states what it counted;
# lint IJ3 states what is missing, and that one CAN go quiet.
printf '%s Capability outside this repo, so you do not carry it: %d REGISTERED project(s) own skills and tools that are NOT in your listing because they are scoped to their own tree.%s\nTo use one, read its .claude/skills/ or cd into it — do not rebuild what it already does, and do not conclude the capability is absent because you cannot see it.\n' \
  "$loc" "$n" "$out"
