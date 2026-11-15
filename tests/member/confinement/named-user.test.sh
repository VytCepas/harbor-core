#!/usr/bin/env sh
# deploy-confinement.sh for a named member (harbor#1278, R3): root composes as --user with no SUDO_USER, and --member ignores the write zone.
# Root is simulated on a COPY with the PATH pin and the OS paths taken out, HOST-1's pattern, so stub id and sudo reach it and no real file is read.
. "$(dirname "$0")/../../lib/core.sh"; t_init
T_TMP="$(cd "$T_TMP" && pwd -P)"
C="$T_ROOT/bin/deploy-confinement.sh"
X="$T_TMP/x"; mkdir -p "$X/bin" "$X/contracts"
cp "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/scope-roots.sh" "$X/bin/"
cp "$T_ROOT/contracts/confinement-hosts.txt" "$T_ROOT/contracts/confinement-paths.txt" "$T_ROOT/contracts/roots.tsv" "$X/contracts/"
sed -e 's|^PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH$|:|' \
    -e "s|/Library/Application Support/ClaudeCode/managed-settings.json|$T_TMP/none/managed-settings.json|" \
    -e "s|/etc/claude-code/managed-settings.json|$T_TMP/none/managed-settings.json|" "$C" > "$X/bin/deploy-confinement.sh"
stub() { _s="$1"; shift; { printf '#!/bin/sh\n'; printf '%s\n' "$@"; } > "$_s"; chmod +x "$_s"; }
AHOME="$T_TMP/alice-home"; mkdir -p "$AHOME/port"; SUDO_CALLS="$T_TMP/sudo"; export AHOME SUDO_CALLS
# Root until sudo drops to the named user, as the real one would.
stub "$T_BIN/id" 'case "$*" in -u) echo "${FAKE_UID:-0}" ;; *) exec /usr/bin/id "$@" ;; esac'
stub "$T_BIN/sudo" 'printf "%s\n" "$*" >> "$SUDO_CALLS"' '[ "$1" = -u ] || exit 9' 'who="$2"; shift 2' '[ "$1" != -H ] || shift' 'if [ "$1" = env ]; then HOME="$AHOME" FAKE_UID=1001 exec "$@"; fi' 'exec "$@"'
stub "$T_BIN/bwrap" 'exit 0'; stub "$T_BIN/socat" 'exit 0'

t_section "root with no SUDO_USER (R3)"
OUT="$T_TMP/out"
RC=0; env -u SUDO_USER sh "$X/bin/deploy-confinement.sh" --dry-run >"$OUT" 2>"$OUT.err" || RC=$?
t_eq "no --user is still refused" 1 "$RC"; t_has "...as before" "$(cat "$OUT.err")" 'there is no operator to compose for'
RC=0; env -u SUDO_USER sh "$X/bin/deploy-confinement.sh" --dry-run --user alice >"$OUT" 2>"$OUT.err" || RC=$?
t_eq "--user composes" 0 "$RC"
t_eq "the write zone is the member's, not root's" "$AHOME/port" "$(jq -r '.sandbox.filesystem.allowWrite[0]' "$OUT")"
t_has "it dropped to that user with their HOME" "$(cat "$SUDO_CALLS")" '-u alice -H env PORT_ROOT= sh'
RC=0; SUDO_USER=it-admin sh "$X/bin/deploy-confinement.sh" --dry-run --user alice >"$OUT" 2>/dev/null || RC=$?
t_eq "--user wins over SUDO_USER: IT's own account gets nothing" "$AHOME/port" "$(jq -r '.sandbox.filesystem.allowWrite[0]' "$OUT")"
: > "$SUDO_CALLS"; RC=0; SUDO_USER=it-admin sh "$X/bin/deploy-confinement.sh" --dry-run >"$OUT" 2>/dev/null || RC=$?
t_has "CONTROL: without --user, SUDO_USER is who it was" "$(cat "$SUDO_CALLS")" '-u it-admin -H env'
RC=0; env -u SUDO_USER sh "$X/bin/deploy-confinement.sh" --compose --member --user alice >"$OUT" 2>/dev/null || RC=$?
t_eq "--compose --user drops too" "$AHOME/port" "$(jq -r '.filesystem.allowWrite[0]' "$OUT")"
t_eq "...keeping --member" false "$(jq .allowUnsandboxedCommands "$OUT")"
RC=0; env -u SUDO_USER sh "$X/bin/deploy-confinement.sh" --marker --user alice >"$OUT" 2>/dev/null || RC=$?
t_has "--marker --user too" "$(cat "$OUT")" 'confinement installed'

t_section "the bubblewrap probe runs as the member"
: > "$SUDO_CALLS"; RC=0; env -u SUDO_USER HARBOR_CONFINEMENT_OS=Linux FAKE_UID=1001 sh "$X/bin/deploy-confinement.sh" --preflight --user alice >/dev/null 2>&1 || RC=$?
t_eq "as a plain user it probes as itself" 0 "$RC"; t_eq "...with no sudo" 0 "$(wc -l < "$SUDO_CALLS" | tr -d ' ')"
# Under fake root the override is refused, so root's branch is read through its function.
op() { env -u SUDO_USER "$@" CONFINEMENT_LIB=1 sh -c '. "$0"; confine_operator "$1"' "$X/bin/deploy-confinement.sh" "$2" 2>/dev/null; }
t_eq "root with --user answers that user" alice "$(env -u SUDO_USER CONFINE_USER=alice CONFINEMENT_LIB=1 sh -c '. "$0"; CONFINE_USER=alice; confine_operator 0' "$X/bin/deploy-confinement.sh")"
t_eq "root with neither answers nothing, and fails" 1 "$(env -u SUDO_USER CONFINEMENT_LIB=1 sh -c '. "$0"; confine_operator 0 || echo $?' "$X/bin/deploy-confinement.sh")"
t_eq "SUDO_USER=root is no operator" 1 "$(SUDO_USER=root CONFINEMENT_LIB=1 sh -c '. "$0"; confine_operator 0 || echo $?' "$X/bin/deploy-confinement.sh")"
stub "$T_BIN/bwrap" 'exit 1'
RC=0; env -u SUDO_USER HARBOR_CONFINEMENT_OS=Linux FAKE_UID=1001 sh "$X/bin/deploy-confinement.sh" --preflight >"$OUT" 2>&1 || RC=$?
t_eq "a failing probe is a failing preflight" 1 "$RC"
stub "$T_BIN/bwrap" 'exit 0'

t_section "--user takes a name, not a shell word"
t_exit "a space" 2 sh "$C" --compose --user 'a b'
t_exit "a semicolon" 2 sh "$C" --compose --user 'a;b'
t_exit "a flag" 2 sh "$C" --compose --user --member
t_exit "nothing" 2 sh "$C" --compose --user

t_section "--member ignores the write zone (F4, R11); plain runs don't change"
mkdir -p "$HOME/port/harbor-private"
printf 'confinement_skip = "true"\n' > "$HOME/port/harbor-private/harbor.toml"
printf 'write /evil\n' > "$HOME/port/harbor-private/confinement-paths.txt"
plain="$(sh "$C" --compose)"; member="$(sh "$C" --compose --member)"
t_eq "plain: the retry stays open" true "$(printf '%s' "$plain" | jq .allowUnsandboxedCommands)"
t_eq "plain: no credential rows" null "$(printf '%s' "$plain" | jq -c .credentials)"
t_has "plain: the private layer is read" "$(printf '%s' "$plain" | jq -r '.filesystem.allowWrite[]')" /evil
t_has "plain: the skip is read" "$(sh "$C" --marker)" 'skip=covered'
t_eq "member: strict" false "$(printf '%s' "$member" | jq .allowUnsandboxedCommands)"
t_has "member: credential rows" "$(printf '%s' "$member" | jq -r '.credentials.files[].path')" '~/.ssh'
t_hasnt "member: no private row" "$(printf '%s' "$member" | jq -r '.filesystem.allowWrite[]')" /evil
t_hasnt "member: no skip" "$(sh "$C" --marker --member)" 'skip=covered'
t_done
