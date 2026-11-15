#!/usr/bin/env sh
# bin/standard-label-sync.sh against a stubbed gh (harbor#1427): the dry run plans and writes nothing, --apply issues exactly the
# plan's calls, status: labels are planned for removal and only removed with --remove-retired, --check reports a label outside
# the register with its fix as a delta with ages. The stub records every call, so "writes nothing" is read, not assumed.
. "$(dirname "$0")/../../lib/core.sh"; t_init
FX="$T_TMP/fx"; GH="$T_TMP/gh"; CFG="$T_TMP/cfg"; CALLS="$T_TMP/calls"
mkdir -p "$FX" "$CFG"
cat > "$GH" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$CALLS"
case "$1 $2" in
  "label list") r="$(printf '%s' "$4" | tr / _)"; cat "$FX/$r.labels" || exit 1 ;;
  "issue list") printf '7\n8\n' ;;
  "pr list") printf '9\n' ;;
  *) : ;;
esac
STUB
chmod +x "$GH"
printf 'bug\tmeasurably wrong\nP0-critical\told\nstatus:testing\tx\ntype:chore\tkept\nfoo\tunknown\ntheme:memory\told\nfamily:memory\talready here\nfeature\tx\n' > "$FX/o_r.labels"
printf 'type:bug\tfine\n' > "$FX/o_ok.labels"
run() { CALLS="$CALLS" FX="$FX" sh "$T_ROOT/bin/standard-label-sync.sh" --gh "$GH" --config-dir "$CFG" "$@" 2>&1; }
code() { CALLS="$CALLS" FX="$FX" sh "$T_ROOT/bin/standard-label-sync.sh" --gh "$GH" --config-dir "$CFG" "$@" >/dev/null 2>&1; echo "exit $?"; }

t_section "the dry run is the default: it prints the plan and changes nothing"
: > "$CALLS"
_o="$(run --repo o/r)"
t_has "a legacy label is a rename to its register label" "$_o" "rename       bug  ->  type:bug"
t_has "P0-critical is renamed to priority:p0" "$_o" "rename       P0-critical  ->  priority:p0"
t_has "a legacy label whose target exists is a merge" "$_o" "merge        theme:memory  ->  family:memory"
t_has "status: is planned for removal" "$_o" "remove       status:testing"
t_has "a label the register does not know is unregistered, never touched" "$_o" "unregistered foo"
t_has "a missing register label is created" "$_o" "create       type:tech-debt"
t_hasnt "a registered label is not in the plan" "$_o" "type:chore"
t_has "the dry run says so" "$_o" "dry run: nothing was changed"
t_eq "…and the only gh call was the read" "label list --repo o/r --limit 1000 --json name,description --jq .[] | [.name, (.description // \"\")] | @tsv" "$(cat "$CALLS")"
t_eq "a plan with lines exits 1" "exit 1" "$(code --repo o/r)"
mkdir -p "$T_TMP/gen"; sh "$T_ROOT/bin/lint-name.sh" --gen labels --root "$T_TMP/gen" --registry "$T_ROOT/standards/naming" >/dev/null 2>&1
grep -v -e '^#' -e '^name	' "$T_TMP/gen/build/naming/labels.tsv" > "$FX/o_eq.labels"
t_eq "a repo whose labels equal the register exits 0 and plans nothing" "exit 0" "$(code --repo o/eq)"

t_section "--apply issues the plan's calls, one argument vector each; removal needs its own flag"
: > "$CALLS"; run --repo o/r --apply >/dev/null
_c="$(cat "$CALLS")"
t_has "rename keeps the issues: label edit --name" "$_c" "label edit bug --repo o/r --name type:bug"
t_has "a merge relabels each issue" "$_c" "issue edit 7 --repo o/r --add-label family:memory --remove-label theme:memory"
t_has "…and each pull request" "$_c" "pr edit 9 --repo o/r --add-label family:memory --remove-label theme:memory"
t_has "…then deletes the merged label" "$_c" "label delete theme:memory --repo o/r --yes"
t_has "a missing label is created with the register's description" "$_c" "label create type:tech-debt --repo o/r --description"
t_hasnt "status: is NOT removed by a plain --apply" "$_c" "label delete status:testing"
t_hasnt "an unregistered label is never touched" "$_c" " foo"
: > "$CALLS"; run --repo o/r --apply --remove-retired >/dev/null
t_has "--remove-retired removes status:testing" "$(cat "$CALLS")" "label delete status:testing --repo o/r --yes"
t_eq "--remove-retired without --apply is usage" "exit 2" "$(code --repo o/r --remove-retired)"

t_section "--check is the delta and the ages, with the fix beside each label"
_o="$(run --repo o/r --check --today 2026-11-01)"
t_has "stamped with the check id" "$_o" "[check:standard.label-registered]"
t_has "a legacy label names its rename" "$_o" "label-outside-register o/r: bug: apply the rename to type:bug"
t_has "an unregistered label names the register row to add" "$_o" "label-outside-register o/r: foo: add its row to standards/naming/label-axes.tsv"
t_has "status: is red as retired" "$_o" "label-outside-register o/r: status:testing: retired"
t_eq "new findings exit 1" "exit 1" "$(rm -f "$CFG/cache/standard-label-registered.tsv"; code --repo o/r --check --today 2026-11-01)"
_o="$(run --repo o/r --check --today 2026-11-08)"
t_has "a second run has nothing new" "$_o" "nothing new"
t_has "…and the standing findings carry their age" "$_o" "oldest 7 day(s)"
t_has "the receipt is red" "$(cat "$CFG/cache/checks/standard.label-registered.json")" '"status":"red"'
printf 'type:bug\tfine\n' > "$FX/o_r.labels"
_o="$(run --repo o/r --check --today 2026-11-15)"
t_has "a repaired repo is reported fixed" "$_o" "  fixed "
t_has "the receipt turns green" "$(cat "$CFG/cache/checks/standard.label-registered.json")" '"status":"green"'

t_section "a repo that cannot be read is never fixed, and nothing read is exit 3"
rm -f "$FX/o_gone.labels"
t_eq "no repo readable is unchecked" "exit 3" "$(code --repo o/gone)"
t_eq "an unknown argument is exit 2" "exit 2" "$(code --nope)"
t_eq "a bare repo name is exit 2" "exit 2" "$(code --repo justname)"

t_section "the register is label-axes.tsv: a fixture label that is not in it is reported"
printf 'foo\tx\n' > "$FX/o_r.labels"
t_has "foo is reported against the shipped register" "$(run --repo o/r)" "unregistered foo"
t_red check.label-registered check.label-sync   # the falsifier this suite names for them (harbor#1422)
t_done
