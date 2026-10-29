#!/usr/bin/env sh
# policy-constitution-install.sh's back-port gate reads HISTORY, not HEAD (harbor#683, #685): a replaced
# committed line passes, a line in no commit refuses, and a failed history read says so.
# Each case is a throwaway checkout with a V1 -> V2 history, deploying into its own config dir.
# Then the install standard (harbor#765, #771): the interface, the dry-run exit rule, backups and the log.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset CLAUDECODE HARBOR_DEPLOY
V1='# Rules

**It defers inside a governed repo.** Where a project carries the marker,
that repo'"'"'s own governance is authoritative and this file yields to it.

## No.1 Response shape
Lead with the answer.'
V2='# Rules

**It defers inside a governed repo, on everything but the five.** The repo
wins on workflow, conventions and tooling; the five never yield.

## No.1 Response shape
Lead with the answer.'
checkout() { # <name> → a checkout on main whose history is V1 then V2
  _d="$T_TMP/$1"; mkdir -p "$_d/bin" "$_d/policy"
  cp "$T_ROOT/bin/policy-constitution-install.sh" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/deploy-install-lib.sh" "$_d/bin/"
  ( cd "$_d" && git init -q . && git symbolic-ref HEAD refs/heads/main
    printf '%s\n' "$V1" > policy/constitution.md; git add -A && git -c user.email=t@t -c user.name=t commit -qm v1
    printf '%s\n' "$V2" > policy/constitution.md; git add -A && git -c user.email=t@t -c user.name=t commit -qm v2 ) >/dev/null 2>&1
  printf '%s' "$_d"
}
deploy() { # <checkout> <live-content> [flags…] → exit code; output in $T_TMP/out and err
  _c="$1" _live="$2"; shift 2; rm -rf "$_c.cfg"; mkdir -p "$_c.cfg" "$_c.home"
  printf '%s\n' "$_live" > "$_c.cfg/CLAUDE.md"
  HOME="$_c.home" CLAUDE_CONFIG_DIR="$_c.cfg" sh "$_c/bin/policy-constitution-install.sh" --apply --dir "$_c.cfg" "$@" >"$T_TMP/out" 2>"$T_TMP/err"
  echo $?
}
plan() { # <checkout> [flags…] → the exit code of a dry run on the config dir deploy() left
  _c="$1"; shift
  HOME="$_c.home" CLAUDE_CONFIG_DIR="$_c.cfg" sh "$_c/bin/policy-constitution-install.sh" --dir "$_c.cfg" "$@" >"$T_TMP/out" 2>"$T_TMP/err"
  echo $?
}
out() { cat "$T_TMP/out"; }
err() { cat "$T_TMP/err"; }

t_section "a committed line the repo replaced is not a loss (the #581 deploy)"
C="$(checkout replay)"
t_eq "replaying the #581 shape" 0 "$(deploy "$C" "$V1")"
t_hasnt "the gate does not refuse text in a commit" "$(cat "$T_TMP/out" "$T_TMP/err")" "FAIL:"
t_exit "the live file is the new version" 0 cmp -s "$C/policy/constitution.md" "$C.cfg/CLAUDE.md"

t_section "the history follows the file across a rename (W2: CONSTITUTION.md -> policy/constitution.md)"
# The real move kept most of the file, which is what lets git see a rename; a body the two versions share does the same here.
BODY="$(i=1; while [ $i -le 20 ]; do printf 'Shared rule %s, unchanged by the move.\n' $i; i=$((i + 1)); done)"
moved() { # <name> → V1 committed as CONSTITUTION.md, then moved and replaced by V2 in one commit, then the old name's shim
  _d="$T_TMP/$1"; mkdir -p "$_d/bin" "$_d/policy"
  cp "$T_ROOT/bin/policy-constitution-install.sh" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/deploy-install-lib.sh" "$_d/bin/"
  ( cd "$_d" && git init -q . && git symbolic-ref HEAD refs/heads/main
    printf '%s\n%s\n' "$V1" "$BODY" > CONSTITUTION.md; git add -A && git -c user.email=t@t -c user.name=t commit -qm v1
    git mv CONSTITUTION.md policy/constitution.md && printf '%s\n%s\n' "$V2" "$BODY" > policy/constitution.md
    git add -A && git -c user.email=t@t -c user.name=t commit -qm 'move and edit, as #1395 did'
    ln -s policy/constitution.md CONSTITUTION.md && git add -A && git -c user.email=t@t -c user.name=t commit -qm shim ) >/dev/null 2>&1
  printf '%s' "$_d"
}
C="$(moved renamed)"
t_eq "a line committed only under the old name is not a loss" 0 "$(deploy "$C" "$V1")"
t_hasnt "...and is not refused" "$(cat "$T_TMP/out" "$T_TMP/err")" "FAIL:"
C="$(moved renamed-unique)"
t_eq "a live-only line still refuses across the rename" 1 "$(deploy "$C" "$V1
LIVE-ONLY: never committed.")"
t_has "...counting the versions under both names, and not the shim's commit" "$(out)" \
  "found in none of the 2 committed version(s) of policy/constitution.md"
t_hasnt "...and does not list the old-name paragraph" "$(out)" "| **It defers inside a governed repo.**"

t_section "a line in no commit still refuses, and is named"
C="$(checkout unique)"
LIVE="$V1
LIVE-ONLY: typed straight into the box and never committed anywhere."
t_eq "a live-only line" 1 "$(deploy "$C" "$LIVE")"
t_has "says it refused, as a FAIL" "$(out)" "  FAIL: refused: the box's CLAUDE.md carries 1 line(s)"
t_has "names the live-only line" "$(out)" "| LIVE-ONLY: typed straight into the box"
t_hasnt "does not list the replaced committed paragraph" "$(out)" "| **It defers inside a governed repo.**"
t_has "says it read the history" "$(out)" "found in none of the 2 committed version(s) of policy/constitution.md"
t_has "the FAIL is followed by the fix that passes the gate" "$(grep -A1 '  FAIL: refused:' "$T_TMP/out" | tail -1)" \
  "  fix: sh $C/bin/policy-constitution-install.sh --apply --dir '$(cd "$C.cfg" && pwd -P)' --accept-loss"
t_has "and names the lossless back-port" "$(out)" "the lossless way is a back-port"
t_eq "the refused deploy left the live file" "$LIVE" "$(cat "$C.cfg/CLAUDE.md")"

t_section "--accept-loss goes through, and keeps the only copy"
t_eq "--accept-loss" 0 "$(deploy "$C" "$LIVE" --accept-loss)"
t_exit "--accept-loss installs the new version" 0 cmp -s "$C/policy/constitution.md" "$C.cfg/CLAUDE.md"
t_has "the backup holds the live-only line" "$(cat "$C.cfg"/backups/constitution-install/*/CLAUDE.md 2>/dev/null)" "LIVE-ONLY: typed straight"
t_has "the accepted loss is a WARN naming it" "$(out)" "  WARN: --accept-loss: the box's CLAUDE.md carries 1 line(s)"

t_section "reordering and blank lines are not a loss"
C="$(checkout reorder)"
t_eq "a reordered live file" 0 "$(deploy "$C" "## No.1 Response shape
Lead with the answer.


# Rules
**It defers inside a governed repo, on everything but the five.** The repo
wins on workflow, conventions and tooling; the five never yield.")"

t_section "outside a git checkout: the current file only, and it says so"
C="$(checkout nogit)"; rm -rf "$C/.git"
t_eq "the replaced paragraph refuses (--from-branch passes the branch gate)" 1 "$(deploy "$C" "$V1" --from-branch)"
t_has "says why" "$(out)" "is not a git checkout, so its history could not be read"

t_section "a failed history read is reported as failed (review of #685)"
C="$(checkout revlist-fails)"; FB="$T_TMP/fakebin"; mkdir -p "$FB"
printf '#!/bin/sh\nfor a in "$@"; do case "$a" in rev-list|log) echo "fatal: bad object" >&2; exit 128 ;; esac; done\nexec %s "$@"\n' \
  "$(command -v git)" > "$FB/git"; chmod +x "$FB/git"
t_eq "the history read failing: the replaced paragraph refuses" 1 "$(PATH="$FB:$PATH" deploy "$C" "$V1")"
t_has "names the failed history read" "$(out)" "git log --follow failed in"
t_hasnt "claims no history search" "$(out)" "committed version(s) of policy/constitution.md"
C="$(checkout show-fails)"
B="$(git -C "$C" rev-parse HEAD~1:policy/constitution.md)"; rm -f "$C/.git/objects/$(printf '%s' "$B" | cut -c1-2)/$(printf '%s' "$B" | cut -c3-)"
t_eq "v1 unreadable: v1's paragraph refuses" 1 "$(deploy "$C" "$V1")"
t_has "counts the partial read" "$(out)" "1 of 2 committed version(s) that could be read"
t_has "names the unreadable version" "$(out)" "1 version(s) could NOT be read"

t_section "the interface: no positional target, unknown flags, the live dir only by --live, and no env target"
C="$(checkout iface)"; mkdir -p "$C.home/.claude" "$C.cfg"; printf '%s\n' "$V1" > "$C.home/.claude/CLAUDE.md"
ci() { env -u CLAUDE_CONFIG_DIR HOME="$C.home" sh "$C/bin/policy-constitution-install.sh" "$@" >"$T_TMP/out" 2>"$T_TMP/err"; echo $?; }
t_eq "a positional target is a usage error" 2 "$(ci --apply "$C.cfg")"
t_has "...that says there is none" "$(err)" "there is no positional target"
t_eq "an unknown flag is a usage error" 2 "$(ci --dir "$C.cfg" --bogus)"
t_eq "no target is a usage error" 2 "$(ci --apply)"
t_eq "--dir onto the live dir is refused" 1 "$(ci --apply --dir "$C.home/.claude/")"
t_has "...with the --live command as its fix" "$(out)" "  fix: sh $C/bin/policy-constitution-install.sh --apply --live"
t_eq "...and the live CLAUDE.md is untouched" "$V1" "$(cat "$C.home/.claude/CLAUDE.md")"
t_eq "CLAUDE_CONFIG_DIR pointing elsewhere is a usage error" 2 \
  "$(env HOME="$C.home" CLAUDE_CONFIG_DIR="$C.cfg" sh "$C/bin/policy-constitution-install.sh" --live >/dev/null 2>&1; echo $?)"
t_eq "-h in any position prints the usage" 0 "$(ci --dir "$C.cfg" -h)"
t_has "...from the header" "$(out)" "[--apply] (--live | --dir PATH) [--from-branch] [--accept-loss]"

t_section "the dry-run exit rule: a dry run exits 1 exactly when --apply would refuse"
C="$(checkout dryrule)"
LIVE="$V1
LIVE-ONLY: a line only the box has."
deploy "$C" "$LIVE" >/dev/null; NLOG="$(ls "$C.cfg/backups/constitution-install" | wc -l | tr -d ' ')"
t_eq "the loss check runs in the dry run: exit 1" 1 "$(plan "$C")"
t_has "...saying what --apply would refuse" "$(out)" "  FAIL: --apply would refuse: the box's CLAUDE.md carries 1 line(s)"
t_has "...with the fix" "$(out)" "  fix: sh $C/bin/policy-constitution-install.sh --apply --dir '$(cd "$C.cfg" && pwd -P)' --accept-loss"
t_eq "...and it wrote nothing" "$LIVE" "$(cat "$C.cfg/CLAUDE.md")"
t_eq "...and opened no log (the refused apply before it opened the only one)" "$NLOG" "$(ls "$C.cfg/backups/constitution-install" | wc -l | tr -d ' ')"
t_eq "a dry run with --accept-loss exits 0" 0 "$(plan "$C" --accept-loss)"
t_has "...warning what would be lost" "$(out)" "  WARN: --accept-loss: the box's CLAUDE.md carries 1 line(s)"
git -C "$C" checkout -q -b feature 2>/dev/null
t_eq "a dry run from a feature branch exits 1" 1 "$(plan "$C" --accept-loss)"
t_has "...naming the branch gate" "$(out)" "  FAIL: --apply would refuse: deploying from 'feature', not main"
t_has "...and --from-branch as the fix" "$(out)" "--accept-loss --from-branch"
t_eq "...which --from-branch clears" 0 "$(plan "$C" --accept-loss --from-branch)"
git -C "$C" checkout -q main 2>/dev/null; printf 'uncommitted\n' >> "$C/policy/constitution.md"
t_eq "a dry run with uncommitted policy/constitution.md edits exits 1" 1 "$(plan "$C" --accept-loss)"
t_has "...naming them" "$(out)" "policy/constitution.md has uncommitted changes"
git -C "$C" checkout -q -- policy/constitution.md
cp "$C/policy/constitution.md" "$C.cfg/CLAUDE.md"
t_eq "an identical box is a clean dry run" 0 "$(plan "$C")"
t_has "...that says so" "$(out)" "  ok: already identical, nothing to write"
printf '%s\n' "$V1" > "$C.cfg/CLAUDE.md"
t_eq "a plain update is a clean dry run" 0 "$(plan "$C")"
t_has "...ending with the apply command" "$(out)" "  note: next: sh $C/bin/policy-constitution-install.sh --apply --dir"
t_has "...and the summary" "$(tail -1 "$T_TMP/out")" "constitution-install: 0 ok, 0 failed, 0 warnings"

t_section "an apply: the backup and the log in backups/constitution-install/<TS>/, and a refusal is logged too"
C="$(checkout applylog)"
t_eq "a replayed update applies" 0 "$(deploy "$C" "$V1")"
LD="$(tail -1 "$T_TMP/out" | sed -n 's/^log: //p')"
t_has "the last line names the log" "$LD" "$(cd "$C.cfg" && pwd -P)/backups/constitution-install/"
t_has "...which holds the run's lines" "$(cat "$LD" 2>/dev/null)" "  ok: installed"
t_eq "the pre-run CLAUDE.md is beside it" "$V1" "$(cat "$(dirname "$LD")/CLAUDE.md" 2>/dev/null)"
t_eq "no old-style backup is written" "" "$(ls "$C.cfg/backups" | grep -v '^constitution-install$')"
t_eq "a refused apply (a box-only line)" 1 "$(deploy "$C" "$V1
BOX-ONLY")"
LD="$(tail -1 "$T_TMP/out" | sed -n 's/^log: //p')"
t_has "...still writes its log, with the refusal" "$(cat "$LD" 2>/dev/null)" "FAIL: refused:"
t_has "...and says nothing was written" "$(out)" "  note: nothing was written"

t_section "under deploy the B8 re-pin next step is deploy's, and is not printed (harbor#285)"
C="$(checkout repin)"; mkdir -p "$C.home/.claude"; printf '%s\n' "$V1" > "$C.home/.claude/CLAUDE.md"
env -u CLAUDE_CONFIG_DIR HOME="$C.home" sh "$C/bin/policy-constitution-install.sh" --apply --live >"$T_TMP/out" 2>&1
t_has "a live apply names the re-pin, in pin-instructions' own interface" "$(out)" \
  "  note: next: sh $(cd "$C.home/.claude" && pwd -P)/bin/pin-instructions.sh --apply --live"
printf '%s\n' "$V1" > "$C.home/.claude/CLAUDE.md"
env -u CLAUDE_CONFIG_DIR HOME="$C.home" HARBOR_DEPLOY=1 sh "$C/bin/policy-constitution-install.sh" --apply --live >"$T_TMP/out" 2>&1
t_hasnt "under deploy it does not" "$(out)" "pin-instructions.sh --apply --live"
t_has "...though the install itself ran" "$(out)" "  ok: installed"
t_section "the install manifest (install standard §3): CLAUDE.md is a row, written on --apply only"
C="$(checkout manifest)"
t_eq "a dry run" 0 "$(deploy "$C" "$V2" >/dev/null; rm -f "$C.cfg/.harbor-manifest"; plan "$C")"
t_eq "...writes no manifest" no "$([ -e "$C.cfg/.harbor-manifest" ] && echo yes || echo no)"
t_eq "an apply" 0 "$(deploy "$C" "$V1")"
t_eq "...records CLAUDE.md: the bytes installed, 100644, the installer and the checkout's commit" \
  "$(git hash-object "$C.cfg/CLAUDE.md") 100644 CLAUDE.md constitution-install $(git -C "$C" rev-parse HEAD)" \
  "$(grep ' CLAUDE.md ' "$C.cfg/.harbor-manifest" 2>/dev/null)"
t_done
