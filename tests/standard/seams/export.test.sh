#!/usr/bin/env sh
# The harbor-core export is a seam row of kind export (harbor#1436): standard-seams-fresh.sh reads the pin from the mirror's last commit,
# counts the harbor commits that touch a core path since it, and reports the export's age on its report line; past allowed_lag it is a
# finding, and a mirror it cannot read is `unchecked`. Fixture repos only: a mini harbor and a mini mirror, a stub for the fleet comparison.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset CLAUDECODE HARBOR_DEPLOY_ACTIVE
T="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"
H="$T/harbor"; C="$T/mirror"; CFG="$T/cfg"; mkdir -p "$H/bin" "$H/contracts" "$H/docs" "$C" "$CFG"
cp "$T_ROOT/bin/standard-seams-fresh.sh" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/scope-roots.sh" "$H/bin/"; cp "$T_ROOT/contracts/roots.tsv" "$H/contracts/"
printf 'path\tlayer\tnote\nbin/\tcore\tthe tools\ndocs/how-to/\tdev\tnotes\n' > "$H/contracts/layers.tsv"
git -C "$H" init -q; git -C "$H" config user.email t@t; git -C "$H" config user.name t
commit() { git -C "$H" add -A >/dev/null 2>&1; git -C "$H" commit -q -m "$1"; }
printf '# seams\nid\tkind\tproducer\tconsumer\tcopy_path\tpin\tschema\tfreshness\towner\tallowed_lag\treason\nharbor-core-export\texport\tharbor\tharbor-core\t-\t-\t-\tcheck.seam-fresh\tdeploy\t2\tfixture\n' > "$H/contracts/seams.tsv"
echo a > "$H/bin/a.sh"; commit "c1"; PIN="$(git -C "$H" rev-parse HEAD)"
git -C "$C" init -q; git -C "$C" config user.email t@t; git -C "$C" config user.name t
echo x > "$C/x"; git -C "$C" add -A; GIT_COMMITTER_DATE="2026-10-20T10:00:00" git -C "$C" commit -q --date="2026-10-20T10:00:00" -m "export: core snapshot of ${PIN%"${PIN#????????????}"}

Source commit: $PIN (1 files)"
run() { HARBOR_SCOPE_ROOT="$H" sh "$H/bin/standard-seams-fresh.sh" --register "$H/contracts/seams.tsv" --root "harbor-core=$C" --checker true --config-dir "$CFG" --today 2026-11-02 "$@" 2>&1; }

t_section "an export at its pin is current and reports its age"
_o="$(run)"
t_has "the age line names the pin, the days and the lag" "$_o" "age      harbor-core-export: pinned at ${PIN%"${PIN#???????}"}, 13 day(s) old, 0 core commit(s) behind (allowed 2)"
t_hasnt "…and no finding" "$_o" "new      check.seam-fresh"

t_section "core commits since the pin count, dev-layer commits do not"
echo d > "$H/docs/how-to-note"; mkdir -p "$H/docs/how-to"; echo n > "$H/docs/how-to/n.md"; commit "dev only"
t_has "a commit touching only a dev path is not lag" "$(run)" "0 core commit(s) behind"
echo b >> "$H/bin/a.sh"; commit "core 1"; echo c >> "$H/bin/a.sh"; commit "core 2"
t_has "two core commits are two behind, within the allowance" "$(run)" "2 core commit(s) behind (allowed 2)"
t_hasnt "…and still no finding" "$(run)" "new      check.seam-fresh"
echo e >> "$H/bin/a.sh"; commit "core 3"
_o="$(run --config-dir "$T/cfg2")"
t_has "a third passes the allowance: a finding" "$_o" "new      check.seam-fresh harbor-core-export: stale"
t_has "…its detail carries the age and the lag" "$_o" "pinned at ${PIN%"${PIN#???????}"}, 13 day(s) old and 3 core commit(s) behind (allowed 2)"
t_eq "…and the exit is 1" "exit 1" "$(HARBOR_SCOPE_ROOT="$H" sh "$H/bin/standard-seams-fresh.sh" --register "$H/contracts/seams.tsv" --root "harbor-core=$C" --checker true --config-dir "$T/cfg3" --today 2026-11-02 >/dev/null 2>&1; echo "exit $?")"

t_section "a mirror that cannot be read is unchecked, never green"
_o="$(HARBOR_SCOPE_ROOT="$H" sh "$H/bin/standard-seams-fresh.sh" --register "$H/contracts/seams.tsv" --root "harbor-core=$T/nowhere" --checker true --config-dir "$T/cfg4" --today 2026-11-02 2>&1)"
t_has "no checkout is named, not passed" "$_o" "harbor-core-export: no checkout of harbor-core"
mkdir -p "$T/nopin"; git -C "$T/nopin" init -q; git -C "$T/nopin" config user.email t@t; git -C "$T/nopin" config user.name t; echo y > "$T/nopin/y"; git -C "$T/nopin" add -A; git -C "$T/nopin" commit -q -m "export: no source line"
_o="$(HARBOR_SCOPE_ROOT="$H" sh "$H/bin/standard-seams-fresh.sh" --register "$H/contracts/seams.tsv" --root "harbor-core=$T/nopin" --checker true --config-dir "$T/cfg5" --today 2026-11-02 2>&1)"
t_has "a mirror with no Source commit line is unchecked" "$_o" "the pin <none> of the last export is not a harbor commit"

t_done
