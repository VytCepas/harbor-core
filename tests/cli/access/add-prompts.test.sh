#!/usr/bin/env sh
# bin/access.sh's interactive `add` (harbor#1205): a missing field is asked for on a terminal, and an answer shaped like a
# credential is refused. Driven through a pseudo-terminal from script(1), so every prompt sees a real tty on stdin.
# A temp HOME, a temp HARBOR_SCOPE_PRIVATE and the file-backed keychain stub: no case reaches the login Keychain.
# Linux: script(1) is util-linux there (`script -qec "cmd" FILE`), the form tests/cli/secret-test.sh already uses.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/../keychain-stub.sh"
AX="$T_ROOT/bin/access.sh"; SC="$T_ROOT/bin/secret"
PV="$T_TMP/pv"; export HARBOR_SCOPE_PRIVATE="$PV" PORT_ROOT="$T_TMP/port"
sh "$T_ROOT/bin/scope.sh" install --private-only >/dev/null 2>&1
REG="$PV/access/register.md"
FAKECRED="ghp_$(printf 'a%.0s' $(seq 1 36))"
VAL="fake-pty-value-$(printf 'q%.0s' 1 2 3 4 5 6)-0123"
CASE="$T_TMP/add-case.sh"
command -v script >/dev/null 2>&1 || { echo "add-prompts: script(1) is not on PATH" >&2; exit 2; }

# ADD_PTY <answers> [value] — `access.sh add pty-token` under a pty. The field answers come first, then the value
# after a pause, so the value is typed once secret put has turned echo off (a person types it that way too). The
# input is held open a second after the last line: closing it early makes script(1) send EOF into the tty.
printf '#!/bin/sh\nexec sh "%s" add pty-token\n' "$AX" > "$CASE"
ADD_PTY() {
  if [ "$(uname -s)" = Darwin ]; then
    { printf '%s' "$1"; [ -z "${2:-}" ] || { sleep 1; printf '%s\n' "$2"; }; sleep 1; } | script -q /dev/null sh "$CASE"
  else
    { printf '%s' "$1"; [ -z "${2:-}" ] || { sleep 1; printf '%s\n' "$2"; }; sleep 1; } | script -qec "sh $CASE" /dev/null
  fi
}
# A transcript and an exit code, captured apart: the pipeline's status is script(1)'s, which is the child's.
PTY_RUN() { # <answers> [value] — sets OUT (the transcript) and RC
  ADD_PTY "$@" > "$T_TMP/pty.out" 2>&1; RC=$?
  OUT="$(tr -d '\r' < "$T_TMP/pty.out")"
}
ANSWERS='token
a pty test token
only in the prompt test
nothing real
anything
the suite
pty-token-ref
'

t_section "a full interactive add: every missing field is prompted, the entry is written, the value goes to the store"
PTY_RUN "$ANSWERS" "$VAL"
t_eq "add exits 0 under a pty" 0 "$RC"
t_has "prompted for the kind" "$OUT" "kind (account role app mailbox token):"
t_has "prompted for what it is" "$OUT" "what it is:"
t_has "prompted for when to use it" "$OUT" "when to use it:"
t_has "prompted for what it reaches" "$OUT" "what it reaches:"
t_has "prompted for what it cannot do" "$OUT" "what it cannot do:"
t_has "prompted for who granted it" "$OUT" "who granted it:"
t_has "prompted for the secret reference" "$OUT" "secret reference (empty for none):"
t_has "then prompted for the value, not echoed" "$OUT" "value for pty-token-ref (not echoed):"
t_has "the entry was written with the typed kind" "$(cat "$REG")" "## pty-token"
t_has "...with the typed fields" "$(cat "$REG")" "    what: a pty test token"
t_has "...and the grant" "$(cat "$REG")" "    grant: the suite"
t_has "...and the ref it names" "$(cat "$REG")" "    secret: pty-token-ref"
t_hasnt "the register holds no value" "$(cat "$REG")" "$VAL"
t_has "the store was written under the ref" "$(grep 'add-generic-password' "$KC_STUB/argv.log")" "secret.pty-token-ref|"
t_eq "the stored value reads back through the seam" "$VAL" "$("$SC" run pty-token-ref V -- sh -c 'printf %s "$V"' 2>/dev/null)"
t_has "the transcript says the value was stored" "$OUT" "stored secret.pty-token-ref"
t_hasnt "the transcript never shows the value (no echo at the value prompt)" "$OUT" "$VAL"
t_eq "check is green with the entry" 0 "$(sh "$AX" check >/dev/null 2>&1; echo $?)"

t_section "a credential-shaped answer typed at a prompt is refused, and nothing is written"
BEFORE="$(cksum < "$REG")"
PTY_RUN "token
$FAKECRED
only in the prompt test
nothing real
anything
the suite
cred-ref
"
t_eq "the refusal exits 2 under a pty" 2 "$RC"
t_has "and names the refusal" "$OUT" "a field is shaped like a credential value"
t_eq "the register is byte-for-byte what it was" "$BEFORE" "$(cksum < "$REG")"
t_eq "the ref is not registered" 1 "$(sh "$AX" has cred-ref >/dev/null 2>&1; echo $?)"
t_eq "the store was never reached for it" 0 "$(grep -c 'cred-ref' "$KC_STUB/argv.log")"

t_section "the prompt is the only way to fill a missing field: without a tty the same add is a usage error and writes nothing"
BEFORE="$(cksum < "$REG")"
t_eq "no tty, no flags: exit 2" 2 "$(sh "$AX" add untty-token </dev/null >/dev/null 2>&1; echo $?)"
t_eq "...and the register is unchanged" "$BEFORE" "$(cksum < "$REG")"
t_done
