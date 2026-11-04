#!/usr/bin/env sh
# vendored.test.sh (harbor#967, #1415): the vendored lint, run from a workload root with no flags, finds its own
# registry and judges the workload's names only. Registry-owner rules (control-, exemption-, alias-expired,
# registry-, surface-) judge harbor's tree and never fire in a root that holds no standards/naming/ of its own.
. "$(dirname "$0")/../../lib/core.sh"; t_init
HARBOR_SCOPE_PRIVATE="$T_TMP/no-private"; CLAUDE_CONFIG_DIR="$T_TMP/no-config"; export HARBOR_SCOPE_PRIVATE CLAUDE_CONFIG_DIR; unset PORT_ROOT
TAB="$(printf '\t')"
OWNER='name\.(registry-|exemption-|alias-expired|control-|surface-)'

W="$T_TMP/workload"; mkdir -p "$W/bin" "$W/docs" "$W/other"
: > "$W/docs/qzxv-notes.md"; : > "$W/bin/corpus-build.sh"
sh "$T_ROOT/bin/standard-vendor.sh" "$W" > /dev/null 2>&1
t_eq "the fixture workload holds a vendored package and no standards/naming/" "yes" "$([ -f "$W/vendor/naming/lint-name.sh" ] && [ ! -d "$W/standards/naming" ] && echo yes)"

t_section "no flags, from the workload root: the vendored registry is found"
out="$(cd "$W" && sh vendor/naming/lint-name.sh --format findings 2>&1)"; rc=$?
t_eq "exit 0 or 1, never 3 (unchecked)" 0 "$([ "$rc" -le 1 ] && echo 0 || echo "$rc")"
t_hasnt "it does not say the registry is unreadable" "$out" "nothing was judged"
t_has "it judges a workload name: an unregistered word" "$out" "name.word-unregistered${TAB}docs/qzxv-notes.md"

t_section "no flags, from another directory: the root is the vendoring repo, not the cwd"
out2="$(cd "$W/other" && sh ../vendor/naming/lint-name.sh --format findings 2>&1)"
t_has "same finding" "$out2" "name.word-unregistered${TAB}docs/qzxv-notes.md"

t_section "only what applies to a workload: harbor's registry-owner rules stay silent"
# each variant must also have judged (the workload word finding), so a run that judged nothing is not "silent"
silent() { # <label> <findings>
  t_has "$1: it judged" "$2" "name.word-unregistered${TAB}docs/qzxv-notes.md"
  t_eq "$1: no registry-owner finding" "0" "$(printf '%s\n' "$2" | grep -cE "$OWNER")"
  t_hasnt "$1: no harbor-only engine named as missing" "$2" "is not in the tree"
}
silent "no flags" "$out"
silent "--root . and no --registry" "$(cd "$W" && sh vendor/naming/lint-name.sh --root . --format findings 2>&1)"
silent "the old explicit flags" "$(cd "$W" && sh vendor/naming/lint-name.sh --root . --registry vendor/naming/registry --format findings 2>&1)"

t_section "harbor's own tree still judges its registry (the filter is the workload's, not a switch-off)"
H="$T_TMP/harbor"; mkdir -p "$H/standards/naming" "$H/bin"
cp "$T_ROOT"/standards/naming/*.tsv "$H/standards/naming/"
_h="$(sh "$T_ROOT/bin/lint-name.sh" --root "$H" --registry "$H/standards/naming" --format findings 2>&1)"
t_has "a root that holds standards/naming/ is still judged on its controls" "$_h" "name.control-shape${TAB}control:"
t_done
