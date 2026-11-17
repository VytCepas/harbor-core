#!/usr/bin/env sh
# L0-5 (harbor#21, extended harbor#59, redesigned harbor#293) — Claude Code statusline.
# Deliberately one file (docs/explanation/modularity.md): `lint-module-shape.sh --seam` finds no
# seam (2026-09-22), and a split would be a `.` per tick on a path that counts forks.
#
# Four rows, one question each: SESSION (stdin JSON only), PLACE (session, repo, branch, PR, live sessions),
# YOU (what waits on the operator; absent when empty, so colour there means act), BOX (network, RC, CPU, GPU, RAM, disk, CI, fleet).
# Emoji only for two-state facts and the nautical nouns (🏠🔒🔓 📱📵 ⛵ ⚓); each is East-Asian-width W, so tiers count it as 2 columns.
# Alarms are WORDS, never icons. Only yellow and red carry colour.
# Deliberately absent, do not fix: a stored countdown (the harness cancels in-flight scripts, so store WHEN and compute time-left at print time),
# burn rate, an absolute token count beside ctx, a `>200k` token (the suite asserts its absence), `blocks N`, a cached floor verdict (the hash runs live).
# All arithmetic and formatting happen in jq: used_percentage is unrounded (41.699999999999996), so POSIX `[ -ge ]` errors into silence,
# and reading TSV with IFS=<tab> collapses empty fields. jq emits the finished string; the shell never parses a number.
# Never invokes the orchestrator: fleet state is read from the cache status-fleet-snapshot-refresh.sh writes (launchd com.harbor.status.fleet-snapshot, 5 min);
# absent, stale or invalid degrades to "fleet: unknown".
# Removed notes: docs/explanation/code-cases/bin-status-fleet-glyph.md
# FLAGS / ENV:
#   --help                 this header
#   HARBOR_STATUS_GLYPH_DUMP=<f>  append the raw stdin payload to <f> and continue, to check which fields THIS version sends. Off unless set.
#   HARBOR_STATUS_GLYPH_COLS=<n>  override the terminal width (the suite pins this).
#   HARBOR_STATUS_GLYPH_STALE_S   fleet-cache staleness ceiling, default 900.
#   HARBOR_TEST_NOW=<epoch>     freeze the clock (the suite pins this).
#   HARBOR_STATUS_GLYPH_MACHINE=0 drop the machine segments of row 3 (the other suites set this);
#                          the CI tokens still show there, so row 3 is gone only when both are empty.
#   HARBOR_STATUS_GLYPH_MACHINE_REFRESH=0  never spawn the CPU sampler; read its cache only.
set -eu

case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CACHE_DIR="${HARBOR_SCOPE_CACHE_DIR:-$CFG/cache}"
CACHE="$CACHE_DIR/fleet-snapshot.json"
OBS="$CACHE_DIR/guard-decisions.json"
STALE_S="${HARBOR_STATUS_GLYPH_STALE_S:-900}"

E="$(printf '\033')"
DIM="$E[2m"; RST="$E[0m"; RED="$E[31m"; YEL="$E[33m"; GRN="$E[32m"
CYN="$E[36m"; BLU="$E[34m"; MAG="$E[35m"; BLD="$E[1m"
# GREY is bright-black (90m), a real colour: unlike DIM (a faint attribute many terminals ignore) it overrides an inherited red or yellow.
GREY="$E[90m"

# Separator grammar, exactly two marks: ` │ ` a DIFFERENT fact; ` ·` MORE ABOUT the fact on its left, no space after (`5h 1% ·in 4h13m`).
# A bare space is the third relationship, same fact next part. Two consecutive spaces mean nothing and the suite asserts none are rendered.
# `runtime4·floor5` is drift-renew-check.sh vocabulary, kept verbatim (see the STALE tile). │ is one column wide; tiers never measure the finished string.
SEP="${DIM}│${RST}"

IN="$(cat 2>/dev/null || true)"

# HARBOR_STATUS_GLYPH_DUMP: the stdin payload is the only copy of the session JSON, so a dump hook is how to check which fields THIS version sends.
if [ -n "${HARBOR_STATUS_GLYPH_DUMP:-}" ] && [ -n "$IN" ]; then
  ( umask 077; printf '%s\n' "$IN" >> "${HARBOR_STATUS_GLYPH_DUMP:-}" ) 2>/dev/null || true
fi

# ── terminal width → render tier ─────────────────────────────────────────────
# Claude Code captures output, so `tput cols` cannot work; COLUMNS is exported instead. An unreadable width (0 or unset) means unknown and takes the full render.
# Tiers are chosen by which tokens they include, never by measuring the finished string (ANSI plus double-width emoji has no correct ${#s}).
_c="${HARBOR_STATUS_GLYPH_COLS:-${COLUMNS:-0}}"
case "$_c" in ''|*[!0-9]*) _c=0 ;; esac
if   [ "$_c" -eq 0 ]   || [ "$_c" -ge 120 ]; then TIER=full
elif [ "$_c" -ge 100 ]; then TIER=wide
elif [ "$_c" -ge 80 ];  then TIER=mid
else                         TIER=narrow
fi

# ── the session-state bridge (harbor#1043, #1044) ────────────────────────────
# The statusline is the one place told how full the context is, so it hands ctx_pct to the Stop hook via $STATE/ctx/<session_id>
# (re-scaled to CLAUDE_CODE_AUTO_COMPACT_WINDOW when set; the row still shows the payload's own percentage).
# It also shows the state record session-state.sh wrote at the last Stop, only while prompt_id matches: a stale `? you` on a working session is a lie.
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
# One jq pass, fully rendered. An absent field contributes zero columns; `// null` plus an explicit empty branch, never `// 0` (0% reads as plenty of room).
ROW1=""
# The clock is injected (HARBOR_TEST_NOW) because jq's `now` would make the reset countdowns unpinnable in a golden-output suite.
NOW_EPOCH="${HARBOR_TEST_NOW:-$(date +%s)}"
if [ -n "$IN" ] && command -v jq >/dev/null 2>&1; then
  ROW1="$(printf '%s' "$IN" | jq -r --arg dim "$DIM" --arg rst "$RST" \
                                    --arg red "$RED" --arg yel "$YEL" \
                                    --arg grn "$GRN" --arg cyn "$CYN" --arg blu "$BLU" --arg mag "$MAG" \
                                    --arg tier "$TIER" --arg sep " $SEP " --arg st "$STTOK" \
                                    --argjson now "$NOW_EPOCH" '
    def ramp(p): if p >= 90 then $red elif p >= 70 then $yel else "" end;
    def ramp3(p): ramp(p);
    def pad2(n): (if n < 10 then "0" else "" end) + (n | tostring);
    # WHEN THE WINDOW REFILLS, as time left. resets_at is present only for subscribers and per window, so absent gives "" (zero columns).
    # A reset in the past is dropped, not shown as 0m, which would read as about to refill. The `in` marks remaining time, not window length.
    # NO APOSTROPHE MAY APPEAR in comments inside this single-quoted jq program: it closes the shell quote and fails as "bad substitution".
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
    # Window size comes from context_window_size, never from display_name (which may or may not carry a parenthetical size); strip any trailing parenthetical.
    def wsize(n): if   n >= 1000000 then ((n / 1000000) | floor | tostring) + "M"
                  elif n >= 1000    then ((n / 1000)    | floor | tostring) + "k"
                  else (n | tostring) end;
    (((.model.display_name // "claude") | sub(" *\\([^)]*\\)$"; "")) as $mn
     | (.context_window.context_window_size // null) as $ws
     | if $ws == null then $mn else $mn + " " + wsize($ws) end) as $model
    # Effort is shown because it moves and costs: xhigh and max are yellow (a price tag, not an alarm). Absent when the model has no effort parameter.
    | (if (.effort.level // null) == null then ""
       else (.effort.level | ascii_downcase) as $e
            | " " + (if $e == "max" or $e == "xhigh" then $yel + ($e | ascii_upcase) + $rst
                     elif $e == "high" then $e
                     else $dim + $e + $rst end) end) as $eff
    | [ $dim + $model + $rst + $eff ]
    # Exceptions only: fast when ON, no-think when thinking is OFF. The ordinary states would be never-changing wallpaper.
    + (if (.fast_mode // false) then [ $yel + "fast" + $rst ] else [] end)
    + (if (.thinking // null) != null and (.thinking.enabled == false)
       then [ $dim + "no-think" + $rst ] else [] end)
    # ctx is a percentage only: no absolute count (the model tile states the window size) and no >200k token (exceeds_200k_tokens stays in the payload, unread, by decision).
    + (if (.context_window.used_percentage // null) == null then []
       else (.context_window.used_percentage | round) as $p
            | [ ramp3($p) + "ctx " + ($p | tostring) + "%" + $rst ] end)
    # THE SESSION STATE (hooks/session-state/session-state.sh, via the bridge above): done, waiting on you, N agents, red.
    + (if $st != "" then [ $st ] else [] end)
    # CACHE SHARE = cache_read / (input + cache_read + cache_creation). The null check and the <= 0 check overlap, so no test kills either alone;
    # removing BOTH divides by zero and kills the whole row-1 pass. current_usage is null before the first call and again after every /compact, where "cache 0%" would be wrong.
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
    # The countdown sits inside the colour span so a red 5h reads as one unit.
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

# ── row 2 · the ground ──
# Three zones: ALARM (act-on words in caps, absent when clean), GROUND (session, tree, PR), AMBIENT (inventory, where truncation is harmless).
ALARM=""; GROUND=""; AMBIENT=""; CIAMB=""; CIALM=""
# The zone owns the colour, not the caller: callers pass PLAIN TEXT (no sed fork per token), harbor-state tokens render grey,
# and the suite asserts PLACE and BOX contain no red, yellow or green. Severity colour exists on YOU only, decided HERE by the word:
# red when broken or unsafe now, yellow when waiting.
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

# Which session: session_name is absent until a name exists, so a name-or-nothing field would show nothing on a fresh terminal.
# Two visibly distinct tiers: a chosen name renders bold, an agent name or session-id stem dim (a dim stem means unnamed). agent.name sits between them.
NAME=""; NAME_KIND=""; PRTOK=""; WTMARK=""; REPO=""
if [ -n "$IN" ] && command -v jq >/dev/null 2>&1; then
  # `kind SP name`: kind never contains a space, so ${x%% *} / ${x#* } is exact (not TSV, which collapses empty fields).
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

  # The open PR for this branch and its review state. pr.review_state may be absent independently of pr; kind == mr is a GitLab merge request and takes the ! sigil.
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
  # The repo, not the directory: a linked worktree is named for its task. workspace.repo.name, the directory as fallback.
  REPO="$(printf '%s' "$IN" | jq -r '.workspace.repo.name // empty' 2>/dev/null || true)"

  # workspace.git_worktree is absent in the main tree and set in any linked worktree. The marker is dim; the hazard (sessions sharing the main tree) is the SHARED TREE alarm.
  WTMARK="$(printf '%s' "$IN" | jq -r 'if (.workspace.git_worktree // "") == "" then empty else "wt" end' 2>/dev/null || true)"
fi

# The session title is the one prose field something else writes, so it is capped (default 80, HARBOR_STATUS_GLYPH_NAME_CAP) to bound the row.
# Cut on a character count, not a word boundary; ${#NAME} is bytes in POSIX sh, so a multibyte title caps shorter, the safe direction.
NAME_CAP="${HARBOR_STATUS_GLYPH_NAME_CAP:-80}"
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
  # Which session is a different fact from which tree, so it takes the boundary mark.
  GROUND="$GROUND $SEP"
fi
# Everything after it is one fact in parts (tree, branch, worktree mark, dirty count, PR), space-joined.
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

# -uall, not -uno: untracked files are how a stray scratch file reaches a commit.
if [ -n "$br" ]; then
  GROUND="$GROUND $br"
  n="$(git -C "$DIR" status --porcelain -uall 2>/dev/null | wc -l | tr -d ' ')"
  # 0 renders nothing: absence is the clean signal.
  [ "${n:-0}" -gt 0 ] && GROUND="$GROUND ${DIM}~$n${RST}"
fi
[ -n "$PRTOK" ] && GROUND="$GROUND $PRTOK"

# ── ⛵ ships · live sessions, how many are busy, how many share this tree ─────
# (L0-11, harbor#75.) Two sources, each used for what it knows:
#   COUNT and busy/idle from Claude Code's session registry ($CFG/sessions/<pid>.json), which covers a session before it has run a tool;
#   TREE attribution from .helm-peers, because the registry cwd is the launch directory (harbor#75).
# No forks: the pid is in the filename and liveness is `kill -0`; context-peers.sh does the accurate procStart check, deliberately not repeated per tick.
# Status is counted, never rendered: registry name/status are peer-supplied, so only a tally of the literal `busy` reaches the row.
SESSDIR="${HARBOR_SESSION_REGISTRY_DIR:-$CFG/sessions}"
SHIPS=0; BUSY=0; HERE=1
for _sf in "$SESSDIR"/*.json; do
  [ -f "$_sf" ] || continue
  _sp="${_sf##*/}"; _sp="${_sp%%.*}"
  case "$_sp" in ''|*[!0-9]*) continue ;; esac
  kill -0 "$_sp" 2>/dev/null || continue
  SHIPS=$((SHIPS + 1))
  # No jq: a substring test cannot be turned into a different question by the record contents.
  case "$(cat "$_sf" 2>/dev/null)" in *'"status":"busy"'*) BUSY=$((BUSY + 1)) ;; esac
done
# Degrade to 1, never 0: an unreadable registry means this script cannot see itself.
[ "$SHIPS" -gt 0 ] || SHIPS=1

if [ -d "$CFG/.helm-peers" ]; then
  _mysid=""
  if [ -n "$IN" ] && command -v jq >/dev/null 2>&1; then
    _mysid="$(printf '%s' "$IN" | jq -r '.session_id // empty' 2>/dev/null || true)"
  fi
  # Only a git work tree can be shared: two sessions launched in a plain folder (~/port) each work in their own
  # worktree, and counting them lit SHARED TREE red on 2026-10-26 with nothing at risk.
  _mytree="$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null || :)"
  [ -n "$_mytree" ] && for _pf in "$CFG"/.helm-peers/*; do
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

# The count is inventory; SHARED TREE (here > 1) is an alarm, because it is the exact condition under which uncommitted work was lost,
# and the narrow tier drops ambient. The ⛵ count sits on PLACE.
PEERS=""
case "$TIER" in
  full|wide) if [ "$BUSY" -gt 0 ]; then PEERS="⛵$SHIPS ·$BUSY busy"
             else PEERS="⛵$SHIPS"; fi ;;
  mid)       PEERS="⛵$SHIPS" ;;
esac
[ "$HERE" -gt 1 ] && alarm "SHARED TREE $HERE"

# ── ⚓ berths · the fleet snapshot ────────────────────────────────────────────
# Rendering owes the cache AGE: a glyph that cannot say how old it is cannot be told from a current one.
# Drift is an alarm WORD, not a glyph (⚠ is East-Asian-width N and may not draw). The predicate counts drift.status == "drift", not drift.total,
# which is the manifest size, so any scaffolded repo made the alarm unreachable at 0. `no-manifest` deliberately does not count (asserted in tests/status/statusline/fleet.test.sh).
# NO APOSTROPHES in the jq block below: it is a shell single-quoted string.
BERTHS=""; DRIFTN=0
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
      # jq's exit code is part of the answer: jq streams, so a cache with trailing junk printed the first document before failing.
      # ONE DOCUMENT OR NOTHING: jq runs the program once per JSON document, so two concatenated arrays print two lines; the line count is the tell.
      # Not a `case` on a newline pattern: command substitution strips the newline, the pattern collapses to `**`, and every cache would blank the tile.
      if [ "$(printf '%s\n' "$g" | wc -l | tr -d ' ')" -gt 1 ]; then g=''; fi
      if [ -n "$g" ]; then
        BERTHS="${g%%	*}"; DRIFTN="${g##*	}"
        case "$DRIFTN" in ''|*[!0-9]*) DRIFTN=0 ;; esac
        if [ "$age" -lt 60 ]; then a="${age}s"; else a="$((age / 60))m"; fi
        # The cache age is a sub-fact of the fleet count (`·4m ago`).
        if [ "$TIER" = narrow ]; then ambient "$BERTHS"; else ambient "$BERTHS ·$a ago"; fi
      fi
    fi
  fi
fi
[ -n "$BERTHS" ] || ambient "fleet: unknown"
[ "$DRIFTN" -gt 0 ] && alarm "DRIFT $DRIFTN"

# ── the pin · LIVE, not cached · WORD ONLY ───────────────────────────────────
# Live, not cached; word only. The pin can change mid-session when settings.json is edited. Nothing renders when it holds: a steady-state token is wallpaper.
# The icon was dropped (it was grey in both states), so PIN DRIFT is the single channel; `harbor verify` and session-verdicts.sh also report the pin.
# No helper: the statusline is one file by design (a `.` per tick costs a fork), so its one hash is spelled inline (harbor#1392).
if [ -f "$CFG/settings.json" ] && command -v jq >/dev/null 2>&1; then
  if [ -f "$CFG/.helm-floor-teeth" ]; then
    pinned="$(cat "$CFG/.helm-floor-teeth" 2>/dev/null || true)"
    live="$(jq -S '{deny:.permissions.deny, locks:{bypass:.permissions.disableBypassPermissionsMode, auto:.permissions.disableAutoMode}}' \
              "$CFG/settings.json" 2>/dev/null | { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi; } | awk '{print $1}' || true)"
    # The hash is computed even when nothing renders: it is what decides that nothing should.
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
# The numbers above are only as true as the launchd jobs that write them. status-fleet-snapshot-refresh.sh caches the loaded-job count in .helm-watch (no `launchctl list` per tick).
# Renders nothing when the file is absent: the check never ran, which is renew-check's verdict, not a number to invent.
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
# Written twice a day by housekeeping-clean.sh --record (rides fleet-snapshot's run, 09:00 and 16:00): `items` are the DECIDE and RISK rows. Cached, not probed (a GitHub read per repo).
# Zero renders nothing. `?` means a repo was unread or the record is older than 26h, so the number is a lower bound.
# SWEEP is an alarm with an age; `due=1` is the writer's call, not re-derived here.
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
        SWEEPTOK="SWEEP $_si$_sq ·$_sg"
      fi ;;
  esac
fi

# ── ⧗ obligations · work that was opened and has not been closed (harbor#1050, docs/reference/checks.md row status.obligations) ──
# status-obligations.sh writes the cache inside fleet-snapshot's run and stores epochs; the overdue age is computed here at print time. OVERDUE is the alarm, with its age.
# A cache over 900s old claims neither a queue nor an alarm; an unreadable source still shows OVERDUE.
#
# The YOU queue is the cache's `you` list: operator-owned handoffs (event-bus.sh emit obligation.open, no session id) and approvals. Titles are session-written, so control
# characters are stripped and the text capped at 40 columns here as well as at the fold (an escape sequence must not repaint this row);
# the full title is in `harbor status obligations --json` (the print view clips at 70). Overdue items are red.
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
# harbor#657. ci-queue.sh stores each repo's expected finish as an EPOCH and the minutes are subtracted here, so time left keeps counting down between refreshes. `~` because the estimate ignores `needs:`.
# Idle renders nothing; `due` is a job past its usual length. `?` means a repo unread or a cache over 900s old: the count then shows with no time.
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
  # A wedged runner is an alarm, not inventory (harbor#152): ci-queue.sh calls a stall when a self-hosted job queued past ten minutes while a runner sat idle on two refreshes.
  # A stale cache says nothing. The remedy is in `sh bin/ci-queue.sh --print`.
  _cis="$(jq -r --argjson now "$NOW_EPOCH" '
      if ($now - ((.at // 0) | tonumber)) > 900 then empty
      elif ([.repos[]? | select(.stall == true)] | length) > 0 then "CI STALL"
      else empty end' "$CACHE_DIR/ci-queue.json" 2>/dev/null || true)"
  [ -n "$_cis" ] && ci_alarm "$_cis"
fi

# ── MAIN RED · a fleet repo's main has no green CI verdict (harbor#586) ─────────────
# ci-main-tip-verdict.sh writes {at, unread, repos:[{repo, tip, ...}]} inside fleet-snapshot's run; an older single-repo cache has no .repos and reads as one nameless repo.
# An ALARM: the age counts at print time from tip.red_at (the commit time in an older cache); one failed push run reads `·1 run`. A scheduled workflow failing beside a green push tip
# is `SCHED <repo>`, ambient (tip.sched). A cache over 900s old or an unread one shows `main?`. Compact: `MAIN RED estate 3h`, two are listed, more count.
if [ -f "$CACHE_DIR/main-tip-verdict.json" ] && command -v jq >/dev/null 2>&1; then
  _mt="$(jq -r --argjson now "$NOW_EPOCH" '
      def ago: if . < 3600 then "\(. / 60 | floor)m" elif . < 172800 then "\(. / 3600 | floor)h" else "\(. / 86400 | floor)d" end;
      . as $c | (($now - (($c.at // 0) | tonumber)) > 900) as $stale
      | ([($c | if (.repos | type) == "array" then .repos else [.] end)[]
         | select(.tip.red == true and (.unread != true)) | {n: ((.repo // "") | sub("^[^/]*/"; "")), a: ($now - (.tip.red_at // .tip.at)), one: (.tip.single == true)}] | sort_by(-.a)) as $red
      | if $stale then "?"
        elif ($red | length) == 0 then (if $c.unread == true then "?" else empty end)
        elif ($red | length) > 2 then "!\($red | length) repos, oldest \($red[0].a | ago)"
        else "!" + ($red | map((if .n == "" then "" else .n + " " end) + (.a | ago) + (if .one then " ·1 run" else "" end)) | join(", ")) end' \
      "$CACHE_DIR/main-tip-verdict.json" 2>/dev/null || true)"
  case "$_mt" in
    '?') ci_ambient "main?" ;;
    '!'*) ci_alarm "MAIN RED ${_mt#!}" ;;
  esac
  _ms="$(jq -r --argjson now "$NOW_EPOCH" '
      . as $c | if (($now - (($c.at // 0) | tonumber)) > 900) then empty else
      [($c | if (.repos | type) == "array" then .repos else [.] end)[]
       | select(.tip.red != true and .unread != true and ((.tip.sched // []) | length) > 0) | ((.repo // "") | sub("^[^/]*/"; ""))]
      | if length == 0 then empty elif length > 2 then "SCHED \(length) repos" else "SCHED " + join(", ") end end' \
      "$CACHE_DIR/main-tip-verdict.json" 2>/dev/null || true)"
  [ -n "$_ms" ] && ci_ambient "$_ms"
fi

# ── CI→local · the month's Actions minutes ran short and CI fell back to the self-hosted runners (harbor#865) ─────
# ci-runner-switch.sh writes the cache and sets HARBOR_CI_RUNNER; the FALLBACK is the news, so github-hosted (the normal state) renders nothing.
# The runners are this Mac and a Linux container, hence `local`. A cache over 900s old or an unread one says `CI?`.
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

# ── PLAN / GATE · the account plan or main's protection differs from what a person acknowledged (bin/ci-github-plan.sh) ──
# harbor#1060: Pro -> Free on 2026-10-05 turned protection off and surfaced only when a merge was refused. The alarm
# holds until `ci-github-plan.sh ack`; a cache over 900s old or a failed read is `plan?`, never a calm state.
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

# Cache written by status-fleet-snapshot-refresh.sh (harbor#44): the answer needs a `git rev-list` and a LaunchAgents walk. RED: a renewal not done is a merged guard that gates nothing here.
# The count is dropped and the tokens kept verbatim: drift-renew-check.sh owns this vocabulary (`renew 2 runtime3·floor4`), and re-spelling it here could disagree with it.
if [ -f "$CFG/.helm-renew" ]; then
  r="$(head -1 "$CFG/.helm-renew" 2>/dev/null || true)"
  case "$r" in
    "renew 0"|"renew 0 "*|"") ;;
    renew\ *) _rt="${r#renew }"; _rt="${_rt#* }"
              [ -n "$_rt" ] && alarm "STALE ${_rt}" ;;
  esac
fi

# The daily judge's verdict, which no other surface on the row reads (`renew` only notices a missing or two-day-stale file). The age is required: an undated verdict cannot be falsified.
# Age comes from the file mtime, not from parsing the ISO stamp (`date -j -f` is BSD-only). `worst=ok` renders nothing.
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

[ -n "$SWEEPTOK" ] && alarm "$SWEEPTOK"
[ -n "$OBLTOK" ] && alarm "$OBLTOK"

# Overrides only: `blocks N` was a monotonic lifetime counter nothing could move. An override is the operator saying a rule is wrong; it renders nothing until one happens.
if [ -f "$OBS" ] && command -v jq >/dev/null 2>&1; then
  o="$(jq -r 'if (.overrides // 0) > 0 then "ovr \(.overrides)" else empty end' "$OBS" 2>/dev/null || true)"
  [ -n "$o" ] && alarm "${o}"
fi

# Proposal packets waiting for a human (harbor#44): nothing at zero or when the file is absent.
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
if [ "${HARBOR_STATUS_GLYPH_MACHINE:-1}" != 0 ]; then
  # CPU busy is read from a cache written by a detached sampler (iostat -c 2 -w 1), so its 1 s wait never lands on a tick; `ps %cpu` is a decayed average and `top -l 1` costs 250 ms.
  CPUC="$CACHE_DIR/machine-cpu"; _ce=0; _cp=""
  if [ -r "$CPUC" ]; then read -r _ce _cp < "$CPUC" 2>/dev/null || true; fi
  case "$_ce" in ''|*[!0-9]*) _ce=0; _cp="" ;; esac
  case "$_cp" in ''|*[!0-9]*) _cp="" ;; esac
  _age=$(( NOW_EPOCH - _ce ))
  if [ "$_age" -lt 0 ] || [ "$_age" -gt 120 ]; then _cp=""; fi
  if [ "${HARBOR_STATUS_GLYPH_MACHINE_REFRESH:-1}" != 0 ] && { [ -z "$_cp" ] || [ "$_age" -ge 8 ]; } \
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
  # DISK, used/total, on the volume holding $HOME (the Data volume on macOS; used = total - available because APFS volumes share a container). Yellow under 15% free, red under 7%. HARBOR_STATUS_GLYPH_DF stands in for df in the suite.
  _df="$("${HARBOR_STATUS_GLYPH_DF:-df}" -k "${HOME:-/}" 2>/dev/null | awk 'NR == 2 && $2 ~ /^[0-9]+$/ && $4 ~ /^[0-9]+$/ && $2 > 0 {
          printf "%d %d %d", ($2 - $4) / 1048576, $2 / 1048576, ($4 * 100) / $2 }')" || true
  case "$_df" in
    *[!0-9\ ]*|'') ;;
    *) _du="${_df%% *}"; _dp="${_df##* }"; _dt="${_df#* }"; _dt="${_dt% *}"
       if [ "$_dp" -lt 7 ]; then _lv=2; elif [ "$_dp" -lt 15 ]; then _lv=1; else _lv=0; fi
       seg3 "$_lv" "SSD ${_du}/${_dt}G" ;;
  esac
  # SWAP, used/total, shown once sysctl answers; macOS grows swap on demand, so a total of 0 is real and reads `0/0G`.
  if [ -n "$_sw" ]; then lvl "$_swmb" 2048 6144; seg3 "$_lv" "swap ${_sw}/${_swt:-0}G"; fi
fi

# ── row 3 · is the internet safe, is Remote Control on (operator request 2026-10-12) ──
# Emoji by operator request, an exception to decision 3: 🏠 trusted gateway, 🔒 VPN route,
# 🔓 neither or firewall off; 📱/📵 Remote Control. An unreadable source renders nothing.
NET3=""
if [ "${HARBOR_STATUS_GLYPH_MACHINE:-1}" != 0 ]; then
  _fw="$("${HARBOR_STATUS_GLYPH_FIREWALL:-/usr/libexec/ApplicationFirewall/socketfilterfw}" --getglobalstate 2>/dev/null \
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
# ── Rows: PLACE, YOU, BOX ──
# Alarms lead a row of their own (YOU), so no system notification on the right of a row can clip them. The old alarms-first / alarms-last argument is superseded; see the case document.
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
