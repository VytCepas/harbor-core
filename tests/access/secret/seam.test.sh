#!/usr/bin/env sh
# secret seam: bin/secret itself, its import and run fixes, and the derive that no bin/ file calls a credential CLI
# directly (harbor#618). The callers' own probes (stape, stape-write, meta) left core with those tools for the
# measurement pack (harbor#1149). Fake values only. Keychain and libsecret are the stubs in keychain-stub.sh and
# libsecret-stub.sh. DEFERRED: a real Keychain or Secret Service.
[ -L "$0" ] && exec sh "$(readlink "$0")" "$@"
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/../../cli/keychain-stub.sh"
. "$T_ROOT/tests/lib/linux-sim.sh"; . "$(dirname "$0")/../../cli/libsecret-stub.sh"
BIN="$T_ROOT/bin"; W="$T_TMP/work"; mkdir -p "$W"; OUT="$W/out"
# bin/secret serves only a ref the access register names (harbor#1205): the probe names this suite uses are registered here.
export ACCESS_DIR="$W/access"; mkdir -p "$ACCESS_DIR"; export HARBOR_SCOPE_ROOT="$T_ROOT"   # a mutant copy of secret reads the checkout's tables, not its own parent
for _g in argvprobe stape-fresh stape-api meta-system-user-read; do printf '\n## %s\n\n    secret: %s\n' "$_g" "$_g" >> "$ACCESS_DIR/register.md"; done
ACCT="${USER:-$(id -un)}"
SKEY='FAKE-STAPE-KEY-0123456789abcdef'
MTOK="EAA$(printf 'a%.0s' $(seq 1 45))"
LX="$T_TMP/lx"; libsecret_stub "$LX"

reset() { rm -rf "$KC_STUB/items" "$ST_STUB/items" "$HOME/.local/share/secret"; mkdir -p "$KC_STUB/items" "$ST_STUB/items"
  : > "$KC_STUB/argv.log"; : > "$ST_STUB/argv.log"; }
# val <name> [bindir] [PATH] — what `secret run` hands a child, or nothing
val() { PATH="${3:-$PATH}" "${2:-$BIN}/secret" run "$1" V -- sh -c 'printf %s "$V"' 2>/dev/null; }
# mutant <caller> <exact line> <replacement>: a copy of bin/ holding the caller with that line replaced.
mutant() {
  _d="$W/mut-$1-$2"; rm -rf "$_d"; mkdir -p "$_d"
  cp "$BIN/secret" "$BIN/access.sh" "$BIN/scope-roots.sh" "$BIN/library-log.sh" "$_d/"; cp "$BIN/$1" "$_d/"
  M="$3" R="$4" awk '$0==ENVIRON["M"]{print ENVIRON["R"];next}{print}' "$BIN/$1" > "$_d/$1"; chmod +x "$_d/$1"
  cmp -s "$BIN/$1" "$_d/$1" && { echo "NOT-APPLIED"; return; }
  echo "$_d"
}

t_section "a stored secret reaches the child through secret, on macOS and on Linux, and no store argv"
reset; printf '%s' "$SKEY" | "$BIN/secret" put stape-api >/dev/null 2>&1
t_eq "macOS (Keychain stub): run hands the child the value" "$SKEY" "$(val stape-api)"
t_eq "control: the macOS run used a secret.-prefixed Keychain item" 1 "$(grep -c 'secret\.' "$KC_STUB/argv.log" | sed 's/^[1-9][0-9]*$/1/')"
t_eq "...and the value reached no Keychain argv" 0 "$(grep -cF "$SKEY" "$KC_STUB/argv.log")"
reset; printf '%s' "$MTOK" | PATH="$LX" "$BIN/secret" put meta-system-user-read >/dev/null 2>&1
t_eq "Linux (secret-tool stub, no security): run hands the child the value" "$MTOK" "$(val meta-system-user-read "$BIN" "$LX")"
t_eq "control: the Linux run used secret-tool" 1 "$(grep -c 'service|secret\.' "$ST_STUB/argv.log" | sed 's/^[1-9][0-9]*$/1/')"
t_eq "control: the Linux PATH has no security" "" "$(PATH="$LX" command -v security)"
t_eq "...and the value reached no secret-tool argv" 0 "$(grep -cF "$MTOK" "$ST_STUB/argv.log")"
reset
t_exit "an absent secret: run exits 1" 1 "$BIN/secret" run stape-api V -- sh -c 'echo ran > "$0"' "$OUT"
t_eq "...and the child never ran" no "$([ -f "$OUT" ] && echo yes || echo no)"
t_has "...and the refusal names the secret" "$("$BIN/secret" run stape-api V -- true 2>&1)" "no secret named 'stape-api'"

t_section "an item an older tool stored under its own service name moves with secret import"
reset
security add-generic-password -s stape-api -a "$ACCT" -w "$SKEY"
security add-generic-password -s meta-system-user-read -a "$ACCT" -w "$MTOK"
t_eq "before import the new route does not see the old item" "" "$(val stape-api)"
"$BIN/secret" import stape-api stape-api >/dev/null 2>&1
"$BIN/secret" import meta-system-user-read meta-system-user-read >/dev/null 2>&1
t_eq "after import secret serves the old key" "$SKEY" "$(val stape-api)"
t_eq "...and the old token" "$MTOK" "$(val meta-system-user-read)"
t_hasnt "import printed no value" "$("$BIN/secret" import stape-api stape-api 2>&1)" "$SKEY"
t_exit "import of an absent service is refused" 1 "$BIN/secret" import no-such-service x
t_exit "import wants two names" 2 "$BIN/secret" import only-one
reset; printf '%s' "$SKEY" | PATH="$LX" secret-tool store --label=old service stape-api account "$ACCT"
PATH="$LX" "$BIN/secret" import stape-api stape-api >/dev/null 2>&1
t_eq "import works on libsecret too" "$SKEY" "$(val stape-api "$BIN" "$LX")"

# ── import never replaces a stored secret unless told to (the harbor#1112 review: a rotated key was lost) ──
t_section "import refuses to overwrite an existing secret, and --force replaces it"
OLDK=OLD-REVOKED-KEY; NEWK=NEW-ROTATED-KEY
cur() { "${1:-$BIN}/secret" run stape-api V -- sh -c 'printf %s "$V"' 2>/dev/null; }
seed() { # macOS stub: a rotated key under secret, an old raw item under the service name
  reset; printf '%s' "$NEWK" | "$BIN/secret" put stape-api >/dev/null 2>&1
  security add-generic-password -s stape-api -a "$ACCT" -w "$OLDK"; }
seed
t_has "control: before the import secret holds the rotated key" "$(cur)" "$NEWK"
t_has "control: the older raw item holds the old one, so the refusal could leak either" "$(cat "$KC_STUB/items/stape-api@$ACCT")" "$OLDK"
t_exit "import onto a name that already holds a secret is refused" 1 "$BIN/secret" import stape-api stape-api
t_eq "...and the rotated key is untouched" "$NEWK" "$(cur)"
_r="$("$BIN/secret" import stape-api stape-api 2>&1)"
t_has "...and the refusal names --force" "$_r" "--force"
t_hasnt "...and prints neither value" "$_r" "$OLDK"
t_hasnt "...nor the rotated one" "$_r" "$NEWK"
t_has "the help text documents --force" "$("$BIN/secret" help 2>&1)" "import <service> <name> [--force]"
t_exit "--force replaces it" 0 "$BIN/secret" import stape-api stape-api --force
t_eq "...with the old item's value" "$OLDK" "$(cur)"
t_exit "import onto a free name needs no --force" 0 "$BIN/secret" import stape-api stape-fresh
t_exit "a third operand other than --force is a usage error" 2 "$BIN/secret" import stape-api stape-api --frce
reset; printf '%s' "$NEWK" | PATH="$LX" "$BIN/secret" put stape-api >/dev/null 2>&1
printf '%s' "$OLDK" | PATH="$LX" secret-tool store --label=old service stape-api account "$ACCT"
t_exit "libsecret: import onto a held name is refused" 1 env PATH="$LX" "$BIN/secret" import stape-api stape-api
t_eq "...and the rotated key is untouched" "$NEWK" "$(PATH="$LX" "$BIN/secret" run stape-api V -- sh -c 'printf %s "$V"' 2>/dev/null)"

# ── `secret run` keeps the value out of every argv (the harbor#1112 review: `exec env VAR=value` leaked it to ps) ──
t_section "secret run puts the value in the child's environment and in no argv"
SENT=FAKEKEY-SENTINEL-123; ENV_LOG="$W/env.log"; export ENV_LOG; EW="$W/envwrap"; mkdir -p "$EW"
# An `env` that logs its argv and its own ps line first on PATH, then does what env does: it sees what ps would.
printf '%s\n' '#!/bin/sh' '{ printf "env-argv: %s\n" "$*"; ps -o args= -p $$ 2>/dev/null || :; } >> "$ENV_LOG"' 'exec /usr/bin/env "$@"' > "$EW/env"
chmod +x "$EW/env"
argvprobe() { # <bindir> — what the child saw, with the env wrapper in front of PATH; the log is $ENV_LOG
  reset; : > "$ENV_LOG"; printf '%s' "$SENT" | "$1/secret" put argvprobe >/dev/null 2>&1
  PATH="$EW:$PATH" "$1/secret" run argvprobe V -- sh -c 'printf %s "$V"' 2>/dev/null; }
t_eq "the child still receives the full value" "$SENT" "$(argvprobe "$BIN")"
t_eq "no env call carried the value in its argv" 0 "$(grep -cF "$SENT" "$ENV_LOG")"
t_eq "...and secret made no env call at all" 0 "$(grep -c 'env-argv:' "$ENV_LOG")"

# ── the widened derive: a bare credential-CLI call anywhere in bin/*, extensionless included ──────────
# A call is `security <find|add|delete|dump>-…` or `secret-tool <lookup|store|clear|search>` in command position.
# Out of scope: bin/secret and the guards. Any other file needs a header `# secret-seam: <why>`.
CALL='(^|[;&|(`{!]|\$\(|(^|[[:space:]])(then|else|do|if))[[:space:]]*(security[[:space:]]+(find|add|delete|dump)-[a-z-]+|secret-tool[[:space:]]+(lookup|store|clear|search))([[:space:]]|$)'
derive() { # <dir> — prints file:line for every undeclared bare call
  for _f in "$1"/*; do
    [ -f "$_f" ] || continue
    case "${_f##*/}" in secret|guard-*.sh|admission-*.sh|library-admission.sh) continue ;; esac
    head -40 "$_f" | grep -q '^# *secret-seam:' && continue
    grep -nE "$CALL" "$_f" | grep -v '^[0-9]*:[[:space:]]*#' | sed "s|^|${_f##*/}:|"
  done
}
t_section "derive: no undeclared bare credential-CLI call in bin/*"
t_eq "bin/* has none" "" "$(derive "$BIN")"
t_has "deploy-live-verify.sh declares itself macOS-only" "$(head -40 "$BIN/deploy-live-verify.sh")" "# secret-seam: macOS-only"
F="$W/fixture"; rm -rf "$F"; mkdir -p "$F"
printf '#!/bin/sh\nx=$(security find-generic-password -s k -w)\n' > "$F/extensionless"
printf '#!/bin/sh\nif secret-tool lookup service k account a; then :; fi\n' > "$F/linux.sh"
printf '#!/bin/sh\n# security find-generic-password is only prose here\necho ok\n' > "$F/prose.sh"
printf '#!/bin/sh\n# secret-seam: macOS-only, because a test said so\nsecurity delete-generic-password -s k\n' > "$F/declared.sh"
printf '#!/bin/sh\nsecurity add-generic-password -s k -w v\n' > "$F/guard-x.sh"
printf '#!/bin/sh\nsecurity add-generic-password -s k -w v\n' > "$F/secret"
_d="$(derive "$F")"
t_has "red: an extensionless script with a bare Keychain read is flagged" "$_d" "extensionless:2:"
t_has "red: a bare libsecret call is flagged" "$_d" "linux.sh:2:"
t_hasnt "a comment mentioning the CLI is not a call" "$_d" "prose.sh"
t_hasnt "a declared file is not flagged" "$_d" "declared.sh"
t_hasnt "the guards are out of scope" "$_d" "guard-x.sh"
t_hasnt "the seam itself is out of scope" "$_d" "secret:"
sed '/^# secret-seam:/,/^#   libsecret/d' "$BIN/deploy-live-verify.sh" > "$F/deploy-live-verify.sh"
t_has "red: live-verify without its declaration is flagged" "$(derive "$F")" "deploy-live-verify.sh:"

# ── red-proofs for bin/secret itself: each fix, reverted, fails the probe written for it ──────────────
t_section "red-proof: bin/secret without the run fix or the import guard fails its probes"
RUNFIX='    export "$VAR=$_val"'
MD="$(mutant secret run "$RUNFIX" '    exec env "$VAR=$_val" "$@"')"
t_eq "the exec-env mutant was built" 1 "$([ -d "$MD" ] && echo 1 || echo "$MD")"
t_eq "control: the unmutated run passes the same probe" 0 "$(argvprobe "$BIN" >/dev/null; grep -cF "$SENT" "$ENV_LOG")"
t_eq "the exec-env mutant still hands the child the value" "$SENT" "$(argvprobe "$MD")"
t_eq "red-proof: ...but the env wrapper saw the value in env's argv" 1 "$(grep -cF "env-argv: V=$SENT" "$ENV_LOG" | sed 's/^[1-9][0-9]*$/1/')"
GUARD="$(grep -F '[ "$FORCE" = 1 ] ||' "$BIN/secret")"
MD="$(mutant secret guard "$GUARD" '    :')"
t_eq "the no-guard mutant was built" 1 "$([ -d "$MD" ] && echo 1 || echo "$MD")"
seed; "$MD/secret" import stape-api stape-api >/dev/null 2>&1
t_eq "red-proof: without the guard import overwrites the rotated key" "$OLDK" "$(cur "$MD")"
FORCE_L='    if [ "${3:-}" = "--force" ]; then FORCE=1; set -- "$1" "$2"; fi'
MD="$(mutant secret force "$FORCE_L" '    :')"
t_eq "the no---force mutant was built" 1 "$([ -d "$MD" ] && echo 1 || echo "$MD")"
seed; "$MD/secret" import stape-api stape-api --force >/dev/null 2>&1; _rc=$?
t_eq "red-proof: without --force parsing, the flag is a usage error" 2 "$_rc"
t_eq "...and the rotated key is still there" "$NEWK" "$(cur "$MD")"
t_done
