#!/usr/bin/env sh
# bin/ci-release-names.sh against a stubbed gh (harbor#957, harbor#986): a release tag is v<semver>, its title is
# the tag, and a released repo's CHANGELOG.md has a Keep a Changelog heading per release. A repo gh cannot read is
# not judged, and every repo unread is exit 3, never a green. The stub fails on any call it was not told about.
. "$(dirname "$0")/../../lib/core.sh"; t_init
FX="$T_TMP/fx"; GH="$T_TMP/gh"; C="$T_TMP/controls.tsv"
mkdir -p "$FX"
cat > "$GH" <<'STUB'
#!/bin/sh
case "$*" in
  "release list -R "*" --limit 1000 --json tagName,name,isDraft")
    r="$(printf '%s' "$4" | tr / _)"
    [ -f "$FX/$r.rel" ] || { echo "gh: Could not resolve to a Repository (HTTP 404)" >&2; exit 1; }
    cat "$FX/$r.rel" ;;
  "api -H Accept: application/vnd.github.raw repos/"*"/contents/CHANGELOG.md")
    r="$(printf '%s' "$4" | sed 's#^repos/##; s#/contents/CHANGELOG.md$##' | tr / _)"
    [ -f "$FX/$r.cl" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
    cat "$FX/$r.cl" ;;
  *) echo "UNEXPECTED gh call: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$GH"
mode() { awk -F'\t' -v OFS='\t' -v m="$1" '$1 == "ci.release-names" { $2 = m } { print }' "$T_ROOT/standards/naming/controls.tsv" > "$C"; }
run() { FX="$FX" sh "$T_ROOT/bin/ci-release-names.sh" --gh "$GH" --controls "$C" "$@" 2>&1; }
code() { FX="$FX" sh "$T_ROOT/bin/ci-release-names.sh" --gh "$GH" --controls "$C" "$@" >/dev/null 2>&1; echo "exit $?"; }
rel() { printf '[%s]\n' "$2" > "$FX/$(printf '%s' "$1" | tr / _).rel"; }
cl()  { printf '# Changelog\n\n## [Unreleased]\n%s\n' "$2" > "$FX/$(printf '%s' "$1" | tr / _).cl"; }
mode warn

t_section "a repo that follows the rule is green"
rel o/good '{"tagName":"v1.2.0","name":"v1.2.0","isDraft":false},{"tagName":"v1.1.0","name":"","isDraft":false},{"tagName":"wip","name":"wip","isDraft":true}'
cl o/good "$(printf '## [1.2.0] - 2026-10-01\n## [1.1.0] - 2026-09-01')"
_o="$(run --repo o/good)"
t_has "the run is stamped with its control id" "$_o" "[check:ci.release-names]"
t_has "two published releases judged, the draft skipped" "$_o" "2 release(s) across 1 of 1 repos"
t_hasnt "no finding" "$_o" "WARN"
t_eq "green exits 0" "exit 0" "$(code --repo o/good)"
rel o/none '' ; t_has "a repo with no release needs no changelog" "$(run --repo o/none)" "0 release(s) across 1 of 1 repos"

t_section "each half of the rule goes red on its own"
rel o/tag '{"tagName":"transition-check-v1","name":"transition-check-v1","isDraft":false}'; cl o/tag ''
t_has "a tag that is not v<semver>" "$(run --repo o/tag)" "release tag transition-check-v1 is not v<major>.<minor>.<patch>"
rel o/title '{"tagName":"v0.1.0","name":"TagScope 0.1.0","isDraft":false}'; cl o/title '## [0.1.0]'
_o="$(run --repo o/title)"
t_has "a title that is not the tag" "$_o" 'release v0.1.0 is titled "TagScope 0.1.0"'
t_hasnt "…and only that: its tag and changelog are fine" "$_o" "not v<major>"
rel o/nocl '{"tagName":"v1.0.0","name":"v1.0.0","isDraft":false}'
t_has "a released repo with no CHANGELOG.md" "$(run --repo o/nocl)" "1 release(s) and no CHANGELOG.md"
rel o/head '{"tagName":"v2.0.0","name":"v2.0.0","isDraft":false},{"tagName":"v1.0.0","name":"v1.0.0","isDraft":false}'; cl o/head '## [1.0.0]'
_o="$(run --repo o/head)"
t_has "a changelog missing one release's heading" "$_o" 'no "## [2.0.0]" heading for release v2.0.0'
t_hasnt "…and not the heading it has" "$_o" '"## [1.0.0]" heading'
t_eq "under warn a finding prints and exits 0" "exit 0" "$(code --repo o/title)"
mode block
t_eq "under block a finding exits 1" "exit 1" "$(code --repo o/title)"
t_eq "…and green still exits 0" "exit 0" "$(code --repo o/good)"
mode shadow
t_eq "under shadow a finding prints nothing" "" "$(run --repo o/title)"
_rl="$T_TMP/redlog"; : > "$_rl"; LINT_REDLOG="$_rl" FX="$FX" sh "$T_ROOT/bin/ci-release-names.sh" --gh "$GH" --controls "$C" --repo o/title >/dev/null 2>&1
t_eq "…and still records the red in LINT_REDLOG" "ci.release-names" "$(cat "$_rl")"
mode warn

t_section "a repo it cannot read is never green (D-29)"
_o="$(run --repo o/good --repo o/gone)"
t_has "an unreadable repo is named as not judged" "$_o" "not judged: o/gone (o/gone): gh release list failed"
t_has "…beside the one it judged" "$_o" "across 1 of 2 repos"
t_eq "every repo unread is exit 3" "exit 3" "$(code --repo o/gone)"
_reg="$T_TMP/reg.tsv"; printf 'ghost\t%s/no-such-dir\n' "$T_TMP" > "$_reg"
t_eq "a registry whose only repo has no checkout is exit 3" "exit 3" "$(code --registry "$_reg")"
t_has "…and says why" "$(run --registry "$_reg")" "no checkout at its registry path"
mkdir -p "$T_TMP/r1"; git -C "$T_TMP/r1" init -q && git -C "$T_TMP/r1" remote add origin https://github.com/o/good.git
printf 'r1\t%s/r1\n' "$T_TMP" > "$_reg"
t_has "a registry row is read through its checkout's origin" "$(run --registry "$_reg")" "2 release(s) across 1 of 1 repos"
awk -F'\t' '$1 != "ci.release-names"' "$T_ROOT/standards/naming/controls.tsv" > "$C"
t_eq "no controls row: the mode is unknown, exit 3" "exit 3" "$(code --repo o/good)"
mode warn

t_section "usage is 2"
t_eq "an unknown argument" "exit 2" "$(code --nope)"
t_eq "--repo without OWNER/NAME" "exit 2" "$(code --repo harbor)"
t_eq "--repo with nothing after it" "exit 2" "$(code --repo)"
t_done
