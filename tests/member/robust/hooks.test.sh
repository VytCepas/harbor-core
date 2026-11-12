#!/usr/bin/env sh
# hooks.test.sh (harbor#1278) — the managed hooks, run as the managed settings spell them, against faults. The dispatcher fails closed; every other hook fails open.
# A budget is a bound the code states, asserted against the code. ROBUST_MUTANT=<id> plants a defect (lib.sh) to watch a property go red.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/member/robust/lib.sh"
DD='dd if=/dev/zero of=/dev/sda'
RID=r-0123456789abcdef
# A hub call is cut at BOARD seconds (HUB_BOARD_BOUND in bin/library-board.sh); curl's own --max-time 6 is at bin/hub-board.sh, and does not cover a hung secret store.
BOARD=10
t_eq "BOARD is the bound the code states" 1 "$(grep -c "HUB_BOARD_BOUND=$BOARD\$" "$T_ROOT/bin/library-board.sh")"
# Dispatcher: status, then file, one board call each. Post and note: one.
B_DISPATCH=$((2 * BOARD + 10)); B_ONE=$((BOARD + 5))

seed_request() { # an open request with a recorded approval, and the call that asked: what a hung consume or note has to talk to the board about
  mkdir -p "$HS/requests" "$HS/open" "$HS/used"
  printf '{"id":"%s","issue":5,"rule":"admission.dd-device","tier":"very-high","target":"file","label":"x"}\n' "$RID" > "$HS/requests/$RID.json"
  printf 'c1\n' > "$HS/requests/$RID.approved"
  printf 's-1\t0\tadmission.dd-device\tvery-high\tfile\t%s\n' "$RID" > "$HS/open/toolu_1"
}

t_section "1 - a hub that hangs does not hold a session"
fresh real; echo hang > "$MB/stub-board"
m_bash "$DD" > "$T_TMP/in"; h_run dispatch "$T_TMP/in"
h_blocked "the dispatcher, hub hung: blocked, not held" "$B_DISPATCH"
printf "  held %ss\n" "$H_SEC"
fresh real; echo hang > "$MB/stub-board"; seed_request
base post > "$T_TMP/in"; h_run post "$T_TMP/in"
h_open "post, hub hung: exit 0 inside the bound" "$B_ONE"
printf "  held %ss\n" "$H_SEC"
fresh real; echo hang > "$MB/stub-board"; seed_request; rm -f "$HS/open/toolu_1" "$HS/requests/$RID.approved"
base note > "$T_TMP/in"; h_run note "$T_TMP/in"
h_open "note, hub hung: exit 0 inside the bound" "$B_ONE"
printf "  held %ss\n" "$H_SEC"
t_done
