#!/usr/bin/env sh
# surface.test.sh (harbor#1050 PR 3) — what a person, the statusline, the console and the finding ledger read of the
# obligations ledger: `harbor status obligations` (--json, --print, --since), the `OVERDUE N ·age` alarm and the YOU queue,
# the receipt that goes red over 24h overdue, and the dotted id `status.obligations` being SEEN by every reader of docs/reference/checks.md.
#
# THE RED-PROOFS ARE IN THE SUITE, as in reconcile.test.sh. Each surface is a case function that prints ok or what was
# wrong, and runs twice: against the real file (must print ok) and against a copy with one line broken (must not). A
# mutation that did not apply fails too, so a proof cannot pass for want of a change.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/obs/findings-fixture.sh"   # the stub GitHub, the published checkout and `rec`; sets F, TMP, PUB, RCD, GH_STATE

BIN="$T_ROOT/bin/status-obligations.sh"; REAL_KINDS="$T_ROOT/contracts/obligation-kinds.tsv"
# The scenarios below need a row that goes overdue, and the real register gives a session NO deadline (harbor#1115), so they run on
# a copy that restores the old 24h one. The one case that asks about a long-lived session reads the REAL register (case_long_session).
TAB="$(printf '\t')"; KINDS="$T_TMP/kinds-session24h.tsv"
awk 'BEGIN { FS = OFS = "\t" } $1 == "session" { $4 = "24h" } { print }' "$REAL_KINDS" > "$KINDS"
W="$T_TMP/w"; EV="$W/ev"; OB="$W/ob"; CACHE="$W/cache"; MUTD="$T_TMP/mut"; D=2026-10-07.jsonl; N=0; AT=2026-10-07T03:00:00Z
mkdir -p "$MUTD"

fresh() { rm -rf "$W"; mkdir -p "$EV" "$OB" "$CACHE"; N=0; AT=2026-10-07T03:00:00Z; }
ev() { # <ts> <kind> <subject> [data-json]
  N=$((N + 1))
  printf '{"id":"e%s","ts":"%s","src":"cli","kind":"%s","subject":"%s","repo":"harbor","cause":"","data":%s}\n' "$N" "$1" "$2" "$3" "${4:-$EMPTY}" >> "$EV/$D"
}
ob() { # <script> <mode…> — the real or broken script on this bus and this state, stdout and stderr together
  _s="$1"; shift
  env HARBOR_EVENT_DIR="$EV" HARBOR_OBLIGATION_DIR="$OB" HARBOR_SCOPE_CACHE_DIR="$CACHE" HARBOR_STATUS_OBLIGATION_NOW="$AT" \
    HARBOR_STATUS_OBLIGATION_KINDS="$KINDS" HARBOR_STATUS_OBLIGATION_ON_OVERDUE=off sh "$_s" "$@" 2>&1
}
obq() { _s="$1"; shift; ob "$_s" "$@" 2>/dev/null; }   # stdout only: what a parser sees
epoch() { jq -n -r --arg t "$1" '$t | fromdateiso8601'; }
EMPTY='{}'
BAD=""
chk() { [ "$3" = "$2" ] || BAD="$BAD [$1: want '$2', got '$3']"; }
verdict() { printf '%s' "${BAD:-ok}"; BAD=""; }
# A scratch bin/ of symlinks to the real one, so a broken copy of ONE file still finds its siblings. $MUTD/rp is rebuilt per proof.
farm() { rm -rf "$MUTD/rp"; mkdir -p "$MUTD/rp"; for _f in "$T_ROOT"/bin/*; do ln -s "$_f" "$MUTD/rp/$(basename "$_f")"; done; }
mutate() { # <file> <from> <to> — $MUTD/rp/<name> becomes a copy of <file> with the first <from> replaced
  _mf="$MUTD/rp/$(basename "$1")"; rm -f "$_mf"
  from="$2" to="$3" awk 'BEGIN { RS = "\001"; from = ENVIRON["from"]; to = ENVIRON["to"] } { i = index($0, from); if (i == 0) exit 3; printf "%s%s%s", substr($0, 1, i - 1), to, substr($0, i + length(from)) }' \
    "$1" > "$_mf" || { t_fail "mutation target not found in $(basename "$1"): $2"; return 1; }
  cmp -s "$1" "$_mf" && { t_fail "mutation changed nothing: $2"; return 1; }
  return 0
}
redproof() { # <label> <case function> <file> <from> <to> — the broken copy must not pass the case, and an unbroken copy must
  farm; rm -f "$MUTD/rp/$(basename "$3")"; cp "$3" "$MUTD/rp/$(basename "$3")"; _c="$("$2" "$MUTD/rp/$(basename "$3")")"
  [ "$_c" = ok ] || { t_fail "$1: the control copy, unbroken, fails the case: $_c"; return 0; }
  mutate "$3" "$4" "$5" || return 0
  _v="$("$2" "$MUTD/rp/$(basename "$3")")"
  [ "$_v" != ok ] && t_pass || t_fail "$1: the broken copy still passed"
}

# ── the schema check the console's contract needs: every key, in order, typed; fails when one goes missing ──────────
KEYS_TOP='["generated_ts","sources","obligations","proposals","read_ts"]'
KEYS_ROW='["id","kind","subject","repo","owner","title","link","opened_ts","deadline_ts","state","closed_by","closed_ts","age_s"]'
shape() { # <json on stdin> → yes | no
  jq -e --argjson top "$KEYS_TOP" --argjson row "$KEYS_ROW" '
    (keys_unsorted == $top) and (.generated_ts | type == "string") and (.sources | type == "object") and (.proposals == [])
    and (.obligations | type == "array")
    and all(.obligations[]; (keys_unsorted == $row) and (.age_s | type == "number")
        and ([.id, .kind, .subject, .repo, .owner, .title, .link, .opened_ts, .deadline_ts, .state, .closed_by, .closed_ts] | all(type == "string"))
        and (.state | IN("open", "overdue", "closed", "abandoned")))
    and all(.sources[]; (keys_unsorted == ["ok", "reason", "ts"]) and (.ok | type == "boolean"))' >/dev/null 2>&1 && echo yes || echo no
}

# One bus: an old session (overdue by 26h at $AT), a PR (open, the oldest live row), a new agent, a background tool that closed.
scenario() {
  fresh
  ev 2026-10-05T01:00:00Z session.start S1 '{"title":"harbor night"}'
  ev 2026-10-04T10:00:00Z pr.opened VytCepas/harbor#9 '{"title":"fold the bus","link":"https://github.com/VytCepas/harbor/pull/9"}'
  ev 2026-10-07T01:00:00Z agent.spawn A1 '{"title":"review lane"}'
  ev 2026-10-07T01:10:00Z tool.background.start S2:T1 '{"tool":"Monitor"}'
  ev 2026-10-07T01:20:00Z tool.background.done S2:T1
}

case_shape() { _x="$1"; scenario
  printf '{"gh-pr":{"ok":false,"reason":"exited 1","ts":"2026-10-07T02:55:00Z"},"sweep":{"ok":true,"reason":"","ts":"2026-10-07T02:55:00Z"}}\n' > "$OB/sources.json"
  ob "$_x" fold >/dev/null
  _j="$(obq "$_x" show --json)"
  chk "the output is the frozen shape" yes "$(printf '%s' "$_j" | shape)"
  chk "generated_ts is the fold's clock (here the same instant as the read)" "$AT" "$(printf '%s' "$_j" | jq -r '.generated_ts')"
  chk "read_ts is the read's clock" "$AT" "$(printf '%s' "$_j" | jq -r '.read_ts')"
  chk "every ledger row is listed, closed ones too" 4 "$(printf '%s' "$_j" | jq '.obligations | length')"
  chk "age_s is counted at read from opened_ts (S1: 2d2h)" 180000 "$(printf '%s' "$_j" | jq '.obligations[] | select(.id == "session:S1") | .age_s')"
  chk "an overdue row keeps its state" overdue "$(printf '%s' "$_j" | jq -r '.obligations[] | select(.id == "session:S1") | .state')"
  chk "sources come from sources.json, verbatim" '{"gh-pr":{"ok":false,"reason":"exited 1","ts":"2026-10-07T02:55:00Z"},"sweep":{"ok":true,"reason":"","ts":"2026-10-07T02:55:00Z"}}' "$(printf '%s' "$_j" | jq -c '.sources')"
  chk "proposals is empty until #1052" '[]' "$(printf '%s' "$_j" | jq -c '.proposals')"
  # a row the fold wrote with keys missing still comes out whole: the console reads ONLY this shape
  printf '{"generated_ts":"x","obligations":[{"id":"pr:o/r#1","kind":"pr","subject":"o/r#1","state":"open","opened_ts":"2026-10-07T01:00:00Z"}]}\n' > "$OB/current.json"
  chk "a row missing keys is defaulted, not passed through short" yes "$(obq "$_x" show --json | shape)"
  rm -f "$OB/current.json"
  chk "an absent ledger is the empty shape, exit 0" yes "$(obq "$_x" show --json | shape)"
  verdict
}

case_receipt() { _x="$1"
  scenario; ob "$_x" fold >/dev/null; _r="$CACHE/checks/status.obligations.json"
  chk "26h overdue: the receipt is red" red "$(jq -r '.status' "$_r" 2>/dev/null)"
  chk "named for its dotted id" status.obligations "$(jq -r '.id' "$_r" 2>/dev/null)"
  chk "over the id of the row, never a count" '["session:S1"]' "$(jq -c '.subjects' "$_r" 2>/dev/null)"
  chk "the statusline cache says one overdue" 1 "$(jq '.overdue' "$CACHE/status-obligations.json" 2>/dev/null)"
  chk "and counts the live rows (S1, the PR, the agent)" 3 "$(jq '.live' "$CACHE/status-obligations.json" 2>/dev/null)"
  chk "the cache holds the epoch the oldest overdue row opened, not an age" "$(epoch 2026-10-05T01:00:00Z)" "$(jq '.overdue_since' "$CACHE/status-obligations.json" 2>/dev/null)"
  scenario; AT=2026-10-07T00:59:00Z; ob "$_x" fold >/dev/null
  chk "23h59m overdue: overdue, but not yet the finding" green "$(jq -r '.status' "$_r" 2>/dev/null)"
  chk "the alarm half still counts it" 1 "$(jq '.overdue' "$CACHE/status-obligations.json" 2>/dev/null)"
  scenario; AT=2026-10-07T01:01:00Z; ob "$_x" fold >/dev/null
  chk "24h01m overdue: red" red "$(jq -r '.status' "$_r" 2>/dev/null)"
  ev 2026-10-07T01:30:00Z session.stop S1; AT=2026-10-07T01:31:00Z; ob "$_x" fold >/dev/null
  chk "closing the row turns the receipt green again" green "$(jq -r '.status' "$_r" 2>/dev/null)"
  verdict
}

# The statusline, driven from a cache a person could write by hand: one case per state the ticket names.
GC="$T_TMP/gcache"; GCFG="$T_TMP/gcfg"; mkdir -p "$GC" "$GCFG/bin" "$GCFG/cache" "$T_TMP/notrepo"
ESC="$(printf '\033')"
glyph() { # <script> — the whole statusline, colour stripped
  printf '%s' '{"workspace":{"current_dir":"'"$T_TMP"'/notrepo"}}' \
    | env CLAUDE_CONFIG_DIR="$GCFG" HARBOR_SCOPE_CACHE_DIR="$GC" HARBOR_TEST_NOW="$GNOW" HARBOR_GLYPH_MACHINE=0 HARBOR_STATUS_GLYPH_COLS=200 sh "$1" 2>/dev/null \
    | sed "s/${ESC}\\[[0-9]*m//g"
}
gset() { printf '%s\n' "$1" > "$GC/status-obligations.json"; }   # <cache json>
has() { case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac; }
GNOW="$(epoch 2026-10-07T03:00:00Z)"
case_glyph() { _x="$1"; rm -f "$GC/status-obligations.json"
  _o="$(glyph "$_x")"
  chk "an absent cache renders nothing (no ⧗)" no "$(has "$_o" '⧗')"
  chk "an absent cache renders no OVERDUE" no "$(has "$_o" 'OVERDUE')"
  gset "{\"at\":$((GNOW - 60)),\"live\":3,\"overdue\":0,\"overdue_since\":0,\"unread\":false}"; _o="$(glyph "$_x")"
  chk "three open rows render no count: the ⧗ tile left the line 2026-10-16" no "$(has "$_o" '⧗')"
  chk "and no alarm while none is overdue" no "$(has "$_o" 'OVERDUE')"
  gset "{\"at\":$((GNOW - 60)),\"live\":5,\"overdue\":2,\"overdue_since\":$((GNOW - 3 * 86400)),\"unread\":false}"; _o="$(glyph "$_x")"
  chk "overdue rows: the alarm with the age of the oldest, counted at print time" yes "$(has "$_o" 'OVERDUE 2 ·3d')"
  chk "on the YOU row" yes "$(has "$_o" 'OVERDUE 2 ·3d')"
  gset "{\"at\":$((GNOW - 60)),\"live\":1,\"overdue\":1,\"overdue_since\":$((GNOW - 5400)),\"unread\":false}"; _o="$(glyph "$_x")"
  chk "an age under a day is in hours" yes "$(has "$_o" 'OVERDUE 1 ·1h')"
  gset "{\"at\":$((GNOW - 60)),\"live\":1,\"overdue\":1,\"overdue_since\":$((GNOW - 600)),\"unread\":false}"; _o="$(glyph "$_x")"
  chk "an age under an hour is in minutes" yes "$(has "$_o" 'OVERDUE 1 ·10m')"
  gset "{\"at\":$((GNOW - 901)),\"live\":5,\"overdue\":2,\"overdue_since\":$((GNOW - 3 * 86400)),\"unread\":false,\"you\":[{\"k\":\"intent\",\"o\":false,\"t\":\"o/r#9\"}]}"; _o="$(glyph "$_x")"
  chk "a cache over 900s old claims no alarm" no "$(has "$_o" 'OVERDUE')"
  chk "and no queue" no "$(has "$_o" 'o/r#9')"
  gset "{\"at\":$((GNOW - 60)),\"live\":5,\"overdue\":1,\"overdue_since\":$((GNOW - 7200)),\"unread\":true}"; _o="$(glyph "$_x")"
  chk "an overdue row is in the ledger whatever a source said: OVERDUE still shows" yes "$(has "$_o" 'OVERDUE 1 ·2h')"
  printf 'not json\n' > "$GC/status-obligations.json"; _o="$(glyph "$_x")"
  chk "a malformed cache renders nothing" no "$(has "$_o" 'OVERDUE')"
  gset "{\"at\":$((GNOW - 60)),\"live\":2,\"overdue\":0,\"overdue_since\":0,\"unread\":false,\"you\":[{\"k\":\"pr\",\"o\":false,\"t\":\"o/r#9\"},{\"k\":\"intent\",\"o\":true,\"t\":\"run cleanup\"}]}"; _o="$(glyph "$_x")"
  chk "the queue is the YOU row: the handoff" yes "$(has "$_o" 'run cleanup')"
  chk "and never a PR (several agents, several PRs)" no "$(has "$_o" 'o/r#9')"
  gset "{\"at\":$((GNOW - 60)),\"live\":2,\"overdue\":1,\"overdue_since\":$((GNOW - 7200)),\"unread\":false,\"you\":[{\"k\":\"intent\",\"o\":true,\"t\":\"run cleanup\"}]}"
  _raw="$(printf '%s' '{"workspace":{"current_dir":"'"$T_TMP"'/notrepo"}}' | env CLAUDE_CONFIG_DIR="$GCFG" HARBOR_SCOPE_CACHE_DIR="$GC" HARBOR_TEST_NOW="$GNOW" HARBOR_GLYPH_MACHINE=0 HARBOR_STATUS_GLYPH_COLS=200 sh "$_x" 2>/dev/null)"
  chk "the overdue alarm is yellow" yes "$(has "$_raw" "${ESC}[33mOVERDUE 1")"
  chk "an overdue handoff is red" yes "$(has "$_raw" "${ESC}[31mrun cleanup")"
  rm -f "$GC/status-obligations.json"
  verdict
}

# `harbor status obligations` is routed by bin/harbor, so the front door is what is asked, not the script behind it.
case_route() { _d="$1"; scenario; ob "$BIN" fold >/dev/null
  _h() { env HARBOR_SCOPE_BIN="$_d" HARBOR_OBLIGATION_DIR="$OB" HARBOR_SCOPE_CACHE_DIR="$CACHE" HARBOR_STATUS_OBLIGATION_NOW="$AT" sh "$_d/harbor" "$@" 2>/dev/null; }
  chk "harbor status obligations --json is the ledger's shape" yes "$(_h status obligations --json | shape)"
  chk "and equals the script's own --json" "$(obq "$BIN" show --json)" "$(_h status obligations --json)"
  chk "--print goes the same way" "$(obq "$BIN" show --print)" "$(_h status obligations --print)"
  _rc=0; _h status obligations --since banana >/dev/null || _rc=$?
  chk "a bad --since is a usage error, exit 2" 2 "$_rc"
  chk "harbor status without the sub-verb is still status-generate.sh" yes "$(has "$(_h status --help)" 'generate docs/generated/status.md')"
  verdict
}

# The dotted id: written by log_receipt, read by lint-findings.sh (file name = id), lint FL1 (lanes keys) and lint X9 (the register).
case_dotted_receipt() { _l="$1"; rm -rf "$W/lib"; mkdir -p "$W/lib"
  ( . "$_l"; log_receipt "$W/lib" status.obligations red 'session:S1' ) 2>/dev/null; chk "log_receipt writes <id>.json for a dotted id" yes "$([ -s "$W/lib/status.obligations.json" ] && echo yes || echo no)"
  for _bad in .hidden a..b trailing. a/b A.b ''; do
    rm -f "$W/lib"/*.json; ( . "$_l"; log_receipt "$W/lib" "$_bad" red x ) 2>/dev/null && _okc=yes || _okc=no
    chk "log_receipt refuses the id '$_bad'" no "$_okc"
  done
  verdict
}
case_findings() { _f="$1"; scenario; ob "$BIN" fold >/dev/null
  rm -rf "$RCD"; mkdir -p "$RCD"; cp "$CACHE/checks/status.obligations.json" "$RCD/"
  : > "$GH_LOG"; rm -f "$GH_STATE"
  records "$TMP/c1" lint.long-file-reason -- lint.long-file-reason:bin/big.sh
  _o="$(HARBOR_SCOPE_ROOT="$PUB" HARBOR_LINT_FINDINGS_NOW="$(date -u +%F)" GH_NOW="$(date -u +%F)" sh "$_f" reconcile --from "$TMP/c1" --apply 2>&1)"
  chk "lint-findings.sh files the dotted id from its receipt" yes "$(has "$_o" 'check/status.obligations (1 subject(s))')"
  chk "and does not refuse it as a receipt with no row" no "$(has "$_o" 'receipt with no docs/reference/checks.md row')"
  chk "the issue exists, open, keyed by the id" "OPEN" "$(jq -r '[.issues[] | select(.body | contains("key=check/status.obligations "))][0].state' "$GH_STATE" 2>/dev/null)"
  chk "its subject is the row id" yes "$(has "$(jq -r '[.issues[] | select(.body | contains("key=check/status.obligations "))][0].body' "$GH_STATE" 2>/dev/null)" 'session:S1')"
  verdict
}
case_lint() { _l="$1"; _lr="$W/lintroot"; rm -rf "$_lr"; mkdir -p "$_lr/contracts" "$_lr/bin" "$_lr/launchd"
  cp "$T_ROOT/contracts/finding.md" "$_lr/contracts/"; mkdir -p "$_lr/docs/reference"; cp "$T_ROOT/docs/reference/checks.md" "$_lr/docs/reference/"; : > "$_lr/bin/skill-catalog.sh"; : > "$_lr/bin/memory-route.sh"
  awk '/^<!-- lanes:end -->$/ { print "| PROPOSE | `check/status.obligations` | `*` | `-` | #1050 |" } { print }' "$_lr/contracts/finding.md" > "$_lr/f.md" && mv "$_lr/f.md" "$_lr/contracts/finding.md"
  _o="$(HARBOR_SCOPE_ROOT="$_lr" sh "$_l" --only FL1 2>&1)"
  chk "FL1 joins a lanes key check/status.obligations to its docs/reference/checks.md row" no "$(has "$_o" 'names no docs/reference/checks.md row')"
  _x9="$W/x9"; rm -rf "$_x9"; mkdir -p "$_x9/bin" "$_x9/launchd" "$_x9/docs/reference"
  printf '# Register\n\n| id | watches | schedule | notifies | red means |\n|---|---|---|---|---|\n| `status.obligations` | w | daily 09:00 | n | r |\n' > "$_x9/docs/reference/checks.md"
  _o="$(HARBOR_SCOPE_ROOT="$_x9" sh "$_l" --only X9 2>&1)"
  chk "X9 reads the dotted row: a launchd row with no plist is named" yes "$(has "$_o" 'com.harbor.status.obligations.plist')"
  verdict
}

# ── the sections ─────────────────────────────────────────────────────────────────────────────────────────────────
t_section "--json: the frozen shape, every key, in order, defaulted; age_s at read; sources from sources.json"
t_eq "the case passes on the real script" ok "$(case_shape "$BIN")"
t_eq "the shape check itself fails when a key goes missing" no "$(scenario; ob "$BIN" fold >/dev/null; obq "$BIN" show --json | jq 'del(.obligations[0].link)' | shape)"
t_eq "and when a key moves" no "$(obq "$BIN" show --json | jq '.obligations[0] |= (to_entries | reverse | from_entries)' | shape)"
t_eq "and when a top-level key goes missing" no "$(obq "$BIN" show --json | jq 'del(.proposals)' | shape)"
t_eq "and when a source loses its reason" no "$(obq "$BIN" show --json | jq '.sources = {"x": {"ok": true, "ts": "t"}}' | shape)"
redproof "--json: a row without its link key" case_shape "$BIN" 'title: (.title // ""), link: (.link // ""),' 'title: (.title // ""),'
redproof "--json: proposals dropped" case_shape "$BIN" 'proposals: [], read_ts: $nowiso}' 'read_ts: $nowiso}'
redproof "--json: read_ts dropped" case_shape "$BIN" 'proposals: [], read_ts: $nowiso}' 'proposals: []}'
redproof "--json: age_s counted from the wrong end" case_shape "$BIN" '[0, ($now - ts(.opened_ts))] | max' '[0, (ts(.opened_ts) - $now)] | max'

# A stale current.json read three days after its fold: it must say how old it is, and an expired row must not read as healthy (harbor#1115).
case_stale_read() { _x="$1"; scenario; ob "$_x" fold >/dev/null
  AT=2026-10-10T03:00:00Z   # three days on, and nothing has folded since
  _j="$(obq "$_x" show --json)"
  chk "generated_ts is still the fold's own clock, three days old" 2026-10-07T03:00:00Z "$(printf '%s' "$_j" | jq -r '.generated_ts')"
  chk "read_ts is the read's clock" "$AT" "$(printf '%s' "$_j" | jq -r '.read_ts')"
  chk "the fold stored the PR open" open "$(jq -r '.obligations[] | select(.id == "pr:VytCepas/harbor#9") | .state' "$OB/current.json")"
  chk "a PR whose deadline passed is read as overdue" overdue "$(printf '%s' "$_j" | jq -r '.obligations[] | select(.id == "pr:VytCepas/harbor#9") | .state')"
  chk "so is the agent" overdue "$(printf '%s' "$_j" | jq -r '.obligations[] | select(.id == "agent:A1") | .state')"
  chk "a closed row stays closed" closed "$(printf '%s' "$_j" | jq -r '.obligations[] | select(.id == "tool.background:S2:T1") | .state')"
  chk "the shape is still the frozen one" yes "$(printf '%s' "$_j" | shape)"
  chk "--print counts the expired rows too (S1, the PR, the agent)" yes "$(has "$(obq "$_x" show --print | sed -n 1p)" ' 3 overdue ')"
  AT=2026-10-07T03:00:00Z
  verdict
}
# A healthy session alive for more than a day, against the REAL register: not overdue, receipt green (harbor#1115).
case_long_session() { _x="$1"; fresh
  ev 2026-10-05T01:00:00Z session.start S1 '{"title":"harbor night"}'   # 26h old at $AT
  printf '#!/bin/sh\nprintf '"'"'[{"sessionId":"S1","pid":1}]'"'"'\n' > "$W/sessions.sh"; chmod +x "$W/sessions.sh"
  _go() { # <register> <mode>
    env HARBOR_EVENT_DIR="$EV" HARBOR_OBLIGATION_DIR="$OB" HARBOR_SCOPE_CACHE_DIR="$CACHE" HARBOR_STATUS_OBLIGATION_NOW="$AT" HARBOR_STATUS_OBLIGATION_KINDS="$1" \
      HARBOR_STATUS_OBLIGATION_SESSIONS="$W/sessions.sh" HARBOR_STATUS_OBLIGATION_GH="$W/none" HARBOR_STATUS_OBLIGATION_CLAUDE="$W/none" \
      HARBOR_STATUS_OBLIGATION_HOUSEKEEPING="$W/none.jsonl" sh "$_x" "$2" >/dev/null 2>&1
  }
  _go "$REAL_KINDS" reconcile
  chk "a session both sources say is alive, 26h old, is open" open "$(jq -r '.obligations[] | select(.id == "session:S1") | .state' "$OB/current.json")"
  chk "it has no deadline" "" "$(jq -r '.obligations[] | select(.id == "session:S1") | .deadline_ts' "$OB/current.json")"
  chk "the receipt stays green" green "$(jq -r '.status' "$CACHE/checks/status.obligations.json" 2>/dev/null)"
  chk "and the cache counts nothing overdue" 0 "$(jq '.overdue' "$CACHE/status-obligations.json" 2>/dev/null)"
  rm -rf "$OB" "$CACHE"; mkdir -p "$OB" "$CACHE"; _go "$KINDS" reconcile   # the control: the old 24h register
  chk "CONTROL: under the old 24h register the same session is overdue" overdue "$(jq -r '.obligations[] | select(.id == "session:S1") | .state' "$OB/current.json")"
  chk "CONTROL: and the receipt is red, which is what filed a finding for a working session" red "$(jq -r '.status' "$CACHE/checks/status.obligations.json" 2>/dev/null)"
  verdict
}
t_section "a stale current.json: generated_ts is the fold's, an expired row reads overdue (harbor#1115)"
t_eq "the case passes on the real script" ok "$(case_stale_read "$BIN")"
redproof "stale read: generated_ts back to the read's clock" case_stale_read "$BIN" 'generated_ts: (.generated_ts // $nowiso)' 'generated_ts: $nowiso'
redproof "stale read: an expired open row not re-derived" case_stale_read "$BIN" '| . + {state: (if .state == "open" and ts(.deadline_ts) > 0 and ts(.deadline_ts) < $now then "overdue" else .state end)}' '| . + {}'
t_eq "the fixture register differs from the real one in exactly the session deadline" 1 "$(diff "$REAL_KINDS" "$KINDS" | grep -c '^<')"

t_section "a session has no deadline: alive for 26h is not overdue, the receipt stays green (harbor#1115)"
t_eq "the case passes against the real register" ok "$(case_long_session "$BIN")"

t_section "--since: opened or changed within the window, from the ledger's last transition"
scenario; ob "$BIN" fold >/dev/null
_ids() { printf '%s' "$1" | jq -r '[.obligations[].id] | sort | join(",")'; }
t_eq "30m: only what changed in it (the fold stamped S1 overdue at 03:00)" "session:S1" "$(_ids "$(obq "$BIN" show --json --since 30m)")"
t_eq "2h: adds the agent opened at 01:00 and the tool" "agent:A1,session:S1,tool.background:S2:T1" "$(_ids "$(obq "$BIN" show --json --since 2h)")"
t_eq "10d: everything" "agent:A1,pr:VytCepas/harbor#9,session:S1,tool.background:S2:T1" "$(_ids "$(obq "$BIN" show --json --since 10d)")"
t_eq "the filtered output keeps the shape" yes "$(obq "$BIN" show --json --since 30m | shape)"
t_exit "a malformed window is exit 2" 2 env HARBOR_OBLIGATION_DIR="$OB" sh "$BIN" show --since 3x
t_exit "a missing window is exit 2" 2 env HARBOR_OBLIGATION_DIR="$OB" sh "$BIN" show --since
t_exit "an unknown flag is exit 2" 2 env HARBOR_OBLIGATION_DIR="$OB" sh "$BIN" show --census

t_section "--print: overdue, then new, then oldest; a short view, never every row"
_p="$(obq "$BIN" show --print)"
_l1="$(printf '%s\n' "$_p" | sed -n 1p)"
t_has "line one is the delta and the live count" "$_l1" "1 overdue · 1 new · 1 closed · 0 abandoned · 3 live"
_io="$(printf '%s\n' "$_p" | grep -n '^OVERDUE' | cut -d: -f1)"; _in="$(printf '%s\n' "$_p" | grep -n '^NEW' | cut -d: -f1)"; _id="$(printf '%s\n' "$_p" | grep -n '^OLDEST OPEN' | cut -d: -f1)"
t_eq "overdue comes before new, new before oldest" yes "$([ "$_io" -lt "$_in" ] && [ "$_in" -lt "$_id" ] && echo yes || echo no)"
t_has "an overdue row carries how long, and its owner" "$_p" "session:S1  26h over · session:S1  harbor night"
t_has "the oldest open row carries its age" "$_p" "pr:VytCepas/harbor#9  2d old  fold the bus"
t_hasnt "a closed row is counted, not listed" "$_p" "tool.background:S2:T1"
jq -n -c '{generated_ts: "x", obligations: [range(0; 60) | {id: "pr:o/r#\(.)", kind: "pr", subject: "o/r#\(.)", owner: "operator", title: "t\(.)", opened_ts: "2026-09-01T00:00:00Z", deadline_ts: (if . < 20 then "2026-09-04T00:00:00Z" else "2026-12-01T00:00:00Z" end), state: (if . < 20 then "overdue" else "open" end), closed_by: "", closed_ts: ""}]}' > "$OB/current.json"
_p="$(obq "$BIN" show --print)"
t_eq "sixty rows print as a screenful, not sixty lines (got $(printf '%s\n' "$_p" | wc -l | tr -d ' '))" yes "$([ "$(printf '%s\n' "$_p" | wc -l | tr -d ' ')" -le 25 ] && echo yes || echo no)"
t_has "and say how many more there are" "$_p" "… and 12 more overdue"
t_has "the oldest open section is capped too" "$_p" "… and 35 more open"
printf '{"gh-pr":{"ok":false,"reason":"exited 1","ts":"t"},"sweep":{"ok":true,"reason":"","ts":"t"}}\n' > "$OB/sources.json"
t_has "a source that did not answer is named, with its reason" "$(obq "$BIN" show --print)" "NO ANSWER FROM: gh-pr (exited 1)"
rm -f "$OB/current.json" "$OB/sources.json"
t_has "an absent ledger says so and exits 0" "$(obq "$BIN" show --print)" "no obligations ledger"
t_exit "and exits 0" 0 env HARBOR_OBLIGATION_DIR="$OB" sh "$BIN" show --print
printf '{"generated_ts":"x","obligations":[]}\n' > "$OB/current.json"
t_has "an empty ledger says nothing is live" "$(obq "$BIN" show --print)" "nothing live, nothing new"
printf '{"generated_ts":"x","obligations":[{"id":"pr:o/r#1","kind":"pr","subject":"o/r#1","state":"open","opened_ts":"2026-10-07T02:00:00Z","title":"a\\u001b[31mred\\u0007"}]}\n' > "$OB/current.json"
t_eq "a control byte in a title never reaches the terminal" 0 "$(obq "$BIN" show --print | grep -c "$ESC")"

t_section "the receipt: red over the ids of rows more than 24h overdue, green otherwise; the cache the statusline reads"
t_eq "the case passes on the real script" ok "$(case_receipt "$BIN")"
redproof "receipt: the 24h line moved to ten days" case_receipt "$BIN" 'RED_AFTER_S=86400' 'RED_AFTER_S=864000'
redproof "receipt: red names no row" case_receipt "$BIN" 'status.obligations red "$@"' 'status.obligations green'
redproof "cache: the overdue epoch dropped" case_receipt "$BIN" 'overdue_since: ([$od[] | ts(.opened_ts)] | min // 0)' 'overdue_since: 0'
scenario; : > "$W/notdir"; _rc=0
_o="$(env HARBOR_EVENT_DIR="$EV" HARBOR_OBLIGATION_DIR="$OB" HARBOR_SCOPE_CACHE_DIR="$W/notdir/c" HARBOR_STATUS_OBLIGATION_NOW="$AT" HARBOR_STATUS_OBLIGATION_KINDS="$KINDS" HARBOR_STATUS_OBLIGATION_ON_OVERDUE=off sh "$BIN" fold 2>&1)" || _rc=$?
t_eq "a fold that cannot write its cache still exits 0" 0 "$_rc"
t_has "and says so" "$_o" "no statusline cache or receipt written"

t_section "the statusline: OVERDUE N ·age and the operator queue on YOU; nothing from a stale, absent or malformed cache"
t_eq "the case passes on the real glyph" ok "$(case_glyph "$T_ROOT/bin/status-fleet-glyph.sh")"
redproof "glyph: the staleness ceiling removed" case_glyph "$T_ROOT/bin/status-fleet-glyph.sh" '($now - $at) > 900 then "⧗?", "", ""' '($now - $at) > 9000000 then "⧗?", "", ""'
redproof "glyph: the queue dropped" case_glyph "$T_ROOT/bin/status-fleet-glyph.sh" 'OBLTOK="$_ol"; YOUQ="$_oq"' 'OBLTOK="$_ol"; YOUQ=""'
redproof "glyph: an overdue item not told apart" case_glyph "$T_ROOT/bin/status-fleet-glyph.sh" 'def col($o): if $o == true then $red' 'def col($o): if false then $red'
redproof "glyph: the overdue alarm dropped" case_glyph "$T_ROOT/bin/status-fleet-glyph.sh" '[ -n "$OBLTOK" ] && alarm "$OBLTOK"' ':'
redproof "glyph: the age counted from the wrong epoch" case_glyph "$T_ROOT/bin/status-fleet-glyph.sh" '(($now - $since) | if . < 3600' '((0 - $since) | if . < 3600'

t_section "an end to end: a fold writes the cache, and the statusline reads that file"
scenario; ev 2026-10-07T02:00:00Z obligation.open handoff-cleanup '{"title":"run cleanup.sh"}'
ob "$BIN" fold >/dev/null; cp "$CACHE/status-obligations.json" "$GC/status-obligations.json"
t_has "oldest overdue row opened 2d ago renders OVERDUE 1 ·2d, the age counted at print time" "$(glyph "$T_ROOT/bin/status-fleet-glyph.sh")" "OVERDUE 1 ·2d"
t_eq "the cache lists what the operator acts on: the handoff, and no PR" '[{"k":"intent","o":false,"t":"run cleanup.sh"}]' "$(jq -c '.you' "$CACHE/status-obligations.json")"
t_has "and the YOU row reads them" "$(glyph "$T_ROOT/bin/status-fleet-glyph.sh")" "run cleanup.sh │ OVERDUE 1 ·2d"
t_hasnt "a session row is not the operator's" "$(jq -c '.you' "$CACHE/status-obligations.json")" 'S1'
rm -f "$GC/status-obligations.json"

t_section "harbor status obligations: routed inside bin/harbor, so the verb table and CLI1 are untouched"
t_eq "the case passes through the real dispatcher" ok "$(case_route "$T_ROOT/bin")"
farm; mutate "$T_ROOT/bin/harbor" '"${1:-}" = obligations ]' '"${1:-}" = obligations-off ]' && t_eq "red-proof: with the route broken the case fails" no "$([ "$(case_route "$MUTD/rp")" = ok ] && echo yes || echo no)"
farm; t_eq "control: the farm of unbroken symlinks passes the same case" ok "$(case_route "$MUTD/rp")"
t_eq "bin/harbor's verb table has no obligations verb" 0 "$(grep -c '^obligations	' "$T_ROOT/bin/harbor" | tr -d ' ')"

t_section "the dotted id status.obligations is SEEN by every reader that must see it"
t_eq "log_receipt writes a dotted id and refuses a path-shaped one" ok "$(case_dotted_receipt "$T_ROOT/bin/library-log.sh")"
redproof "log_receipt: dots refused" case_dotted_receipt "$T_ROOT/bin/library-log.sh" '*[!abcdefghijklmnopqrstuvwxyz0-9.-]*) return 1' '*[!abcdefghijklmnopqrstuvwxyz0-9-]*) return 1'
redproof "log_receipt: a leading dot allowed" case_dotted_receipt "$T_ROOT/bin/library-log.sh" "''|.*|*..*|*.|" "''|"
t_eq "lint-findings.sh files check/status.obligations from the receipt the fold wrote" ok "$(case_findings "$T_ROOT/bin/lint-findings.sh")"
redproof "lint-findings.sh: the docs/reference/checks.md reader without the dot" case_findings "$T_ROOT/bin/lint-findings.sh" '/^\| `[a-z0-9.-]+` \|/ { id = $2;' '/^\| `[a-z0-9-]+` \|/ { id = $2;'
t_eq "lint FL1 and X9 read the dotted row" ok "$(case_lint "$T_ROOT/bin/lint-conventions.sh")"
redproof "lint FL1: the row reader without the dot" case_lint "$T_ROOT/bin/lint-conventions.sh" "_fl1chk=\" \$(sed -n 's/^| \`\\([a-z0-9.-]*\\)\` |.*/\\1/p'" "_fl1chk=\" \$(sed -n 's/^| \`\\([a-z0-9-]*\\)\` |.*/\\1/p'"
redproof "lint X9: the row reader without the dot" case_lint "$T_ROOT/bin/lint-conventions.sh" '  /^\| `[a-z0-9.-]+` \|/ {
    id = $2; gsub(/[` ]/, "", id)
    if (NF != 7)' '  /^\| `[a-z0-9-]+` \|/ {
    id = $2; gsub(/[` ]/, "", id)
    if (NF != 7)'
t_eq "the register row itself exists, with its five cells and its disable command" yes "$(grep '^| `status.obligations` |' "$T_ROOT/docs/reference/checks.md" | awk -F'|' 'NF == 7 && $6 ~ /Disable:/ && $5 ~ /OVERDUE/ { print "yes" }')"
t_eq "and has its Platforms row" 1 "$(grep -c '^| status.obligations | inherits' "$T_ROOT/docs/reference/checks.md" | tr -d ' ')"

t_done
