#!/usr/bin/env sh
# bin/check-run.sh (harbor#1437): the scheduled entry of the read-only checks. It runs the row of contracts/scheduled-checks.tsv
# from a tree (a fresh clone of main under launchd; --from DIR here), clears the environment, and leaves the receipt the
# findings reconcile reads. And the table, the plists and the register agree on what is scheduled.
. "$(dirname "$0")/../../lib/core.sh"; t_init
INST="$T_TMP/inst"; TREE="$T_TMP/tree"; mkdir -p "$INST/bin" "$INST/cache" "$TREE/bin" "$TREE/contracts"
cp "$T_ROOT/bin/check-run.sh" "$T_ROOT/bin/library-log.sh" "$INST/bin/"
CR="$INST/bin/check-run.sh"; RC="$INST/cache/checks"
printf '#!/bin/sh\necho "clean"\nexit 0\n' > "$TREE/bin/t-ok.sh"
printf '#!/bin/sh\necho "1 finding"\necho "rule x fired on y"\nexit 1\n' > "$TREE/bin/t-red.sh"
printf '#!/bin/sh\necho "nothing judged"\nexit 3\n' > "$TREE/bin/t-none.sh"
printf '#!/bin/sh\nprintf "env=[%%s] cfg=[%%s] args=[%%s]\\n" "${HARBOR_TEST_LEAK-}" "${CLAUDE_CONFIG_DIR-}" "$*"\nexit 0\n' > "$TREE/bin/t-env.sh"
cat > "$TREE/bin/t-own.sh" <<OWN
#!/bin/sh
mkdir -p "\$CLAUDE_CONFIG_DIR/cache/checks"; printf '{"id":"t.own","status":"green"}\n' > "\$CLAUDE_CONFIG_DIR/cache/checks/t.own.json"
OWN
printf 't.ok\twrap\tbin/t-ok.sh\nt.red\twrap\tbin/t-red.sh\nt.none\twrap\tbin/t-none.sh\nt.env\twrap\tbin/t-env.sh a {cfg}\nt.own\ttool\tbin/t-own.sh\nt.bad\tmaybe\tbin/t-ok.sh\nt.gone\twrap\tbin/missing.sh\n' > "$TREE/contracts/scheduled-checks.tsv"
run() { HARBOR_TEST_LEAK=leaked sh "$CR" "$@" > "$T_TMP/out" 2>&1; echo "exit $?"; }

t_section "a wrapped check leaves the receipt its exit code earns"
t_eq "a clean check exits 0" "exit 0" "$(run t.ok --from "$TREE")"
t_eq "...and its receipt is green" green "$(jq -r .status "$RC/t.ok.json")"
t_eq "a check with findings exits 1" "exit 1" "$(run t.red --from "$TREE")"
t_eq "...and its receipt is red" red "$(jq -r .status "$RC/t.red.json")"
t_has "...naming the command's last line" "$(jq -r '.subjects[]' "$RC/t.red.json")" "rule x fired on y"
t_eq "a check that judged nothing (exit 3) is stood down, not green" "exit 3" "$(run t.none --from "$TREE")"
t_eq "...receipt stood-down" stood-down "$(jq -r .status "$RC/t.none.json")"
t_eq "a tool-mode check writes its own receipt and the runner adds none" green "$(run t.own --from "$TREE" >/dev/null; jq -r .status "$RC/t.own.json")"
t_eq "...(and nothing under another name)" "t.own.json" "$(ls "$RC" | grep 't.own')"
t_has "every run leaves a checks.log line with the id" "$(cat "$INST/cache/checks.log")" "[check:t.red]"

t_section "the environment is not an input, and {cfg} is this copy's config dir"
run t.env --from "$TREE" >/dev/null
t_has "a HARBOR_* variable of the caller is cleared" "$(cat "$T_TMP/out")" "env=[]"
t_has "{cfg} is the config dir beside this copy" "$(cat "$T_TMP/out")" "args=[a $(cd "$INST" && pwd -P)]"
t_has "CLAUDE_CONFIG_DIR is that dir for the check" "$(cat "$T_TMP/out")" "cfg=[$(cd "$INST" && pwd -P)]"

t_section "an id the table does not have, a bad row, a missing command: exit 1, said, and no receipt"
t_eq "an unknown id" "exit 1" "$(run t.nope --from "$TREE")"
t_has "...says it is not a row" "$(cat "$T_TMP/out")" "t.nope is not a row of contracts/scheduled-checks.tsv"
t_eq "a receipt column that is neither tool nor wrap" "exit 1" "$(run t.bad --from "$TREE")"
t_eq "a command that is not in the tree" "exit 1" "$(run t.gone --from "$TREE")"
t_eq "no id is a usage error" "exit 2" "$(run)"
t_eq "an id that is not lower case is a usage error" "exit 2" "$(run Bad --from "$TREE")"
t_eq "--from a directory that is not one" "exit 1" "$(run t.ok --from "$T_TMP/none")"
t_has "--list names the table's ids" "$(sh "$CR" --list --from "$TREE")" "t.red"

t_section "no clone and no repo-slug.txt: it refuses, it does not run the checkout"
t_eq "without --from and without repo-slug.txt beside it" "exit 1" "$(run t.ok)"
t_has "...it says what is missing" "$(cat "$T_TMP/out")" "names no repository"

t_section "the table, the plists and the register agree on what is scheduled"
TBL="$T_ROOT/contracts/scheduled-checks.tsv"
for id in $(awk -F'\t' '!/^#/ && NF >= 3 { print $1 }' "$TBL"); do
  pl="$T_ROOT/launchd/com.harbor.$id.plist"
  t_eq "$id: its command exists in the repo" yes "$([ -f "$T_ROOT/$(awk -F'\t' -v i="$id" '$1 == i { split($3, w, " "); print w[1] }' "$TBL")" ] && echo yes)"
  t_has "$id: it has a plist that the deploy installs" "$(cat "$pl" 2>/dev/null)" "harbor:deploy-installs"
  t_has "$id: ...and the plist runs check-run.sh with exactly this id" "$(cat "$pl" 2>/dev/null)" "<string>$id</string>"
  t_has "$id: it has a register row" "$(cat "$T_ROOT/docs/reference/checks.md")" "| \`$id\` |"
  t_eq "$id: its receipt column is tool or wrap" 1 "$(awk -F'\t' -v i="$id" '$1 == i && ($2 == "tool" || $2 == "wrap")' "$TBL" | grep -c .)"
done
t_done
