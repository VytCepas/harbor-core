#!/usr/bin/env sh
# The harbor dispatcher (CLI-1, harbor#42): every CONTRACTS/cli.md verb dispatches and no other does,
# exit codes pass through verbatim, --json is refused where a verb has none, and a wrong HARBOR_BIN
# fails instead of falling back. Stub verbs in $T_TMP/sbin, so no real suite or installer runs;
# the unknown-flag section alone runs real scripts, only ones that refuse before any write.
. "$(dirname "$0")/../lib/core.sh"; t_init
unset HARBOR_BIN
H="$T_ROOT/bin/harbor"; SB="$T_TMP/sbin"; mkdir -p "$SB"
hb() { HARBOR_BIN="$SB" sh "$H" "$@" 2>&1; }  # the dispatcher against the stub tree
# `harbor <verb>` <TAB> script <TAB> the fixed words the verb passes first (harbor#800: `deploy.sh --only floor`).
VERBS_C="$(grep -E '^\| `harbor [a-z-]+` \| `[a-z0-9.-]+\.sh( [a-z0-9-]+)*` \|' "$T_ROOT/CONTRACTS/cli.md" \
  | sed -E 's/^\| `harbor ([a-z-]+)` \| `([a-z0-9.-]+\.sh)( ([a-z0-9 -]+))?` \|.*/\1 \2 \4/')"
VN="$(printf '%s\n' "$VERBS_C" | grep -c .)"
printf '%s\n' "$VERBS_C" | while read -r _v _s _rest; do
  [ -n "${_s:-}" ] || continue
  printf '#!/usr/bin/env sh\nprintf "STUB %s argv=%%s\\n" "$*"\nexit 0\n' "$_s" > "$SB/$_s"; chmod +x "$SB/$_s"
done

t_section "CLI1 every contracted verb dispatches"
t_eq "the contract parser found at least 11 verbs" yes "$([ "$VN" -ge 11 ] && echo yes || echo no)"
for v in $(printf '%s\n' "$VERBS_C" | awk '{print $1}'); do
  s="$(printf '%s\n' "$VERBS_C" | awk -v v="$v" '$1 == v { print $2 }')"
  a="$(printf '%s\n' "$VERBS_C" | awk -v v="$v" '$1 == v { $1 = ""; $2 = ""; sub(/^ +/, ""); print }')"
  t_eq "harbor $v reaches $s${a:+ $a}" "STUB $s argv=$a" "$(hb "$v")"
done

t_section "the install verbs go through deploy, the one live entry; verify names the live box (harbor#800)"
t_eq "harbor install --apply --live is deploy's floor component" "STUB deploy.sh argv=--only floor --apply --live" "$(hb install --apply --live)"
t_eq "harbor skills --live is deploy's skills component" "STUB deploy.sh argv=--only skills --live" "$(hb skills --live)"
t_eq "harbor inject --live is deploy's inject component" "STUB deploy.sh argv=--only inject --live" "$(hb inject --live)"
t_eq "harbor constitution --apply --live is deploy's constitution component" \
  "STUB deploy.sh argv=--only constitution --apply --live" "$(hb constitution --apply --live)"
t_eq "harbor deploy is deploy.sh whole: every argument through, none added (2026-09-30)" \
  "STUB deploy.sh argv=--apply --only floor,skills --with-b6 --live" "$(hb deploy --apply --only floor,skills --with-b6 --live)"
t_eq "harbor verify names the live box with --live, never through CLAUDE_CONFIG_DIR" "STUB floor-verify.sh argv=--live" "$(hb verify)"
t_eq "harbor restore stays restore.sh, the other live entry" "STUB restore.sh argv=--live" "$(hb restore --live)"
t_eq "harbor uninstall --apply --live is deploy's floor uninstall (harbor#808)" \
  "STUB deploy.sh argv=--only floor --uninstall --apply --live" "$(hb uninstall --apply --live)"
t_eq "no install or uninstall verb runs an installer bare" "" \
  "$(awk '/^VERBS="/{f=1;next} /^"$/{f=0} f && NF' "$H" | awk -F'\t' '$1 ~ /^(install|uninstall|skills|inject|constitution)$/ && $2 !~ /^deploy\.sh --only / { print $1 }')"
printf '#!/usr/bin/env sh\nprintf "argv="; for a in "$@"; do printf "[%%s]" "$a"; done; echo\n' > "$SB/deploy.sh"
t_eq "the fixed words come first, and a caller's quoted word stays one word" "argv=[--only][floor][--apply][a b]" \
  "$(hb install --apply "a b")"
t_eq "...and through harbor deploy, with no fixed word before them" "argv=[--live][a b]" "$(hb deploy --live "a b")"

t_section "the dispatcher claims no verb the contract does not"
awk '/^VERBS="/{f=1;next} /^"$/{f=0} f && NF' "$H" | awk -F'\t' '{print $1}' | sort > "$T_TMP/d.txt"
printf '%s\n' "$VERBS_C" | awk 'NF{print $1}' | sort > "$T_TMP/c.txt"
t_eq "the dispatcher's own verb table parsed, one row per contracted verb" "$VN" "$(grep -c . "$T_TMP/d.txt")"
t_eq "no dispatcher verb is absent from the contract" "" "$(comm -23 "$T_TMP/d.txt" "$T_TMP/c.txt")"

t_section "exit codes are the seam"
t_exit "an unknown verb" 2 hb nosuchverb
t_exit "--json on a verb without it is refused, not ignored" 2 hb lint --json
t_exit "--json on a verb that supports it passes through" 0 hb status --json

t_section "an unknown flag is a usage error, in the verbs that can prove it (CONTRACTS/cli.md:70)"
for v in fresh cite dash; do
  t_exit "harbor $v with an unknown flag" 2 sh "$H" "$v" --definitely-not-a-real-flag
done
t_exit "harbor restore with an unknown flag (harbor#765)" 2 sh "$H" restore --live --definitely-not-a-real-flag
t_exit "harbor fresh with no flag still runs (the guard is not over-broad)" 0 sh "$H" fresh
t_exit "harbor fresh --open, a documented flag, still runs" 0 sh "$H" fresh --open
t_exit "an unknown flag after a valid first one (harbor#226)" 2 sh "$H" fresh --open --definitely-not-a-real-flag
t_exit "a stray operand after a valid first one (harbor#226)" 2 sh "$H" fresh --open stray-operand

t_section "a missing script is 127, and a target's status is forwarded verbatim"
rm -f "$SB/restore.sh"
t_exit "a contracted verb whose script is absent" 127 hb restore
printf '#!/usr/bin/env sh\nexit 1\n'  > "$SB/lint-conventions.sh"
printf '#!/usr/bin/env sh\nexit 42\n' > "$SB/freshness.sh"
t_exit "a verb reporting 1 surfaces as 1, never remapped" 1 hb lint
t_exit "an arbitrary target status passes through unchanged" 42 hb fresh

t_section "arguments arrive unmangled"
# One bracket per argv word: the legacy stub printed "$*", which reads the same split or not.
printf '#!/usr/bin/env sh\nprintf "argv="; for a in "$@"; do printf "[%%s]" "$a"; done; echo\n' > "$SB/freshness.sh"
t_eq "a flag passes through" "argv=[--open]" "$(hb fresh --open)"
t_eq "a quoted argument arrives as one word" "argv=[two words]" "$(hb fresh "two words")"
cp "$SB/freshness.sh" "$SB/restore.sh"
t_eq "harbor restore passes every argument through (harbor#765)" "argv=[--apply][--dir][a b][--from][s]" \
  "$(hb restore --apply --dir "a b" --from s)"

t_section "help, version, and the no-argument case"
for a in help --help -h; do t_has "'$a' prints usage" "$(hb "$a")" "usage: harbor <verb>"; done
t_has "no argument prints usage" "$(hb)" "usage: harbor <verb>"
HELP="$(hb help)"
for v in $(printf '%s\n' "$VERBS_C" | awk '{print $1}'); do
  t_eq "help lists $v" 1 "$(printf '%s\n' "$HELP" | grep -cE "^  $v ")"
done
t_eq "version prints the contract version" 1 "$(hb version | grep -c 'contract v[0-9]')"

t_section "an explicit HARBOR_BIN that is wrong FAILS, never falls back"
t_exit "a bad HARBOR_BIN exits 127" 127 env HARBOR_BIN="$T_TMP/nonexistent" sh "$H" status
t_has "a bad HARBOR_BIN says it is refusing" "$(HARBOR_BIN="$T_TMP/nonexistent" sh "$H" status 2>&1)" "refusing to fall back"
t_section "its own failures are log lines on stderr: FAIL, the fix, the summary (harbor#771)"
hbe() { "$@" > "$T_TMP/hb.out" 2> "$T_TMP/hb.err"; echo $?; }  # the exit code; stdout and stderr kept apart
t_eq "a bad HARBOR_BIN exits 127" 127 "$(hbe env HARBOR_BIN="$T_TMP/nonexistent" sh "$H" status)"
t_eq "...with nothing on stdout" "" "$(cat "$T_TMP/hb.out")"
t_eq "...and FAIL, its fix, then the summary on stderr" \
  "$(printf '%s\n' "  FAIL: HARBOR_BIN=$T_TMP/nonexistent has no status-gen.sh — refusing to fall back" \
     '  fix: unset HARBOR_BIN' 'harbor: 0 ok, 1 failed, 0 warnings')" "$(cat "$T_TMP/hb.err")"
t_eq "the fix resolves it: unset, the dispatcher runs" 0 "$(hbe env -u HARBOR_BIN sh "$H" version)"
rm -f "$SB/restore.sh"  # the argv section above put one back
t_eq "a missing script exits 127" 127 "$(hbe env HARBOR_BIN="$SB" sh "$H" restore)"
t_has "...its FAIL names the script and where it looked" "$(cat "$T_TMP/hb.err")" \
  "  FAIL: restore.sh is not installed next to the dispatcher (looked in: $SB)"
t_has "...with no checkout to point at, the fix says where to look" "$(cat "$T_TMP/hb.err")" \
  '  fix: none automatic — see CONTRACTS/cli.md'
t_has "...then the summary" "$(tail -1 "$T_TMP/hb.err")" 'harbor: 0 ok, 1 failed, 0 warnings'
t_eq "a usage error is not a run" 2 "$(hbe env HARBOR_BIN="$SB" sh "$H" nosuchverb)"
t_hasnt "...so it prints no summary line" "$(cat "$T_TMP/hb.err")" 'harbor: 0 ok'
t_has "...only its usage message" "$(cat "$T_TMP/hb.err")" 'harbor: unknown verb "nosuchverb"'

t_section "with no log-lib.sh anywhere it still dispatches, and still names the fix"
NL="$T_TMP/nolog"; mkdir -p "$NL"; cp "$H" "$NL/harbor"
printf '#!/usr/bin/env sh\necho "STUB status"\n' > "$NL/status-gen.sh"
t_eq "the control: the stub tree has no log-lib.sh, nor does HOME" "no no" \
  "$([ -f "$NL/log-lib.sh" ] && echo yes || echo no) $([ -f "$HOME/port/harbor/bin/log-lib.sh" ] && echo yes || echo no)"
t_eq "a verb still dispatches" "STUB status" "$(sh "$NL/harbor" status 2>&1)"
t_eq "a missing script still exits 127" 127 "$(hbe sh "$NL/harbor" restore)"
t_eq "...naming what failed, then the fix" \
  "$(printf '%s\n' "harbor: restore.sh is not installed next to the dispatcher (looked in: $NL)" \
     '  fix: none automatic — see CONTRACTS/cli.md (which script each verb runs)')" "$(cat "$T_TMP/hb.err")"

t_section "a native Windows shell is refused before any verb runs, naming WSL2 (harbor#833)"
# `uname` stubbed on PATH; every stub verb would print STUB, so its absence is "nothing ran".
UB="$T_TMP/uname-bin"; mkdir -p "$UB"
for _u in MINGW64_NT-10.0 MSYS_NT-10.0 CYGWIN_NT-10.0; do
  printf '#!/bin/sh\necho %s\n' "$_u" > "$UB/uname"; chmod +x "$UB/uname"
  for _v in status deploy help; do
    t_eq "harbor $_v under $_u exits 1" 1 "$(hbe env PATH="$UB:$PATH" HARBOR_BIN="$SB" sh "$H" "$_v")"
    t_has "...naming WSL2" "$(cat "$T_TMP/hb.err")" "WSL2"
    t_hasnt "...having run nothing" "$(cat "$T_TMP/hb.out" "$T_TMP/hb.err")" "STUB"
  done
done
for _u in Linux Darwin; do
  printf '#!/bin/sh\necho %s\n' "$_u" > "$UB/uname"
  t_eq "the control: harbor status under $_u still dispatches" "STUB status-gen.sh argv=" \
    "$(env PATH="$UB:$PATH" HARBOR_BIN="$SB" sh "$H" status 2>&1)"
done

t_section "a checkout that holds the script makes the fix exact, and the fix works"
mkdir -p "$HOME/port/harbor/bin"; cp "$T_ROOT/bin/log-lib.sh" "$HOME/port/harbor/bin/"
printf '#!/usr/bin/env sh\necho "CHECKOUT restore $*"\n' > "$HOME/port/harbor/bin/restore.sh"
printf '#!/usr/bin/env sh\necho ok\n' > "$HOME/port/harbor/bin/status-gen.sh"
t_eq "a missing script in HARBOR_BIN exits 127" 127 "$(hbe env HARBOR_BIN="$SB" sh "$H" restore)"
_fx="$(sed -n 's/^  fix: //p' "$T_TMP/hb.err")"
t_eq "the fix names the checkout" "HARBOR_BIN='$HOME/port/harbor/bin' harbor restore" "$_fx"
t_eq "...and run as printed (harbor = this dispatcher), it reaches the script" "CHECKOUT restore --live" \
  "$(eval "$(printf '%s' "$_fx" | sed "s|harbor restore\$|sh '$H' restore --live|")" 2>&1)"
t_done
