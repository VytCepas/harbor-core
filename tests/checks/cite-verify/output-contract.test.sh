#!/usr/bin/env sh
# cite-verify.sh's output follows CONTRACTS/logging.md (harbor#771): each cited URL is a log line, a citation that
# changed its answer is a FAIL followed by its fix, a recorded non-2xx answer is ok, and the run ends with the
# summary. A fixture tree, a stub curl and a stub gh stand in for the repo and the network.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE; export GIT_CONFIG_NOSYSTEM=1
R="$T_TMP/r"; mkdir -p "$R/bin" "$T_TMP/stub"
cp "$T_ROOT/bin/cite-verify.sh" "$T_ROOT/bin/log-lib.sh" "$R/bin/"
printf "_fx='https://example\\\\.invalid'\n" > "$R/bin/lint-conventions.sh"
printf 'See https://ok.test/a and https://gated.test/b and https://gone.test/c for the claim.\n' > "$R/NOTES.md"
printf '| url | http | cited for |\n|---|---|---|\n| `https://gated.test/b` | 401 | an authenticated endpoint |\n' > "$R/CITATIONS.md"
git -C "$R" init -q; git -C "$R" add -A
# curl prints the code for the URL asked; gh is absent from the stub PATH's front so only curl answers.
cat > "$T_TMP/stub/curl" <<'EOT'
#!/bin/sh
for a in "$@"; do u="$a"; done
case "$u" in https://ok.test/*) printf 200 ;; https://gated.test/*) printf 401 ;; *) printf 404 ;; esac
EOT
chmod +x "$T_TMP/stub/curl"
run() { env PATH="$T_TMP/stub:$PATH" sh "$R/bin/cite-verify.sh" "$@" >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?"; }
OUT() { cat "$T_TMP/out"; }; ERR() { cat "$T_TMP/err"; }
after_fail() { awk '/^  FAIL:/ { f = 1; next } f { print; exit }' "$T_TMP/out"; }

t_section "a sweep with a good, a recorded and a changed citation"
t_eq "a changed citation exits 1" "exit 1" "$(run)"
t_eq "the header counts the URLs" "── cite-verify · 3 cited URL(s)" "$(OUT | head -1)"
t_has "a 200 is an ok line" "$(OUT)" "  ok: https://ok.test/a  http=200 via curl"
t_has "a recorded 401 is an ok line that says so" "$(OUT)" "  ok: https://gated.test/b  http=401 via curl — matches the code recorded in CITATIONS.md"
t_has "an unrecorded 404 is a FAIL" "$(OUT)" "  FAIL: https://gone.test/c  http=404 via curl — UNEXPECTED (recorded: none)"
t_has "followed by its fix" "$(after_fail)" "  fix: curl -sIL https://gone.test/c"
t_eq "the summary" "cite-verify: 2 ok, 1 failed, 0 warnings" "$(OUT | tail -1)"
t_eq "stderr is empty" "" "$(ERR)"
t_eq "no legacy table is left" 0 "$(OUT | grep -c '^URL \|citation(s) did not resolve')"

t_section "every citation resolving: exit 0"
printf '| `https://gone.test/c` | 404 | recorded |\n' >> "$R/CITATIONS.md"
t_eq "exit 0" "exit 0" "$(run)"
t_eq "the summary" "cite-verify: 3 ok, 0 failed, 0 warnings" "$(OUT | tail -1)"
t_has "the existence-not-support caveat is a note" "$(OUT)" "  note: a resolving URL is existence, NOT support"

t_section "an argument: FAIL, its fix, exit 2"
t_eq "exit 2" "exit 2" "$(run --json)"
t_has "the FAIL" "$(OUT)" "  FAIL: unknown flag --json"
t_eq "its fix" "  fix: sh $R/bin/cite-verify.sh" "$(after_fail)"
t_eq "the summary" "cite-verify: 0 ok, 1 failed, 0 warnings" "$(OUT | tail -1)"
t_done
