#!/usr/bin/env sh
# bq-logs.sh (harbor#1278; `harbor logs`) — the operator's Mac into harbor's BigQuery logs, by hand (D3), as closed rows keyed by
# this Mac's random id, never a login (#1278 "Log scope", level 2).
#   harbor logs push [--apply] [--since DAY] [--until DAY] [--project P] [--dataset D]
#        Projects the guard ledger and the tool failures under <config>/MEMORY/OBSERVABILITY (the coded fields only: never h, k, sk
#        or the host folder's name, D10), the event bus's kinds and the usage counts, per day. Every row passes bq-format.sh and the
#        scrub gate of audit-stream-export.py. Without --apply it prints the rows it would send, one {"table","row"} a line, and
#        sends nothing. --apply loads them as the loader's service account, impersonated through your own gcloud login (no key
#        file), and needs the notice marker. --project and --dataset default to project= and dataset= in the config file below.
#        DAY is YYYY-MM-DD, UTC; the default window is the day of the last push (or 30 days back) through today. A day is replaced
#        whole, so pushing it again never adds.
#   harbor logs id
#        This Mac's random id, read only; push makes it once if it is missing.
# Files: ${XDG_CONFIG_HOME:-~/.config}/harbor/ holds logs.id (the id), notice-received (your own receipt marker) and logs.conf.
# Exit 0 done, 1 refused, 2 usage, 3 unchecked (a tool or a source is missing, so nothing was judged).
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
BQ_HERE="$HERE"
LOG_FD=2; export LOG_FD
. "$HERE/library-log.sh"
. "$HERE/library-bq.sh"
log_init bq-logs

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/harbor"
IDF="$CONF/logs.id"; MARK="$CONF/notice-received"; CONFF="$CONF/logs.conf"
EVD="${HARBOR_EVENT_DIR:-$HOME/.local/state/harbor/events}"
CURSOR="${XDG_STATE_HOME:-$HOME/.local/state}/harbor/logs/last-push"
VOCAB="$HERE/../contracts/hub-vocabulary.tsv"

usage() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
die() { log_fail "$1"; log_fix "${2:-sh $0 --help}"; log_end || :; exit "${3:-1}"; }
W=''
trap '[ -z "$W" ] || rm -rf "$W"' EXIT
trap 'exit 130' INT HUP TERM
for _t in jq python3; do command -v "$_t" >/dev/null 2>&1 || die "unchecked — $_t is missing, so nothing was judged" "$(pkg_hint "$_t")" 3; done

valid_id() { case "$1" in *[!0123456789abcdef]*) return 1 ;; esac; [ "${#1}" -eq 32 ]; }
read_id() { _ri="$(cat "$IDF" 2>/dev/null)" || _ri=''; valid_id "$_ri" && printf '%s' "$_ri"; }
make_id() {
  (umask 077; mkdir -p "$CONF") || return 1
  _mi="$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')"; valid_id "$_mi" || return 1
  (umask 377; printf '%s\n' "$_mi" > "$IDF.new.$$") && mv "$IDF.new.$$" "$IDF"
}
conf() { sed -n "s/^$1=//p" "$CONFF" 2>/dev/null | head -n 1; }

cmd_id() {
  [ $# -eq 0 ] || usage
  _id="$(read_id)" || die "no id yet at $IDF: the first push makes one" "harbor logs push"
  printf '%s\n' "$_id"
  if [ -f "$MARK" ]; then log_note "the notice marker is set: --apply may send under this id"; else log_note "no notice marker at $MARK: nothing is sent"; fi
  log_end || :
}

# ── the projection: one jq per source, each reading only the fields it names ──
LEDGER='
  def day: .ts[0:10];
  def rank: {deny: 9, block: 8, ask: 7, gate: 6, armed: 5, shadow: 4, advise: 3, override: 2, covered: 1}[.] // 0;
  [.[] | select(type == "object" and (.ts | type) == "string") | {ts, g, d, r, s, t, h, sk, c, x}
   | select(day >= $since and day <= $until)] as $l
  | ($l | map(select(.d != "allow")) | group_by([day, .r, .g, .d, .s, .t, .c, .x])
     | map((map(.h | select(type == "string" and . != "-"))) as $hs
          | {table: "decision", row: {day: (.[0] | day), kind: "guard", rule: .[0].r, guard: .[0].g, verdict: .[0].d, shape: .[0].s, tool: .[0].t,
             confinement: (if .[0].c == "-" then "na" else .[0].c end), verb_class: (if .[0].x == "-" then null else .[0].x end),
             count: length,
             distinct_subjects: (if ($hs | length) > 0 then ($hs | unique | length) else null end),
             max_repeat: (if ($hs | length) > 0 then ($hs | group_by(.) | map(length) | max) else null end)}}) | .[]),
    # calls: the guard rows of one call share its second, session digest and tool. An approximation the design names (F3).
    ($l | group_by([.ts, .sk, .t])
     | map({day: (.[0] | day), tool: .[0].t, verb_class: (map(.x | select(. != "-")) | first // null),
            verdict: (map(.d) | max_by(rank))})
     | group_by([.day, .tool, .verb_class, .verdict]) | map({table: "activity", row: (.[0] + {calls: length})}) | .[])'
FAILURES='
  [.[] | select(type == "object" and (.ts | type) == "string") | {ts, t, e} | select(.ts[0:10] >= $since and .ts[0:10] <= $until)
   | {day: .ts[0:10], tool: (.t as $t | if any($tools[]; . == $t) then $t elif ($t | type == "string" and startswith("mcp__")) then "mcp" else "other" end),
      error_class: .e}]
  | group_by([.day, .tool, .error_class]) | map({table: "activity", row: (.[0] + {failures: length})}) | .[]'
BUS='
  [.[] | select(type == "object" and (.ts | type) == "string") | {day: .ts[0:10], kind} | select(.day >= $since and .day <= $until)]
  | (group_by([.day, .kind]) | map({table: "bus_counts", row: {day: .[0].day, kind: .[0].kind, count: length}}) | .[]),
    (group_by(.day) | map({table: "session", row: {day: .[0].day,
        started: (map(select(.kind == "session.start")) | length), ended: (map(select(.kind == "session.stop")) | length),
        agents: (map(select(.kind == "agent.spawn")) | length)}}) | .[])'
USAGE='
  [.[] | select(type == "object" and (.day | type) == "string") | select(.day >= $since and .day <= $until)
   | .model as $mo | .entry as $en
   | {day, model: (if $mo == "<synthetic>" then "synthetic" elif any($models[]; . == $mo) then $mo else "other" end),
      entry: (if any($entries[]; . == $en) then $en else "other" end), msgs, inp, out, cc, cr}]
  | group_by([.day, .model, .entry])
  | map({table: "usage_daily", row: (.[0] + {msgs: (map(.msgs) | add), inp: (map(.inp) | add), out: (map(.out) | add), cc: (map(.cc) | add), cr: (map(.cr) | add)})}) | .[]'

# slurp <out> <file...>: the JSON lines of the files as one array, a broken line skipped
slurp() { _so="$1"; shift; if [ $# -eq 0 ]; then printf '[]' > "$_so"; else cat "$@" 2>/dev/null | jq -R -c 'fromjson? // empty' | jq -s -c . > "$_so"; fi; }

cmd_push() {
  APPLY=0; SINCE=''; UNTIL=''; PROJECT="$(conf project)"; DATASET="$(conf dataset)"
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply) APPLY=1 ;;
      --since|--until|--project|--dataset) [ $# -ge 2 ] || usage
        case "$1" in --since) SINCE="$2" ;; --until) UNTIL="$2" ;; --project) PROJECT="$2" ;; --dataset) DATASET="$2" ;; esac; shift ;;
      *) usage ;;
    esac; shift
  done
  [ -n "$UNTIL" ] || UNTIL="$(date -u +%Y-%m-%d)"
  [ -n "$SINCE" ] || SINCE="$(cat "$CURSOR" 2>/dev/null)" || SINCE=''
  [ -n "$SINCE" ] || SINCE="$(jq -rn 'now - 30 * 86400 | strftime("%Y-%m-%d")')"
  for _d in "$SINCE" "$UNTIL"; do case "$_d" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) die "a day is YYYY-MM-DD, got '$_d'" "" 2 ;; esac; done
  if [ "$APPLY" -eq 1 ]; then
    [ -f "$MARK" ] || die "no notice marker at $MARK, so nothing is sent (legal/dpia.md R11)" "touch '$MARK' once your own receipt of the notice is on file"
    command -v bq >/dev/null 2>&1 || die "unchecked — bq is missing, so nothing was sent" "$(pkg_hint google-cloud-sdk)" 3
    case "$PROJECT$DATASET" in ''|*[!abcdefghijklmnopqrstuvwxyz0123456789_-]*) die "--apply wants --project and --dataset, [a-z0-9_-] (or project= and dataset= in $CONFF)" "" 2 ;; esac
    [ -n "$PROJECT" ] && [ -n "$DATASET" ] || die "--apply wants --project and --dataset" "" 2
  fi
  _id="$(read_id)" || { make_id && _id="$(read_id)"; } || die "no id could be made at $IDF" "ls -ld '$CONF'"
  W="$(mktemp -d "${TMPDIR:-/tmp}/bq-logs.XXXXXX")"; OUT="$W/out"; mkdir -p "$OUT"; printf '{}' > "$OUT/refused.json"
  _core="$(git -C "$HERE/.." rev-parse HEAD 2>/dev/null | cut -c1-12)" || _core=''
  case "$_core" in ????????????) ;; *) _core=000000000000 ;; esac
  _load="$(date -u +%Y%m%d%H%M)"

  # the sources. The host folder is globbed and never read as a value.
  _obs="$CFG/MEMORY/OBSERVABILITY"
  find "$_obs" -maxdepth 3 -type f \( -name 'guard-decisions.jsonl' -o -name 'guard-decisions.jsonl.[0-9]' -o -name 'guard-decisions.*.jsonl' \) 2>/dev/null > "$W/ledger.list" || :
  find "$_obs" -maxdepth 3 -type f \( -name 'tool-failures.jsonl' -o -name 'tool-failures.jsonl.[0-9]' -o -name 'tool-failures.*.jsonl' \) 2>/dev/null > "$W/fail.list" || :
  find "$CFG/MEMORY/USAGE" -maxdepth 2 -type f -name usage.jsonl 2>/dev/null > "$W/usage.list" || :
  find "$EVD" -maxdepth 1 -type f -name '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].jsonl' 2>/dev/null > "$W/bus.list" || :
  [ -s "$W/ledger.list" ] || [ -s "$W/fail.list" ] || [ -s "$W/usage.list" ] || [ -s "$W/bus.list" ] \
    || die "unchecked — no source under $CFG or $EVD, so nothing was judged" "" 3
  # shellcheck disable=SC2046 # one path a line, none with a space (they are harbor's own sinks)
  slurp "$W/ledger.json" $(cat "$W/ledger.list"); slurp "$W/fail.json" $(cat "$W/fail.list")
  # shellcheck disable=SC2046
  slurp "$W/usage.json" $(cat "$W/usage.list"); slurp "$W/bus.json" $(cat "$W/bus.list")
  awk -F'\t' '$1 == "tool" { print $2 }' "$VOCAB" | jq -R -s -c 'split("\n") | map(select(length > 0))' > "$W/tools.json"
  awk -F'\t' '$1 == "model" && $4 == "live" { print $3 }' "$HERE/../contracts/bq-values.tsv" | jq -R -s -c 'split("\n") | map(select(length > 0))' > "$W/models.json"
  awk -F'\t' '$1 == "entry" && $4 == "live" { print $3 }' "$HERE/../contracts/bq-values.tsv" | jq -R -s -c 'split("\n") | map(select(length > 0))' > "$W/entries.json"
  jq -c --arg since "$SINCE" --arg until "$UNTIL" "$LEDGER" "$W/ledger.json" > "$W/p1" || die "the ledger projection failed to run" "the jq error is above" 3
  jq -c --arg since "$SINCE" --arg until "$UNTIL" --slurpfile T "$W/tools.json" '$T[0] as $tools | '"$FAILURES" "$W/fail.json" > "$W/p2" \
    || die "the tool-failure projection failed to run" "the jq error is above" 3
  jq -c --arg since "$SINCE" --arg until "$UNTIL" "$BUS" "$W/bus.json" > "$W/p3" || die "the bus projection failed to run" "the jq error is above" 3
  jq -c --arg since "$SINCE" --arg until "$UNTIL" --slurpfile M "$W/models.json" --slurpfile E "$W/entries.json" '$M[0] as $models | $E[0] as $entries | '"$USAGE" "$W/usage.json" > "$W/p4" \
    || die "the usage projection failed to run" "the jq error is above" 3
  cat "$W/p1" "$W/p2" "$W/p3" "$W/p4" | jq -c --arg id "$_id" --arg core "$_core" --argjson load "$_load" \
      '.row = ({schema_v: 1, source: "operator-mac", person_id: $id, core: $core, load_id: $load} + .row)' > "$W/rows.jsonl" \
    || die "the projection failed to run" "the jq error is above" 3

  # the scrub gate, over every value that would leave: this Mac's user, home, host and host token, any home path or e-mail
  if ! python3 -I "$HERE/audit-stream-export.py" scrub "$W/rows.jsonl" --cfg "$CFG" >/dev/null 2>"$W/scrub.err"; then
    die "the scrub gate refused the projection: $(sed -n 's/.*scrub gate: //p' "$W/scrub.err"). Nothing was sent" "none automatic — a field carries this machine's identity; see harbor#1278"
  fi
  for _t in decision activity session usage_daily bus_counts; do
    jq -c --arg t "$_t" 'select(.table == $t) | .row' "$W/rows.jsonl" > "$W/$_t.values.jsonl"
    bq_stage "$OUT" "$_t" "$W/$_t.values.jsonl" || die "staging $_t failed" "sh bin/bq-format.sh row $_t"
  done
  _in="${BQ_IN:-0}"; _kept="${BQ_OUT:-0}"; _ref="$(jq '[.[]] | add // 0' "$OUT/refused.json")"
  jq -n -c --argjson l "$_load" --arg run "$(date -u +%Y-%m-%dT%H:%M:00Z)" --argjson i "$_in" --argjson k "$_kept" --argjson r "$_ref" \
    '{schema_v: 1, load_id: $l, run_at: $run, source: "operator-mac", rows_in: $i, rows_loaded: $k, rows_refused: $r, members_seen: 1, laptop_dropped: 0}' > "$W/ingest_audit.values.jsonl"
  jq -c --argjson l "$_load" --arg run "$(date -u +%Y-%m-%dT%H:%M:00Z)" 'to_entries[] | select(.value > 0) | {schema_v: 1, load_id: $l, run_at: $run, reason: .key, count: .value}' \
    "$OUT/refused.json" > "$W/ingest_refusal.values.jsonl"
  bq_stage "$OUT" ingest_audit "$W/ingest_audit.values.jsonl" || die "staging ingest_audit failed" "sh bin/bq-format.sh row ingest_audit"
  bq_stage "$OUT" ingest_refusal "$W/ingest_refusal.values.jsonl" || die "staging ingest_refusal failed" "sh bin/bq-format.sh row ingest_refusal"
  python3 -I "$HERE/audit-stream-export.py" scrub "$OUT/staging/decision.jsonl" --cfg "$CFG" >/dev/null 2>&1 || [ ! -f "$OUT/staging/decision.jsonl" ] \
    || die "the scrub gate refused a staged file: nothing was sent" "none automatic — see harbor#1278"

  if [ "$APPLY" -eq 0 ]; then
    cat "$W/rows.jsonl"
    log_ok "dry run, $SINCE to $UNTIL: $_kept of $_in row(s) would be sent, refused by reason: $(cat "$OUT/refused.json"). Nothing was sent"
    log_note "harbor logs push --apply sends them"; log_end || :; return 0
  fi
  # the loader's account, through your own gcloud login: no key file exists (D2, D3)
  CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT="harbor-bq-loader@$PROJECT.iam.gserviceaccount.com"; export CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT
  BQ_ERASE=''; export BQ_ERASE
  _rc=0; bq_apply "$OUT" "$PROJECT" "$DATASET" || _rc=$?
  [ "$_rc" -eq 0 ] || { log_end || :; exit "$_rc"; }
  mkdir -p "${CURSOR%/*}" && printf '%s\n' "$UNTIL" > "$CURSOR"
  log_ok "sent $_kept row(s), $SINCE to $UNTIL, to $PROJECT:$DATASET as harbor-bq-loader"; log_end || :
}

verb="${1:-}"; [ -n "$verb" ] || usage
shift
case "$verb" in
  -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  push) cmd_push "$@" ;;
  id) cmd_id "$@" ;;
  *) usage ;;
esac
