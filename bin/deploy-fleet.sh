#!/usr/bin/env sh
# deploy-fleet.sh (harbor#1060, harbor#1018) — the ship runner: merge and deploy opted-in fleet repos unattended,
# catch a bad deploy, restore it, and leave a morning report. Reached as `harbor ship`. Ship contract v1, §3 and §5.
#
#   night [--plan <file>]... [<owner/repo>...]   every fleet repo carrying .agents/ship.conf, or only those named
#   deploy <owner/repo> --sha <sha> [--approved]  one repo's deploy, the same verify and auto-restore
#
# A repo opts in with one file, .agents/ship.conf, read from origin's default branch, never the working tree; without
# it nothing about the repo is autonomous. Merges go through gate-merge-stack.sh, one PR per plan, pinned to the head
# that was classified; protected work is queued through gate-queue.sh, never applied unattended. Every manifest
# command is bounded. The flow, the manifest reference and every rail: docs/design/deploy-fleet.md.
# Exit: 0 nothing failed (queued, skipped red and a kill switch are not failures), 1 a problem was reported, 2 usage.
# Deliberately one file: night and deploy share the manifest reader, the deploy stage, the queue and the report.

case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH= cd -- "$HERE" && pwd)"
. "$HERE/log-lib.sh"
set -eu
log_init deploy-fleet
umask 077

usage() {
  cat <<'EOF'
usage: harbor ship night [--plan <file>]... [<owner/repo>...]
       harbor ship deploy <owner/repo> --sha <sha> [--approved]

  night    merge each opted-in repo's ready PRs (a --plan's, else the open PRs labelled ship:auto), then deploy
           the default branch's change since the last deployed commit; protected work is queued for approval
  deploy   one repo at <sha>: plan, apply, every verify, and restore on red. --approved is gate-approve.sh's
           alone: it lets a protected change through, and is refused when SHIP_UNATTENDED=1

The flow, the manifest (.agents/ship.conf) and the rails: docs/design/deploy-fleet.md
EOF
}
usage_err() { printf 'deploy-fleet: %s\n' "$1" >&2; usage >&2; exit 2; }

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CFG="$(CDPATH='' cd -P -- "$CFG" 2>/dev/null && pwd -P || printf '%s' "$CFG")"   # physical, as the gate's rules name it
KILL="$CFG/.harbor-autoship.off"                      # the contract's kill switch (§4)
CLASSIFY="$CFG/bin/gate-classify.sh"                 # contract v1.2 §5b.9: the installed names, verbatim
APPROVE="$CFG/bin/gate-approve.sh"
GQUEUE="$CFG/bin/gate-queue.sh"                       # the ONLY queue writer
# The trusted state (deployed shas, rolled-back commits, the night window) lives where a session cannot write it: the
# config dir's .helm-ship, an integrity surface the floor guards (#1127). Logs and the lock are not trusted, so stay out.
STATE="$CFG/.helm-ship"                               # <owner>_<name>.json per repo (§3), and last-rollback
WORK="$HOME/.local/state/harbor/ship"                 # the lock and the run logs
CACHE_DIR="${HARBOR_CACHE_DIR:-$HOME/.claude/cache}"
SNAP="${HARBOR_FLEET_SNAPSHOT:-$CACHE_DIR/fleet-snapshot.json}"
# the fleet file through the registry-aware reader beside this script (harbor#966)
FLEET="${HARBOR_FLEET_FILE:-$(sh "$HERE/roots.sh" --get HARBOR_FLEET_FILE 2>/dev/null || :)}"
ORCH="${HARBOR_ORCH_BIN:-$HOME/.local/bin/projects-orchestrator}"
GMS="$HERE/gate-merge-stack.sh"
NOW="${HARBOR_DEPLOY_FLEET_NOW:-$(date +%s)}"; case "$NOW" in ''|*[!0-9]*) NOW="$(date +%s)" ;; esac
NIGHT=57600                                           # a rollback stops every unattended run for 16 hours
TAB="$(printf '\t')"

SUB=''; SLUGS=''; PLANS=''; SHA=''; APPROVED=0
[ $# -gt 0 ] || usage_err "a sub-verb is required"
case "$1" in -h|--help|help) usage; exit 0 ;; night|deploy) SUB="$1"; shift ;; *) usage_err "unknown sub-verb $1" ;; esac
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --plan) [ "$SUB" = night ] && [ $# -ge 2 ] || usage_err "--plan <file> belongs to night"
            [ -f "$2" ] || usage_err "no plan file: $2"; PLANS="$PLANS$2$TAB"; shift ;;
    --sha) [ "$SUB" = deploy ] && [ $# -ge 2 ] || usage_err "--sha <sha> belongs to deploy"; SHA="$2"; shift ;;
    --approved) [ "$SUB" = deploy ] || usage_err "--approved belongs to deploy"; APPROVED=1 ;;
    -*) usage_err "unknown option $1" ;;
    *) case "$1" in */*/*|*[!A-Za-z0-9._/-]*|/*|*/) usage_err "a repo is owner/name: $1" ;; */*) ;; *) usage_err "a repo is owner/name: $1" ;; esac
       SLUGS="$SLUGS $1" ;;
  esac
  shift
done
# §5a.4: --approved is the approve tool's child, never an unattended run's
[ "$APPROVED" = 0 ] || [ "${SHIP_UNATTENDED:-}" != 1 ] || usage_err "--approved is refused when SHIP_UNATTENDED=1: only gate-approve.sh passes it"
if [ "$SUB" = deploy ]; then
  set -- $SLUGS; [ $# = 1 ] || usage_err "deploy takes exactly one <owner/repo>"
  case "$SHA" in '') usage_err "deploy needs --sha <sha>" ;; *[!0-9abcdef]*) usage_err "--sha is a hex commit id: $SHA" ;; esac
  [ "${#SHA}" -ge 7 ] || usage_err "--sha is a hex commit id: $SHA"
fi
command -v jq >/dev/null 2>&1 || { log_fail "jq is required"; log_fix "$(pkg_hint jq)"; log_end || :; exit 2; }
# The click's one-shot token (§5a.4, #1127): gate-approve.sh writes it under the guarded config dir and runs us; we
# take --approved only while it exists, and consume it, so a token is good for one deploy of one sha.
if [ "$APPROVED" = 1 ]; then
  set -- $SLUGS
  TOKEN="$CFG/.helm-approvals/approved/deploy-$(printf '%s' "$1" | tr / _)-$(printf '%s' "$SHA" | cut -c1-12)"
  [ -f "$TOKEN" ] || { log_fail "--approved without the approval token $TOKEN: only gate-approve.sh, after the operator's click, can pass it"
    log_fix "$CFG/bin/gate-approve.sh deploy $1 <sha>"; log_end || :; exit 2; }
  rm -f "${TOKEN:?}"
fi

iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
lday() { date -r "$1" "+$2" 2>/dev/null || date -d "@$1" "+$2"; }
REPORT_DIR="${HARBOR_DEPLOY_FLEET_REPORT_DIR:-$HOME/Deliverables/$(lday "$NOW" %Y-%m-%d)-ship}"
REPORT="$REPORT_DIR/REPORT.md"

# ── the run: one lock, one log dir (every command's output lands beside the log), one list per report section ──
mkdir -p "$STATE" "$WORK"
LOCK="$WORK/lock.d"
if ! mkdir "$LOCK" 2>/dev/null; then
  _op="$(cat "$LOCK/pid" 2>/dev/null || :)"
  if [ -n "$_op" ] && kill -0 "$_op" 2>/dev/null; then
    log_fail "another ship run holds $LOCK (pid $_op)"; log_fix "wait for it, or check: ps -p $_op"; log_end || :; exit 1
  fi
  rm -rf "$LOCK"; mkdir "$LOCK"
fi
echo $$ > "$LOCK/pid"
trap 'rm -rf "$LOCK"' EXIT
log_file "$WORK"; RUN="${LOG_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/ship.XXXXXX")}"
for _s in merged deployed rolledback red deferred queued problems notes; do : > "$RUN/$_s.md"; done
add() { printf -- '- %s\n' "$2" >> "$RUN/$1.md"; }               # <section> <line>
STOPPED=''; KILLED=0; SUBJECTS=''; CHILD=''; INFLIGHT=''; IN_ROLLBACK=0
problem() { add problems "$1"; log_fail "$1"; log_fix "$2"; SUBJECTS="$SUBJECTS $3"; }   # <what> <fix> <subject>

killed() { [ -e "$KILL" ]; }
kill_stop() { # → 0 when the kill switch is on (the run stops there)
  killed || return 1
  KILLED=1; STOPPED="the kill switch $KILL is on"; log_warn "stopped: $STOPPED"; return 0
}
night_stopped() { # → 0 when a rollback within the last 16 hours stops unattended work; an edited record stops it too
  [ -f "$STATE/last-rollback" ] || return 1
  _lr="$(cut -f1 "$STATE/last-rollback")"
  if [ "$(cut -f4 "$STATE/last-rollback")" != "$(cut -f1-3 "$STATE/last-rollback" | sha256)" ]; then case "$_lr" in ''|*[!0-9]*) _lr="$NOW" ;; esac
    STOPPED="the rollback record $STATE/last-rollback fails its checksum: edited outside the runner"
    SUBJECTS="$SUBJECTS state:rollback"; return 0; fi
  case "$_lr" in ''|*[!0-9]*) return 1 ;; esac
  [ $((NOW - _lr)) -lt "$NIGHT" ] || return 1
  STOPPED="a rollback at $(iso "$_lr") stopped the night ($(cut -f2,3 "$STATE/last-rollback" | tr '\t' ' '))"
  SUBJECTS="$SUBJECTS $(cut -f2 "$STATE/last-rollback"):rollback"; return 0   # the finding stays open while the night is stopped
}

# ── the manifest: `key value` lines, `#` a comment; a command keeps its own spacing ───────────────
mf() { # <manifest> <key> → every value, one per line
  awk -v k="$2" '/^[[:space:]]*#/ { next }
    { l = $0; sub(/^[[:space:]]+/, "", l); key = l; sub(/[[:space:]].*$/, "", key); if (key != k) next
      v = substr(l, length(key) + 1); sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+#.*$/, "", v); sub(/[[:space:]]+$/, "", v)
      if (v != "") print v }' "$1"
}
mf1() { mf "$1" "$2" | head -1; }
slug_of() { # <checkout> → owner/name from its origin url, as written (insteadOf is not applied)
  git -C "$1" config --get remote.origin.url 2>/dev/null | sed -E 's#(\.git)?/?$##; s#.*[:/]([^/:]+/[^/:]+)$#\1#'
}
sfile() { printf '%s/%s.json' "$STATE" "$(printf '%s' "$1" | tr / _)"; }
# Each state file carries .sum, the sha256 of the rest (jq -cS). It is not keyed: it catches an edit that did not
# recompute it (a hand edit, a sed, a stray tool), and the floor's guard on .helm-ship is what stops a deliberate one.
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{ print $1 }'; }
ssum() { jq -cS 'del(.sum)' "$1" 2>/dev/null | sha256; }
state_ok() { # <slug> → 0 when there is no state or it is the runner's own; 1 when it fails its checksum
  _sf="$(sfile "$1")"; [ -f "$_sf" ] || return 0
  [ "$(jq -r '.sum // empty' "$_sf" 2>/dev/null)" = "$(ssum "$_sf")" ]
}
sget() { [ -f "$(sfile "$1")" ] && state_ok "$1" && jq -r "$2 // empty" "$(sfile "$1")" 2>/dev/null || :; }
sput() { # <slug> <jq program> [jq args…] — rewrite the state through jq, then seal it with its sum
  _sf="$(sfile "$1")"; _jp="$2"; shift 2
  [ -f "$_sf" ] || printf '{"rolled_back":[]}\n' > "$_sf"
  jq "$@" "del(.sum) | $_jp" "$_sf" > "$_sf.tmp" && jq --arg s "$(jq -cS . "$_sf.tmp" | sha256)" '.sum = $s' "$_sf.tmp" > "$_sf.new" \
    && mv "$_sf.new" "$_sf" && rm -f "$_sf.tmp"
}

# ── the fleet: the snapshot's repos (as ci-runners.sh reads them), one main checkout each; opt-in is origin's ──
fleet() { # → $RUN/fleet.tsv: slug TAB checkout, one main checkout per origin repo (opt-in is read later, from origin)
  : > "$RUN/fleet.tsv"
  if [ -s "$SNAP" ] && jq -e 'type == "array"' "$SNAP" >/dev/null 2>&1; then cp "$SNAP" "$RUN/snap.json"
  elif [ -x "$ORCH" ] && "$ORCH" snapshot --fleet "$FLEET" --json > "$RUN/snap.json" 2>/dev/null; then :
  else problem "no fleet snapshot: $SNAP is absent and $ORCH did not answer" "$ORCH snapshot --fleet $FLEET --json" fleet; return 0; fi
  jq -r '.[] | .descriptor | select(.path != null and .name != null) | .path' "$RUN/snap.json" > "$RUN/paths" || :
  : > "$RUN/cands"
  while IFS= read -r _p <&3; do
    _gd="$(git -C "$_p" rev-parse --git-dir 2>/dev/null)" || continue
    # a linked worktree is never the main checkout, whatever it carries
    [ "$_gd" = "$(git -C "$_p" rev-parse --git-common-dir 2>/dev/null)" ] || continue
    _o="$(slug_of "$_p")"; case "$_o" in */*) ;; *) continue ;; esac
    printf '%s\t%s\n' "$_o" "$_p" >> "$RUN/cands"
  done 3< "$RUN/paths"
  for _r in $(cut -f1 "$RUN/cands" | sort -u); do
    _all="$(awk -F'\t' -v r="$_r" '$1 == r { print $2 }' "$RUN/cands")"
    _n="$(printf '%s\n' "$_all" | grep -c .)"
    [ "$_n" = 1 ] || _all="$(printf '%s\n' "$_all" | awk -v b="${_r#*/}" '{ n = $0; sub(/.*\//, "", n) } n == b')"
    if [ "$(printf '%s\n' "$_all" | grep -c .)" = 1 ]; then printf '%s\t%s\n' "$_r" "$_all" >> "$RUN/fleet.tsv"
    else add notes "$_r: skipped, more than one checkout and none is named ${_r#*/} ($(awk -F'\t' -v r="$_r" '$1 == r { printf "%s ", $2 }' "$RUN/cands")); name one in a plan's checkout line"; fi
  done
}

# ── the remote's truth (§5b.11): the default branch, the manifest and the register, from origin, never the tree ──
dbranch() { # <checkout> → the default branch origin's HEAD names
  git -C "$1" ls-remote --symref origin HEAD </dev/null 2>/dev/null | awk '$1 == "ref:" && $3 == "HEAD" { sub(/^refs\/heads\//, "", $2); print $2; exit }'
}
remote_root() { # <checkout> <ref> <dir> → <dir> holds the manifest and its register as <ref> has them; 1 when <ref> has no manifest
  _rd="${3:?}"; rm -rf "${_rd:?}"; mkdir -p "$_rd/.agents"
  git -C "$1" show "$2:.agents/ship.conf" > "$_rd/.agents/ship.conf" 2>/dev/null || { rm -rf "${_rd:?}"; return 1; }
  _rg="$(mf1 "$_rd/.agents/ship.conf" protected)"; _rg="${_rg:-.agents/protected-paths.tsv}"
  case "/$_rg/" in //*|*/../*|*/./*) return 0 ;; esac   # a register path no repo-relative read can trust: left absent, so classify refuses
  mkdir -p "$_rd/$(dirname "$_rg")"; git -C "$1" show "$2:$_rg" > "$_rd/$_rg" 2>/dev/null || rm -f "${_rd:?}/${_rg:?}"
}
open_repo() { # <slug> <checkout> → DB, MF and ROOTD from origin/<default branch>; 1 a problem (said), 2 it does not opt in
  DB="$(dbranch "$2")"
  case "$DB" in ''|*[!A-Za-z0-9._/-]*) problem "$1: cannot read the default branch from origin" "git -C $2 ls-remote --symref origin HEAD" "$1:fetch"; return 1 ;; esac
  git -C "$2" fetch -q origin "+refs/heads/$DB:refs/remotes/origin/$DB" </dev/null 2>/dev/null \
    || { problem "$1: cannot fetch origin/$DB" "git -C $2 fetch origin $DB" "$1:fetch"; return 1; }
  ROOTD="$RUN/$(printf '%s' "$1" | tr / _).root"; MF="$ROOTD/.agents/ship.conf"
  remote_root "$2" "origin/$DB" "$ROOTD" || return 2
  [ "$(mf1 "$MF" repo)" = "$1" ] || { problem "$1: the manifest on origin/$DB names repo $(mf1 "$MF" repo)" "fix repo in .agents/ship.conf on $DB" "$1:manifest"; return 1; }
}

# ── the classifier (§2), fail-closed: a path it cannot judge, or a classifier that cannot answer, is protected ──
paths() { # <checkout> <base> <head> → every changed path, a rename's old and new, a deletion's path; 1 when git cannot say
  [ -n "$2" ] && [ -n "$3" ] || return 1
  _d="$(git -C "$1" -c core.quotePath=false diff --name-status -M "$2" "$3")" || return 1
  [ -z "$_d" ] || printf '%s\n' "$_d" | awk -F'\t' '{ for (i = 2; i <= NF; i++) print $i }'
}
classify() { # <root from remote_root> <paths-file> → 0 none protected; 1 protected, WHY says which
  WHY=''
  if grep -q '^"' "$2"; then WHY="a path git had to quote: $(grep -m1 '^"' "$2")"; return 1; fi
  [ -x "$CLASSIFY" ] || { WHY="no classifier at $CLASSIFY"; return 1; }
  _cr=0; "$CLASSIFY" "$1" < "$2" > "$RUN/classify.out" 2>&1 || _cr=$?
  case "$_cr" in
    0) return 0 ;;
    1) WHY="protected: $(awk -F'\t' '$1 == "PROTECTED" { printf "%s%s (%s)", s, $2, $3; s = ", " }' "$RUN/classify.out")"; return 1 ;;
    *) WHY="the classifier failed (exit $_cr)"; return 1 ;;
  esac
}

# ── the queue (§4): one row per protected change, and an obligation that stays open until approve closes it ──
queue() { # <kind> <slug> <pr or -> <sha> <reason> — through gate-queue.sh, the only queue writer (§5b.9)
  if [ "$1" = merge ]; then _qc="$APPROVE merge $2 $3 $4"; else _qc="$APPROVE deploy $2 $4"; fi
  _qw="$2 $1$([ "$3" = - ] || printf ' #%s' "$3") at $(printf '%s' "$4" | cut -c1-12)"
  _qid=''
  if [ -x "$GQUEUE" ]; then
    if [ "$3" = - ]; then _qid="$("$GQUEUE" add "$1" "$2" "$4" --reason "$5" </dev/null 2>>"$RUN/queue.err" | tail -1)" || _qid=''
    else _qid="$("$GQUEUE" add "$1" "$2" "$4" "$3" --reason "$5" </dev/null 2>>"$RUN/queue.err" | tail -1)" || _qid=''; fi
  fi
  if [ -n "$_qid" ]; then add queued "$_qw — $5 — \`$_qc\` (queue id $_qid)"; log_note "queued for approval: $_qc ($5)"
  else problem "$_qw NOT queued: $5; $GQUEUE did not answer (log: $RUN/queue.err)" "$_qc" "$2:queue"; fi
}

# ── merge stage (§5.1–2, §5b.10): each PR through merge-stack on a plan of its own, pinned to the head classified ──
bg_run() { # <log> <command…> — in the background, so a signal reaches the trap at once instead of after the command
  _bl="$1"; shift; "$@" </dev/null > "$_bl" 2>&1 & CHILD=$!; _brc=0
  wait "$CHILD" || _brc=$?
  while kill -0 "$CHILD" 2>/dev/null; do _brc=0; wait "$CHILD" || _brc=$?; done
  CHILD=''; return "$_brc"
}
deferred() { # <slug> <pr> <log> — merge-stack found the head moved or behind: the next night classifies the new head
  add deferred "$1 #$2 needs a rebase onto $DB: left for the next night, when its new head is classified again (log: $3)"
  log_note "$1 #$2: needs-rebase, left for the next night"
}
merge_stage() { # <slug> <checkout> <plan or empty>   (DB, MF, ROOTD: open_repo's)
  _s="$1"; _h="$2"; _pl="$3"; _f="$(printf '%s' "$_s" | tr / _)"
  if [ -n "$_pl" ]; then _prs="$(mf "$_pl" pr | awk '{ print $1 }')"
  else _prs="$(gh pr list -R "$_s" --label ship:auto --state open --json number --jq '.[].number' </dev/null 2>"$RUN/$_f.prs.err")" \
      || { problem "$_s: gh could not list the ship:auto PRs" "gh pr list -R $_s --label ship:auto" "$_s:merge"; return 0; }
    _prs="$(printf '%s\n' "$_prs" | sort -n)"; fi
  [ -n "$_prs" ] || { log_note "$_s: no PR to merge"; return 0; }
  for _n in $_prs; do
    case "$_n" in *[!0-9]*) problem "$_s: a plan pr is not a number: $_n" "fix the plan" "$_s:merge"; continue ;; esac
    ! kill_stop || return 0
    _hd="$(gh pr view "$_n" -R "$_s" --json headRefOid --jq .headRefOid </dev/null 2>/dev/null || :)"
    _t="$(gh pr view "$_n" -R "$_s" --json title --jq .title </dev/null 2>/dev/null || :)"
    git -C "$_h" fetch -q origin "pull/$_n/head" </dev/null 2>/dev/null \
      || { problem "$_s #$_n: cannot fetch the PR head" "git -C $_h fetch origin pull/$_n/head" "$_s:merge"; continue; }
    case "$_hd" in *[!0-9abcdef]*) _hd='' ;; esac; [ "${#_hd}" = 40 ] || _hd=''   # the pin is always the full sha (a short one can be forged)
    [ -n "$_hd" ] && [ "$(git -C "$_h" rev-parse FETCH_HEAD)" = "$_hd" ] \
      || { problem "$_s #$_n: the fetched head is not the head GitHub reports (${_hd:-none}); not judged" "re-run tomorrow, or: gh pr view $_n -R $_s" "$_s:merge"; continue; }
    _p="$RUN/$_f-$_n.plan"
    { printf 'repo %s\ncheckout %s\npr %s head %s\n' "$_s" "$_h" "$_n" "$_hd"; _w="$(mf1 "$MF" workflow)"; [ -z "$_w" ] || printf 'workflow %s\n' "$_w"
      [ -z "$_pl" ] || mf "$_pl" after | awk -v n="$_n" '$1 == n { print "after " $0 }'; } > "$_p"
    _crc=0; bg_run "$_p.check" sh "$GMS" check "$_p" || _crc=$?
    if [ "$_crc" = 3 ]; then deferred "$_s" "$_n" "$_p.check"; continue; fi   # merge-stack: a pinned head that moved
    [ "$_crc" = 0 ] || { log_skip "$_s #$_n not ready (merge-stack check exit $_crc)"
      if [ "$_crc" = 1 ]; then add red "$_s #$_n — $(grep -m1 'FAIL:' "$_p.check" | sed 's/^ *FAIL: //') (log: $_p.check)"
      else problem "$_s #$_n: merge-stack check exited $_crc" "sh $GMS check $_p" "$_s:merge"; fi; continue; }
    paths "$_h" "$(git -C "$_h" merge-base "origin/$DB" "$_hd" 2>/dev/null || :)" "$_hd" > "$RUN/$_f-$_n.paths" \
      || { problem "$_s #$_n: cannot diff it against its merge-base" "git -C $_h diff origin/$DB...$_hd" "$_s:merge"; continue; }
    classify "$ROOTD" "$RUN/$_f-$_n.paths" || { queue merge "$_s" "$_n" "$_hd" "$WHY"; continue; }
    ! kill_stop || return 0
    log_head "merge $_s #$_n at $(printf '%s' "$_hd" | cut -c1-12)"
    _mrc=0; bg_run "$_p.merge" sh "$GMS" merge "$_p" || _mrc=$?
    if [ "$_mrc" = 0 ]; then add merged "$_s #$_n $_t (head $(printf '%s' "$_hd" | cut -c1-12))"; log_ok "$_s #$_n merged"
    elif [ "$_mrc" = 3 ]; then deferred "$_s" "$_n" "$_p.merge"
    else problem "$_s #$_n did not merge: $(grep 'FAIL:' "$_p.merge" | tail -1 | sed 's/^ *FAIL: //') (log: $_p.merge)" "sh $GMS merge $_p" "$_s:merge"; fi
  done
}

# ── deploy stage (§3, §5.3): change since the last deployed commit, gated, then plan, apply, verify, restore on red ──
# Every manifest command runs bounded (§5a.5): perl makes it a process-group leader, and on its timeout, or on a signal
# to the supervisor, the whole group is killed (TERM, then KILL 2 s later). Exit 124 is a timeout.
SUPERVISE='my $t = shift; my $p = fork; defined $p or exit 127;
if (!$p) { setpgrp(0, 0); exec @ARGV or exit 127 }
my $end = sub { kill "TERM", -$p; for (1 .. 20) { last unless kill 0, -$p; select(undef, undef, undef, 0.1) }
  kill "KILL", -$p; waitpid($p, 0) };
$SIG{ALRM} = sub { $end->(); exit 124 }; $SIG{TERM} = $SIG{INT} = $SIG{HUP} = sub { $end->(); exit 143 };
alarm $t; waitpid($p, 0); my $s = $?; alarm 0; exit($s & 127 ? 128 + ($s & 127) : $s >> 8)'
tmo() { # <cmd> <default> → the manifest's timeout.<cmd> in whole seconds, else the default
  _tv="$(mf1 "$MF" "timeout.$1")"; case "$_tv" in ''|*[!0-9]*) _tv="$2" ;; esac
  [ "$_tv" -ge 1 ] 2>/dev/null && [ "$_tv" -le 86400 ] || _tv="$2"; printf '%s' "$_tv"
}
run_cmd() { # <checkout> <log> <seconds> <command> [snapshot id] — sh -c in the main checkout, bounded, with the contract's env
  ( cd "$1" && exec env SHIP_UNATTENDED=1 SHIP_REPO="$DS" SHIP_SNAPSHOT="$SNAPF" ${5:+"SHIP_SNAPSHOT_ID=$5"} \
      perl -e "$SUPERVISE" "$3" sh -c "$4" ) </dev/null > "$2" 2>&1 &
  CHILD=$!; _xrc=0
  wait "$CHILD" || _xrc=$?
  while kill -0 "$CHILD" 2>/dev/null; do _xrc=0; wait "$CHILD" || _xrc=$?; done   # a trapped signal ended the wait, not the command
  CHILD=''
  [ "$_xrc" != 124 ] || printf '\ndeploy-fleet: timed out after %ss, its process group killed\n' "$3" >> "$2"
  return "$_xrc"
}
verify_all() { # <checkout> <log prefix> → 0 all green; FIRST_RED names the first that was not
  FIRST_RED=''; _vi=0; _vr=0; _vt="$(tmo verify 600)"
  while IFS= read -r _v <&4; do
    _vi=$((_vi + 1)); _vc=0
    run_cmd "$1" "$2.verify-$_vi.log" "$_vt" "$_v" || _vc=$?
    if [ "$_vc" = 0 ]; then log_ok "$DS verify $_vi: $_v"; continue; fi
    _vr=1; _vw="$([ "$_vc" = 124 ] && printf 'timed out after %ss' "$_vt" || printf 'exit %s' "$_vc")"
    log_warn "$DS verify $_vi red ($_vw): $_v (log: $2.verify-$_vi.log)"
    [ -n "$FIRST_RED" ] || FIRST_RED="\`$_v\` $_vw (log: $2.verify-$_vi.log)"
  done 4<<EOF
$(mf "$MF" verify)
EOF
  return "$_vr"
}
record_deployed() { # <slug> <sha> <snapshot> — the baseline moves only here, after every verify passed
  sput "$1" '.repo = $r | .sha = $s | .ts = $t | .snapshot = $n' --arg r "$1" --arg s "$2" --arg t "$(iso "$NOW")" --arg n "$3"
}
record_rollback() { # <slug> <sha> <check>
  sput "$1" '.repo = $r | .rolled_back = ((.rolled_back // []) + [{sha: $s, ts: $t, check: $c}])' --arg r "$1" --arg s "$2" --arg t "$(iso "$NOW")" --arg c "$3"
  _lrl="$(printf '%s\t%s\t%s' "$NOW" "$1" "$2")"
  printf '%s\t%s\n' "$_lrl" "$(printf '%s\n' "$_lrl" | sha256)" > "$STATE/last-rollback"
}
read_snapshot() { # <file> → the id apply wrote, if it is one plain token
  _id="$(head -1 "$1" 2>/dev/null | tr -d '\r' || :)"; case "$_id" in ''|*[!A-Za-z0-9._:/@+-]*) ;; *) printf '%s' "$_id" ;; esac
}
take_snapshot() { # SID ← this run's id; one equal to the id an earlier run recorded is refused (§5b.13)
  SID="$(read_snapshot "$SNAPF")"; STALE=''
  [ -n "$SID" ] && [ "$SID" = "$(sget "$DS" .snapshot)" ] || return 0
  STALE="apply reported $SID, the snapshot an earlier run recorded, so it is not this run's"; log_warn "$DS: $STALE"; SID=''
}
rollback() { # <checkout> <sha> <why> — restore THIS run's snapshot, verify again, stop the night
  _rh="$1"; _rs="$2"; _rwhy="$3"; _rlog="$RUN/$(printf '%s' "$DS" | tr / _)"; INFLIGHT=''; IN_ROLLBACK=1
  STOPPED="$DS was rolled back"
  record_rollback "$DS" "$_rs" "$_rwhy"
  if [ -z "$SID" ]; then
    problem "$DS at $(printf '%s' "$_rs" | cut -c1-12): $_rwhy, and ${STALE:-apply wrote no snapshot id this run}: NOT restored" \
      "restore by hand from the repo's own snapshots; nothing older is restored automatically" "$DS:rollback"
    add rolledback "$DS $(printf '%s' "$_rs" | cut -c1-12) — failing: $_rwhy — snapshot: none from this run, NOT restored${STALE:+ ($STALE)} — log: $LOG_PATH"
    IN_ROLLBACK=0; return 0
  fi
  _rrc=0; run_cmd "$_rh" "$_rlog.restore.log" "$(tmo restore 1800)" "$(mf1 "$MF" restore)" "$SID" || _rrc=$?
  _rv=green; verify_all "$_rh" "$_rlog.after-restore" || _rv="red: $FIRST_RED"
  _rr="$([ "$_rrc" = 0 ] && echo ok || { [ "$_rrc" = 124 ] && echo 'TIMED OUT' || echo "FAILED, exit $_rrc"; })"
  add rolledback "$DS $(printf '%s' "$_rs" | cut -c1-12) — failing: $_rwhy — snapshot: $SID — restore: $_rr ($_rlog.restore.log) — verify after restore: $_rv — log: $LOG_PATH"
  problem "$DS at $(printf '%s' "$_rs" | cut -c1-12) rolled back to snapshot $SID (restore $_rr): $_rwhy; after restore verify is $_rv" \
    "$APPROVE deploy $DS <sha> once fixed; the night stays stopped for 16 hours" "$DS:rollback"
  IN_ROLLBACK=0
}
deploy_stage() { # <slug> <checkout> <sha or empty> <approved>   (DB, MF: open_repo's, read from origin/<default branch>)
  DS="$1"; _h="$2"; _want="$3"; _ap="$4"; SID=''; SNAPF=''; STALE=''
  _apply="$(mf1 "$MF" apply)"
  [ -n "$_apply" ] || { add notes "$DS: merge-only (no apply in its manifest): no deploy stage"; log_note "$DS: merge-only"; return 0; }
  if [ "$_ap" = 0 ]; then ! kill_stop || return 0; ! night_stopped || { log_warn "$DS: $STOPPED"; return 0; }; fi
  command -v perl >/dev/null 2>&1 || { problem "$DS: perl is missing, so no manifest command can be bounded; not deployed" "install perl" "$DS:checkout"; return 0; }
  [ "$(git -C "$_h" branch --show-current)" = "$DB" ] && [ -z "$(git -C "$_h" status --porcelain --untracked-files=no)" ] \
    || { problem "$DS: $_h is not a clean $DB checkout; not deployed" "git -C $_h status" "$DS:checkout"; return 0; }
  git -C "$_h" merge -q --ff-only "origin/$DB" </dev/null >/dev/null 2>&1 \
    || { problem "$DS: cannot fast-forward $_h to origin/$DB; not deployed" "git -C $_h pull --ff-only" "$DS:checkout"; return 0; }
  _sha="$(git -C "$_h" rev-parse HEAD)"
  [ "$_sha" = "$(git -C "$_h" rev-parse "origin/$DB")" ] \
    || { problem "$DS: $_h holds commits origin/$DB does not; not deployed" "git -C $_h log origin/$DB..HEAD" "$DS:checkout"; return 0; }
  if [ -n "$_want" ]; then
    case "$_sha" in "$_want"*) ;; *) problem "$DS: $DB is at $(printf '%s' "$_sha" | cut -c1-12), not $_want; not deployed" "approve the sha $DB is at now" "$DS:sha"; return 0 ;; esac
  fi
  if ! state_ok "$DS"; then
    problem "$DS: its deployed-sha state $(sfile "$DS") fails its checksum: edited outside the runner" "inspect it; an approved deploy rewrites it" "$DS:state"
    [ "$_ap" = 1 ] || { queue deploy "$DS" - "$_sha" "the deployed-sha state fails its checksum, so no baseline can be trusted"; return 0; }
  fi
  _base="$(sget "$DS" .sha)"; _short="$(printf '%s' "$_sha" | cut -c1-12)"; _l="$RUN/$(printf '%s' "$DS" | tr / _)"; _bwhy=''
  # The recorded sha is trusted only while the live install agrees (the manifest's `deployed`): a restore outside the
  # runner undoes a deploy without telling it, and a protected change would then look deployed already.
  _dcmd="$(mf1 "$MF" deployed)"
  if [ -n "$_base" ] && [ -n "$_dcmd" ]; then
    _drc=0; run_cmd "$_h" "$_l.deployed.log" "$(tmo deployed 60)" "$_dcmd" || _drc=$?
    _live="$(awk 'NF { print $1; exit }' "$_l.deployed.log")"; case "$_live" in *[!0-9abcdef]*) _live='' ;; esac
    [ "$_drc" = 0 ] && [ "${#_live}" -ge 7 ] || _live=''
    if [ -z "$_live" ] || [ "${_base#"$_live"}" = "$_base" ]; then
      _bwhy="the live install is at ${_live:-an unreadable commit}, not the recorded $(printf '%s' "$_base" | cut -c1-12): changed outside the runner (a manual restore?), so the baseline is not trusted"
      log_warn "$DS: $_bwhy"; _base=''
    fi
  fi
  [ "$_base" != "$_sha" ] || { add notes "$DS: $_short is already deployed"; log_ok "$DS: $_short already deployed"; return 0; }
  _gate=''
  [ -n "$(mf1 "$MF" verify)" ] && [ -n "$(mf1 "$MF" restore)" ] || _gate="the manifest has no verify or no restore: every deploy waits for a click"
  [ -n "$_gate" ] || [ -n "$_base" ] || _gate="${_bwhy:-no deployed commit is recorded yet: the first deploy sets the baseline}"
  if [ -z "$_gate" ] && ! git -C "$_h" merge-base --is-ancestor "$_base" "$_sha" 2>/dev/null; then _gate="the last deployed commit $(printf '%s' "$_base" | cut -c1-12) is not an ancestor of $DB"; fi
  if [ -z "$_gate" ]; then
    for _rb in $(sget "$DS" '.rolled_back[]?.sha'); do
      git -C "$_h" merge-base --is-ancestor "$_rb" "$_sha" 2>/dev/null && ! git -C "$_h" merge-base --is-ancestor "$_rb" "$_base" 2>/dev/null \
        && { _gate="it contains $(printf '%s' "$_rb" | cut -c1-12), which was rolled back: never applied unattended again"; break; }
    done
  fi
  if [ -z "$_gate" ]; then
    paths "$_h" "$_base" "$_sha" > "$RUN/deploy.paths" && classify "$ROOTD" "$RUN/deploy.paths" || _gate="${WHY:-cannot diff $_base..$_sha}"
  fi
  if [ -n "$_gate" ]; then
    [ "$_ap" = 0 ] || { log_note "$DS: approved, so it goes ahead although $_gate"; _gate=''; }
    [ -z "$_gate" ] || { queue deploy "$DS" - "$_sha" "$_gate"; return 0; }
  fi
  _plan="$(mf1 "$MF" plan)"
  log_head "deploy $DS ${_base:+$(printf '%s' "$_base" | cut -c1-12)..}$_short"
  if [ -n "$_plan" ]; then
    _prc=0; run_cmd "$_h" "$_l.plan.log" "$(tmo plan 600)" "$_plan" || _prc=$?
    [ "$_prc" = 0 ] || { problem "$DS at $_short: the deploy plan failed (exit $_prc), nothing applied (log: $_l.plan.log)" "cd $_h && $_plan" "$DS:plan"; return 0; }
  fi
  [ "$_ap" = 1 ] || ! kill_stop || return 0
  SNAPF="$(mktemp "$RUN/snapshot.XXXXXX")"          # fresh and empty: restore can only ever see this run's id
  INFLIGHT="$_h$TAB$_sha"                            # from here a signal restores (on_signal)
  _arc=0; run_cmd "$_h" "$_l.apply.log" "$(tmo apply 1800)" "$_apply" || _arc=$?
  take_snapshot
  [ "$_arc" = 0 ] || { rollback "$_h" "$_sha" "apply $([ "$_arc" = 124 ] && echo 'timed out' || echo "exited $_arc") (log: $_l.apply.log)"; return 0; }
  if verify_all "$_h" "$_l"; then
    INFLIGHT=''
    record_deployed "$DS" "$_sha" "$SID"
    add deployed "$DS ${_base:+$(printf '%s' "$_base" | cut -c1-12)..}$_short (snapshot ${SID:-none})$([ "$_ap" = 0 ] || printf ' — approved')"
    log_ok "$DS deployed $_short"
  else rollback "$_h" "$_sha" "$FIRST_RED"; fi
}

# ── a signal: kill the running command's group, restore if an apply started, report, stop ──────────────────
on_signal() {
  if [ "$IN_ROLLBACK" = 1 ]; then log_warn "a signal arrived during a restore: the restore finishes first"; return 0; fi
  trap '' INT TERM HUP
  [ -z "$CHILD" ] || { kill -TERM "$CHILD" 2>/dev/null || :; wait "$CHILD" 2>/dev/null || :; }; CHILD=''
  log_warn "interrupted by a signal"
  if [ -n "$INFLIGHT" ]; then
    take_snapshot; rollback "${INFLIGHT%%"$TAB"*}" "${INFLIGHT#*"$TAB"}" "the run was interrupted by a signal during apply or verify"
  else problem "the run was interrupted by a signal" "re-run: harbor ship $SUB$SLUGS" "signal"; fi
  STOPPED="${STOPPED:-interrupted by a signal}"
  finish || :
  exit 143
}
trap on_signal INT TERM HUP

# ── the report, the checks.log line and the receipt ──────────────────────────────────────────────
section() { [ ! -s "$RUN/$2.md" ] || { printf '\n### %s\n\n' "$1"; cat "$RUN/$2.md"; }; }   # an empty section is left out
finish() {
  mkdir -p "$REPORT_DIR"
  { [ -s "$REPORT" ] || printf '# Ship report — %s\n\nOne section per run of `harbor ship`, newest last.\n' "$(lday "$NOW" %Y-%m-%d)"
    printf '\n## %s %s\n\n' "$(lday "$NOW" %H:%M)" "ship $SUB$SLUGS"
    printf -- '- stopped: %s\n- log: %s\n' "${STOPPED:-no}" "${LOG_PATH:-none}"
    cat "$RUN"/merged.md "$RUN"/deployed.md "$RUN"/rolledback.md "$RUN"/red.md "$RUN"/queued.md "$RUN"/problems.md | grep -q . || echo '- nothing to merge, deploy or approve' 
    section Merged merged; section Deployed deployed; section 'Rolled back' rolledback; section 'Skipped red' red
    section 'Waiting for the next night (needs a rebase)' deferred
    section 'Queued for approval (run each command to approve)' queued; section Problems problems; section Notes notes
  } >> "$REPORT"
  _c() { grep -c . "$RUN/$1.md" || :; }
  SUBJECTS="$(printf '%s\n' $SUBJECTS | sort -u | tr '\n' ' ')"; SUBJECTS="${SUBJECTS% }"
  _st=green; [ "$KILLED" = 0 ] || _st=stood-down; [ -z "$SUBJECTS" ] || _st=red
  mkdir -p "$CACHE_DIR"
  printf '[check:ship] %s %s %s: merged %s, deployed %s, rolled back %s, skipped red %s, queued %s, problems %s%s; report %s\n' \
    "$(iso "$NOW")" "$_st" "$SUB" "$(_c merged)" "$(_c deployed)" "$(_c rolledback)" "$(_c red)" "$(_c queued)" "$(_c problems)" \
    "${STOPPED:+; stopped: $STOPPED}" "$REPORT" >> "$CACHE_DIR/checks.log" 2>/dev/null || :
  # shellcheck disable=SC2086
  log_receipt "$(receipt_dir)" ship "$_st" $([ "$_st" != stood-down ] || echo stood-down) $SUBJECTS || log_warn "could not write the ship receipt"
  log_note "report: $REPORT"
  log_end
}

# ── night and deploy ───────────────────────────────────────────────────────────────────────────
cmd_deploy() {
  set -- $SLUGS; _s="$1"
  fleet; _h="$(awk -F'\t' -v r="$_s" '$1 == r { print $2; exit }' "$RUN/fleet.tsv")"
  [ -n "$_h" ] || { problem "$_s has no main checkout in the fleet" "refresh the fleet snapshot" "$_s:fleet"; return 0; }
  if [ "$APPROVED" = 0 ] && night_stopped; then log_warn "$STOPPED"; return 0; fi
  _orc=0; open_repo "$_s" "$_h" || _orc=$?
  [ "$_orc" != 2 ] || problem "$_s does not opt in: origin's default branch carries no .agents/ship.conf" "add .agents/ship.conf to $_s" "$_s:fleet"
  [ "$_orc" = 0 ] || return 0
  deploy_stage "$_s" "$_h" "$SHA" "$APPROVED"
}
cmd_night() {
  ! kill_stop || return 0
  ! night_stopped || { log_warn "$STOPPED"; return 0; }
  : > "$RUN/fleet.tsv"; [ -z "$SLUGS" ] && [ -n "$PLANS" ] || fleet   # plans alone name their checkouts
  : > "$RUN/run.tsv"
  _old="$IFS"; IFS="$TAB"; set -- $PLANS; IFS="$_old"
  for _pl in "$@"; do
    _r="$(mf1 "$_pl" repo)"; _c="$(mf1 "$_pl" checkout)"
    if [ -n "$_r" ] && [ -d "$_c" ] && [ "$(slug_of "$_c")" = "$_r" ]; then printf '%s\t%s\t%s\tnamed\n' "$_r" "$_c" "$_pl" >> "$RUN/run.tsv"
    else problem "plan $_pl: its checkout must be a clone of its repo" "check repo and checkout in $_pl" "${_r:-plan}:plan"; fi
  done
  for _r in $SLUGS; do
    awk -F'\t' -v r="$_r" '$1 == r { f = 1 } END { exit !f }' "$RUN/run.tsv" && continue
    _c="$(awk -F'\t' -v r="$_r" '$1 == r { print $2; exit }' "$RUN/fleet.tsv")"
    [ -n "$_c" ] && printf '%s\t%s\t-\tnamed\n' "$_r" "$_c" >> "$RUN/run.tsv" \
      || problem "$_r has no main checkout in the fleet" "refresh the fleet snapshot, or name its checkout in a plan" "$_r:fleet"
  done
  [ -n "$SLUGS$PLANS" ] || awk -F'\t' '{ print $1 "\t" $2 "\t-\tfleet" }' "$RUN/fleet.tsv" > "$RUN/run.tsv"
  while IFS="$TAB" read -r _r _c _pl _how <&3; do
    if [ -n "$STOPPED" ]; then add notes "$_r: not reached, the night stopped"; continue; fi
    _orc=0; open_repo "$_r" "$_c" || _orc=$?
    if [ "$_orc" = 2 ]; then
      [ "$_how" = fleet ] || problem "$_r does not opt in: origin's default branch carries no .agents/ship.conf" "add .agents/ship.conf to $_r" "$_r:fleet"
      continue
    fi
    [ "$_orc" = 0 ] || continue
    log_head "$_r ($_c, $DB)"
    [ "$_pl" != - ] || _pl=''   # a tab is IFS white space, so an empty field would collapse: "-" stands for none
    merge_stage "$_r" "$_c" "$_pl"
    [ -z "$STOPPED" ] || continue
    _orc=0; open_repo "$_r" "$_c" || _orc=$?        # the merges moved origin: the deploy reads the manifest it will deploy
    if [ "$_orc" = 0 ]; then deploy_stage "$_r" "$_c" '' 0; fi
  done 3< "$RUN/run.tsv"
}

log_head "ship $SUB$SLUGS"
if [ "$SUB" = night ]; then cmd_night; else cmd_deploy; fi
finish
