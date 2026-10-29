#!/usr/bin/env sh
# Sourced by the approval-gate suites (harbor#1018) after t_init. No network: `gh` is a stub answering from files under
# $GF, `sleep` a no-op, and the gate tools run as INSTALLED copies in the sandbox config dir, the only place they run.
# ag_world builds it: acme/widgets with a manifest and a register on main, PR 7 open at $SHA_A, CI green, checks pass.
AG_R=acme/widgets
SHA_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
SHA_B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
SHA_M=cccccccccccccccccccccccccccccccccccccccc
# The gate reads the account's own ~/.claude from the account database, never $HOME; where there is none (a fresh CI
# container, a stranger's clone) it cannot tell a sandbox from the real thing and proves ancestry in every case, so these
# suites passed only on a box that had run Claude Code. An empty dir is all it reads, left in place: siblings run in parallel.
_ag_live="$(eval "printf %s ~$(id -un)")/.claude"; [ -d "$_ag_live" ] || mkdir -p "$_ag_live"
ag_world() {
  GF="$T_TMP/gf";rm -rf "$GF" "$HOME/.local" "$CLAUDE_CONFIG_DIR"; export GF
  mkdir -p "$GF/contents/.agents" "$GF/pr" "$GF/compare" "$GF/runs" "$GF/watch" "$GF/checks" "$CLAUDE_CONFIG_DIR/bin"
  CFG="$(CDPATH='' cd -P -- "$CLAUDE_CONFIG_DIR" && pwd -P)"; GB="$CFG/bin"
  for f in library-log.sh library-fs.sh library-gate.sh gate-classify.sh gate-merge.sh gate-approve.sh gate-queue.sh gate-merge-check.sh event-bus.sh \
           gate-merge-stack.sh gate-merge-stack-resolve.py; do
    cp "$T_ROOT/bin/$f" "$GB/$f"
  done
  : > "$GB/required-checks.tsv"   # as runtime-install ships them beside merge-stack; harbor's own rows name no acme repo
  cp "$T_ROOT/contracts/merge-stack-union.txt" "$GB/"
  printf '%s\tCI gate\n' "$AG_R" > "$GF/contents/.agents/required-checks.tsv"
  jq -n --arg a "Bash($GB/gate-approve.sh *)" '{permissions: {ask: [$a], allow: [], deny: [], disableBypassPermissionsMode: "disable"}}' > "$CFG/settings.json"
  printf 'repo %s\nworkflow ci.yml\n' "$AG_R" > "$GF/contents/.agents/ship.conf"
  printf 'glob\tclass\treason\nbin/guard-*\tguard\tthe floor\nCONSTITUTION.md\tconstitution\tthe constitution\n' > "$GF/contents/.agents/protected-paths.tsv"
  echo OPEN > "$GF/pr/7.state"; echo "$SHA_A" > "$GF/pr/7.head"
  ag_files "$SHA_A" docs/a.md
  printf 'CI gate\tpass\t1m\thttps://example.invalid/run/1\n' > "$GF/checks/7"
  echo "$SHA_M" > "$GF/main.sha"
  HARBOR_EVENT_DIR="$T_TMP/bus"; export HARBOR_EVENT_DIR
  ag_stubs
}
ag_files() { # <sha> <path>… — what the compare of main...<sha> lists; `old=>new` is a rename
  _s="$1"; shift
  for _p in "$@"; do case "$_p" in
    *'=>'*) jq -n --arg o "${_p%%=>*}" --arg n "${_p#*=>}" '{filename: $n, previous_filename: $o, status: "renamed"}' ;;
    -*)     jq -n --arg n "${_p#-}" '{filename: $n, status: "removed"}' ;;
    *)      jq -n --arg n "$_p" '{filename: $n, status: "modified"}' ;;
  esac; done | jq -s '{files: .}' > "$GF/compare/$_s.json"
}
ag_stubs() {
  printf '#!/bin/sh\nexit 0\n' > "$T_BIN/sleep"
  cat > "$T_BIN/gh" <<'EOF'
#!/bin/sh
F="$GF"; printf '%s\n' "$*" >> "$F/calls.log"
jqx=''; prev=''; commit=''
for a in "$@"; do [ "$prev" = --jq ] && jqx="$a"; [ "$prev" = --commit ] && commit="$a"; prev="$a"; done
emit() { if [ -n "$jqx" ]; then jq -r "$jqx"; else cat; fi; }
case "$1 $2" in
  "auth status") exit 0 ;;
  "repo view") echo '{"defaultBranchRef":{"name":"main"}}' | emit ;;
  "pr view") n="$3"; jq -n --arg s "$(cat "$F/pr/$n.state")" --arg h "$(cat "$F/pr/$n.head")" \
      '{state: $s, baseRefName: "main", headRefOid: $h, mergeable: "MERGEABLE", title: "PR", headRefName: "feat"}' | emit ;;
  "pr checks") case " $* " in *" --required "*) echo "no required checks reported" >&2; exit 1 ;; esac   # no branch protection
      cat "$F/checks/$3"; grep -qv "	pass	" "$F/checks/$3" && exit 8; exit 0 ;;
  "pr merge") echo "$*" >> "$F/merge.log"; [ ! -f "$F/mergefail" ] || exit 1; echo MERGED > "$F/pr/$3.state" ;;
  "run list") k="$commit"; [ -f "$F/runs/$k" ] || k=default
      if [ -f "$F/runs/$k" ]; then cat "$F/runs/$k"; else echo '[{"databaseId":900,"status":"completed","conclusion":"success","workflowName":"ci"}]'; fi | emit ;;
  "run watch") exit "$(cat "$F/watch/$3" 2>/dev/null || echo 0)" ;;
  "run view") jq -n --arg c "$(cat "$F/view/$3" 2>/dev/null || echo success)" '{conclusion: $c}' | emit ;;
  "api -H") p="${4#repos/*/*/contents/}"; p="${p%%\?*}"; [ -f "$F/contents/$p" ] && cat "$F/contents/$p" ;;
  "api repos/"*)
    case "$2" in
      */compare/*) s="${2##*...}"; cat "$F/compare/$s.json" ;;
      */commits/*) jq -n --arg s "$(cat "$F/main.sha")" '{sha: $s}' | emit ;;
      */branches/*/protection) echo "HTTP 403: Upgrade to GitHub Pro" >&2; exit 1 ;;
      *) echo '{"default_branch":"main"}' | emit ;;
    esac ;;
  *) echo "stub gh: unhandled: $*" >&2; exit 1 ;;
esac
EOF
  chmod +x "$T_BIN/sleep" "$T_BIN/gh"
}
# GitHub's git side: a bare repo whose main holds $GF/contents, reached as https://github.com/$AG_R.git by the sandbox
# HOME's insteadOf. merge-stack fetches the required checks from it.
ag_origin() {
  _o="$GF/origin.git"; _w="$GF/origin-wt"; rm -rf "$_o" "$_w"
  git init -q --bare "$_o" && git -C "$_o" config uploadpack.allowFilter true
  cp -R "$GF/contents" "$_w" && git -C "$_w" init -q -b main && git -C "$_w" add -A \
    && git -C "$_w" -c user.name=t -c user.email=t@t commit -qm world && git -C "$_w" push -q "$_o" main
  git config --global "url.file://$_o.insteadOf" "https://github.com/$AG_R.git"
}
ag_run() { # <tool> <args…> → OUT, RC; stdin closed
  ag_origin
  _t="$1"; shift; RC=0
  ( cd "$T_TMP" && sh -c '"$0" "$@"' "$GB/$_t" "$@" ) >"$T_TMP/out" 2>&1 </dev/null || RC=$?
  OUT="$(cat "$T_TMP/out")"
}
ag_merged() { cat "$GF/merge.log" 2>/dev/null; }
ag_ledger() { cut -f2,3,5 "$CFG/.helm-approvals/ledger.tsv" 2>/dev/null; }
# A mutant: <label> <file> <sed expr> — the installed copy of <file> with one line changed.
ag_mutant() {
  sed "$3" "$T_ROOT/bin/$2" > "$GB/$2"
  t_exit "$1: the mutation applies" 1 cmp -s "$GB/$2" "$T_ROOT/bin/$2"
}
ag_restore() { cp "$T_ROOT/bin/$1" "$GB/$1"; }
# ag_tree <command text> — run it as Claude Code's Bash tool would (measured 2026-10-07): a process whose argv0 is
# `claude`, its child `/bin/bash -c "source <cfg>/shell-snapshots/… || true && eval '<text>' < /dev/null && pwd -P >|
# …-cwd"`. The fake claude is not Anthropic's signed binary, so even the canonical text stops at the identity check.
ag_tree() {
  ag_origin
  _q="$(printf '%s' "$1" | sed "s/'/'\"'\"'/g")"
  _in="source $CFG/shell-snapshots/snapshot-bash-1-ab12.sh 2>/dev/null || true && eval '$_q' < /dev/null && pwd -P >| $T_TMP/claude-ab12-cwd"
  printf '#!/bin/bash\nexec -a claude /bin/bash -c '"'"'/bin/bash -c "$1"; exit $?'"'"' claude-tree "$1"\n' > "$T_TMP/claude-tree.sh"
  RC=0; ( cd "$T_TMP" && /bin/bash "$T_TMP/claude-tree.sh" "$_in" ) >"$T_TMP/out" 2>&1 </dev/null || RC=$?
  OUT="$(cat "$T_TMP/out")"
}
