#!/usr/bin/env sh
# gate-merge-stack.sh (harbor#1060) — merge a plan's PRs in order, squash only, each on its own green CI.
# Reached as `harbor merge-stack <check|rehearse|merge|verify> <plan>`. Ported from the 2026-10-06 night-stack kit.
#
#   check    <plan>            read-only: state, CI and mergeability of every PR; exit 1 if any is not ready
#   rehearse <plan> [--push]   build the combined tree in a scratch clone; --push opens the DO-NOT-MERGE PR, whose CI lints it
#   merge    <plan>            preflight (the check report must be clean), then merge in plan order. A real Terminal
#   verify   <plan>            after the merge: every PR merged, main equals the tested tree, lint clean, deploy plan passes
#
# The procedure, the plan format and the trap each piece handles: docs/design/merge-stack.md.
# Exit: 0 clean, 1 a problem was reported, 2 usage or a bad plan, 3 a pinned PR (`pr N head <sha>`) needs a rebase.
# Rerunnable: a merged PR is skipped. Every merge is pinned to the head whose CI was judged (--match-head-commit).
# HARBOR_GATE_REHEARSE_DIR moves the rehearsal's scratch clone (default ~/.cache/merge-stack, not a session scratchpad).
# gate-merge-check.sh is resolved from THIS tool's own dir, never from the target repo (harbor#1060, ship contract 5a.6), so a
# repo needs none of harbor's scripts. It is always handed the required checks read from origin once, at preflight (5b.11, r5 #3-4).
# merge-stack never runs code from a PR branch: no generator, lint or suite, and no git hook, in sync or rehearse (r5 #2).
# Deliberately one file: the four sub-verbs share the plan reader, the rebase-with-union step and the log shape.

case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH= cd -- "$HERE" && pwd)"
. "$HERE/library-log.sh"
set -eu
log_init gate-merge-stack
# the line lists whose pure additions the resolver keeps from both sides: beside the tool once installed, else the checkout's
UNION="$HERE/merge-stack-union.txt"; [ -f "$UNION" ] || UNION="$HERE/../contracts/merge-stack-union.txt"
RESOLVER="$HERE/gate-merge-stack-resolve.py"
# harbor's own required-checks rows (r5 #3): installed beside the tool, else the checkout's contracts/ (read from its origin)
HROWS="$HERE/required-checks.tsv"; [ -f "$HROWS" ] || HROWS="$HERE/../contracts/required-checks.tsv"

usage() {
  cat <<'EOF'
usage: harbor merge-stack <check|rehearse|merge|verify> <plan> [--push]

  check    <plan>            read-only: every PR's state, CI and mergeability; exit 1 if any is not ready
  rehearse <plan> [--push]   the combined tree in a scratch clone; --push opens the DO-NOT-MERGE PR for CI
  merge    <plan>            merge in plan order, each on its own green CI (run from a real Terminal)
  verify   <plan>            after the merge: merged, equal to the tested tree, lint clean, deploy plan passes

Procedure, plan format and the traps each piece handles: docs/design/merge-stack.md
EOF
}
usage_err() { printf 'gate-merge-stack: %s\n' "$1" >&2; usage >&2; exit 2; }

SUB=''; PLAN=''; PUSH=0
for _a in "$@"; do
  case "$_a" in
    -h|--help|help) usage; exit 0 ;;
    --push) PUSH=1 ;;
    -*) usage_err "unknown option $_a" ;;
    *) if [ -z "$SUB" ]; then SUB="$_a"; elif [ -z "$PLAN" ]; then PLAN="$_a"; else usage_err "one plan only: $_a"; fi ;;
  esac
done
case "$SUB" in check|rehearse|merge|verify) ;; '') usage_err "a sub-verb is required" ;; *) usage_err "unknown sub-verb $SUB" ;; esac
[ -n "$PLAN" ] || usage_err "a plan file is required"
[ "$PUSH" = 0 ] || [ "$SUB" = rehearse ] || usage_err "--push belongs to rehearse"
[ -f "$PLAN" ] || usage_err "no plan file: $PLAN"

key() { awk -v k="$1" '{ sub(/#.*/, "") } $1 == k { $1 = ""; sub(/^ +/, ""); print }' "$PLAN"; }
R="$(key repo)"; H="$(key checkout)"; PRLINES="$(key pr)"; WF="$(key workflow)"; T="$(key tested)"
# `method squash|merge-commit` (default squash): a merge commit keeps the PR's commits and authors on the default
# branch; a squash is authored by whoever opened the PR (harbor#1018: the App opens them, the operator authors).
METHOD="$(key method | head -1)"; case "${METHOD:-squash}" in squash|merge-commit) METHOD="${METHOD:-squash}" ;; *) usage_err "plan method must be squash or merge-commit: $METHOD" ;; esac
PRS="$(printf '%s\n' "$PRLINES" | awk 'NF { print $1 }')"
[ -n "$R" ] && [ -n "$H" ] && [ -n "$PRS" ] || usage_err "plan needs repo, checkout and at least one pr"
case "$R" in */*/*|*[!A-Za-z0-9._/-]*|/*|*/) usage_err "plan repo must be owner/name: $R" ;; */*) ;; *) usage_err "plan repo must be owner/name: $R" ;; esac
for _p in $PRS; do case "$_p" in *[!0-9]*) usage_err "plan pr must be a number: $_p" ;; esac; done
# `pr N head <sha>` pins the commit that was judged (ship contract 5b.10): any other head is needs-rebase, never synced.
# A pin is the FULL 40-hex sha, compared with `=`: a prefix can be brute-forced into a forged commit.
_badpin="$(printf '%s\n' "$PRLINES" | awk 'NF == 1 { next } NF == 3 && $2 == "head" && length($3) == 40 && $3 !~ /[^0-9a-f]/ { next } { print $1; exit }')"
[ -z "$_badpin" ] || usage_err "a pr line is 'pr N' or 'pr N head <40-hex sha>' (a full sha, not a prefix): pr $_badpin"
pin_of() { printf '%s\n' "$PRLINES" | awk -v p="$1" '$1 == p && $2 == "head" { print $3; exit }'; }
head_is() { # <pr> <pin> — the PR's current head IS the pin
  _cur="$(st "$1" headRefOid)"; [ "$_cur" = "$2" ]
}
NEEDS=0
needs_rebase() { # <pr> <pin>
  NEEDS=1; log_warn "needs-rebase #$1: its head is $(st "$1" headRefOid), the plan pins $2; a pinned PR is never synced"
  log_fix "re-classify #$1 and pin its new head, or rebase it yourself, then re-run: harbor merge-stack merge $PLAN"
}
[ -d "$H" ] || usage_err "plan checkout is not a directory: $H"
MC="$HERE/gate-merge-check.sh"   # the tool's own install, not "$H/bin": a repo that is not harbor has no bin/
# the repo's own required-checks declarations on origin/<default>; ALL of them count, with harbor's rows (r5 #3)
RC_PATHS='.agents/required-checks.tsv contracts/required-checks.tsv'
RCTMP=''

die() { log_fail "$1"; log_fix "$2"; log_end || :; exit 1; }
NBAD=0
bad() { NBAD=$((NBAD + 1)); log_fail "$1"; log_fix "$2"; }
st() { gh pr view "$1" -R "$R" --json "$2" --jq ".$2"; }
merged() { [ "$(st "$1" state)" = MERGED ]; }
wt_of() { git -C "$H" worktree list --porcelain | awk -v b="refs/heads/$1" '/^worktree /{ w = substr($0, 10) } $0 == "branch " b { print w }'; }
wf() { [ -z "$WF" ] || printf -- '--workflow\n%s\n' "$WF"; }
# The latest run of EVERY workflow on a commit, per event, one "<id> <status> <conclusion>" line each. With a plan `workflow`
# key only that workflow's runs are listed; without one, all of them count (ship contract 5b.12). Per event: a newer green
# workflow_dispatch or push run of the same workflow must not hide a red pull_request run. A latest run that was cancelled
# stays in, and is not green: only a newer run of the same workflow and event replaces it.
# gh returns the NEWEST $RUN_LIMIT runs: a full page may hide an older red run, so it is refused (exit 3), never judged.
RUN_LIMIT=100
latest_runs() {
  _lr="$(gh run list -R "$R" $(wf) --commit "$1" --limit "$RUN_LIMIT" --json databaseId,status,conclusion,workflowDatabaseId,event \
    --jq "if length >= $RUN_LIMIT then \"TRUNCATED\" else (group_by([.workflowDatabaseId, .event]) | map(max_by(.databaseId)) | .[] | \"\\(.databaseId) \\(.status) \\(.conclusion)\") end")" || return 1
  [ "$_lr" != TRUNCATED ] || return 3
  [ -z "$_lr" ] || printf '%s\n' "$_lr"
}
TRUNC_FIX='a commit with that many runs is judged by a person: gh run list -R'
# Every git command here runs with no hook (r5 #2): a relative core.hooksPath resolves into the PR's own tree, and a hook
# from anywhere may run the tree's scripts (harbor's pre-push runs bin/). CI is the gate on a PR's code; nothing here runs it.
# A shell function, so merge-check, verify's lint and deploy (main's reviewed code, run as children) keep the operator's git.
git() { command git -c core.hooksPath=/dev/null "$@"; }
# the attribute-free git (r5 #5); `command`, so GIT_ATTR_NOSYSTEM reaches git alone and never persists in this shell
attr_git() { _ad="$1"; shift
  GIT_ATTR_NOSYSTEM=1 command git -c core.hooksPath=/dev/null -C "$_ad" --attr-source="$(empty_tree "$_ad")" -c core.attributesFile=/dev/null "$@"; }
empty_tree() { git -C "$1" hash-object -t tree /dev/null; }
# One git for every rebase, in the conflict style the resolver reads (diff3, always: it needs the base section to tell an
# addition from a deletion or an edit). Never git's `union` driver: it keeps both sides of a block whatever they are, so a
# line main deleted comes back beside the PR's edit of it (r4 #2). Every conflict goes to the resolver or to a person.
# No merge driver at all (r5 #5): no attributes are read from the tree, the global file or the system file (--attr-source,
# git 2.42+), merge.default is git's own text merge, and rerere replays nothing. $GIT_DIR/info/attributes cannot be
# switched off, so drivers_clear refuses a PR whose paths it would route through a driver.
# core.commentChar=auto: a message starting with `#` (the rehearsal's `#N net`, a PR title) is not stripped to empty on --continue.
rebase_git() { _rd="$1"; shift; attr_git "$_rd" -c merge.default=text -c rerere.enabled=false -c merge.conflictStyle=diff3 -c core.commentChar=auto "$@"; }
drivers_clear() { # <dir> <from> <to> — every path changed between them merges with git's own text merge in rebase_git
  _dv="$(git -C "$1" diff --name-only -z --no-renames "$2" "$3" | attr_git "$1" check-attr -z --stdin merge | tr '\0' '\n' |
    awk 'NR % 3 == 1 { p = $0 } NR % 3 == 0 && $0 != "unspecified" && $0 != "set" { print p " (merge=" $0 ")" }')"
  [ -z "$_dv" ] || { log_warn "a merge driver would resolve these unseen: $(echo $_dv)"; return 1; }
}
DRIVER_FIX='drop the merge attribute for those paths from $GIT_DIR/info/attributes, or resolve the PR by hand'
# A conflicted file both sides only added to: keep both. A declared line list is resolved line by line. Anything else stays for a person.
resolve_file() { # <worktree> <repo-relative path>
  command -v python3 >/dev/null 2>&1 || { log_warn "python3 is not on PATH: $2 stays conflicted for a person"; return 1; }
  if awk -v f="$2" '/^[[:space:]]*(#|$)/ { next } NF == 1 && $1 == f { hit = 1 } END { exit !hit }' "$UNION"; then
    python3 "$RESOLVER" --lines "$1/$2"
  else python3 "$RESOLVER" "$1/$2"; fi
}
# docs/generated/status.md, where the repo owns its generator (bin/status-generate.sh): verify leaves it out of its tested-tree diff, and a
# conflict in it stops for a person, because rebuilding it means running the PR's code. docs/index.html is not here any
# more (harbor#1197): harbor builds it on demand and does not commit it, so no PR carries it and no conflict can.
generated_by() { # <worktree> <path> → 0 when the repo has the generator for that path
  case "$2" in docs/generated/status.md) [ -f "$1/bin/status-generate.sh" ] ;; *) return 1 ;; esac
}
# A line both sides added is kept once (a suite listed twice is run twice and its result LOST). Nothing is regenerated (r5 #2):
# the generators run the tree they read (doc-index-generate.sh runs its lint, status-generate.sh its suites), so no copy of them, installed or
# origin's, can rebuild a PR's generated files without running the PR's code. A stale one fails the PR's own CI, which stops the run.
dedupe() { # <worktree> <commit message>
  for _m in contracts/suites.txt contracts/suite-paths.txt; do [ -f "$1/$_m" ] || continue
    awk '/^[[:space:]]*(#|$)/ { print; next } !seen[$0]++' "$1/$_m" > "$1/$_m.tmp" && mv "$1/$_m.tmp" "$1/$_m"; done
  [ -z "$(git -C "$1" status --porcelain --untracked-files=no)" ] || git -C "$1" commit -qam "$2"
}
# git holds all three stages (base, ours, theirs) of the path, each the same regular-file mode (r5 #1)
three_stages() { # <worktree> <path>
  _ls="$(git -C "$1" ls-files -u -- ":(literal)$2")"
  [ "$(printf '%s\n' "$_ls" | awk '{ print $3 }' | sort | tr -d '\n')" = 123 ] || return 1
  case "$(printf '%s\n' "$_ls" | awk '{ print $1 }' | sort -u | tr '\n' ' ')" in '100644 '|'100755 ') ;; *) return 1 ;; esac
}
# A conflicted file is resolved only when both sides edited it (three_stages) and the resolver resolved at least one block in
# it. A delete/modify or an add/add (no stage 1 or 3), a mode change, a link, a submodule or a binary file (no markers) stops
# for a person (r5 #1), and so does a generated file (no PR code runs to rebuild it, r5 #2). False, listing them, otherwise.
settle() { # <worktree> → 0 when no conflict is left
  for _f in $(git -C "$1" diff --name-only --diff-filter=U); do
    if generated_by "$1" "$_f"; then log_warn "$_f is generated: rebuild it on the PR branch (merge-stack never runs a PR's generator)"
    elif ! three_stages "$1" "$_f"; then log_warn "$_f: not an edit on both sides (a deletion, an add/add, a mode change, a link, a submodule)"
    elif resolve_file "$1" "$_f"; then git -C "$1" add -- ":(literal)$_f"; log_note "$_f — both sides kept"; fi
  done
  [ -z "$(git -C "$1" diff --name-only --diff-filter=U)" ]
}
# The default branch is the remote's, read from GitHub (else origin/HEAD); nothing here says `main`.
default_branch() {
  _d="$(gh repo view "$R" --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null)" || _d=''
  [ -n "$_d" ] || _d="$(git -C "$H" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')" || _d=''
  case "$_d" in ''|*[!A-Za-z0-9._/-]*) die "cannot read $R's default branch from GitHub or origin/HEAD" "gh repo view $R --json defaultBranchRef" ;; esac
  printf '%s' "$_d"
}
rebasing() { [ -d "$(git -C "$1" rev-parse --path-format=absolute --git-path rebase-merge)" ]; }
# harbor's own contracts/required-checks.tsv, never a PR's working tree (r4 #1): the copy installed beside the tool (deployed from
# harbor's main, already composed with the private layer's rows by runtime-install), or, from a harbor checkout, the file as that
# checkout's origin/<default branch> holds it followed by the private layer's required-checks.tsv (harbor#1149): no branch of any
# repo being merged, but no protected path either, so it holds only the rows core cannot carry. A private file that does not
# compose, or cannot be read, refuses the read. → stdout
harbor_rows() {
  [ "$HROWS" != "$HERE/required-checks.tsv" ] || { cat "$HROWS"; return; }
  _hc="$(CDPATH= cd -- "$HERE/.." && pwd -P)"
  if [ "$(git -C "$_hc" rev-parse --show-toplevel 2>/dev/null)" = "$_hc" ] && git -C "$_hc" ls-files --error-unmatch contracts/required-checks.tsv >/dev/null 2>&1; then
    _hd="$(git -C "$_hc" ls-remote --symref origin HEAD | awk '$1 == "ref:" { sub("^refs/heads/", "", $2); print $2; exit }')"
    [ -n "$_hd" ] && git -C "$_hc" fetch -q origin "+refs/heads/$_hd:refs/remotes/origin/$_hd" || return 1
    git -C "$_hc" cat-file -e "refs/remotes/origin/$_hd:contracts/required-checks.tsv" 2>/dev/null || return 0
    git -C "$_hc" show "refs/remotes/origin/$_hd:contracts/required-checks.tsv" > "$RCTMP.core" || return 1
    _hrc=0; harbor_compose "$RCTMP.core" || _hrc=$?; rm -f "$RCTMP.core"; return "$_hrc"
  else harbor_compose "$HROWS"; fi
}
harbor_compose() { # <core file> -> core's rows, then the private layer's; the plain file where the composer is not beside the tool
  if [ -f "$HERE/gate-required-generate.sh" ]; then sh "$HERE/gate-required-generate.sh" --core "$1"; else cat "$1"; fi
}
# The required checks merge-check is ALWAYS handed (5b.11), into $RCTMP: read from origin ONCE, at preflight, and held for the
# whole run, so an earlier PR in the plan cannot lower the gate a later one is judged by (r5 #4). The UNION of every
# declaration (r5 #3, #1139): origin/<default>'s .agents/required-checks.tsv and contracts/required-checks.tsv, and harbor's
# rows for this repo. A repo's own file can add a check and never drop one harbor requires. Empty: branch protection alone gates.
checks_snapshot() {
  git -C "$H" fetch -q origin "+refs/heads/$DEF:refs/remotes/origin/$DEF" || die "cannot fetch $DEF to read the required checks from it" "git -C $H fetch origin $DEF"
  : > "$RCTMP.all"
  for _rp in $RC_PATHS; do
    git -C "$H" cat-file -e "refs/remotes/origin/$DEF:$_rp" 2>/dev/null || continue
    git -C "$H" show "refs/remotes/origin/$DEF:$_rp" >> "$RCTMP.all" || die "cannot read $_rp from origin/$DEF" "git -C $H show origin/$DEF:$_rp"
    log_note "required checks: $_rp as origin/$DEF holds it"
  done
  harbor_rows >> "$RCTMP.all" || die "cannot read harbor's required checks from $HROWS's origin, or the private layer's required-checks.tsv does not compose with them" "git -C $HERE/.. fetch origin, or sh $HERE/gate-required-generate.sh (names the line)"
  awk -F'\t' -v r="$R" '$1 == r && $2 != "" && !seen[$2]++' "$RCTMP.all" > "$RCTMP"; rm -f "$RCTMP.all"
  if [ -s "$RCTMP" ]; then log_note "required checks for $R, fixed for this run: $(cut -f2 "$RCTMP" | paste -sd'|' - | sed 's/|/ | /g')"
  else log_note "required checks: origin/$DEF declares none and harbor lists none for $R, so only branch protection can gate"; fi
}

# ── check · the report a merge must find clean before it starts ───────────────
report() {
  _bad=0
  gh auth status >/dev/null 2>&1 || { bad "gh is not logged in" "gh auth login"; _bad=1; }
  [ -f "$MC" ] || { bad "no $MC: this install of the tool is incomplete" "git -C $HERE pull --ff-only, or reinstall harbor"; _bad=1; }
  [ -f "$UNION" ] || { bad "no merge-stack-union.txt beside $HERE: this install of the tool is incomplete" "git -C $HERE pull --ff-only, or reinstall harbor"; _bad=1; }
  [ -f "$HROWS" ] || { bad "no required-checks.tsv beside $HERE: this install of the tool is incomplete" "git -C $HERE pull --ff-only, or reinstall harbor"; _bad=1; }
  for p in $PRS; do
    s="$(st "$p" state)"
    if [ "$s" = MERGED ]; then log_ok "#$p merged"; continue; fi
    [ "$s" = OPEN ] || { bad "#$p is $s" "reopen #$p or take it out of $PLAN: gh pr view $p -R $R"; _bad=1; continue; }
    _pin="$(pin_of "$p")"
    if [ -n "$_pin" ] && ! head_is "$p" "$_pin"; then needs_rebase "$p" "$_pin"; continue; fi
    _sha="$(st "$p" headRefOid)"; _lrc=0; runs="$(latest_runs "$_sha")" || _lrc=$?
    if [ "$_lrc" = 3 ]; then bad "#$p has $RUN_LIMIT or more CI runs on its head: an older red run may be hidden" "$TRUNC_FIX $R --commit $_sha"; _bad=1; continue; fi
    [ "$_lrc" = 0 ] || { bad "#$p: cannot list its CI runs" "gh run list -R $R --commit $_sha"; _bad=1; continue; }
    m="$(st "$p" mergeable)"
    r="$(printf '%s\n' "$runs" | awk '$2 == "completed" && $3 != "success" { print; exit }')"
    if [ -n "$r" ]; then bad "#$p last CI run red: $r" "gh run view ${r%% *} -R $R --log-failed"; _bad=1; continue; fi
    r="$(printf '%s\n' "$runs" | awk '$2 != "completed" { print; exit }')"
    if [ -n "$r" ] || [ -z "$runs" ]; then log_note "wait #$p CI not finished: ${r:-no run yet} ($m)"; else log_ok "#$p green, $m"; fi
  done
  return "$_bad"
}

# ── merge · the run's own CI gate: the PR's current head has a green, non-cancelled run.
# NOT `gh pr checks --required`: with no branch protection (a Free private repo) it reports none forever and hangs;
# gate-merge-check.sh gates on the required-checks list itself (checks_snapshot).
GREEN_N=0; JUDGED=''
green() {
  # after a sync push GitHub can report the OLD head for a moment; judging that head's run passed a stale run (#1115)
  if [ -n "${PUSHED:-}" ]; then _i=0
    until [ "$(st "$1" headRefOid)" = "$PUSHED" ]; do
      _i=$((_i + 1)); [ "$_i" -le 36 ] || die "#$1: GitHub never showed the pushed head $PUSHED" "gh pr view $1 -R $R --json headRefOid"; sleep 5; done
  fi
  GREEN_N=$((GREEN_N + 1)); [ "$GREEN_N" -le 6 ] || die "#$1: its CI kept changing under the wait (6 rounds)" "gh run list -R $R --commit $JUDGED"
  _sha="$(st "$1" headRefOid)"
  case "$_sha" in *[!0-9abcdef]*|'') die "#$1: GitHub gave no head commit for it ('$_sha')" "gh pr view $1 -R $R --json headRefOid" ;; esac
  [ "${#_sha}" = 40 ] || die "#$1: its head is not a full sha ('$_sha')" "gh pr view $1 -R $R --json headRefOid"
  JUDGED="$_sha"; _i=0   # the head whose runs are judged: the merge is pinned to it
  until { _lrc=0; _runs="$(latest_runs "$_sha")" || _lrc=$?
    [ "$_lrc" != 3 ] || die "#$1: $RUN_LIMIT or more CI runs on $_sha, so an older red run may be hidden — stopping" "$TRUNC_FIX $R --commit $_sha"
    [ "$_lrc" = 0 ] && [ -n "$_runs" ]; }; do
    _i=$((_i + 1)); [ "$_i" -le 180 ] || die "#$1: no CI run for $_sha in 30 min" "gh run list -R $R --commit $_sha"; sleep 10
  done
  # every workflow's latest run must pass: a red lint beside a newer green test blocks (ship contract 5b.12)
  _again=0
  for _run in $(printf '%s\n' "$_runs" | awk '{ print $1 }'); do
    _wrc=0; gh run watch "$_run" -R "$R" --exit-status --interval 30 >/dev/null 2>&1 || _wrc=$?
    _c="$(gh run view "$_run" -R "$R" --json conclusion --jq .conclusion)"
    if [ "$_c" = cancelled ]; then   # superseded (a newer run of its workflow and event) is re-judged; otherwise it is red
      _k=0; while latest_runs "$_sha" | awk -v r="$_run" '$1 == r { f = 1 } END { exit !f }'; do
        _k=$((_k + 1)); [ "$_k" -le 6 ] || die "#$1: CI run $_run was cancelled and no newer run replaced it — stopping" "gh run rerun $_run -R $R, then re-run: harbor merge-stack merge $PLAN"; sleep 10; done
      _again=1; break; fi
    if [ "$_wrc" != 0 ] || [ "$_c" != success ]; then die "#$1: CI run $_run is red (${_c:-no conclusion}) — stopping" "gh run view $_run -R $R --log-failed"; fi
  done
  [ "$_again" = 0 ] || { green "$1"; return; }
  # a workflow may have started, or been re-run, while the others were watched: judge the set again
  [ "$(latest_runs "$_sha")" = "$_runs" ] || { green "$1"; return; }
  log_ok "#$1: CI run $(printf '%s' "$_runs" | awk '{ printf "%s ", $1 }' | sed 's/ $//') green"
}

# a PR GitHub now calls conflicting (an earlier merge touched the same lines): its NET change, rebased onto main
sync() {
  _i=0; while [ "$(st "$1" mergeable)" = UNKNOWN ]; do _i=$((_i + 1)); [ $_i -le 30 ] || break; sleep 5; done
  [ "$(st "$1" mergeable)" = CONFLICTING ] || return 0
  _b="$(st "$1" headRefName)"; _w="$(wt_of "$_b")"
  [ -n "$_w" ] || { _w="${PORT_ROOT:-$HOME/port}/.worktrees/$(basename -- "$H")/stack-$1"; mkdir -p -- "$(dirname -- "$_w")"; git -C "$H" fetch -q origin "$_b"; git -C "$H" worktree add -q "$_w" "$_b"; }  # harbor#1149: not a ~/port sibling
  log_head "rebase #$1 ($_b) onto $DEF"
  git -C "$_w" fetch -q origin
  [ -z "$(git -C "$_w" status --porcelain)" ] || die "#$1: worktree $_w is dirty — stopping" "git -C $_w status"
  # one net commit: replaying history through a line union can resurrect a line the PR added and later deleted
  git -C "$_w" checkout -q "$_b"
  # what is merged is what is on the PR: a local branch holding an unpushed commit, or an older one, is refused
  [ "$(git -C "$_w" rev-parse HEAD)" = "$(git -C "$_w" rev-parse "origin/$_b")" ] || die "#$1: local branch $_b is not origin/$_b (an unpushed or a stale commit)" "git -C $_w log --oneline origin/$_b..$_b; push it or reset the branch to origin/$_b, then re-run: harbor merge-stack merge $PLAN"
  git -C "$_w" reset -q --soft "$(git -C "$_w" merge-base origin/$DEF HEAD)"
  git -C "$_w" commit -q -m "$(st "$1" title)" -m "Squashed for the rebase onto $DEF by merge-stack; the PR is squash-merged anyway."
  drivers_clear "$_w" HEAD~1 HEAD || die "#$1: a merge driver in $_w's info/attributes would resolve its paths — stopping" "$DRIVER_FIX"
  _again=0; rebase_git "$_w" rebase -q origin/$DEF "$_b" >/dev/null 2>&1 || _again=1
  while [ "$_again" = 1 ]; do
    settle "$_w" || { git -C "$_w" diff --name-only --diff-filter=U; git -C "$_w" rebase --abort
      die "#$1: conflict needs a person — stopping" "resolve it on the PR branch with a new commit, then re-run: harbor merge-stack merge $PLAN"; }
    # a --continue that fails with nothing left conflicted would fail the same way forever: stop, never loop
    GIT_EDITOR=true rebase_git "$_w" rebase --continue >/dev/null 2>&1 || ! rebasing "$_w" || [ -n "$(git -C "$_w" diff --name-only --diff-filter=U)" ] ||
      { git -C "$_w" rebase --abort; die "#$1: the rebase would not continue once its conflicts were resolved — stopping" "git -C $_w status"; }
    if rebasing "$_w"; then _again=1; else _again=0; fi
  done
  dedupe "$_w" "chore: list lines both sides added, kept once, after the rebase onto $DEF"
  git -C "$_w" push -q --force-with-lease origin "$_b"
  PUSHED="$(git -C "$_w" rev-parse HEAD)"
}

cmd_merge() {
  RCTMP="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"; trap 'rm -f "$RCTMP" "$RCTMP.all" "$RCTMP.core"' EXIT
  checks_snapshot
  for p in $PRS; do
    if merged "$p"; then log_note "#$p already merged"; continue; fi
    # a pinned PR is merged only on the head that was judged, and is never synced (it would move the head)
    _pin="$(pin_of "$p")"
    if [ -n "$_pin" ] && ! head_is "$p" "$_pin"; then needs_rebase "$p" "$_pin"; continue; fi
    PUSHED=""; GREEN_N=0; [ -n "$_pin" ] || sync "$p"
    log_head "merge #$p"; green "$p"
    if [ -n "$_pin" ] && [ "$JUDGED" != "$_pin" ]; then needs_rebase "$p" "$_pin"; continue; fi
    # --match-head-commit: gh refuses if the head moved after the run was judged, so a push in between cannot land.
    # merge-check's gate logic is unchanged; it is told the repo, the branch and the required checks read at preflight
    ( HARBOR_REPO="$R"; export HARBOR_REPO; HARBOR_BRANCH="$DEF"; export HARBOR_BRANCH
      HARBOR_REQUIRED_CHECKS="$RCTMP"; export HARBOR_REQUIRED_CHECKS
      sh "$MC" "--$METHOD" --merge "$p" --match-head-commit "$JUDGED" )
    merged "$p" || die "#$p did not merge — stopping" "HARBOR_REPO=$R sh $MC --$METHOD --merge $p --match-head-commit $JUDGED"
    key after | awk -v p="$p" '$1 == p { $1 = ""; sub(/^ +/, ""); print $0 }' | while IFS= read -r _c; do log_note "run once now: $_c"; done
  done
  log_note "done — next: harbor merge-stack verify $PLAN"
}

# ── rehearse · the combined tree, built the way merge will merge it ───────────
cmd_rehearse() {
  set +e   # as the kit ran it: every failure below is handled by name
  [ "$PUSH" = 0 ] || [ -n "$T" ] || { log_fail "plan has no tested: branch name"; log_fix "add a line to $PLAN: tested ci/integration-<name>"; log_end; exit 2; }
  case "$T" in "$DEF"|main|master|HEAD) die "tested: $T would overwrite $T" "name a throwaway branch, e.g. tested ci/integration-<date>" ;; esac
  S="${HARBOR_GATE_REHEARSE_DIR:-$HOME/.cache/merge-stack}/$(echo "$R" | tr / _)"   # under ~: a session scratchpad can be purged mid-run
  mkdir -p "$(dirname "$S")"
  [ -d "$S/.git" ] || git clone -q "$H" "$S" || die "cannot clone $H into $S" "git clone $H $S"
  cd "$S" || exit 1
  git config user.name merge-stack; git config user.email merge-stack@localhost
  git remote set-url origin "https://github.com/$R.git"
  git fetch -q origin '+refs/heads/*:refs/remotes/origin/*' || die "cannot fetch $R" "gh auth status"
  git rebase --abort >/dev/null 2>&1; git merge --abort >/dev/null 2>&1; git reset -q --hard
  git checkout -q -B rehearse origin/$DEF
  for p in $PRS; do
    b="$(gh pr view "$p" -R "$R" --json headRefName,state --jq 'select(.state=="OPEN") | .headRefName')"
    [ -n "$b" ] || { log_skip "#$p (not open)"; continue; }
    _pin="$(pin_of "$p")"; if [ -n "$_pin" ] && ! head_is "$p" "$_pin"; then needs_rebase "$p" "$_pin"; continue; fi
    [ "$b" != "$T" ] || die "tested: $T is the head branch of #$p" "name a throwaway branch in $PLAN"
    # the PR's head must be origin/$b itself: a fork PR's branch is not on origin, and a same-named one is not its code (r5 #6)
    _hd="$(st "$p" headRefOid)"
    { [ -n "$_hd" ] && [ "$(git rev-parse -q --verify "refs/remotes/origin/$b^{commit}")" = "$_hd" ]; } ||
      die "STOP at #$p ($b): its head ${_hd:-?} is not origin/$b (a fork PR's branch is not on origin), so it cannot be rehearsed" "push the branch to $R, or take #$p out of $PLAN"
    { git checkout -q -B "net-$p" "origin/$b" && git reset -q --soft "$(git merge-base origin/$DEF HEAD)" && git commit -q --allow-empty -m "#$p net"; } ||
      die "STOP at #$p ($b): its net change could not be built" "cd $S && git status"
    drivers_clear . HEAD~1 HEAD || die "STOP at #$p ($b): a merge driver in the scratch clone's info/attributes would resolve its paths" "$DRIVER_FIX"
    rebase_git . rebase -q rehearse "net-$p" >/dev/null 2>&1
    while rebasing .; do
      if ! settle .; then
        _u="$(git diff --name-only --diff-filter=U)"
        log_fail "STOP at #$p ($b): needs a person in: $_u"
        log_fix "resolve it on the PR branch with a new commit, then re-run: harbor merge-stack rehearse $PLAN"
        git diff | head -40; git rebase --abort; log_end; exit 1
      fi
      GIT_EDITOR=true rebase_git . rebase --continue >/dev/null 2>&1 || ! rebasing . || [ -n "$(git diff --name-only --diff-filter=U)" ] ||
        { git rebase --abort; die "STOP at #$p ($b): the rebase would not continue once its conflicts were resolved" "cd $S && git status"; }
    done
    { git checkout -q rehearse && git merge -q --ff-only "net-$p"; } || die "STOP at #$p ($b): the combined tree did not take its net change" "cd $S && git status"
    log_ok "#$p ($b) rebased onto the combined tree"
  done
  dedupe . "rehearsal: list lines both sides added, kept once"
  # The combined tree's lint, suites and generators are its PRs' code, so they are not run here (r5 #2): CI runs them on --push.
  [ "$PUSH" = 1 ] || log_note "lint and suites of the combined tree run in CI, never here: harbor merge-stack rehearse $PLAN --push"
  if [ "$PUSH" = 1 ]; then
    git push -q -f origin "rehearse:refs/heads/$T" && log_ok "pushed $T"   # a rehearsal branch is ours to overwrite
    n="$(gh pr list -R "$R" --head "$T" --state open --json number --jq '.[0].number // empty')"
    [ -n "$n" ] || gh pr create -R "$R" --base "$DEF" --head "$T" --title "ci: DO NOT MERGE — integration check of $(echo $PRS | sed 's/ / #/g; s/^/#/')" \
      --body "**What:** DO NOT MERGE. The planned PRs merged together onto the default branch, as merge-stack will merge them, so CI runs the full suite on the combination. **Merge:** never; close it (with --delete-branch) after harbor merge-stack verify passes."
  fi
  log_ok "rehearsal clean"
}

# ── verify · after the merge, before deploying ───────────────────────────────
cmd_verify() {
  set +e   # as the kit ran it
  log_head "1. every PR merged"
  for p in $PRS; do s="$(gh pr view "$p" -R "$R" --json state --jq .state)"; if [ "$s" = MERGED ]; then log_ok "#$p"; else bad "#$p is $s" "harbor merge-stack merge $PLAN"; fi; done
  log_head "2. the checkout is $DEF at origin/$DEF"
  git -C "$H" fetch -q origin
  [ "$(git -C "$H" branch --show-current)" = "$DEF" ] || git -C "$H" checkout -q "$DEF" || bad "cannot check out $DEF in $H" "git -C $H status"
  [ -z "$(git -C "$H" status --porcelain --untracked-files=no)" ] || bad "$H has uncommitted changes" "git -C $H status"
  git -C "$H" merge -q --ff-only origin/$DEF 2>/dev/null || bad "cannot fast-forward $H" "git -C $H log --oneline origin/$DEF..HEAD"
  if [ "$(git -C "$H" rev-parse HEAD)" = "$(git -C "$H" rev-parse origin/$DEF)" ]; then log_ok "at $(git -C "$H" rev-parse --short HEAD)"; fi
  log_head "3. $DEF's code is the tested tree (generated files aside)"
  if [ -n "$T" ] && git -C "$H" rev-parse -q --verify "origin/$T" >/dev/null; then
    set -- .; generated_by "$H" docs/generated/status.md && set -- "$@" ':!docs/generated/status.md'
    d="$(git -C "$H" diff --name-only "origin/$T" origin/$DEF -- "$@")"
    pat="$(for p in $PRS; do printf '#%s\\)|' "$p"; done | sed 's/|$//')"
    others="$(git -C "$H" log --format='%h %s' "$(git -C "$H" merge-base "origin/$T" origin/$DEF)"..origin/$DEF | grep -vE "($pat)")"
    if [ -z "$d" ]; then log_ok "identical to $T"
    elif [ -n "$others" ]; then log_note "$DEF also has commits outside the plan: $(echo $others)"; log_ok "differs only alongside those: $(echo $d)"
    else bad "differs from the tested tree with nothing else to explain it: $(echo $d)" "git -C $H diff origin/$T origin/$DEF"; fi
  else bad "no tested branch origin/$T — keep it until this passes" "harbor merge-stack rehearse $PLAN --push"; fi
  log_head "4. lint on a clean checkout of origin/$DEF"
  D="$(mktemp -d "${TMPDIR:-/tmp}/harbor.XXXXXX")"; W="$D/main"; git -C "$H" worktree add -q --detach "$W" origin/$DEF
  if [ -f "$W/bin/lint-conventions.sh" ]; then
    if sh "$W/bin/lint-conventions.sh" >"$D/lint" 2>&1; then log_ok "$(tail -1 "$D/lint")"
    else bad "$(tail -1 "$D/lint")" "sh $H/bin/lint-conventions.sh"; grep VIOLATION "$D/lint" | head -5; fi
  fi
  if [ -f "$W/tests/lib/check.sh" ]; then
    if sh "$W/tests/lib/check.sh" >"$D/chk" 2>&1; then log_ok "$(tail -1 "$D/chk")"; else bad "$(tail -1 "$D/chk")" "sh $H/tests/lib/check.sh"; fi
  fi
  git -C "$H" worktree remove --force "$W"; rm -rf "$D"
  log_head "5. the deploy plan (dry run)"
  if [ -f "$H/bin/deploy.sh" ]; then
    D="$(mktemp -d "${TMPDIR:-/tmp}/harbor.XXXXXX")"; sh "$H/bin/deploy.sh" --live >"$D/deploy" 2>&1
    if tail -1 "$D/deploy" | grep -q ' 0 failed'; then log_ok "$(tail -1 "$D/deploy")"
    else bad "$(tail -1 "$D/deploy")" "sh $H/bin/deploy.sh --live"; grep FAIL "$D/deploy" | head -8; fi
    rm -rf "$D"
  else log_skip "no bin/deploy.sh in this repo — nothing to plan"; fi
  [ "$NBAD" != 0 ] || log_note "ALL CLEAR — deploy from a real Terminal: sh $H/bin/deploy.sh --apply --live"
  log_end
}

log_head "$SUB $PLAN — $R"
case "$SUB" in check) ;; *) DEF="$(default_branch)" ;; esac
# a git that cannot be told to ignore the repo's attributes would merge through their drivers (r5 #5)
case "$SUB" in rehearse|merge) git -C "$H" --attr-source="$(empty_tree "$H")" check-attr merge -- x >/dev/null 2>&1 ||
  die "$(command git --version) cannot ignore a repo's merge attributes (--attr-source): merge-stack needs git 2.42 or newer" "upgrade git" ;; esac
case "$SUB" in
  rehearse) cmd_rehearse; log_end || exit 1; [ "$NEEDS" = 0 ] || exit 3; exit 0 ;;
  verify) cmd_verify; exit $? ;;
esac
if ! report; then log_note "not ready — fix the FAIL lines first, then re-run: harbor merge-stack check $PLAN"; log_end || :; exit 1; fi
if [ "$SUB" = check ]; then log_end || exit 1; [ "$NEEDS" = 0 ] || exit 3; exit 0; fi
cmd_merge
log_end || exit 1
[ "$NEEDS" = 0 ] || exit 3
