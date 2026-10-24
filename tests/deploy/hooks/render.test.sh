#!/usr/bin/env sh
# deploy-hooks.sh (harbor#1272 step 5): hook wiring rendered from manifests, fail closed, desired state for harbor's own
# entries only, one off contract (<engine>.off, removed by hand stays removed). Fixture trees are written here.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/deploy-hooks.sh"
T="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"
R="$T/root"; CFG="$T/cfg"
# engine <name> <manifest wire rows…> — a valid engine folder: the script, and a manifest with one wire row per argument.
engine() {
  _n="$1"; shift; mkdir -p "$R/hooks/$_n"; printf '#!/bin/sh\nexit 0\n' > "$R/hooks/$_n/$_n.sh"
  { printf '# fixture\nkey\tvalue\nengine\t%s\n' "$_n"
    for _w in "$@"; do printf 'wire\t%s\n' "$_w"; done
    printf 'senses\tthe payload\nacts-on\tnothing\nfindings\tstderr\ncloser\tnobody\n'; } > "$R/hooks/$_n/manifest.tsv"
}
fresh() {
  rm -rf "$R" "$CFG"; mkdir -p "$R/standards/naming" "$CFG/bin"
  printf '# renames\nrename-0001\tbin/old-alpha.sh\thooks/alpha/alpha.sh\tpath\tP1\t-\tfixture\n' > "$R/standards/naming/renames.tsv"
  engine alpha "Stop	-	-"
  engine beta "PreToolUse	Bash	30" "SessionStart	-	5"
  for _e in alpha beta; do printf '#!/bin/sh\n' > "$CFG/bin/$_e.sh"; done
}
run() { # <mode> [args…] — stdout in $OUT, stderr in $ERR, exit in $RC
  _m="$1"; shift
  sh "$TOOL" "$_m" "$@" --root "$R" > "$T/out" 2> "$T/err"; RC=$?; OUT="$(cat "$T/out")"; ERR="$(cat "$T/err")"
}
settings() { run --settings "$CFG" "$@"; [ "$RC" != 0 ] || printf '%s\n' "$OUT" > "$CFG/settings.json"; }
cmds() { jq -r '[.hooks // {} | to_entries[] | .key as $e | .value[] | .matcher as $m | .hooks[] | "\($e)|\($m)|\(.timeout // "-")|\(.command)"] | sort | .[]' "$CFG/settings.json"; }
A="/bin/sh $CFG/bin/alpha.sh"; B="/bin/sh $CFG/bin/beta.sh"

t_section "a valid tree checks clean and renders its bindings exactly"
fresh
run --check; t_eq "--check exits 0" 0 "$RC"; t_has "...counts the bindings" "$ERR" "2 engine(s), 3 binding(s)"
settings; t_eq "--settings exits 0 on an empty config dir" 0 "$RC"
t_eq "the three bindings, matcher - as \"\", timeout only where given" \
  "PreToolUse|Bash|30|$B
SessionStart||5|$B
Stop||-|$A" "$(cmds)"
first="$(jq -S . "$CFG/settings.json")"; settings
t_eq "a second render changes nothing" "$first" "$(jq -S . "$CFG/settings.json")"
run --plan "$CFG"; t_has "...and the plan says keep" "$OUT" "keep	alpha	Stop"; t_hasnt "...with nothing to wire" "$OUT" "wire	"

t_section "every manifest defect is refused, with nothing on stdout"
bad() { # <label> <expected message part> — after the caller broke the fixture
  run --settings "$CFG"; t_eq "$1: exit 1" 1 "$RC"; t_eq "$1: stdout empty" "" "$OUT"; t_has "$1: says why" "$ERR" "$2"
}
fresh; printf 'engine\tgamma\n' >> "$R/hooks/alpha/manifest.tsv"; bad "engine named twice" "\`engine\` must appear once"
fresh; sed 's/^engine\talpha/engine\tother/' "$R/hooks/alpha/manifest.tsv" > "$T/m"; mv "$T/m" "$R/hooks/alpha/manifest.tsv"; bad "engine is not its folder" "is not its folder"
fresh; rm "$R/hooks/alpha/alpha.sh"; bad "no script beside the manifest" "no alpha.sh beside the manifest"
fresh; printf 'mode\tblock\n' >> "$R/hooks/alpha/manifest.tsv"; bad "an unknown key" "unknown key \`mode\`"
fresh; engine gamma "Stopp	-	-"; printf '#!/bin/sh\n' > "$CFG/bin/gamma.sh"; bad "a misspelt event" "\`Stopp\` is not a hook event"
fresh; engine gamma "Stop	-	0"; bad "timeout 0" "timeout \`0\`"
fresh; engine gamma "Stop	-	601"; bad "timeout 601" "timeout \`601\`"
fresh; engine gamma "Stop		-"; bad "an empty matcher" "an empty matcher is written"
fresh; engine gamma "Stop	-	-" "Stop	-	5"; bad "one event and matcher bound twice" "is bound twice"
fresh; engine gamma "Stop	-"; bad "a short wire row" "not 3 fields"
fresh; engine gamma; bad "no wire row" "no wire row"
fresh; grep -v '^closer' "$R/hooks/alpha/manifest.tsv" > "$T/m"; mv "$T/m" "$R/hooks/alpha/manifest.tsv"; bad "no closer" "\`closer\` must appear once"
fresh; engine gamma "PreToolUse	@derived	10"; printf '#!/bin/sh\n' > "$CFG/bin/gamma.sh"; bad "@derived with no --matcher" "no --matcher gamma:PreToolUse"
fresh; rm "$CFG/bin/beta.sh"; bad "a binding whose script is not deployed" "beta.sh is not deployed"
fresh; rm -rf "$R/hooks"; run --check; t_eq "no manifest at all: exit 1" 1 "$RC"; t_has "...named" "$ERR" "no hooks/*/manifest.tsv"
run --settings; t_eq "a mode with no config dir is usage, exit 2" 2 "$RC"

t_section "@derived takes the matcher its installer supplies"
fresh; engine gamma "PreToolUse	@derived	10"; printf '#!/bin/sh\n' > "$CFG/bin/gamma.sh"
settings --matcher 'gamma:PreToolUse=Bash|Edit'; t_eq "exit 0" 0 "$RC"
t_has "wired with the supplied matcher" "$(cmds)" "PreToolUse|Bash|Edit|10|/bin/sh $CFG/bin/gamma.sh"

t_section "only harbor's own entries move; everything else is left exactly"
fresh
jq -n --arg a "$A" '{model: "x", hooks: {
  Stop: [{matcher: "", hooks: [{type: "command", command: "/bin/sh /opt/my-alpha.sh"}]},
         {matcher: "", hooks: [{type: "command", command: "/bin/sh /home/someone/.claude/bin/floor-hook.sh /home/someone/.claude/bin/alpha.sh.bak"}]}],
  PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: "/bin/sh /home/someone/guard.sh"}]}]}}' > "$CFG/settings.json"
settings; t_eq "exit 0" 0 "$RC"
t_eq "the operator's other keys survive" '"x"' "$(jq -c .model "$CFG/settings.json")"
t_has "a script whose name only CONTAINS the engine's is not the engine's" "$(cmds)" "Stop||-|/bin/sh /opt/my-alpha.sh"
t_has "a wrapper running another script is not the engine's" "$(cmds)" "floor-hook.sh"
t_has "a foreign PreToolUse hook stays" "$(cmds)" "PreToolUse|Bash|-|/bin/sh /home/someone/guard.sh"
t_eq "and the engine's own bindings are added beside them" 3 "$(cmds | grep -c "$CFG/bin/")"

t_section "a stale copy is pruned: a changed matcher, a duplicate, an old name"
fresh
jq -n --arg b "$B" --arg a "$A" '{hooks: {
  PreToolUse: [{matcher: "Bash|Read", hooks: [{type: "command", command: $b, timeout: 30}]}],
  SessionStart: [{matcher: "", hooks: [{type: "command", command: $b, timeout: 5}]}, {matcher: "", hooks: [{type: "command", command: $b, timeout: 5}]}],
  Stop: [{matcher: "", hooks: [{type: "command", command: "/bin/sh \"/elsewhere/bin/old-alpha.sh\""}]}]}}' > "$CFG/settings.json"
run --plan "$CFG"; t_has "the plan prunes the old matcher" "$OUT" "prune	beta	PreToolUse	Bash|Read"
t_has "...and the entry under the old name" "$OUT" "prune	alpha	Stop	-	-"
settings; t_eq "exit 0" 0 "$RC"
t_eq "exactly the wanted bindings remain" "PreToolUse|Bash|30|$B
SessionStart||5|$B
Stop||-|$A" "$(cmds)"
t_hasnt "the old name is gone" "$(jq -c . "$CFG/settings.json")" "old-alpha"

t_section "an engine that already matches keeps its place in the event"
fresh
jq -n --arg a "$A" '{hooks: {Stop: [{matcher: "", hooks: [{type: "command", command: $a}]}, {matcher: "", hooks: [{type: "command", command: "/bin/sh /home/someone/last.sh"}]}]}}' > "$CFG/settings.json"
settings
t_eq "alpha is still first in Stop" "$A" "$(jq -r '.hooks.Stop[0].hooks[0].command' "$CFG/settings.json")"

t_section "<engine>.off unwires it, and deleting the sentinel wires it again"
fresh; settings; run --record "$CFG"; t_eq "--record exits 0" 0 "$RC"
: > "$CFG/alpha.off"
run --plan "$CFG"; t_has "the plan says off" "$OUT" "off	alpha	Stop"
settings; t_hasnt "alpha is unwired" "$(cmds)" "alpha.sh"; t_has "beta is untouched" "$(cmds)" "beta.sh"
run --record "$CFG"; rm "$CFG/alpha.off"
settings; t_has "with the sentinel gone alpha is wired again, not read as removed by hand" "$(cmds)" "Stop||-|$A"

t_section "a binding removed by hand stays removed; --rewire brings it back"
fresh; settings; run --record "$CFG"
t_has "the record holds what is wired" "$(cat "$CFG/cache/deploy-hooks/wired.tsv")" "beta	SessionStart	-"
jq '.hooks.SessionStart = []' "$CFG/settings.json" > "$T/s"; mv "$T/s" "$CFG/settings.json"
run --plan "$CFG"; t_has "the plan says removed" "$OUT" "removed	beta	SessionStart"
settings; t_hasnt "SessionStart is not re-added" "$(cmds)" "SessionStart|"
t_has "...while beta's other binding stays" "$(cmds)" "PreToolUse|Bash|30|$B"
settings --rewire beta; t_has "--rewire wires it again" "$(cmds)" "SessionStart||5|$B"

t_section "no record yet: a stamped config dir counts every binding as wired before"
fresh; printf 'runtime-install 2026-10-01\n' > "$CFG/.helm-install-stamp"
run --plan "$CFG"; t_has "absent on a stamped box: removed by hand" "$OUT" "removed	alpha	Stop"
rm "$CFG/.helm-install-stamp"; run --plan "$CFG"; t_has "absent on a fresh box: wired" "$OUT" "wire	alpha	Stop"
t_done
