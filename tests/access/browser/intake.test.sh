#!/usr/bin/env sh
# harbor chrome intake (contracts/secret-intake.md, 2026-11-23): a key shown once goes from the headless Chrome's own
# clipboard (or the field at the ref) down a pipe into harbor access --value-stdin, and nowhere else — not stdout, not
# stderr, not the CLI's call log, not a file in the workdir. The stub CLI, the file-backed keychain stub, a temp private
# layer: no real Chrome, Keychain or clipboard is touched (pbpaste and pbcopy are stubs that fail loudly if called).
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/../../cli/keychain-stub.sh"
AGENT="$T_ROOT/bin/access-browser-agent.sh"; unset HARBOR_ACCESS_CHROME
HARBOR_ACCESS_BROWSER_SETTLE=0; export HARBOR_ACCESS_BROWSER_SETTLE
. "$(dirname "$0")/../../cli/browser/agent-stub.sh"
PV="$T_TMP/pv"; export HARBOR_SCOPE_PRIVATE="$PV" PORT_ROOT="$T_TMP/port"
sh "$T_ROOT/bin/scope.sh" install --private-only >/dev/null 2>&1
CLIPLOG="$T_TMP/macos-clipboard"; export CLIPLOG
printf '#!/bin/sh\necho pbpaste >> "$CLIPLOG"\n' > "$T_BIN/pbpaste"; printf '#!/bin/sh\necho pbcopy >> "$CLIPLOG"\n' > "$T_BIN/pbcopy"
chmod +x "$T_BIN/pbpaste" "$T_BIN/pbcopy"
W="$T_TMP/harbor-browser/claude-abc123def456"; mkdir -p "$W"
cat >> "$SNAP" <<'EOF'
  - button "Copy & Close" [ref=e28] [box=8,230,80,20]
  - textbox "API key" [ref=e31] [box=100,230,80,20]
EOF
VAL="fake-intake-value-$(printf '%s' 0123456789)"
printf '  - paragraph [ref=e32]: the open dialog shows %s\n' "$VAL" >> "$SNAP"   # as a vendor's does: so does the guard snapshot
readv() { sh "$T_ROOT/bin/secret" run "$1" V -- sh -c 'printf %s "$V"' 2>/dev/null; }
ans() { STUB_INTAKE="$(jq -cn --arg c "$1" --arg f "$2" '{intake: 1, clip: $c, field: (if $f == "" then null else $f end)}')"; export STUB_INTAKE; }
seen() { cat "$T_TMP/out" "$CALLS" | grep -c -- "$1" || :; }   # the value in the agent's output or the CLI's call log

t_section "intake headless: the clipboard's value lands in the store, and nowhere else"
: > "$W/.agent"; rm -f "$W/.shown"; : > "$CALLS"; ans "$VAL" ''
_r="$(ag intake e28 add github-intake-one --kind token --what w --use-when u --reaches r --cannot c --grant g \
  --secret harbor-github-tools-intake --vendor-name 'EXAMPLECO API GitHub' --expect 'prints `alive`' \
  --check "sh $T_ROOT/bin/secret run harbor-github-tools-intake V -- sh -c 'case \"\$V\" in fake-intake-*) echo alive ;; esac'")"
t_eq "it passes" "exit 0" "$_r"
t_eq "the store holds the value" "$VAL" "$(readv harbor-github-tools-intake)"
t_eq "the agent's stdout and stderr never carry it, nor the CLI's call log" 0 "$(seen "$VAL")"
t_eq "...nor any file in the session workdir" "" "$(grep -rl -- "$VAL" "$W" 2>/dev/null)"
t_eq "the CLI's own click on the ref ran once, raw" 1 "$(called ' --raw click e28$')"
t_eq "...then the fixed intake-read row, raw, on that ref" 1 "$(called "--raw run-code async (page) => .*'aria-ref=' + \"e28\"")"
t_eq "the macOS clipboard was never touched" no "$([ -e "$CLIPLOG" ] && echo yes || echo no)"
t_has "the run says where the value went" "$(out)" "stored from this Chrome's own clipboard or the field at e28, unseen"
ans "$VAL-two" ''
t_eq "rotate takes the next value the same way" "exit 0" "$(ag intake e28 rotate github-intake-one)"
t_eq "...into the store" "$VAL-two" "$(readv harbor-github-tools-intake)"
t_eq "...unseen" 0 "$(seen "$VAL-two")"

t_section "no Copy button, or an empty clipboard: the field at the ref"
ans '' "$VAL-field"; : > "$CALLS"
t_eq "intake on the key's field passes" "exit 0" "$(ag intake e31 rotate github-intake-one)"
t_eq "...storing the field's value" "$VAL-field" "$(readv harbor-github-tools-intake)"
t_eq "...unseen" 0 "$(seen "$VAL-field")"
ans "$VAL-stale" "$VAL-field2"
t_eq "a field holding the key outranks a stale clipboard" "exit 0" "$(ag intake e31 rotate github-intake-one)"
t_eq "...the field's value stored" "$VAL-field2" "$(readv harbor-github-tools-intake)"
t_eq "...neither shown" "0 0" "$(seen "$VAL-stale") $(seen "$VAL-field2")"
ans '' ''
t_eq "nothing in either is refused" "exit 1" "$(ag intake e28 rotate github-intake-one)"
t_has "...naming the field ref as the way on" "$(out)" "harbor chrome intake <the key's field ref> rotate github-intake-one"
t_eq "...and the stored value is kept" "$VAL-field2" "$(readv harbor-github-tools-intake)"
STUB_INTAKE='Error: Execution context was destroyed'; export STUB_INTAKE
t_eq "a read that fails is refused too, its text never stored" "exit 1" "$(ag intake e28 rotate github-intake-one)"
t_eq "...the store unchanged" "$VAL-field2" "$(readv harbor-github-tools-intake)"

t_section "refused: a window, the operator's Chrome, a value flag, a live-change label"
ans "$VAL-no" ''; : > "$W/.shown"; : > "$CALLS"
t_eq "the agent Chrome in a window (attach --show) is refused" "exit 1" "$(ag intake e28 rotate github-intake-one)"
t_has "...naming --value-clipboard as that route" "$(out)" "harbor access rotate github-intake-one --value-clipboard"
rm -f "$W/.agent" "$W/.shown"
t_eq "the operator's Chrome is refused" "exit 1" "$(ag intake e28 rotate github-intake-one)"
t_has "...as the operator's" "$(out)" "runs the operator's Chrome, where the page's Copy reaches the macOS clipboard"
t_eq "...and neither clicked nor read" 0 "$(called ' click \| run-code ')"
: > "$W/.headless"
t_eq "the headless lane takes it" "exit 0" "$(ag intake e28 rotate github-intake-one)"
t_eq "...into the store" "$VAL-no" "$(readv harbor-github-tools-intake)"
rm -f "$W/.headless"; : > "$W/.agent"; : > "$CALLS"
t_eq "--value-stdin among the add flags is refused" "exit 1" "$(ag intake e28 rotate github-intake-one --value-stdin)"
t_eq "--value-clipboard too" "exit 1" "$(ag intake e28 rotate github-intake-one --value-clipboard)"
t_eq "a verb other than add or rotate is refused" "exit 1" "$(ag intake e28 revoke github-intake-one)"
t_eq "a selector for a ref is refused" "exit 1" "$(ag intake 'text=Copy' rotate github-intake-one)"
t_eq "a live-change label at the ref is refused (Save changes)" "exit 1" "$(ag intake e24 rotate github-intake-one)"
t_eq "...none of them clicked or read" 0 "$(called ' click \| run-code ')"
t_eq "a plain click on Copy & Close stays refused headless" "exit 1" "$(ag click e28)"
t_has "...naming the intake verb" "$(out)" "use harbor chrome intake e28 rotate <id>"

t_section "mutants: a printed value, a skipped pipe, a kept guard snapshot"
# The mutant tree: bin/ copied, every other top-level dir linked, so only access-browser-agent.sh differs.
M="$T_TMP/m"; mkdir -p "$M/bin"; cp -R "$T_ROOT/bin/." "$M/bin/" 2>/dev/null
for _d in "$T_ROOT"/*; do [ "${_d##*/}" = bin ] || ln -s "$_d" "$M/${_d##*/}"; done
_pipe='      | sh "$HERE/access.sh" "$_iop" "$_iid" "$@" --value-stdin || _irc=$?'
t_eq "CONTROL: the pipe line is in the agent once" 1 "$(grep -cxF -- "$_pipe" "$AGENT")"
sed 's#^      | sh "\$HERE/access.sh" "\$_iop" "\$_iid" "\$@" --value-stdin || _irc=\$?$#      | { IFS= read -r _v || :; printf "%s\\n" "$_v" >\&2; printf %s "$_v"; } | sh "$HERE/access.sh" "$_iop" "$_iid" "$@" --value-stdin || _irc=$?#' "$AGENT" > "$M/bin/access-browser-agent.sh"
t_eq "the printing mutant differs" yes "$(cmp -s "$AGENT" "$M/bin/access-browser-agent.sh" || echo yes)"
_oa="$AGENT"; AGENT="$M/bin/access-browser-agent.sh"; ans "$VAL-mut" ''
ag intake e28 rotate github-intake-one >/dev/null
t_eq "with the value also printed to stderr, the unseen check goes red" 1 "$(seen "$VAL-mut")"
sed 's#^      | sh "\$HERE/access.sh" "\$_iop" "\$_iid" "\$@" --value-stdin || _irc=\$?$#      >/dev/null; sh "$HERE/access.sh" "$_iop" "$_iid" "$@" --value-stdin </dev/null || _irc=$?#' "$_oa" > "$M/bin/access-browser-agent.sh"
t_eq "the skipped-pipe mutant differs" yes "$(cmp -s "$_oa" "$M/bin/access-browser-agent.sh" || echo yes)"
ans "$VAL-skip" ''
ag intake e28 rotate github-intake-one >/dev/null
t_eq "with the pipe skipped, the store check goes red" no "$([ "$(readv harbor-github-tools-intake)" = "$VAL-skip" ] && echo yes || echo no)"
sed '/^    rm -f "\$WORKDIR\/harbor-guard.yml" "\$WORKDIR\/harbor-guard.out"$/d' "$_oa" > "$M/bin/access-browser-agent.sh"
t_eq "the kept-snapshot mutant differs" yes "$(cmp -s "$_oa" "$M/bin/access-browser-agent.sh" || echo yes)"
ans "$VAL-snap" ''; ag intake e28 rotate github-intake-one >/dev/null
t_eq "with the guard snapshot kept, the no-file check goes red" "$W/harbor-guard.yml" "$(grep -rl -- "$VAL" "$W" 2>/dev/null)"
AGENT="$_oa"
t_done
