#!/usr/bin/env sh
# issue-connector: the taxonomy is the only source, and every mode decides without a network (harbor#512, #609, #612, #724).
# `gh` is a stub first on PATH that answers from files the cases write; any other call exits 9.
. "$(dirname "$0")/../lib/core.sh"; t_init
SUT="$T_ROOT/bin/issue-connector.sh"; TAX_REAL="$T_ROOT/CONTRACTS/issue-taxonomy.tsv"
cat > "$T_BIN/gh" <<'STUB'
#!/usr/bin/env sh
case "$1 $2" in
  "issue view")
    case "$*" in
      *"--json labels"*) cat "${STUB_LABELS:-/dev/null}" 2>/dev/null || true; exit 0 ;;
      *"--json body"*)   cat "${STUB_BODY:-/dev/null}"   2>/dev/null || true; exit 0 ;;
    esac ;;
  "issue list")  [ "${STUB_LIST_FAIL:-no}" = yes ] && exit 1; cat "${STUB_LIST:-/dev/null}" 2>/dev/null || true; exit 0 ;;
  "issue edit")  printf '%s\n' "$*" >> "$TMP_EDITLOG"; exit 0 ;;
  "label list")  cat "${STUB_LABELS_LIVE:-/dev/null}" 2>/dev/null || true; exit 0 ;;
  "api graphql") cat "${STUB_GRAPH:-/dev/null}" 2>/dev/null || true; exit 0 ;;
esac
exit 9
STUB
chmod +x "$T_BIN/gh"
TMP_EDITLOG="$T_TMP/edits.log"; HARBOR_ISSUE_REPO=owner/repo; export TMP_EDITLOG HARBOR_ISSUE_REPO
STUB_LABELS="$T_TMP/l1"; STUB_BODY="$T_TMP/b1"; STUB_LIST="$T_TMP/fl"; export STUB_LABELS STUB_BODY STUB_LIST
STUB_LIST_FAIL=no; export STUB_LIST_FAIL   # yes: the stub fails `gh issue list`, as a network or auth error would
kinds()  { awk -F'\t' -v k="$2" '/^#/ || NF < 4 { next } $1 == k { n++ } END { print n+0 }' "$1"; }  # <tax> <kind>
# The export carries no dev-layer file (CONTRACTS/layers.tsv), so there a glob naming one is not dead: it names what the
# export left out. Only where NO tracked path is dev-layer: in the dev repo a glob matching nothing is dead, whatever layer it names.
layer()  { printf '%s\n' "$1" > "$T_TMP/layer.in"; sh "$T_ROOT/bin/layers.sh" --classify < "$T_TMP/layer.in" | awk -F'\t' '{ print $NF }'; }  # <path> -> core|dev
git -C "$T_ROOT" ls-files > "$T_TMP/tracked.txt"; sh "$T_ROOT/bin/layers.sh" --classify < "$T_TMP/tracked.txt" > "$T_TMP/tracked.layers"
[ -n "$(awk -F'\t' '$NF == "dev"' "$T_TMP/tracked.layers" | head -1)" ] && IS_EXPORT=no || IS_EXPORT=yes
dead()   { awk -F'\t' '/^#/ || NF < 4 { next } $1 == "theme" && $3 != "-" { print $2 "\t" $3 }' "$1" |
           while IFS='	' read -r l gs; do set -f; for g in $gs; do  # -f: git expands the glob, never the cwd
             [ -z "$(git -C "$T_ROOT" ls-files -- "$g" | head -1)" ] || continue
             [ "$IS_EXPORT" = yes ] && [ "$(layer "$g")" = dev ] && continue
             printf ' %s:%s' "$l" "$g"; done; done; }
labels() { printf "$1" > "$STUB_LABELS"; }
edits()  { : > "$TMP_EDITLOG"; sh "$SUT" --apply 7 "$@" >/dev/null 2>&1; echo "exit $?"; }

t_section "the taxonomy is the only source"
t_eq "--labels prints every type the file declares" "$(kinds "$TAX_REAL" type)" \
  "$(sh "$SUT" --labels | awk '/^types:/{f=1;next} /^themes:/{f=0} f && NF {n++} END{print n+0}')"
t_eq "--labels prints every theme the file declares" "$(kinds "$TAX_REAL" theme)" \
  "$(sh "$SUT" --labels | awk '/^themes:/{f=1;next} f && NF {n++} END{print n+0}')"
t_eq "the taxonomy declares at least one type and one theme" yes \
  "$([ "$(kinds "$TAX_REAL" type)" -gt 0 ] && [ "$(kinds "$TAX_REAL" theme)" -gt 0 ] && echo yes)"
t_eq "a missing taxonomy exits 2, not read as empty" 2 "$(HARBOR_TAXONOMY="$T_TMP/nope.tsv" sh "$SUT" --labels >/dev/null 2>&1; echo $?)"

t_section "every theme glob matches a tracked path (the arm that earns column 3)"
t_eq "no theme glob is dead" "" "$(dead "$TAX_REAL")"
t_has "control: a known-live glob resolves" "$(git -C "$T_ROOT" ls-files -- 'bin/guard-*.sh')" bin/guard-bash.sh
cp "$TAX_REAL" "$T_TMP/tax-mutant.tsv"
printf 'theme\ttheme:planted\tbin/there-is-no-such-file-*.sh\tplanted by the suite\n' >> "$T_TMP/tax-mutant.tsv"
t_eq "mutation: a planted dead glob IS reported" " theme:planted:bin/there-is-no-such-file-*.sh" "$(dead "$T_TMP/tax-mutant.tsv")"
printf 'theme\ttheme:planted-dev\tEVALS-DATA/there-is-no-such-dir/*\tplanted by the suite\n' > "$T_TMP/tax-dev.tsv"
t_eq "a dead glob naming a dev-layer path: reported in the dev repo, excused only in an export" \
  "$([ "$IS_EXPORT" = yes ] && echo '' || echo ' theme:planted-dev:EVALS-DATA/there-is-no-such-dir/*')" "$(dead "$T_TMP/tax-dev.tsv")"

t_section "--check: both axes, and the declared exemption"
labels 'bug\ntheme:floor\n';      t_exit "type + theme passes" 0 sh "$SUT" --check 1
labels 'theme:floor\n';           t_exit "a missing type is refused" 1 sh "$SUT" --check 1
labels 'bug\n';                   t_exit "a missing theme is refused" 1 sh "$SUT" --check 1
labels 'epic:provenance\n';       t_exit "a provenance epic is theme-exempt" 0 sh "$SUT" --check 1
labels 'epic:workstream\n';       t_exit "control: the exemption does NOT extend to a workstream epic" 1 sh "$SUT" --check 1
labels 'wontfix\nneeds-triage\n'; t_exit "labels outside the taxonomy count as neither axis" 1 sh "$SUT" --check 1

t_section "--apply never invents a label"
t_eq "an unknown label is refused" "exit 1" "$(edits not-a-real-label)"
t_eq "and nothing was written when it refused" "" "$(cat "$TMP_EDITLOG")"
t_eq "control: two taxonomy labels apply" "exit 0" "$(edits bug theme:floor)"
t_has "bug is added" "$(cat "$TMP_EDITLOG")" "--add-label bug"
t_has "theme:floor is added" "$(cat "$TMP_EDITLOG")" "--add-label theme:floor"
# harbor#609: the gate reads the whole contract, so a declared status/system label applies too.
t_eq "declared labels outside type/theme apply" "exit 0" "$(edits blocked:review system:verifier)"
t_has "blocked:review is added" "$(cat "$TMP_EDITLOG")" "--add-label blocked:review"
t_has "system:verifier is added" "$(cat "$TMP_EDITLOG")" "--add-label system:verifier"
t_eq "an undeclared label is still refused after the widening" "exit 1" "$(edits P9-imaginary)"
t_eq "and still nothing was written" "" "$(cat "$TMP_EDITLOG")"
t_eq "--apply with no labels is refused" "exit 2" "$(edits)"

t_section "--suggest derives from paths, and declines rather than guessing"
printf 'the defect is in bin/guard-bash.sh and nowhere else\n' > "$STUB_BODY"
t_eq "a body naming a floor path suggests theme:floor" theme:floor "$(sh "$SUT" --suggest 1 2>/dev/null)"
printf 'CONTRACTS/browser-routing.md is the only copy\n' > "$STUB_BODY"
t_eq "a body naming the router suggests theme:browser" theme:browser "$(sh "$SUT" --suggest 1 2>/dev/null)"
printf 'the Read tool returns 181 KB per call and nothing measures it\n' > "$STUB_BODY"
t_exit "a body naming no tracked path declines" 1 sh "$SUT" --suggest 1
t_has "and says so" "$(sh "$SUT" --suggest 1 2>&1)" "choose by hand"

t_section "shape"
t_has "--help prints the header (S4)" "$(sh "$SUT" --help)" "issue-connector (harbor#512)"
t_exit "an unknown mode is refused" 2 sh "$SUT" --not-a-mode
t_has "the script names its ticket in the first 4 lines (S3)" "$(head -4 "$SUT")" "harbor#512"

t_section "--falsifiers reports, and exempts an epic"
printf '1\tbug,theme:floor\tno refutation condition anywhere in this body\n' > "$STUB_LIST"
t_eq "an issue with no falsifier is named" 1 "$(sh "$SUT" --falsifiers 2>/dev/null | grep -c '^  #1$')"
printf '1\tbug,theme:floor\tFalsifier: the guard goes red on the planted case\n' > "$STUB_LIST"
t_has "control: an issue stating a falsifier is counted, not reported" "$(sh "$SUT" --falsifiers 2>/dev/null)" "0 of 1 non-epic"
printf '2\tepic:workstream,theme:ci\tno refutation condition here either\n' > "$STUB_LIST"
t_has "an epic is exempt" "$(sh "$SUT" --falsifiers 2>/dev/null)" "0 of 0 non-epic"

t_section "--audit enforces the declared cardinality (harbor#612)"
AUD_TAX="$T_TMP/aud-tax.tsv"
cat > "$AUD_TAX" <<'TAXEOF'
#AXIS	type	1	1	the filer
#AXIS	theme	1	99	the connector
#AXIS	status	0	1	triage
type	bug	-	measurably wrong behaviour
type	feature	-	new capability
type	epic:provenance	-	origin record of an audit pass
theme	theme:floor	bin/guard-*.sh	guard and floor correctness
theme	theme:ci	.github/workflows/*	CI and drift
status	blocked:review	-	waiting on a PR review
TAXEOF
aud() { # <issue-list> [--strict] — the audit's stdout; its exit lands in $T_TMP/aud.rc
  STUB_LIST="$1" STUB_LABELS_LIVE="$T_TMP/live.txt" STUB_GRAPH="$T_TMP/graph.json" \
    HARBOR_TAXONOMY="$AUD_TAX" sh "$SUT" --audit ${2:-} 2>/dev/null; echo "exit $?" > "$T_TMP/aud.rc"
}
issues() { printf "$2" > "$T_TMP/$1"; printf '%s' "$T_TMP/$1"; }  # <name> <lines> — prints the list file
graph()  { printf '{"data":{"repository":{"issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[%s]}}}}\n' "$1" > "$T_TMP/graph.json"; }
live()   { printf "$1" > "$T_TMP/live.txt"; }
live 'bug\nfeature\ntheme:floor\ntheme:ci\nepic:provenance\nblocked:review\n'; graph ''
t_has "two types on one issue are reported" "$(aud "$(issues l1 '7\tbug,feature,theme:floor\n')" | grep '#7')" "type=2(max 1)"
t_has "a missing type is reported" "$(aud "$(issues l2 '7\ttheme:floor\n')" | grep '#7')" "type=0(min 1)"
t_has "a missing theme is reported" "$(aud "$(issues l3 '7\tbug\n')" | grep '#7')" "theme=0(min 1)"
t_has "two status labels are reported" "$(aud "$(issues l4 '7\tbug,theme:floor,blocked:review,blocked:review\n')" | grep '#7')" "status=2(max 1)"
t_has "control: a conformant issue is not reported" "$(aud "$(issues l5 '7\tbug,theme:floor\n')" | sed -n '/cardinality/,/^$/p')" "none"
t_hasnt "a provenance epic is theme-exempt" "$(aud "$(issues l6 '7\tepic:provenance\n')")" "theme=0"

t_section "--audit reconciles the contract against the tracker, both directions (harbor#609)"
L7="$(issues l7 '7\tbug,theme:floor\n')"
live 'bug\nfeature\ntheme:floor\nepic:provenance\nblocked:review\n'
t_has "a declared label absent from the tracker is reported" "$(aud "$L7" | grep 'ABSENT on the tracker')" "theme:ci"
live 'bug\nfeature\ntheme:floor\ntheme:ci\nepic:provenance\nblocked:review\nrogue-label\n'
t_has "a tracker label absent from the contract is reported" "$(aud "$L7" | grep 'NOT declared here')" "rogue-label"
live 'bug\nfeature\ntheme:floor\ntheme:ci\nepic:provenance\nblocked:review\n'
t_has "control: a matching contract reports reconciled" "$(aud "$L7")" "reconciled"

t_section "--audit reads the ownership graph, not a label that restates it"
graph '{"number":7,"parent":{"number":999},"subIssues":{"totalCount":0}}'
t_has "an open issue under a closed parent is reported" "$(aud "$L7")" "CLOSED parent: #7->#999"
graph '{"number":7,"parent":null,"subIssues":{"totalCount":0}}'
t_has "an epic that parents nothing is reported" "$(aud "$(issues l8 '7\tepic:provenance\n')")" "parents nothing: #7"
graph '{"number":7,"parent":null,"subIssues":{"totalCount":2}}'
t_has "a parent with no epic label is reported" "$(aud "$L7" | grep 'carrying no epic')" ": #7"
graph '{"number":7,"parent":null,"subIssues":{"totalCount":0}}'
t_has "control: a consistent graph says so" "$(aud "$L7")" "edges consistent"

t_section "--strict is opt-in, and the audit reaches its own gate (#613)"
L9="$(issues l9 '7\tbug\n')"
aud "$L9" >/dev/null;          t_eq "a violation does NOT fail the default audit" "exit 0" "$(cat "$T_TMP/aud.rc")"
aud "$L9" --strict >/dev/null; t_eq "--strict fails on the same input" "exit 1" "$(cat "$T_TMP/aud.rc")"
# Every theme has two issues citing each other, so the sibling loop ends false under set -e.
L10="$(issues l10 '7\tbug,theme:floor\tsee #8 and #9\n8\tbug,theme:ci\tsee #7\n9\ttheme:floor\tsee #7\n')"
aud "$L10" >/dev/null;          t_eq "the default audit exits 0 when no theme has a lonely issue" "exit 0" "$(cat "$T_TMP/aud.rc")"
aud "$L10" --strict >/dev/null; t_eq "--strict still fails on the same input" "exit 1" "$(cat "$T_TMP/aud.rc")"
aud "$(issues l11 '7\tbug,theme:floor\tsee #8\n8\tbug,theme:ci\tsee #7\n')" --strict >/dev/null
t_eq "control: --strict exits 0 on a clean backlog" "exit 0" "$(cat "$T_TMP/aud.rc")"
t_section "--audit refuses to call an unread open list a clean audit (harbor#626)"
# An unreadable or empty open-issue list means nothing was audited. Each arm below was RED on the
# pre-fix code: the first printed nothing, the second printed a clean "edges consistent".
unreadable() { STUB_LIST_FAIL=yes; aud "$@"; STUB_LIST_FAIL=no; }
U0="$(issues u0 '')"; E0="$(issues e0 '')"
graph '{"number":7,"parent":{"number":999},"subIssues":{"totalCount":0}}'
t_has "a failed gh read is reported, not exited on silently" "$(unreadable "$U0")" "could not read open issues — nothing was audited"
unreadable "$U0" >/dev/null;           t_eq "the default audit fails when the open list is unreadable" "exit 1" "$(cat "$T_TMP/aud.rc")"
unreadable "$U0" --strict >/dev/null;  t_eq "--strict fails when the open list is unreadable" "exit 1" "$(cat "$T_TMP/aud.rc")"
t_has "an empty open list is reported, not read as a clean audit" "$(aud "$E0")" "could not read open issues — nothing was audited"
t_hasnt "an empty open list does not render the graph as consistent" "$(aud "$E0")" "edges consistent"
aud "$E0" --strict >/dev/null;         t_eq "--strict fails on an empty open list" "exit 1" "$(cat "$T_TMP/aud.rc")"
t_hasnt "the cardinality section does not run over an empty list (it read it as 'none')" "$(aud "$E0")" "cardinality"
live 'bug\nfeature\ntheme:floor\ntheme:ci\nepic:provenance\nblocked:review\n'
t_has "control: a non-empty open list still reports the closed-parent child" "$(aud "$(issues c0 '7\tbug,theme:floor\n')")" "CLOSED parent: #7->#999"
# The join itself, run on its own: the audit's guard stops an empty open list before the join, so reverting
# only the join is invisible to every audit arm. This arm runs the join line as written in the script.
JOIN="$(grep -F 'closedpar="$(awk' "$SUT")"
join_out() { ( ALLOPEN="$1"; GRAPH="$2"; eval "$JOIN"; printf '%s' "$closedpar" ); }  # <open-list> <graph>
printf '7\t999\t0\n8\t-\t0\n' > "$T_TMP/join-graph"; : > "$T_TMP/join-empty"; printf '999\n' > "$T_TMP/join-open"
t_has "the join line is found in the script" "$JOIN" "closedpar="
t_eq "an EMPTY first file does not swallow the graph: the closed-parent edge is reported" " #7->#999" "$(join_out "$T_TMP/join-empty" "$T_TMP/join-graph")"
t_eq "control: a parent that IS open is not reported" "" "$(join_out "$T_TMP/join-open" "$T_TMP/join-graph")"

t_done
