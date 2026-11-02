#!/usr/bin/env sh
# pulse (harbor#9 — workstream E, E1) — the between-sessions health probe.
#
#   sh alert-probe.sh            # the table
#   sh alert-probe.sh --json     # {ran_at, inputs_seen, worst, checks{}}
#
# The cadence this occupies: status-fleet-glyph.sh (numbers that move, per statusline tick), session-verdicts.sh (standing verdicts, once per session) and status-dashboard-generate.sh (on demand) all run only while the operator is looking. A box with no session open for three days is checked by nothing; pulse is the unattended rhythm: launchd fires it, it evaluates, alert-notify.sh speaks only when a verdict CHANGES.
# Writes nothing: a pure evaluator, safe from any session; the writer is alert-notify.sh, which is what lets the suite test every verdict without a sink or a cache.
# It never fires a guard: admission-verify.sh proves the floor by firing six blocked shapes, each appending a real block record to the guard-decision ledger that observe-report --fp adjudicates from, which at a 300s interval is on the order of a thousand fabricated blocks a day. So `floor` says WIRED, never PROVEN; `harbor verify` proves it by hand.
# Every check is answerable from the live config dir alone; nothing reads the repo, since a probe that needs a checkout cannot report while the checkout is missing or broken. Live-bin lag and repo counts are `status-gen --observed`'s, document staleness doc-freshness.sh's, the full dependency table deploy-doctor.sh's.
# Unknown is not ok: an unreadable source yields `unknown`, and `inputs_seen` counts the checks that got a real answer (DE-14, DE-18: a reporter that says zero when it never ran).
# The wired-guard predicate is a copy of status-generate.sh's (whole-path-segment match on admission-hook.sh plus a non-empty check over the guard files; `test("guard-")` gave a false green because prod-guard-ambient.sh satisfies the substring). pulse-test.sh asserts the two agree on one fixture: a copy with a test that fails on divergence is a seam.
# Removed notes: docs/explanation/code-cases/bin-alert-probe.md
set -eu

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CACHE_DIR="${HARBOR_SCOPE_CACHE_DIR:-$CFG/cache}"
FLEET_CACHE="$CACHE_DIR/fleet-snapshot.json"
# Six times the refresher's interval: narrower and a machine that slept through one wake-up reports a dead fleet job every morning (§2.11).
FLEET_MAX_AGE="${HARBOR_ALERT_PROBE_FLEET_MAX_AGE:-1800}"
MODE="${1:-}"

case "$MODE" in
  -h|--help)
    cat <<'USAGE'
pulse — the between-sessions health probe (harbor#9, workstream E).

  sh alert-probe.sh          the table
  sh alert-probe.sh --json   {ran_at, generated, inputs_seen, worst, checks{}}

Verdicts: ok · warn · crit · unknown (a source that could not be read —
never reported as ok). Writes nothing; alert-notify.sh is the writer.
USAGE
    exit 0 ;;
esac

# Its status lines are log-lib's, on stderr (contracts/logging.md): stdout is the table or the JSON.
# Parameter expansion, not dirname: the deps check runs on a PATH that may hold almost nothing.
case "$0" in */*) _pd="${0%/*}" ;; *) _pd=. ;; esac
. "$_pd/library-log.sh"
. "$_pd/library-fs.sh"
# shellcheck disable=SC2034 # ALERT_LIB_DIR: read by library-alert.sh
ALERT_LIB_DIR="$_pd"; . "$_pd/library-alert.sh"
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2; log_init pulse

# jq missing must not print nothing: it is the dependency whose absence made every guard exit 0 on rm -rf / (B9).
if ! command -v jq >/dev/null 2>&1; then
  log_fail "CRIT deps — jq is missing, and every floor guard fails open without it"
  log_fix "$(pkg_hint jq)"
  log_end || :; exit 1
fi

RESULTS="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"
trap 'rm -f "$RESULTS"' EXIT INT TERM HUP
emit() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$RESULTS"; }

mtime() { fs_mtime "$1"; } # <file> -> epoch seconds, or empty (bin/library-fs.sh, harbor#618)

# ── floor · does anything protect anything ───────────────────────────────────
check_floor() {
  _s="$CFG/settings.json"
  if [ ! -f "$_s" ]; then emit floor unknown "no settings.json in the config dir"; return 0; fi
  # Ask for the entry ONLY admission-deny.sh writes, not a non-empty list: one unrelated deny rule made this read "B1 is live" on a box with every Harbor pattern removed.
  _sentinel='(.permissions.deny // []) | index("Edit(~/.claude/.helm-floor-teeth)")'
  _deny=no
  jq -e "$_sentinel" "$_s" >/dev/null 2>&1 && _deny=yes
  # The matrix, not the basename: admission-install.sh wires distinct (event, matcher, guard) triples, and flattening them to "does this guard appear anywhere" missed pass 11's critical (admission-egress.sh's mcp__*, Task/Agent, WebFetch/WebSearch and NotebookEdit branches could not run for months because only Bash|Write|Edit was wired). This list MIRRORS admission-install.sh, which the probe cannot read (no repo); pulse-test.sh extracts the installer's `add` lines and fails when the two disagree.
  _unwired=""; _ntot=0   # _ntot counts the MATRIX rows below, so "no guard wired" tracks the table
  _parsed=yes
  jq -e . "$_s" >/dev/null 2>&1 || _parsed=no
  if [ "$_parsed" = yes ]; then
    while IFS='	' read -r _ev _mt _g; do
      [ -n "$_ev" ] || continue
      _ntot=$((_ntot + 1))
      jq -e --arg e "$_ev" --arg m "$_mt" --arg g "$_g" '
            [.hooks[$e][]? | select(.matcher == $m) | .hooks[]?.command // empty]
            | map(select(test("(^|/)admission-hook[.]sh([[:space:]]|$)")) | select(contains($g)))
            | length > 0' "$_s" >/dev/null 2>&1 \
        || _unwired="$_unwired ${_g%.sh}/${_mt%%|*}"
    done <<'MATRIX'
PreToolUse	Bash	admission-bash.sh
PreToolUse	Bash|Write|Edit|MultiEdit	admission-egress.sh
PreToolUse	mcp__.*|Task|Agent|WebFetch|WebSearch|NotebookEdit	admission-egress.sh
PreToolUse	Write|Edit|MultiEdit	admission-self-edit.sh
PostToolUse	WebFetch|WebSearch|ToolSearch|mcp__.*	annotate-web.sh
PreToolUse	Monitor	admission-bash.sh
PreToolUse	Monitor	admission-egress.sh
PreToolUse	Grep	admission-egress.sh
MATRIX
  fi
  # An EMPTY file parses as neither valid nor invalid: jq over zero inputs prints nothing and exits 0, so this once reported a healthy floor on an unguarded box. Reachable: deploy-harden.sh writes the live settings with a truncating redirect, so an interrupted apply leaves exactly that file.
  if [ "$_parsed" = no ]; then
    emit floor unknown "the live settings file is empty or could not be parsed"; return 0
  fi
  # All seven files, not the five obvious guards: annotate-web.sh (B4 PostToolUse) and admission-normalize.awk (the shared normaliser) missing is a partial install that reads as complete.
  _missing=0
  for _f in admission-hook.sh library-admission.sh admission-bash.sh admission-egress.sh \
            admission-self-edit.sh annotate-web.sh admission-normalize.awk; do
    [ -s "$CFG/bin/$_f" ] || _missing=$((_missing + 1))
  done
  _nun=0
  for _u in $_unwired; do _nun=$((_nun + 1)); done
  if [ "$_deny" = no ] && [ "$_nun" -eq "$_ntot" ]; then
    emit floor crit "nothing protects this box: no B1 sentinel, and no guard wired"
  elif [ "$_nun" -eq "$_ntot" ]; then
    emit floor warn "B1 deny is live, no guard is wired (the install gate may be holding this shut)"
  elif [ "$_nun" -gt 0 ]; then
    emit floor crit "a PARTIAL floor:$_unwired not wired — the rest of it reads as installed"
  elif [ "$_missing" -gt 0 ]; then
    emit floor crit "guards wired, $_missing guard file(s) missing — wired at nothing"
  elif [ "$_deny" = no ]; then
    emit floor warn "guards wired, but the B1 deny sentinel is gone from the live settings"
  else
    emit floor ok "B1 sentinel live and every guard wired on every matcher (wired, not fired — use harbor verify)"
  fi
}

# ── deps · what the INSTALLED surface needs tonight ──────────────────────────
check_deps() {
  _crit=""; _warn=""
  command -v git >/dev/null 2>&1 || _crit="$_crit git"
  command -v gitleaks >/dev/null 2>&1 || _warn="$_warn gitleaks"
  # The notify sink (bin/library-alert.sh, harbor#618): with no desktop channel a banner is only logged.
  [ "$(notify_sink)" != log ] || _warn="$_warn desktop-notifier"
  if [ -n "$_crit" ]; then
    emit deps crit "missing:$_crit — the work-log cannot sync at all"
  elif [ -n "$_warn" ]; then
    # gitleaks is fail-CLOSED: without it worklog-push refuses the commit silently on every Stop. A missing sink means this probe's own sink is dead, so a CRIT would be seen by nobody.
    emit deps warn "missing:$_warn — a fail-closed gate or the notify sink is down"
  else
    emit deps ok "jq, git, gitleaks and the notify sink are all present"
  fi
}

# ── fleet · the orchestrator snapshot, and whether its writer is alive ───────
# Reads only descriptor.name, hooks and status: the cache carries each repo's full memory store inline (client names, escalation notes), which §3 makes the operator's business, and a notification body carries none of it.
check_fleet() {
  if [ ! -f "$FLEET_CACHE" ]; then emit fleet unknown "no fleet snapshot has been written yet"; return 0; fi
  _m="$(mtime "$FLEET_CACHE")"
  _now="$(date +%s)"
  if [ -n "$_m" ]; then
    _age=$((_now - _m))
    if [ "$_age" -gt "$FLEET_MAX_AGE" ]; then
      # A closed laptop looks exactly like a dead refresher: both are launchd StartInterval jobs on one machine, so if OUR last run is also older than the window nothing was running. Warning would fire a false WARN after every sleep and a false RECOVERED minutes later, a flap on a channel that only speaks on change. The notifier passes its previous ran_at.
      _last="${HARBOR_ALERT_PROBE_LAST_RUN:-0}"
      case "$_last" in ''|*[!0-9]*) _last=0 ;; esac
      if [ "$_last" -gt 0 ] && [ "$((_now - _last))" -gt "$FLEET_MAX_AGE" ]; then
        emit fleet unknown "snapshot is $((_age / 60))m old, and so is this probe — the machine was not running"
      else
        emit fleet warn "snapshot is $((_age / 60))m old — the refresher has stopped writing"
      fi
      return 0
    fi
  fi
  _n="$(jq -r 'if type == "array" then length else "x" end' "$FLEET_CACHE" 2>/dev/null || printf 'x')"
  case "$_n" in x|"") emit fleet unknown "the snapshot is not the array the refresher writes"; return 0 ;; esac
  # Only the literal "missing" is a finding. The snapshot carries a third value, `-`, for a repo the orchestrator could not answer for; "anything not OK is bad" turns every future value into a false alarm.
  _bad="$(jq -r '[.[] | select(.hooks == "missing")] | length' "$FLEET_CACHE" 2>/dev/null || printf 'x')"
  _unread="$(jq -r '[.[] | select((.hooks | type) != "string" or (.hooks != "ok" and .hooks != "missing"))] | length' \
              "$FLEET_CACHE" 2>/dev/null || printf 'x')"
  case "$_bad$_unread" in *x*|"") emit fleet unknown "the snapshot could not be read"; return 0 ;; esac
  # Drift is deliberately NOT a verdict: most repos carry uncommitted work most of the time. Missing governance hooks is the fleet fact that is broken rather than in progress.
  if [ "$_n" -eq 0 ]; then
    # An empty fleet is a valid fleet; otherwise unread == total (0 == 0) would report unknown forever on a clean machine.
    emit fleet ok "the snapshot lists no repos"
  elif [ "$_bad" -gt 0 ]; then
    emit fleet warn "$_bad of $_n repo(s) are missing governance hooks"
  elif [ "$_unread" -eq "$_n" ]; then
    emit fleet unknown "$_n repo(s), none of them answering about hooks"
  elif [ "$_unread" -gt 0 ]; then
    emit fleet ok "$_n repo(s), hooks intact where reported ($_unread unreported)"
  else
    emit fleet ok "$_n repo(s), hooks intact, snapshot fresh"
  fi
}

# ── cudoctor · is the ticket-standard gate still firing, and did it check ────
# The receipt had no reader. bin/cu-doctor-run.sh writes cu-doctor-state.json and calls `ran_at` liveness, but (2026-09-02) nothing read it, so the job could stop firing while the file read `green` forever.
# Three states: `error` means cu doctor REFUSED and nothing was checked; it is as quiet on stdout as `green`, so only this tells them apart unattended.
# The threshold is 3x the cadence, not check_fleet's 6x: this is a StartCalendarInterval job at 08:47 that launchd fires on WAKE, so a closed laptop still gets its run, and two consecutive days without one means the job is gone. Overridable for a box on another cadence.
CUDOCTOR_STATE="$CACHE_DIR/cu-doctor-state.json"
CUDOCTOR_MAX_AGE="${HARBOR_ALERT_PROBE_CLICKUP_DOCTOR_MAX_AGE:-259200}"
check_cudoctor() {
  if [ ! -f "$CUDOCTOR_STATE" ]; then
    emit cudoctor unknown "no cu doctor receipt has been written yet"; return 0
  fi
  # ran_at, not mtime: it is the field the writer promises and only moves when a run completed.
  _at="$(jq -r '.ran_at // empty' "$CUDOCTOR_STATE" 2>/dev/null || true)"
  _st="$(jq -r '.status // empty' "$CUDOCTOR_STATE" 2>/dev/null || true)"
  if [ -z "$_st" ]; then
    emit cudoctor unknown "the receipt is not the JSON cu-doctor-run.sh writes"; return 0
  fi
  # BSD date parses the Z form with -j -f, GNU wants -d; digits or nothing, as mtime() above.
  _ep="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$_at" +%s 2>/dev/null || true)"
  case "$_ep" in ''|*[!0-9]*) _ep="$(date -u -d "$_at" +%s 2>/dev/null || true)" ;; esac
  case "$_ep" in ''|*[!0-9]*) _ep="" ;; esac
  if [ -n "$_ep" ]; then
    _age=$(( $(date +%s) - _ep ))
    if [ "$_age" -gt "$CUDOCTOR_MAX_AGE" ]; then
      # Staleness outranks the verdict inside: a six-day-old `green` is evidence nothing has looked, not that the board is clean.
      emit cudoctor warn "last run was $((_age / 86400))d ago — the daily gate has stopped firing, so its verdict is stale whatever it says"
      return 0
    fi
  else
    emit cudoctor unknown "the receipt carries no readable ran_at, so liveness cannot be established"; return 0
  fi
  _n="$(jq -r '.gates_failing // "?"' "$CUDOCTOR_STATE" 2>/dev/null || printf '?')"
  case "$_st" in
    green)   emit cudoctor ok "every ticket gate green, $((_age / 3600))h ago" ;;
    failing) emit cudoctor warn "$_n ticket gate(s) failing — cu doctor" ;;
    error)   emit cudoctor crit "cu doctor REFUSED and nothing was checked — see $CUDOCTOR_STATE" ;;
    # A status the writer does not emit is not ok.
    *)       emit cudoctor unknown "unrecognised receipt status \"$_st\"" ;;
  esac
}

# ── worklog · is the git-backed log actually leaving this machine ────────────
# Cleanliness is not the signal (the store is dirty by design); unpushed commits are, since they accumulate only when the Stop push is failing.
check_worklog() {
  _m="$CFG/MEMORY"
  if [ ! -d "$_m/.git" ]; then emit worklog unknown "no work-log repository"; return 0; fi
  if ! command -v git >/dev/null 2>&1; then emit worklog unknown "git is missing"; return 0; fi
  if ! git -C "$_m" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    # session-verdicts.sh owns this verdict, loudly, once per session; repeating it here would put one fact on two channels.
    emit worklog unknown "the branch has no upstream (session-verdicts owns this verdict)"
    return 0
  fi
  _ahead="$(git -C "$_m" rev-list --count '@{u}..HEAD' 2>/dev/null || printf 'x')"
  case "$_ahead" in x|"") emit worklog unknown "the work-log could not be read"; return 0 ;; esac
  if [ "$_ahead" -gt 0 ]; then
    emit worklog warn "$_ahead session record(s) committed and never pushed"
    return 0
  fi
  # Ahead=0 has two meanings, one bad: everything pushed, or nothing ever committed, which is what a frozen Stop hook produces (the gitleaks gate is fail-closed, so a missing scanner makes worklog-push refuse silently). Age separates them; a week never trips on normal use and always trips on a freeze, and the wording carries both readings since an idle machine is the innocent one. Scoped to the record paths: an unscoped `log -1` is refreshed by any commit (idea commits push IDEAS.md on their own), so a frozen work-log reads fresh the moment the operator files an idea. worklog-push.sh's staging allowlist is the authority on where a session record lands.
  _last="$(git -C "$_m" log -1 --format=%ct -- 'WORK/sessions' 2>/dev/null || printf '')"
  case "$_last" in ''|*[!0-9]*) emit worklog ok "in sync with the remote"; return 0 ;; esac
  _age=$(( $(date +%s) - _last ))
  if [ "$_age" -gt "${HARBOR_ALERT_PROBE_WORKLOG_MAX_AGE:-604800}" ]; then
    emit worklog warn "nothing committed in $((_age / 86400))d — either nothing ran, or the Stop gate is refusing"
  else
    emit worklog ok "every session record has reached the remote"
  fi
}

# ── dispatch · is the event dispatcher following, if this box runs one ──────
# A NOT FOLLOWING line in checks.log scrolled out of the console panel within an hour, and launchd lists an exited-0 job like an idle one (harbor#1044 review r3 #4). So the follower leaves a receipt (status following, down, off or stopped, with pid and reason) and this row is the surface: down is crit, and pulse-notify speaks on the change. No receipt is ok, not unknown: the dispatcher is opt-in and ships inert.
# harbor#1437: a deploy installs the job now, so "installed and never reported" is a dead dispatcher, and a rule the follower
# has refused on two passes running (cache/event-dispatch-refused.tsv) is a warn: it runs nothing. alert-notify.sh files the
# dispatch row as finding check/event.dispatch.
DISPATCH_STATE="$CACHE_DIR/event-dispatch-state.json"
DISPATCH_REFUSED="$CACHE_DIR/event-dispatch-refused.tsv"
DISPATCH_PLIST="${HOME:-/nonexistent}/Library/LaunchAgents/com.harbor.event.dispatch.plist"
check_dispatch() {
  if [ ! -f "$DISPATCH_STATE" ]; then
    if [ -f "$DISPATCH_PLIST" ]; then emit dispatch warn "the dispatcher is installed (launchd com.harbor.event.dispatch) and has never written its receipt: it is not running, or runs code that predates the receipt"
    else emit dispatch ok "no event dispatcher has run here (none installed)"; fi
    return 0
  fi
  if [ -s "$DISPATCH_REFUSED" ]; then
    _rl="$(cut -f1 "$DISPATCH_REFUSED" | tr '\n' ' ' | sed 's/ $//')"
    emit dispatch warn "rule(s) $_rl refused on two passes running and run nothing — event-dispatch.sh reconcile (a deploy runs it) replaces a refused preset"
    return 0
  fi
  _st="$(jq -r '.status // empty' "$DISPATCH_STATE" 2>/dev/null || true)"
  _pid="$(jq -r '.pid // empty' "$DISPATCH_STATE" 2>/dev/null || true)"
  _why="$(jq -r '.reason // empty' "$DISPATCH_STATE" 2>/dev/null || true)"
  case "$_pid" in ''|*[!0-9]*) _pid="" ;; esac
  case "$_st" in
    down)      emit dispatch crit "NOT FOLLOWING: ${_why:-no reason recorded} — launchd leaves it down until it is fixed and restarted" ;;
    following) if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then emit dispatch ok "following the event bus (pid $_pid)"
               else emit dispatch warn "it said it was following, and pid ${_pid:-?} is gone: it stopped without a word"; fi ;;
    off)       emit dispatch ok "stopped by dispatch.off" ;;
    stopped)   emit dispatch ok "stopped (${_why:-a signal}), as a launchd bootout does" ;;
    *)         emit dispatch unknown "the receipt is not the JSON event-dispatch.sh writes" ;;
  esac
}

check_floor
check_deps
check_fleet
check_worklog
check_cudoctor
check_dispatch

# ── verdict arithmetic ───────────────────────────────────────────────────────
# ok < unknown < warn < crit. unknown outranks ok deliberately: "could not look" is worse news than "looked and fine", and an all-unreadable run must not render as a healthy zero.
rank() { case "$1" in ok) echo 0 ;; unknown) echo 1 ;; warn) echo 2 ;; crit) echo 3 ;; *) echo 1 ;; esac; }
WORST=ok
SEEN=0
TOTAL=0
while IFS='	' read -r _id _v _d; do
  [ -n "$_id" ] || continue
  TOTAL=$((TOTAL + 1))
  [ "$_v" = unknown ] || SEEN=$((SEEN + 1))
  [ "$(rank "$_v")" -gt "$(rank "$WORST")" ] && WORST="$_v"
  : "$_d"
done < "$RESULTS"

RAN_AT="$(date +%s)"
GENERATED="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

if [ "$MODE" = "--json" ]; then
  jq -Rn --argjson ran "$RAN_AT" --arg gen "$GENERATED" \
     --argjson seen "$SEEN" --argjson total "$TOTAL" --arg worst "$WORST" \
     --rawfile rows "$RESULTS" '
    { ran_at: $ran, generated: $gen, inputs_seen: $seen, checks_run: $total, worst: $worst,
      checks: ($rows | split("\n") | map(select(length > 0) | split("\t"))
               | map({ key: .[0], value: { verdict: .[1], detail: .[2] } }) | from_entries) }'
  exit 0
fi

printf 'PULSE  %s   worst: %s   answered: %s/%s\n\n' "$GENERATED" "$WORST" "$SEEN" "$TOTAL"
while IFS='	' read -r _id _v _d; do
  [ -n "$_id" ] || continue
  printf '  %-8s %-8s %s\n' "$_id" "$_v" "$_d"
done < "$RESULTS"
if [ "$SEEN" -eq 0 ]; then
  printf '\n  Every source was unreadable. This is a broken probe, not a healthy box.\n'
fi
exit 0
