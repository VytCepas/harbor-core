#!/usr/bin/env sh
# secret: values round-trip byte-exact, stay private, and no verb prints one (SEC-0, harbor#724).
# Every Keychain call goes to tests/cli/keychain-stub.sh, never the login Keychain.
# DEFERRED, needs a human at the keyboard: `--locked` raising the login-password prompt.
# Typed as the secret-test.sh shim (contracts/shims.tsv), $0 is a symlink: re-run from the file.
[ -L "$0" ] && exec sh "$(readlink "$0")" "$@"
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/../../cli/keychain-stub.sh"
TOOL="$T_ROOT/bin/secret"; PFX=zz-selftest; W="$T_TMP/work"; mkdir -p "$W"
BD="$HOME/.local/share/secret"; LOG="$KC_STUB/argv.log"
ACCT="${USER:-$(id -un)}"   # bin/secret's own fallback: a container has no $USER
# bin/secret serves only a ref the access register names (harbor#1205): n registers each name it hands out.
ACC="$T_TMP/access"; mkdir -p "$ACC"; export ACCESS_DIR="$ACC"
n()     { grep -qxF "    secret: $PFX-$1" "$ACC/register.md" 2>/dev/null || printf '\n## %s-%s\n\n    secret: %s-%s\n' "$PFX" "$1" "$PFX" "$1" >> "$ACC/register.md"; printf '%s-%s' "$PFX" "$1"; }
val()   { "$TOOL" run "$(n "$1")" V -- sh -c 'printf %s "$V"' 2>/dev/null; }
sha()   { shasum -a 256 < "$1" | cut -d' ' -f1; }
fsha()  { "$TOOL" withfile "$(n "$1")" -- shasum -a 256 '{}' 2>/dev/null | cut -d' ' -f1; }
there() { if [ -e "$1" ]; then echo present; else echo gone; fi; }
item()  { printf '%s/items/secret.%s@%s' "$KC_STUB" "$(n "$1")" "$ACCT"; }

t_section "a string round-trips exactly"
VAL='pk_112514370_ABCDEF0123456789'
printf '%s' "$VAL" | "$TOOL" put "$(n roundtrip)" >/dev/null 2>&1
t_eq "string round-trips byte-exact" "$VAL" "$(val roundtrip)"
t_has "run hands it to the child's environment" "$("$TOOL" run "$(n roundtrip)" V -- env 2>/dev/null)" "V=$VAL"
# The control reads a WRONG passphrase back from the item: it must be refused, never decoded.
cp "$(item roundtrip)" "$W/item"; printf 'v1:enc:not-the-passphrase' > "$(item roundtrip)"
t_exit "control: a passphrase that does not open the blob is refused" 1 "$TOOL" run "$(n roundtrip)" V -- true
cp "$W/item" "$(item roundtrip)"

t_section "an embedded newline survives (the cu.sh incident)"
NL="$(printf 'line1\nurl = "http://evil/"')"
printf '%s' "$NL" | "$TOOL" put "$(n newline)" >/dev/null 2>&1
t_eq "embedded newline survives intact" "$NL" "$(val newline)"

t_section "a pasted env line is refused, a multi-line file is not"
t_exit "NAME=value is refused" 1 sh -c 'printf "PW_EXT_TOKEN=abc123" | "$1" put "$2"' _ "$TOOL" "$(n envline)"
t_exit "...with a trailing newline too" 1 sh -c 'printf "PW_EXT_TOKEN=abc123\n" | "$1" put "$2"' _ "$TOOL" "$(n envline)"
t_has "...naming the fix" "$(printf 'PW_EXT_TOKEN=abc123' | "$TOOL" put "$(n envline)" 2>&1)" "only what follows the ="
t_exit "a two-line file that starts NAME= is stored" 0 sh -c 'printf "A_B=1\nC_D=2\n" | "$1" put "$2"' _ "$TOOL" "$(n envfile)"

t_section "files round-trip, text and binary, at the sizes that once broke"
printf '{"type":"service_account","private_key":"-----BEGIN\nabc\n-----END"}' > "$W/sa.json"
"$TOOL" putfile "$(n keyfile)" "$W/sa.json" >/dev/null 2>&1
t_eq "file round-trips byte-exact" "$(sha "$W/sa.json")" "$(fsha keyfile)"
for RAW in 90 96 99 534; do
  head -c "$RAW" /dev/zero | tr '\0' 'x' > "$W/sz"
  "$TOOL" putfile "$(n "sz$RAW")" "$W/sz" >/dev/null 2>&1
  t_eq "$RAW raw bytes round-trip" "$(sha "$W/sz")" "$(fsha "sz$RAW")"
done
# Every size is blob-backed: an inline mode would put the secret itself in argv.
t_eq "90 bytes is blob-backed" present "$(there "$BD/$(n sz90).enc")"
t_eq "534 bytes is blob-backed" present "$(there "$BD/$(n sz534).enc")"
t_eq "control: the blob holds no plaintext" 0 "$(grep -ac xxxxxxxxxx "$BD/$(n sz534).enc")"
mv "$BD/$(n sz534).enc" "$W/stash.enc"
t_exit "control: a missing blob fails" 1 "$TOOL" run "$(n sz534)" V -- true
t_has "and says the blob is missing" "$("$TOOL" run "$(n sz534)" V -- true 2>&1)" "is blob-backed but"
mv "$W/stash.enc" "$BD/$(n sz534).enc"
printf '\001\002\377\000\376' > "$W/bin.der"
"$TOOL" putfile "$(n binkey)" "$W/bin.der" >/dev/null 2>&1
t_eq "binary file round-trips byte-exact" "$(sha "$W/bin.der")" "$(fsha binkey)"

t_section "withfile materialises privately and always cleans up"
LEAK="$("$TOOL" withfile "$(n keyfile)" -- sh -c 'printf %s "$1"' _ '{}' 2>/dev/null)"
t_has "withfile hands the command its temp path" "$LEAK" "/$(n keyfile)"
t_eq "withfile removes the temp file on exit" gone "$(there "$LEAK")"
t_eq "control: the temp file exists DURING the command" present \
  "$("$TOOL" withfile "$(n keyfile)" -- sh -c '[ -f "$1" ] && echo present' _ '{}' 2>/dev/null)"
# BSD `stat -f %Lp`; GNU's -f is --file-system and prints a report, so fall back to -c %a (harbor#865).
t_eq "temp file is mode 600" 600 "$("$TOOL" withfile "$(n keyfile)" -- sh -c 'm="$(stat -f %Lp "$1" 2>/dev/null)"; case "$m" in ""|*[!0-7]*) m="$(stat -c %a "$1")" ;; esac; printf %s "$m"' _ '{}' 2>/dev/null)"
LEAK2="$("$TOOL" withfile "$(n keyfile)" -- sh -c 'printf %s "$1"; exit 3' _ '{}' 2>/dev/null)"
t_has "a failing command also gets its temp path" "$LEAK2" "/$(n keyfile)"
t_eq "withfile cleans up after a failing command" gone "$(there "$LEAK2")"

t_section "adopt verifies before it deletes"
printf 'pk_112514370_ZZZ\n' > "$W/service-token.txt"; AWANT="$(sha "$W/service-token.txt")"
"$TOOL" adopt "$W/service-token.txt" "$(n adopted)" >/dev/null 2>&1
t_eq "adopt removed the plaintext original" gone "$(there "$W/service-token.txt")"
t_eq "adopt stored the exact bytes" "$AWANT" "$(fsha adopted)"
: > "$W/empty.txt"  # an empty file makes store() refuse, so adopt must not delete it
"$TOOL" adopt "$W/empty.txt" "$(n emptyone)" >/dev/null 2>&1
t_eq "control: adopt keeps the original when the store fails" present "$(there "$W/empty.txt")"

t_section "no verb prints a secret"
t_exit "no 'get' verb exists" 1 "$TOOL" get "$(n roundtrip)"
LISTED="$("$TOOL" list 2>/dev/null)"
t_has "list shows the stored name" "$LISTED" "secret.$PFX-roundtrip"
t_hasnt "list prints no value" "$LISTED" "$VAL"

t_section "under a pty (the /dev/tty trap)"
# stdin is /dev/null so a regression that reads the tty again fails instead of hanging.
cat > "$W/ptycase.sh" <<PTYEOF
printf 'pty-value-123' | "$TOOL" put "$(n pty)" >/dev/null 2>&1
"$TOOL" run "$(n pty)" V -- sh -c 'printf %s "\$V"'
PTYEOF
# BSD `script -q FILE cmd...`; util-linux wants `script -qec "cmd" FILE` (harbor#865).
if [ "$(uname -s)" = Darwin ]; then PTYOUT="$(script -q /dev/null sh "$W/ptycase.sh" < /dev/null 2>/dev/null)"
else PTYOUT="$(script -qec "sh $W/ptycase.sh" /dev/null < /dev/null 2>/dev/null)"; fi
t_has "round-trips under a pty" "$(printf %s "$PTYOUT" | tr -d '\r\n')" pty-value-123
t_has "the pty case reached the stub, not the login Keychain" "$(cat "$LOG")" "secret.$PFX-pty|"

t_section "names, rm and --locked"
t_eq "rejects a name outside [A-Za-z0-9._-]" 1 "$(printf v | "$TOOL" put 'evil name' >/dev/null 2>&1; echo $?)"
"$TOOL" rm "$(n roundtrip)" >/dev/null 2>&1
t_exit "a removed secret is gone" 1 "$TOOL" run "$(n roundtrip)" V -- true
printf 'lk' | "$TOOL" put "$(n locked)" --locked >/dev/null 2>&1
t_has "--locked stores with -T \"\"" "$(grep "secret.$PFX-locked|" "$LOG" | grep add-generic)" "|-T||-w|"

t_section "an openssl that fails unread never strands the FIFO writer (harbor#768)"
# The passphrase writer blocks in open(2) until openssl opens the FIFO; one that exits first left it there.
mkdir -p "$W/ossl"; printf '#!/bin/sh\ncase "$1" in rand) echo cGFzc3BocmFzZQ== ;; *) exit 1 ;; esac\n' > "$W/ossl/openssl"
chmod +x "$W/ossl/openssl"; FN="$(n fifo)"
printf v | env PATH="$W/ossl:$PATH" "$TOOL" put "$FN" >/dev/null 2>&1 &
_fp=$!; _fi=0; while kill -0 "$_fp" 2>/dev/null && [ "$_fi" -lt 20 ]; do sleep 0.1; _fi=$((_fi + 1)); done
t_eq "put returns within 2s when openssl exits 1 unread" returned "$(kill -0 "$_fp" 2>/dev/null && echo hung || echo returned)"
pkill -9 -f "$FN" 2>/dev/null; wait "$_fp"; _frc=$?  # a hung run is reaped, so a red one leaks nothing
t_eq "…with a non-zero exit" 1 "$_frc"
t_eq "…and nothing of that run is left running" 0 "$(ps -A -o command= | awk -v d="$FN" 'index($0, d) && $1 != "awk"' | wc -l | tr -d ' ')"

t_section "argv carries a generated passphrase, never a value"
t_has "the Keychain write carries a v1:enc passphrase" "$(cat "$LOG")" "|-w|v1:enc:"
t_hasnt "no Keychain call carried the string value" "$(cat "$LOG")" "$VAL"
t_hasnt "no Keychain call carried the pty value" "$(cat "$LOG")" pty-value-123

t_section "Linux: libsecret (secret-tool) is the store when there is no Keychain (harbor#618)"
. "$T_ROOT/tests/lib/linux-sim.sh"; . "$(dirname "$0")/../../cli/libsecret-stub.sh"
LX="$T_TMP/lx"; libsecret_stub "$LX"; SLOG="$ST_STUB/argv.log"
lx() { PATH="$LX" "$TOOL" "$@"; }
lval() { PATH="$LX" "$TOOL" run "$(n "$1")" V -- sh -c 'printf %s "$V"' 2>/dev/null; }
t_eq "control: the Linux PATH has no security" "" "$(PATH="$LX" command -v security)"
LV='pk_linux_0123456789ABCDEF'
printf '%s' "$LV" | lx put "$(n lx)" >/dev/null 2>&1
t_eq "a string round-trips through secret-tool" "$LV" "$(lval lx)"
t_has "control: the value the argv checks below look for is the one stored" "$(lval lx)" "$LV"
t_has "...stored under the same service and account names" "$(cat "$SLOG")" "store|--label=secret.$PFX-lx|service|secret.$PFX-lx|account|$ACCT|"
t_hasnt "...and no secret-tool call carried the value in argv" "$(cat "$SLOG")" "$LV"
printf '{"k":"v"}\n' > "$W/lx.json"; lx putfile "$(n lxf)" "$W/lx.json" >/dev/null 2>&1
t_eq "a file round-trips through secret-tool" "$(sha "$W/lx.json")" "$(PATH="$LX" "$TOOL" withfile "$(n lxf)" -- shasum -a 256 '{}' 2>/dev/null | cut -d' ' -f1)"
_ll="$(lx list 2>/dev/null)"
t_has "list names what libsecret holds" "$_ll" "secret.$PFX-lx"
t_hasnt "...and prints no value" "$_ll" "$LV"
t_exit "--locked is refused: libsecret has no per-item prompt, so it would be a silent downgrade" 1 \
  sh -c 'printf lk | PATH="$1" "$2" put "$3" --locked' _ "$LX" "$TOOL" "$(n lxlocked)"
lx rm "$(n lx)" >/dev/null 2>&1
t_exit "a removed secret is gone" 1 env PATH="$LX" "$TOOL" run "$(n lx)" V -- true
rm -f "$LX/secret-tool"
t_exit "with neither store it refuses" 1 sh -c 'printf v | PATH="$1" "$2" put "$3"' _ "$LX" "$TOOL" "$(n lxnone)"
t_has "...naming both" "$(printf v | PATH="$LX" "$TOOL" put "$(n lxnone)" 2>&1)" "secret-tool"
t_done
