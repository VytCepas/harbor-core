#!/usr/bin/env sh
# The env renames of harbor#1097 (renames.tsv wave W5e): both names were read until 2026-11-15, and from then on only the new
# one is. The audit stream and the event hand-off are probed with each spelling alone, so a reader that still honours an old
# name is red; then every W5e row is held structurally.
. "$(dirname "$0")/../../lib/core.sh"; t_init
HERE="$T_ROOT/bin"; . "$HERE/library-log.sh"; log_init env-window-test; . "$HERE/audit-stream-lib.sh"
DAY="$(date -u +%Y-%m-%d)"
RN="$T_ROOT/standards/naming/renames.tsv"
# old <new>: the retired spelling of <new>, read from the register so no retired name is spelled here (lint.name-ratchet)
old() { awk -F'\t' -v n="env:$1" '$3 == n && $4 == "env" { sub(/^env:/, "", $2); print $2; exit }' "$RN"; }
unset HARBOR_AUDIT_STREAM_SINK HARBOR_AUDIT_STREAM_WRITER HARBOR_AUDIT_STREAM_SESSION HARBOR_AUDIT_STREAM_REPO_NAME HARBOR_AUDIT_STREAM_CAUSE \
  HARBOR_AUDIT_STREAM_STRICT HARBOR_EVENT_JSON
for _v in HARBOR_AUDIT_STREAM_SINK HARBOR_AUDIT_STREAM_WRITER HARBOR_AUDIT_STREAM_SESSION HARBOR_AUDIT_STREAM_REPO_NAME \
  HARBOR_AUDIT_STREAM_CAUSE HARBOR_AUDIT_STREAM_STRICT HARBOR_EVENT_JSON; do _o="$(old "$_v")"; [ -n "$_o" ] && unset "$_o"; done
OLD_EVENT="$(old HARBOR_EVENT_JSON)"

# emit <sink-var> <writer-var> <session-var> <repo-var> <cause-var> <dir>: one line written with the five names given, in a subshell
emit() {
  ( export "$1=$6/sink" "$2=w1" "$3=s1" "$4=acme/api" "$5=because"; harbor_emit window '{"k":1}' ) >/dev/null 2>&1
  jq -c '[.src, .sess, .repo, .cause]' "$6/sink/window/$DAY/w1.s1.jsonl" 2>/dev/null
}
t_section "audit stream: the NEW names alone"
mkdir -p "$T_TMP/new"
t_eq "sink, writer, session, repo and cause are all read" '["w1","s1","acme/api","because"]' \
  "$(emit HARBOR_AUDIT_STREAM_SINK HARBOR_AUDIT_STREAM_WRITER HARBOR_AUDIT_STREAM_SESSION HARBOR_AUDIT_STREAM_REPO_NAME HARBOR_AUDIT_STREAM_CAUSE "$T_TMP/new")"
t_section "audit stream: the OLD names alone are no longer read (window closed 2026-11-15)"
mkdir -p "$T_TMP/old"
t_eq "the five retired spellings write nothing" "" \
  "$(emit "$(old HARBOR_AUDIT_STREAM_SINK)" "$(old HARBOR_AUDIT_STREAM_WRITER)" "$(old HARBOR_AUDIT_STREAM_SESSION)" "$(old HARBOR_AUDIT_STREAM_REPO_NAME)" "$(old HARBOR_AUDIT_STREAM_CAUSE)" "$T_TMP/old")"

strict() { # <var>: the exit of an emit that cannot write, with <var>=1
  ( export HARBOR_AUDIT_STREAM_SINK="$T_TMP/ro/sink"; export "$1=1"; harbor_emit window 'not json' >/dev/null 2>&1; echo $? )
}
mkdir -p "$T_TMP/ro"
t_eq "a failed write spills and returns 0 by default" 0 "$( ( export HARBOR_AUDIT_STREAM_SINK="$T_TMP/ro/sink"; harbor_emit window 'not json' >/dev/null 2>&1; echo $? ) )"
t_eq "HARBOR_AUDIT_STREAM_STRICT=1 fails the caller" 1 "$(strict HARBOR_AUDIT_STREAM_STRICT)"
t_eq "the retired strict switch no longer does" 0 "$(strict "$(old HARBOR_AUDIT_STREAM_STRICT)")"

EV='{"kind":"session.title","subject":"sess-1","data":{"title":"t"}}'
t_section "the event hand-off: HARBOR_EVENT_JSON only, its retired spelling ignored"
t_eq "the new name is parsed" "session.title sess-1" "$(HARBOR_EVENT_JSON="$EV" sh -c 'HERE=$1; . "$1/session-react-lib.sh"; react_event; echo "$RKIND $RSID"' _ "$HERE" 2>/dev/null)"
t_eq "the old name alone is not parsed" "" "$(env "$OLD_EVENT=$EV" sh -c 'HERE=$1; . "$1/session-react-lib.sh"; react_event && echo "$RKIND $RSID"' _ "$HERE" 2>/dev/null)"
t_eq "an old name beside the new one is ignored" "session.title sess-1" "$(env HARBOR_EVENT_JSON="$EV" "$OLD_EVENT={\"kind\":\"x\",\"subject\":\"other\"}" sh -c 'HERE=$1; . "$1/session-react-lib.sh"; react_event; echo "$RKIND $RSID"' _ "$HERE" 2>/dev/null)"

t_section "every W5e row: a line that names the old name names the new one too"
# A reader that kept the old name alone ("${#OLD}", a `for` list, a message) is the shape that broke the lane check on the first pass.
RN="$T_ROOT/standards/naming/renames.tsv"
awk -F'\t' '$5 == "W5e" && $4 == "env" { o = $2; n = $3; sub(/^env:/, "", o); sub(/^env:/, "", n); print o "\t" n }' "$RN" > "$T_TMP/w5e.tsv"
t_eq "the wave has its 26 rows" 26 "$(grep -c . "$T_TMP/w5e.tsv")"
BAD=""
while IFS='	' read -r _o _n; do
  _l="$(git -C "$T_ROOT" grep -nw -e "$_o" -- bin hooks context-rules tools runners launchd ':!*.test.sh' 2>/dev/null \
    | grep -v -e '^[^:]*:[0-9]*:[[:space:]]*#' | grep -vw -e "$_n" | cut -d: -f1 | sort -u | tr '\n' ' ' || :)"
  [ -z "$_l" ] || BAD="$BAD $_o in $_l"
done < "$T_TMP/w5e.tsv"
t_eq "no code line reads an old name without its new one" "" "${BAD# }"
t_done
