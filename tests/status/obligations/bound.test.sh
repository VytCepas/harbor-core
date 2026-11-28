#!/usr/bin/env sh
# bound.test.sh — what the obligations job writes and keeps: (1) the ledger is cut once a day to what a reader can still look back to,
# (2) a run with nothing new does not rewrite current.json or snapshot.json (~10 MB together on the live box), and a run with
# something new does.
#
# THE RED-PROOFS ARE IN THE SUITE, as in harden.test.sh: each is a case function that prints ok or what was wrong, run against the
# real script (must print ok) and against a copy with the change taken out (must not).
. "$(dirname "$0")/../../lib/core.sh"; t_init

BIN="$T_ROOT/bin/status-obligations.sh"; KINDS="$T_ROOT/contracts/obligation-kinds.tsv"
W="$T_TMP/w"; EV="$W/ev"; OB="$W/ob"; CACHE="$W/cache"; MUTD="$T_TMP/mut"; FHOME="$T_TMP/zed"; D=2026-10-06.jsonl
NOW=2026-10-06T02:00:00Z; N=0; EMPTY='{}'
mkdir -p "$MUTD" "$FHOME"

fresh() { rm -rf "$W"; mkdir -p "$EV" "$OB" "$CACHE"; N=0; NOW=2026-10-06T02:00:00Z; }
ev() { N=$((N + 1)); printf '{"id":"e%s","ts":"%s","src":"cli","kind":"%s","subject":"%s","repo":"harbor","cause":"","data":%s}\n' "$N" "$1" "$2" "$3" "${4:-$EMPTY}" >> "$EV/$D"; }
ob() { # <script> <mode…>
  _s="$1"; shift
  env HOME="$FHOME" HARBOR_EVENT_DIR="$EV" HARBOR_STATUS_OBLIGATION_DIR="$OB" HARBOR_SCOPE_CACHE_DIR="$CACHE" HARBOR_STATUS_OBLIGATION_NOW="$NOW" \
    HARBOR_STATUS_OBLIGATION_KINDS="$KINDS" HARBOR_STATUS_OBLIGATION_ON_OVERDUE=off sh "$_s" "$@" 2>&1
}
inode() { ls -i "$1" | awk '{ print $1 }'; }
BAD=""
chk() { [ "$3" = "$2" ] || BAD="$BAD [$1: want '$2', got '$3']"; }
verdict() { printf '%s' "${BAD:-ok}"; BAD=""; }
farm() { rm -rf "$MUTD/rp"; mkdir -p "$MUTD/rp"; for _f in "$T_ROOT"/bin/*; do ln -s "$_f" "$MUTD/rp/$(basename "$_f")"; done; }
mutate() { # <file> <from> <to>
  _mf="$MUTD/rp/$(basename "$1")"; rm -f "$_mf"
  from="$2" to="$3" awk 'BEGIN { RS = "\001"; from = ENVIRON["from"]; to = ENVIRON["to"] } { i = index($0, from); if (i == 0) exit 3; printf "%s%s%s", substr($0, 1, i - 1), to, substr($0, i + length(from)) }' \
    "$1" > "$_mf" || { t_fail "mutation target not found in $(basename "$1"): $2"; return 1; }
  cmp -s "$1" "$_mf" && { t_fail "mutation changed nothing: $2"; return 1; }
  return 0
}
redproof() { # <label> <case function> <file> <from> <to>
  farm; rm -f "$MUTD/rp/$(basename "$3")"; cp "$3" "$MUTD/rp/$(basename "$3")"; _c="$("$2" "$MUTD/rp/$(basename "$3")")"
  [ "$_c" = ok ] || { t_fail "$1: the control copy, unbroken, fails the case: $_c"; return 0; }
  mutate "$3" "$4" "$5" || return 0
  _v="$("$2" "$MUTD/rp/$(basename "$3")")"
  [ "$_v" != ok ] && t_pass || t_fail "$1: the broken copy still passed"
}

# A ledger of five obligations at 2026-10-06 (window 15 days: the cut is 2026-09-21T02:00:00Z).
row_open() { printf '{"ts":"%s","obligation":"pr:o/r#%s","to":"open","event":"o%s","kind":"pr","subject":"o/r#%s","repo":"r","owner":"operator","title":"t%s","link":"","deadline_ts":"","outlives":false}\n' "$1" "$2" "$2" "$2" "$2"; }
row_close() { printf '{"ts":"%s","obligation":"pr:o/r#%s","to":"closed","event":"c%s","closed_by":"c%s"}\n' "$1" "$2" "$2" "$2"; }
old_ledger() {
  { row_open 2026-08-01T00:00:00Z 1; row_close 2026-08-01T01:00:00Z 1       # 1: closed long ago: gone
    row_open 2026-08-02T00:00:00Z 2                                          # 2: open since August: every line stays, whatever its age
    row_open 2026-09-10T00:00:00Z 3; row_close 2026-10-04T00:00:00Z 3        # 3: opened before the window, closed inside it: both stay
    row_open 2026-10-05T00:00:00Z 4                                          # 4: recent
    printf 'this line does not parse\n'                                      # kept: it is counted, not judged
    printf '{"ts":"2026-08-03T00:00:00Z","obligation":"agent:zz","to":"pending","event":"p1","closed_by":"p1"}\n'   # an old held close: gone
  } > "$OB/ledger.jsonl"
}
ids() { jq -r '.obligations[] | select(.state == "open" or .state == "closed") | "\(.id) \(.state)"' "$OB/current.json" 2>/dev/null | sort | tr '\n' ' '; }

case_bound() { # <script>
  fresh; old_ledger; _before="$(jq -c .obligations "$OB/current.json" 2>/dev/null || :)"
  ob "$1" fold >/dev/null
  chk "five lines are left of eight" 5 "$(wc -l < "$OB/ledger.jsonl" | tr -d ' ')"
  chk "the closed row's lines are gone" 0 "$(grep -c 'o/r#1"' "$OB/ledger.jsonl")"
  chk "the old held close is gone" 0 "$(grep -c 'agent:zz' "$OB/ledger.jsonl")"
  chk "the open row keeps its August line" 1 "$(grep -c '"2026-08-02T00:00:00Z"' "$OB/ledger.jsonl")"
  chk "a row that moved inside the window keeps both lines" 2 "$(grep -c 'o/r#3"' "$OB/ledger.jsonl")"
  chk "a line that does not parse stays" 1 "$(grep -c 'does not parse' "$OB/ledger.jsonl")"
  chk "what a reader sees is the same" "pr:o/r#2 open pr:o/r#3 closed pr:o/r#4 open " "$(ids)"
  # the snapshot sits on a line of the cut ledger, so the next run reads from its byte and finds nothing new
  chk "the snapshot is at the cut ledger's end" "$(wc -c < "$OB/ledger.jsonl" | tr -d ' ')" "$(jq -r .ledger_bytes "$OB/snapshot.json")"
  chk "the cut is stamped" 2026-10-06 "$(cat "$OB/compacted" 2>/dev/null)"
  # a rebuild from the cut ledger alone gives the same rows
  _cur="$(jq -c .obligations "$OB/current.json")"; rm -f "$OB/snapshot.json" "$OB/compacted"; ob "$1" fold >/dev/null
  chk "a rebuild from the cut ledger gives the same rows" "$_cur" "$(jq -c .obligations "$OB/current.json")"
  chk "and does not cut it again" 5 "$(wc -l < "$OB/ledger.jsonl" | tr -d ' ')"
  # a day later the ledger is looked at again: the closed row 3 is still inside its window, and nothing else moves
  NOW=2026-10-06T23:00:00Z; ob "$1" fold >/dev/null; rm -f "$OB/compacted"; NOW=2026-10-07T01:00:00Z; ob "$1" fold >/dev/null
  chk "a second cut with nothing to drop leaves it whole" 5 "$(wc -l < "$OB/ledger.jsonl" | tr -d ' ')"
  verdict
}
case_under_bound() { # <script> — a ledger with nothing past the bound is left byte for byte
  fresh; { row_open 2026-10-05T00:00:00Z 4; row_open 2026-10-05T01:00:00Z 5; row_close 2026-10-05T02:00:00Z 5; } > "$OB/ledger.jsonl"
  cp "$OB/ledger.jsonl" "$W/ledger.before"; ob "$1" fold >/dev/null
  cmp -s "$W/ledger.before" "$OB/ledger.jsonl" || BAD="$BAD [a ledger inside the bound was changed]"
  chk "the cut is still stamped, so it is not read again today" 2026-10-06 "$(cat "$OB/compacted" 2>/dev/null)"
  verdict
}
case_unchanged() { # <script> — a run with nothing new writes neither big file; one with something new writes both
  fresh; NOW=2026-10-06T01:00:00Z; ev 2026-10-06T01:00:00Z session.start S1 '{"title":"harbor night"}'
  # a row closed 15 days and a half-hour before the second run: under an exact 15-day edge it would leave current.json on that run
  ev 2026-09-21T01:00:00Z pr.opened VytCepas/harbor#9; ev 2026-09-21T01:30:00Z pr.merged VytCepas/harbor#9; ob "$1" fold >/dev/null
  chk "the edge row is in current.json to begin with" closed "$(jq -r '.obligations[] | select(.id == "pr:VytCepas/harbor#9") | .state' "$OB/current.json")"
  _ic="$(inode "$OB/current.json")"; _is="$(inode "$OB/snapshot.json")"; _il="$(inode "$OB/ledger.jsonl")"
  NOW=2026-10-06T02:05:00Z; ob "$1" fold >/dev/null
  chk "current.json is not rewritten" "$_ic" "$(inode "$OB/current.json")"
  chk "snapshot.json is not rewritten" "$_is" "$(inode "$OB/snapshot.json")"
  chk "the ledger is not rewritten" "$_il" "$(inode "$OB/ledger.jsonl")"
  chk "the run's clock still moves, in the stamp" 2026-10-06T02:05:00Z "$(cat "$OB/generated_ts")"
  chk "and show reports it as generated_ts" 2026-10-06T02:05:00Z "$(ob "$1" show --json 2>/dev/null | jq -r .generated_ts)"
  NOW=2026-10-06T02:10:00Z; ev 2026-10-06T02:06:00Z session.stop S1; ob "$1" fold >/dev/null
  [ "$(inode "$OB/current.json")" != "$_ic" ] || BAD="$BAD [a changed tick did not write current.json]"
  [ "$(inode "$OB/snapshot.json")" != "$_is" ] || BAD="$BAD [a changed tick did not write snapshot.json]"
  chk "the change is in current.json" closed "$(jq -r '.obligations[] | select(.id == "session:S1") | .state' "$OB/current.json")"
  verdict
}

t_section "the ledger is cut to its bound, and nothing a reader uses goes with it"
t_eq "real script: a ledger past the bound is cut to it" ok "$(case_bound "$BIN")"
t_eq "real script: a ledger inside the bound is untouched" ok "$(case_under_bound "$BIN")"
redproof "no cut" case_bound "$BIN" '  compact_ledger
}' '  :
}'
redproof "the cut drops live rows' lines" case_bound "$BIN" 'select($P[$i] == null or $live[$P[$i].o] == true or $last[$P[$i].o] >= $cut)' 'select($P[$i] == null or $last[$P[$i].o] >= $cut)'
redproof "the cut drops the history of a row that closed inside the window" case_bound "$BIN" '$last[$P[$i].o] >= $cut)' '$P[$i].t >= $cut)'

t_section "a run with nothing new rewrites nothing; one with something new does"
t_eq "real script" ok "$(case_unchanged "$BIN")"
redproof "current.json always rewritten" case_unchanged "$BIN" '  put_if_changed "$T/current.doc" "$CURRENT" body ||' '  mv -f "$T/current.doc" "$CURRENT" ||'
redproof "the retention edge moves continuously, so every tick changes the file" case_unchanged "$BIN" '((($now - $retain) / $step | floor) * $step) as $cut' '($now - $retain) as $cut'
redproof "snapshot.json always rewritten" case_unchanged "$BIN" '&& put_if_changed "$T/snapshot.new" "$SNAP" whole' '&& mv -f "$T/snapshot.new" "$SNAP"'
t_done
