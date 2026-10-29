#!/usr/bin/env sh
# L0-5 (harbor#59): the statusline's row 1, golden output. A renderer always prints SOMETHING, so a
# regression is invisible by eye. Parts: .fleet (row-2 fleet, pin, writer, verdicts hook), .row2
# (row-2 tiles and tiers), .subagent (status-subagent-glyph.sh). `--dash` runs the subjects under dash.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/../../hooks/statusline-fixture.sh"

t_section "row 1: fields present"
O="$(row1 '{"model":{"display_name":"Opus 5"},'"$WS"',"context_window":{"used_percentage":26},"cost":{"total_cost_usd":1.3}}')"
t_has "the model name" "$O" "Opus 5"
t_has "the context share" "$O" "ctx 26%"
t_has "money at two decimals" "$O" '$1.30'

t_section "row 1: ABSENT fields occupy zero columns"
O="$(row1 '{"model":{"display_name":"Opus 5"},'"$WS"'}')"
t_eq "a fresh session renders the model alone" "Opus 5" "$O"
t_hasnt "no ctx placeholder" "$O" 'ctx'
t_hasnt "no money placeholder" "$O" '$'
t_hasnt "no dash placeholder" "$O" '--'
t_hasnt "no zero-percent placeholder" "$O" '0%'

t_section "row 1: a REAL zero renders, an ABSENT value does not"
O="$(row1 '{"model":{"display_name":"O"},'"$WS"',"context_window":{"used_percentage":0},"cost":{"total_cost_usd":0}}')"
t_has "a measured 0% renders" "$O" "ctx 0%"
t_has "a measured \$0 renders" "$O" '$0.00'

t_section "row 1: rate_limits are UNROUNDED FLOATS (the ramp that never fired)"
# `[ 41.7 -ge 85 ]` is an ERROR, not false, and `2>/dev/null &&` swallowed it: assert rounding AND colour.
O="$(run '{"model":{"display_name":"O"},'"$WS"',"rate_limits":{"five_hour":{"used_percentage":91.4},"seven_day":{"used_percentage":41.699999999999996}}}')"
t_has "5h float rounded" "$(printf '%s' "$O" | plain)" "5h 91%"
t_has "7d float rounded" "$(printf '%s' "$O" | plain)" "7d 42%"
t_has "5h at 91.4 is RED" "$O" "${ESC}[31m5h 91%"
O2="$(run '{"model":{"display_name":"O"},'"$WS"',"rate_limits":{"five_hour":{"used_percentage":12.3}}}' | head -1)"
t_hasnt "12.3% is not red" "$O2" "${ESC}[31m"
t_hasnt "12.3% is not yellow" "$O2" "${ESC}[33m"
t_has "75% sits in the YELLOW band" "$(run '{"model":{"display_name":"O"},'"$WS"',"rate_limits":{"five_hour":{"used_percentage":75}}}' | head -1)" "${ESC}[33m5h 75%"

t_section "row 1: the reset countdown (harbor#84)"
rl() { runat '{"model":{"display_name":"O"},'"$WS"',"rate_limits":{"five_hour":'"$1"'}}' | head -1; }  # <five_hour body>
t_has "hours and minutes" "$(rl '{"used_percentage":91.4,"resets_at":1785608040}' | plain)" "5h 91% ·in 2h14m"
t_has "a sub-hour countdown drops the hours" "$(rl '{"used_percentage":96,"resets_at":1785601380}' | plain)" "5h 96% ·in 23m"
t_has "under a minute is <1m, never 0m" "$(rl '{"used_percentage":99,"resets_at":1785600030}' | plain)" "5h 99% ·in <1m"
O="$(rl '{"used_percentage":91.4,"resets_at":1785599500}' | plain)"
t_hasnt "a past resets_at renders no countdown" "$O" '·'
t_has "the percentage survives the dropped countdown" "$O" "5h 91%"
O="$(rl '{"used_percentage":91.4}' | plain)"
t_hasnt "an absent resets_at renders no placeholder" "$O" '·'
t_has "5h survives an absent resets_at" "$O" "5h 91%"
t_has "the countdown sits inside the red span" "$(rl '{"used_percentage":91.4,"resets_at":1785608040}')" "${ESC}[31m5h 91% ·in 2h14m${ESC}"
O="$(runat '{"model":{"display_name":"O"},'"$WS"',"rate_limits":{"seven_day":{"used_percentage":41.7,"resets_at":1785960000}}}' | head -1 | plain)"
t_has "7d counts down in days and hours" "$O" "7d 42% ·in 4d04h"

t_section "row 1: vanishes entirely without stdin (never a blank line)"
O="$(printf '' | CLAUDE_CONFIG_DIR="$CFG" HARBOR_SCOPE_CACHE_DIR="$CFG/cache" "$SH" "$SRC/status-fleet-glyph.sh" 2>/dev/null)"
t_eq "no blank line with no stdin" "$(printf '%s\n' "$O" | wc -l | tr -d ' ')" "$(printf '%s\n' "$O" | grep -c .)"
t_hasnt "no stdin: no SESSION row (no model, no ctx)" "$(printf "%s\n" "$O" | head -1 | plain)" "ctx"

t_section "row 1: the CACHE share"
# cache_read / (input + cache_read + cache_creation): the share served from cache.
CU='"context_window":{"used_percentage":26,"current_usage":{"input_tokens":1000,"cache_read_input_tokens":7000,"cache_creation_input_tokens":2000}}'
t_has "the cache share" "$(row1 '{"model":{"display_name":"O"},'"$WS"','"$CU"'}')" "cache 70%"
# current_usage is NULL before the first API call and after /compact: never "cache 0%" there.
O="$(row1 '{"model":{"display_name":"O"},'"$WS"',"context_window":{"used_percentage":26,"current_usage":null}}')"
t_hasnt "a null current_usage renders no cache column" "$O" 'cache'
t_has "the context share survives a null current_usage" "$O" "ctx 26%"
t_hasnt "an absent current_usage renders no cache column" "$(row1 '{"model":{"display_name":"O"},'"$WS"',"context_window":{"used_percentage":26}}')" 'cache'
t_has "a measured 0% cache renders" "$(row1 '{"model":{"display_name":"O"},'"$WS"',"context_window":{"current_usage":{"input_tokens":1000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}')" "cache 0%"
t_hasnt "zero total tokens is no column, not a division" "$(row1 '{"model":{"display_name":"O"},'"$WS"',"context_window":{"current_usage":{"input_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}')" 'cache'

t_section "the separator grammar: two marks, and NO double space anywhere"
# Two spaces are meaningless now, so a token appended with the old double-gap idiom fails here.
OG="$(gram)"
t_hasnt "no double space on either row" "$OG" '  '
t_has "the boundary mark is present" "$OG" ' │ '
t_has "the sub-fact mark is present" "$OG" ' ·in '
t_hasnt "a middot never does a boundary job" "$OG" ' · '
t_eq "no row ends in whitespace" 0 "$(printf '%s\n' "$OG" | grep -c ' $')"

t_section "the separator grammar holds on every row, and PLACE and BOX are golden with CI live"
printf '{"at":%s,"repos":[{"repo":"o/r","runners":4,"left":2,"eta":%s}]}\n' "$NOW" "$((NOW + 300))" > "$CFG/cache/ci-queue.json"
printf '{"at":%s,"runner":"self-hosted","fallback":true,"percent":100,"unread":false}\n' "$NOW" > "$CFG/cache/runner-switch.json"
OG="$(gram)"
t_eq "three rows: SESSION, PLACE, BOX (pinned, so no YOU)" 3 "$(printf '%s\n' "$OG" | wc -l | tr -d ' ')"
t_eq "PLACE, golden" "abc123 │ notrepo │ ⛵1" "$(printf "%s\n" "$OG" | sed -n 2p)"
t_eq "BOX is CI then the fleet, golden" "⏳2 ·~5m │ CI→local 100% │ ⚓1 ·AGE ago" "$(printf "%s\n" "$OG" | sed -n 3p | sed "s/·[0-9]*[sm] ago$/·AGE ago/")"
t_hasnt "no double space on any of the three rows" "$OG" '  '
t_eq "no row ends in whitespace" 0 "$(printf '%s\n' "$OG" | grep -c ' $')"
rm -f "$CFG/cache/ci-queue.json" "$CFG/cache/runner-switch.json"

t_section "row 1: the model tile STATES THE WINDOW SIZE, once"
O="$(row1 '{"model":{"display_name":"Opus 5 (1M context)"},"context_window":{"context_window_size":1000000,"used_percentage":38},'"$WS"'}')"
t_eq "the size comes from the FIELD and replaces the parenthetical" yes "$(starts "$O" "Opus 5 1M")"
t_eq "the window size prints once" 1 "$(printf '%s' "$O" | grep -o '1M' | wc -l | tr -d ' ')"
t_hasnt "the display_name parenthetical is gone" "$O" 'context'
t_eq "200000 renders as 200k" yes \
  "$(starts "$(row1 '{"model":{"display_name":"Sonnet 5"},"context_window":{"context_window_size":200000,"used_percentage":10},'"$WS"'}')" "Sonnet 5 200k")"
t_eq "an absent size invents none" "Opus 5" "$(row1 '{"model":{"display_name":"Opus 5"},'"$WS"'}')"
# The absolute token count stays gone (operator decision 2026-08-23).
t_hasnt "no absolute token count on row 1" "$(row1 '{"model":{"display_name":"Opus 5"},"context_window":{"context_window_size":1000000,"used_percentage":38,"total_input_tokens":384000},'"$WS"'}')" '384'

t_section "row 1: effort, upper-cased when it is expensive"
t_has "max effort, upper-cased" "$(row1 '{"model":{"display_name":"Opus 5"},"effort":{"level":"max"},'"$WS"'}')" "MAX"
t_has "xhigh effort, upper-cased" "$(row1 '{"model":{"display_name":"Opus 5"},"effort":{"level":"xhigh"},'"$WS"'}')" "XHIGH"
O="$(row1 '{"model":{"display_name":"Opus 5"},"effort":{"level":"medium"},'"$WS"'}')"
t_has "an ordinary effort renders lower-cased" "$O" "medium"
t_hasnt "an ordinary effort does not shout" "$O" 'MEDIUM'
t_eq "an absent effort occupies zero columns" "Opus 5" "$(row1 '{"model":{"display_name":"Opus 5"},'"$WS"'}')"

t_section "row 1: the exceptions only: fast, no-think"
O="$(row1 '{"model":{"display_name":"Opus 5"},"fast_mode":true,"thinking":{"enabled":true},'"$WS"'}')"
t_has "fast mode renders when on" "$O" 'fast'
t_hasnt "thinking ENABLED renders nothing" "$O" 'think'
O="$(row1 '{"model":{"display_name":"Opus 5"},"fast_mode":false,"thinking":{"enabled":false},'"$WS"'}')"
t_has "thinking DISABLED renders" "$O" "no-think"
t_hasnt "fast mode off renders nothing" "$O" 'fast'
# `>200k` is cut (operator decision 2026-08-24), asserted with the field TRUE.
O="$(row1 '{"model":{"display_name":"Opus 5"},"context_window":{"used_percentage":22},"exceeds_200k_tokens":true,'"$WS"'}')"
t_hasnt ">200k does not render even when the field is true" "$O" '200k'
t_has "the context share survives the cut threshold token" "$O" "ctx 22%"
t_hasnt "under the threshold renders nothing" "$(row1 '{"model":{"display_name":"Opus 5"},"context_window":{"used_percentage":22},"exceeds_200k_tokens":false,'"$WS"'}')" '200k'

t_done
