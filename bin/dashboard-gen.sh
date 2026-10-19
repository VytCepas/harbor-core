#!/usr/bin/env sh
# VIZ-1 (harbor#59 follow-on) — render Harbor's numbers as a local HTML page.
#
#   sh dashboard-gen.sh            # write build/dashboard.html
#   sh dashboard-gen.sh --open     # ... and open it
#   sh dashboard-gen.sh --stdout   # print the HTML instead of writing
#
# WHY A VIEW AND NOT A DOCUMENT. STATUS.md is the one place Harbor states a
# number about itself (lint T1/T2). A dashboard that hard-coded any of these
# would be a copy of a fact that lives in the code — and a chart is a WORSE place
# for a copy than prose is, because nobody greps a chart to find the stale
# number. So every figure here comes from `status-gen.sh --json`, `freshness.sh`
# or git, at render time. This file states no counts of its own, and the page it
# writes is git-ignored: it is output, not a source.
#
# UNAVAILABLE IS NOT ZERO. If `gh` cannot reach GitHub the ticket panel says so.
# A burn-down chart that renders 0 open tickets because the network was down is
# the same class of lie as a test that cannot fail — it reads as good news.
#
# SELF-CONTAINED, no network at view time: inline CSS, inline SVG, no fonts, no
# CDN. It must render on a laptop with the wifi off, which is when you most want
# to know what state the floor is in.
#
# DELIBERATELY ONE FILE (DOCTRINE/modularity.md), and G1 asked once it passed 300
# lines: this is a single renderer whose output is ONE page. Splitting it per panel
# would spread one HTML document across several files that must agree on the same
# stylesheet, the same escaping and the same bar() semantics — three copies of a
# contract with no test between them. The blast radius is a git-ignored page either
# way, and the numbers all come from other tools by design.
set -eu

# --help BEFORE ANY WORK (S4, harbor#140). Placed immediately after strict mode
# so it is the first executable line: a --help that reaches an argument parser is
# a --help that a script with no parser ignores, and this file had none. Measured
# 2026-08-20: a sweep of `bin/*.sh --help` ran past five minutes because at least
# one script treated the flag as a request to do work, and five of the scripts
# with no --help at all are mutators. The text is the header, read out of THIS
# file at runtime, so a help message cannot drift from what the script says it is.
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
ROOT="${HARBOR_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
# One log format (CONTRACTS/logging.md), on stderr: stdout is the page itself under --stdout.
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/log-lib.sh"
LOG_FD=2; log_init dashboard-gen
OUT="$ROOT/build/dashboard.html"
MODE="${1:-}"
# UNKNOWN FLAG → 2 (CONTRACTS/cli.md:70), AND VALIDATED BEFORE THE RENDER.
# The `case "$MODE"` at the bottom of this file dispatches `--stdout` and falls
# everything else into `*)`, which WRITES THE PAGE. So `harbor dash --bogus`
# rendered the dashboard and exited 0 — cli.md's own words for that shape are
# "must not silently accept and ignore the flag — that is worse than refusing,
# because a caller parsing empty output cannot tell 'no data' from 'flag not
# supported'". Measured 2026-08-14 alongside `harbor fresh` and `harbor cite`.
#
# Checked HERE rather than in the bottom `case`, so a typo costs no render: the
# page reads status-gen --json, freshness.sh and git before it can fail.
case "$MODE" in
  ''|--stdout|--open) ;;
  *) printf 'dashboard-gen: unknown flag %s (accepts: --stdout, --open)\n' "$MODE" >&2; exit 2 ;;
esac

if ! command -v jq >/dev/null 2>&1; then log_fail "jq is required, and is not on PATH"; log_fix "$(pkg_hint jq)"; log_end || :; exit 1; fi

# HTML-escape. `deny_installed` carries backticks and parentheses today and will
# carry whatever a future ticket puts in it; an unescaped `<` would silently eat
# the rest of the page.
esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

# ── the numbers, from their single author ────────────────────────────────────
J="$(sh "$ROOT/bin/status-gen.sh" --json-fast 2>/dev/null || echo '{}')"
if [ "$J" = "{}" ]; then
  log_fail "status-gen --json-fast produced nothing ($ROOT/bin/status-gen.sh), so no page is rendered: an empty one would read as zeros"
  log_fix "sh '$ROOT/bin/status-gen.sh' --json-fast"
  log_end || :; exit 1
fi
jget() { printf '%s' "$J" | jq -r "$1" 2>/dev/null || printf 'unavailable'; }

n_rules="$(jget '.counted.lint_rules')"
n_skills="$(jget '.counted.vendored_skills')"
n_contracts="$(jget '.counted.frozen_contracts')"
n_guards="$(jget '.counted.floor_guards')"
n_cases="$(jget '.counted.marker_fixtures')"
a_floor="$(jget '.assertions."floor-test"')"
a_norm="$(jget '.assertions."normalize-test"')"
a_marker="$(jget '.assertions."marker-test"')"
o_deny="$(jget '.observed.b1_deny')"
o_hooks="$(jget '.observed.guard_hooks')"
o_const="$(jget '.observed.constitution')"
o_drift="$(jget '.observed.live_bin_lagging')"

# Guards WIRED is the number that decides whether any of this protects anything,
# and it is not in STATUS.md as a count — it is a yes/no there. Derive the pair:
# built is countable, wired is observed, and the gap is the whole story.
guards_wired=0
case "$o_hooks" in yes) guards_wired="$n_guards" ;; esac

# ── pulse — the between-sessions probe, and the fleet it watches (harbor#9) ──
# Both are READ here and derived nowhere: pulse-notify.sh is the only writer of
# the state file, and fleet-snapshot-refresh.sh is the only writer of the cache.
# A dashboard that recomputed either would be a second opinion about a fact that
# already has an author.
PCFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
# TWO STEPS, IN THE WRITER'S ORDER. pulse-notify.sh resolves the cache dir first
# and the state path from it, so a reader that jumps straight to the config dir
# looks in a different place the moment HARBOR_CACHE_DIR is set without the more
# specific override — the fleet tile would honour the custom dir while the Pulse
# tile reported that no probe had ever run. Same shape as the resolution bug the
# seam survey found in fleet-snapshot-refresh.sh.
PCACHE="${HARBOR_CACHE_DIR:-$PCFG/cache}"
PSTATE="${HARBOR_PULSE_STATE:-$PCACHE/pulse-state.json}"
FSNAP="$PCACHE/fleet-snapshot.json"
PJ='{}'
[ -f "$PSTATE" ] && PJ="$(cat "$PSTATE" 2>/dev/null || printf '{}')"
printf '%s' "$PJ" | jq -e . >/dev/null 2>&1 || PJ='{}'

# ── assertion history — from git, the only place it is recorded ──────────────
# Each commit that touched STATUS.md carries the totals of the day. No new state
# file: the history already exists, it was just never read.
HIST="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"; trap 'rm -f "$HIST" "$TIX" 2>/dev/null' EXIT INT TERM HUP
git -C "$ROOT" log --format='%h %cs' -- STATUS.md 2>/dev/null | while read -r sha day; do
  _n="$(git -C "$ROOT" show "$sha:STATUS.md" 2>/dev/null \
        | grep -F '`floor-test`' | grep -oE '[0-9]+' | head -1 || true)"
  [ -n "${_n:-}" ] && printf '%s\t%s\n' "$day" "$_n"
done | sort -u > "$HIST" || true
# The working tree is the newest point and git does not know it yet. Without this
# the series ends at the last COMMIT while the panel above shows the current
# total, and the two disagree on the same page — the drift T2 exists to stop,
# reintroduced by a chart. Appended only when it actually differs.
_last="$(tail -1 "$HIST" | cut -f2)"
if [ -n "${_last:-}" ] && [ "$_last" != "$a_floor" ]; then
  printf '%s\t%s\n' "now" "$a_floor" >> "$HIST"
fi

# ── tickets — fail-SOFT and say so ──────────────────────────────────────────
TIX="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"
tix_state="unavailable"
if command -v gh >/dev/null 2>&1; then
  if gh issue list --state all --limit 300 --json state,labels > "$TIX" 2>/dev/null; then
    tix_state="ok"
  fi
fi
t_open=0; t_closed=0; t_sec=0; t_bug=0
if [ "$tix_state" = "ok" ]; then
  t_open="$(jq '[.[] | select(.state=="OPEN")] | length' "$TIX")"
  t_closed="$(jq '[.[] | select(.state=="CLOSED")] | length' "$TIX")"
  t_sec="$(jq '[.[] | select(.state=="OPEN") | select(.labels[]?.name=="security")] | length' "$TIX")"
  t_bug="$(jq '[.[] | select(.state=="OPEN") | select(.labels[]?.name=="bug")] | length' "$TIX")"
fi

# ── the always-on budget — reuse the measurer, parse its labels ─────────────
# Anchored on the label and taking the first number after it, NOT on a field index:
# a field index breaks the moment a label's word count changes, which is exactly how
# floor-test's first version of this parse read the word `injection)` as a number.
_bud="$(sh "$ROOT/bin/context-budget.sh" 2>/dev/null || true)"
BUD_SPENT="$(printf '%s\n' "$_bud" | sed -n 's/^SPENT[^0-9]*\([0-9][0-9]*\).*/\1/p')"
BUD_PROJ="$(printf '%s\n' "$_bud" | sed -n 's/^PROJECTED[^0-9]*\([0-9][0-9]*\).*/\1/p')"
BUD_CEIL="$(printf '%s\n' "$_bud" | sed -n 's/.*ceiling \([0-9][0-9]*\).*/\1/p' | head -1)"
[ -n "${BUD_PROJ:-}" ] || BUD_PROJ="$BUD_SPENT"

# ── skills — the live surface, ambient vs invoked-only ──────────────────────
# Measured from the INSTALLED skills, not the vendored copies: what costs money is
# what the harness loads. `description:` length is the ambient cost; the body loads
# only on invocation.
SK_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"
SK_ROWS=""; SK_AMB_N=0; SK_INV_N=0; SK_AMB_B=0
if [ -d "$SK_DIR" ]; then
  for _d in "$SK_DIR"/*/; do
    _f="$_d/SKILL.md"; [ -f "$_f" ] || continue
    _n="$(basename "$_d")"
    _b="$(awk '/^description:/{print length($0); exit}' "$_f" 2>/dev/null || echo 0)"
    _b="${_b:-0}"
    if grep -q '^disable-model-invocation:[[:space:]]*true' "$_f" 2>/dev/null; then
      _t=INVOKED; SK_INV_N=$(( SK_INV_N + 1 ))
    else
      _t=AMBIENT; SK_AMB_N=$(( SK_AMB_N + 1 )); SK_AMB_B=$(( SK_AMB_B + _b ))
    fi
    SK_ROWS="$(printf '%s\n%s\t%s\t%s' "$SK_ROWS" "$_b" "$_t" "$_n")"
  done
  # Dearest first: the point of the panel is deciding what to demote.
  SK_ROWS="$(printf '%s\n' "$SK_ROWS" | grep -v '^$' | sort -rn)"
fi

# ── document freshness — reuse the scorer, do not re-implement it ────────────
FRESH_ALL="$(sh "$ROOT/bin/freshness.sh" 2>/dev/null | awk '
  /^────/ {on=1; next}
  /^$/    {on=0}
  on && NF>=4 && $2 ~ /d$/ {gsub(/d$/,"",$2); gsub(/d$/,"",$3); print $1"\t"$2"\t"$3}
' || true)"
# freshness.sh already sorts stalest-first, so the head IS the interesting end.
# THE CAP IS STATED, never silent: a panel that quietly shows ten of thirty reads
# as "thirty documents, all fine" — the same failure mode as a chart rendering 0
# for missing data.
FRESH_N="$(printf '%s' "$FRESH_ALL" | grep -c . || true)"
FRESH_SHOW=10
FRESH="$(printf '%s\n' "$FRESH_ALL" | head -"$FRESH_SHOW")"

# ── render ──────────────────────────────────────────────────────────────────
# bar <label> <value> <max> — width is a percentage, so the page needs no JS and
# no chart library to be readable, and it degrades to plain text if CSS is off.
bar() {
  _pct=0
  [ "$3" -gt 0 ] 2>/dev/null && _pct=$(( $2 * 100 / $3 ))
  [ "$_pct" -le 100 ] || _pct=100
  printf '<div class="row"><span class="k">%s</span><span class="t"><i style="width:%s%%"></i></span><span class="v">%s</span></div>\n' \
    "$(printf '%s' "$1" | esc)" "$_pct" "$(printf '%s' "$2" | esc)"
}

pill() { # <label> <value> — a standing yes/no, worded, never a glyph (L0-5)
  case "$2" in
    yes)                 _c="good" ;;
    no)                  _c="bad"  ;;
    0)                   _c="good" ;;
    unavailable)         _c="unk"  ;;
    ok)                  _c="good" ;;
    crit)                _c="bad"  ;;
    unknown)             _c="unk"  ;;
    *)                   _c="warn" ;;
  esac
  printf '<div class="pill %s"><span>%s</span><b>%s</b></div>\n' \
    "$_c" "$(printf '%s' "$1" | esc)" "$(printf '%s' "$2" | esc)"
}

spark() { # inline SVG polyline over the assertion history
  _n="$(wc -l < "$HIST" | tr -d ' ')"
  if [ "$_n" -lt 2 ]; then
    printf '<p class="none">Only one recorded data point so far — the series starts once STATUS.md has been regenerated on a second day.</p>'
    return 0
  fi
  awk -F'\t' -v w=520 -v h=90 '
    {d[NR]=$1; v[NR]=$2; if (v[NR]>mx || NR==1) mx=v[NR]; if (v[NR]<mn || NR==1) mn=v[NR]}
    END {
      if (mx==mn) mx=mn+1
      printf "<svg viewBox=\"0 0 %d %d\" class=\"spark\" role=\"img\" aria-label=\"floor-test assertions over time\">", w, h+22
      pts=""
      for (i=1;i<=NR;i++) {
        x = (NR==1) ? 0 : (i-1)*(w-40)/(NR-1) + 20
        y = h - 10 - (v[i]-mn)*(h-25)/(mx-mn)
        pts = pts sprintf("%.1f,%.1f ", x, y)
      }
      printf "<polyline points=\"%s\"/>", pts
      for (i=1;i<=NR;i++) {
        x = (NR==1) ? 0 : (i-1)*(w-40)/(NR-1) + 20
        y = h - 10 - (v[i]-mn)*(h-25)/(mx-mn)
        printf "<circle cx=\"%.1f\" cy=\"%.1f\" r=\"3\"/>", x, y
        if (i==1 || i==NR) printf "<text x=\"%.1f\" y=\"%d\" class=\"lbl\">%s</text>", x, h+16, d[i]
      }
      printf "<text x=\"20\" y=\"12\" class=\"lbl\">%d → %d</text>", v[1], v[NR]
      printf "</svg>"
    }' "$HIST"
}

render() {
# THE DARK BLOCK REDEFINES EVERY COLOUR TOKEN, and lint H1 now fails the commit
# if it does not. It shipped without `--unk` (added 2026-08-31): the unknown and
# unavailable statuses therefore drew a light-ground grey on a #151514 ground at
# 3.42:1, under the 4.5:1 AA floor, while `--dim` — the SAME hex in light mode —
# got #9a9a96 for 6.47:1. Because the two tokens are identical under `:root`,
# light mode rendered the omission perfectly and gave no signal for months.
#
# `--panel` IS A SURFACE AND `--bar` IS A TRACK, and they are not interchangeable
# (added 2026-09-01). `--bar` sizes the 8px `.t` rail, where nothing sits on top;
# it was also painting the ground behind `code` and `.sl`, so every ink in the
# status line was measured against #c9c9c4 / #33332f instead of a real surface.
# Twelve AA failures, all one cause. The name is archify's — its template calls
# this role `--panel` and ours had no word for it, which is why a track got the job.
#
# TWO INKS THEN FAILED ON THEIR OWN. Light `--warn` #9a6b12 reaches only 4.49:1 on
# pure white, so no panel could have saved it; `--good` #2f7d5c cleared the panel by
# 0.09. Darkened to #8b6010 (4.91 on panel, 5.37 on bg) and #2d7757 (4.78 / 5.22).
# Dark mode needed no ink change at all — the same asymmetry as `--unk` above, and
# for the same reason: a colour chosen as a text colour survives being used as one.
# No status token is a fill or a border anywhere in this file, so darkening is safe.
cat <<'HEAD'
<!doctype html>
<meta charset="utf-8">
<title>Harbor — state</title>
<style>
:root{--bg:#fbfbfa;--fg:#1a1a19;--dim:#6b6b68;--line:#e3e3e0;--good:#2d7757;--bad:#a33a3a;--warn:#8b6010;--unk:#6b6b68;--panel:#f1f1ef;--bar:#c9c9c4;--barf:#3f3f3c}
@media(prefers-color-scheme:dark){:root{--bg:#151514;--fg:#ececea;--dim:#9a9a96;--line:#2c2c2a;--good:#63b58c;--bad:#e07a7a;--warn:#d4a24c;--unk:#9a9a96;--panel:#232321;--bar:#33332f;--barf:#b9b9b3}}
*{box-sizing:border-box}
body{margin:0;padding:32px;background:var(--bg);color:var(--fg);font:15px/1.5 ui-sans-serif,-apple-system,system-ui,sans-serif}
h1{font-size:20px;margin:0 0 4px}
.sub{color:var(--dim);font-size:13px;margin:0 0 28px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(340px,1fr));gap:20px}
section{border:1px solid var(--line);border-radius:10px;padding:16px 18px;min-width:0}
h2{font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:var(--dim);margin:0 0 14px;font-weight:600}
.row{display:flex;align-items:center;gap:10px;margin:6px 0;font-size:13px}
.k{flex:0 0 42%;color:var(--fg);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.t{flex:1;height:8px;background:var(--bar);border-radius:5px;overflow:hidden}
.t i{display:block;height:100%;background:var(--barf)}
.v{flex:0 0 46px;text-align:right;font-variant-numeric:tabular-nums;color:var(--dim)}
.pill{display:flex;justify-content:space-between;gap:12px;padding:8px 0;border-bottom:1px solid var(--line);font-size:13px}
.pill:last-child{border-bottom:0}
.pill b{font-weight:600;text-align:right}
.pill.good b{color:var(--good)}.pill.bad b{color:var(--bad)}.pill.warn b{color:var(--warn)}.pill.unk b{color:var(--unk)}
.spark{width:100%;height:auto}
.spark polyline{fill:none;stroke:var(--barf);stroke-width:2}
.spark circle{fill:var(--barf)}
.spark .lbl{fill:var(--dim);font-size:11px}
.none{color:var(--dim);font-size:13px;margin:4px 0}
footer{margin-top:28px;color:var(--dim);font-size:12px;border-top:1px solid var(--line);padding-top:12px}
code{font:12px ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--panel);padding:1px 4px;border-radius:3px}
details{margin:0 0 10px}
summary{cursor:pointer;font-size:13px;padding:6px 0;border-bottom:1px solid var(--line);list-style:none}
summary::-webkit-details-marker{display:none}
summary::before{content:"▸ ";color:var(--dim)}
details[open] summary::before{content:"▾ "}
summary b{font-weight:600;color:var(--dim)}
table{width:100%;border-collapse:collapse;margin:8px 0;font-size:12px;display:block;overflow-x:auto}
th{text-align:left;color:var(--dim);font-weight:600;padding:4px 8px 4px 0;white-space:nowrap}
td{padding:3px 8px 3px 0;border-top:1px solid var(--line);vertical-align:top}
td.n{font-variant-numeric:tabular-nums;color:var(--dim);white-space:nowrap}
td.amb{color:var(--warn);font-weight:600;white-space:nowrap}
td.inv{color:var(--dim);white-space:nowrap}
section.wide{grid-column:1/-1}
.sl{font:13px/1.9 ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--panel);border-radius:8px;padding:12px 14px;margin:0 0 14px;overflow-x:auto;white-space:pre}
.sl .z{color:var(--dim)}
.sl .al{color:var(--bad);font-weight:600}
.sl .wn{color:var(--warn);font-weight:600}
.sl .gd{color:var(--good)}
.zk{display:inline-block;min-width:74px;font:11px ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:.04em;text-transform:uppercase;color:var(--dim)}
td.ic{font-size:15px;white-space:nowrap;padding-right:10px}
td.tk{font:12px ui-monospace,SFMono-Regular,Menlo,monospace;white-space:nowrap;color:var(--fg)}
tr.alarmrow td.tk{color:var(--bad)}
</style>
HEAD

printf '<h1>Harbor — state</h1>\n'
printf '<p class="sub">Every figure is derived at render time from <code>status-gen.sh --json</code>, <code>freshness.sh</code> and git. Generated %s.</p>\n' "$(date '+%Y-%m-%d %H:%M')"
printf '<div class="grid">\n'

printf '<section><h2>Does anything protect anything</h2>\n'
pill "B1 deny layer (harness, pre-hook)" "$o_deny"
pill "B2–B6 guard hooks wired" "$o_hooks"
pill "constitution in force" "$o_const"
pill "live bin/ scripts lagging" "$o_drift"
printf '<p class="none">Guards built: %s. Guards wired: %s. The gap is the whole story — <code>pass-score.sh</code> exits 2, so this is the current correct state, not a todo.</p>\n' \
  "$(printf '%s' "$n_guards" | esc)" "$(printf '%s' "$guards_wired" | esc)"
printf '</section>\n'

printf '<section><h2>Pulse — the between-sessions probe</h2>\n'
if [ "$PJ" = '{}' ]; then
  # NOT the word "unavailable": the ticket panel below owns that string, and a
  # second producer of it would make VIZ-1's whole-page assertion pass for the
  # wrong reason. This says the specific thing that is true instead.
  printf '<p class="none">No probe has run on this machine. <code>launchd/com.harbor.pulse.plist</code> is what fires it; until that is bootstrapped, nothing checks this box while no session is open.</p>\n'
else
  _pran="$(printf '%s' "$PJ" | jq -r '.ran_at // 0')"
  _page=$(( $(date +%s) - _pran ))
  [ "$_page" -ge 0 ] || _page=0
  printf '%s' "$PJ" | jq -r '.checks | to_entries[] | [.key, .value.verdict] | @tsv' 2>/dev/null \
  | while IFS='	' read -r _k _v; do pill "$_k" "$_v"; done
  # A STALE RUN IS NOT A HEALTHY ONE. Three intervals without a write means the
  # job stopped, and the verdicts above are history — say so beside them rather
  # than letting an old green read as this minute's.
  if [ "$_page" -gt 2700 ]; then
    printf '<p class="none"><b>Last ran %sm ago</b> — past three intervals, so these verdicts are history and the job itself is the finding.</p>\n' "$(( _page / 60 ))"
  else
    printf '<p class="none">Last ran %sm ago; answered %s of %s checks; %s notification(s) sent that run. Sink: %s.</p>\n' \
      "$(( _page / 60 ))" \
      "$(printf '%s' "$PJ" | jq -r '.inputs_seen // 0')" \
      "$(printf '%s' "$PJ" | jq -r '.checks_run // 0')" \
      "$(printf '%s' "$PJ" | jq -r '.notifications // 0')" \
      "$(printf '%s' "$PJ" | jq -r '.sink // "?"' | esc)"
  fi
fi
printf '</section>\n'

# ── the statusline legend (L0-5b, harbor#293) ────────────────────────────────
# WHY A LEGEND IS A PANEL AND NOT A COMMENT. The statusline is the one Harbor
# surface an operator reads hundreds of times a day, and it is deliberately
# terse: four icons and a dozen abbreviations across two rows. Terse is right for
# a status bar and wrong for the only place its vocabulary is defined — the
# operator asked what "⚓8 ✎2 ⇅1" meant after months of it being on screen, which
# is the whole argument for this table existing somewhere readable.
#
# THE MEANINGS ARE STATIC AND THE VALUES ARE DERIVED, and the split is the point.
# A legend row saying what `📌` means is a definition, and definitions belong in
# prose. The LIVE column beside it is a fact, so it is read at render time from
# the same file the statusline reads — never restated here. That is this file's
# own rule (nothing on this page states a count of its own), and it is also the
# only way the table can be trusted: if the page and the row ever disagree, the
# page is reading the wrong file and you can see it.
#
# "NOT WRITTEN" IS NOT "ZERO". Every source below is a cache some launchd job
# produces. An absent one means the job has never run, which is a different fact
# from a clean verdict and is rendered as such — the same discipline the
# statusline itself follows when it renders nothing rather than a reassuring 0.
_slv() { # <file> — the first line of a helm cache, or the absent marker
  if [ -f "$1" ]; then head -1 "$1" 2>/dev/null | esc; else printf 'not written'; fi
}
_slrow() { # <icon> <token> <zone> <meaning> <source> <live> [alarm]
  printf '<tr%s><td class="ic">%s</td><td class="tk">%s</td><td class="inv">%s</td><td>%s</td><td class="inv"><code>%s</code></td><td class="n">%s</td></tr>\n' \
    "${7:+ class=\"alarmrow\"}" "$1" "$2" "$3" "$4" "$5" "$6"
}
printf '<section class="wide"><h2>Reading the statusline</h2>\n'

# The mock is a MOCK and says so. Rendering the operator's real row here would
# need this page to hold a session payload it does not have; what it can honestly
# show is the shape and the zone order, which is the part that was wrong before.
printf '<div class="sl"><span class="zk">row 1</span>Opus 5 1M <span class="z">│</span> <span class="wn">MAX</span> <span class="z">│</span> ctx 38%% <span class="z">│</span> <span class="z">cache 94%%</span> <span class="z">│</span> $2.14 <span class="z">│</span> 5h 12%% <span class="z">·in 2h10m</span> <span class="z">│</span> 7d 47%% <span class="z">·in 1d22h</span>\n'
printf '<span class="zk">row 2</span><span class="al">STALE runtime3·floor4</span> <span class="z">│</span> <span class="al">JUDGE crit 1 ·16h</span> <span class="z">│</span> <span class="z">a3d7bc</span> <span class="z">│</span> harbor main <span class="gd">#292 approved</span> <span class="z">│</span> ⛵5<span class="z"> ·3 busy</span> <span class="z">│</span> ⚓8<span class="z"> ·2 dirty</span> <span class="z">│</span> 📡6 <span class="z">│</span> <span class="z">4m</span></div>\n'
printf '<p class="none"><b>Two marks, and the difference is the trailing space.</b> <code> │ </code> means a DIFFERENT fact; <code> ·</code> means MORE ABOUT the fact on its left, with no gap before the value — so <code>5h 12%% ·in 2h10m</code> is one fact (the five-hour window: how much used, when it refills) and the bar before <code>7d</code> starts another. A plain single space is the third and commonest relationship, "same fact, next part of it": <code>harbor main #292 approved</code>. Before 2026-08-24 the boundary was two spaces and the sub-fact a middot, which asked you to tell one space from two at a glance; <code>runtime3·floor4</code> keeps a third, tight form because that token is renew-check quoted verbatim.</p>\n'
printf '<p class="none"><b>Three zones, left to right: what you are working on, then the inventory, then the alarms.</b> This <b>reversed on 2026-08-24</b> at the operator&#39;s request, and the reversal has a known cost. Claude Code renders its own system notifications (MCP errors, auto-updates) on the right of this same row and documents that they <i>may truncate your status line output</i> \u2014 so the rightmost token is the one you can afford to lose, and the alarms are now the rightmost token. A long MCP error can eat them, and you would not know one was there to lose. That trade was put in exactly those terms and taken: the row now leads with the session and the repo in the overwhelming majority of ticks where nothing is wrong, instead of leading with harbor&#39;s complaints. Every harbor-state token is also <b>dark grey</b> now (<code>SGR 90</code>, not the <code>SGR 2</code> faint attribute several terminals ignore) \u2014 de-emphasised rather than removed.</p>\n'

printf '<table><tr><th></th><th>Token</th><th>Zone</th><th>What it means</th><th>Source</th><th>Live now</th></tr>\n'

_slrow '' 'Opus 5 1M' 'row 1' 'Model, and the context window size it is running with. Derived from <code>context_window.context_window_size</code>, not read off the display name — a name without the parenthetical would otherwise state no size at all, and one with it would state it twice.' 'stdin payload' 'per session'
_slrow '' 'MAX / xhigh / medium' 'row 1' 'Reasoning effort, reflecting mid-session <code>/effort</code> changes. Upper-cased at <code>xhigh</code> and <code>max</code> because those are a price, not a preference: the same session costs a multiple of itself between levels. Absent when the model has no effort parameter.' 'stdin payload' 'per session'
_slrow '' 'fast / no-think' 'row 1' 'The exceptions only — <code>fast</code> when fast mode is on, <code>no-think</code> when extended thinking is <i>off</i>. Their ordinary states render nothing, because a token that never changes is a column spent to say nothing.' 'stdin payload' 'per session'
_slrow '' 'ctx 38%' 'row 1' 'Share of the context window used. A percentage only — the model tile already gave the denominator, so an absolute count would be the same fact spelled twice (cut 2026-08-23). The <code>&gt;200k</code> threshold token that used to sit beside it was cut on 2026-08-24: the harness still reports <code>exceeds_200k_tokens</code> and the row deliberately does not read it. Both cuts are operator taste calls about their own status row, and both are asserted in the suite so they do not come back helpfully.' 'stdin payload' 'per session'
_slrow '' 'cache 94%' 'row 1' 'How much of the live context came from cache instead of being re-sent. Absent before the first API call and again after every <code>/compact</code> — where <code>cache 0%</code> would be a confident wrong number at the exact moment the context was rebuilt. Dropped below 120 columns.' 'stdin payload' 'per session'
_slrow '' '$2.14' 'row 1' 'Estimated session cost, client-side. Resets to zero on <code>/clear</code>. There is deliberately no burn rate: it was cut as noise, not because it could not be computed.' 'stdin payload' 'per session'
_slrow '' '5h 12% ·in 2h10m' 'row 1' 'Rate-limit window used, and when it refills. The countdown is inside the colour span so a red window reads as one unit. A reset in the past renders nothing rather than <code>0m</code>, which would read as "about to refill" when it may only mean the payload is old.' 'stdin payload' 'per session'
_slrow '' '7d 47% ·in 1d22h' 'row 1' 'The weekly window, same rules. Dropped below 80 columns.' 'stdin payload' 'per session'

_slrow '' 'STALE runtime3·floor4' 'alarm' 'The installed floor is not the floor this repo built — the tokens are <code>renew-check.sh</code>&#39;s own and name which installer is how many <code>bin/</code>+<code>hooks/</code> commits behind. A merged, tested, contract-documented guard that gates nothing on this machine. Remedy: <code>sh bin/deploy.sh --apply --only runtime,floor --live</code>, from your own terminal: deploy runs them in that order, behind one snapshot.' "$PCFG/.helm-renew" "$(_slv "$PCFG/.helm-renew")" alarm
_slrow '' 'JUDGE crit 1 ·16h' 'alarm' 'The daily ledger judge&#39;s worst finding, <b>with its age</b>. New on the row in 2026-08: the box carried <code>crit=1 warn=62</code> here while the row showed a green pin, because nothing read the verdict. The age is not optional — the crit that prompted this rested on a single record from three days earlier whose remedy had already run, and an undated verdict cannot be falsified. <code>worst=ok</code> renders nothing.' "$PCFG/.helm-judge" "$(_slv "$PCFG/.helm-judge")" alarm
_slrow '' 'PIN DRIFT / UNPINNED' 'alarm' 'The <code>permissions.deny</code> list no longer hashes to what it was pinned at, or was never pinned. Fires alongside the pushpin — one binary in two channels, deliberately, because an unpinned floor must not depend on noticing a colour. Since the 2026-08-24 recolour the pushpin is dark grey in <i>both</i> states, so <b>this word is the whole signal</b> and the icon now only tells you the check ran. That is exactly why the redundancy was built: the channel that survived a design change is the one that was never carrying meaning in a colour.' 'live sha256, every tick' 'computed live'
_slrow '' 'SHARED TREE 2' 'alarm' 'Another live session is writing <i>this</i> working tree. The measured failure: three files reverted to HEAD mid-suite, <code>git status</code> clean, no stash. An alarm rather than a sub-count because the ambient zone is dropped on a narrow terminal and this is not a fact you can afford to lose.' "$PCFG/.helm-peers/" 'computed live'
_slrow '' 'DRIFT 1' 'alarm' 'Repos whose scaffold manifest no longer matches. Counts <code>drift.status</code>, the verdict — never <code>drift.total</code>, which is the manifest <i>size</i> and made the alarm unable to reach zero while any repo was scaffolded. Known limit, asserted so it stays known: <code>no-manifest</code> does not count, so an unmeasured repo reads like a clean one.' 'fleet-snapshot.json' 'see Fleet panel'
_slrow '' 'WATCH 4/5' 'alarm' 'A scheduled job is installed and not loaded. Every cached number on this row freezes at its last value if its job stops, and keeps rendering as current.' "$PCFG/.helm-watch" "$(_slv "$PCFG/.helm-watch")" alarm
_slrow '' 'SWEEP 12 ·2h' 'alarm' 'Leftovers need a person, <b>with the age of the count</b>. Due when any row is RISK — work that exists in one place only, like uncommitted changes in a finished worktree or a branch on no remote and in no PR — or when enough rows wait on a decision. The writer decides <code>due</code>; the row renders it. Recorded at 09:00 and 16:00 by <code>harbor-clean.sh --record</code> inside the fleet refresher; it counts and never deletes. <code>skills/housekeeping</code> turns the rows into one batch.' "$PCFG/.helm-sweep" "$(_slv "$PCFG/.helm-sweep")" alarm
_slrow '' 'ovr 3' 'alarm' 'Guard overrides — the operator saying a rule is wrong with their hands, which the constitution calls a defect in the rule. This replaced <code>blocks N</code>, a lifetime counter no action could move; the removal is asserted in the suite so it is not helpfully restored.' 'guard-decisions.json' "$( [ -f "$PCACHE/guard-decisions.json" ] && jq -r '"blocks \(.blocks // 0), overrides \(.overrides // 0)"' "$PCACHE/guard-decisions.json" 2>/dev/null | esc || printf 'not written' )"
_slrow '' 'props 2' 'alarm' 'Proposal packets waiting for a human. Yellow, not red — a queued packet is the system working as designed.' "$PCFG/.helm-props" "$(_slv "$PCFG/.helm-props")"

_slrow '' 'a3d7bc <span class="z">·</span>' 'ground' 'Which terminal this is. <b>Dim means unnamed</b> — a session-id stem, and <code>/rename</code> replaces it with a bright name. An <code>--agent</code> session shows <code>@agent-name</code> instead.' 'stdin payload' 'per session'
_slrow '' 'harbor main wt ~3' 'ground' 'Directory, branch, and the count of dirty files <i>here</i> — <code>-uall</code>, so untracked files count, because that is how a stray scratch file reaches a commit. <code>wt</code> marks a linked worktree. Zero renders nothing: absence is the clean signal.' 'git, at render time' 'computed live'
_slrow '' '#292 approved' 'ground' 'The open PR for this branch and its review state — green approved, red changes, dim pending or draft. A GitLab merge request takes <code>!</code> instead of <code>#</code>. On the row because this box has merged past its own review gate once, over two real findings including a crash.' 'stdin payload' 'per session'
_slrow '' 'PIN, as a word only' 'alarm' 'The floor pin asks one question: do <code>permissions.deny</code> plus the two lock flags still hash to <code>.helm-floor-teeth</code>? Computed <b>live</b> every tick \u2014 4ms measured with <code>sha256sum</code> \u2014 because a cached all-clear can go stale and a stale all-clear is the worst number on the page. <b>It renders nothing when the pin holds.</b> It was <code>floor\u2713</code> until 2026-08-23 (two columns from <code>renew \u2026 floor4</code>, which made one surface look like it contradicted the other), then the 📌 pushpin, and the pushpin was cut on 2026-08-24: the recolour that same day left it grey in both states, so it answered its own question in neither. See <code>PIN DRIFT / UNPINNED</code> below \u2014 that word is now the only channel this binary has.' 'live sha256, every tick' 'computed live'

_slrow '⛵' 'ships' 'ambient' 'Live Claude Code sessions on this machine, and how many are busy. Counted from Claude Code&#39;s own registry, which sees a session from the moment it starts — the previous token required a written peer record and rendered <i>nothing</i> with five sessions open. Status is counted, never echoed: registry fields are peer-supplied and a tally is immune to that where a rendered string is not. Never zero; a session reporting no sessions is visibly false.' "$PCFG/sessions/" "$(ls "$PCFG"/sessions/*.json 2>/dev/null | wc -l | tr -d ' ') registered"
_slrow '⚓' 'berths' 'ambient' 'Repos in the fleet snapshot, with dirty and unsynced sub-counts. Sub-counts are dropped below 100 columns; the anchor count survives to 80.' 'fleet-snapshot.json' "$( [ -f "$FSNAP" ] && jq -r 'if type=="array" then "\(length) repos" else "wrong shape" end' "$FSNAP" 2>/dev/null | esc || printf 'not written' )"
_slrow '📡' 'watch' 'ambient' 'Harbor&#39;s scheduled jobs, loaded over installed. This is the tile that says whether the reporters behind every cached number above are alive — alerting that fires only on failure is silent over a dead feed. Absent when the check has never run, never <code>📡0</code>.' "$PCFG/.helm-watch" "$(_slv "$PCFG/.helm-watch")"
_slrow '🧹' 'sweep' 'ambient' 'Rows that need a person: branches and worktrees whose PR merged, branches left on GitHub, green PRs waiting, issues that say they are done, strays. Zero renders nothing. <code>🧹4?</code> is a lower bound — a repo could not be read, or the count is over 26h old — never a clean count.' "$PCFG/.helm-sweep" "$(_slv "$PCFG/.helm-sweep")"
_slrow '' '4m' 'ambient' 'Age of the fleet snapshot, dating the cached tiles beside it. Past 15 minutes the whole tile degrades to <code>fleet: unknown</code> rather than showing a stale count.' 'cache mtime' 'computed live'

printf '</table>\n'
printf '<p class="none"><b>Icons are emoji-presentation only, and there are four.</b> The operator reported seeing nothing but the anchor, and the cause is mechanical: <code>east_asian_width</code> is <b>W</b> for ⚓ and ⛵ and <b>N</b> for ✎, ⇅ and the bare ⚠ — a narrow text-presentation dingbat is not drawn from the colour-emoji font, so it renders thin or not at all. Every icon here is verified W and the width tiers count it as two columns. Icons name <i>nouns</i>; every alarm is a word, because "⚓2 ⚠1" was once read as "two anchors and one hat".</p>\n'
printf '<p class="none"><b>Width tiers.</b> Claude Code exports <code>COLUMNS</code> (it captures this script&#39;s output, so <code>tput cols</code> cannot work). 120+ renders everything; 100–119 drops the cache share and the watch tile; 80–99 also drops the sub-counts and keeps the anchor; below 80 the ambient zone goes entirely and the alarms, identity and pin remain. An <i>unreadable</i> width takes the full render — dropping fields on a wide terminal is the failure nobody would report.</p>\n'
printf '<p class="none"><b>Subagent rows</b> come from <code>subagent-glyph.sh</code> via <code>subagentStatusLine</code>, one per live agent: <code>name │ effort │ ctx%% │ age │ directory</code>. It uses the <b>same two marks as the main row</b>, because the two are read in one glance — every field there is a different fact, so every join is a bar. Until 2026-08-24 it used a spaced middot, the one form the main row dropped; the mark is now duplicated in two sibling renderers that cannot share a library, so the suite asserts both emit it and neither emits a spaced middot. That assertion is what keeps the copy honest. A directory claimed by more than one agent is marked <code>SHARED</code> — the collision behind both the shared-scratchpad incident (12 arms, 51 operations on one filename) and the reverted-worktree one, each previously diagnosed from transcripts after the damage. The percentage needs <i>both</i> <code>tokenCount</code> and <code>contextWindowSize</code>: 186k reads as 93%% on a 200k window and 19%% on a 1M one, so an assumed denominator would be wrong by 5x in the direction that looks like trouble.</p>\n'
printf '</section>\n'

# ── the fleet tile (E2) ─────────────────────────────────────────────────────
# Shells nothing: it reads the cache fleet-snapshot-refresh.sh already writes,
# which is the ticket's own rule — a page must never invoke the orchestrator at
# render time. FOUR FIELDS AND NO OTHERS: the cache carries each repo's whole
# memory store inline, bodies included, and none of that belongs on a page.
printf '<section><h2>Fleet</h2>\n'
if [ -f "$FSNAP" ]; then
  # ASK THE SHAPE QUESTION SEPARATELY FROM THE CONTENT QUESTION. Rendering rows
  # and then treating "no rows" as "not an array" collapses two states that mean
  # opposite things: the valid empty snapshot a box with nothing scaffolded
  # writes, and a cache that is the wrong shape entirely. pulse.sh already keeps
  # them apart; this tile did not, and told a clean machine its cache was broken.
  _ftype="$(jq -r 'type' "$FSNAP" 2>/dev/null || printf '?')"
  _frows="$(jq -r 'if type == "array" then .[] | [(.descriptor.name // "?"), ((.hooks // "-") | tostring), ((.status.ahead // 0) | tostring), ((.drift.status // "-") | tostring)] | @tsv else empty end' "$FSNAP" 2>/dev/null || printf '')"
  if [ "$_ftype" != "array" ]; then
    printf '<p class="none">The snapshot is not the array the refresher writes — <code>fleet-snapshot-refresh.sh</code> is what repairs it.</p>\n'
  elif [ -z "$_frows" ]; then
    printf '<p class="none">The snapshot lists no repos. That is a valid fleet, not a broken cache.</p>\n'
  elif [ -n "$_frows" ]; then
    printf '<table><tr><th>repo</th><th>hooks</th><th>ahead</th><th>tree</th></tr>\n'
    printf '%s\n' "$_frows" | while IFS='	' read -r _n _h _a _d; do
      _cls="inv"; [ "$_h" = "missing" ] && _cls="amb"
      printf '<tr><td>%s</td><td class="%s">%s</td><td class="n">%s</td><td class="inv">%s</td></tr>\n' \
        "$(printf '%s' "$_n" | esc)" "$_cls" "$(printf '%s' "$_h" | esc)" \
        "$(printf '%s' "$_a" | esc)" "$(printf '%s' "$_d" | esc)"
    done
    printf '</table>\n'
    printf '<p class="none">Governance hooks are the column that means something is broken; an unpushed commit or a dirty tree is work in progress, which is why neither raises a verdict in <code>pulse.sh</code>.</p>\n'
  fi
else
  printf '<p class="none">No fleet snapshot on this machine. <code>launchd/com.harbor.fleet-snapshot.plist</code> is what writes it.</p>\n'
fi
printf '</section>\n'

printf '<section><h2>Counted from the repo</h2>\n'
_mx="$n_rules"; for _v in "$n_skills" "$n_contracts" "$n_guards" "$n_cases"; do
  [ "$_v" -gt "$_mx" ] 2>/dev/null && _mx="$_v"; done
bar "lint rules"            "$n_rules"     "$_mx"
bar "vendored skills"       "$n_skills"    "$_mx"
bar "marker fixtures"       "$n_cases"     "$_mx"
bar "frozen contracts"      "$n_contracts" "$_mx"
bar "floor guards (built)"  "$n_guards"    "$_mx"
printf '</section>\n'

printf '<section><h2>Suite assertions</h2>\n'
_ax="$a_floor"
bar "floor-test"     "$a_floor"  "$_ax"
bar "normalize-test" "$a_norm"   "$_ax"
bar "marker-test"    "$a_marker" "$_ax"
printf '<h2 style="margin-top:18px">floor-test over time</h2>'
spark
printf '</section>\n'

printf '<section><h2>Tickets</h2>\n'
if [ "$tix_state" = "ok" ]; then
  _tt=$(( t_open + t_closed )); [ "$_tt" -gt 0 ] || _tt=1
  bar "open"            "$t_open"   "$_tt"
  bar "closed"          "$t_closed" "$_tt"
  bar "open · security" "$t_sec"    "$_tt"
  bar "open · bug"      "$t_bug"    "$_tt"
else
  printf '<p class="none"><b>unavailable</b> — <code>gh</code> is missing or could not reach GitHub. Rendering 0 here would read as "no open tickets", which is why this panel refuses to draw.</p>\n'
fi
printf '</section>\n'

# ── the always-on budget, spent vs projected ────────────────────────────────
# Two numbers, never one: the ceiling binds what is SPENT, and the projection is
# what lands if memory injection ships. Conflating them is what made this tool's
# own source cry wolf on 2026-07-31.
printf '<section><h2>Always-on budget</h2>\n'
if [ -n "${BUD_SPENT:-}" ]; then
  bar "spent every session" "$BUD_SPENT" "$BUD_CEIL"
  bar "projected if D lands" "$BUD_PROJ" "$BUD_CEIL"
  printf '<div class="row"><span class="k">ceiling</span><span class="t"><i style="width:100%%;opacity:.35"></i></span><span class="v">%s</span></div>\n' \
    "$(printf '%s' "$BUD_CEIL" | esc)"
  printf '<p class="none">Bytes before your first word, every session. The ceiling binds the <b>spent</b> line; the projection is what memory injection would add and is the argument for deciding before it lands, not after.</p>\n'
else
  printf '<p class="none"><b>unavailable</b> — context-budget.sh produced no parseable totals.</p>\n'
fi
printf '</section>\n'

# ── the inventory: what this box actually carries ───────────────────────────
# Collapsed by default with <details>, so the page stays scannable and the lists
# are one click away rather than a wall. No JS: <details> is the whole mechanism,
# which keeps the page working with scripting off and inside a strict CSP.
printf '<section><h2>Inventory</h2>\n'

# SKILLS — ambient ones are paid for in every session; invoked-only ones are free
# until you type their name, which is verifiable: an invoked-only skill does not
# appear in the model's skill listing at all.
printf '<details open><summary>skills — %s ambient, %s invoked-only <b>(%s B ambient)</b></summary>\n' \
  "$(printf '%s' "$SK_AMB_N" | esc)" "$(printf '%s' "$SK_INV_N" | esc)" "$(printf '%s' "$SK_AMB_B" | esc)"
if [ -n "${SK_ROWS:-}" ]; then
  printf '<table><tr><th>skill</th><th>tier</th><th>desc B</th></tr>\n'
  printf '%s\n' "$SK_ROWS" | while IFS="$(printf '\t')" read -r _sb _st _sn; do
    [ -n "${_sn:-}" ] || continue
    printf '<tr><td>%s</td><td class="%s">%s</td><td class="n">%s</td></tr>\n' \
      "$(printf '%s' "$_sn" | esc)" \
      "$([ "$_st" = AMBIENT ] && echo 'amb' || echo 'inv')" \
      "$(printf '%s' "$_st" | esc)" "$(printf '%s' "$_sb" | esc)"
  done
  printf '</table>\n'
  printf '<p class="none">Ambient = the description is in every session and the model may select it unprompted. Invoked-only = free until you type its name. A skill that carries a <b>prohibition</b> belongs ambient even if it is rarely used — an unloaded rule is not a rule.</p>\n'
else
  printf '<p class="none"><b>unavailable</b> — no skills directory found.</p>\n'
fi
printf '</details>\n'

# HARBOR VERBS — read from the contract, which lint CLI1 keeps equal to bin/harbor
printf '<details><summary>harbor verbs — the L0 command surface</summary>\n'
_verbs="$(grep -E '^\| `harbor [a-z-]+` \| `[a-z0-9.-]+\.sh` \|' "$ROOT/CONTRACTS/cli.md" 2>/dev/null \
          | sed -E 's/^\| `harbor ([a-z-]+)` \| `([a-z0-9.-]+)` \| ([a-z]+) \| (.*) \|$/\1\t\2\t\3\t\4/')"
if [ -n "$_verbs" ]; then
  printf '<table><tr><th>verb</th><th>script</th><th>--json</th><th>what it does</th></tr>\n'
  printf '%s\n' "$_verbs" | while IFS="$(printf '\t')" read -r _v _s _j _d; do
    [ -n "${_v:-}" ] || continue
    printf '<tr><td><code>harbor %s</code></td><td class="n">%s</td><td>%s</td><td>%s</td></tr>\n' \
      "$(printf '%s' "$_v" | esc)" "$(printf '%s' "$_s" | esc)" \
      "$([ "$_j" = yes ] && echo '&#10003;' || echo '')" "$(printf '%s' "$_d" | esc)"
  done
  printf '</table>\n'
else
  printf '<p class="none"><b>unavailable</b> — CONTRACTS/cli.md carries no parseable verb table.</p>\n'
fi
printf '</details>\n'

# CONTRACTS and LINT RULES — the governance surface, derived from the tools
printf '<details><summary>frozen contracts</summary><table><tr><th>seam</th></tr>\n'
for _c in "$ROOT"/CONTRACTS/*.md; do
  [ -f "$_c" ] || continue
  case "$(basename "$_c")" in README.md) continue ;; esac
  printf '<tr><td><code>%s</code></td></tr>\n' "$(basename "$_c" | esc)"
done
printf '</table></details>\n'

printf '<details><summary>lint rules — run on every commit and in CI</summary><table><tr><th>rule</th></tr>\n'
sh "$ROOT/bin/lint-conventions.sh" --list 2>/dev/null | sed 's/^  *//' | while IFS= read -r _r; do
  [ -n "$_r" ] || continue
  printf '<tr><td>%s</td></tr>\n' "$(printf '%s' "$_r" | esc)"
done
printf '</table></details>\n'
printf '</section>\n'

printf '<section><h2>Document freshness — "still right?"</h2>\n'
if [ -n "$FRESH" ]; then
  printf '%s\n' "$FRESH" | while IFS="$(printf '\t')" read -r _f _a _t; do
    [ -n "${_t:-}" ] || continue
    bar "$_f" "$_a" "$_t"
  done
  printf '<p class="none">Bar is age against that document type&#39;s threshold. Full bar = past it. Staleness is a priority signal, not a failure. Showing the %s highest-priority of %s scored documents — the rest are further from their threshold, not omitted for space.</p>\n' \
    "$FRESH_SHOW" "$(printf '%s' "$FRESH_N" | esc)"
else
  printf '<p class="none"><b>unavailable</b> — freshness.sh produced no rows.</p>\n'
fi
printf '</section>\n'

printf '</div>\n'
printf '<footer>Local file, no network at view time. Regenerate: <code>sh bin/dashboard-gen.sh</code>. Numbers live in STATUS.md; this page is a view, not a source.</footer>\n'
}

case "$MODE" in
  --stdout) render ;;
  *)
    mkdir -p "$ROOT/build"
    _t="$OUT.tmp.$$"
    render > "$_t"
    if [ ! -s "$_t" ]; then
      rm -f "$_t"; log_fail "rendered an empty page, so $OUT is left unchanged"; log_nofix "the render errors above"; log_end || :; exit 1
    fi
    mv "$_t" "$OUT"
    log_ok "wrote $OUT"
    # open on macOS, xdg-open on Linux, wslview on WSL2 (harbor#618); with none the page is still written, and the note says where.
    case "$MODE" in --open)
      if command -v open >/dev/null 2>&1; then open "$OUT"
      elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$OUT" >/dev/null 2>&1 || log_note "xdg-open could not open $OUT"
      elif command -v wslview >/dev/null 2>&1; then wslview "$OUT" >/dev/null 2>&1 || log_note "wslview could not open $OUT"
      else log_note "no opener (open, xdg-open, wslview) on PATH: the page is at $OUT"; fi ;; esac ;;
esac
log_end
