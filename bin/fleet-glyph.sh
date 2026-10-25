#!/usr/bin/env sh
# L0-5 (harbor#21, extended harbor#59, redesigned harbor#293) — Claude Code statusline.
# Deliberately one file (DOCTRINE/modularity.md): `module-shape.sh --seam` finds no
# seam (2026-09-22), and a split would be a `.` per tick on a path that counts forks.
#
# FOUR ROWS, ONE QUESTION EACH (operator decision 2026-10-16, layout B of
# ~/Deliverables/2026-10-15-statusline-redesign; it replaces the three cadence rows of
# 2026-07-29 and 2026-10-05):
#   row 1  SESSION — the moving numbers, all from the stdin JSON, zero extra reads
#   row 2  PLACE   — which session (its title, up to 64 columns), which repo and branch,
#                    which PR, how many sessions are live
#   row 3  YOU     — what waits on the operator: handoffs and approvals from
#                    the obligations ledger, then every alarm word, coloured by severity.
#                    ABSENT when nothing waits, so colour on this row always means act
#   row 4  BOX     — network, Remote Control, CPU, GPU, RAM, disk, CI and the fleet
# EMOJI ONLY WHERE A GLYPH SAYS MORE THAN A WORD (operator, 2026-10-16: "just in some
# places where it makes sense"): two-state facts (🏠🔒🔓 network,
# 📱📵 Remote Control) and the nautical nouns the line started with (operator, same day): ⛵ live
# sessions and ⚓ fleet berths. No emoji on the YOU row, the cache or a level. Numbers keep their
# word labels (ctx, 5h, CPU, RAM, SSD, swap). ONLY yellow and red carry colour: informational
# tokens are plain, dim or grey, like the session title and the cache share. Every emoji is East-Asian-width W (§2); alarms stay WORDS (§3).
#
# ── THE 2026-08-23 REDESIGN, AND THE FOUR MEASUREMENTS BEHIND IT ─────────────
#
# 1 · ALARMS MOVED LEFT, AMBIENT MOVED RIGHT. The statusline docs state that
#   system notifications (MCP errors, auto-updates) render on the RIGHT SIDE OF
#   THE SAME ROW and "may truncate your status line output". The loudest token on
#   this box — `renew`, four merged floor commits that gate nothing here — was in
#   exactly that column. Truncation must destroy the LEAST important token, so
#   ordering was: alarms · identity · pin · inventory · age.
#
#   REVERSED 2026-08-24 to identity · inventory · age · alarms, at the operator's
#   request and with this cost put to them in these words. The note at the print
#   block carries the decision; this paragraph is left standing because it is the
#   argument AGAINST it, and a reversal whose counter-argument has been deleted is
#   one nobody can re-examine.
#
# 2 · ICONS ARE EMOJI-PRESENTATION ONLY, AND THERE ARE THREE — four until the
#   pushpin was cut on 2026-08-24, and the width rule here is unchanged and binds
#   any icon added later. The operator
#   reported seeing "nothing apart from the anchor", and the reason is measurable:
#   `unicodedata.east_asian_width` is **W** for the anchor and the sailboat, and
#   **N** for the pencil, the up-down arrow and the bare warning sign. A narrow
#   text-presentation dingbat is not drawn from the colour-emoji font, so it
#   renders thin or not at all. Every icon here is verified W (two columns), and
#   the width tiers below count them as two.
#
# 3 · ICONS NAME NOUNS, ALARMS ARE WORDS. Kept from the earlier decision and now
#   load-bearing: the operator read "⚓2 ⚠1" as "two anchors and one hat". An icon
#   carrying an alarm is an icon that gets misread. So ⚓⛵📡 count things and every
#   alarm is a word in caps. THE FOURTH ICON, 📌, WAS REMOVED 2026-08-24 — the
#   recolour left it grey in both states, i.e. an icon that no longer answered its
#   own question, and this rule is why it went rather than gaining a colour back.
#
# 4 · THE JUDGE IS ON THE ROW NOW, AND THAT WAS THE REAL DEFECT. This box had
#   FOUR verdict surfaces and rendered one: the pin hash (green), `renew` (two
#   gaps, far right), `.helm-judge` (crit=1 warn=62, INVISIBLE) and
#   pulse-state.json (ok, invisible). A reader saw `floor✓` and concluded safe
#   while the daily judge held a crit. Two different questions, one of them
#   unasked. `floor✓` became 📌 — it only ever meant "the deny list matches its
#   pin" — and is now the WORD PIN DRIFT alone (2026-08-24); the judge has its own
#   token WITH AN AGE, because the crit that
#   prompted this rested on a single record from three days earlier whose remedy
#   had already run. A verdict with no age cannot be falsified.
#
# WHAT IS DELIBERATELY ABSENT, AND WHY (do not "fix" these):
# • No STORED countdown. The harness CANCELS an in-flight script when a new
#   trigger arrives, so no field may assume it ran recently. Time renders as an
#   age, or a time LEFT, computed at print time from an absolute epoch — never
#   as a stored countdown. This bullet read "No countdown or ETA" until
#   2026-09-23; row 1's reset time (harbor#84) was already a time-left computed
#   this way, and ⏳'s CI estimate (harbor#657, operator request) is the second.
#   The reason stands and binds both: what is stored is WHEN, never HOW LONG.
# • No BURN RATE — but the earlier reason for that ban was wrong and is recorded
#   here so it is not re-argued from it. The ban said a rate cannot be trusted
#   because the script may not have run recently; that does not reach `$ ÷
#   total_duration_ms`, where BOTH operands arrive in the same payload and
#   nothing is stored between ticks. It is out because the operator cut it as
#   noise (2026-08-23), which is a taste call and a legitimate one.
# • No absolute token count beside `ctx N%`. Operator decision 2026-08-23: the
#   model tile already states the window size, so a percentage is sufficient and
#   the absolute is a second encoding of the same fact.
# • No `>200k` threshold token. Operator decision 2026-08-24, and the argument
#   against cutting it is recorded here because it was a real one: the harness
#   reports `exceeds_200k_tokens` independently of window size, so on a 1M model it
#   was the only sign on the row that the cheap-cache regime had been left. The
#   operator does not want the fact, which settles it — a taste call about their own
#   status row, the same class as the burn-rate cut above. `exceeds_200k_tokens`
#   stays in the payload and stays unread. The suite asserts the ABSENCE both ways
#   round, so this line is a rule rather than a note.
# • No `blocks N`. It was a monotonic LIFETIME counter (4,719 against 102,012
#   records) that no action could move, i.e. wallpaper by the third session.
#   `ovr N` survives it: an override is the operator saying a rule is wrong with
#   their hands, and it renders nothing until one happens.
# • No cached floor verdict. /sbin/sha256sum exists on this box and costs 4.0ms
#   measured (shasum 16.8ms), so the integrity check runs LIVE.
#
# ALL ARITHMETIC AND FORMATTING HAPPEN IN jq. Two reasons, both measured:
# rate_limits.used_percentage is utilization*100 with NO rounding
# (0.417 -> 41.699999999999996), and POSIX `[ 41.7 -ge 85 ]` is not false — it is
# an ERROR that `2>/dev/null &&` swallows into silence, i.e. a colour ramp that
# never fires. And reading a TSV with IFS=<tab> COLLAPSES consecutive tabs, so
# one empty field shifts every later field a column left and still looks
# plausible. jq emits the finished string; the shell never parses a number.
#
# NEVER invokes the orchestrator (REVIEW F6): a tick re-runs sub-second and a
# live snapshot is a full-fleet scan. Fleet state is read from the cache written
# by fleet-snapshot-refresh.sh (launchd com.harbor.fleet-snapshot, 5 min).
# Absent/stale/invalid cache degrades to "fleet: unknown".
#
# FLAGS / ENV:
#   --help                 this header
#   HARBOR_GLYPH_DUMP=<f>  append the raw stdin payload to <f> and continue. The
#                          honest way to answer "is that field actually in the
#                          payload on THIS version" — the docs are a claim, one
#                          captured tick is the fact. Off unless set.
#   HARBOR_GLYPH_COLS=<n>  override the terminal width (the suite pins this).
#   HARBOR_GLYPH_STALE_S   fleet-cache staleness ceiling, default 900.
#   HARBOR_NOW=<epoch>     freeze the clock (the suite pins this).
#   HARBOR_GLYPH_MACHINE=0 drop the machine segments of row 3 (the other suites set this);
#                          the CI tokens still show there, so row 3 is gone only when both are empty.
#   HARBOR_GLYPH_MACHINE_REFRESH=0  never spawn the CPU sampler; read its cache only.
set -eu

case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CACHE_DIR="${HARBOR_CACHE_DIR:-$CFG/cache}"
CACHE="$CACHE_DIR/fleet-snapshot.json"
OBS="$CACHE_DIR/guard-decisions.json"
STALE_S="${HARBOR_GLYPH_STALE_S:-900}"

E="$(printf '\033')"
DIM="$E[2m"; RST="$E[0m"; RED="$E[31m"; YEL="$E[33m"; GRN="$E[32m"
CYN="$E[36m"; BLU="$E[34m"; MAG="$E[35m"; BLD="$E[1m"
# DARK GREY, AND IT IS A DIFFERENT THING FROM DIM (operator decision 2026-08-24).
# `$E[2m` is a faint ATTRIBUTE applied to whatever colour is current, and several
# terminals render it as plain or ignore it outright; `$E[90m` is bright-black, an
# actual colour, so it is the same grey everywhere and it OVERRIDES an inherited
# red or yellow rather than tinting it. That distinction is the whole reason this
# variable exists: the harbor-state tokens below were red and yellow, and dimming
# them would have left them red and yellow on most terminals.
GREY="$E[90m"

# ── the separator grammar (operator request 2026-08-24) ──────────────────────
# THREE RELATIONSHIPS WERE BEING CARRIED BY TWO SPACES AND ONE MIDDOT, and the
# reader had to already know which was which. The reported case was
# `$1.57  5h 1% ·4h13m  7d 49% ·1d19h`: four durations and two percentages, where
# the only thing distinguishing "a different fact" from "more about the fact to my
# left" was one space against two. That distinction does not survive a glance, and
# it does not survive a terminal that renders spacing tightly either.
#
# SO THE ROW HAS A GRAMMAR NOW, AND IT IS EXACTLY TWO MARKS. What separates them
# is the TRAILING space, not the character — say it that way, because the first
# draft of this comment said the middot takes no space before it, which is simply
# untrue of every middot on the row:
#   ` │ `  a DIFFERENT fact       — space, bar, space
#   ` ·`   MORE ABOUT the fact on its left — space, middot, then the value with no
#          gap: `5h 1% ·in 4h13m`, `⛵2 ·2 busy`
# A single space with no mark is the third relationship and the commonest: "same
# fact, next part of it" (`harbor main wt ~3 #294`).
#
# AND TWO CONSECUTIVE SPACES NOW MEAN NOTHING AT ALL — they are the state this
# change removed, so the suite asserts the rendered rows contain none. That one
# assertion is the whole grammar-guard: any future token appended with the old
# double-gap idiom fails it, and nothing else would have noticed.
#
# A THIRD MARK EXISTS AND IS DELIBERATELY NOT OURS. `runtime4·floor5` is
# renew-check.sh's vocabulary, borrowed verbatim — see the note at the STALE tile
# for why re-spelling another tool's naming here is a defect rather than a tidy-up.
#
# ONE COLUMN, NOT TWO, AND THAT IS THE PART A TEST CANNOT SEE. U+2502 is
# single-width where every emoji on row 2 is double. The tiers pick by which
# tokens they include and never by measuring the finished string — this file's own
# header explains why — so a separator that quietly changed width would widen
# every row with nothing to catch it.
SEP="${DIM}│${RST}"

IN="$(cat 2>/dev/null || true)"

# THE RAW PAYLOAD, ON REQUEST. Claude Code hands this script the only copy of the
# session JSON that exists; nothing else on the box can produce one. Without a
# dump hook, "does this version really send effort.level" is answerable only from
# documentation, and CONSTITUTION §2.5 is explicit that a source which exists is
# not a source that supports the claim. One tick with this set settles it.
if [ -n "${HARBOR_GLYPH_DUMP:-}" ] && [ -n "$IN" ]; then
  ( umask 077; printf '%s\n' "$IN" >> "$HARBOR_GLYPH_DUMP" ) 2>/dev/null || true
fi

# ── terminal width → render tier ─────────────────────────────────────────────
# Claude Code CAPTURES this script's output rather than attaching it to the tty,
# so `tput cols` cannot work here and the docs say so; COLUMNS/LINES are exported
# instead (v2.1.153+). An UNREADABLE width is not a narrow one: 0 and unset both
# mean "unknown" and take the full render, because silently dropping fields on a
# wide terminal is the failure nobody would report.
#
# EVERY ICON IS TWO COLUMNS. The tiers are chosen by which tokens they include,
# never by measuring the finished string — an ANSI-laden string containing
# double-width emoji has no correct `${#s}`, and a width computed from one is the
# confident wrong number this file's own rules forbid.
_c="${HARBOR_GLYPH_COLS:-${COLUMNS:-0}}"
case "$_c" in ''|*[!0-9]*) _c=0 ;; esac
if   [ "$_c" -eq 0 ]   || [ "$_c" -ge 120 ]; then TIER=full
elif [ "$_c" -ge 100 ]; then TIER=wide
elif [ "$_c" -ge 80 ];  then TIER=mid
else                         TIER=narrow
fi

# ── the session-state bridge (harbor#1043, #1044) ────────────────────────────
# The statusline is the one place that is told how full the context is, so it hands that to the Stop hook:
# $STATE/ctx/<session_id> holds ctx_pct, one integer, re-scaled to CLAUDE_CODE_AUTO_COMPACT_WINDOW when that
# is set (used_percentage is measured against the model window and stops predicting compaction once an
# earlier window is configured). The row itself still shows the payload's own percentage, unchanged.
# It also reads the state record hooks/session-state/session-state.sh wrote at the last Stop and shows one token for it,
# only while the payload's prompt_id is the one the record was written for: a new prompt means the record
# is a turn old, and a stale `? you` on a working session is a lie.
STTOK=""
if [ -n "$IN" ] && command -v jq >/dev/null 2>&1; then
  _gs="$(printf '%s' "$IN" | jq -r '[(.session_id // "-"), (.prompt_id // "-"), (.context_window.used_percentage // "-"), (.context_window.context_window_size // "-")] | map(tostring | if . == "" then "-" else . end) | join(" ")' 2>/dev/null || true)"
  _gsid="-"; _gpid="-"; _gpct="-"; _gwin="-"
  read -r _gsid _gpid _gpct _gwin <<GLYPH_BRIDGE || true
$_gs
GLYPH_BRIDGE
  _SDIR="${HARBOR_STATUS_DIR:-${HOME:-/nonexistent}/.local/state/harbor}"
  case "$_gsid" in ''|-|*[!A-Za-z0-9_-]*) ;; *)
    case "$_gpct" in ''|-|*[!0-9.]*) ;; *)
      _cx="$(awk -v p="$_gpct" -v w="$_gwin" -v a="${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}" 'BEGIN {
        if (a ~ /^[0-9]+$/ && a + 0 >= 100000 && w ~ /^[0-9]+$/ && w + 0 > 0) { if (a + 0 > w + 0) a = w; p = p * w / a }
        if (p > 100) p = 100; printf "%d", p + 0.5 }' 2>/dev/null || true)"
      if [ -n "$_cx" ]; then
        _cf="$_SDIR/ctx/$_gsid"; _old=""
        [ ! -r "$_cf" ] || read -r _old < "$_cf" 2>/dev/null || true
        if [ "$_old" != "$_cx" ] && mkdir -p "$_SDIR/ctx" 2>/dev/null; then
          { printf '%s\n' "$_cx" > "$_cf.$$" && mv -f "$_cf.$$" "$_cf"; } 2>/dev/null || rm -f "$_cf.$$" 2>/dev/null || true
        fi
      fi ;;
    esac
    # event.session-check's verdict (bin/session-check.sh) outlives the turn it was made in, so it is not prompt-gated:
    # hooks/session-state/session-state.sh removes it when the session leaves `done`.
    _ck=""; [ ! -r "$_SDIR/sessions/$_gsid.check" ] || read -r _ck < "$_SDIR/sessions/$_gsid.check" 2>/dev/null || true
    _cktok=""; case "$_ck" in red*) _cktok="${RED}lint ✗${RST}" ;; esac
    _rf="$_SDIR/sessions/$_gsid.json"
    if [ -r "$_rf" ]; then
      _r="$(head -c 4096 "$_rf" 2>/dev/null || true)"
      case "$_gpid" in -) _fresh=0 ;; *) case "$_r" in *"\"prompt_id\":\"$_gpid\""*) _fresh=1 ;; *) _fresh=0 ;; esac ;; esac
      if [ "$_fresh" = 1 ]; then
        _st="${_r#*\"state\":\"}"; _st="${_st%%\"*}"
        _ag="${_r#*\"agents\":}"; _ag="${_ag%%[!0-9]*}"
        case "$_st" in
          done)             STTOK="${DIM}✓ done${RST}" ;;
          waiting-operator) STTOK="${YEL}? you${RST}" ;;
          waiting-agents)   STTOK="${DIM}⧗ ${_ag:-?} agents${RST}" ;;
          blocked)          STTOK="${RED}✗ red${RST}" ;;
        esac
      fi
    fi
    [ -z "$_cktok" ] || STTOK="${STTOK:+$STTOK }$_cktok" ;;
  esac
fi

# ── row 1 · the moving numbers ───────────────────────────────────────────────
# One jq pass, fully rendered. An absent field contributes ZERO columns: no
# label, no gap, no placeholder. `// null` then an explicit empty-list branch,
# never `// 0` — 0% is the most dangerous plausible wrong number here, because
# it reads as "plenty of room" in precisely the state where there is none.
ROW1=""
# THE CLOCK IS INJECTED, NOT READ INSIDE jq. jq's `now` would make the reset
# countdowns below unpinnable — a golden-output suite cannot assert on a value
# that moves between the fixture and the assertion. HARBOR_NOW lets the suite
# freeze it; nothing else sets it, so live rendering takes the real clock.
NOW_EPOCH="${HARBOR_NOW:-$(date +%s)}"
if [ -n "$IN" ] && command -v jq >/dev/null 2>&1; then
  ROW1="$(printf '%s' "$IN" | jq -r --arg dim "$DIM" --arg rst "$RST" \
                                    --arg red "$RED" --arg yel "$YEL" \
                                    --arg grn "$GRN" --arg cyn "$CYN" --arg blu "$BLU" --arg mag "$MAG" \
                                    --arg tier "$TIER" --arg sep " $SEP " --arg st "$STTOK" \
                                    --argjson now "$NOW_EPOCH" '
    def ramp(p): if p >= 90 then $red elif p >= 70 then $yel else "" end;
    # Context also says when it is roomy: green under half (operator ask 2026-10-16, more colour).
    def ramp3(p): ramp(p);
    def pad2(n): (if n < 10 then "0" else "" end) + (n | tostring);
    # WHEN THE WINDOW REFILLS. A percentage answers "how much is left"; the
    # question you actually have at 91% is "how long until I can work again",
    # and that is a subtraction the reader should not have to do in their head.
    # `resets_at` is documented as present only for Claude.ai subscribers after
    # the first API response, with each window independently absent — so this
    # returns "" and contributes ZERO columns rather than a placeholder.
    #
    # A RESET IN THE PAST IS DROPPED, not rendered as 0m. A stale payload is the
    # one case where a countdown would state something false with total
    # confidence, and "0m" reads as "about to refill" when it may mean the field
    # is simply old.
    #
    # AND IT SAYS `in`. `5h 1% ·4h13m` puts two durations in one token that mean
    # opposite things — the LENGTH of the window and the time REMAINING in it — and
    # the middot says only "related", never which. Three characters buy that, and
    # the alternative considered and rejected was a refresh glyph: ambiguous-width
    # in several fonts, which the tier note in the header explains cannot be
    # measured here.
    #
    # NO APOSTROPHE MAY APPEAR IN THIS BLOCK, and that is not a style rule. Every
    # comment from here down to the join sits inside a single-quoted jq program, so
    # a single apostrophe closes the quote and the shell parses the rest of the
    # program as code. It cost two rounds to find while writing this very comment:
    # the failure surfaces as "bad substitution: no closing )" pointing at a line
    # that reads like ordinary prose, and the prose is the bug.
    def resets(t):
      if (t // null) == null then ""
      else ((t - $now) | floor) as $s
        | if   $s <= 0     then ""
          elif $s < 60     then " ·in <1m"
          elif $s < 3600   then " ·in " + (($s / 60) | floor | tostring) + "m"
          elif $s < 86400  then " ·in " + (($s / 3600) | floor | tostring) + "h"
                                        + pad2((($s % 3600) / 60) | floor) + "m"
          else                  " ·in " + (($s / 86400) | floor | tostring) + "d"
                                        + pad2((($s % 86400) / 3600) | floor) + "h"
          end
      end;
    def money(x): (x * 100 | round) as $c
      | "$" + (($c / 100) | floor | tostring) + "."
            + (if ($c % 100) < 10 then "0" else "" end) + (($c % 100) | tostring);
    # THE WINDOW SIZE IS DERIVED FROM THE FIELD, NEVER READ OFF THE NAME.
    # `display_name` happens to read "Opus 5 (1M context)" today, so appending a
    # size would print it twice; a name without the parenthetical would print it
    # never. Strip any trailing parenthetical and state the size from
    # context_window_size, which is the field that actually knows.
    def wsize(n): if   n >= 1000000 then ((n / 1000000) | floor | tostring) + "M"
                  elif n >= 1000    then ((n / 1000)    | floor | tostring) + "k"
                  else (n | tostring) end;
    (((.model.display_name // "claude") | sub(" *\\([^)]*\\)$"; "")) as $mn
     | (.context_window.context_window_size // null) as $ws
     | if $ws == null then $mn else $mn + " " + wsize($ws) end) as $model
    # EFFORT IS ON THE ROW BECAUSE IT MOVES AND IT IS EXPENSIVE. The field
    # reflects mid-session /effort changes, and a session silently running at
    # `max` costs a multiple of one running at `medium`. xhigh and max are
    # yellow: not an alarm, a price tag. Absent when the model has no effort
    # parameter, and then it costs zero columns. Model and effort are one fact
    # in two parts, so they share the brain tile and a plain space.
    | (if (.effort.level // null) == null then ""
       else (.effort.level | ascii_downcase) as $e
            | " " + (if $e == "max" or $e == "xhigh" then $yel + ($e | ascii_upcase) + $rst
                     elif $e == "high" then $e
                     else $dim + $e + $rst end) end) as $eff
    | [ $dim + $model + $rst + $eff ]
    # THE EXCEPTIONS ONLY. `fast` renders when fast mode is ON; `no-think` when
    # extended thinking is OFF. Rendering the ordinary state of either would be a
    # token that never changes, which is the wallpaper failure this file names
    # twice elsewhere.
    + (if (.fast_mode // false) then [ $yel + "fast" + $rst ] else [] end)
    + (if (.thinking // null) != null and (.thinking.enabled == false)
       then [ $dim + "no-think" + $rst ] else [] end)
    # CONTEXT AS A PERCENTAGE, AND NOTHING ELSE (operator decisions 2026-08-23 and
    # 2026-08-24). The absolute count went first: the model tile above states the
    # window size, so it was the same fact spelled twice. The `>200k` threshold
    # followed, cut on 08-24 — see the absent-by-decision list in the header for
    # the argument that was made FOR keeping it, which was a good one and lost.
    # `exceeds_200k_tokens` is still in the payload; it is deliberately unread.
    + (if (.context_window.used_percentage // null) == null then []
       else (.context_window.used_percentage | round) as $p
            | [ ramp3($p) + "ctx " + ($p | tostring) + "%" + $rst ] end)
    # THE SESSION STATE (hooks/session-state/session-state.sh, via the bridge above): done, waiting on you, N agents, red.
    + (if $st != "" then [ $st ] else [] end)
    # CACHE SHARE — cache_read / (input + cache_read + cache_creation): how much
    # of the live context came from cache instead of being re-sent.
    #
    # THE TWO GUARDS BELOW OVERLAP, AND NEITHER IS INDIVIDUALLY KILLABLE BY A
    # TEST. Do not delete one on the strength of a green suite. Removing the null
    # check alone leaves $u null, so each `// 0` yields 0, so $tot is 0, so the
    # `<= 0` branch suppresses the column anyway — same observable. Removing the
    # `<= 0` check alone is covered by the null check for the same reason.
    # Removing BOTH is what bites: jq raises on division by zero, the whole row-1
    # pass dies, and 16 assertions go red (verified 2026-07-31). A null
    # current_usage and a present-but-all-zero one are observationally identical,
    # so no assertion can separate them — this comment is the only mechanism.
    #
    # The null case is not hypothetical: the schema documents current_usage as
    # null before the first API call AND AGAIN AFTER EVERY /compact until the next
    # one. "cache 0%" there would be a confident wrong number in the exact moment
    # the context was just rebuilt.
    + (if $tier == "narrow" or $tier == "mid" or $tier == "wide" then []
       elif (.context_window.current_usage // null) == null then []
       else .context_window.current_usage as $u
            | (($u.input_tokens // 0)
               + ($u.cache_read_input_tokens // 0)
               + ($u.cache_creation_input_tokens // 0)) as $tot
            | if $tot <= 0 then []
              else ((($u.cache_read_input_tokens // 0) * 100) / $tot | round) as $h
                   | [ $dim + "cache " + ($h | tostring) + "%" + $rst ] end end)
    + (if (.cost.total_cost_usd // null) == null then []
       else [ money(.cost.total_cost_usd) ] end)
    # The countdown sits INSIDE the colour span, so a red 5h reads as one unit
    # rather than a red number beside an uncoloured time.
    + (if (.rate_limits.five_hour.used_percentage // null) == null then []
       else (.rate_limits.five_hour.used_percentage | round) as $q
            | [ ramp3($q) + "5h " + ($q | tostring) + "%"
                + resets(.rate_limits.five_hour.resets_at) + $rst ] end)
    + (if $tier == "narrow" then []
       elif (.rate_limits.seven_day.used_percentage // null) == null then []
       else (.rate_limits.seven_day.used_percentage | round) as $w
            | [ ramp3($w) + "7d " + ($w | tostring) + "%"
                + resets(.rate_limits.seven_day.resets_at) + $rst ] end)
    | join($sep)' 2>/dev/null || true)"
fi

# ── row 2 · the ground ───────────────────────────────────────────────────────
# BUILT IN THREE ZONES, AND THE ZONE ORDER IS THE FIX:
#   ALARM   things to act on, leftmost, words in caps, absent when clean
#   GROUND  which session, which tree, which PR — and the pin
#   AMBIENT inventory and cache age, rightmost, where truncation is harmless
# The statusline docs put system notifications on the right of this same row and
# say they "may truncate your status line output". Everything on the right must
# therefore be something you can afford to lose mid-sentence.
ALARM=""; GROUND=""; AMBIENT=""; CIAMB=""; CIALM=""
# THE ZONE OWNS THE COLOUR, NOT THE CALLER (operator decision 2026-08-24). Every
# harbor-state token is dark grey now, and the enforcement is HERE rather than at
# the fourteen call sites that used to spell ${RED} and ${YEL} themselves. One
# place cannot drift; fourteen can, and the fifteenth caller would arrive red.
#
# WHY NOT STRIP THE CALLER ANSI INSTEAD. Stripping needs a `sed` per token — this
# file's header explains that a statusline paying forks per tick is a statusline
# you switch off, and it would be 14 of them. So callers pass PLAIN TEXT and the
# suite asserts row 2 contains no red, yellow or green at all. That assertion is
# the mechanism: without it this is a convention, and a convention is a wish.
#
# SEVERITY COLOUR RETURNS, ON THE YOU ROW ONLY (operator decision 2026-10-16). The
# 2026-08-24 grey was right for a row that mixed alarms with inventory: colour there
# competed with the facts. YOU holds nothing but things to act on, so its colour has
# one meaning, and severity is decided HERE, by the word, in one place: red when
# something is broken or unsafe now, yellow when it is waiting. Callers still pass
# plain text, and the suite asserts PLACE and BOX inventory stay uncoloured grey.
sev() { # <text> [red|yel]: a given level wins over the word lookup
  case "${2:-}" in red) _sv="$RED"; return ;; yel) _sv="$YEL"; return ;; esac
  case "$1" in
    "MAIN RED"*|"PIN "*|"STALE "*|"CI STALL"*|"CI EMERG"*|"DOCKER DOWN"*|\
    "RUNNER "*|"CI NO RUNNER"*|"SHARED TREE"*|"WATCH "*|"PLAN "*|"GATE "*) _sv="$RED" ;;
    *) _sv="$YEL" ;;
  esac
}
alarm() { sev "$1" "${2:-}"; ALARM="$ALARM${ALARM:+ $SEP }$_sv$1${RST}"; }
# The fleet tile is the only ambient left: grey like every informational token.
ambient() { AMBIENT="$AMBIENT${AMBIENT:+ $SEP }${GREY}$1${RST}"; }
# CI alarms join YOU; CI inventory joins BOX (harbor#1032 put both on the machine row).
ci_alarm() { sev "$1"; CIALM="$CIALM${CIALM:+ $SEP }$_sv$1${RST}"; }
ci_ambient() { CIAMB="$CIAMB${CIAMB:+ $SEP }${GREY}$1${RST}"; }

DIR=""
if [ -n "$IN" ] && command -v jq >/dev/null 2>&1; then
  DIR="$(printf '%s' "$IN" | jq -r '.workspace.current_dir // empty' 2>/dev/null || true)"
fi
[ -n "$DIR" ] || DIR="$PWD"

# WHICH TERMINAL IS THIS, AND WHAT IS IT WORKING ON (owner request 2026-07-31).
# With several terminals open on the same repo, dir+branch identifies the WORK but
# not the SESSION — two windows on the same branch render identically, which is
# exactly when you need to tell them apart.
#
# `session_name` is the real answer, and it is ABSENT until a name exists (a
# custom one from `/rename`/`--name`, or an AI-generated title); the default
# display name like `harbor-3f` does NOT populate it. So a name-or-nothing field
# would show nothing on a fresh terminal, i.e. it would fail the request in the
# common case.
#
# Hence a two-tier field, VISUALLY DISTINCT rather than merged: a chosen name
# renders bright, a session-id stem renders dim. Reading a dim stem tells you the
# session is unnamed and `/rename` will fix it; a merged rendering would teach
# you to read an opaque 6-char token as if it were a name. `agent.name` sits
# between them because an --agent session's identity IS the agent.
NAME=""; NAME_KIND=""; PRTOK=""; WTMARK=""; REPO=""
if [ -n "$IN" ] && command -v jq >/dev/null 2>&1; then
  # `kind SP name` — kind never contains a space, so ${x%% *} / ${x#* } is exact.
  # NOT a tab-separated pair: this file's own header records that reading TSV with
  # IFS=<tab> collapses consecutive tabs, so one empty field shifts the rest and
  # still looks plausible.
  _nm="$(printf '%s' "$IN" | jq -r '
    def nz(x): (x // "") | tostring | if . == "" then empty else . end;
    first(
      ("named " + nz(.session_name)),
      ("agent " + nz(.agent.name)),
      ("id " + nz((.session_id // "") | .[0:6]))
    )' 2>/dev/null || true)"
  case "$_nm" in
    *" "*) NAME_KIND="${_nm%% *}"; NAME="${_nm#* }" ;;
  esac

  # THE OPEN PR FOR THIS BRANCH, AND ITS REVIEW STATE. Harbor's whole workflow is
  # PR-gated and the review gate has been merged past once, over two real findings
  # including a crash — so "is there a PR and has anyone approved it" is a fact
  # with a history on this box, not a decoration. `pr.review_state` may be absent
  # independently of `pr`, and `pr.kind == "mr"` means a GitLab merge request, so
  # the number takes the `!` sigil that platform uses.
  PRTOK="$(printf '%s' "$IN" | jq -r --arg dim "$DIM" --arg rst "$RST" \
                                     --arg red "$RED" --arg grn "$GRN" --arg yel "$YEL" '
    if (.pr.number // null) == null then empty
    else (if (.pr.kind // "") == "mr" then "!" else "#" end) as $sig
      | ($sig + (.pr.number | tostring)) as $n
      | (.pr.review_state // "") as $s
      | (if $s == "approved"   then $n + " approved"
        elif $s == "changes_requested" then $red + $n + " changes" + $rst
        elif $s == "draft"             then $dim + $n + " draft" + $rst
        elif $s == "pending"           then $dim + $n + " pending" + $rst
        else $dim + $n + $rst end)
    end' 2>/dev/null || true)"
  # THE REPO, NOT THE DIRECTORY. A linked worktree is named for its task, so the
  # directory alone hides which repo it belongs to; the payload names the repo
  # (workspace.repo.name) and the directory is the fallback when it does not.
  REPO="$(printf '%s' "$IN" | jq -r '.workspace.repo.name // empty' 2>/dev/null || true)"

  # IN A WORKTREE OR IN THE MAIN TREE. `workspace.git_worktree` is documented as
  # ABSENT in the main working tree and populated for ANY linked worktree — which
  # makes the safe state the labelled one and the hazardous state the blank one.
  # That is backwards for this box: the measured incident was three files reverted
  # to HEAD mid-suite in the MAIN tree by another session, while the peers who did
  # it were each on their own worktree. So the marker is dim here and the alarm is
  # carried by the ships tile instead, which is the thing that knows about peers.
  WTMARK="$(printf '%s' "$IN" | jq -r 'if (.workspace.git_worktree // "") == "" then empty else "wt" end' 2>/dev/null || true)"
fi

# CAPPED, BECAUSE THE NAME IS THE ONE FIELD SOMETHING ELSE WRITES (operator
# decision 2026-08-24). `session_name` carries a chosen name from /rename OR an
# AI-generated title, and a title is prose — "investigating the statusline
# separator grammar and the FC-2 repair wording" is a plausible one. Every other
# token on this row has a bounded width by construction; this one does not, and an
# unbounded leading token pushes the whole row into the truncation zone the note at
# the print block just accepted for the alarms. So the row leads with the topic and
# the topic cannot expand the row.
#
# 48 COLUMNS AND AN ELLIPSIS. Cut on a character count rather than a word boundary:
# a word-boundary cut is a variable-width cut, which is the thing being prevented.
# ${#NAME} is byte length in POSIX sh, so a multibyte title caps shorter in columns
# than 48 rather than longer — the safe direction, and stated because the opposite
# would silently defeat the cap.
#
# RAISED FROM 24 (operator decision 2026-08-24). 24 cut real names mid-word —
# "Click up milestone regi…" — which loses the fact the token exists to carry, so
# the cap was costing more than the row width it bought. 48 fits the names
# actually in use here while still bounding the row: the cap is what stops one
# prose title from pushing the alarms on the right into the terminal's own
# truncation, so it is raised rather than removed. HARBOR_GLYPH_NAME_CAP overrides
# it per-session for anyone who wants a different trade.
#
# RAISED TO 80 (operator decisions 2026-10-16: "at least 60", then 80). The title now leads
# its own row, PLACE, and the alarms it used to push off the edge live on YOU, so
# the cost that justified 48 is gone; the cap still bounds the one prose field.
NAME_CAP="${HARBOR_GLYPH_NAME_CAP:-80}"
case "$NAME_CAP" in ''|*[!0-9]*|0) NAME_CAP=24 ;; esac
if [ -n "$NAME" ] && [ "${#NAME}" -gt "$NAME_CAP" ]; then
  _keep=$((NAME_CAP - 1))
  NAME="$(printf '%.*s…' "$_keep" "$NAME")"
fi
if [ -n "$NAME" ]; then
  case "$NAME_KIND" in
    named) GROUND="${BLD}${NAME}${RST}" ;;
    agent) GROUND="${DIM}@${NAME}${RST}" ;;
    *)     GROUND="${DIM}${NAME}${RST}" ;;
  esac
  # WHICH SESSION is a different fact from WHICH TREE, so it takes the boundary
  # mark. This was the one place a SPACED middot was doing a separator's job
  # (`2df546 · someone`) while a TIGHT middot two tokens away meant sub-fact
  # (`·18h`) — the same character, two opposite meanings, on one row.
  GROUND="$GROUND $SEP"
fi
# …and everything after it is ONE fact in several parts — tree, branch, worktree
# mark, dirty count, PR — so those stay space-joined. That is now what a space
# means, and it is the reason the cluster does not need a mark of its own.
# Branch and the shared git dir in ONE rev-parse: the second line names the repo when
# the payload does not (a linked worktree's common dir is <repo>/.git).
br=""
if _rp="$(git -C "$DIR" rev-parse --abbrev-ref HEAD --path-format=absolute --git-common-dir 2>/dev/null)"; then
  br="${_rp%%
*}"; _gc="${_rp#*
}"
  if [ -z "$REPO" ] && [ "$_gc" != "$_rp" ]; then
    case "$_gc" in */.git) _gc="${_gc%/.git}"; REPO="${_gc##*/}" ;; esac
  fi
fi
GROUND="$GROUND${GROUND:+ }${REPO:-${DIR##*/}}"
[ -n "$WTMARK" ] && GROUND="$GROUND ${DIM}${WTMARK}${RST}"

# Branch + dirty count. -uall, not -uno: untracked files are how a stray scratch
# file reaches a commit, and -uno reports a clean tree on this very box while two
# untracked files sit in bin/. A count is a count, never a guess.
if [ -n "$br" ]; then
  GROUND="$GROUND $br"
  n="$(git -C "$DIR" status --porcelain -uall 2>/dev/null | wc -l | tr -d ' ')"
  # 0 renders NOTHING, not a tick. Absence of the marker IS the clean signal; a
  # tick would be a second symbol to learn carrying no new information.
  [ "${n:-0}" -gt 0 ] && GROUND="$GROUND ${DIM}~$n${RST}"
fi
[ -n "$PRTOK" ] && GROUND="$GROUND $PRTOK"

# ── ⛵ ships · live sessions, how many are busy, how many share this tree ─────
# (L0-11, harbor#75; rewritten 2026-08-23 onto the registry.)
#
# THE OLD TOKEN COULD NOT FIRE WHERE IT MATTERED, TWICE OVER. It required
# `src=write` on a peer record and counted only peers, so with five live sessions
# — four launched in $HOME — it rendered nothing while the SessionStart hook in
# the same terminal announced four peers. Dropping the filter fixed the silence
# and exposed the second half: `.helm-peers` is written by context-resolve.sh, so
# a session that has run no tool has NO RECORD, and the count read 3 of 5.
#
# TWO SOURCES, EACH USED FOR WHAT IT ACTUALLY KNOWS:
#   • the COUNT and the busy/idle split come from Claude Code's own session
#     registry ($CFG/sessions/<pid>.json), which covers a session from the moment
#     it starts, before it has done anything.
#   • the TREE attribution comes from `.helm-peers`, because harbor#75 measured
#     the registry's `cwd` to be the LAUNCH directory — as is `lsof -d cwd` — so
#     a tree count keyed on it reads 2-in-this-tree for two sessions that share
#     only the terminal they were started from.
# Neither source can answer the other's question, and the previous code failed by
# asking one source both.
#
# NO FORKS FOR THE COUNT. The registry is keyed by pid IN THE FILENAME, so the
# pid needs no parse, and liveness is `kill -0` — a shell builtin. The registry
# does not self-reap, and fleet-sessions.sh defeats a recycled pid by comparing
# `procStart` against `ps -o lstart` within a 90s window; that costs a fork per
# session and is deliberately NOT done here. This is a display count, and paying
# five forks per tick to sharpen it in a rare case is how a statusline becomes
# the slow thing you switch off. fleet-sessions.sh remains the accurate answer.
#
# STATUS IS COUNTED, NEVER RENDERED. fleet-sessions.sh records that registry
# `name` and `status` are PEER-SUPPLIED — writable by another session or a crafted
# file — and bounds them before display for that reason. Counting is immune to it:
# the comparison is against the literal string `busy` and what reaches the row is
# a digit this script produced. Echoing a peer field would be a cross-session
# instruction channel; a tally is not.
SESSDIR="${HARBOR_SESSIONS_DIR:-$CFG/sessions}"
SHIPS=0; BUSY=0; HERE=1
for _sf in "$SESSDIR"/*.json; do
  [ -f "$_sf" ] || continue
  _sp="${_sf##*/}"; _sp="${_sp%%.*}"
  case "$_sp" in ''|*[!0-9]*) continue ;; esac
  kill -0 "$_sp" 2>/dev/null || continue
  SHIPS=$((SHIPS + 1))
  # No jq: one substring test on the record, which cannot be turned into a
  # different question by its contents the way a rendered field could.
  case "$(cat "$_sf" 2>/dev/null)" in *'"status":"busy"'*) BUSY=$((BUSY + 1)) ;; esac
done
# DEGRADE TO 1, NEVER TO 0. An unreadable or absent registry means this script
# cannot see itself, and "0 sessions" printed by a session is a visibly false
# number. One is the floor the row can always defend.
[ "$SHIPS" -gt 0 ] || SHIPS=1

if [ -d "$CFG/.helm-peers" ]; then
  _mysid=""
  if [ -n "$IN" ] && command -v jq >/dev/null 2>&1; then
    _mysid="$(printf '%s' "$IN" | jq -r '.session_id // empty' 2>/dev/null || true)"
  fi
  _mytree="$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$DIR")"
  for _pf in "$CFG"/.helm-peers/*; do
    [ -f "$_pf" ] || continue
    case "${_pf##*/}" in "$_mysid") continue ;; esac
    _ptree=""; _ppid=""
    while IFS='=' read -r _pk _pv; do
      case "$_pk" in tree) _ptree="$_pv" ;; pid) _ppid="$_pv" ;; esac
    done < "$_pf"
    case "$_ppid" in ''|*[!0-9]*) continue ;; esac
    kill -0 "$_ppid" 2>/dev/null || continue
    [ "$_ptree" = "$_mytree" ] && HERE=$((HERE + 1))
  done
fi

# THE COUNT IS INVENTORY; THE SHARED TREE IS AN ALARM. `here > 1` is the exact
# condition under which uncommitted work has actually been lost on this box —
# three files reverted to HEAD mid-suite, git status clean, no stash — so it must
# not live in the ambient zone, which the narrow tier drops entirely. Inventory
# is what you can afford to lose off the right edge; this is not.
# ⛵ on PLACE now (2026-10-16): live sessions are part of where this one stands.
PEERS=""
case "$TIER" in
  full|wide) if [ "$BUSY" -gt 0 ]; then PEERS="⛵$SHIPS ·$BUSY busy"
             else PEERS="⛵$SHIPS"; fi ;;
  mid)       PEERS="⛵$SHIPS" ;;
esac
[ "$HERE" -gt 1 ] && alarm "SHARED TREE $HERE"

# ── ⚓ berths · the fleet snapshot ────────────────────────────────────────────
# Rendering owes the cache AGE, because a glyph that cannot say how old it is
# cannot be told apart from a glyph that is current.
#
# DRIFT LEFT THIS TILE (2026-08-23) and became an alarm word. It was `⚠N` here,
# and ⚠ is East-Asian-width N — a narrow text-presentation dingbat that this
# terminal does not draw from the emoji font. An alarm rendered in a glyph the
# operator cannot see is worse than no alarm, because the tile still looks
# populated.
#
# THE DRIFT PREDICATE COUNTS THE VERDICT, NOT THE MANIFEST. It was
# `(.drift.total // 0) > 0`, and drift.total is the number of files the manifest
# COVERS: projects-orchestrator states it in the docstring (drift.py:36) and sets
# it from `len(manifest)` (drift.py:113). So the alarm counted every repo that
# carried a manifest AT ALL — the live box showed 8 with only 7 drifted, because
# `zarija` reports status "clean", modified [] and missing [] against a 126-file
# manifest. The alarm could not reach 0 while any repo was scaffolded.
#
# NO APOSTROPHES IN THE jq BLOCK BELOW. It is a shell single-quoted string, so one
# apostrophe ends it early: measured, a first draft of a comment there took
# statusline-test from 79 passed / 0 failed to 54 passed / 25 failed and made the
# glyph print nothing at all.
#
# `no-manifest` deliberately does NOT count, and that is the weaker half: an
# UNMEASURED repo reads exactly like a clean one. Widening it would put
# project-init permanently in the alarm; the tradeoff is asserted in
# tests/hooks/statusline.fleet-test.sh so it stays a decision.
BERTHS=""; DRIFTN=0; AGETOK=""
if [ -f "$CACHE" ] && command -v jq >/dev/null 2>&1; then
  now="$(date +%s)"
  if mt="$(stat -f %m "$CACHE" 2>/dev/null)" || mt="$(stat -c %Y "$CACHE" 2>/dev/null)"; then
    age=$((now - mt))
    if [ "$age" -le "$STALE_S" ]; then
      g="$(jq -r --arg dim "$DIM" --arg rst "$RST" --arg tier "$TIER" '
        if type != "array" then empty else
          (length) as $n
          | ([.[] | select(.status.dirty == true)] | length) as $dirty
          | ([.[] | select((.status.ahead // 0) > 0 or (.status.behind // 0) > 0)] | length) as $sync
          | ([.[] | select(.drift.status == "drift")] | length) as $drift
          | (if $tier == "full" or $tier == "wide" then
               (if $dirty > 0 then $dim + " ·" + ($dirty|tostring) + " dirty" + $rst else "" end)
               + (if $sync > 0 then $dim + " ·" + ($sync|tostring) + " unsynced" + $rst else "" end)
             else "" end) as $sub
          | "⚓\($n)\($sub)\t\($drift)"
        end' "$CACHE" 2>/dev/null)" || g=''
      # jq's EXIT CODE IS PART OF THE ANSWER. This was `|| true`, which threw the
      # status away — and jq STREAMS: on `[{…}] garbage` it prints the first
      # document's line and only then fails, so the tile rendered a real fleet
      # count from a file it could not finish reading. Measured 2026-08-14: ⚓1
      # from a cache with trailing junk.
      #
      # ONE DOCUMENT, OR NOTHING. `jq -r PROGRAM file` runs the program ONCE PER
      # JSON DOCUMENT, and a cache holding two concatenated top-level arrays is
      # not a parse error — it is two answers. Measured 2026-08-14: `[{…}]`
      # followed by `[{…},{…},{…}]` rendered THREE statusline rows with TWO
      # different fleet counts (⚓1 then ⚓3), against this file's own two-row
      # contract. The `[ -n "$g" ]` guard accepted it because a multi-document
      # answer is non-empty. The same shape defeated the WRITER's gate, which
      # checked `jq -e 'type == "array"'` — also per document. Both are fixed.
      #
      # A LINE COUNT IS THE TELL, not a re-parse: this program emits exactly one
      # line per document by construction, so more than one line means more than
      # one document. NOT `case "$g" in *"$(printf '\n')"*)`: command substitution
      # STRIPS trailing newlines, so that subshell yields the EMPTY STRING, the
      # pattern collapses to `**`, and every cache — including a valid one —
      # matched and blanked the tile. Caught by keeping a valid single array in
      # the probe set as a control (CONSTITUTION §2.11).
      if [ "$(printf '%s\n' "$g" | wc -l | tr -d ' ')" -gt 1 ]; then g=''; fi
      if [ -n "$g" ]; then
        BERTHS="${g%%	*}"; DRIFTN="${g##*	}"
        case "$DRIFTN" in ''|*[!0-9]*) DRIFTN=0 ;; esac
        if [ "$age" -lt 60 ]; then a="${age}s"; else a="$((age / 60))m"; fi
        # The cache age is a sub-fact of the fleet count, so it rides it (`·4m ago`)
        # instead of standing alone as a bare duration nobody could name.
        if [ "$TIER" = narrow ]; then ambient "$BERTHS"; else ambient "$BERTHS ·$a ago"; fi
      fi
    fi
  fi
fi
[ -n "$BERTHS" ] || ambient "fleet: unknown"
[ "$DRIFTN" -gt 0 ] && alarm "DRIFT $DRIFTN"

# ── the pin · LIVE, not cached · WORD ONLY ───────────────────────────────────
# The one ground fact that can change mid-session, because it changes the moment
# settings.json is edited.
#
# THE ICON IS GONE (operator decision 2026-08-24) and this is the third and last
# step of one argument, so the whole arc is here rather than three comments apart.
# The token was `floor✓`, which sat two columns from `renew … floor4` and made one
# surface look like it contradicted the other — a reader saw `floor✓` and concluded
# the floor was fine while four merged floor commits gated nothing. It became 📌 to
# stop that. Then the 08-24 recolour made every state token grey, so the pushpin was
# grey whether the pin held or not: an icon in two identical states, which is a
# column spent to say the check ran. The operator asked for it removed and they are
# right — that is the same reasoning that cut `blocks N` and keeps `worst=ok` silent.
#
# SO THE BINARY NOW HAS EXACTLY ONE CHANNEL, and the comment this replaces called
# the redundancy deliberate. It was, and losing it has a cost worth stating: with
# the alarm zone moved to the right end of row 2, a system notification can truncate
# the row and PIN DRIFT is then not merely quiet but ABSENT — the two decisions
# compound, and neither one alone would have done it. `harbor verify` and
# session-verdicts.sh both still report the pin, so the fact has surfaces; what it
# no longer has is a surface you cannot miss.
#
# NOTHING RENDERS WHEN THE PIN HOLDS. That is this file's rule everywhere else and
# the pin is no longer the exception: a token whose steady state is "fine" is
# wallpaper by the third session, and wallpaper is how a real alarm gets missed.
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{print $1}'; }
if [ -f "$CFG/settings.json" ] && command -v jq >/dev/null 2>&1; then
  if [ -f "$CFG/.helm-floor-teeth" ]; then
    pinned="$(cat "$CFG/.helm-floor-teeth" 2>/dev/null || true)"
    live="$(jq -S '{deny:.permissions.deny, locks:{bypass:.permissions.disableBypassPermissionsMode, auto:.permissions.disableAutoMode}}' \
              "$CFG/settings.json" 2>/dev/null | sha || true)"
    # The hash is still computed on the holding path even though nothing renders:
    # it is what decides that nothing should render, and skipping it would turn a
    # verified all-clear into an assumed one.
    if [ -n "$pinned" ] && [ "$pinned" = "$live" ]; then
      :
    else
      alarm "PIN DRIFT"
    fi
  else
    alarm "PIN UNPINNED"
  fi
fi

# ── 📡 watch · the schedulers, and whether they are actually loaded ───────────
# THE NUMBERS ABOVE ARE ONLY AS TRUE AS THE JOBS THAT WRITE THEM. `renew`, the
# judge verdict, the guard-decision counts and the whole fleet snapshot are files
# on disk refreshed by launchd. If com.harbor.fleet-snapshot stops, every one of
# them freezes at its last value and keeps rendering as current — a green board
# over a dead reporter, which is the exact failure this box has already measured
# in its data pipelines.
#
# CACHED, NOT PROBED. `launchctl list` per tick is a fork this row may not spend,
# so fleet-snapshot-refresh.sh writes `.helm-watch` and this reads it. RENDERS
# NOTHING WHEN THE FILE IS ABSENT: that means the check has never run, which is a
# verdict for renew-check, not a number to invent here.
if [ -f "$CFG/.helm-watch" ] && [ "$TIER" = full ]; then
  _w="$(head -1 "$CFG/.helm-watch" 2>/dev/null || true)"
  case "$_w" in
    watch\ *)
      _wl="${_w#watch }"; _wi="${_wl#* }"; _wl="${_wl%% *}"
      case "$_wl$_wi" in
        *[!0-9]*) ;;
        # Healthy renders nothing (2026-10-16): all schedulers loaded is the steady state.
        *) [ "$_wl" = "$_wi" ] || alarm "WATCH $_wl/$_wi" ;;
      esac ;;
  esac
fi

# ── 🧹 sweep · what is left over and needs a person ─────────────────────────
# Written twice a day by harbor-clean.sh --record, which rides fleet-snapshot's
# run (09:00 and 16:00, operator decision 2026-09-22): `items` is the DECIDE and
# RISK rows — a branch whose PR merged, a finished worktree, work that exists in
# one place only. CACHED, NOT PROBED: the count needs a GitHub read per repo.
#
# ZERO RENDERS NOTHING, like every other token here. The `?` is the honest
# middle: some repo could not be read (`unread`), or the record is older than
# the longest gap between two slots plus margin (26h) — either way the number is
# a lower bound, and a bare 🧹3 would claim to be the whole of it.
#
# SWEEP IS THE ALARM, WITH AN AGE. `due=1` is the writer's call (any RISK row,
# or enough rows), not re-derived here — one policy, one place. The zone owns
# the colour, so it is grey like every other alarm (operator decision
# 2026-08-24); being in the alarm zone at all is the escalation.
SWEEPTOK=""
if [ -f "$CFG/.helm-sweep" ]; then
  _sw="$(head -1 "$CFG/.helm-sweep" 2>/dev/null || true)"
  _si=""; _su=""; _sd=""; _sa=""
  case "$_sw" in
    sweep\ *)
      for _kv in $_sw; do
        case "$_kv" in
          items=*)  _si="${_kv#items=}" ;;
          unread=*) _su="${_kv#unread=}" ;;
          due=*)    _sd="${_kv#due=}" ;;
          at=*)     _sa="${_kv#at=}" ;;
        esac
      done ;;
  esac
  case "$_si:$_su:$_sd:$_sa" in
    *[!0-9:]*|:*|*::*|*:) ;;   # malformed or missing field: render nothing
    *)
      _ss=$(( NOW_EPOCH - _sa )); _sq=""
      if [ "$_su" -gt 0 ] || [ "$_ss" -gt 93600 ]; then _sq="?"; fi
      # The 🧹 count left the line 2026-10-16: SWEEP below carries the same number when it is due.
      if [ "$_sd" = 1 ] && [ "$_si" -gt 0 ]; then
        if   [ "$_ss" -lt 3600 ];  then _sg="$((_ss / 60))m"
        elif [ "$_ss" -lt 86400 ]; then _sg="$((_ss / 3600))h"
        else                            _sg="$((_ss / 86400))d"; fi
        SWEEPTOK="SWEEP $_si ·$_sg"
      fi ;;
  esac
fi

# ── ⧗ obligations · work that was opened and has not been closed (harbor#1050, CHECKS.md row status.obligations) ──
# status-obligations.sh writes the cache inside fleet-snapshot's run and stores epochs, so the age of the oldest overdue
# row is counted here at print time. `⧗N` is the rows still open (grey); OVERDUE is the alarm, with its age.
# ABSENT RENDERS NOTHING, like every token here. `⧗?` is the honest middle: the cache is over 900s old (the writer did
# not run, so no count and no alarm is claimed from it) or a source did not answer on the last reconcile (the count is a
# lower bound, so it is not printed as a number). An overdue row is in the ledger whatever a source said, so OVERDUE still shows.
#
# THE YOU QUEUE (2026-10-16) is the cache's `you` list: the operator-owned
# handoffs (`intent`, opened by `event-bus.sh emit obligation.open <slug> --data
# '{"title":"…"}'` with no session id) and approvals. Titles are written by sessions,
# so control characters are stripped and the text capped here as well as at the fold:
# an escape sequence in a title must not be able to repaint this row. 40 columns each (was 90): two
# 90-column titles pushed every alarm past the terminal's edge; the full title is in `harbor status obligations`. Overdue items
# are red. A stale cache claims no queue at all, the rule OVERDUE already follows.
OBLTOK=""; YOUQ=""
if [ -f "$CACHE_DIR/status-obligations.json" ] && command -v jq >/dev/null 2>&1; then
  _ob="$(jq -r --argjson now "$NOW_EPOCH" --arg red "$RED" --arg yel "$YEL" --arg dim "$DIM" --arg rst "$RST" \
              --arg sep " $SEP " '
      def clip: (. // "") | tostring | gsub("[[:cntrl:]]"; "") | if length > 40 then .[0:39] + "…" else . end;
      def col($o): if $o == true then $red else $yel end;
      ((.at // 0) | tonumber) as $at | (.live // 0 | tonumber) as $n | (.overdue // 0 | tonumber) as $od | (.overdue_since // 0 | tonumber) as $since
      | if ($now - $at) > 900 then "⧗?", "", ""
        else (if .unread == true then "⧗?" elif $n > 0 then "⧗\($n)" else "" end),
          (if $od > 0 then "OVERDUE \($od)" + (if $since > 0 then (($now - $since) | if . < 3600 then " ·\([0, . / 60 | floor] | max)m" elif . < 86400 then " ·\(. / 3600 | floor)h" else " ·\(. / 86400 | floor)d" end) else "" end) else "" end),
          ((if (.you | type) == "array" then .you else [] end) as $y
           | [$y[] | select(.k != "pr")] as $h
           | (($h[:3] | map((if .k == "approval" then "approve " else "" end) + col(.o) + (.t | clip) + $rst)))
           | join($sep))
        end' "$CACHE_DIR/status-obligations.json" 2>/dev/null || true)"
  _oa=""; _ol=""; _oq=""
  { IFS= read -r _oa || :; IFS= read -r _ol || :; IFS= read -r _oq || :; } <<OBLEOF
$_ob
OBLEOF
  # The ⧗ open count left the line 2026-10-16 (`harbor status obligations` lists it); OVERDUE stays.
  OBLTOK="$_ol"; YOUQ="$_oq"
fi

# ── ⏳ CI · jobs left on this box's runners, and when they should be done ────
# Operator request 2026-09-23 (harbor#657). ci-queue.sh writes the cache inside
# fleet-snapshot's run, every 300s; it stores each repo's expected finish as an
# EPOCH, and the minutes are subtracted here, at print time — so the time left
# keeps counting down between refreshes, and only a run that starts or ends
# shows up to one refresh late. `~` because the estimate ignores `needs:`.
#
# IDLE RENDERS NOTHING, like every token on this row. `due` is a job running past
# its usual length, never a negative number. `?` is the honest middle, as on 🧹:
# a repo GitHub did not answer for, or a cache older than three refreshes (900s)
# — then the count is shown with no time at all, because a time computed from a
# stale finish would be a confident guess about a queue nobody has looked at.
if [ -f "$CACHE_DIR/ci-queue.json" ] && command -v jq >/dev/null 2>&1; then
  _ci="$(jq -r --argjson now "$NOW_EPOCH" '
      ((.at // 0) | tonumber) as $at
      | ([.repos[]? | select(.unread != true) | .left // 0] | add // 0) as $n
      | ([.repos[]? | select(.unread == true)] | length) as $u
      | ([.repos[]? | select(.unread != true) | .eta // empty] | max) as $eta
      | if $n == 0 and $u == 0 then empty
        elif ($now - $at) > 900 or $eta == null then "⏳\($n)?"
        else ((($eta - $now) / 60) | ceil) as $m
          | "⏳\($n) ·"
            + (if $m <= 0 then "due" elif $m < 60 then "~\($m)m"
               else "~\($m / 60 | floor)h\($m % 60)m" end)
            + (if $u > 0 then "?" else "" end)
        end' "$CACHE_DIR/ci-queue.json" 2>/dev/null || true)"
  [ -n "$_ci" ] && ci_ambient "$_ci"
  # A WEDGED RUNNER IS AN ALARM, NOT INVENTORY (harbor#152). ci-queue.sh calls a
  # stall only when a self-hosted job has queued past ten minutes while a runner
  # of that repo sat idle on two refreshes in a row — the state that froze every
  # merge for 25 minutes on 2026-08-06 while every surface read "queued, online".
  # A stale cache says nothing: a stall read from a cache nobody refreshed is a
  # confident claim about a queue nobody looked at. The remedy is in
  # `sh bin/ci-queue.sh --print`, not here — this row has no room for it.
  _cis="$(jq -r --argjson now "$NOW_EPOCH" '
      if ($now - ((.at // 0) | tonumber)) > 900 then empty
      elif ([.repos[]? | select(.stall == true)] | length) > 0 then "CI STALL"
      else empty end' "$CACHE_DIR/ci-queue.json" 2>/dev/null || true)"
  [ -n "$_cis" ] && ci_alarm "$_cis"
fi

# ── MAIN RED · a fleet repo's main has no green CI verdict (harbor#586) ─────────────
# main-tip-verdict.sh writes {at, unread, repos:[{repo, tip, ...}]} inside fleet-snapshot's run; the older
# single-repo cache has no .repos and reads as one nameless repo. An ALARM, because a merged commit nobody
# has a green run for is how 41 of 99 pushes went unnoticed; the age is computed here from the commit's own
# time, so it keeps counting between refreshes. A cache over 900s old, or one whose last read failed, is not
# claimed either way: `main?` says "could not look". Compact: `MAIN RED estate 3h`, two are listed, more count.
if [ -f "$CACHE_DIR/main-tip-verdict.json" ] && command -v jq >/dev/null 2>&1; then
  _mt="$(jq -r --argjson now "$NOW_EPOCH" '
      def ago: if . < 3600 then "\(. / 60 | floor)m" elif . < 172800 then "\(. / 3600 | floor)h" else "\(. / 86400 | floor)d" end;
      . as $c | (($now - (($c.at // 0) | tonumber)) > 900) as $stale
      | ([($c | if (.repos | type) == "array" then .repos else [.] end)[]
         | select(.tip.red == true and (.unread != true)) | {n: ((.repo // "") | sub("^[^/]*/"; "")), a: ($now - .tip.at)}] | sort_by(-.a)) as $red
      | if $stale then "?"
        elif ($red | length) == 0 then (if $c.unread == true then "?" else empty end)
        elif ($red | length) > 2 then "!\($red | length) repos, oldest \($red[0].a | ago)"
        else "!" + ($red | map((if .n == "" then "" else .n + " " end) + (.a | ago)) | join(", ")) end' \
      "$CACHE_DIR/main-tip-verdict.json" 2>/dev/null || true)"
  case "$_mt" in
    '?') ci_ambient "main?" ;;
    '!'*) ci_alarm "MAIN RED ${_mt#!}" ;;
  esac
fi

# ── CI→local · the month's Actions minutes ran short and CI fell back to the self-hosted runners (harbor#865) ─────
# runner-switch.sh writes the cache inside fleet-snapshot's run and sets HARBOR_RUNNER; this only shows it. The runners
# are this Mac and a Linux container, hence `local`, not `mac` (2026-10-05). The FALLBACK is the news, so github-hosted (the normal state) renders nothing, like every idle token on this row.
# A cache over 900s old, or one whose last read failed, says `CI?`: the runner may be one this token does not know.
if [ -f "$CACHE_DIR/runner-switch.json" ] && command -v jq >/dev/null 2>&1; then
  _rs="$(jq -r --argjson now "$NOW_EPOCH" '
      ((($now - ((.at // 0) | tonumber)) > 900) or .unread == true) as $old
      | if $old then "CI?"
        elif .fallback == true then "CI→local \(.percent // 0)%"
        else empty end' "$CACHE_DIR/runner-switch.json" 2>/dev/null || true)"
  [ -n "$_rs" ] && ci_ambient "$_rs"
fi

# ── CI⇣ · the CI core budget is held under its target (bin/ci-governor.sh, on events) ─────────────
# Held means throttled: the box is loaded, or the budget is still climbing back. At its target it renders
# nothing. The governor writes only when something happens, so an old cache is normal; `gov?` means its
# listener is not running (the pid it recorded is gone), and nothing is deciding.
# `CI EMERG` is an alarm: a spike has CI at its floor, local runs stopped and a Mac job backgrounded.
if [ -f "$CACHE_DIR/ci-governor.json" ] && command -v jq >/dev/null 2>&1; then
  _gp="$(jq -r '.listener_pid // empty' "$CACHE_DIR/ci-governor.json" 2>/dev/null || true)"
  if [ -n "$_gp" ] && kill -0 "$_gp" 2>/dev/null; then
    _gv="$(jq -r '
        if .emergency == true then "!CI EMERG"
        elif (.budget // 0) < (.target // 0) then "CI⇣\(.budget)/\(.target)"
        else empty end' "$CACHE_DIR/ci-governor.json" 2>/dev/null || true)"
  else _gv="gov?"; fi
  case "$_gv" in '!'*) ci_alarm "${_gv#!}" ;; ?*) ci_ambient "$_gv" ;; esac
fi

# ── PLAN / GATE · the account plan or main's protection differs from what a person acknowledged (bin/gh-plan.sh) ──
# harbor#1060: Pro -> Free on 2026-10-05 turned protection off and surfaced only when a merge was refused. The alarm
# holds until `gh-plan.sh ack`; a cache over 900s old or a failed read is `plan?`, never a calm state.
# ── DOCKER DOWN · RUNNER DOWN n · RUNNER WEDGED n · CI NO RUNNER n ·Mm (bin/ci-runners.sh tick, check ci-runner-alarm) ──
# A dead docker or a registered runner offline on two ticks, and self-hosted jobs no online runner can take, the minutes
# counted here from the oldest one's queue time. `runners?`: the cache is over 900s old or GitHub did not answer.
# RUNNER WEDGED: a runner container busy on a dead job (an oom_kill then flat CPU, or 2h+ flat), read docker-side.
for _ac in gh-plan ci-runner-alarm; do
  [ -f "$CACHE_DIR/$_ac.json" ] && command -v jq >/dev/null 2>&1 || continue
  _ao="$(jq -r --arg c "$_ac" --argjson now "$NOW_EPOCH" '
      ((($now - ((.at // 0) | tonumber)) > 900)) as $old
      | if $c == "gh-plan" then
          (if $old or .unread == true then "?plan?"
           elif .alarm == true then
             (if .plan != .ack.plan then "PLAN \(.ack.plan)→\(.plan)" else empty end),
             (if .gate != .ack.gate then "GATE \(.gate)" else empty end)
           else empty end)
        elif $old then "?runners?"
        else
          (if .docker_down == true then "DOCKER DOWN" else empty end),
          (if .unread == true then "?runners?" else empty end),
          (if (.offline // [] | length) > 0 then "RUNNER DOWN \(.offline | length)" else empty end),
          (if (.wedged // [] | length) > 0 then "RUNNER WEDGED \(.wedged | length)" else empty end),
          (if (.stuck.jobs // 0) > 0 then "CI NO RUNNER \(.stuck.jobs) ·\((($now - .stuck.oldest) / 60) | floor)m" else empty end)
        end' "$CACHE_DIR/$_ac.json" 2>/dev/null || true)"
  while IFS= read -r _at; do
    case "$_at" in '?'*) ci_ambient "${_at#?}" ;; ?*) ci_alarm "$_at" ;; esac
  done <<ALARMS
$_ao
ALARMS
done


# ── the alarm zone ────────────────────────────────────────────────────────────

# WHAT IS BUILT HERE AND NOT RUNNING THERE (harbor#44). Cache written by
# fleet-snapshot-refresh.sh — the answer needs a `git rev-list` and a walk of
# LaunchAgents, and a tick must not scale with either.
#
# RED, AND LOUDER THAN ANY COUNT. A renewal not done is a merged, tested,
# contract-documented guard that gates nothing on this machine — measured
# 2026-08-13 as 11 bin/hooks commits behind, which is why guard-cloud.sh and
# guard-destroy.sh were not live.
#
# THE COUNT IS DROPPED AND THE TOKENS ARE KEPT VERBATIM. renew-check.sh owns this
# vocabulary; `renew 2 runtime3·floor4` states the same quantity twice, and
# re-spelling `runtime3` as `runtime+3` here would be a second implementation of
# another tool's naming that can disagree with it. The label says the condition,
# the tokens stay renew-check's.
if [ -f "$CFG/.helm-renew" ]; then
  r="$(head -1 "$CFG/.helm-renew" 2>/dev/null || true)"
  case "$r" in
    "renew 0"|"renew 0 "*|"") ;;
    renew\ *) _rt="${r#renew }"; _rt="${_rt#* }"
              [ -n "$_rt" ] && alarm "STALE ${_rt}" ;;
  esac
fi

# THE DAILY JUDGE'S VERDICT — new on the row 2026-08-23, and the reason for the
# whole redesign. This box carried `crit=1 warn=62` in .helm-judge while the row
# rendered a green pin, because nothing read the verdict; `renew` only notices the
# judge when the FILE is absent or two days stale, never what it says.
#
# THE AGE IS NOT OPTIONAL. The crit that prompted this rested on ONE
# wrapper-guard-missing record from 2026-08-20, and the remedy it prints
# (re-run floor-install.sh) had already run on 2026-08-23 — so the verdict was
# almost certainly true-but-spent, and nothing on the row could say so. An
# undated verdict cannot be falsified, and CONSTITUTION §2.4 says a claim with no
# falsifier is not a claim. Age comes from the file mtime, the same idiom the
# fleet cache uses, and not from parsing the ISO stamp inside: `date -j -f` is
# BSD-only and this file must survive a userland change.
#
# `worst=ok` RENDERS NOTHING. A judge reporting clean every tick is wallpaper by
# the third session, and wallpaper is how a real alarm gets missed.
if [ -f "$CFG/.helm-judge" ]; then
  _j="$(head -1 "$CFG/.helm-judge" 2>/dev/null || true)"
  _jw=""
  case "$_j" in *worst=*) _jw="${_j#*worst=}"; _jw="${_jw%% *}" ;; esac
  if [ "$_jw" = crit ] || [ "$_jw" = warn ]; then
    _ja=""
    if _jm="$(stat -f %m "$CFG/.helm-judge" 2>/dev/null)" || _jm="$(stat -c %Y "$CFG/.helm-judge" 2>/dev/null)"; then
      _js=$(( NOW_EPOCH - _jm ))
      # harbor#300: a file newer than the clock (skew, restored copy) has no honest age: show none, not "0m".
      if   [ "$_js" -lt 0 ];     then _ja=""
      elif [ "$_js" -lt 3600 ];  then _ja=" ·$((_js / 60))m"
      elif [ "$_js" -lt 86400 ]; then _ja=" ·$((_js / 3600))h"
      else                            _ja=" ·$((_js / 86400))d"; fi
    fi
    _jn=""
    case "$_j" in *"${_jw}="*) _jn="${_j#*${_jw}=}"; _jn=" ${_jn%% *}" ;; esac
    # NO crit/warn WORD (operator, 2026-10-16): the colour is the level, red crit, yellow warn.
    if [ "$_jw" = crit ]; then alarm "JUDGE${_jn}${_ja}" red
    else                       alarm "JUDGE${_jn}${_ja}" yel; fi
  fi
fi

# The sweep's alarm, computed with its tile above (the 🧹 section).
[ -n "$SWEEPTOK" ] && alarm "$SWEEPTOK"
# The obligations alarm, computed with its tile above (the ⧗ section).
[ -n "$OBLTOK" ] && alarm "$OBLTOK"

# OVERRIDES ONLY — `blocks N` was removed 2026-08-23. It was a monotonic lifetime
# counter (4,719 blocks against 102,012 ledger records) that no action could move,
# so it was read past by the third session; the operator asked for it gone and the
# reasoning agrees. An OVERRIDE is different in kind: it is the operator saying a
# rule is wrong with their hands, which CONSTITUTION §2.11 calls a defect in the
# rule. It renders nothing until one happens, which is most of the time.
if [ -f "$OBS" ] && command -v jq >/dev/null 2>&1; then
  o="$(jq -r 'if (.overrides // 0) > 0 then "ovr \(.overrides)" else empty end' "$OBS" 2>/dev/null || true)"
  [ -n "$o" ] && alarm "${o}"
fi

# Proposal packets waiting for a human (harbor#44). Same silence rule: nothing at
# zero, nothing when the file is absent. YELLOW, not red — a queued packet is the
# system working as designed, where a renewal not done is a gap between what was
# built and what is running.
if [ -f "$CFG/.helm-props" ]; then
  q="$(head -1 "$CFG/.helm-props" 2>/dev/null || true)"
  case "$q" in
    "props 0"|"") ;;
    props\ *) alarm "${q}" ;;
  esac
fi

# ── row 3 · the machine, then CI (operator request 2026-10-05, harbor#1032) ───
# The load the CI governor acts on, at each refresh: CPU, GPU, RAM, swap. Every source
# is optional — a missing or failing one drops ITS segment; the CI tokens follow (see print).
# Cost budget: three fork+awk pairs (sysctl, ioreg, vm_stat), measured in the PR.
ROW3=""
lvl() { # <n> <warn> <crit> — sets _lv to 0, 1 (yellow) or 2 (red), the row-1 ramp
  if [ "$1" -ge "$3" ]; then _lv=2; elif [ "$1" -ge "$2" ]; then _lv=1
  else _lv=0; fi
}
seg3() { # <level> <text>
  case "$1" in 2) _k="$RED" ;; 1) _k="$YEL" ;; *) _k="" ;; esac
  ROW3="$ROW3${ROW3:+ $SEP }${_k}$2${_k:+$RST}"
}
if [ "${HARBOR_GLYPH_MACHINE:-1}" != 0 ]; then
  # CPU BUSY IS READ FROM A CACHE, NEVER SAMPLED INLINE. A real busy figure needs two
  # counter reads a second apart (iostat -c 2 -w 1); `ps %cpu` is a decayed average and
  # `top -l 1` costs 250 ms. A detached sampler refreshes `epoch busy` and a render
  # shows the last value, so the 1 s wait never lands on a tick.
  CPUC="$CACHE_DIR/machine-cpu"; _ce=0; _cp=""
  if [ -r "$CPUC" ]; then read -r _ce _cp < "$CPUC" 2>/dev/null || true; fi
  case "$_ce" in ''|*[!0-9]*) _ce=0; _cp="" ;; esac
  case "$_cp" in ''|*[!0-9]*) _cp="" ;; esac
  _age=$(( NOW_EPOCH - _ce ))
  if [ "$_age" -lt 0 ] || [ "$_age" -gt 120 ]; then _cp=""; fi
  if [ "${HARBOR_GLYPH_MACHINE_REFRESH:-1}" != 0 ] && { [ -z "$_cp" ] || [ "$_age" -ge 8 ]; } \
     && command -v iostat >/dev/null 2>&1; then
    # `.try` rate-limits the spawn: a burst of ticks inside one second must not fan out.
    _tr=0
    if [ -r "$CPUC.try" ]; then read -r _tr < "$CPUC.try" 2>/dev/null || _tr=0; fi
    case "$_tr" in ''|*[!0-9]*) _tr=0 ;; esac
    if [ $(( NOW_EPOCH - _tr )) -ge 5 ]; then
      printf '%s\n' "$NOW_EPOCH" > "$CPUC.try" 2>/dev/null || true
      ( iostat -n0 -c 2 -w 1 2>/dev/null \
          | awk -v t="$NOW_EPOCH" 'NF >= 3 && $1 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ { id = $3; n = 1 }
                                   END { if (n) print t, 100 - id }' > "$CPUC.tmp" 2>/dev/null
        [ -s "$CPUC.tmp" ] && mv -f "$CPUC.tmp" "$CPUC" ) </dev/null >/dev/null 2>&1 &
    fi
  fi

  # `key: value` output, so a key this OS lacks costs only its own token and never
  # shifts the others. Pressure is the kernel's own 1/2/4 level, not a threshold of mine.
  _ld=""; _sw=""; _swt=""; _swmb=0; _pl=""; _mem=""
  # Each value must look like a number first: awks differ on "nan" (mawk prints 0.0), harbor#1032.
  _sy="$(sysctl kern.memorystatus_vm_pressure_level vm.swapusage vm.loadavg hw.memsize 2>/dev/null \
    | awk '/^kern.memorystatus_vm_pressure_level:/ { if ($2 ~ /^[0-9]+$/) printf "pl=%d ", $2 }
           /^vm.loadavg:/ { if ($3 ~ /^[0-9]+(\.[0-9]+)?$/) printf "ld=%.1f ", $3 }
           /^hw.memsize:/ { printf "mem=%s ", $2 }
           /^vm.swapusage:/ { for (i = 1; i < NF; i++) if ($i == "used") {
               v = $(i + 2); if (v !~ /^[0-9]+(\.[0-9]+)?[KMG]$/) next; u = substr(v, length(v)); n = v + 0
               if (u == "G") n *= 1024; else if (u == "K") n /= 1024
               printf "swmb=%d sw=%.1f ", n, n / 1024 }
             for (i = 1; i < NF; i++) if ($i == "total") {
               v = $(i + 2); if (v !~ /^[0-9]+(\.[0-9]+)?[KMG]$/) next; u = substr(v, length(v)); t = v + 0
               if (u == "G") t *= 1024; else if (u == "K") t /= 1024
               printf "swt=%.0f ", t / 1024 } }')" || true
  for _t in $_sy; do
    case "$_t" in
      pl=[0-9]*) _pl="${_t#pl=}" ;;
      ld=[0-9]*) _ld="${_t#ld=}" ;;
      mem=[0-9]*) _mem="${_t#mem=}" ;;
      swmb=[0-9]*) _swmb="${_t#swmb=}" ;;
      sw=[0-9]*) _sw="${_t#sw=}" ;;
      swt=[0-9]*) _swt="${_t#swt=}" ;;
    esac
  done
  _gpu="$(ioreg -r -d 1 -c IOAccelerator 2>/dev/null \
    | awk '{ if (match($0, /"Device Utilization %"=[0-9]+/)) { s = substr($0, RSTART, RLENGTH); sub(/.*=/, "", s)
                if (s + 0 > m) m = s + 0; f = 1 } } END { if (f) print m + 0 }')" || true
  _ram=""
  if [ -n "$_mem" ]; then
    # Used = app (anonymous - purgeable) + wired + compressed, the Activity Monitor sum.
    _ram="$(vm_stat 2>/dev/null | awk -v mem="$_mem" '
      /page size of/ { for (i = 1; i <= NF; i++) if ($i == "of") ps = $(i + 1) }
      /^Anonymous pages:/ { a = $3 }  /^Pages purgeable:/ { p = $3 }
      /^Pages wired down:/ { w = $4 }  /^Pages occupied by compressor:/ { c = $5 }
      END { if (ps > 0 && a != "" && w != "" && c != "" && mem > 0)
              printf "%.1f/%.0fG", ((a - p) + w + c) * ps / 1073741824, mem / 1073741824 }')" || true
  fi

  # ONLY YELLOW AND RED (operator, 2026-10-16): a tile is plain until it needs attention. The
  # memory-pressure WORD is gone and its level colours the RAM tile; RAM, SSD and swap read used/total.
  _t=""; _lv=0
  if [ -n "$_cp" ]; then _t="CPU ${_cp}%"; lvl "$_cp" 70 90; fi
  if [ -n "$_ld" ]; then
    if [ -n "$_t" ]; then _t="$_t ·load $_ld"; else _t="load $_ld"; fi
  fi
  if [ -n "$_cp" ] && [ "$_cp" -ge 70 ]; then
    _tp="$(ps -A -o %cpu=,comm= 2>/dev/null \
      | awk '{ if ($1 + 0 > m) { m = $1 + 0; n = $0 } }
             END { sub(/^ *[0-9.]+ +/, "", n); sub(/.*\//, "", n); print substr(n, 1, 18) }')" || true
    [ -z "$_tp" ] || _t="$_t ·$_tp"
  fi
  [ -z "$_t" ] || seg3 "$_lv" "$_t"
  case "$_gpu" in ''|*[!0-9]*) ;; *) lvl "$_gpu" 70 90; seg3 "$_lv" "GPU ${_gpu}%" ;; esac
  _lv=0
  case "$_pl" in 2) _lv=1 ;; 4) _lv=2 ;; esac
  [ -z "$_ram" ] || seg3 "$_lv" "RAM $_ram"
  # DISK, used/total like RAM (operator, 2026-10-16), on the volume that holds $HOME: on macOS the
  # Data volume, since `/` is the sealed system snapshot. Used is total minus available, because APFS
  # volumes share a container and the Used column undercounts. One `df` fork; yellow under 15% free,
  # red under 7%. HARBOR_GLYPH_DF stands in for df in the suite.
  _df="$("${HARBOR_GLYPH_DF:-df}" -k "${HOME:-/}" 2>/dev/null | awk 'NR == 2 && $2 ~ /^[0-9]+$/ && $4 ~ /^[0-9]+$/ && $2 > 0 {
          printf "%d %d %d", ($2 - $4) / 1048576, $2 / 1048576, ($4 * 100) / $2 }')" || true
  case "$_df" in
    *[!0-9\ ]*|'') ;;
    *) _du="${_df%% *}"; _dp="${_df##* }"; _dt="${_df#* }"; _dt="${_dt% *}"
       if [ "$_dp" -lt 7 ]; then _lv=2; elif [ "$_dp" -lt 15 ]; then _lv=1; else _lv=0; fi
       seg3 "$_lv" "SSD ${_du}/${_dt}G" ;;
  esac
  # SWAP, used/total, always shown once sysctl answers (operator, 2026-10-16): macOS grows the
  # swap files on demand, so a total of 0 is real and reads `0/0G`.
  if [ -n "$_sw" ]; then lvl "$_swmb" 2048 6144; seg3 "$_lv" "swap ${_sw}/${_swt:-0}G"; fi
fi

# ── row 3 · is the internet safe, is Remote Control on (operator request 2026-10-12) ──
# Emoji by operator request, an exception to decision 3: 🏠 trusted gateway, 🔒 VPN route,
# 🔓 neither or firewall off; 📱/📵 Remote Control. An unreadable source renders nothing.
NET3=""
if [ "${HARBOR_GLYPH_MACHINE:-1}" != 0 ]; then
  _fw="$("${HARBOR_GLYPH_FW:-/usr/libexec/ApplicationFirewall/socketfilterfw}" --getglobalstate 2>/dev/null \
    | awk '/State = 0/ { print "off"; exit } /State = [0-9]/ { print "on"; exit }')" || true
  _rt="$(route -n get 1.1.1.1 2>/dev/null \
    | awk '$1 == "interface:" { i = $2 } $1 == "gateway:" { g = $2 } END { if (i != "") print i, g }')" || true
  _if="${_rt%% *}"; _gw="${_rt#* }"; [ "$_gw" != "$_rt" ] || _gw=""
  if [ -n "$_if" ] && [ -n "$_fw" ]; then
    if [ "$_fw" = off ]; then NET3="🔓"
    else
      case "$_if" in
        utun*|ipsec*|ppp*|tun*|wg*) NET3="🔒" ;;
        *) NET3="🔓"
           # `$CFG/trusted-networks`: one gateway MAC per line, as `arp -n` prints it.
           if [ -n "$_gw" ] && [ -r "$CFG/trusted-networks" ]; then
             _tn="$(arp -n "$_gw" 2>/dev/null | awk '
               function norm(m,  p, n, i, o) { n = split(tolower(m), p, ":"); if (n != 6) return ""
                 for (i = 1; i <= n; i++) o = o (i > 1 ? ":" : "") (length(p[i]) == 1 ? "0" : "") p[i]; return o }
               FNR == NR { for (i = 1; i < NF; i++) if ($i == "at") mac = norm($(i + 1)); next }
               { sub(/#.*/, "") } mac != "" && norm($1) == mac { print "yes"; exit }' - "$CFG/trusted-networks")" || true
             [ "$_tn" != yes ] || NET3="🏠"
           fi ;;
      esac
    fi
  fi
  # Remote Control: this session's `sessions/<pid>.json` carries `bridgeSessionId` while
  # linked. Undocumented, observed on 2.1.296; the stdin JSON has no such field.
  if [ -n "$IN" ]; then
    _rc="$(printf '%s\n' "$IN" | awk '
      FNR == NR { if (match($0, /"session_id" *: *"[^"]+"/)) { s = substr($0, RSTART, RLENGTH)
                    sub(/^"session_id" *: *"/, "", s); sub(/"$/, "", s) } next }
      index($0, "\"sessionId\":\"" s "\"") { print ($0 ~ /"bridgeSessionId":"[^"]+"/) ? "on" : "off"; exit }' \
      - "$CFG"/sessions/*.json 2>/dev/null)" || true
    case "$_rc" in on) NET3="$NET3${NET3:+ }📱" ;; off) NET3="$NET3${NET3:+ }📵" ;; esac
  fi
fi

# ── print ────────────────────────────────────────────────────────────────────
# Row 1 is omitted ENTIRELY when there is no stdin or no jq — never a blank line,
# never a dash. One row that is true beats two rows where one is furniture.
[ -n "$ROW1" ] && printf '%s\n' "$ROW1"
# ── ZONE ORDER: GROUND, AMBIENT, ALARM (operator decision 2026-08-24) ─────────
# THIS REVERSES DECISION 1 IN THE HEADER, AND THE COST IS REAL AND ACCEPTED. That
# decision put alarms leftmost because the statusline docs say Claude Code renders
# its own system notifications on the RIGHT of this row and that they "may truncate
# your status line output" — so the rightmost token is the one you can afford to
# lose. Alarms are now the rightmost token, which means a long MCP error can eat
# them, and the failure mode is that you would not know an alarm was there to lose.
#
# The operator was shown that cost, in those words, and chose the right end anyway.
# It is their status row and the trade is theirs to make: what they get back is a
# row that leads with what they are working on instead of with harbor's complaints,
# every session, including the overwhelming majority where nothing is wrong.
#
# RECORDED RATHER THAN ARGUED AGAIN. The next reader will find decision 1 above
# still explaining why alarms belong on the left; both are operator decisions and
# this one is later. Do not "restore" the old order from that paragraph alone.
#
# SUPERSEDED 2026-10-16 BY THE YOU ROW, and the cost above is gone rather than
# re-accepted: alarms now lead a row of their own, so no notification can clip them
# and they no longer crowd what PLACE is for. Both paragraphs stay as the record.
#
# PLACE: title, repo, branch, PR, then the live-session count.
ROW2="$GROUND${PEERS:+ $SEP $GREY$PEERS$RST}"
printf '%s\n' "$ROW2"
# YOU: the queue first (things only the operator can do), then every alarm. Absent
# when empty, so the row appearing at all is the signal. Kept in every tier.
YOU="$YOUQ"
YOU="$YOU${ALARM:+${YOU:+ $SEP }$ALARM}"
YOU="$YOU${CIALM:+${YOU:+ $SEP }$CIALM}"
[ -z "$YOU" ] || printf "%s\n" "$YOU"
# BOX: network and Remote Control leftmost (never clipped), the machine, then CI and
# fleet inventory, which the narrow tier drops.
ROW4="$ROW3"
[ "$TIER" = narrow ] || ROW4="$ROW4${CIAMB:+${ROW4:+ $SEP }$CIAMB}"
[ "$TIER" = narrow ] || ROW4="$ROW4${AMBIENT:+${ROW4:+ $SEP }$AMBIENT}"
ROW4="$NET3${NET3:+${ROW4:+ $SEP }}$ROW4"
if [ -n "$ROW4" ]; then printf '%s\n' "$ROW4"; fi
