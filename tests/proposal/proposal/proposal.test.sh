#!/usr/bin/env sh
# proposal.sh (harbor#44), against a throwaway checkout, never this one. The three that
# carry the design: there is no approve verb (3); a review signs the patch bytes, so an
# edit after review invalidates it (6); a patch touching the machinery is refused with no
# override (8, 8b).
. "$(dirname "$0")/../../lib/core.sh"; t_init
P="$T_ROOT/bin/proposal.sh"
R="$T_TMP/repo"; mkdir -p "$R/bin" "$R/hooks"
git -C "$R" init -q; git -C "$R" config user.email t@t; git -C "$R" config user.name t; git -C "$R" config commit.gpgsign false
printf 'v1\n' > "$R/bin/thing.sh"; printf 'g1\n' > "$R/bin/guard-x.sh"; printf 'm1\n' > "$R/bin/proposal.sh"
git -C "$R" add -A >/dev/null; git -C "$R" commit -qm base
pr() { HARBOR_SCOPE_REPO="$R" sh "$P" "$@" 2>/dev/null; }
err() { HARBOR_SCOPE_REPO="$R" sh "$P" "$@" 2>&1 >/dev/null; }
px() { _pl="$1"; _pw="$2"; shift 2; t_exit "$_pl" "$_pw" env HARBOR_SCOPE_REPO="$R" sh "$P" "$@"; }
clean() { git -C "$R" checkout -- . 2>/dev/null; git -C "$R" clean -fdq bin hooks 2>/dev/null; }
isdir() { [ -d "$1" ] && echo yes || echo no; }

t_section "1 · new: a packet needs a change and a falsifier"
px "an empty diff" 1 new p-empty --falsifier x
printf 'v2\n' > "$R/bin/thing.sh"
px "a missing --falsifier" 2 new p-nofals
pr new p1 --falsifier "the suite goes red" >/dev/null
t_eq "the patch is captured" yes "$([ -f "$R/proposals/p1/patch.diff" ] && echo yes || echo no)"
t_has "the packet is pending" "$(cat "$R/proposals/p1/meta")" "status=pending"
t_has "absent evidence is recorded as absent" "$(cat "$R/proposals/p1/evidence.md")" "NO EVIDENCE SUPPLIED"
clean

t_section "1b · an untracked file is refused, never silently dropped from the patch"
# A tracked change too, or the empty-diff gate refuses first and the case proves nothing.
printf 'v2\n' > "$R/bin/thing.sh"; printf 'new\n' > "$R/bin/brand-new.sh"
px "a diff missing an untracked file" 1 new p-untracked --falsifier x
t_has "the refusal names the omission" "$(err new p-untracked --falsifier x)" "the patch would omit these"
t_eq "the refused packet left no directory" no "$(isdir "$R/proposals/p-untracked")"
git -C "$R" add -N bin/brand-new.sh >/dev/null 2>&1
pr new p-intent --falsifier x >/dev/null
t_has "add -N brings the new file into the patch" "$(cat "$R/proposals/p-intent/patch.diff")" "brand-new"
t_eq "an accepted packet does leave its directory" yes "$(isdir "$R/proposals/p-intent")"
rm -rf "$R/proposals/p-intent"; git -C "$R" rm --cached -q bin/brand-new.sh 2>/dev/null; rm -f "$R/bin/brand-new.sh"; clean

t_section "2 · apply refuses an unreviewed packet"
px "an unreviewed packet" 1 apply p1

t_section "3 · there is no approve verb"
px "--approve" 2 review p1 --as bot --approve
t_has "--approve names the rule" "$(err review p1 --as bot --approve)" "there is no approve verb"
px "an anonymous verdict" 2 review p1 --refuted --reason x
px "a veto with no reason" 2 review p1 --as bot --refuted

t_section "4 · an unrefuted review lets a dry run through, and writes nothing"
pr review p1 --as bot >/dev/null
px "an unrefuted packet, dry run" 0 apply p1
t_eq "the dry run left the tree alone" v1 "$(cat "$R/bin/thing.sh")"

t_section "5 · a refutation blocks it"
pr review p1 --as skeptic --refuted --reason "breaks X" >/dev/null
px "a refuted packet with --apply" 1 apply p1 --apply
t_has "the refutation marks the packet" "$(cat "$R/proposals/p1/meta")" "status=vetoed"

t_section "6 · a review signs the patch bytes, not the packet name"
printf 'v3\n' > "$R/bin/thing.sh"
pr new p2 --falsifier "the suite goes red" >/dev/null
clean; pr review p2 --as bot >/dev/null
px "a clean reviewed packet" 0 apply p2
printf '\n# swapped after review\n' >> "$R/proposals/p2/patch.diff"
px "a patch edited after review" 1 apply p2 --apply
pr review p2 --as bot >/dev/null
px "a re-review of the new bytes" 0 apply p2

t_section "7 · floor-adjacent paths need --floor typed as well"
git -C "$R" checkout -- proposals 2>/dev/null || true
printf 'g2\n' > "$R/bin/guard-x.sh"
pr new p-floor --falsifier "floor-test goes red" >/dev/null
clean; pr review p-floor --as bot >/dev/null
px "a floor patch without --floor" 1 apply p-floor
t_has "the refusal names --floor" "$(err apply p-floor)" "refusing without --floor"
px "a floor patch with --floor" 0 apply p-floor --floor

t_section "8 · a patch touching the machinery is refused, with no override"
printf 'm2\n' > "$R/bin/proposal.sh"
px "a machinery packet at new" 1 new p-self --falsifier x
t_eq "the refused packet left no directory" no "$(isdir "$R/proposals/p-self")"
mkdir -p "$R/proposals/p-sneak/reviews"
printf 'slug=p-sneak\nstatus=pending\nfalsifier=x\n' > "$R/proposals/p-sneak/meta"
printf -- '--- a/bin/proposal.sh\n+++ b/bin/proposal.sh\n@@ -1 +1 @@\n-m1\n+m2\n' > "$R/proposals/p-sneak/patch.diff"
clean; pr review p-sneak --as bot >/dev/null
px "a swapped machinery patch, even with --apply --floor" 1 apply p-sneak --apply --floor
t_has "the refusal is the machinery gate" "$(err apply p-sneak --apply --floor)" "touches the packet machinery itself"

mkdir -p "$R/tests/proposal/proposal"; printf 's1\n' > "$R/tests/proposal/proposal/proposal.test.sh"
git -C "$R" add tests >/dev/null; git -C "$R" commit -qm suite >/dev/null
printf 's2\n' > "$R/tests/proposal/proposal/proposal.test.sh"
px "a packet touching the suite at its tests/obs path" 1 new p-suite --falsifier x
t_has "the suite is machinery too (harbor#667 moved it)" "$(err new p-suite --falsifier x)" "touches the packet machinery itself"
git -C "$R" checkout -- tests

t_section "8b · a delete and a rename both reach the gate (adversarial, 2026-08-13)"
clean; git -C "$R" checkout -- . 2>/dev/null
git -C "$R" rm -q bin/proposal.sh
px "a patch deleting the machinery" 1 new p-del --falsifier x
git -C "$R" checkout HEAD -- bin/proposal.sh 2>/dev/null; git -C "$R" reset -q
git -C "$R" mv bin/guard-x.sh bin/harmless.sh 2>/dev/null
pr new p-ren --falsifier x >/dev/null
t_has "the fixture rename produced a rename patch" "$(cat "$R/proposals/p-ren/patch.diff")" "guard-x"
clean; git -C "$R" checkout -- . 2>/dev/null; git -C "$R" reset -q --hard >/dev/null
pr review p-ren --as bot >/dev/null
px "a renamed guard stays in the floor tier" 1 apply p-ren
rm -rf "$R/proposals/p-ren" "$R/proposals/p-del"

t_section "9 · a dirty tree is refused; a clean one applies and records it"
printf 'dirty\n' > "$R/bin/other.sh"
px "apply into a dirty tree" 1 apply p2 --apply
rm -f "$R/bin/other.sh"
git -C "$R" add -A >/dev/null; git -C "$R" commit -qm packets >/dev/null
px "a clean apply" 0 apply p2 --apply
t_eq "apply changed the tree" v3 "$(cat "$R/bin/thing.sh")"
t_has "the status is recorded" "$(cat "$R/proposals/p2/meta")" "status=applied"

t_section "9b · new never blocks on stdin"
# A held-open FIFO, not a pipeline: the shell waits for every pipeline element, so a
# pipeline reads 3s whether or not the command touches stdin.
_F="$T_TMP/fifo"; rm -f "$_F"; mkfifo "$_F"
( exec 9>"$_F"; sleep 3 ) &
_t0="$(date +%s)"
HARBOR_SCOPE_REPO="$R" sh "$P" new p-nohang --falsifier x < "$_F" >/dev/null 2>&1
_t1="$(date +%s)"; wait
t_eq "new returned within a second on an open, silent stdin" yes "$([ $((_t1 - _t0)) -lt 2 ] && echo yes || echo "no ($((_t1 - _t0))s)")"
t_has "absent evidence is recorded" "$(cat "$R/proposals/p-nohang/evidence.md" 2>/dev/null)" "NO EVIDENCE SUPPLIED"
printf 'measured\n' | HARBOR_SCOPE_REPO="$R" sh "$P" new p-ev --falsifier x --evidence - >/dev/null 2>&1
t_has "--evidence - reads stdin" "$(cat "$R/proposals/p-ev/evidence.md" 2>/dev/null)" "measured"
rm -rf "$R/proposals/p-nohang" "$R/proposals/p-ev"

t_section "10 · count is pending-only (what the statusline shows)"
t_eq "p-floor and p-sneak pending; p1 vetoed, p2 applied" 2 "$(pr count)"
t_done
