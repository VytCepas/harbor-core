#!/usr/bin/env sh
# pulse (harbor#9 — workstream E, E1) — the between-sessions health probe.
#
#   sh alert-probe.sh            # the table
#   sh alert-probe.sh --json     # {ran_at, inputs_seen, worst, checks{}}
#
# THE CADENCE THIS OCCUPIES, AND WHY IT IS THE ONLY ONE LEFT. Harbor already
# answers "what is true right now" three times, each at a different rhythm:
# status-fleet-glyph.sh carries the numbers that MOVE, per statusline tick, over a
# cache; session-verdicts.sh carries the standing verdicts that do NOT move,
# once per session, loudly; status-dashboard-generate.sh renders everything on demand. All
# three run only while the operator is already looking. A box with no session
# open for three days is checked by nothing, and that is exactly the window in
# which a work-log stops syncing or a floor stands down unnoticed. Pulse is the
# unattended rhythm: launchd fires it, it evaluates, and alert-notify.sh speaks
# only when a verdict CHANGES.
#
# WRITES NOTHING. This file is a pure evaluator so it is safe to run at any
# moment, from any session, in any state — the writer is alert-notify.sh, which
# is the only thing that touches the state file. That split is what makes the
# suite able to test every verdict without a sink or a cache.
#
# IT NEVER FIRES A GUARD. floor-verify.sh answers "is the floor ON?" by firing
# six known-blocked shapes, and every one of those appends a real block record
# to the guard-decision ledger — the only real-traffic dataset Harbor has, and
# the one observe-report --fp adjudicates false positives from. On a 300s
# interval that is on the order of a thousand fabricated blocks a day. A probe
# must not manufacture the evidence its own system learns from, so this reads
# the wiring and refuses to call the reading a firing test: `floor` says WIRED,
# never PROVEN. `harbor verify` remains the thing that proves it, by hand.
#
# EVERY CHECK IS ANSWERABLE FROM THE LIVE CONFIG DIR ALONE. Nothing here reads
# the repo. That is a constraint, not an omission: a probe that needs a checkout
# to be present, current and unbroken cannot report on the box while the
# checkout is any of those things. It costs four candidate checks, each of which
# has a better home — live-bin lag and the repo counts are `status-gen
# --observed` and the dashboard; document staleness is doc-freshness.sh; the full
# twenty-row dependency table is deploy-doctor.sh. `deps` here asks the narrower
# question those cannot: which tools does the INSTALLED surface need tonight.
#
# UNKNOWN IS NOT OK, AND A ZERO IS UNMEASURED UNTIL THE RUN IS PROVEN. A source
# that cannot be read yields `unknown`, never `ok`, and `inputs_seen` counts the
# checks that got a real answer. DE-14 and DE-18 are both instances of the same
# defect — a reporter that says zero when it never ran, and the clean number is
# the one you want to believe.
#
# THE WIRED-GUARD PREDICATE IS A COPY, AND THE SUITE KNOWS IT. status-generate.sh
# owns the correct one: a whole-path-segment match on floor-hook.sh plus a
# presence-and-nonempty check over the guard files. The tempting one-liner —
# `test("guard-")` over the hook table — produced a false green on 2026-08-01,
# because prod-guard-ambient.sh satisfies the substring on a box with none of
# B2-B6. This file cannot call status-gen (that would be the repo dependency
# above), so it copies the corrected predicate, and pulse-test.sh asserts the
# two agree on the same fixture. A copy with a test that fails when it diverges
# is a seam; a copy without one is the drift T2 exists to prevent.
set -eu

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CACHE_DIR="${HARBOR_SCOPE_CACHE_DIR:-${HARBOR_CACHE_DIR:-$CFG/cache}}"
FLEET_CACHE="$CACHE_DIR/fleet-snapshot.json"
# Six times the refresher's own interval. Narrower than that and a machine that
# slept through one wake-up reports a dead fleet job every morning, which is the
# false positive that gets a channel muted (CONSTITUTION №2.11).
FLEET_MAX_AGE="${HARBOR_ALERT_PROBE_FLEET_MAX_AGE:-${HARBOR_FLEET_MAX_AGE:-1800}}"
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
ALERT_LIB_DIR="$_pd"; . "$_pd/library-alert.sh"
LOG_FD=2; log_init pulse

# jq missing is not a reason to print nothing — it is the single dependency
# whose absence made every guard exit 0 on 'rm -rf /' (B9). Say so in plain
# text and exit non-zero rather than emitting malformed JSON.
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
  # ASK FOR THE ENTRY ONLY floor-deny.sh WRITES, not for a non-empty list. A
  # deny array is a list anyone may add to, so a single unrelated rule made this
  # read "B1 is live" on a box where every Harbor pattern had been removed.
  # status-generate.sh asks for the sentinel by name; so does this.
  _sentinel='(.permissions.deny // []) | index("Edit(~/.claude/.helm-floor-teeth)")'
  _deny=no
  jq -e "$_sentinel" "$_s" >/dev/null 2>&1 && _deny=yes
  # THE MATRIX, NOT THE BASENAME. floor-install.sh wires five distinct
  # (event, matcher, guard) triples, and a check that flattens them into "does
  # this guard appear anywhere" cannot see the failure the installer's own
  # comment records as pass 11's critical: guard-egress.sh carries dedicated
  # branches for mcp__*, Task/Agent, WebFetch/WebSearch and NotebookEdit, and
  # for months NONE of them could run because only the Bash|Write|Edit matcher
  # was ever wired. The suite missed it "because its wiring assertions only
  # checked the pairs the installer already wired". Same trap, one level up:
  # asking an easier question than the one the row claims to answer.
  #
  # This list is a MIRROR of floor-install.sh and cannot read it — the probe
  # runs from the live config dir with no repo. pulse-test.sh extracts the
  # installer's own `add` lines and fails when the two disagree, which is what
  # keeps a mirror from becoming a fossil.
  _unwired=""; _ntot=0   # _ntot counts the MATRIX rows below, so "no guard wired" tracks the table
  _parsed=yes
  jq -e . "$_s" >/dev/null 2>&1 || _parsed=no
  if [ "$_parsed" = yes ]; then
    while IFS='	' read -r _ev _mt _g; do
      [ -n "$_ev" ] || continue
      _ntot=$((_ntot + 1))
      jq -e --arg e "$_ev" --arg m "$_mt" --arg g "$_g" '
            [.hooks[$e][]? | select(.matcher == $m) | .hooks[]?.command // empty]
            | map(select(test("(^|/)floor-hook[.]sh([[:space:]]|$)")) | select(contains($g)))
            | length > 0' "$_s" >/dev/null 2>&1 \
        || _unwired="$_unwired ${_g%.sh}/${_mt%%|*}"
    done <<'MATRIX'
PreToolUse	Bash	guard-bash.sh
PreToolUse	Bash|Write|Edit|MultiEdit	guard-egress.sh
PreToolUse	mcp__.*|Task|Agent|WebFetch|WebSearch|NotebookEdit	guard-egress.sh
PreToolUse	Write|Edit|MultiEdit	guard-selfedit.sh
PostToolUse	WebFetch|WebSearch|ToolSearch|mcp__.*	annotate-web.sh
PreToolUse	Monitor	guard-bash.sh
PreToolUse	Monitor	guard-egress.sh
PreToolUse	Grep	guard-egress.sh
MATRIX
  fi
  # An EMPTY file parses as neither valid nor invalid to a naive check: jq over
  # zero inputs prints nothing and exits 0, so an earlier version of this code
  # fell through every integer test into its `ok` default and reported a healthy
  # floor on a completely unguarded box. Reachable, not theoretical -
  # deploy-harden.sh writes the live settings with a truncating in-place redirect,
  # so an interrupted apply leaves exactly that file.
  if [ "$_parsed" = no ]; then
    emit floor unknown "the live settings file is empty or could not be parsed"; return 0
  fi
  # ALL SEVEN FILES, not the five that are obviously guards. annotate-web.sh is
  # the B4 PostToolUse guard and floor-normalize.awk is the shared normaliser; a
  # live dir missing either is a partial install that reads as complete. This
  # list started as five, and the suite's agreement assertion against
  # status-generate.sh failed on its first run and named the two.
  _missing=0
  for _f in floor-hook.sh guard-lib.sh guard-bash.sh guard-egress.sh \
            guard-selfedit.sh annotate-web.sh floor-normalize.awk; do
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
    # gitleaks is fail-CLOSED by design: without it worklog-push refuses the
    # commit, silently, on every Stop. A missing sink means this probe's own
    # sink is dead and a CRIT would be seen by nobody.
    emit deps warn "missing:$_warn — a fail-closed gate or the notify sink is down"
  else
    emit deps ok "jq, git, gitleaks and the notify sink are all present"
  fi
}

# ── fleet · the orchestrator snapshot, and whether its writer is alive ───────
# READS FOUR FIELDS AND NO OTHERS. The cache carries each repo's full memory
# store inline, bodies and all — client names, escalation notes, whatever a
# scaffolded repo happens to keep in .agents/memory. §3 makes that the operator's
# business and nobody else's, so this reads descriptor.name, hooks and status
# only, and a notification body never carries even those.
check_fleet() {
  if [ ! -f "$FLEET_CACHE" ]; then emit fleet unknown "no fleet snapshot has been written yet"; return 0; fi
  _m="$(mtime "$FLEET_CACHE")"
  _now="$(date +%s)"
  if [ -n "$_m" ]; then
    _age=$((_now - _m))
    if [ "$_age" -gt "$FLEET_MAX_AGE" ]; then
      # A CLOSED LAPTOP LOOKS EXACTLY LIKE A DEAD REFRESHER, in wall-clock. Both
      # jobs are launchd StartInterval jobs on the same machine, so if OUR last
      # run is also older than the window, nothing was running and the stale
      # cache says nothing about the refresher. Warning here would fire a false
      # WARN on the first probe after every sleep, and a false RECOVERED five
      # minutes later — a flap on a channel whose whole value is that it only
      # speaks when something changed. The notifier passes its previous ran_at.
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
  # ONLY the literal "missing" is a finding. The live snapshot carries a third
  # value — `-` — for a repo the orchestrator could not answer for, and the
  # first cut of this check counted it as broken: it reported three repos in
  # trouble when two were. A predicate of the form "anything that is not OK is
  # bad" turns every future field value into a false alarm, which is the defect
  # that gets a channel muted.
  _bad="$(jq -r '[.[] | select(.hooks == "missing")] | length' "$FLEET_CACHE" 2>/dev/null || printf 'x')"
  _unread="$(jq -r '[.[] | select((.hooks | type) != "string" or (.hooks != "ok" and .hooks != "missing"))] | length' \
              "$FLEET_CACHE" 2>/dev/null || printf 'x')"
  case "$_bad$_unread" in *x*|"") emit fleet unknown "the snapshot could not be read"; return 0 ;; esac
  # Drift is deliberately NOT a verdict. Most repos carry uncommitted work most
  # of the time; alerting on it would notify every day and teach the operator to
  # ignore the channel. Governance hooks missing is the fleet fact that is
  # actually broken rather than merely in progress.
  if [ "$_n" -eq 0 ]; then
    # An empty fleet is a valid fleet — a box with nothing scaffolded yet. The
    # unread-equals-total branch below would otherwise call 0 == 0 an unreadable
    # snapshot and report unknown forever on a clean machine.
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
# THE RECEIPT HAD NO READER. bin/cu-doctor-run.sh writes cu-doctor-state.json and
# its own header calls `ran_at` liveness — "a clean run and a run that never
# happened both leave an empty log". Measured 2026-09-02: nothing on the box read
# it. The repo, ~/.claude/bin and ~/.local/bin between them contained exactly one
# file naming the path, and it was the writer. So the job could stop firing and
# the file would sit there reading `green` forever, which is the same defect one
# level up — a reporter that says zero when it never ran.
#
# THREE STATES, NOT TWO, and `error` is the one that matters most: it means
# cu doctor REFUSED and nothing was checked. A `green` receipt and an `error`
# receipt are equally quiet on stdout; only this tells them apart unattended.
#
# THE THRESHOLD IS 3x THE CADENCE, not the 6x check_fleet uses, and the
# difference is deliberate. Fleet is a 300s job where one sleep cycle explains a
# stale cache; this is a StartCalendarInterval job at 08:47 that launchd fires on
# WAKE when the hour has passed, so a closed laptop still gets its run. Two
# consecutive days with no run is not a laptop being shut, it is the job being
# gone. Overridable, because a box on a different cadence should not have to
# patch this file.
CUDOCTOR_STATE="$CACHE_DIR/cu-doctor-state.json"
CUDOCTOR_MAX_AGE="${HARBOR_ALERT_PROBE_CLICKUP_DOCTOR_MAX_AGE:-${HARBOR_CUDOCTOR_MAX_AGE:-259200}}"
check_cudoctor() {
  if [ ! -f "$CUDOCTOR_STATE" ]; then
    emit cudoctor unknown "no cu doctor receipt has been written yet"; return 0
  fi
  # ran_at, NOT mtime, because that is the field the writer promises and the one
  # its header names. mtime moves if anything touches the file; ran_at only moves
  # when a run actually completed.
  _at="$(jq -r '.ran_at // empty' "$CUDOCTOR_STATE" 2>/dev/null || true)"
  _st="$(jq -r '.status // empty' "$CUDOCTOR_STATE" 2>/dev/null || true)"
  if [ -z "$_st" ]; then
    emit cudoctor unknown "the receipt is not the JSON cu-doctor-run.sh writes"; return 0
  fi
  # BSD date parses the Z form with -j -f; GNU wants -d. Digits or nothing, the
  # same contract mtime() above keeps, for the same reason.
  _ep="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$_at" +%s 2>/dev/null || true)"
  case "$_ep" in ''|*[!0-9]*) _ep="$(date -u -d "$_at" +%s 2>/dev/null || true)" ;; esac
  case "$_ep" in ''|*[!0-9]*) _ep="" ;; esac
  if [ -n "$_ep" ]; then
    _age=$(( $(date +%s) - _ep ))
    if [ "$_age" -gt "$CUDOCTOR_MAX_AGE" ]; then
      # STALENESS OUTRANKS THE VERDICT INSIDE. A receipt saying `green` from six
      # days ago is not evidence the board is clean; it is evidence nothing has
      # looked. Reporting the stored verdict here would be believing a number
      # that predates the question.
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
    # A status the writer does not currently emit is not ok. Every future value
    # arriving as a healthy green is the defect this whole file keeps finding.
    *)       emit cudoctor unknown "unrecognised receipt status \"$_st\"" ;;
  esac
}

# ── worklog · is the git-backed log actually leaving this machine ────────────
# Cleanliness is NOT the signal: the store is dirty by design (IDENTITY.md and
# TELOS/ are untracked forever, outside the staging allowlist). Unpushed commits
# are, because they only accumulate when the Stop push is failing.
check_worklog() {
  _m="$CFG/MEMORY"
  if [ ! -d "$_m/.git" ]; then emit worklog unknown "no work-log repository"; return 0; fi
  if ! command -v git >/dev/null 2>&1; then emit worklog unknown "git is missing"; return 0; fi
  if ! git -C "$_m" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    # session-verdicts.sh owns this one, loudly, once per session. Repeating it
    # as a WARN here would put the same fact on two channels.
    emit worklog unknown "the branch has no upstream (session-verdicts owns this verdict)"
    return 0
  fi
  _ahead="$(git -C "$_m" rev-list --count '@{u}..HEAD' 2>/dev/null || printf 'x')"
  case "$_ahead" in x|"") emit worklog unknown "the work-log could not be read"; return 0 ;; esac
  if [ "$_ahead" -gt 0 ]; then
    emit worklog warn "$_ahead session record(s) committed and never pushed"
    return 0
  fi
  # AHEAD=0 HAS TWO MEANINGS AND ONE OF THEM IS BAD. Everything pushed, or
  # nothing was ever committed — which is what a frozen Stop hook produces: the
  # gitleaks gate is fail-closed, so a missing scanner makes worklog-push refuse
  # the commit, silently, on every session. The ahead-count then sits at 0
  # forever and the check reports a healthy log that has not moved in weeks.
  # Age is the only thing that separates the two. A week is wide enough that a
  # normal stretch of use never trips it and an actual freeze always does; the
  # wording carries both readings because an idle machine is the innocent one.
  # SCOPED TO THE RECORD PATHS. An unscoped `log -1` is refreshed by any commit
  # the store receives — idea commits and pushes IDEAS.md on its own — so a
  # work-log whose Stop hook has been frozen for months reads as fresh the
  # moment the operator files an idea. The staging allowlist in worklog-push.sh
  # is the authority on where a session record lands.
  _last="$(git -C "$_m" log -1 --format=%ct -- 'WORK/sessions' 2>/dev/null || printf '')"
  case "$_last" in ''|*[!0-9]*) emit worklog ok "in sync with the remote"; return 0 ;; esac
  _age=$(( $(date +%s) - _last ))
  if [ "$_age" -gt "${HARBOR_ALERT_PROBE_WORKLOG_MAX_AGE:-${HARBOR_WORKLOG_MAX_AGE:-604800}}" ]; then
    emit worklog warn "nothing committed in $((_age / 86400))d — either nothing ran, or the Stop gate is refusing"
  else
    emit worklog ok "every session record has reached the remote"
  fi
}

# ── dispatch · is the event dispatcher following, if this box runs one ──────
# A NOT FOLLOWING line in checks.log scrolled out of the console's 40-line panel
# within an hour, and launchd lists a job that exited 0 the same way as one that
# is idle (harbor#1044 review r3 #4). So the follower leaves a receipt — status
# following, down, off or stopped, with its pid and reason — and this row is the
# surface: down is crit, and pulse-notify speaks on the change. No receipt is ok,
# not unknown: the dispatcher is opt-in and ships inert, so most boxes have none.
DISPATCH_STATE="$CACHE_DIR/event-dispatch-state.json"
check_dispatch() {
  if [ ! -f "$DISPATCH_STATE" ]; then emit dispatch ok "no event dispatcher has run here (opt-in, shipped inert)"; return 0; fi
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
# ok < unknown < warn < crit. unknown outranks ok deliberately: "I could not
# look" is worse news than "I looked and it was fine", and a run where every
# source was unreadable must not render as a healthy zero.
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
