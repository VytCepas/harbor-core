#!/usr/bin/env sh
# lint-conventions.sh, part: the mode is the register's (harbor#1422) — a rule takes its mode from its controls.tsv row,
# a titled tier is red, and an engine whose behaviour disagrees with its row is red. Each is shown red, then green.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
RP="$TMP/mode"
reg() { # <rule id> <mode> → a fixture register naming one lint rule at one mode
  printf 'id\tmode\ttype\tengine\tsurfaces\tmoment\tfunction\tstability\tsuccessor\towner\tred_proof\temitted\ttitle\n%s\t%s\tlint\tbin/lint-conventions.sh\t-\tci\tdetective\texperimental\t-\tlint\t-\t-\tfixture\n' "$1" "$2" > "$RP.reg"
}
runm() { # <rule id> <mode> <root> → exit status and output of that rule alone under that mode
  reg "$1" "$2"; HARBOR_LINT_CONTROLS="$RP.reg" HARBOR_SCOPE_ROOT="$3" sh "$LINT" --only "$1" 2>&1; printf 'exit=%s\n' "$?"
}

t_section "a bad() rule: the row flips the linter's exit with no other edit"
EK="$RP.ek"; rm -rf "$EK"; mkdir -p "$EK/bin" "$EK/contracts"; printf '#!/usr/bin/env sh\n# fixture (harbor#1422)\n' > "$EK/bin/y.sh"
printf 'kind\tshape\tsubject\temitter\tmeaning\nx.done\tterminal\ts\tbin/y.sh\tm\n' > "$EK/contracts/event-kinds.tsv"
_o="$(runm event.kind-registered block "$EK")"
t_has "block: the finding is a VIOLATION" "$_o" 'VIOLATION [event.kind-registered]'
t_has "block: the run exits 1" "$_o" 'exit=1'
_o="$(runm event.kind-registered warn "$EK")"
t_has "warn: the same finding prints as an ADVISORY" "$_o" 'ADVISORY [event.kind-registered]'
t_hasnt "warn: it is no violation" "$_o" 'VIOLATION [event.kind-registered]'
t_has "warn: the run exits 0" "$_o" 'exit=0'
_o="$(runm event.kind-registered shadow "$EK")"
t_hasnt "shadow: nothing is printed for the rule" "$_o" '[event.kind-registered]'
t_has "shadow: the run exits 0" "$_o" 'exit=0'
RL="$RP.red"; : > "$RL"; reg event.kind-registered shadow
LINT_REDLOG="$RL" HARBOR_LINT_CONTROLS="$RP.reg" HARBOR_SCOPE_ROOT="$EK" sh "$LINT" --only event.kind-registered > /dev/null 2>&1 || :
t_has "shadow: the rule is still recorded in LINT_REDLOG" "$(cat "$RL")" 'event.kind-registered'

t_section "an _adv rule: warn to block turns its finding into a failure"
LF="$RP.lf"; rm -rf "$LF"; mkdir -p "$LF/bin"; { printf '#!/usr/bin/env sh\n# fixture (harbor#1422)\n'; i=0; while [ "$i" -lt 320 ]; do printf 'echo %s\n' "$i"; i=$((i+1)); done; } > "$LF/bin/long.sh"
_o="$(runm lint.long-file-reason warn "$LF")"
t_has "warn: advisory" "$_o" 'ADVISORY [lint.long-file-reason]'
t_has "warn: exit 0" "$_o" 'exit=0'
_o="$(runm lint.long-file-reason block "$LF")"
t_has "block: the same finding is a VIOLATION" "$_o" 'VIOLATION [lint.long-file-reason]'
t_has "block: exit 1" "$_o" 'exit=1'
_o="$(runm lint.long-file-reason shadow "$LF")"
t_hasnt "shadow: silent" "$_o" '[lint.long-file-reason]'
t_has "shadow: exit 0" "$_o" 'exit=0'

t_section "no row, no change: a tree without a register keeps each call's old default"
printf 'id\tmode\n' > "$RP.empty"
_o="$(HARBOR_LINT_CONTROLS="$RP.empty" HARBOR_SCOPE_ROOT="$EK" sh "$LINT" --only event.kind-registered 2>&1; printf 'exit=%s\n' "$?")"
t_has "bad() with no row blocks" "$_o" 'exit=1'
_o="$(HARBOR_LINT_CONTROLS="$RP.empty" HARBOR_SCOPE_ROOT="$LF" sh "$LINT" --only lint.long-file-reason 2>&1; printf 'exit=%s\n' "$?")"
t_has "_adv with no row advises" "$_o" 'exit=0'

t_section "lint.mode-matches-engine: the event.kind-registered shape is red (harbor#1422)"
SRC1="$RP.src"
# the shape the rule had before: every failure is a fixed block while its row says warn
printf 'rule_event_kind_registered() {\nrule "event.kind-registered every kind is registered (harbor#1367)"\n_hard event.kind-registered "x"\n}\n' > "$SRC1"
reg event.kind-registered warn
_o="$(HARBOR_LINT_SOURCE="$SRC1" HARBOR_LINT_CONTROLS="$RP.reg" HARBOR_SCOPE_ROOT="$EK" sh "$LINT" --only lint.mode-matches-engine 2>&1)"
t_has "RED: fixed-block calls under a warn row" "$_o" 'event.kind-registered: every failure it raises is _hard, so it blocks whatever its row says; the row says warn'
reg event.kind-registered block
_o="$(HARBOR_LINT_SOURCE="$SRC1" HARBOR_LINT_CONTROLS="$RP.reg" HARBOR_SCOPE_ROOT="$EK" sh "$LINT" --only lint.mode-matches-engine 2>&1)"
t_hasnt "GREEN: the same calls under a block row" "$_o" 'every failure it raises'
printf 'rule_x() {\nrule "x.y a rule that only notes"\n_advn x.y s\n}\n' > "$SRC1"; reg x.y block
_o="$(HARBOR_LINT_SOURCE="$SRC1" HARBOR_LINT_CONTROLS="$RP.reg" HARBOR_SCOPE_ROOT="$EK" sh "$LINT" --only lint.mode-matches-engine 2>&1)"
t_has "RED: a rule that only notes under a block row can never fail" "$_o" 'x.y: it only ever notes, so it can never fail; the row says block'
printf 'rule_x() {\nrule "x.y a rule with a tier in its title (block)"\nbad x.y m\n}\n' > "$SRC1"; reg x.y block
_o="$(HARBOR_LINT_SOURCE="$SRC1" HARBOR_LINT_CONTROLS="$RP.reg" HARBOR_SCOPE_ROOT="$EK" sh "$LINT" --only lint.mode-matches-engine 2>&1)"
t_has "RED: a title that names its tier" "$_o" 'x.y: the title names a tier'
printf 'rule_x() {\nrule "x.y a rule with a moded call"\nbad x.y m\n}\n' > "$SRC1"; reg x.y warn
_o="$(HARBOR_LINT_SOURCE="$SRC1" HARBOR_LINT_CONTROLS="$RP.reg" HARBOR_SCOPE_ROOT="$EK" sh "$LINT" --only lint.mode-matches-engine 2>&1)"
t_hasnt "GREEN: a moded call takes whatever its row says" "$_o" 'VIOLATION'
t_hasnt "...and ADVISORY" "$_o" 'ADVISORY [lint.mode-matches-engine] x.y'

t_section "lint.mode-matches-engine: an injection pack that can deny is a block row"
PK="$RP.pk"; rm -rf "$PK"; mkdir -p "$PK/context-rules/user"
printf -- '---\nid: can-deny\nevent: PreToolUse\ntool: Bash\nwhen: always\nrun: d.sh\n---\n' > "$PK/context-rules/user/can-deny.md"
printf '#!/bin/sh\nprintf "HARBOR-DECISION deny: no\\n"\n' > "$PK/context-rules/user/d.sh"
printf -- '---\nid: only-note\nevent: PreToolUse\ntool: Bash\nwhen: always\n---\nnote\n' > "$PK/context-rules/user/only-note.md"
injreg() { printf 'id\tmode\ttype\tengine\tsurfaces\tmoment\tfunction\tstability\tsuccessor\towner\tred_proof\temitted\ttitle\ncontext.can-deny\t%s\tinjection\tx\t-\truntime\tpreventive\texperimental\t-\tcontext\t-\tcan-deny\tt\ncontext.only-note\t%s\tinjection\tx\t-\truntime\tpreventive\texperimental\t-\tcontext\t-\tonly-note\tt\n' "$1" "$2" > "$RP.reg"; }
printf '#\n' > "$RP.nosrc"
inj() { HARBOR_LINT_SOURCE="$RP.nosrc" HARBOR_LINT_CONTROLS="$RP.reg" HARBOR_SCOPE_ROOT="$PK" sh "$LINT" --only lint.mode-matches-engine 2>&1; }
injreg warn warn
t_has "RED: a pack that can deny, row warn" "$(inj)" 'pack can-deny can deny'
injreg block block
t_has "RED: a block row on a pack that cannot deny" "$(inj)" 'pack only-note cannot deny'
injreg block warn
t_eq "GREEN: deny-capable is block, the note-only pack is warn" "" "$(inj | grep -E '(VIOLATION|ADVISORY) \[lint.mode-matches-engine\]')"
t_section "lint.advisory-recorded still reads the print sites _advp and _advm (harbor#1422)"
FLR="$RP.fl"; rm -rf "$FLR"; mkdir -p "$FLR/bin"
printf "_advp '  ADVISORY [x.y] z\\n'\n" > "$FLR/bin/lint-conventions.sh"
t_has "RED: an _advp line with no _adv before it" "$(lint1 lint.advisory-recorded "$FLR")" 'prints ADVISORY [x.y] with no `_adv x.y <subject>`'
printf '_advm "  ADVISORY [x.y] z"\n' > "$FLR/bin/lint-conventions.sh"
t_has "RED: an _advm line with no _adv before it" "$(lint1 lint.advisory-recorded "$FLR")" 'prints ADVISORY [x.y]'
printf "_adv x.y s; _advp '  ADVISORY [x.y] z\\n'\n_advn x.y s; _advm \"  ADVISORY [x.y] z\"\n" > "$FLR/bin/lint-conventions.sh"
t_eq "GREEN: _adv or _advn on the line" "" "$(lint1 lint.advisory-recorded "$FLR" | grep -F 'VIOLATION')"
t_section "drift.check-register: checks.md and the check rows are one register, cell for cell (harbor#1422)"
CR="$RP.cr"; rm -rf "$CR"; mkdir -p "$CR/docs/reference"
crmd() { printf '## Register\n\n| id | watches | schedule | notifies | red means |\n|---|---|---|---|---|\n%s\n\n## Platforms\n' "$1" > "$CR/docs/reference/checks.md"; }
crreg() { # <id> <moment> <red_proof> [emitted]
  printf 'id\tmode\ttype\tengine\tsurfaces\tmoment\tfunction\tstability\tsuccessor\towner\tred_proof\temitted\ttitle\n%s\twarn\tcheck\tx\t-\t%s\tdetective\texperimental\t-\tcheck\t%s\t%s\tt\n' "$1" "$2" "$3" "${4:--}" > "$RP.reg"; }
crrun() { HARBOR_LINT_CONTROLS="$RP.reg" HARBOR_SCOPE_ROOT="$CR" sh "$LINT" --only drift.check-register 2>&1; }
crmd '| `a.one` | w | every 300s; falsifier: `sh tests/x/a.test.sh` | n | r |'
crreg check.a.one schedule tests/x/a.test.sh a.one
t_eq "GREEN: id, falsifier and schedule agree" "" "$(crrun | grep -E '(VIOLATION|ADVISORY) \[' )"
crreg check.a.one schedule tests/x/b.test.sh a.one
t_has "RED: red_proof names a different suite than the schedule cell" "$(crrun)" 'the schedule cell names the falsifier tests/x/a.test.sh and red_proof is tests/x/b.test.sh'
crreg check.a.one schedule - a.one
t_has "RED: the cell names a falsifier and red_proof is empty" "$(crrun)" 'red_proof is -'
crmd '| `a.one` | w | not scheduled: a person types it | n | r |'; crreg check.a.one schedule - a.one
t_has "RED: not scheduled in the cell, schedule in the row" "$(crrun)" 'says not scheduled and the moment is schedule'
crreg check.a.one manual - a.one
t_eq "GREEN: manual and not scheduled" "" "$(crrun | grep -E '(VIOLATION|ADVISORY) \[' )"
crmd '| `a.one` | w | not scheduled | n | r |
| `b.two` | w | not scheduled | n | r |'
t_has "RED: a check in checks.md with no row" "$(crrun)" 'b.two: checks.md has the check and controls.tsv has no row'
crmd '| `b.two` | w | not scheduled | n | r |'
t_has "RED: a row whose check is not in checks.md" "$(crrun)" 'controls.tsv has the check row and checks.md has no row for it'
t_done
