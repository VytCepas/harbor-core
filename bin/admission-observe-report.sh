#!/usr/bin/env sh
# OBSERVE-1 (harbor#41) — read the guard-decision ledger.
#
# The writer is redacted by construction, so everything answerable here is
# answerable WITHOUT any command text ever having been stored. What it can
# answer, and why each question is the one that was stuck:
#
#   • which rules fire, and how often   — "top rules" was unanswerable
#   • flat vs argv, per rule            — DE-01's axis, unanswerable until now
#   • the override rate                 — the operator saying "this rule is
#                                         wrong" with their hands
#   • repeat blocks of the SAME shape   — the false-positive CANDIDATES, which
#                                         CONSTITUTION No.2 calls a defect and no
#                                         data source could previously identify.
#                                         Harbor's own probe and suite traffic is
#                                         dropped first (harbor#560), or its top
#                                         rows are the verifier, not the operator
#   • the tool census                   — a wiring-liveness check: a dispatch arm
#                                         that is dead shows up as a tool class
#                                         that never appears (P11-W1 was exactly
#                                         this, dead for months)
#   • wrapper denies                    — "the floor is broken" as distinct from
#                                         "a rule fired"; without it a jq outage
#                                         reads as the rules getting better
#   • shadow would-blocks, per rule     — what a rule refused while recording
#                                         instead of blocking (harbor#482): the
#                                         false-positive rate docs/explanation/admission-baseline.md needs is
#                                         read off real traffic, not guessed
#
# What it deliberately does NOT claim: which rule an operator overrode. Under
# HARBOR_ADMISSION_DISABLE every guard and the wrapper exit at line 2, so zero rules
# are evaluated and there is nothing to attribute. The blocks immediately
# preceding an `override` marker are reported as exactly that — "the last blocks
# before an override" — and never as the cause.
set -eu

HERE="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)" || HERE=""
# contracts/logging.md's line shape (harbor#771, converted by harbor#560). A copy with no library-log.sh
# beside it says so rather than crashing.
[ -n "$HERE" ] && [ -f "$HERE/library-log.sh" ] || {
  printf 'observe-report: library-log.sh is missing beside %s, so this copy cannot report; run the checkout copy: sh ~/port/harbor/bin/admission-observe-report.sh\n' "${HERE:-?}" >&2
  exit 1
}
. "$HERE/library-log.sh"
log_init observe-report
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
while [ "${CFG%/}" != "$CFG" ] && [ "$CFG" != "/" ]; do CFG="${CFG%/}"; done
OBS="$CFG/MEMORY/OBSERVABILITY"
MODE=all
PROBES=0

while [ $# -gt 0 ]; do
  case "$1" in
    --overrides) MODE=overrides ;;
    --rules)     MODE=rules ;;
    --gates)     MODE=gates ;;
    --fp)        MODE=fp ;;
    --advise)    MODE=advise ;;
    --shadow)    MODE=shadow ;;
    --reroute)   MODE=reroute ;;
    --confinement) MODE=confinement ;;
    --json)      MODE=json ;;
    --with-probes) PROBES=1 ;;
    -h|--help)
      echo "usage: admission-observe-report.sh [--rules|--gates|--overrides|--fp|--advise|--shadow|--reroute|--confinement|--json] [--with-probes]"
      echo "  --with-probes  keep harbor's own probe and suite traffic in the --fp candidates"
      echo "  (reads \$CLAUDE_CONFIG_DIR/MEMORY/OBSERVABILITY/*/guard-decisions.jsonl*)"
      exit 0 ;;
    *) echo "observe-report: unknown option $1" >&2; exit 1 ;;
  esac
  shift
done
# --json prints data on stdout, so its log (an error, if any) goes to stderr.
[ "$MODE" != json ] || LOG_FD=2
# stop <what failed, and where> <fix> — the report cannot be built.
stop() { log_fail "$1"; log_fix "$2"; log_end || :; exit 1; }

[ -d "$OBS" ] || stop "no ledger at $OBS — the floor writes one at SessionStart once installed" "sh ~/port/harbor/bin/deploy.sh --only floor --apply --live"

# Rotated generations first, so the series reads oldest → newest.
FILES="$(find "$OBS" -type f -name 'guard-decisions.jsonl*' 2>/dev/null | sort -r)"
[ -n "$FILES" ] || stop "the ledger is empty at $OBS" "start a session with the floor armed, then re-run: the SessionStart writer creates the sink"

command -v jq >/dev/null 2>&1 || stop "jq is required to read the ledger at $OBS" "$(pkg_hint jq)"

# One pass, tolerant of a torn tail: `fromjson?` drops an unparseable line
# rather than aborting the report. A ledger that cannot be read at all is the
# one failure mode that would make this whole ticket pointless.
REC="$(cat $FILES 2>/dev/null | jq -c 'fromjson? // empty' -R 2>/dev/null || true)"
[ -n "$REC" ] || stop "no parseable records in $OBS" "read the newest guard-decisions.jsonl by hand: a sink that is not JSONL means floor_log_decision refused every write"

# tr -d, and NOT a bare `grep -c`: BSD grep -c pads its count, the padding
# became a second printf argument, and printf then RE-RAN its whole format —
# the override line printed twice with different numbers.
n()   { _c="$(printf '%s\n' "$REC" | jq -r "select($1)|1" 2>/dev/null | grep -c '^1$' 2>/dev/null | tr -d ' \n')"
        case "$_c" in ''|*[!0-9]*) _c=0 ;; esac
        printf '%s' "$_c"; }

TOTAL=$(printf '%s\n' "$REC" | grep -c . 2>/dev/null | tr -d ' \n')
case "$TOTAL" in ''|*[!0-9]*) TOTAL=0 ;; esac
NBLOCK=$(n '.d=="block"'); NALLOW=$(n '.d=="allow"'); NDENY=$(n '.d=="deny"')
NGATE=$(n '.d=="gate"');   NOVR=$(n '.d=="override"'); NARM=$(n '.d=="armed"')

# `deny` USED to mean exactly one thing — admission-hook.sh could not reach a verdict,
# i.e. the floor is broken — and this file's header still promises that reading
# ("without it a jq outage reads as the rules getting better"). guard-cloud and
# guard-destroy then shipped with `deny` as their NORMAL verdict, so the alarm
# began firing on hundreds of correct decisions and a real wrapper failure became
# invisible inside the same bucket. Splitting on the guard token restores the
# discriminator: only `wrapper` denies mean the floor could not decide.
NWRAP=$(n '.d=="deny" and .g=="wrapper"')
NGDENY=$(n '.d=="deny" and .g!="wrapper"')
# Asks are counted separately and deliberately NOT folded into the deny total: an
# ask that reached a human is a gate working, and an ask in an unattended session
# auto-approves. The ledger cannot tell those two apart (nothing records whether a
# human answered), so the count is reported as the exposure it is, never as a stop.
NASK=$(n '.d=="ask"')
NADV=$(n '.d=="advise"')
# Shadow (harbor#482): a session record (g=session) is the boundary; every other
# shadow record is one rule that would have blocked one call.
NSHS=$(n '.d=="shadow" and .g=="session"')
NSHW=$(n '.d=="shadow" and .g!="session"')

if [ "$MODE" = json ]; then
  printf '%s\n' "$REC" | jq -s --argjson t "$TOTAL" '{
    records:$t,
    verdicts:(group_by(.d)|map({key:.[0].d,value:length})|from_entries),
    rules:(map(select(.d=="block"))|group_by(.r)|map({key:.[0].r,value:length})|from_entries),
    shadow:(map(select(.d=="shadow" and .g!="session"))|group_by(.r)|map({key:.[0].r,value:length})|from_entries),
    shapes:(map(select(.d=="block"))|group_by(.s)|map({key:.[0].s,value:length})|from_entries),
    tools:(group_by(.t)|map({key:.[0].t,value:length})|from_entries)
  }'
  exit 0
fi

show_rules() {
  log_head "rules that fired (blocks)"
  if [ "$NBLOCK" = 0 ]; then echo "  (no blocks recorded)"; return; fi
  # Deliberately blocks-only: a guard deny (cloud/destroy) is a DIFFERENT event —
  # the operator was asked or refused at a gate, not stopped by a rule — and mixing
  # the two would make "top rules" incomparable across the series. Guard denies get
  # their own section below, now that they carry a rule token at all.
  printf '%s\n' "$REC" | jq -r 'select(.d=="block")|"\(.r)\t\(.s)"' \
    | sort | uniq -c | sort -rn \
    | awk '{ printf "  %5d  %-32s %s\n", $1, $2, $3 }'
  # DE-01 made countable: one rule, two mechanisms.
  _tw="$(printf '%s\n' "$REC" | jq -r 'select(.d=="block")|"\(.r) \(.s)"' | sort -u \
         | awk '{c[$1]=c[$1]" "$2} END{for(r in c) if (split(c[r],a," ")>1) print "  " r ":" c[r]}')"
  [ -z "$_tw" ] || { echo "  (caught by BOTH mechanisms — the DE-01 axis:)"; printf '%s\n' "$_tw"; }
}

# AN ADVISE RECORD REACHED NO REPORT A HUMAN RUNS (harbor#303, FC-4): 178 B6 integrity advisories
# in six days sat in the ledger and in --json alone. An advisory refuses nothing, so it is counted
# here beside the verdicts and grouped by what raised it, with the day it last did.
show_advise() {
  log_head "advisories (advise records: nothing was refused)"
  if [ "$NADV" = 0 ]; then echo "  (no advisories recorded)"; return; fi
  # Tab-separated and tostring'd: a rule token with a space, or a ts that is not a string, must
  # neither split a group nor abort the pass and drop the rest (review #943).
  _adv_rows="$(printf '%s\n' "$REC" | jq -r 'select(.d=="advise")|"\(.g)/\(.r)\t\(.ts|tostring|.[0:10])"' 2>/dev/null \
    | awk -F'\t' '{ n[$1]++; if ($2 > last[$1]) last[$1] = $2 } END { for (k in n) printf "  %5d  %-36s last %s\n", n[k], k, last[k] }' \
    | sort -rn)"
  printf '%s\n' "$_adv_rows"
  case "$_adv_rows" in *" integrity/"*) echo "  integrity/* is B6 reporting instruction-surface drift: read it with \`harbor verify\`." ;; esac
}

show_gdeny() {
  log_head "gates that fired (cloud / destroy)"
  if [ "$NGDENY" = 0 ] && [ "$NASK" = 0 ]; then echo "  (no gate decisions recorded)"; return; fi
  printf '%s\n' "$REC" \
    | jq -r 'select((.d=="deny" and .g!="wrapper") or .d=="ask")|"\(.d)\t\(.g)\t\(.r)"' \
    | sort | uniq -c | sort -rn \
    | awk '{ printf "  %5d  %-5s %-9s %s\n", $1, $2, $3, $4 }'
  if [ "$NASK" != 0 ]; then
    log_warn "$NASK ask verdicts. An ask is a stop ONLY where a human answers it; in an unattended or subagent session it auto-approves (admission-cloud.sh:104). Nothing in the ledger records whether a human was present, so read this as EXPOSURE, not as a block."
    log_fix "CLOUD_POSTURE=deny / HARBOR_ADMISSION_DESTROY_POSTURE=deny in the settings.json env block escalate the soft tier to a real refusal"
  fi
}

# HARBOR'S OWN TRAFFIC IS DROPPED BEFORE RANKING (harbor#560). floor-verify fires known-blocked
# shapes through the real guards and the floor suite fires hundreds more, each a real block record
# under the live salt. On 2026-09-20 the six probe digests held the top six rows, 171-173 each,
# about 1,028 rows above the first operator candidate: the view built to show friction led with the
# one shape that is by construction not friction. The digests come from audit-triage.sh
# --exclusion-set, the derivation FC-5 already uses, so there is one spelling of it. Whatever it
# drops is counted on screen, and a derivation that fails is said out loud, never read as clean.
show_fp() {
  log_head "false-positive CANDIDATES"
  echo "  A shape refused repeatedly (block, deny or ask) is the operator re-hitting a wall."
  echo "  CONSTITUTION No.2: a false positive is a defect, not safety."
  # deny and ask are refusals too (harbor#319), the same set audit-triage.sh's FC-5 sweeps
  _fpall="$(printf '%s\n' "$REC" | jq -r 'select((.d=="block" or .d=="deny" or .d=="ask") and .h!="-")|"\(.h) \(.r)"' | sort | uniq -c | sort -rn)"
  _excl=""; _exst=skipped
  if [ "$PROBES" = 0 ] && printf '%s\n' "$_fpall" | awk '$1>1{f=1} END{exit !f}'; then
    if [ -n "$HERE" ] && [ -f "$HERE/audit-triage.sh" ] \
       && _excl="$(sh "$HERE/audit-triage.sh" --exclusion-set "$CFG" 2>/dev/null)"; then _exst=ok
    else _excl=""; _exst=failed; fi
  fi
  # One stream, the exclusion set first: `X <digest>` lines, then the `<n> <digest> <rule>` counts.
  _fpx="$({ printf '%s\n' "$_excl" | awk 'NF == 2 { print "X " $2 }'; printf '%s\n' "$_fpall"; })"
  _fp="$(printf '%s\n' "$_fpx" | awk '$1 == "X" { x[$2] = 1; next }
           ($2 in x) { next } $1 > 1 { printf "  %5d x  %-20s digest %s\n", $1, $3, $2 }')"
  [ -n "$_fp" ] && printf '%s\n' "$_fp" || echo "  (no command refused more than once)"
  case "$_exst" in
    ok)
      _xn="$(printf '%s\n' "$_fpx" | awk '$1 == "X" { x[$2] = 1; next }
               ($2 in x) { r += $1; d++ } END { printf "%d %d", r, d }')"
      if [ "${_xn% *}" = 0 ]; then
        echo "  (harbor's probe and suite digests were derived and none is in this ledger, so nothing was dropped —"
        echo "   either they never ran against it, or the salt changed after they did)"
      else
        echo "  (dropped ${_xn% *} block record(s) under ${_xn#* } digest(s): harbor's own probe and suite traffic — --with-probes shows them)"
      fi ;;
    failed)
      log_warn "harbor's own probe and suite traffic could NOT be separated (audit-triage.sh, admission-verify.sh, library-admission.sh or the salt was unreadable), so the rows above may be this box's own verifier"
      log_fix "sh $HERE/audit-triage.sh --exclusion-set $CFG   # names what it could not read" ;;
  esac
}

# SHADOW WOULD-BLOCKS (harbor#482). Under HARBOR_ADMISSION_SHADOW a rule records instead of
# blocking, so its rows are what it would have refused in sessions where nothing was
# routed around it. Per rule: would-blocks, distinct commands (digests), and how many
# of those came back. Whether each was a false positive is a person's call, and this
# is the population they make it on; docs/explanation/admission-baseline.md's per-rule column is read from here.
show_shadow() {
  log_head "shadow (would have blocked; recorded, not enforced)"
  if [ "$NSHS" = 0 ] && [ "$NSHW" = 0 ]; then
    echo "  (no shadow sessions recorded: the operator opens one with HARBOR_ADMISSION_SHADOW at launch)"
    return
  fi
  printf '  %d shadow session(s), %d would-block record(s)\n' "$NSHS" "$NSHW"
  [ "$NSHW" = 0 ] && return
  echo "  would-blocks  distinct  repeated  rule"
  printf '%s\n' "$REC" | jq -r 'select(.d=="shadow" and .g!="session")|"\(.g)/\(.r)\t\(.h)"' 2>/dev/null \
    | awk -F'\t' '{ n[$1]++; if (!(($1 FS $2) in seen)) { seen[$1 FS $2] = 1; d[$1]++ } else if ($2 != "-") { if (!(($1 FS $2) in rep)) { rep[$1 FS $2] = 1; r[$1]++ } } }
        END { for (k in n) printf "  %12d  %8d  %8d  %s\n", n[k], d[k], r[k], k }' \
    | sort -rn
}

# REROUTE (harbor#309): after a refused Bash call, how often is the session's next call a Write or
# Edit, against the same rate after an allowed Bash call? Joined on `sk`, the salted session key.
# A call is an egress record (egress writes one for every tool call it hooks). Each refusal or ask
# goes to ONE call: the nearest record of the same tool within a second, one per guard, and a
# refusal with several candidates (parallel calls) is counted as ambiguous. Unkeyed records sit out.
# A refusal with no record within a second takes the nearest same-tool allowed call within 10 s out
# of the control as unknown: a guard can lag egress by seconds on a big heredoc (harbor#976).
RR_MIN=20   # below this many calls on either side the ratio is noise, so it is withheld
RR_JQ='
def ep: (.ts | tostring | fromdateiso8601? // null);
def refusal: .d == "block" or .d == "deny";
def ww: . == "Write" or . == "Edit" or . == "MultiEdit" or . == "NotebookEdit";
def near($c): .t == $c.t and .e != null and $c.e != null and ((.e - $c.e) | fabs) <= 1;
(map(select((.sk // "-") != "-"))) as $k
| [ $k | group_by(.sk)[]
    | (to_entries | map(.value + {p: .key, e: (.value | ep)})) as $r
    | ($r | map(select(.g == "egress"))) as $c
    | ($r | map(select(.g != "wrapper" and .g != "session" and (.d == "block" or .d == "deny" or .d == "ask" or .d == "shadow")))) as $x
    | (reduce $x[] as $d ({taken: {}, cls: {}, rule: {}, amb: 0, lost: 0, lostd: [], unk: 0};
        . as $st
        | ([range(0; $c | length) as $j | select($d | near($c[$j])) | $j]) as $cand
        | ($cand | map(select(($st.taken["\($d.g):\(.)"] // false) | not))) as $free
        | if ($free | length) == 0 then
            (if ($d | refusal) then .lost += 1 | .lostd += [$d] else . end)
          else ($free | min_by(($c[.].p - $d.p) | fabs)) as $j
            | .taken["\($d.g):\($j)"] = true
            | .amb += (if ($d | refusal) and ($cand | length) > 1 then 1 else 0 end)
            | if ($d | refusal) then .cls["\($j)"] = "ref" | .rule["\($j)"] = $d.r
              elif (.cls["\($j)"] // "") == "ref" then . else .cls["\($j)"] = "ask" end
          end)
      | reduce .lostd[] as $d (.;
          . as $st
          | ([range(0; $c | length) as $j
              | select($c[$j].t == $d.t and $c[$j].e != null and $d.e != null
                       and (($c[$j].e - $d.e) | fabs) < 10 and ($st.cls["\($j)"] // "ok") == "ok") | $j]) as $cand
          | if ($cand | length) == 0 then .
            else ($cand | min_by(($c[.].p - $d.p) | fabs)) as $j | .cls["\($j)"] = "unk" | .unk += 1 end)) as $a
    | { lost: $a.lost, amb: $a.amb, unk: $a.unk,
        rows: [range(0; $c | length) as $j
               | { t: $c[$j].t, cls: ($a.cls["\($j)"] // "ok"), rule: ($a.rule["\($j)"] // null),
                   next: (if $j + 1 < ($c | length) then $c[$j + 1].t else null end) }] } ]
| (map(.rows[])) as $all
| ($all | map(select(.t == "Bash" and .next != null))) as $b
| ($b | map(select(.cls == "ref"))) as $rb
| { total: $n, keyed: ($k | length), sessions: ($k | map(.sk) | unique | length),
    lost: (map(.lost) | add // 0), amb: (map(.amb) | add // 0), unk: (map(.unk) | add // 0),
    other_ref: ($all | map(select(.cls == "ref" and .t != "Bash")) | length),
    rn: ($rb | length), rw: ($rb | map(select(.next | ww)) | length),
    cn: ($b | map(select(.cls == "ok")) | length),
    cw: ($b | map(select(.cls == "ok" and (.next | ww))) | length),
    after: ($rb | map(.next) | group_by(.) | map({t: .[0], n: length}) | sort_by(-.n) | .[0:5]),
    rules: ($rb | group_by(.rule) | map({r: .[0].rule, n: length, w: (map(select(.next | ww)) | length)})
            | sort_by(-.n) | .[0:8]) }
'
show_reroute() {
  log_head "reroute after a refusal (harbor#309)"
  echo "  After a refused Bash call, how often is the session's next call a Write or Edit?"
  echo "  Against the same rate after an allowed Bash call. CONSTITUTION 2.11: a wall gets walked around."
  _rr="$(printf '%s\n' "$REC" | jq -cs --argjson n "$TOTAL" "$RR_JQ" 2>/dev/null)" || _rr=""
  [ -n "$_rr" ] || { log_warn "the reroute join could not be computed from this ledger"; log_nofix "jq failed on the records; read the newest guard-decisions.jsonl by hand"; return; }
  printf '%s\n' "$_rr" | jq -r --argjson min "$RR_MIN" '
    def pct($a; $b): if $b > 0 then "\((1000 * $a / $b | round) / 10)%" else "n/a" end;
    "  \(.keyed) of \(.total) records carry a session key, across \(.sessions) session(s). The rest sit out:",
    "  written before harbor#309, or by a writer without the payload (the fail-closed wrapper, B6 at SessionStart)",
    (if .rn == 0 then "  (no refused Bash call with a key and a next call yet: nothing to join)"
     else "  refused Bash calls: \(.rn), next call Write/Edit: \(.rw) (\(pct(.rw; .rn)))" end),
    (if .cn == 0 then "  (no allowed Bash call with a key and a next call: no control, so no rate is compared)"
     else "  allowed Bash calls (control): \(.cn), next call Write/Edit: \(.cw) (\(pct(.cw; .cn)))" end),
    (if .rn >= $min and .cn >= $min and .cw > 0 then "  ratio: \(((.rw / .rn) / (.cw / .cn) * 10 | round) / 10)x"
     elif .rn >= $min and .cn >= $min then "  (ratio undefined: the control rate is 0)"
     elif .rn > 0 and .cn > 0 then "  (ratio withheld: fewer than \($min) calls on a side)" else empty end),
    (if (.rules | length) > 0 then "  by rule (refused, then next call Write/Edit):" else empty end),
    (.rules[] | "    \(.r // "?"): \(.n), \(.w) (\(pct(.w; .n)))"),
    (if (.after | length) > 0 then "  next call after a refused Bash call: " + (.after | map("\(.t) \(.n)") | join(", ")) else empty end),
    (if .other_ref > 0 then "  \(.other_ref) refused non-Bash call(s) are not in the rate: the control is Bash" else empty end),
    (if .amb > 0 then "  \(.amb) refusal(s) had parallel calls of the same tool in the same second; each went to the nearest record" else empty end),
    (if .lost > 0 then "  \(.lost) refusal(s) matched no egress record within a second, so no call to join them to" else empty end),
    (if .unk > 0 then "  \(.unk) call(s) within 10 s of such a refusal sit out of the control as unknown" else empty end),
    "  what this cannot see: tools the floor does not hook (Read, Grep, Glob), so \"next\" is the next call the floor",
    "  saw, and a call issued in the same batch before the refusal came back still counts as next. One key per",
    "  session: its subagents share it, so in parallel work \"next\" can be a sibling agent'"'"'s call. Refusals the",
    "  ledger never records stay in the control: govern-hook denies, a project-wired prod_guard.py, harness",
    "  permission denials and user rejections."'
}

# --confinement (harbor#1298): the escape rate #555 decision 10(a) stops on. One record per Bash call comes from
# guard-bash (g=bash); `c` says whether the call ran confined or asked to leave the sandbox. Days are UTC.
CONF_STOP=2
show_confinement() {
  log_head "confinement escape rate (harbor#555 decision 10a)"
  echo "  Bash calls that asked to run outside the sandbox, over all calls while it was installed."
  _cf="$(printf '%s\n' "$REC" | jq -r 'select(.g=="bash" and .t=="Bash" and (.c=="confined" or .c=="unconfined" or .c=="off"))|"\(.ts[0:10])\t\(.c)"' 2>/dev/null)" || _cf=""
  if [ -z "$_cf" ]; then
    echo "  (no Bash record carries the confinement field yet: written before harbor#1298, or no session since)"
    return
  fi
  case "$_cf" in *confined*) ;; *)
    printf '  (%s Bash call(s), none with the confinement installed)\n' "$(printf '%s\n' "$_cf" | grep -c .)"; return ;;
  esac
  echo "  day (UTC)     confined  unconfined  rate"
  printf '%s\n' "$_cf" | awk -F'\t' '
    { d[$1] = 1; n[$1 FS $2]++ }
    END {
      for (k in d) {
        c = n[k FS "confined"] + 0; u = n[k FS "unconfined"] + 0
        if (c + u > 0) printf "  %s  %8d  %10d  %4.1f%%\n", k, c, u, 100 * u / (c + u)
      }
    }' | sort
  printf '%s\n' "$_cf" | awk -F'\t' -v stop="$CONF_STOP" '
    { t[$2]++ }
    END {
      c = t["confined"] + 0; u = t["unconfined"] + 0; if (c + u == 0) exit
      r = 100 * u / (c + u)
      printf "  all days: %d of %d (%.1f%%) against the %d%% stop line: %s\n", u, c + u, r, stop, (r > stop ? "OVER, so P3 does not ship" : "under")
      if (t["off"]) printf "  %d Bash call(s) ran with no confinement installed and sit out of the rate\n", t["off"]
    }'
  # P3 (harbor#1300): blocks a confined call left to the sandbox, per rule. Absent until the operator turns the skip on.
  _cv="$(printf '%s\n' "$REC" | jq -r 'select(.d=="covered")|.r' 2>/dev/null | sort | uniq -c | sort -rn)"
  [ -z "$_cv" ] || { echo "  left to the sandbox (P3, covered), by rule:"; printf '%s\n' "$_cv" | awk '{ printf "  %8d  %s\n", $1, $2 }'; }
}

show_overrides() {
  log_head "overrides"
  _den=$((NOVR + NARM))
  if [ "$_den" = 0 ]; then
    echo "  no session boundary records yet (admission-observe.sh runs at SessionStart)"
  else
    # awk -v, never string interpolation into the program text: an empty counter
    # produced the program `BEGIN{printf "%.1f", 100*/1}` and a syntax error.
    printf '  %d overridden / %d armed sessions = %s%% override rate\n' \
      "$NOVR" "$NARM" "$(awk -v a="$NOVR" -v b="$_den" 'BEGIN{printf "%.1f", (b>0 ? 100*a/b : 0)}')"
  fi
  [ "$NSHS" = 0 ] || printf '  %d shadow session(s), outside both counts: guards ran and recorded, and almost nothing blocked (--shadow)\n' "$NSHS"
  [ "$NOVR" = 0 ] && return
  echo "  blocks immediately preceding an override — NOT attributed as the cause:"
  echo "  (under HARBOR_ADMISSION_DISABLE no guard runs at all, so nothing is attributable)"
  printf '%s\n' "$REC" | awk -F'"' '
    /"d":"block"/ { last=$0 }
    /"d":"override"/ { if (last != "") { print "  " last; last="" } }' \
    | sed 's/{"v":1,//' | head -10
}

case "$MODE" in
  rules)     show_rules ;;
  gates)     show_gdeny ;;
  fp)        show_fp ;;
  advise)    show_advise ;;
  shadow)    show_shadow ;;
  reroute)   show_reroute ;;
  confinement) show_confinement ;;
  overrides) show_overrides ;;
  all)
    log_head "guard-decision ledger · $OBS"
    printf '   %d records · %d block · %d gate-deny · %d gate-ask · %d advise · %d shadow · %d allow · %d wrapper-deny · %d session-gate\n' \
      "$TOTAL" "$NBLOCK" "$NGDENY" "$NASK" "$NADV" "$NSHW" "$NALLOW" "$NWRAP" "$NGATE"
    if [ "$NWRAP" != 0 ]; then
      log_warn "$NWRAP wrapper denies — the floor could not REACH a verdict that often. That is 'the floor is broken', not 'a rule fired': investigate before reading any block count as a measure of the rules."
      log_nofix "docs/explanation/admission-baseline.md — sh bin/audit-triage.sh --live names the rule (FC-1/FC-2)"
    fi
    echo
    show_rules; echo
    show_gdeny; echo
    show_advise; echo
    show_fp; echo
    show_shadow; echo
    show_reroute; echo
    show_confinement; echo
    show_overrides; echo
    log_head "tool census (wiring liveness)"
    echo "  A tool class that never appears is a dispatch arm that may be DEAD."
    printf '%s\n' "$REC" | jq -r .t | sort | uniq -c | sort -rn \
      | awk '{ printf "  %5d  %s\n", $1, $2 }'
    ;;
esac
log_end || :
