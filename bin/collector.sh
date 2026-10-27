#!/usr/bin/env sh
# collector.sh (harbor#1181 lane 5) — copies every observability stream into a store the observed agent cannot write.
#   collector.sh                       one pass: append each source's new bytes to the store, re-check the bytes
#                                      already copied, write status.json
#   collector.sh --checkpoint [DAY]    sign the store manifest for a closed UTC day (default: yesterday)
#   collector.sh --verify DAY          verify that day's checkpoint signature and that the store still matches it
# Runs every 300 s as the _harborlog user from a root-owned copy (collector-install.sh, launchd). It reads the
# sources through an ACL the operator's uid could remove: that, an edit, a truncation or a gap is REPORTED in
# status.json, never prevented (docs/design/telemetry.md, tier 2). Sources: HARBOR_COLLECTOR_SRC, a :-separated list of dirs and files (the
# OBSERVABILITY dir); store: HARBOR_COLLECTOR_STORE.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
case "${1:-}" in -h|--help) awk 'NR<2{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;; esac
. "$HERE/log-lib.sh"
. "$HERE/fs-lib.sh"
log_init collector
SRC="${HARBOR_COLLECTOR_SRC:-}"
STORE="${HARBOR_COLLECTOR_STORE:-/Library/Application Support/Harbor/collector}"
NS=harbor-collector   # ssh-keygen -Y namespace: a signature made for anything else does not verify here
[ -n "$SRC" ] || { log_fail "HARBOR_COLLECTOR_SRC is not set"; log_fix "set it to <cfg>/MEMORY/OBSERVABILITY in the launchd job"; exit 2; }
umask 077
mkdir -p "$STORE/data" "$STORE/state" "$STORE/checkpoints"
chmod 0755 "$STORE/checkpoints"   # signed checkpoints are public, for the off-host anchor; data/ and state/ are not
STATE="$STORE/state/files.tsv"; EVENTS="$STORE/events.jsonl"; touch "$STATE" "$EVENTS"
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
# shasum is perl and missing on minimal Linux; sha256sum is coreutils and missing on macOS: whichever exists
# appendonly <file> — after a write, the store file takes appends only: macOS uappnd (the owner or root alone clears
# it), Linux chattr +a (the unit grants CAP_LINUX_IMMUTABLE). An accident guard against edits, root can still clear it.
appendonly() { chflags uappnd "$1" 2>/dev/null || chattr +a "$1" 2>/dev/null || :; }
if command -v shasum >/dev/null 2>&1; then sha() { shasum -a 256 | cut -c1-64; }; else sha() { sha256sum | cut -c1-64; }; fi
# event <kind> <path> <detail> — a finding, logged ONCE: a standing condition (a removed ACL, a kept edit) is in
# state/active and stays quiet until it clears, so events.jsonl is the delta, never the census (CLAUDE.md, findings).
event() {
  printf "%s\t%s\n" "$1" "$2" >> "$STORE/state/active.now"
  grep -qxF "$(printf "%s\t%s" "$1" "$2")" "$STORE/state/active" 2>/dev/null && return 0
  printf '{"ts":"%s","kind":"%s","path":"%s","detail":"%s"}\n' "$(now)" "$1" "$2" "$3" >> "$EVENTS"
}

ingest() {
  _unread=0; _files=0; _bytes=0; _new="$STORE/state/files.tsv.new"; : > "$_new"; _now="$(date +%s)"
  : > "$STORE/state/active.now"
  : > "$STORE/state/list"
  # Every source, wherever its writer keeps it (lane 4): a dir contributes its ledgers, a file itself.
  _ifs="$IFS"; IFS=:
  for _s in $SRC; do IFS="$_ifs"
    if [ -d "$_s" ]; then
      { [ -r "$_s" ] && [ -x "$_s" ]; } || { event unreadable "$_s" "source dir not readable: ACL removed?"; _unread=$((_unread + 1)); continue; }
      find "$_s" -type f \( -name "*.jsonl*" -o -name "*.log" -o -name "*.tsv" \) 2>/dev/null >> "$STORE/state/list"
    elif [ -e "$_s" ]; then printf "%s\n" "$_s" >> "$STORE/state/list"
    else event missing "$_s" "source gone: moved, deleted, or never created"; _unread=$((_unread + 1)); fi
  done; IFS="$_ifs"
  LC_ALL=C sort -u -o "$STORE/state/list" "$STORE/state/list"
  while IFS= read -r f; do
    rel="$f"
    [ -r "$f" ] || { event unreadable "$rel" "file not readable"; _unread=$((_unread + 1)); continue; }
    ino="$(ls -di "$f" | awk '{print $1}')"; size="$(wc -c < "$f" | tr -d ' ')"
    prev="$(awk -F'\t' -v i="$ino" '$1 == i { print; exit }' "$STATE")"
    done_b=0; done_h=""; done_m=""; mt="$(fs_mtime "$f" 2>/dev/null || echo 0)"
    if [ -n "$prev" ]; then done_b="$(printf '%s' "$prev" | cut -f2)"; done_h="$(printf '%s' "$prev" | cut -f3)"; done_m="$(printf '%s' "$prev" | cut -f5)"; fi
    # The fast path: a CLOSED file (idle over an hour: archives, rotated generations) with unchanged size and mtime skips
    # the re-hash (5 s per 200 MB measured); anything recent is always re-hashed, so mtime's one-second grain hides
    # nothing. An edit to a closed file that restores size and mtime is caught by the daily --checkpoint full pass.
    if [ "${HARBOR_COLLECTOR_FULL:-0}" != 1 ] && [ "$size" = "$done_b" ] && [ -n "$done_m" ] && [ "$mt" = "$done_m" ] \
       && [ "$((_now - mt))" -gt 3600 ]; then
      printf '%s\t%s\t%s\t%s\t%s\n' "$ino" "$done_b" "$done_h" "$rel" "$done_m" >> "$_new"; _files=$((_files + 1)); continue
    fi
    if [ "$size" -lt "$done_b" ]; then
      event truncated "$rel" "size $size < $done_b already copied"; printf '%s\t%s\t%s\t%s\t%s\n' "$ino" "$done_b" "$done_h" "$rel" "$done_m" >> "$_new"; continue
    fi
    if [ "$done_b" -gt 0 ] && [ "$(head -c "$done_b" "$f" | sha)" != "$done_h" ]; then
      event edited "$rel" "the first $done_b bytes changed after they were copied"
      printf '%s\t%s\t%s\t%s\t%s\n' "$ino" "$done_b" "$done_h" "$rel" "$done_m" >> "$_new"; continue
    fi
    if [ "$size" -gt "$done_b" ]; then
      tail -c "+$((done_b + 1))" "$f" | head -c "$((size - done_b))" >> "$STORE/data/$ino.jsonl"
      appendonly "$STORE/data/$ino.jsonl"
      _bytes=$((_bytes + size - done_b))
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$ino" "$size" "$(head -c "$size" "$f" | sha)" "$rel" "$mt" >> "$_new"
    _files=$((_files + 1))
  done < "$STORE/state/list"
  # a file that vanished keeps its row: its copied bytes are still in data/, and the row says where they came from
  awk -F'\t' 'NR == FNR { seen[$1] = 1; next } !($1 in seen)' "$_new" "$STATE" >> "$_new"
  mv -f "$_new" "$STATE"
  # what is active now replaces what was: a condition that cleared can fire again if it comes back
  LC_ALL=C sort -u "$STORE/state/active.now" > "$STORE/state/active"
  _ev="$(grep -c . "$EVENTS" 2>/dev/null || true)"
  printf '{"ts":"%s","files":%s,"bytes_this_pass":%s,"unreadable":%s,"events_total":%s}\n' \
    "$(now)" "$_files" "$_bytes" "$_unread" "${_ev:-0}" > "$STORE/status.json.tmp"
  chmod 0644 "$STORE/status.json.tmp"; mv -f "$STORE/status.json.tmp" "$STORE/status.json"
  log_ok "ingested $_files source file(s), $_bytes new byte(s); $_unread unreadable"
}

manifest() { # the store's data files, sorted, with size and sha256: what a checkpoint signs
  find "$STORE/data" -type f -name '*.jsonl' | LC_ALL=C sort | while IFS= read -r d; do
    printf '%s\t%s\t%s\n' "${d##*/}" "$(wc -c < "$d" | tr -d ' ')" "$(sha < "$d")"
  done
}

checkpoint() { # <day>
  HARBOR_COLLECTOR_FULL=1 ingest   # every kept byte re-hashed before a day is signed: the fast path's backstop
  _cp="$STORE/checkpoints/$1.tsv"
  [ ! -e "$_cp" ] || { log_fail "a checkpoint for $1 already exists: one per day, never rewritten"; log_nofix "verify it: $0 --verify $1"; return 1; }
  [ -f "$STORE/key/collector" ] || { log_fail "no signing key at $STORE/key/collector"; log_fix "sudo sh bin/collector-install.sh"; return 1; }
  { printf '# harbor-collector checkpoint day=%s made=%s\n' "$1" "$(now)"; manifest; } > "$_cp"
  ssh-keygen -Y sign -q -f "$STORE/key/collector" -n "$NS" "$_cp" >/dev/null 2>&1 \
    || { rm -f "$_cp"; log_fail "ssh-keygen could not sign $_cp"; log_nofix "check $STORE/key"; return 1; }
  chmod 0644 "$_cp" "$_cp.sig"
  # the public key beside them, so the off-host anchor can verify a day without reading the 0700 key dir
  cp "$STORE/key/collector.pub" "$STORE/checkpoints/collector.pub" 2>/dev/null && chmod 0644 "$STORE/checkpoints/collector.pub" || :
  log_ok "checkpoint $1: $(grep -vc '^#' "$_cp") file(s), head $(sha < "$_cp" | cut -c1-16)"
}

verify() { # <day>
  _cp="$STORE/checkpoints/$1.tsv"
  [ -f "$_cp" ] && [ -f "$_cp.sig" ] || { log_fail "no checkpoint for $1"; log_nofix "$0 --checkpoint $1"; return 1; }
  _pub="$(cat "$STORE/key/collector.pub")"
  printf 'collector %s\n' "$_pub" > "$STORE/state/allowed"
  ssh-keygen -Y verify -f "$STORE/state/allowed" -I collector -n "$NS" -s "$_cp.sig" < "$_cp" >/dev/null 2>&1 \
    || { log_fail "the signature on $_cp does not verify"; log_nofix "the checkpoint or its signature was changed"; return 1; }
  # Each file the checkpoint names must still START with the bytes it signed: appends since are fine, edits are not.
  _bad=0
  while IFS="$(printf '\t')" read -r n s h; do
    case "$n" in '#'*|'') continue ;; esac
    [ "$(head -c "$s" "$STORE/data/$n" 2>/dev/null | sha)" = "$h" ] || { log_warn "$n differs from the $1 checkpoint"; _bad=1; }
  done < "$_cp"
  [ "$_bad" -eq 0 ] || { log_fail "the store no longer matches the $1 checkpoint"; log_nofix "investigate $STORE/data"; return 1; }
  log_ok "checkpoint $1 verifies, and the store still matches it"
}

case "${1:-}" in
  '') ingest ;;
  --checkpoint) checkpoint "${2:-$(date -u -v-1d +%Y-%m-%d 2>/dev/null || date -u -d yesterday +%Y-%m-%d)}" || { log_end || :; exit 1; } ;;
  --verify) [ -n "${2:-}" ] || { log_fail "--verify needs a day"; log_nofix "$0 --verify YYYY-MM-DD"; exit 2; }
            verify "$2" || { log_end || :; exit 1; } ;;
  *) log_fail "unknown argument $1"; log_nofix "sh bin/collector.sh --help"; exit 2 ;;
esac
log_end
