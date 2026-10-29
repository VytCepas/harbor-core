#!/usr/bin/env sh
# ci-runner-switch.sh (harbor#865) — GitHub-hosted is the primary CI runner; the Mac is the fallback when the month's Actions minutes run short.
#
#   sh ci-runner-switch.sh            read the month's private-repo Actions minutes, set the repo variable HARBOR_RUNNER
#                                  (governance.yml's selector) when it should change, write cache/runner-switch.json
#   sh ci-runner-switch.sh --print    the same read, writes nothing: the usage, the allowance, what it would set
#   sh ci-runner-switch.sh --org ORG [--print]   an organisation's own verdict, its minutes against its cap (the --org block below)
#
# THE RULE. used = month-to-date `quantity` of billing items whose product is actions, whose sku names Linux, macOS or
# Windows, and whose repository is private (public repos are free and storage is not minutes).
# allowance = the plan's included minutes (`gh api user` .plan.name: free 2000, pro 3000; harbor#1060) + a budget in minutes.
# used >= 90% of it -> `self-hosted`; below -> `github-hosted`. A plan it does not know, or cannot read, flips nothing.
# It never reads or writes a spending limit or budget on GitHub: the budget below is a local file, not the bill's.
# THE 1ST (UTC) sets `github-hosted` without reading the bill: the month's usage is a day old at most, and a bill that
# will not answer must not pin the Mac for the first day of a fresh allowance. Every other day a failed read changes NOTHING.
#
# THE BUDGET is a config value, default 0: the file $CLAUDE_CONFIG_DIR/.harbor-ci-budget holding `minutes N` or `usd N`
# (Linux is $0.008 a minute, so 1 dollar is 125 minutes), or the env HARBOR_CI_BUDGET_MIN. Absent means 0.
#
# IT WRITES ONLY WHEN THE VALUE WOULD CHANGE. An unset variable already means self-hosted (the workflow's own default), so
# it is read that way. A change is ONE line in cache/checks.log (`[check:runner-switch]`), never one per tick, and the
# cache feeds fleet-glyph's `CI→local` token (the Mac and the Linux container both run self-hosted). A read that fails
# (the bill, the repo list or the variable) flips NOTHING: it warns, marks the cache `unread`, and logs once on the way in, not on every tick of a standing outage.
#
# Run by status-fleet-snapshot-refresh.sh every 300s: no schedule of its own. POSIX sh, jq, gh (HARBOR_GH swaps in a fake).
set -eu
. "$(dirname -- "$0")/library-log.sh"
log_init runner-switch

case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
PRINT=0; ORG=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --print) PRINT=1 ;;
    --org) ORG="${2:-}"; [ "$#" -gt 1 ] && shift
           case "$ORG" in ''|-*|*[!A-Za-z0-9-]*) log_fail "--org needs an organisation name"; log_fix "sh $0 --org ExampleOrg"; exit 2 ;; esac ;;
    *) log_fail "unknown option $1"; log_fix "sh $0 --help"; exit 2 ;;
  esac
  shift
done

REPO="${HARBOR_SWITCH_REPO:-$(repo_slug)}"   # harbor's own OWNER/NAME (harbor#1149); --org never reads it, the rest refuses an empty one
BUSER="${HARBOR_BILLING_USER:-${REPO%%/*}}"  # the account billed for the minutes is the repo's owner unless named
VARNAME=HARBOR_RUNNER
PCT=90
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CACHE_DIR="${HARBOR_CACHE_DIR:-$HOME/.claude/cache}"
OUT="$CACHE_DIR/runner-switch.json"
LOG="$CACHE_DIR/checks.log"
NOW="${HARBOR_NOW:-$(date +%s)}"
GH="${HARBOR_GH:-gh}"
command -v jq >/dev/null 2>&1 || { log_fail "jq is required"; log_fix "$(pkg_hint jq)"; exit 2; }
case "$NOW" in ''|*[!0-9]*) NOW="$(date +%s)" ;; esac

# The UTC date of an epoch: BSD `date -r <epoch>`, else GNU `date -d @<epoch>`.
fmt() { date -u -r "$NOW" "+$1" 2>/dev/null || date -u -d "@$NOW" "+$1"; }
YEAR="$(fmt %Y)"; MONTH="$(fmt %m)"; DAY="$(fmt %d)"
MONTH_N="${MONTH#0}"

# ── the budget, in minutes ─────────────────────────────────────────────────────
BUDGET=0
_bf="$CFG/.harbor-ci-budget"
if [ -f "$_bf" ]; then
  BUDGET="$(awk '$1 == "minutes" && $2 ~ /^[0-9.]+$/ { printf "%d", $2; exit }
                 $1 == "usd"     && $2 ~ /^[0-9.]+$/ { printf "%d", $2 / 0.008 + 0.5; exit }' "$_bf" 2>/dev/null || true)"
elif [ -n "${HARBOR_CI_BUDGET_MIN:-}" ]; then
  BUDGET="$HARBOR_CI_BUDGET_MIN"
fi
case "$BUDGET" in ''|*[!0-9]*) BUDGET=0 ;; esac

T="$(mktemp -d "${TMPDIR:-/tmp}/runner-switch.XXXXXX")"
trap 'rm -rf "$T"' EXIT INT TERM
mkdir -p "$CACHE_DIR"

# ── --org ORG (harbor#1060): an organisation's verdict, decided apart from the personal account's ──────────
# used = the org's month-to-date Actions minutes (product actions, sku Linux, macOS or Windows, every repo: the org's
# repos are private, and a deleted repo's minutes still count). cap = `org ORG N` in $CLAUDE_CONFIG_DIR/.harbor-ci-runners,
# default 2000. used >= cap -> self-hosted. It sets NO variable: cache/runner-switch.<ORG>.json is the verdict, and
# ci-runners.sh flips the org-level CI_RUNS_ON only while the org's runner is online. The 1st and a failed read are as above;
# a change of verdict is one `[check:runner-switch-org]` line.
if [ -n "$ORG" ]; then
  OUT="$CACHE_DIR/runner-switch.$ORG.json"
  CAP="$(awk -v o="$ORG" '$1 == "org" && $2 == o && $3 ~ /^[0-9]+$/ { print $3; exit }' "$CFG/.harbor-ci-runners" 2>/dev/null || true)"
  CAP="${CAP:-2000}"
  PREV_UNREAD=false; PREV_RUNNER=""
  if [ -f "$OUT" ] && jq -e . "$OUT" >/dev/null 2>&1; then
    PREV_UNREAD="$(jq -r '.unread // false' "$OUT")"; PREV_RUNNER="$(jq -r '.runner // ""' "$OUT")"
  fi
  ologline() { [ "$PRINT" = 1 ] || printf '[check:runner-switch-org] %s %s\n' "$(fmt %Y-%m-%dT%H:%M:%SZ)" "$1" >> "$LOG" 2>/dev/null || :; }
  ounread() { # <what> — no new verdict: the last one kept and marked unread, one line on the way in
    log_warn "$ORG: $1 did not answer; its verdict is left as it is"; log_fix "gh auth status (the org's bill needs admin:org)"
    [ "$PRINT" = 1 ] && exit 2
    if [ -f "$OUT" ] && jq -e . "$OUT" >/dev/null 2>&1; then
      jq -c --argjson now "$NOW" '. + {unread: true, at: $now}' "$OUT" > "$OUT.tmp.$$" || { rm -f "$OUT.tmp.$$"; exit 1; }
    else printf '{"at":%s,"owner":"%s","unread":true,"fallback":false}\n' "$NOW" "$ORG" > "$OUT.tmp.$$"; fi
    mv -f "$OUT.tmp.$$" "$OUT"
    [ "$PREV_UNREAD" = true ] || ologline "$ORG: $1 did not answer; its verdict is left as it is (the next good read clears this)"
    exit 0
  }
  USED=0; NEWMONTH=false
  if [ "$DAY" = 01 ]; then NEWMONTH=true
  else
    "$GH" api "/orgs/$ORG/settings/billing/usage?year=$YEAR&month=$MONTH_N" > "$T/bill.json" 2>/dev/null || ounread "the org billing usage read"
    jq -e '.usageItems | type == "array"' "$T/bill.json" >/dev/null 2>&1 || ounread "the org billing usage read (not a usage list)"
    USED="$(jq -r '[.usageItems[] | select(.product == "actions" and (.sku | test("Linux|macOS|Windows"))) | .quantity] | add // 0 | floor' \
      "$T/bill.json" 2>/dev/null || true)"
    case "$USED" in ''|*[!0-9]*) ounread "the org billing usage read (no minutes in it)" ;; esac
  fi
  if [ "$NEWMONTH" = true ]; then WANT=github-hosted; WHY="new month"
  elif [ "$USED" -ge "$CAP" ]; then WANT=self-hosted; WHY="$USED/$CAP minutes, at or over the cap"
  else WANT=github-hosted; WHY="$USED/$CAP minutes, under the cap"; fi
  if [ "$PRINT" = 1 ]; then
    log_head "runner"
    log_note "$ORG used $USED of its $CAP-minute cap; verdict $WANT ($WHY), last ${PREV_RUNNER:-none}"
    log_end >/dev/null || :
    exit 0
  fi
  # The "did not answer" line promised the next good read clears it: say so once, or the log ends on the failure.
  [ "$PREV_UNREAD" != true ] || ologline "$ORG: the org billing usage read answers again"
  [ "$WANT" = "$PREV_RUNNER" ] || ologline "$ORG ${PREV_RUNNER:-none} -> $WANT ($WHY)"
  FALLBACK=false; [ "$WANT" = self-hosted ] && FALLBACK=true
  jq -cn --argjson now "$NOW" --arg owner "$ORG" --arg runner "$WANT" --argjson used "$USED" --argjson cap "$CAP" \
    --argjson fb "$FALLBACK" --argjson nm "$NEWMONTH" \
    '{at: $now, owner: $owner, runner: $runner, fallback: $fb, used: $used, allowance: $cap,
      percent: (if $cap > 0 then (($used * 100 / $cap) | floor) else 0 end), new_month: $nm, unread: false}' > "$OUT.tmp.$$" \
    && mv -f "$OUT.tmp.$$" "$OUT" || { rm -f "$OUT.tmp.$$"; exit 1; }
  exit 0
fi

# prev: the last cache's mark and runner, for "log once on the way in".
PREV_UNREAD=false; PREV_RUNNER=""
if [ -f "$OUT" ] && jq -e . "$OUT" >/dev/null 2>&1; then
  PREV_UNREAD="$(jq -r '.unread // false' "$OUT")"
  PREV_RUNNER="$(jq -r '.runner // ""' "$OUT")"
fi
logline() { # <message> — one checks.log line, never from --print
  [ "$PRINT" = 1 ] && return 0
  printf '[check:runner-switch] %s %s\n' "$(date -u -r "$NOW" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$NOW" +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$LOG" 2>/dev/null || :
}
# A failed read: no flip, a warning, the cache marked unread (the last good fields kept), one log line on entry.
unread() { # <what>
  log_warn "$REPO: $1 did not answer; HARBOR_RUNNER left as it is"; log_fix "gh auth status"
  [ "$PRINT" = 1 ] && exit 2
  if [ -f "$OUT" ] && jq -e . "$OUT" >/dev/null 2>&1; then
    jq -c --argjson now "$NOW" '. + {unread: true, at: $now}' "$OUT" > "$OUT.tmp.$$" || { rm -f "$OUT.tmp.$$"; exit 1; }
  else
    printf '{"at":%s,"repo":"%s","unread":true,"fallback":false}\n' "$NOW" "$REPO" > "$OUT.tmp.$$"
  fi
  mv -f "$OUT.tmp.$$" "$OUT"
  [ "$PREV_UNREAD" = true ] || logline "$REPO: $1 did not answer; HARBOR_RUNNER left as it is (the next good read clears this)"
  exit 0
}

# No name for harbor's own repository: nothing below can be read, so it is an unread (cache marked, one line) and flips nothing.
[ -n "$REPO" ] || { REPO='?'; unread "the repository name (no origin in this checkout, no repo-slug.txt beside this install; set HARBOR_SWITCH_REPO=<owner/name>)"; }

# ── the current value: unset reads as self-hosted, which is what the workflow does with it ──
CUR="$("$GH" variable get "$VARNAME" -R "$REPO" 2>"$T/vget.err" || true)"
CUR="$(printf '%s' "$CUR" | tr -d ' \r\n')"
if [ -z "$CUR" ]; then
  if grep -qi 'not found' "$T/vget.err" 2>/dev/null; then CUR=self-hosted; else unread "the $VARNAME read"; fi
fi

# ── the allowance follows the account's plan (harbor#1060: Pro -> Free on 2026-10-05 took 1,000 minutes away) ──
# Included private-repo Actions minutes a month. The 1st reads no bill, so a plan that will not answer there costs nothing.
PLAN="$("$GH" api user --jq '.plan.name' 2>/dev/null || true)"; PLAN="$(printf '%s' "$PLAN" | tr -d ' \r\n' | tr 'A-Z' 'a-z')"
case "$PLAN" in
  free) INCLUDED=2000 ;;
  pro)  INCLUDED=3000 ;;
  *) [ "$DAY" = 01 ] || unread "the plan read (plan '${PLAN:-none}')"; INCLUDED=0 ;;
esac
ALLOW=$((INCLUDED + BUDGET))
THRESH=$(( (ALLOW * PCT + 99) / 100 ))      # the smallest whole minute count that is at least PCT percent

# ── the month's usage ──────────────────────────────────────────────────────────────────
USED=0; NEWMONTH=false
if [ "$DAY" = 01 ]; then
  NEWMONTH=true
else
  "$GH" api "/users/$BUSER/settings/billing/usage?year=$YEAR&month=$MONTH_N" > "$T/bill.json" 2>/dev/null || unread "the billing usage read"
  jq -e '.usageItems | type == "array"' "$T/bill.json" >/dev/null 2>&1 || unread "the billing usage read (not a usage list)"
  "$GH" api "/user/repos?visibility=private&affiliation=owner&per_page=100" --paginate --jq '.[].name' > "$T/priv.txt" 2>/dev/null || unread "the private-repo list"
  [ -s "$T/priv.txt" ] || unread "the private-repo list (empty)"
  USED="$(jq -r --rawfile p "$T/priv.txt" '
      ($p | split("\n") | map(select(. != ""))) as $priv
      | [.usageItems[]
         | select(.product == "actions" and (.sku | test("Linux|macOS|Windows"))
                  and (.repositoryName as $r | $priv | index($r) != null))
         | .quantity] | add // 0 | floor' "$T/bill.json" 2>/dev/null || true)"
  case "$USED" in ''|*[!0-9]*) unread "the billing usage read (no minutes in it)" ;; esac
fi

# ── the decision ────────────────────────────────────────────────────────────────────────
if [ "$NEWMONTH" = true ]; then WANT=github-hosted; WHY="new month"
elif [ "$USED" -ge "$THRESH" ]; then WANT=self-hosted; WHY="$USED/$ALLOW minutes, at or over $PCT%"
else WANT=github-hosted; WHY="$USED/$ALLOW minutes, under $PCT%"; fi

if [ "$PRINT" = 1 ]; then
  log_head "runner"
  log_note "$REPO $VARNAME is $CUR; used $USED of $ALLOW minutes (plan ${PLAN:-?} includes $INCLUDED + budget $BUDGET), threshold $THRESH; would set $WANT ($WHY)"
  log_end >/dev/null || :
  exit 0
fi

if [ "$WANT" != "$CUR" ]; then
  if "$GH" variable set "$VARNAME" --body "$WANT" -R "$REPO" >/dev/null 2>&1; then
    logline "$REPO $VARNAME $CUR -> $WANT ($WHY)"
  else
    unread "the $VARNAME write"
  fi
fi

[ "$PREV_UNREAD" != true ] || logline "$REPO: the HARBOR_RUNNER read answers again"
FALLBACK=false; [ "$WANT" = self-hosted ] && FALLBACK=true
jq -cn --argjson now "$NOW" --arg repo "$REPO" --arg runner "$WANT" --argjson used "$USED" --argjson allow "$ALLOW" \
  --argjson fb "$FALLBACK" --argjson nm "$NEWMONTH" --arg plan "${PLAN:-}" \
  '{at: $now, repo: $repo, runner: $runner, fallback: $fb, used: $used, allowance: $allow, plan: $plan,
    percent: (if $allow > 0 then (($used * 100 / $allow) | floor) else 0 end), new_month: $nm, unread: false}' > "$OUT.tmp.$$" \
  && mv -f "$OUT.tmp.$$" "$OUT" || { rm -f "$OUT.tmp.$$"; exit 1; }
