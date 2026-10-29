#!/usr/bin/env sh
# Sourced by the deploy-fleet suites after t_init. Two fake repos behind local bare remotes (url.insteadOf), no harbor file in
# either: acme/api deploys (default branch trunk; plan, apply, two verify, restore over a fake live dir), acme/web merges only.
# The tools run from an install dir, as §5b.9 installs them; `gh`, gate-merge-check.sh, gate-classify.sh and gate-queue.sh are stubs
# to the contract's CLI. fx_world builds it; fx_pr/fx_red/fx_main/fx_base build the night; fx_mutant copies the runner.
fx_inst() { # <dir> — the runner and merge-stack side by side, with a stub gate-merge-check.sh
  mkdir -p "$1/bin" "$1/contracts"
  cp "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/event-bus.sh" "$T_ROOT/bin/gate-merge-stack.sh" "$T_ROOT/bin/gate-merge-stack-resolve.py" \
    "$T_ROOT/bin/deploy-fleet.sh" "$T_ROOT/bin/scope-roots.sh" "$1/bin/"
  cp "$T_ROOT/contracts/roots.tsv" "$1/bin/roots.tsv"   # the installed runner finds the fleet file through scope-roots.sh (harbor#966)
  cp "$T_ROOT/contracts/merge-stack-union.txt" "$1/contracts/"
  : > "$1/contracts/required-checks.tsv"   # harbor's own rows, which name no acme repo (merge-stack reads them since #1126 r4)
  cat > "$1/bin/gate-merge-check.sh" <<'EOF'
#!/bin/sh
# stub merge-check: squash-merge the PR into the bare default branch, as GitHub does; refuses a --match-head-commit mismatch
n=''; mh=''; prev=''; for a in "$@"; do case "$prev" in --merge) n="$a" ;; --match-head-commit) mh="$a" ;; esac; prev="$a"; done
r="${HARBOR_SCOPE_REPO#*/}"; D="$SF/gh/acme_$r"; b="$(cat "$D/pr/$n.branch")"; echo "merge $r #$n" >> "$SF/merge.log"
m="$SF/merger-$r"; [ -d "$m" ] || git clone -q "https://github.com/acme/$r.git" "$m" 2>/dev/null
git -C "$m" fetch -q origin; db="$(git -C "$m" symbolic-ref --short refs/remotes/origin/HEAD)"; git -C "$m" checkout -q -B "${db#origin/}" "$db"
[ -z "$mh" ] || [ "$(git -C "$m" rev-parse "origin/$b")" = "$mh" ] || { echo "head moved" >&2; exit 1; }
git -C "$m" merge -q --squash "origin/$b" >/dev/null 2>&1 || { git -C "$m" reset -q --hard; exit 1; }
git -C "$m" commit -q -m "$(cat "$D/pr/$n.title") (#$n)" && git -C "$m" push -q origin "${db#origin/}" && echo MERGED > "$D/pr/$n.state"
[ ! -f "$SF/kill-after-merge" ] || touch "$CLAUDE_CONFIG_DIR/.harbor-autoship.off"
EOF
  chmod +x "$1/bin/gate-merge-check.sh"
}
fx_db() { case "$1" in api) echo trunk ;; *) echo main ;; esac; }
fx_world() {
  SF="$T_TMP/sf"; LIVE="$T_TMP/live"; P="$T_TMP/port"
  rm -rf "$SF" "$LIVE" "$P" "$T_TMP/wt" "$T_TMP/remotes" "$T_TMP/seed" "$HOME" "$CLAUDE_CONFIG_DIR" "$T_TMP/report" "$T_TMP/cache" "$T_TMP/events"
  mkdir -p "$SF/gh" "$LIVE" "$P" "$T_TMP/remotes" "$T_TMP/seed" "$HOME" "$CLAUDE_CONFIG_DIR/bin"
  HARBOR_FLEET_SNAPSHOT="$T_TMP/snap.json"; HARBOR_SCOPE_CACHE_DIR="$T_TMP/cache"; HARBOR_DEPLOY_FLEET_REPORT_DIR="$T_TMP/report"
  HARBOR_EVENT_DIR="$T_TMP/events"; HARBOR_DEPLOY_FLEET_NOW=1791327600   # 2026-10-07 02:00 +03
  export T_TMP SF LIVE HARBOR_FLEET_SNAPSHOT HARBOR_SCOPE_CACHE_DIR HARBOR_DEPLOY_FLEET_REPORT_DIR HARBOR_EVENT_DIR HARBOR_DEPLOY_FLEET_NOW
  git config --global user.name tester; git config --global user.email tester@example.invalid
  git config --global init.defaultBranch main; git config --global advice.detachedHead false
  printf 'ok\n' > "$LIVE/health.txt"; printf 'none\n' > "$LIVE/sha"
  fx_repo web 'repo acme/web
# merge-only: no deploy commands'
  fx_repo api 'repo acme/api
workflow ci.yml
plan sh ops/plan.sh
apply sh ops/apply.sh
verify sh ops/health.sh
verify sh ops/smoke.sh   # the second check
restore sh ops/deploy-restore.sh
deployed cat "$LIVE/sha"
timeout.verify 3'
  git -C "$P/api" worktree add -q "$P/.wt-api" -b side 2>/dev/null
  git clone -q https://github.com/acme/api.git "$P/.pi-upgrade-api" 2>/dev/null
  mkdir -p "$P/other"
  fx_snap "$P/api" "$P/web" "$P/.wt-api" "$P/.pi-upgrade-api" "$P/other"
  fx_stubs
}
fx_snap() { for _x in "$@"; do printf '%s\n' "$_x"; done | jq -R '{descriptor: {name: (split("/") | last), path: .}}' | jq -s . > "$HARBOR_FLEET_SNAPSHOT"; }
fx_repo() { # <name> <manifest>
  _b="$T_TMP/remotes/$1.git"; _w="$T_TMP/seed/$1"; _db="$(fx_db "$1")"
  git config --global url."$_b".insteadOf "https://github.com/acme/$1.git"
  git init -q --bare "$_b"; git --git-dir="$_b" symbolic-ref HEAD "refs/heads/$_db"
  git clone -q "https://github.com/acme/$1.git" "$_w" 2>/dev/null; git -C "$_w" checkout -q -B "$_db"
  mkdir -p "$_w/.agents" "$_w/ops" "$_w/src" "$SF/gh/acme_$1/pr" "$SF/gh/acme_$1/runs"
  printf '%s\n' "$2" > "$_w/.agents/ship.conf"
  printf '# glob\tclass\treason\nsecrets/*\tsecrets\tkeys\n' > "$_w/.agents/protected-paths.tsv"
  printf 'ok\n' > "$_w/health.txt"; echo seed > "$_w/src/seed.txt"
  cat > "$_w/ops/plan.sh" <<'EOF'
echo "plan $(git rev-parse --short HEAD) unattended=$SHIP_UNATTENDED repo=$SHIP_REPO dir=$(pwd)" >> "$SF/ops.log"
[ ! -f "$SF/kill-in-plan" ] || touch "$CLAUDE_CONFIG_DIR/.harbor-autoship.off"
[ ! -f PLAN_FAILS ]
EOF
  cat > "$_w/ops/apply.sh" <<'EOF'
echo "apply $(git rev-parse --short HEAD)" >> "$SF/ops.log"; [ ! -f APPLY_CRASHES ] || exit 3
n=$(( $(cat "$SF/snapn" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$SF/snapn"
mkdir -p "$SF/snaps/snap-$n"; cp -R "$LIVE/." "$SF/snaps/snap-$n/"; echo "snap-$n" > "$SHIP_SNAPSHOT"
[ ! -f "$SF/apply-stale" ] || echo snap-1 > "$SHIP_SNAPSHOT"
cp health.txt "$LIVE/health.txt"; git rev-parse HEAD > "$LIVE/sha"
EOF
  cat > "$_w/ops/health.sh" <<'EOF'
echo verify-health >> "$SF/ops.log"
[ ! -f "$SF/verify-hangs" ] || { rm -f "$SF/verify-hangs"; echo $$ > "$SF/verify.pid"; exec /bin/sleep 600; }
grep -qx ok "$LIVE/health.txt"
EOF
  printf 'echo verify-smoke >> "$SF/ops.log"; [ -s "$LIVE/sha" ]\n' > "$_w/ops/smoke.sh"
  cat > "$_w/ops/deploy-restore.sh" <<'EOF'
echo "restore $SHIP_SNAPSHOT_ID" >> "$SF/ops.log"; [ -d "$SF/snaps/$SHIP_SNAPSHOT_ID" ] || exit 1
rm -rf "${LIVE:?}"; mkdir -p "$LIVE"; cp -R "$SF/snaps/$SHIP_SNAPSHOT_ID/." "$LIVE/"
EOF
  git -C "$_w" add -A; git -C "$_w" commit -q -m seed; git -C "$_w" push -q origin "HEAD:$_db" 2>/dev/null
  git clone -q "https://github.com/acme/$1.git" "$P/$1" 2>/dev/null
}
fx_stubs() {
  cat > "$CLAUDE_CONFIG_DIR/bin/gate-classify.sh" <<'EOF'
#!/bin/sh
# stub classifier to contract §2: the register <root>/.agents/ship.conf names, plus the always-protected paths
root="$1"; shift; rc=0; echo "classify $root" >> "$SF/classify.log"
reg="$(awk '$1 == "protected" { print $2 }' "$root/.agents/ship.conf")"; reg="$root/${reg:-.agents/protected-paths.tsv}"
[ -f "$reg" ] || exit 2
if [ $# -gt 0 ]; then printf '%s\n' "$@"; else cat; fi > "$SF/classify.in"; cat "$SF/classify.in" >> "$SF/classify.seen"
while IFS= read -r p; do [ -n "$p" ] || continue; c=''
  case "$p" in .agents/ship.conf|.agents/protected-paths.tsv|.github/*) c=always ;; esac
  [ -n "$c" ] || c="$(awk -F'\t' -v p="$p" '!/^#/ && NF >= 2 { g = $1; gsub(/\./, "\\.", g); gsub(/\*/, ".*", g); if (p ~ ("^" g "$")) { print $2; exit } }' "$reg")"
  [ -z "$c" ] || { printf 'PROTECTED\t%s\t%s\n' "$p" "$c"; rc=1; }
done < "$SF/classify.in"
if [ -f "$SF/push-after-classify" ]; then   # the review's #1 attack: the head moves after it was judged
  read -r r b n < "$SF/push-after-classify"; rm -f "$SF/push-after-classify"; w="$T_TMP/seed/$r"
  git -C "$w" fetch -q origin; git -C "$w" checkout -q -B "$b" "origin/$b"; mkdir -p "$w/secrets"; echo hunter2 > "$w/secrets/key"
  git -C "$w" add -A; git -C "$w" commit -q -m sneak; git -C "$w" push -q origin "$b" 2>/dev/null
  git --git-dir="$T_TMP/remotes/$r.git" update-ref "refs/pull/$n/head" "$(git -C "$w" rev-parse HEAD)"
fi
exit $rc
EOF
  cat > "$CLAUDE_CONFIG_DIR/bin/gate-queue.sh" <<'EOF'
#!/bin/sh
# stub queue to contract §5b.9: add <kind> <owner/repo> <sha> [<pr>] --reason <text> → prints the id
[ "$1" = add ] || exit 2; k="$2"; r="$3"; s="$4"; p=''; [ "$5" = --reason ] || { p="$5"; shift; }; why="$6"
id="$k-$(echo "$r" | tr / _)${p:+-$p}-$(echo "$s" | cut -c1-12)"; q="$HOME/.local/state/harbor/approvals/queue.jsonl"; mkdir -p "${q%/*}"
grep -q "\"id\":\"$id\"" "$q" 2>/dev/null || jq -nc --arg i "$id" --arg k "$k" --arg r "$r" --arg s "$s" --arg p "$p" --arg w "$why" \
  '{id: $i, kind: $k, repo: $r, sha: $s, reason: $w} + (if $p == "" then {} else {pr: ($p | tonumber)} end)' >> "$q"
echo "$id"
EOF
  cat > "$T_BIN/sleep" <<'EOF'
#!/bin/sh
echo "sleep $*" >> "$SF/sleep.log"
EOF
  cat > "$T_BIN/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$SF/gh.log"
R=''; jqx=''; commit=''; label=''; prev=''
for a in "$@"; do case "$prev" in -R) R="$a" ;; --jq) jqx="$a" ;; --commit) commit="$a" ;; --label) label="$a" ;; esac; prev="$a"; done
D="$SF/gh/$(echo "$R" | tr / _)"; B="$T_TMP/remotes/${R#*/}.git"
emit() { if [ -n "$jqx" ]; then jq -r "$jqx"; else cat; fi; }
case "$1 $2" in
  "auth status") exit 0 ;;
  "repo view") jq -n --arg b "$(git --git-dir="$B" symbolic-ref --short HEAD)" '{defaultBranchRef: {name: $b}}' | emit ;;
  "pr view")
    n="$3"; br="$(cat "$D/pr/$n.branch")"; st="$(cat "$D/pr/$n.state")"; oid="$(git --git-dir="$B" rev-parse "refs/heads/$br")"
    [ ! -f "$D/pr/$n.reported" ] || oid="$(cat "$D/pr/$n.reported")"
    mg=UNKNOWN; case "$*" in *mergeable*) [ "$st" != OPEN ] || { p="$SF/probe-${R#*/}"; [ -d "$p" ] || git clone -q "https://github.com/$R.git" "$p" 2>/dev/null
      git -C "$p" fetch -q origin; git -C "$p" checkout -q --detach origin/HEAD
      if git -C "$p" merge -q --no-commit --no-ff "origin/$br" >/dev/null 2>&1; then mg=MERGEABLE; else mg=CONFLICTING; fi
      git -C "$p" merge --abort 2>/dev/null; git -C "$p" reset -q --hard; } ;; esac
    jq -n --arg s "$st" --arg t "$(cat "$D/pr/$n.title")" --arg b "$br" --arg o "$oid" --arg m "$mg" \
      '{state:$s,title:$t,headRefName:$b,headRefOid:$o,mergeable:$m}' | emit ;;
  "pr list") for f in "$D"/pr/*.state; do n="$(basename "$f" .state)"
      [ "$(cat "$f")" = OPEN ] && grep -qx "$label" "$D/pr/$n.labels" 2>/dev/null && echo "$n"; done | jq -R 'tonumber' | jq -s 'map({number: .})' | emit ;;
  "run list") if [ -f "$D/runs/$commit" ]; then cat "$D/runs/$commit"; else echo '[{"databaseId":900,"status":"completed","conclusion":"success","workflowName":"ci"}]'; fi | emit ;;
  "run watch") exit 0 ;;
  "run view") echo '{"conclusion":"success"}' | emit ;;
  *) echo "stub gh: unhandled: $*" >&2; exit 1 ;;
esac
EOF
  chmod +x "$CLAUDE_CONFIG_DIR/bin/gate-classify.sh" "$CLAUDE_CONFIG_DIR/bin/gate-queue.sh" "$T_BIN/sleep" "$T_BIN/gh"
}
fx_pr() { # <repo> <n> <file> <content> [label] — a PR branch pr-<n> off the default branch, its pull ref, its gh record
  _w="$T_TMP/seed/$1"; _d="$SF/gh/acme_$1"; _db="$(fx_db "$1")"
  git -C "$_w" fetch -q origin; git -C "$_w" checkout -q -B "pr-$2" "origin/$_db"
  mkdir -p "$(dirname "$_w/$3")"; printf '%s\n' "$4" > "$_w/$3"; git -C "$_w" add -A; git -C "$_w" commit -q -m "pr $2"
  git -C "$_w" push -q origin "+pr-$2" 2>/dev/null
  git --git-dir="$T_TMP/remotes/$1.git" update-ref "refs/pull/$2/head" "$(fx_tip "$1" "pr-$2")"
  echo "pr-$2" > "$_d/pr/$2.branch"; echo OPEN > "$_d/pr/$2.state"; echo "PR $2 on $1" > "$_d/pr/$2.title"
  printf '%s\n' "${5-ship:auto}" > "$_d/pr/$2.labels"
}
fx_red() { printf '[{"databaseId":777,"status":"completed","conclusion":"failure","workflowName":"ci"}]\n' > "$SF/gh/acme_$1/runs/$(fx_tip "$1" "pr-$2")"; }
fx_git() { # <repo> <message> <cmd…> — run cmd in a seed on the default branch, commit, push (an operator merge)
  _r="$1"; _m="$2"; shift 2; _w="$T_TMP/seed/$_r"; _db="$(fx_db "$_r")"
  git -C "$_w" fetch -q origin; git -C "$_w" checkout -q -B "$_db" "origin/$_db"
  ( cd "$_w" && "$@" ); git -C "$_w" add -A; git -C "$_w" commit -q -m "$_m"; git -C "$_w" push -q origin "$_db" 2>/dev/null
}
fx_main() { fx_git "$1" "main: $2" sh -c 'mkdir -p "$(dirname "$1")" && printf "%s\n" "$2" > "$1"' _ "$2" "$3"; }
fx_tip() { git --git-dir="$T_TMP/remotes/$1.git" rev-parse "refs/heads/${2:-$(fx_db "$1")}"; }
fx_sdir() { printf '%s/.helm-ship' "$(CDPATH= cd -P -- "$CLAUDE_CONFIG_DIR" && pwd -P)"; }
fx_sum() { jq -cS 'del(.sum)' | if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{ print $1 }'; }
fx_base() { # <repo> [sha] — record a deployed commit, sealed as the runner seals it, and the live install at it
  _s="${2:-$(fx_tip "$1")}"; mkdir -p "$(fx_sdir)"; _j="$(jq -n --arg r "acme/$1" --arg s "$_s" '{repo: $r, sha: $s, rolled_back: []}')"
  printf '%s' "$_j" | jq --arg m "$(printf '%s' "$_j" | fx_sum)" '.sum = $m' > "$(fx_sdir)/acme_$1.json"; printf '%s\n' "$_s" > "$LIVE/sha"
}
fx_state() { jq -r "$2" "$(fx_sdir)/acme_$1.json" 2>/dev/null; }
fx_merged() { cat "$SF/merge.log" 2>/dev/null | tr '\n' ' '; }
fx_ops() { cat "$SF/ops.log" 2>/dev/null | grep -c "^$1" || true; }
fx_tok() { # <owner/repo> <sha> — the one-shot token gate-approve.sh writes before it runs `deploy … --approved`
  _td="$(CDPATH= cd -P -- "$CLAUDE_CONFIG_DIR" && pwd -P)/.helm-approvals/approved"; mkdir -p "$_td"
  date > "$_td/deploy-$(echo "$1" | tr / _)-$(echo "$2" | cut -c1-12)"
}
ship() { # the runner as installed; an --approved call gets its token first, as gate-approve.sh gives it (FX_NO_TOKEN=1: none)
  case " $* " in *" --approved "*) [ "${FX_NO_TOKEN:-}" = 1 ] || fx_tok "$2" "$(printf '%s\n' "$@" | awk 'f { print; exit } $0 == "--sha" { f = 1 }')" ;; esac
  sh "${SHIP:-$T_TMP/inst/bin/deploy-fleet.sh}" "$@" > "$T_TMP/out" 2>&1; echo $?
}
fx_report() { cat "$T_TMP/report/REPORT.md" 2>/dev/null; }
fx_queue() { cat "$HOME/.local/state/harbor/approvals/queue.jsonl" 2>/dev/null; }
fx_later() { HARBOR_DEPLOY_FLEET_NOW=$((HARBOR_DEPLOY_FLEET_NOW + $1)); export HARBOR_DEPLOY_FLEET_NOW; }
# A mutant: <label> <sed expr> — the install dir again, with one line of the runner changed.
fx_mutant() {
  M="$T_TMP/mut"; rm -rf "${M:?}"; fx_inst "$M"
  sed "$2" "$T_ROOT/bin/deploy-fleet.sh" > "$M/bin/deploy-fleet.sh"
  t_exit "$1: the mutation applies" 1 cmp -s "$M/bin/deploy-fleet.sh" "$T_ROOT/bin/deploy-fleet.sh"
  SHIP="$M/bin/deploy-fleet.sh"
}
fx_inst "$T_TMP/inst"
