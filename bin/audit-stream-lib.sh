#!/usr/bin/env sh
# audit-stream-lib.sh (harbor#1181 lane 3) — the one append contract, docs/design/telemetry.md. Sourced, never run.
#   harbor_emit <stream> [<attrs-json>]   one envelope line to <root>/<stream>/<UTC day>/<writer>.jsonl
#   stream_verify <file>                  prints every seq gap and broken prev link; silent when the file is whole
# <root> is $HARBOR_SINK, else <cfg>/MEMORY/OBSERVABILITY/<host>/streams. A failed write never exits the caller:
# it spills to <root>/.spill/<stream>.jsonl and counts the drop. HARBOR_EMIT_STRICT=1 (approval and deploy streams,
# contracts/streams.tsv target_on_fail=block) also returns 1, so the caller can refuse the action it was recording.
# Not for the guard path: a guard forks nothing on the hot path, so it keeps floor_log_decision (guard-lib.sh).
# Set HARBOR_EMIT_STRICT in a subshell or export it: `VAR=x harbor_emit` leaks VAR past the call in POSIX sh.

# shasum is perl and missing on minimal Linux; sha256sum is coreutils and missing on macOS: whichever exists
if command -v shasum >/dev/null 2>&1; then stream_sha() { shasum -a 256; }; else stream_sha() { sha256sum; }; fi
STREAM_MAX=4096   # bytes per line, envelope included: one write(), nothing a reader has to reassemble
# Every caller sets HERE to its own bin/ and has sourced library-log.sh (a spill is a log_warn on its run log; a caller
# whose stdout is data sets LOG_FD=2 first). A second source keeps the caller's counts.
[ -n "${_LOG_LIB:-}" ] || . "${HERE:?audit-stream-lib.sh: set HERE to the caller bin/ before sourcing}/library-log.sh"

stream_root() {
  if [ -n "${HARBOR_SINK:-}" ]; then printf '%s\n' "$HARBOR_SINK"; return 0; fi
  _src="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; _srh=""
  { [ -f "$_src/.helm-obs-host" ] && IFS= read -r _srh < "$_src/.helm-obs-host"; } 2>/dev/null || :
  case "$_srh" in ''|*[!A-Za-z0-9-]*) _srh=unknown-host ;; esac
  printf '%s\n' "$_src/MEMORY/OBSERVABILITY/$_srh/streams"
}

# stream_spill <root> <stream> <reason> <line> — the fallback; never fails the caller.
stream_spill() {
  _sp="$1/.spill"
  { mkdir -p "$_sp" && printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$3" "$4" >> "$_sp/$2.jsonl"; } 2>/dev/null || :
  _spn=0; { [ -f "$_sp/$2.dropped" ] && IFS= read -r _spn < "$_sp/$2.dropped"; } 2>/dev/null || :
  case "$_spn" in ''|*[!0-9]*) _spn=0 ;; esac
  printf '%s\n' "$((_spn + 1))" > "$_sp/$2.dropped" 2>/dev/null || :
  log_warn "[check:stream.spill] $2: $3"
  [ "${HARBOR_EMIT_STRICT:-0}" != 1 ]
}

harbor_emit() { # <stream> [<attrs-json>]
  _es="${1:-}"; _ea="${2:-}"; [ -n "$_ea" ] || _ea='{}'
  _er="$(stream_root)"
  case "$_es" in ''|*[!abcdefghijklmnopqrstuvwxyz0-9.-]*|.*) stream_spill "$_er" invalid "bad stream id" "$_es"; return $? ;; esac
  command -v jq >/dev/null 2>&1 || { stream_spill "$_er" "$_es" "jq missing" "$_ea"; return $?; }
  printf '%s' "$_ea" | jq -e 'type == "object"' >/dev/null 2>&1 \
    || { stream_spill "$_er" "$_es" "attrs is not a JSON object" "$_ea"; return $?; }
  _ew="${HARBOR_WRITER:-${0##*/}}.${HARBOR_SESSION:-${CLAUDE_SESSION_ID:-$$}}"
  _ew="$(printf '%s' "$_ew" | tr -c 'A-Za-z0-9._-' '_')"
  _ed="$_er/$_es/$(date -u +%Y-%m-%d)"; _ef="$_ed/$_ew.jsonl"
  ( umask 077; mkdir -p "$_ed" ) 2>/dev/null || { stream_spill "$_er" "$_es" "cannot create $_ed" "$_ea"; return $?; }
  { [ ! -e "$_ef" ] || { [ -f "$_ef" ] && [ ! -L "$_ef" ]; }; } || { stream_spill "$_er" "$_es" "sink is not a regular file" "$_ea"; return $?; }
  # One writer at a time per file (measured: 20 concurrent emits all read seq 1). The lock is a file the shell makes
  # with O_EXCL (set -C), never mkdir: uutils mkdir 0.10 exits 0 on a lost race (harbor#1378). A lock older than a
  # minute is a crashed writer's and is broken (a directory: an older writer's); one not won in ~5 s spills.
  _lk="$_ef.lock"; _lt=0
  until ( set -C; : > "$_lk" ) 2>/dev/null; do
    [ -n "$(find "$_lk" -maxdepth 0 -mmin +1 2>/dev/null)" ] && { rmdir "$_lk" || rm -f "$_lk"; } 2>/dev/null && continue
    _lt=$((_lt + 1)); [ "$_lt" -le 100 ] || { stream_spill "$_er" "$_es" "lock not won in 5 s" "$_ea"; return $?; }
    sleep 0.05 2>/dev/null || sleep 1
  done
  _eq=1; _ep=-
  if [ -s "$_ef" ]; then
    _eq=$(( $(wc -l < "$_ef") + 1 ))
    _ep="$(tail -n 1 "$_ef" | stream_sha | cut -c1-16)"
  fi
  _el="$(jq -cn --arg id "$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg s "$_es" --arg sess "${HARBOR_SESSION:-${CLAUDE_SESSION_ID:-}}" --argjson seq "$_eq" \
      --arg src "${HARBOR_WRITER:-${0##*/}}" --arg repo "${HARBOR_REPO_NAME:-}" --arg cause "${HARBOR_CAUSE:-}" \
      --argjson attrs "$_ea" --arg prev "$_ep" \
      '{v:1,id:$id,ts:$ts,stream:$s,sess:$sess,seq:$seq,src:$src,repo:$repo,cause:$cause,attrs:$attrs,prev:$prev}' 2>/dev/null)" \
    || { rm -f "$_lk" 2>/dev/null; stream_spill "$_er" "$_es" "envelope did not build" "$_ea"; return $?; }
  [ "$(printf %s "$_el" | wc -c)" -lt "$STREAM_MAX" ] || { rm -f "$_lk" 2>/dev/null; stream_spill "$_er" "$_es" "line over $STREAM_MAX bytes" "$_es"; return $?; }
  printf '%s\n' "$_el" >> "$_ef" 2>/dev/null || { rm -f "$_lk" 2>/dev/null; stream_spill "$_er" "$_es" "append failed" "$_el"; return $?; }
  rm -f "$_lk" 2>/dev/null || :
  chmod 0600 "$_ef" 2>/dev/null || :
  return 0
}

stream_verify() { # <file>
  _vp=-; _vline=0; _vexp=1
  while IFS= read -r _vl; do
    _vline=$((_vline + 1))
    _vs="$(printf '%s' "$_vl" | jq -r '.seq // "x"' 2>/dev/null)"; _vh="$(printf '%s' "$_vl" | jq -r '.prev // "x"' 2>/dev/null)"
    [ "$_vs" = "$_vexp" ] || printf 'line %s: seq %s, want %s\n' "$_vline" "$_vs" "$_vexp"
    [ "$_vh" = "$_vp" ] || printf 'line %s: prev %s does not match the line before (%s)\n' "$_vline" "$_vh" "$_vp"
    case "$_vs" in ''|*[!0-9]*) _vexp=$((_vexp + 1)) ;; *) _vexp=$((_vs + 1)) ;; esac
    _vp="$(printf '%s\n' "$_vl" | stream_sha | cut -c1-16)"
  done < "$1"
}
