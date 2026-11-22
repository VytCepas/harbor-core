#!/usr/bin/env sh
# harbor access add|rotate --value-clipboard (contracts/secret-intake.md): the value comes from the clipboard into the
# store and nowhere else — not stdout, not stderr, not argv — and the clipboard is emptied after, whatever the outcome.
# A temp HOME, a temp HARBOR_SCOPE_PRIVATE, the file-backed keychain stub and a stub clipboard: nothing real is touched.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/../../cli/keychain-stub.sh"
AX() { sh "$T_ROOT/bin/access.sh" "$@"; }
PV="$T_TMP/pv"; export HARBOR_SCOPE_PRIVATE="$PV" PORT_ROOT="$T_TMP/port"
sh "$T_ROOT/bin/scope.sh" install --private-only >/dev/null 2>&1
# The stub clipboard: pbpaste serves $FAKE_CLIP, pbcopy replaces it (from /dev/null: empties it).
FAKE_CLIP="$T_TMP/clip"; export FAKE_CLIP
printf '#!/bin/sh\ncat "$FAKE_CLIP" 2>/dev/null || true\n' > "$T_BIN/pbpaste"
printf '#!/bin/sh\ncat > "$FAKE_CLIP"\n' > "$T_BIN/pbcopy"
chmod +x "$T_BIN/pbpaste" "$T_BIN/pbcopy"
VAL="fake-clipboard-value-$(printf '%s' 0123456789)"
readv() { sh "$T_ROOT/bin/secret" run "$1" V -- sh -c 'printf %s "$V"' 2>/dev/null; }
ADDC() { # <id> <ref> [extra args...]: add with the clipboard as the value's source
  _i="$1"; _r="$2"; shift 2
  AX add "$_i" --kind token --what w --use-when u --reaches r --cannot c --grant g --secret "$_r" --vendor-name 'EXAMPLECO API GitHub' "$@"
}

t_section "add --value-clipboard: stored, never shown, clipboard emptied"
printf '  %s\n' "$VAL" > "$FAKE_CLIP"
ADDC github-clip-one harbor-github-tools-clip --value-clipboard > "$T_TMP/out" 2> "$T_TMP/err" < /dev/null; _rc=$?
t_eq "it passes" 0 "$_rc"
t_eq "the store holds the value, trimmed as --value-stdin trims it" "$VAL" "$(readv harbor-github-tools-clip)"
t_eq "stdout never carries it" 0 "$(grep -c "$VAL" "$T_TMP/out")"
t_eq "nor stderr" 0 "$(grep -c "$VAL" "$T_TMP/err")"
t_eq "the clipboard is empty after" 0 "$(wc -c < "$FAKE_CLIP" | tr -d ' ')"
t_has "and says so" "$(cat "$T_TMP/err")" "the clipboard was emptied"

t_section "a failed add still empties the clipboard"
printf 'two words %s\n' "$VAL" > "$FAKE_CLIP"
ADDC github-clip-two harbor-github-tools-cliptwo --value-clipboard > "$T_TMP/out" 2> "$T_TMP/err" < /dev/null; _rc=$?
t_eq "a value with whitespace inside is refused, exit 2" 2 "$_rc"
t_eq "and nothing of it is shown" 0 "$(cat "$T_TMP/out" "$T_TMP/err" | grep -c "$VAL")"
t_eq "the clipboard is empty after" 0 "$(wc -c < "$FAKE_CLIP" | tr -d ' ')"
printf '%s' "$VAL" > "$FAKE_CLIP"
t_eq "--value-clipboard with --value-stdin is refused, exit 2" 2 "$(ADDC github-clip-3 harbor-github-tools-clipthree --value-clipboard --value-stdin >/dev/null 2>&1 < /dev/null; echo $?)"
t_eq "rotate of an entry that does not exist fails, exit 2" 2 "$(AX rotate no-such-entry --value-clipboard >/dev/null 2>&1 < /dev/null; echo $?)"
t_eq "and still empties the clipboard" 0 "$(wc -c < "$FAKE_CLIP" | tr -d ' ')"

t_section "no clipboard tool: a refusal naming what it looked for, never a silent empty value"
. "$T_ROOT/tests/lib/linux-sim.sh"
LX="$T_TMP/lx"; linux_path "$LX" pbpaste pbcopy wl-paste wl-copy xclip xsel powershell.exe clip.exe
t_eq "control: that PATH has no pbpaste" "" "$(PATH="$LX" command -v pbpaste)"
OUT="$(PATH="$LX" ADDC github-clip-4 harbor-github-tools-clipfour --value-clipboard 2>&1 < /dev/null)"; _rc=$?
t_eq "exit 2" 2 "$_rc"
t_has "naming the tools" "$OUT" "wl-paste"

t_section "mutant: with the clear removed, the value stays on the clipboard"
# The mutant tree: bin/ copied, every other top-level dir linked, so only access.sh differs from the checkout.
M="$T_TMP/m"; mkdir -p "$M/bin"; cp -R "$T_ROOT/bin/." "$M/bin/" 2>/dev/null
for _d in "$T_ROOT"/*; do [ "${_d##*/}" = bin ] || ln -s "$_d" "$M/${_d##*/}"; done
sed 's/^    if clip_clear; then log_note "the clipboard was emptied"; else log_warn .*$/    :/' "$T_ROOT/bin/access.sh" > "$M/bin/access.sh"
t_eq "the mutant differs" yes "$(cmp -s "$T_ROOT/bin/access.sh" "$M/bin/access.sh" || echo yes)"
printf '%s' "$VAL" > "$FAKE_CLIP"
sh "$M/bin/access.sh" add github-clip-5 --kind token --what w --use-when u --reaches r --cannot c --grant g \
  --secret harbor-github-tools-clipfive --vendor-name 'EXAMPLECO API GitHub' --value-clipboard >/dev/null 2>&1 < /dev/null
t_eq "the add still stores it" "$VAL" "$(readv harbor-github-tools-clipfive)"
t_eq "but the clipboard still holds it" "$VAL" "$(cat "$FAKE_CLIP")"
t_done
