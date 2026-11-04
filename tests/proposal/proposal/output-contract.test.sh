#!/usr/bin/env sh
# proposal.sh's output follows contracts/logging.md (harbor#771): stdout is the verb's data (list, count, show, a dry
# run's files) and only that; every status line is log-lib's, on stderr; a FAIL is followed by its fix and a run ends
# with the summary. The checkout is a throwaway repo, never this one.
. "$(dirname "$0")/../../lib/core.sh"; t_init
P="$T_ROOT/bin/proposal.sh"; R="$T_TMP/repo"; mkdir -p "$R/bin"
git -C "$R" init -q; git -C "$R" config user.email t@t; git -C "$R" config user.name t; git -C "$R" config commit.gpgsign false
printf 'v1\n' > "$R/bin/thing.sh"; git -C "$R" add -A >/dev/null; git -C "$R" commit -qm base
run() { HARBOR_SCOPE_REPO="$R" sh "$P" "$@" >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?"; }
OUT() { cat "$T_TMP/out"; }; ERR() { cat "$T_TMP/err"; }
after_fail() { awk '/^  FAIL:/ { f = 1; next } f { print; exit }' "$T_TMP/err"; }

t_section "a refusal: FAIL, its fix, the summary, nothing on stdout"
t_eq "an empty diff exits 1" "exit 1" "$(run new p-empty --falsifier x)"
t_eq "stdout is empty" "" "$(OUT)"
t_has "the FAIL says what was refused" "$(ERR)" "  FAIL: empty diff"
t_has "the next line is its fix" "$(after_fail)" "  fix: make the change, then sh bin/proposal.sh new p-empty"
t_eq "the summary ends it" "proposal: 0 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "no legacy 'proposal: ' prefix line is left" 0 "$(ERR | grep -c '^proposal: [^0-9]')"
t_eq "a missing --falsifier exits 2" "exit 2" "$(run new p-nofals)"
t_has "its fix is the command with the flag" "$(after_fail)" "  fix: sh bin/proposal.sh new p-nofals --falsifier"
t_eq "a refusal with no command says none automatic" "exit 1" "$(printf 'v2\n' > "$R/bin/thing.sh"; printf 'x\n' > "$R/bin/proposal.sh"; git -C "$R" add -N bin/proposal.sh; run new p-self --falsifier x)"
t_has "the machinery gate has no fix to offer" "$(after_fail)" "  fix: none automatic — see"
git -C "$R" rm -q --cached bin/proposal.sh; rm -f "$R/bin/proposal.sh"

t_section "new, review, apply: each success is an ok line and a summary on stderr"
t_eq "new exits 0" "exit 0" "$(run new p1 --falsifier 'the suite goes red')"
t_eq "stdout is empty" "" "$(OUT)"
t_has "the ok line" "$(ERR)" "  ok: packet p1 created ("
t_eq "the summary" "proposal: 1 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "review exits 0" "exit 0" "$(run review p1 --as bot)"
t_has "the verdict is an ok line" "$(ERR)" "  ok: recorded bot verdict for p1 (refuted=false)"
git -C "$R" checkout -q -- bin; git -C "$R" add -A >/dev/null; git -C "$R" commit -qm packets
t_eq "a dry run exits 0" "exit 0" "$(run apply p1)"
t_has "stdout is the files it would touch" "$(OUT)" "bin/thing.sh"
t_has "the dry run says nothing was written" "$(ERR)" "  ok: every gate passed (dry run, nothing written)"
t_eq "--apply exits 0" "exit 0" "$(run apply p1 --apply)"
t_has "applied is an ok line" "$(ERR)" "  ok: applied p1"
t_has "the falsifier is a note" "$(ERR)" "  note: falsifier to run: the suite goes red"

t_section "list, count and show are data on stdout and log nothing"
t_eq "list exits 0" "exit 0" "$(run list)"
t_has "list prints the packet" "$(OUT)" "p1"
t_eq "list logs nothing" "" "$(ERR)"
t_eq "count prints a number" "0" "$(run count >/dev/null; OUT)"
t_eq "count logs nothing" "" "$(ERR)"
t_eq "show exits 0" "exit 0" "$(run show p1)"
t_has "show prints the meta" "$(OUT)" "slug=p1"
t_eq "show logs nothing" "" "$(ERR)"
t_eq "show of nothing exits 1" "exit 1" "$(run show nope)"
t_has "with a FAIL and its fix" "$(after_fail)" "  fix: sh bin/proposal.sh list"
t_done
