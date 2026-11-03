#!/usr/bin/env sh
# standard.version-registered (harbor#1426): an action a workflow pins that has no row in the versions register is red, and a
# registered one is green. Each arm is a repo built from the vendored package, which carries the register beside the lint.
. "$(dirname "$0")/../../lib/core.sh"; t_init
SV="$T_ROOT/bin/standard-vendor.sh"
H="$T_TMP/harbor"; R="$T_TMP/repo"
mkdir -p "$H/bin" "$H/standards/naming"
cp "$T_ROOT/bin/lint-name.sh" "$T_ROOT/bin/lint-renderer.sh" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/standard-vendor.sh" "$T_ROOT/bin/standard-register.sh" "$T_ROOT/bin/doc-shape.sh" "$T_ROOT/bin/doc-fresh-verify.sh" "$H/bin/"
cp "$T_ROOT"/standards/naming/*.tsv "$H/standards/naming/"
mkdir -p "$R"; sh "$SV" --source "$H" "$R" >/dev/null 2>&1
WF=".github/workflows"; SHA=0123456789abcdef0123456789abcdef01234567
tree() { (cd "$R" && sh vendor/naming/lint-name.sh --root . --registry vendor/naming/registry 2>&1); }
wf() { mkdir -p "$R/$WF"; { printf 'name: x\non: push\njobs:\n  j:\n    runs-on: ubuntu-latest\n    steps:\n'; for _u in "$@"; do printf '      - uses: %s\n' "$_u"; done; } > "$R/$WF/x.yml"; }
V=standard.version-registered

t_section "the package carries the versions register"
t_has "versions.tsv is vendored" "$(ls "$R/vendor/naming/registry")" "versions.tsv"

t_section "a registered action is green"
wf "actions/checkout@$SHA # v6.0.3" "astral-sh/setup-uv@$SHA # v8.1.0" "./local-action"
t_hasnt "no version finding" "$(tree)" "[$V]"

t_section "an action with no row is red, and names the action and the workflow"
wf "actions/checkout@$SHA # v6.0.3" "someone/unregistered-action@$SHA # v1"
OUT="$(tree)"
t_has "red" "$OUT" "[$V]"
t_has "...naming the action" "$OUT" "someone/unregistered-action is pinned in $WF/x.yml"
t_hasnt "...and not the registered one" "$OUT" "actions/checkout is pinned"

t_section "a mutable tag on a registered action is still registered (the SHA lint judges the tag, not this rule)"
wf "actions/checkout@v5"
t_hasnt "no version finding" "$(tree)" "[$V]"

t_section "a repo with no workflows is silent"
rm -rf "$R/.github"
t_hasnt "no version finding" "$(tree)" "[$V]"
t_done
