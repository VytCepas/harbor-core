#!/usr/bin/env sh
# bin/drift-status.sh (harbor#1031 item 5): the consumer reads every adopter's `--status` through one parser, prints only what is
# off (rows, ages, the unchecked) and a total, and never reads a report that breaks contracts/reconcile.md as a green.
# The fixture tree carries its own controls.tsv and adopters on the real library; the adopters are derived, not listed.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TAB="$(printf '\t')"; X="$T_TMP/x"; mkdir -p "$X/standards/naming" "$X/bin" "$T_TMP/cfg"
CTL="$X/standards/naming/controls.tsv"
row() { printf '%s\twarn\t%s\tdocs/reference/checks.md\t-\tschedule\tdetective\texperimental\t-\tcheck\t-\t%s\tfixture\n' "$1" "$2" "$3"; }
{ printf 'id\tmode\ttype\tengine\tsurfaces\tmoment\tfunction\tstability\tsuccessor\towner\tred_proof\temitted\ttitle\n'
  row check.alpha check fx.alpha; row check.beta check fx.beta; row check.gamma check fx.gamma; row lint.nope lint -; row check.plain check fx.plain; } > "$CTL"
adopter() { # <name> <body> : a script on the library that answers --status
  cat > "$X/bin/$1.sh" <<SCRIPT
#!/usr/bin/env sh
case "\$*" in --status) ;; *) exit 2 ;; esac
LOG_FD=2; . "$T_ROOT/bin/library-log.sh"; log_init $1
status_init $2 "\$CLAUDE_CONFIG_DIR" || exit 3
$3
status_end; exit \$?
SCRIPT
}
# alpha is off by one row unless told otherwise; beta is green; gamma cannot look; plain is no adopter
adopter fx-alpha fx.alpha 'status_ok 3; [ -f "$FX_ALPHA_OK" ] || status_drift "row one" "want" "have" "fix it"'
adopter fx-beta fx.beta 'status_ok 5'
printf '#!/usr/bin/env sh\ncase "$*" in --status) ;; *) exit 2 ;; esac\nLOG_FD=2; . "%s/bin/library-log.sh"\nstatus_init fx.gamma "$CLAUDE_CONFIG_DIR" || exit 3\nstatus_unjudged "no store"; exit 3\n' "$T_ROOT" > "$X/bin/fx-gamma.sh"
printf '#!/usr/bin/env sh\nexit 0\n' > "$X/bin/fx-plain.sh"
S() { CLAUDE_CONFIG_DIR="$T_TMP/cfg" FX_ALPHA_OK="$T_TMP/alpha-ok" sh "$T_ROOT/bin/drift-status.sh" --root "$X" "$@" 2>/dev/null; }
rc() { S "$@" > /dev/null; echo $?; }

t_section "the adopters are derived from controls.tsv and the scripts"
t_eq "a check row whose script answers --status is an adopter; a lint row and a script that does not answer are not" "fx.alpha	fx-alpha
fx.beta	fx-beta
fx.gamma	fx-gamma" "$(S --list)"

t_section "one parser reads them all, and prints what is off"
_o="$(S --only fx.alpha --only fx.beta)"
t_eq "a drifted row comes out with its check, state, key, desired, observed, delta and age" "fx.alpha${TAB}new${TAB}row one${TAB}want${TAB}have${TAB}fix it${TAB}0" "$(printf '%s\n' "$_o" | sed -n 1p)"
t_eq "the green adopter prints nothing but is counted: 2 adopters, 1 drifted row, 0 unchecked" "total${TAB}2${TAB}1${TAB}0" "$(printf '%s\n' "$_o" | tail -1)"
t_eq "a drifted row exits 1" 1 "$(rc --only fx.alpha --only fx.beta)"
sleep 1
_o="$(S --only fx.alpha --only fx.beta)"
t_eq "a second run with nothing changed: the same row is standing, not new" "standing" "$(printf '%s\n' "$_o" | head -1 | cut -f2)"
: > "$T_TMP/alpha-ok"
_o="$(S --only fx.alpha --only fx.beta)"
t_eq "once converged only the total is left" "total${TAB}2${TAB}0${TAB}0" "$_o"
t_eq "...and the exit is 0" 0 "$(rc --only fx.alpha --only fx.beta)"

t_section "an adopter that cannot judge is never a green"
_o="$(S)"
t_has "gamma's reason comes out as an unchecked row" "$_o" "fx.gamma${TAB}unchecked${TAB}no store"
t_eq "nothing is off but one could not judge: exit 3" 3 "$(rc)"
rm -f "$T_TMP/alpha-ok"
t_eq "a drifted row outranks an unchecked adopter: exit 1" 1 "$(rc)"

t_section "a report that breaks the contract is read as could-not-judge"
adopter fx-beta fx.beta 'status_ok 5; printf "everything is fine\n"'
t_has "prose among the records" "$(S --only fx.beta)" "fx.beta${TAB}unchecked${TAB}the report breaks contracts/reconcile.md: an unknown record everything is fine"
printf '#!/usr/bin/env sh\ncase "$*" in --status) ;; *) exit 2 ;; esac\nprintf "reconcile\\t1\\tfx.beta\\nnew\\tk\\tw\\th\\tf\\t0\\nsummary\\t1\\t1\\t0\\n"\nexit 0\n' > "$X/bin/fx-beta.sh"
t_has "an exit code that disagrees with the report" "$(S --only fx.beta)" "exit 0 beside 1 drifted"
printf '#!/usr/bin/env sh\ncase "$*" in --status) ;; *) exit 2 ;; esac\necho nonsense\nexit 0\n' > "$X/bin/fx-beta.sh"
t_has "a first line that is not the header" "$(S --only fx.beta)" "the first line is not reconcile"
t_eq "...and none of them is a green: exit 3" 3 "$(rc --only fx.beta)"

t_section "usage is 2, a tree with no adopter is 3"
t_eq "an unknown flag" 2 "$(rc --bogus)"
t_eq "--only a check that is not an adopter" 2 "$(rc --only fx.plain)"
t_eq "--root without a value" 2 "$(rc --root)"
rm -f "$X/bin"/fx-*.sh
t_eq "no script answers --status: exit 3, nothing was read" 3 "$(rc)"

t_section "the real tree: the adopters it derives are the ones the contract names"
_real="$(sh "$T_ROOT/bin/drift-status.sh" --list 2>/dev/null | cut -f1 | sort | tr '\n' ' ' | sed 's/ $//')"
t_eq "memory-route, the reference check, the port-root check and the confinement check" "drift.confinement drift.port-root drift.reference-check memory.route" "$_real"
t_done
