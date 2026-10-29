#!/usr/bin/env sh
# Sourced by the merge-stack suites (harbor#1060) after t_init. No network, no real repo: a local bare repository is the
# GitHub remote (url.insteadOf), `gh` a stub answering from files under $MS_FIX with each PR's head and mergeability
# computed from that bare repo, `sleep` a logging no-op, and the checkout's bin/merge-check.sh a stub that squash-merges
# into the bare main. ms_world builds it; ms_branch/ms_add/ms_del/ms_push/ms_main/ms_pr build PRs; ms_mutant copies the tool.
MS_R=acme/widgets
ms_world() { # [harbor] — a bare repo; `harbor` adds harbor's own files, otherwise the repo owns none of them
  MS_DEF="${MS_DEF:-main}"; export MS_DEF; MS_FLAVOR="${1:-plain}"
  MS_FIX="$T_TMP/fix"; MS_BARE="$T_TMP/remote.git"; H="$T_TMP/checkout"; W="$T_TMP/work"
  rm -rf "$MS_FIX" "$MS_BARE" "$H" "$W" "$T_TMP/inst" "$HOME/port/.worktrees" "$HOME/.gitconfig" "$HOME/.cache" "$T_TMP/scratch"
  mkdir -p "$MS_FIX/pr" "$MS_FIX/runs" "$MS_FIX/watch" "$MS_FIX/view" "$MS_FIX/prs" "$MS_FIX/stale"
  export MS_FIX MS_BARE MS_R; PORT_ROOT="$HOME/port"; export PORT_ROOT  # sync parks its worktree under it
  git config --global user.name tester; git config --global user.email tester@example.invalid
  git config --global init.defaultBranch "$MS_DEF"; echo "$MS_DEF" > "$T_TMP/default-branch"
  git config --global url."$MS_BARE".insteadOf "https://github.com/$MS_R.git"
  git init -q --bare "$MS_BARE"
  git clone -q "$MS_BARE" "$W" 2>/dev/null
  MS_INST="$T_TMP/inst"; mkdir -p "$MS_INST/bin" "$MS_INST/CONTRACTS"
  cp "$T_ROOT/bin/log-lib.sh" "$T_ROOT/bin/gate-merge-stack.sh" "$T_ROOT/bin/gate-merge-stack-resolve.py" "$MS_INST/bin/"
  cp "$T_ROOT/CONTRACTS/merge-stack-union.txt" "$T_ROOT/CONTRACTS/required-checks.tsv" "$MS_INST/CONTRACTS/"; GMS="$MS_INST/bin/gate-merge-stack.sh"
  cat > "$MS_INST/bin/merge-check.sh" <<'EOF'
#!/bin/sh
# stub merge-check: squash-merge PR N into the bare remote's default branch, as GitHub does, and mark it merged
echo "merge-check $1 $2 $3" >> "$MS_FIX/merge.log"
echo "repo=${HARBOR_REPO:-} rc=${HARBOR_REQUIRED_CHECKS:-} br=${HARBOR_BRANCH:-}" >> "$MS_FIX/env.log"
[ -z "${HARBOR_REQUIRED_CHECKS:-}" ] || cat "$HARBOR_REQUIRED_CHECKS" >> "$MS_FIX/rc.log"   # what the file said when merge-check read it
echo "$*" >> "$MS_FIX/args.log"
MS_PR="$3" sh "$MS_FIX/../merge-into.sh" "$@"
EOF
  cat > "$T_TMP/merge-into.sh" <<'EOF'
#!/bin/sh
# what GitHub does for `gh pr merge N --squash [--match-head-commit SHA]` — shared by the stub merge-check and the stub gh
n="$MS_PR"; b="$(cat "$MS_FIX/pr/$n.branch")"
[ "${MS_MERGE_REFUSE:-}" != "$n" ] || exit 1
# like gh pr merge --match-head-commit: refuse when the PR head is no longer that commit
while [ $# -gt 0 ]; do [ "$1" != --match-head-commit ] || want="$2"; shift; done
if [ -n "${want:-}" ] && [ "$(git --git-dir="$MS_BARE" rev-parse "refs/heads/$b")" != "$want" ]; then echo "head branch was modified" >&2; exit 1; fi
m="$MS_FIX/merger"; [ -d "$m" ] || git clone -q "$MS_BARE" "$m" 2>/dev/null
git -C "$m" fetch -q origin; git -C "$m" checkout -q -B "$MS_DEF" "origin/$MS_DEF"
git -C "$m" merge -q --squash "origin/$b" >/dev/null 2>&1 || { git -C "$m" reset -q --hard; exit 1; }
git -C "$m" commit -q -m "$(cat "$MS_FIX/pr/$n.title") (#$n)" && git -C "$m" push -q origin "$MS_DEF"
echo MERGED > "$MS_FIX/pr/$n.state"
EOF
  echo "readme" > "$W/README.md"
  if [ "$MS_FLAVOR" = harbor ]; then
    mkdir -p "$W/bin" "$W/CONTRACTS" "$W/docs" "$W/tests/lib"
    printf '# suites\ntests/a/one.test.sh\ntests/a/two.test.sh\n' > "$W/CONTRACTS/suites.txt"
    printf '# paths\n' > "$W/CONTRACTS/suite-paths.txt"
    printf 'cli one\n' > "$W/CONTRACTS/cli.md"
    printf 'status 0\n' > "$W/STATUS.md"; mkdir -p "$W/docs" "$W/tests/lib"; echo 'site 0' > "$W/docs/index.html"
    printf '#!/bin/sh\ncd "$(dirname "$0")/.." || exit 1\n[ "$1" != --check-fast ] || exit 1\necho "generated: $(grep -c . CONTRACTS/suites.txt) suites" > STATUS.md\n' > "$W/bin/status-gen.sh"
    printf '#!/bin/sh\ncd "$(dirname "$0")/.." || exit 1\necho "site: $(grep -c . CONTRACTS/suites.txt) suites" > docs/index.html\n' > "$W/bin/docs-gen.sh"
    printf '#!/bin/sh\ncd "$(dirname "$0")/.." || exit 1\nif [ -f LINT_FAIL ]; then echo "VIOLATION x"; echo "lint: 1 violation"; exit 1; fi\necho "lint: 0 violations"\n' > "$W/bin/lint-conventions.sh"
    printf '#!/bin/sh\necho "check: 0 violations"\n' > "$W/tests/lib/check.sh"
    printf '#!/bin/sh\ncd "$(dirname "$0")/.." || exit 1\nif [ -f DEPLOY_FAIL ]; then echo "  FAIL: repo behind"; echo "deploy: 2 ok, 1 failed, 0 warnings"; exit 1; fi\necho "deploy: 3 ok, 0 failed, 0 warnings"\n' > "$W/bin/deploy.sh"
  fi
  git -C "$W" add -A; git -C "$W" commit -q -m "seed"; git -C "$W" push -q origin "HEAD:$MS_DEF" 2>/dev/null
  git clone -q "$MS_BARE" "$H" 2>/dev/null
  git -C "$W" fetch -q origin
  ms_stubs
}
ms_stubs() {
  cat > "$T_BIN/sleep" <<'EOF'
#!/bin/sh
echo "sleep $*" >> "$MS_FIX/sleep.log"
EOF
  cat > "$T_BIN/gh" <<'EOF'
#!/bin/sh
F="$MS_FIX"; printf '%s\n' "$*" >> "$F/calls.log"
expr=''; prev=''; commit=''; limit=''
for a in "$@"; do [ "$prev" = --jq ] && expr="$a"; [ "$prev" = --commit ] && commit="$a"; [ "$prev" = --head ] && head="$a"; [ "$prev" = --limit ] && limit="$a"; prev="$a"; done
emit() { if [ -n "$expr" ]; then jq -r "$expr"; else cat; fi; }
probe() { # branch → MERGEABLE or CONFLICTING, by a trial merge on a scratch clone of the bare remote
  p="$F/probe"; [ -d "$p" ] || git clone -q "$MS_BARE" "$p" 2>/dev/null
  git -C "$p" fetch -q origin; git -C "$p" checkout -q --detach "origin/$MS_DEF"
  if git -C "$p" merge -q --no-commit --no-ff "origin/$1" >/dev/null 2>&1; then echo MERGEABLE; else echo CONFLICTING; fi
  git -C "$p" merge --abort 2>/dev/null; git -C "$p" reset -q --hard
}
case "$1 $2" in
  "auth status") [ ! -f "$F/noauth" ] ;;
  "pr view")
    n="$3"; br="$(cat "$F/pr/$n.branch")"; state="$(cat "$F/pr/$n.state")"
    oid="$(git --git-dir="$MS_BARE" rev-parse "refs/heads/$br")"; hook=''
    case "$*" in *headRefOid*)   # the first N reads after a push still show the old head: GitHub lags
      rd=$(( $(cat "$F/reads" 2>/dev/null || echo 0) + 1 )); echo "$rd" > "$F/reads"; hook=1
      if [ -f "$F/stale/$n.count" ]; then
        c="$(cat "$F/stale/$n.count")"; old="$(cat "$F/stale/$n.old")"
        if [ "$c" -gt 0 ] && [ "$oid" != "$old" ]; then echo $((c - 1)) > "$F/stale/$n.count"; oid="$old"; fi
      fi
      [ ! -f "$F/empty-head" ] || oid='' ;; esac
    mg=UNKNOWN; case "$*" in *mergeable*) [ "$state" != OPEN ] || mg="$(probe "$br")" ;; esac
    jq -n --arg s "$state" --arg t "$(cat "$F/pr/$n.title")" --arg b "$br" --arg o "$oid" --arg m "$mg" \
      '{state:$s,title:$t,headRefName:$b,headRefOid:$o,mergeable:$m}' | emit
    # a push that lands right after the Nth read of a PR head (a race between two reads)
    if [ -n "$hook" ] && [ -f "$F/after-read" ] && [ "$(cat "$F/after-read-n")" = "$rd" ]; then sh "$F/after-read" >/dev/null 2>&1; rm -f "$F/after-read"; fi ;;
  "run list")
    k="$commit"; [ -f "$F/runs/$k.1" ] || k=default
    n=$(( $(cat "$F/runs/$k.count" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$F/runs/$k.count"
    while [ ! -f "$F/runs/$k.$n" ] && [ "$n" -gt 1 ]; do n=$((n - 1)); done
    # like gh: --limit N returns the NEWEST N runs, so an older one is simply not there
    if [ -n "$limit" ]; then jq -c --argjson l "$limit" 'sort_by(-.databaseId) | .[:$l]' "$F/runs/$k.$n" | emit; else cat "$F/runs/$k.$n" | emit; fi ;;
  "run watch") rc="$(cat "$F/watch/$3" 2>/dev/null || echo 0)"
    # a push lands right after the run is judged: the hook runs once, after the watch returns
    if [ -f "$F/after-watch" ]; then sh "$F/after-watch" >/dev/null 2>&1; rm -f "$F/after-watch"; fi
    exit "$rc" ;;
  "repo view") jq -n --arg d "$MS_DEF" '{defaultBranchRef:{name:$d}}' | emit ;;
  "run view") jq -n --arg c "$(cat "$F/view/$3" 2>/dev/null || echo success)" '{conclusion:$c}' | emit ;;
  "pr list") hf="$F/prs/$(echo "$head" | tr / _)"; if [ -f "$hf" ]; then jq -n --argjson n "$(cat "$hf")" '[{number:$n}]' | emit; else echo '[]' | emit; fi ;;
  "pr create") echo "$*" >> "$F/created.log"; echo 9001 > "$F/prs/$(echo "$head" | tr / _)"; echo "https://example.invalid/pull/9001" ;;
  "pr checks")   # --required lists only what a branch rule requires: nothing, unless protection answers 200
    case " $* " in *" --required "*) [ "$(cat "$F/protection.rc" 2>/dev/null || echo 1)" = 0 ] || { echo "no required checks reported" >&2; exit 1; } ;; esac
    if [ -f "$F/checks.tsv" ]; then cat "$F/checks.tsv"; exit 0; fi; echo "no required checks reported" >&2; exit 1 ;;
  "api repos/"*"/protection") cat "$F/protection.out" 2>/dev/null; exit "$(cat "$F/protection.rc" 2>/dev/null || echo 1)" ;;
  "pr merge") echo "$*" >> "$F/gh-merge.log"; MS_PR="$3" exec sh "$F/../merge-into.sh" "$@" ;;
  *) echo "stub gh: unhandled: $*" >&2; exit 1 ;;
esac
EOF
  chmod +x "$T_BIN/sleep" "$T_BIN/gh"
  printf '[{"databaseId":900,"status":"completed","conclusion":"success"}]\n' > "$MS_FIX/runs/default.1"
}
wg() { git -C "$W" "$@"; }
ms_branch() { wg fetch -q origin; wg checkout -q -B "$1" "origin/$MS_DEF"; }
ms_add() { printf '%s\n' "$2" >> "$W/$1"; wg add -A; wg commit -q -m "add $2"; }
ms_del() { grep -vxF "$2" "$W/$1" > "$W/$1.t"; mv "$W/$1.t" "$W/$1"; wg add -A; wg commit -q -m "delete $2"; }
ms_push() { wg push -q -f origin "$1" 2>/dev/null; }
ms_main() { wg fetch -q origin; wg checkout -q -B "$MS_DEF" "origin/$MS_DEF"; ms_add "$1" "$2"; wg push -q origin "$MS_DEF" 2>/dev/null; }
ms_pr() { # <n> <branch> [title]
  printf '%s\n' "$2" > "$MS_FIX/pr/$1.branch"; echo OPEN > "$MS_FIX/pr/$1.state"; printf '%s\n' "${3:-PR $1}" > "$MS_FIX/pr/$1.title"
}
ms_plan() { # <file> <pr…> — a plan for the world; $MS_PLAN_EXTRA is appended
  _f="$1"; shift
  { printf 'repo %s\ncheckout %s\n' "$MS_R" "$H"; [ -n "${MS_NOWF:-}" ] || echo "workflow governance.yml"; echo "tested ci/integration-test"; for _n in "$@"; do echo "pr $_n"; done; [ -z "${MS_PLAN_EXTRA:-}" ] || printf '%s\n' "$MS_PLAN_EXTRA"; } > "$_f"
}
ms_tip() { git --git-dir="$MS_BARE" rev-parse "refs/heads/$1"; }
ms_file() { # <ref> <path> — a file as the remote holds it
  git --git-dir="$MS_BARE" show "$1:$2" 2>/dev/null
}
ms_footprint() {
  git --git-dir="$MS_BARE" for-each-ref; git -C "$H" status --porcelain; git -C "$H" worktree list; git -C "$H" for-each-ref
  find "$HOME" -path "$HOME/.gitconfig" -prune -o -print | sort; cat "$MS_FIX"/pr/*.state
}
ms_mutates() { grep -cE '^(pr (merge|create|close)|run rerun)' "$MS_FIX/calls.log" || true; }
# A mutant: <label> <sed expr> — a copy of the tool with one line changed, in a tree shaped like the repo.
ms_mutant() {
  M="$T_TMP/mut"; rm -rf "$M"; mkdir -p "$M/bin" "$M/CONTRACTS"
  cp "$MS_INST"/bin/* "$M/bin/"
  cp "$T_ROOT/CONTRACTS/merge-stack-union.txt" "$MS_INST/CONTRACTS/required-checks.tsv" "$M/CONTRACTS/"
  sed "$2" "$T_ROOT/bin/gate-merge-stack.sh" > "$M/bin/gate-merge-stack.sh"
  t_exit "$1: the mutation applies" 1 cmp -s "$M/bin/gate-merge-stack.sh" "$T_ROOT/bin/gate-merge-stack.sh"
}
# The REAL merge-check beside the tool instead of the stub: it asks the stub gh for protection (403/404/200 per
# $MS_FIX/protection.{rc,out}) and for the PR's check rows ($MS_FIX/checks.tsv), and merges through the stub's `pr merge`.
ms_real_check() { cp "$T_ROOT/bin/merge-check.sh" "$T_ROOT/bin/ci-lost-job.sh" "$T_ROOT/bin/log-lib.sh" "$MS_INST/bin/"; }
