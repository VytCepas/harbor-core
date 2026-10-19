#!/usr/bin/env sh
# ci-queue.sh's output follows CONTRACTS/logging.md (harbor#771): each repo is a log-lib line, an unread repo or
# a stall is a WARN with its fix, the cache write is an ok line, and the run ends with the summary, in both modes.
# A fake gh serves fixtures; nothing reaches GitHub.
. "$(dirname "$0")/../../lib/core.sh"; t_init
FX="$T_TMP/fx"; RUN="$T_TMP/runners"; CACHE="$T_TMP/cache"; GH="$T_TMP/gh"
mkdir -p "$FX" "$RUN/r1" "$RUN/s1"
printf '{"gitHubUrl":"https://github.com/o/r"}' > "$RUN/r1/.runner"
printf '{"gitHubUrl":"https://github.com/o/s"}' > "$RUN/s1/.runner"
cat > "$GH" <<'EOT'
#!/bin/sh
f="$FX/$(printf '%s' "$2" | tr '/?&=' '____')"
[ "$1" = api ] && [ -f "$f" ] && cat "$f"
EOT
chmod +x "$GH"
fx() { printf '%s\n' "$2" > "$FX/$(printf '%s' "$1" | tr '/?&=' '____')"; }
fx 'repos/o/r/actions/runs?status=in_progress&per_page=50' '{"workflow_runs":[]}'
fx 'repos/o/r/actions/runs?status=queued&per_page=50' '{"workflow_runs":[]}'
fx 'repos/o/r/actions/runners?per_page=100' '{"runners":[]}'
NOW=1790000000
q() { FX="$FX" HARBOR_GH="$GH" HARBOR_RUNNERS_DIR="$RUN" HARBOR_CACHE_DIR="$CACHE" HARBOR_NOW="$NOW" \
        sh "$T_ROOT/bin/ci-queue.sh" "$@" >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?"; }
OUT() { cat "$T_TMP/out"; }; ERR() { cat "$T_TMP/err"; }
after_warn() { awk '/^  WARN: .*UNREAD/ { f = 1; next } f { print; exit }' "$T_TMP/out"; }

t_section "--print: one log line per repo, an unread repo is a WARN with a fix"
t_eq "exit 0" "exit 0" "$(q --print)"
t_eq "the header" "── ci-queue · queue per repo" "$(OUT | head -1)"
t_has "an idle repo is an ok line" "$(OUT)" "  ok: o/r  runners=1  idle"
t_has "an unread repo is a WARN" "$(OUT)" "  WARN: o/s  runners=1  UNREAD — GitHub did not answer"
t_has "its fix follows" "$(after_warn)" "  fix: gh auth status"
t_eq "the summary ends it" "ci-queue: 1 ok, 0 failed, 1 warnings" "$(OUT | tail -1)"
t_eq "--print writes no cache" "no" "$([ -e "$CACHE/ci-queue.json" ] && echo yes || echo no)"
t_eq "stderr is empty" "" "$(ERR)"

t_section "the cache run: the same lines, then the write"
t_eq "exit 0" "exit 0" "$(q)"
t_eq "the header says it writes" "── ci-queue · queue per repo, written to the cache" "$(OUT | head -1)"
t_has "the write is an ok line" "$(OUT)" "  ok: wrote $CACHE/ci-queue.json"
t_eq "the cache exists and is JSON" "$NOW" "$(jq -r .at "$CACHE/ci-queue.json")"
t_eq "the summary" "ci-queue: 2 ok, 0 failed, 1 warnings" "$(OUT | tail -1)"

t_section "a cache that cannot be written: FAIL, its fix, exit 1"
printf 'a file\n' > "$T_TMP/notadir"
t_eq "exit 1" "exit 1" "$(FX="$FX" HARBOR_GH="$GH" HARBOR_RUNNERS_DIR="$RUN" HARBOR_CACHE_DIR="$T_TMP/notadir/x" HARBOR_NOW="$NOW" sh "$T_ROOT/bin/ci-queue.sh" >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?")"
t_has "the FAIL" "$(OUT)" "  FAIL: could not write $T_TMP/notadir/x/ci-queue.json"
t_eq "the summary" "ci-queue: 1 ok, 1 failed, 1 warnings" "$(OUT | tail -1)"

t_section "an unknown option: FAIL, its fix, exit 2"
t_eq "exit 2" "exit 2" "$(q --bogus)"
t_has "the FAIL" "$(OUT)" "  FAIL: unknown option --bogus"
t_has "its fix" "$(OUT)" "  fix: sh $T_ROOT/bin/ci-queue.sh --help"
t_done
