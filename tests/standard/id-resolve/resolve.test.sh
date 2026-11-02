#!/usr/bin/env sh
# bin/standard-id-resolve.sh (harbor#957 item 10): an old id of each kind (lint letter, check rename, printed admission id) and a
# current id resolve through the one reader to the controls.tsv row that owns them, and the incident register's `lint:` mechanisms
# are held to it. The fixture plants its own registers, so a letter dropped from the map goes red here and not only on the real tree.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TAB="$(printf '\t')"; X="$T_TMP/x"; mkdir -p "$X/standards/naming" "$X/bin" "$X/registries"
{ printf 'id\tmode\ttype\tengine\tsurfaces\tmoment\tfunction\tstability\tsuccessor\towner\tred_proof\temitted\ttitle\n'
  printf 'deploy.live-flag\tblock\tlint\tbin/lint-conventions.sh\t-\tci\tdetective\tstable\t-\tdeploy\t-\t-\tt\n'
  printf 'check.alerting\twarn\tcheck\tdocs/reference/checks.md\t-\tschedule\tdetective\tstable\t-\talert\t-\talert.probe\tt\n'
  printf 'admission.cd-config\tblock\tadmission\tbin/admission-bash.sh\t-\twrite\tpreventive\tstable\t-\tadmission\t-\tbash:cd-cfg\tt\n'; } > "$X/standards/naming/controls.tsv"
{ printf 'id\told\tnew\tsurface\twave\tremove_by\treason\n'
  printf 'rename-1\tcheck:pulse\tcheck:alert.probe\tcheck-id\tW5c\t2026-11-15\tr\n'
  printf 'rename-2\tbin/a.sh\tbin/b.sh\tbin\tW1\t-\tr\n'; } > "$X/standards/naming/renames.tsv"
printf '#!/bin/sh\nprintf "id\\tdeprecated\\n"; printf "deploy.live-flag\\tD2\\n"; printf "doc.nothing\\t-\\n"\n' > "$X/bin/lint-conventions.sh"
{ printf 'incident\tsource\tproperty\tstatus\tmechanism\tconfidence\tevidence\tsame-as\tunwatched\n'
  printf 'h#1\tbug\tp\tWATCHED\tlint:D2,suite:x\tread\te\t-\t-\n'
  printf 'h#2\tbug\tp\tWATCHED\tcheck:pulse,ci:y\tread\te\t-\t-\n'; } > "$X/registries/coverage-incidents.tsv"
R() { sh "$T_ROOT/bin/standard-id-resolve.sh" --root "$X" "$@" 2>/dev/null; }

t_section "one reader, every kind of old id"
t_eq "a deprecated lint letter resolves to the rule it became"  "D2${TAB}lint${TAB}deploy.live-flag${TAB}deploy.live-flag" "$(R D2)"
t_eq "a lint: prefix is ignored"                                 "lint:D2${TAB}lint${TAB}deploy.live-flag${TAB}deploy.live-flag" "$(R lint:D2)"
t_eq "an old check id resolves through its rename to the control" "pulse${TAB}rename${TAB}alert.probe${TAB}check.alerting" "$(R pulse)"
t_eq "a printed check id resolves to its control"                "alert.probe${TAB}emitted${TAB}alert.probe${TAB}check.alerting" "$(R alert.probe)"
t_eq "a printed admission id resolves to its control"            "bash:cd-cfg${TAB}emitted${TAB}bash:cd-cfg${TAB}admission.cd-config" "$(R bash:cd-cfg)"
t_eq "a current id resolves to itself"                           "check.alerting${TAB}control${TAB}check.alerting${TAB}check.alerting" "$(R check.alerting)"
t_eq "a path rename row is not an id"                            "bin/a.sh${TAB}unknown${TAB}-${TAB}-" "$(R bin/a.sh)"
t_eq "an unknown id is named unknown"                            "zz9${TAB}unknown${TAB}-${TAB}-" "$(R zz9)"
sh "$T_ROOT/bin/standard-id-resolve.sh" --root "$X" D2 zz9 >/dev/null 2>&1; t_eq "…and exits 1" 1 "$?"
sh "$T_ROOT/bin/standard-id-resolve.sh" --root "$X" D2 >/dev/null 2>&1; t_eq "all resolved exits 0" 0 "$?"
sh "$T_ROOT/bin/standard-id-resolve.sh" --root "$X" >/dev/null 2>&1; t_eq "no id is usage, exit 2" 2 "$?"
sh "$T_ROOT/bin/standard-id-resolve.sh" --root "$X" --bogus >/dev/null 2>&1; t_eq "an unknown flag is usage, exit 2" 2 "$?"

t_section "the incident register's lint mechanisms resolve"
_o="$(sh "$T_ROOT/bin/standard-id-resolve.sh" --root "$X" --incidents "$X/registries/coverage-incidents.tsv" 2>&1)"; _rc=$?
t_eq "every lint: mechanism resolves: exit 0" 0 "$_rc"
t_has "…and says how many" "$_o" "1 lint mechanisms"
printf 'h#3\tbug\tp\tWATCHED\tlint:Q9\tread\te\t-\t-\n' >> "$X/registries/coverage-incidents.tsv"
_o="$(sh "$T_ROOT/bin/standard-id-resolve.sh" --root "$X" --incidents "$X/registries/coverage-incidents.tsv" 2>&1)"; _rc=$?
t_eq "a letter no map holds is red: exit 1" 1 "$_rc"
t_has "…and names the incident and the letter" "$_o" "h#3 names the lint mechanism Q9"

t_section "a register it cannot read is unchecked, never green"
rm "$X/bin/lint-conventions.sh"
sh "$T_ROOT/bin/standard-id-resolve.sh" --root "$X" D2 >/dev/null 2>&1; t_eq "no lint map: exit 3" 3 "$?"

t_section "the real tree: every incident's lint mechanism resolves"
sh "$T_ROOT/bin/standard-id-resolve.sh" --incidents >/dev/null 2>&1; t_eq "an incident register is a required argument: exit 2" 2 "$?"
if [ -f "$T_ROOT/registries/coverage-incidents.tsv" ]; then   # a dev-layer file: the export has none and skips this arm
  sh "$T_ROOT/bin/standard-id-resolve.sh" --incidents "$T_ROOT/registries/coverage-incidents.tsv" >/dev/null 2>&1; t_eq "coverage-incidents.tsv resolves" 0 "$?"
fi
t_done
