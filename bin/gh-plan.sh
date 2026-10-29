#!/usr/bin/env sh
# gh-plan.sh (harbor#1060) — has the GitHub account's plan changed, or has branch protection become unreadable?
#
#   sh gh-plan.sh            read the plan and main's protection, write cache/gh-plan.json, one checks.log line per CHANGE
#   sh gh-plan.sh --print    the same reads, writes nothing: plan, gate, what is acknowledged
#   sh gh-plan.sh ack        a person accepts the state now read as normal; the statusline alarm clears until it changes again
#
# WHY. On 2026-10-05 the account fell from Pro to Free. Private-repo protection then answers 403, GitHub enforces no
# required check, and runner-switch's allowance dropped 1,000 minutes. Nothing said so: it surfaced only because a
# merge was refused. This reads the two facts every tick and says so the first time they move.
#
# THE FACTS. plan = `gh api user` .plan.name. gate = what merge-check.sh gates merges on, from
# repos/<repo>/branches/main/protection: `github` (readable, requires checks), `weak` (readable, requires none),
# `local` (HTTP 403, a private repo on a free plan: merge-check falls back to CONTRACTS/required-checks.tsv),
# `absent` (404). Any other answer is UNREAD and changes nothing.
# THE ALARM is the state against the ACKNOWLEDGED one (default pro + github, the state Harbor was built on): it holds
# until a person runs `ack`, so a downgrade is never wallpaper the box decided was fine.
# FINDINGS: `[check:gh-plan]` lines in cache/checks.log, one per change of plan or gate (and one on a first read, so a
# box that is already degraded says so once), one on the way into an unread state; never one per tick.
# Run by fleet-snapshot-refresh.sh every 300s. Reads no billing. POSIX sh, jq, gh (HARBOR_GH swaps in a fake).
set -eu
. "$(dirname -- "$0")/log-lib.sh"
log_init gh-plan

case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
MODE=run
case "${1:-}" in
  --print) MODE=print ;;
  ack) MODE=ack ;;
  "") ;;
  *) log_fail "unknown option $1"; log_fix "sh $0 --help"; exit 2 ;;
esac

REPO="${HARBOR_PLAN_REPO:-$(repo_slug)}"   # harbor's own OWNER/NAME (harbor#1149); empty is an unread below
BRANCH=main
CACHE_DIR="${HARBOR_CACHE_DIR:-$HOME/.claude/cache}"
OUT="$CACHE_DIR/gh-plan.json"
LOG="$CACHE_DIR/checks.log"
NOW="${HARBOR_NOW:-$(date +%s)}"
GH="${HARBOR_GH:-gh}"
command -v jq >/dev/null 2>&1 || { log_fail "jq is required"; log_fix "$(pkg_hint jq)"; exit 2; }
case "$NOW" in ''|*[!0-9]*) NOW="$(date +%s)" ;; esac
iso() { date -u -r "$NOW" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$NOW" +%Y-%m-%dT%H:%M:%SZ; }
logline() { [ "$MODE" = print ] || printf '[check:gh-plan] %s %s\n' "$(iso)" "$1" >> "$LOG" 2>/dev/null || :; }
mkdir -p "$CACHE_DIR"

# the previous reading and what a person accepted; absent or unparsable is no previous reading
PREV='{}'
[ -f "$OUT" ] && jq -e 'type == "object"' "$OUT" >/dev/null 2>&1 && PREV="$(jq -c . "$OUT")"
ACK="$(printf '%s' "$PREV" | jq -c '.ack // {plan: "pro", gate: "github"}')"

save() { # <json> — atomic
  printf '%s\n' "$1" > "$OUT.tmp.$$" && mv -f "$OUT.tmp.$$" "$OUT" || { rm -f "$OUT.tmp.$$"; exit 1; }
}
unread() { # <what>
  log_warn "$1 did not answer; nothing changed"; log_fix "gh auth status"
  [ "$MODE" = run ] || exit 2
  save "$(printf '%s' "$PREV" | jq -c --argjson now "$NOW" --argjson ack "$ACK" '. + {at: $now, unread: true, ack: $ack}')"
  [ "$(printf '%s' "$PREV" | jq -r '.unread // false')" = true ] || logline "$1 did not answer; plan and gate not judged (the next good read clears this)"
  exit 0
}

# ── the two facts ─────────────────────────────────────────────────────────────────────────────
PLAN="$("$GH" api user --jq '.plan.name' 2>/dev/null || true)"
PLAN="$(printf '%s' "$PLAN" | tr -d ' \r\n' | tr 'A-Z' 'a-z')"
case "$PLAN" in ''|*[!abcdefghijklmnopqrstuvwxyz0-9_-]*) unread "the plan read (gh api user)" ;; esac

[ -n "$REPO" ] || unread "the repository name (no origin in this checkout, no repo-slug.txt beside this install; set HARBOR_PLAN_REPO=<owner/name>)"

# the same three answers merge-check.sh --protection tells apart, and unknown is not one of them
_p="$("$GH" api "repos/$REPO/branches/$BRANCH/protection" 2>&1)" && _rc=0 || _rc=$?
if [ "$_rc" -eq 0 ]; then
  _n="$(printf '%s' "$_p" | jq -r '.required_status_checks.contexts // [] | length' 2>/dev/null || printf '')"
  case "$_n" in ''|*[!0-9]*) unread "the $REPO protection read (not a protection object)" ;; 0) GATE=weak ;; *) GATE=github ;; esac
else
  case "$_p" in
    *"Upgrade to GitHub Pro"*|*403*) GATE=local ;;
    *"Branch not protected"*|*404*) GATE=absent ;;
    *) unread "the $REPO protection read" ;;
  esac
fi

PPLAN="$(printf '%s' "$PREV" | jq -r '.plan // ""')"; PGATE="$(printf '%s' "$PREV" | jq -r '.gate // ""')"
APLAN="$(printf '%s' "$ACK" | jq -r .plan)"; AGATE="$(printf '%s' "$ACK" | jq -r .gate)"
if [ "$MODE" = print ]; then
  log_head "plan"
  log_note "plan $PLAN (acknowledged $APLAN); gate $GATE on $REPO/$BRANCH (acknowledged $AGATE)"
  [ "$PLAN/$GATE" = "$APLAN/$AGATE" ] || log_warn "alarm: this differs from what was acknowledged; sh $0 ack accepts it"
  log_end >/dev/null || :
  exit 0
fi

if [ "$MODE" = ack ]; then
  ACK="$(jq -cn --arg p "$PLAN" --arg g "$GATE" '{plan: $p, gate: $g}')"
  logline "acknowledged: plan $PLAN, gate $GATE (was plan $APLAN, gate $AGATE)"
  log_ok "acknowledged plan $PLAN, gate $GATE"
  APLAN="$PLAN"; AGATE="$GATE"
fi

# ── one line per change: the delta, never the census ─────────────────────────────────────────
if [ -z "$PPLAN" ] || [ -z "$PGATE" ]; then
  logline "first reading: plan $PLAN, gate $GATE on $REPO/$BRANCH (acknowledged plan $APLAN, gate $AGATE)"
else
  d=""
  [ "$PLAN" = "$PPLAN" ] || d="plan $PPLAN -> $PLAN"
  why=""; [ "$GATE" != local ] || why=" (protection HTTP 403: merge-check gates on CONTRACTS/required-checks.tsv)"
  [ "$GATE" = "$PGATE" ] || d="$d${d:+; }gate $PGATE -> $GATE on $REPO/$BRANCH$why"
  [ -z "$d" ] || logline "$d"
fi

ALARM=false; [ "$PLAN/$GATE" = "$APLAN/$AGATE" ] || ALARM=true
# The "did not answer" line promised the next good read clears it: say so once, or the log ends on the failure.
[ "$MODE" != run ] || [ "$(printf '%s' "$PREV" | jq -r '.unread // false')" != true ] || logline "the plan read answers again"
save "$(jq -cn --argjson now "$NOW" --arg repo "$REPO" --arg plan "$PLAN" --arg gate "$GATE" --argjson ack "$ACK" --argjson alarm "$ALARM" \
  '{at: $now, repo: $repo, plan: $plan, gate: $gate, ack: $ack, alarm: $alarm, unread: false}')"
[ "$MODE" = ack ] && log_end >/dev/null || :
exit 0
