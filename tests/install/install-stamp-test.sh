#!/usr/bin/env sh
# install-stamp.sh, the deploy-regression guard (harbor#115, #143): ordinary deploys pass, a
# source behind or diverged from the installed commit refuses and names what it would remove,
# unknown states disclose, stamps are per installer, and the live config dir needs --live.
# The script reads the repo it lives in, so each case runs a copy inside a throwaway checkout.
. "$(dirname "$0")/../lib/core.sh"; t_init
T="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"; R="$T/repo"; CFG="$T/stampcfg"  # not $CLAUDE_CONFIG_DIR, the gated one
mkdir -p "$R/bin" "$CFG"; cp "$T_ROOT/bin/install-stamp.sh" "$T_ROOT/bin/log-lib.sh" "$T_ROOT/bin/install-lib.sh" "$R/bin/"
g() { git -C "$R" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main
mk() { printf '%s\n' "$1" > "$R/f-$1"; g add "f-$1"; g commit -qm "$1"; }
mk one; C1="$(g rev-parse HEAD)"; mk two; C2="$(g rev-parse HEAD)"; mk three; C3="$(g rev-parse HEAD)"
st() { sh "$R/bin/install-stamp.sh" "$@" 2>&1; }
rc() { sh "$R/bin/install-stamp.sh" "$@" >/dev/null 2>&1; echo $?; }
stamp_as() { printf '%s %s x x\n' "$2" "$1" > "$CFG/.helm-install-stamp"; }
at() { g checkout -q "$1"; }

t_section "must not block: first install, same commit, forward deploy"
rm -f "$CFG/.helm-install-stamp"
t_eq "a first install (no stamp)" 0 "$(rc --check "$CFG" floor-install)"
t_has "explains the first install, as an ok line" "$(st --check "$CFG" floor-install)" "  ok: floor-install: no previous stamp in $CFG — first install"
at "$C3"; stamp_as "$C3" floor-install
t_eq "re-deploying the same commit" 0 "$(rc --check "$CFG" floor-install)"
stamp_as "$C1" floor-install
t_eq "an ordinary forward deploy" 0 "$(rc --check "$CFG" floor-install)"
t_has "says how far forward" "$(st --check "$CFG" floor-install)" "  ok: floor-install: moves forward 2"

t_section "the 2026-08-04 shape: a source behind the installed state"
at "$C1"; stamp_as "$C3" floor-install
t_eq "deploying a source behind" 1 "$(rc --check "$CFG" floor-install)"
O="$(st --check "$CFG" floor-install)"
t_has "the FAIL deploy reads: <who> would remove N installed commit(s) from <dir>" "$O" "  FAIL: floor-install would remove 2 installed commit(s) from $CFG — a regression"
t_eq "...followed by the fix: the installer's own --accept-loss, spelled so its gate takes it" \
  "  fix: sh $R/bin/floor-install.sh --apply --dir '$CFG' --accept-loss" "$(printf '%s\n' "$O" | grep -A1 '^  FAIL: ' | sed -n 2p)"
t_eq "names each lost commit on its own note line" 2 "$(printf '%s\n' "$O" | grep -cE '^  note: installed, not in the source: [0-9a-f]+ (two|three)$')"
t_eq "ends on the summary, one failure" "install-stamp: 0 ok, 1 failed, 0 warnings" "$(printf '%s\n' "$O" | tail -1)"
t_eq "every line is in the log shape (CONTRACTS/logging.md)" "" \
  "$(printf '%s\n' "$O" | grep -vE '^(  (ok|FAIL|WARN|note|skip|fix): |install-stamp: [0-9]+ ok, [0-9]+ failed, [0-9]+ warnings$)')"

t_section "diverged, not merely behind"
g checkout -q -b side "$C2"; printf 'side\n' > "$R/f-side"; g add f-side; g commit -qm side
stamp_as "$C3" floor-install
t_eq "a diverged source that drops an installed commit" 1 "$(rc --check "$CFG" floor-install)"
t_has "names the commit it would lose" "$(st --check "$CFG" floor-install)" "three"
stamp_as "$C2" floor-install; at main
t_eq "forward deploy with a side branch present" 0 "$(rc --check "$CFG" floor-install)"

t_section "unknown states disclose rather than block"
stamp_as "0000000000000000000000000000000000000000" floor-install
t_eq "an unrecognised stamped commit" 0 "$(rc --check "$CFG" floor-install)"
t_has "and it warns" "$(st --check "$CFG" floor-install)" "  WARN: floor-install: installed from 00000000"
t_has "...with a fix that fetches and re-asks" "$(st --check "$CFG" floor-install)" "  fix: git -C "
NG="$T/nogit"; mkdir -p "$NG/bin"; cp "$T_ROOT/bin/install-stamp.sh" "$T_ROOT/bin/log-lib.sh" "$T_ROOT/bin/install-lib.sh" "$NG/bin/"
t_eq "a non-git source tree" 0 "$(sh "$NG/bin/install-stamp.sh" --check "$CFG" floor-install >/dev/null 2>&1; echo $?)"
t_has "...said as a skip" "$(sh "$NG/bin/install-stamp.sh" --check "$CFG" floor-install 2>&1)" "  skip: floor-install: "

t_section "the stamp file: per installer, rewritten not appended"
rm -f "$CFG/.helm-install-stamp"; at main
st --write "$CFG" floor-install >/dev/null; st --write "$CFG" runtime-install >/dev/null
t_eq "two installers, two stamp lines" 2 "$(grep -c . "$CFG/.helm-install-stamp")"
st --write "$CFG" floor-install >/dev/null
t_eq "re-stamping replaces its line" 2 "$(grep -c . "$CFG/.helm-install-stamp")"
t_has "--show reports the other installer" "$(st --show "$CFG")" "runtime-install"
t_eq "--show is data: the stamp file, byte for byte, and no summary" "$(cat "$CFG/.helm-install-stamp")" "$(st --show "$CFG")"
at "$C1"; stamp_as "$C3" runtime-install
t_eq "a runtime-install stamp does not gate floor-install" 0 "$(rc --check "$CFG" floor-install)"
t_eq "the runtime-install rollback is caught" 1 "$(rc --check "$CFG" runtime-install)"

t_section "the install manifest's commits are judged too, and can only add a refusal (install standard §3)"
at main; SIDE="$(g rev-parse side)"
mrows() { printf '# m\n'; for _r in "$@"; do printf '%s\n' "$_r"; done; }  # <row…> → .harbor-manifest
stamp_as "$C3" floor-install
mrows "aaaa 100755 bin/x.sh floor-install $SIDE" > "$CFG/.harbor-manifest"
t_eq "a manifest row recording a commit this source lacks refuses, though the stamp is current" 1 "$(rc --check "$CFG" floor-install)"
O="$(st --check "$CFG" floor-install)"
t_has "...in the FAIL deploy reads, naming the manifest" "$O" "  FAIL: floor-install would remove 1 installed commit(s) from $CFG — a regression: installed $(printf %.8s "$SIDE") (recorded in $CFG/.harbor-manifest)"
t_has "...with the same --accept-loss fix" "$O" "  fix: sh $R/bin/floor-install.sh --apply --dir '$CFG' --accept-loss"
t_has "...and the stamp's own verdict is still printed first" "$(printf '%s\n' "$O" | head -1)" "  ok: floor-install: already at"
mrows "aaaa 100755 bin/x.sh runtime-install $SIDE" > "$CFG/.harbor-manifest"
t_eq "a row of another installer does not gate this one" 0 "$(rc --check "$CFG" floor-install)"
mrows "aaaa 100755 bin/x.sh floor-install $C1" "bbbb 100644 lib/y floor-install -" > "$CFG/.harbor-manifest"
t_eq "rows at an ancestor, and a row with no commit, pass" 0 "$(rc --check "$CFG" floor-install)"
t_has "...said once, as a note" "$(st --check "$CFG" floor-install)" "  note: floor-install: .harbor-manifest records 1 more installed commit(s)"
rm -f "$CFG/.helm-install-stamp"; mrows "aaaa 100755 bin/x.sh floor-install $SIDE" > "$CFG/.harbor-manifest"
t_eq "with no stamp, a manifest row is still judged: no first-install pass" 1 "$(rc --check "$CFG" floor-install)"
at "$C1"; stamp_as "$C3" floor-install; mrows "aaaa 100755 bin/x.sh floor-install $C1" > "$CFG/.harbor-manifest"
t_eq "the manifest cannot clear the stamp's refusal: rows at the source commit, stamp ahead" 1 "$(rc --check "$CFG" floor-install)"
rm -f "$CFG/.harbor-manifest"; at main

t_section "the live config dir needs --live, by resolved path (harbor#143)"
LV="$T/live"; mkdir -p "$LV"
live() { CLAUDE_CONFIG_DIR="$LV" sh "$R/bin/install-stamp.sh" --write "$@" >/dev/null 2>&1; echo $?; }
t_eq "--write to the live dir without --live" 1 "$(live "$LV" floor-install)"
_lvo="$(CLAUDE_CONFIG_DIR="$LV" sh "$R/bin/install-stamp.sh" --write "$LV" floor-install 2>&1)"
t_has "...a FAIL naming the dir" "$_lvo" "  FAIL: refusing to write the live config dir $LV without an explicit --live"
t_has "...and the fix that passes the gate" "$_lvo" "  fix: sh $R/bin/install-stamp.sh --write '$LV' floor-install --live"
t_eq "the refusal wrote nothing" no "$([ -f "$LV/.helm-install-stamp" ] && echo yes || echo no)"
live "$LV" floor-install --live >/dev/null
t_eq "--write --live writes the live stamp" yes "$([ -f "$LV/.helm-install-stamp" ] && echo yes)"
t_has "...and says so as an ok line" "$(CLAUDE_CONFIG_DIR="$LV" sh "$R/bin/install-stamp.sh" --write "$LV" floor-install --live 2>&1)" "  ok: floor-install: recorded at "
rm -f "$LV/.helm-install-stamp"; live "$LV/." floor-install >/dev/null
t_eq "a trailing /. does not defeat the gate" no "$([ -f "$LV/.helm-install-stamp" ] && echo yes || echo no)"
t_done
