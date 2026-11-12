#!/usr/bin/env sh
# bq-load.sh (harbor#1278) — the hub loader: the board's heartbeat comments into harbor's BigQuery logs, as closed rows keyed by each
# laptop's random id. The hub job (patches/hub/hub-bq-load.patch.md) runs it; by hand until that job has its own yes (D1).
#   sh bq-load.sh policies <hub-checkout> <out-dir>    every policy.json in the hub's history, as <out-dir>/<serial>.json (D6)
#   sh bq-load.sh build --issues F --policies DIR --identity F --out DIR [--excluded F] [--load-id N] [--now UTC]
#        F is hub-fetch.sh's output. Each comment counts only if its author is the issue's login and it passes hub-format.sh board.
#        The heartbeat's sealed field is opened with the age identity (a file only this job reads): it gives the laptop's id and its
#        activity and session counts. A comment without one gives no row (no-id): the laptop sends none before its notice receipt.
#        Rows are per id and day (D4); hub rule and pack names become hub:<serial>:<index> and hubpack:<index> (D6); the GitHub
#        author is dropped before staging, and the run refuses if a login or an e-mail is left in any staged file.
#        --excluded: ids, 32 hex a line, whose rows are dropped here and deleted from BigQuery by the merge (legal/dpia.md R12).
#        Writes <out>/staging/<table>.jsonl, coded for a load, <out>/merge.sql and <out>/summary.json. Nothing leaves the machine.
#   sh bq-load.sh apply --dir DIR --project P --dataset D   load the staged tables and run the checks and the merge (needs bq and a
#        credential: WIF in the hub job). Stops before the fact tables on any failed check.
# Exit 0 done, 1 refused, 2 usage, 3 unchecked (a tool or an input is missing, so nothing was judged).
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
BQ_HERE="$HERE"
LOG_FD=2; export LOG_FD
. "$HERE/library-log.sh"
. "$HERE/library-bq.sh"
log_init bq-load

usage() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
die() { log_fail "$1"; log_fix "${2:-sh $0 --help}"; log_end || :; exit "${3:-1}"; }
W=''
trap '[ -z "$W" ] || rm -rf "$W"' EXIT
trap 'exit 130' INT HUP TERM
for _t in jq base64; do command -v "$_t" >/dev/null 2>&1 || die "unchecked — $_t is missing, so nothing was judged" "$(pkg_hint "$_t")" 3; done

cmd_policies() { # <hub-checkout> <out-dir>
  [ $# -eq 2 ] || usage
  git -C "$1" rev-parse --git-dir >/dev/null 2>&1 || die "$1 is not a git checkout of the hub" "check out the hub with its history (fetch-depth: 0)" 2
  mkdir -p "$2"
  for _c in $(git -C "$1" log --format=%H -- policy.json); do
    git -C "$1" show "$_c:policy.json" > "$2/.p" 2>/dev/null || continue
    sh "$HERE/hub-format.sh" policy "$2/.p" >/dev/null 2>&1 || continue
    _s="$(jq -r .serial "$2/.p")"
    [ -f "$2/$_s.json" ] || cp "$2/.p" "$2/$_s.json"
  done
  rm -f "$2/.p"
  log_ok "$(find "$2" -name '*.json' | grep -c . || true) signed-shape policies by serial in $2"; log_end || :
}

# The comments of the board as one record each: {login, at, day, hb, ev, sealed}. Only a comment its own member wrote, in the issue
# titled with that login, with a fenced JSON array; the rest are counted, never read further.
COMMENTS='
  [.[] | select(type == "object")
   | ((.title // "") | capture("^heartbeat (?<l>[A-Za-z0-9][A-Za-z0-9-]{0,38})$")? // null) as $m
   | select($m != null) | $m.l as $l
   | (.comments // [])[] | select(type == "object")
   | {login: $l, author: (.author // ""), at: (.created_at // ""),
      events: ((.body // "" | capture("^\\s*```json\\s*\\n(?<j>[\\s\\S]*?)\\n```\\s*$")? | .j | fromjson? | select(type == "array")) // null)}]'

cmd_build() {
  ISSUES=''; POLICIES=''; IDENTITY=''; OUT=''; EXCLUDED=''; LOAD_ID=''; NOW=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --issues|--policies|--identity|--out|--excluded|--load-id|--now)
        [ $# -ge 2 ] || usage
        case "$1" in --issues) ISSUES="$2" ;; --policies) POLICIES="$2" ;; --identity) IDENTITY="$2" ;; --out) OUT="$2" ;;
          --excluded) EXCLUDED="$2" ;; --load-id) LOAD_ID="$2" ;; --now) NOW="$2" ;; esac; shift ;;
      *) usage ;;
    esac; shift
  done
  [ -n "$ISSUES" ] && [ -n "$POLICIES" ] && [ -n "$IDENTITY" ] && [ -n "$OUT" ] || usage
  for _f in "$ISSUES" "$IDENTITY"; do [ -r "$_f" ] || die "unchecked — $_f can't be read, so nothing was judged" "sh $0 --help" 3; done
  [ -d "$POLICIES" ] || die "unchecked — $POLICIES is not a directory of policies, so nothing was judged" "sh $0 policies <hub> $POLICIES" 3
  command -v age >/dev/null 2>&1 || die "unchecked — age is missing, so no id can be opened" "$(pkg_hint age)" 3
  [ -n "$NOW" ] || NOW="$(date -u +%Y-%m-%dT%H:%M:00Z)"
  case "$NOW" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:00Z) ;; *) die "--now wants a UTC minute, 2026-11-09T07:23:00Z" "" 2 ;; esac
  [ -n "$LOAD_ID" ] || LOAD_ID="$(date -u +%Y%m%d%H%M)"
  case "$LOAD_ID" in ''|*[!0-9]*) die "--load-id wants a whole number" "" 2 ;; esac
  mkdir -p "$OUT"; rm -rf "$OUT/staging"; printf '{}' > "$OUT/refused.json"
  W="$(mktemp -d "${TMPDIR:-/tmp}/bq-load.XXXXXX")"
  : > "$W/excluded"; [ -z "$EXCLUDED" ] || grep -E '^[0-9a-f]{32}$' "$EXCLUDED" > "$W/excluded" 2>/dev/null || :

  # 1 · the comments, and the ones that do not count
  jq -c "$COMMENTS"' | .[]' "$ISSUES" > "$W/comments.jsonl" || die "unchecked — $ISSUES is not the hub fetch output" "the issues file the fetch step of the hub job writes (harbor#1278)" 3
  jq -r '.login' "$W/comments.jsonl" | sort -u > "$W/logins"
  : > "$W/recs.jsonl"; _mismatch=0; _bad=0; _noid=0; _excl=0; _n=0
  while IFS= read -r _c; do
    _n=$((_n + 1)); printf '%s' "$_c" > "$W/c.json"
    if ! jq -e '(.author | ascii_downcase) == (.login | ascii_downcase)' "$W/c.json" >/dev/null; then _mismatch=$((_mismatch + 1)); continue; fi
    jq '.events' "$W/c.json" > "$W/ev.json"
    if ! jq -e 'type == "array" and length > 0' "$W/ev.json" >/dev/null 2>&1 \
       || ! sh "$HERE/hub-format.sh" board "$W/ev.json" >/dev/null 2>&1 \
       || ! jq -e --slurpfile c "$W/c.json" '($c[0].login | ascii_downcase) as $l | all(.[]; (.member | ascii_downcase) == $l) and (.[0].kind == "heartbeat")' "$W/ev.json" >/dev/null; then
      _bad=$((_bad + 1)); continue
    fi
    # 2 · the seal: the id and the counts. No seal, no row: the author alone never keys anything.
    _s="$(jq -r '.[0].sealed // empty' "$W/ev.json")"
    if [ -z "$_s" ] || ! printf '%s' "$_s" | base64 -d 2>/dev/null > "$W/s.age" \
       || ! age -d -i "$IDENTITY" < "$W/s.age" > "$W/s.json" 2>/dev/null \
       || ! jq -e 'type == "object" and .v == 1 and (.id | type == "string" and test("^[0-9a-f]{32}$")) and (.events | type == "array")
                   and all(.events[]; .kind == "activity" or .kind == "session")' "$W/s.json" >/dev/null 2>&1; then
      _noid=$((_noid + 1)); continue
    fi
    jq '.events' "$W/s.json" > "$W/sev.json"
    if [ "$(jq length "$W/sev.json")" -gt 0 ] && { ! sh "$HERE/hub-format.sh" event "$W/sev.json" >/dev/null 2>&1 \
       || ! jq -e --slurpfile c "$W/c.json" '($c[0].login | ascii_downcase) as $l | all(.[]; (.member | ascii_downcase) == $l)' "$W/sev.json" >/dev/null; }; then
      _bad=$((_bad + 1)); continue
    fi
    if grep -q -x -F "$(jq -r .id "$W/s.json")" "$W/excluded"; then _excl=$((_excl + 1)); continue; fi
    # the record keeps the id and drops the author: from here on nothing knows the login
    jq -c -n --slurpfile c "$W/c.json" --slurpfile e "$W/ev.json" --slurpfile s "$W/s.json" \
      '{id: $s[0].id, day: $c[0].at[0:10], at: $c[0].at, hb: $e[0][0], ev: $e[0][1:], sev: $s[0].events}' >> "$W/recs.jsonl"
  done < "$W/comments.jsonl"
  bq_refuse "$OUT" author-mismatch "$_mismatch"; bq_refuse "$OUT" bad-event "$_bad"; bq_refuse "$OUT" no-id "$_noid"; bq_refuse "$OUT" excluded "$_excl"
  _prerefused=$((_mismatch + _bad + _noid + _excl))

  # 3 · the policies by serial, for D6
  printf '{}' > "$W/pol.json"
  for _p in "$POLICIES"/*.json; do
    [ -f "$_p" ] || continue
    jq -c --slurpfile p "$_p" '. + {($p[0].serial | tostring): {rules: [($p[0].rules // [])[].id], packs: [($p[0].packs // [])[].id]}}' "$W/pol.json" > "$W/pol.new" && mv "$W/pol.new" "$W/pol.json"
  done

  # 4 · rows per table, per id and day. A value no set names stays as it is, so bq-format.sh refuses it by class, never by value.
  jq -s -c --slurpfile P "$W/pol.json" --argjson load "$LOAD_ID" '
    def at($a; $x): [range(0; $a | length) as $j | select($a[$j] == $x) | $j] | first // null;
    def hubrule($s): . as $r | ($P[0][$s | tostring].rules // []) as $a | at($a; $r) as $i | if $i == null then $r else "hub:\($s):\($i)" end;
    def hubpack($s): . as $k | ($P[0][$s | tostring].packs // []) as $a | at($a; $k) as $i | if $i == null then $k else "hubpack:\($i)" end;
    def base($r; $day): {schema_v: 1, source: "member-hub", person_id: $r.id, core: $r.hb.core, load_id: $load, day: $day};
    (map(. as $r | ($r.ev[] | select(.kind == "refusal" or .kind == "ask" or .kind == "request")
        | base($r; .ts[0:10]) + {kind, rule: (.rule | hubrule($r.hb.serial)), tier, target, outcome: (.outcome // null), count: (.count // 1)}))
     | group_by(del(.count)) | map(.[0] + {count: (map(.count) | add)}) | map({t: "decision", row: .})),
    (map(. as $r | ($r.ev[] | select(.kind == "check")
        | base($r; .ts[0:10]) + {check: (.check | hubrule($r.hb.serial)), outcome, count: 1}))
     | group_by(del(.count)) | map(.[0] + {count: (map(.count) | add)}) | map({t: "check_run", row: .})),
    (map(. as $r | ($r.ev[] | select(.kind == "token" or .kind == "support")
        | base($r; .ts[0:10]) + {kind, outcome, reason: (.reason // null), days_left: (.days_left // null), count: 1}))
     | group_by(del(.count, .days_left)) | map(.[0] + {count: (map(.count) | add), days_left: (map(.days_left | numbers) | min)}) | map({t: "lifecycle", row: .})),
    (map(. as $r | ($r.sev[] | select(.kind == "activity")
        | base($r; .ts[0:10]) + {tool, verb_class, verdict, calls: .count}))
     | group_by(del(.calls)) | map(.[0] + {calls: (map(.calls) | add)}) | map({t: "activity", row: .})),
    (map(. as $r | ($r.sev[] | select(.kind == "session") | base($r; .ts[0:10]) + {o: .outcome, n: .count}))
     | group_by(del(.o, .n)) | map(. as $g | ($g[0] | del(.o, .n)) + {started: ($g | map(select(.o == "started") | .n) | add // 0), ended: ($g | map(select(.o == "ended") | .n) | add // 0)})
     | map({t: "session", row: .})),
    (group_by([.id, .day]) | map(sort_by(.at) as $c | $c[-1].hb as $h
        | base($c[-1]; $c[-1].day) + {heartbeats: ($c | length), contract: $h.contract, floor: $h.floor, serial: $h.serial, mode: $h.mode,
            refusals: ($c | map(.hb.refusals) | add), asks: ($c | map(.hb.asks) | add), requests: ($c | map(.hb.requests) | add),
            packs: ($h.packs | map(hubpack($h.serial)))}) | map({t: "heartbeat", row: .}))
    | .[]' "$W/recs.jsonl" > "$W/rows.jsonl" || die "the projection failed to run" "the jq error is above" 3
  for _t in heartbeat decision check_run lifecycle activity session; do
    jq -c --arg t "$_t" 'select(.t == $t) | .row' "$W/rows.jsonl" > "$W/$_t.values.jsonl"
    bq_stage "$OUT" "$_t" "$W/$_t.values.jsonl" || die "staging $_t failed" "sh bin/bq-format.sh row $_t" 1
  done

  # 5 · the dimensions: every value code there is, the hub codes this load used, and the policies
  { awk -F'\t' '!/^#/ && $1 != "set" && NF >= 3 { print $1 "\t" $2 "\t" $3 }' "$HERE/../contracts/bq-values.tsv" \
      | jq -R -c 'split("\t") | {set: .[0], code: (.[1] | tonumber), value: .[2]}'
    jq -r 'select(.t == "decision" or .t == "check_run") | .row | (.rule // .check) | select(test("^hub:"))' "$W/rows.jsonl" | sort -u \
      | jq -R -c 'split(":") as $p | {set: "rule", code: (1000000000 + ($p[1] | tonumber) * 1000 + ($p[2] | tonumber)), value: .}'
    jq -r 'select(.t == "heartbeat") | .row.packs[] | select(test("^hubpack:"))' "$W/rows.jsonl" | sort -u \
      | jq -R -c 'split(":") as $p | {set: "pack", code: (3000000000 + ($p[1] | tonumber)), value: .}'; } > "$W/dim_enum.values.jsonl"
  for _p in "$POLICIES"/*.json; do
    [ -f "$_p" ] || continue
    jq -c --argjson load "$LOAD_ID" '{serial, issued: (.issued[0:17] + "00Z"), mode: .rollout.mode, silent_days, pinned_core: .core.commit[0:12], contract: .core.contract, load_id: $load}' "$_p"
  done > "$W/dim_policy.values.jsonl"
  bq_stage "$OUT" dim_enum "$W/dim_enum.values.jsonl" || die "staging dim_enum failed" "sh bin/bq-format.sh row dim_enum"
  bq_stage "$OUT" dim_policy "$W/dim_policy.values.jsonl" || die "staging dim_policy failed" "sh bin/bq-format.sh row dim_policy"

  # 6 · the load's own record: counts, never values
  _refused=$(( $(jq '[.[]] | add // 0' "$OUT/refused.json") ))
  _dropped="$(jq -s '[.[] | .ev[] | select(.kind == "check" and .check == "hub-events-dropped")] | length' "$W/recs.jsonl")"
  _members="$(jq -s '[.[].id] | unique | length' "$W/recs.jsonl")"
  _run="${NOW}"
  jq -n -c --argjson l "$LOAD_ID" --arg run "$_run" --argjson i "$((${BQ_IN:-0} + _prerefused))" --argjson k "${BQ_OUT:-0}" --argjson r "$_refused" \
    --argjson m "$_members" --argjson d "$_dropped" \
    '{schema_v: 1, load_id: $l, run_at: $run, source: "member-hub", rows_in: $i, rows_loaded: $k, rows_refused: $r, members_seen: $m, laptop_dropped: $d}' > "$W/ingest_audit.values.jsonl"
  jq -c --argjson l "$LOAD_ID" --arg run "$_run" 'to_entries[] | select(.value > 0) | {schema_v: 1, load_id: $l, run_at: $run, reason: .key, count: .value}' \
    "$OUT/refused.json" > "$W/ingest_refusal.values.jsonl"
  BQ_IN_KEEP="${BQ_IN:-0}"; BQ_OUT_KEEP="${BQ_OUT:-0}"
  bq_stage "$OUT" ingest_audit "$W/ingest_audit.values.jsonl" || die "staging ingest_audit failed" "sh bin/bq-format.sh row ingest_audit"
  bq_stage "$OUT" ingest_refusal "$W/ingest_refusal.values.jsonl" || die "staging ingest_refusal failed" "sh bin/bq-format.sh row ingest_refusal"

  # 7 · nothing that names a person may be staged: every login this run read, and any e-mail
  if ! bq_identity_scan "$OUT" "$W/logins"; then
    rm -rf "$OUT/staging"
    die "a login or an e-mail reached a staged file: nothing is staged" "none automatic — this is a defect in bin/bq-load.sh; see harbor#1278"
  fi
  cp "$W/excluded" "$OUT/excluded"
  BQ_ERASE="$OUT/excluded" bq_sql "$OUT" PROJECT DATASET > "$OUT/merge.sql"
  jq -n -c --argjson c "$_n" --argjson k "$(wc -l < "$W/recs.jsonl" | tr -d ' ')" --argjson i "$BQ_IN_KEEP" --argjson o "$BQ_OUT_KEEP" --slurpfile r "$OUT/refused.json" \
    '{comments: $c, comments_kept: $k, rows_in: $i, rows_staged: $o, refused: $r[0]}' > "$OUT/summary.json"
  log_ok "$_n comment(s), $(wc -l < "$W/recs.jsonl" | tr -d ' ') kept; $BQ_OUT_KEEP row(s) staged in $OUT/staging, refused by reason: $(cat "$OUT/refused.json")"
  log_end || :
}

cmd_apply() {
  DIR=''; PROJECT=''; DATASET=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --dir|--project|--dataset) [ $# -ge 2 ] || usage
        case "$1" in --dir) DIR="$2" ;; --project) PROJECT="$2" ;; --dataset) DATASET="$2" ;; esac; shift ;;
      *) usage ;;
    esac; shift
  done
  [ -n "$DIR" ] && [ -n "$PROJECT" ] && [ -n "$DATASET" ] || usage
  [ -d "$DIR/staging" ] || die "unchecked — $DIR holds no staging, so nothing was loaded" "sh $0 build --help" 3
  case "$PROJECT$DATASET" in *[!abcdefghijklmnopqrstuvwxyz0123456789_-]*) die "a project or dataset name with a character outside [a-z0-9_-]" "" 2 ;; esac
  BQ_ERASE="$DIR/excluded"; export BQ_ERASE
  _rc=0; bq_apply "$DIR" "$PROJECT" "$DATASET" || _rc=$?
  [ "$_rc" -eq 0 ] || { log_end || :; exit "$_rc"; }
  log_ok "loaded and merged into $PROJECT:$DATASET"; log_end || :
}

verb="${1:-}"; [ -n "$verb" ] || usage
shift
case "$verb" in
  -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  policies) cmd_policies "$@" ;;
  build) cmd_build "$@" ;;
  apply) cmd_apply "$@" ;;
  *) usage ;;
esac
