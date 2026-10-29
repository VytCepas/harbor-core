#!/usr/bin/env sh
# bin/lint-constitution.sh and doc.constitution-abstract: the constitution carries no date, ticket, absolute home path or
# workload repo name (harbor#1273). The registry and its repo names are made up, so this file names no real workload.
. "$(dirname "$0")/../../lib/core.sh"; t_init
REGD="$T_TMP/priv/inject.d/box"; mkdir -p "$REGD"
printf '# name\tpath\twhat\nzorbcorp\t~/x\tmade up\nharbor\t~/h\tthe control plane\nproject-init\t~/y\tyard\n' > "$REGD/projects.tsv"
LC() { CONSTITUTION_FILE="$1" HARBOR_SCOPE_PRIVATE="${2:-$T_TMP/priv}" sh "$T_ROOT/bin/lint-constitution.sh" 2>&1; }
rc() { CONSTITUTION_FILE="$1" HARBOR_SCOPE_PRIVATE="${2:-$T_TMP/priv}" sh "$T_ROOT/bin/lint-constitution.sh" >/dev/null 2>&1; echo $?; }
doc() { printf '%s\n' "$2" > "$T_TMP/$1.md"; printf '%s' "$T_TMP/$1.md"; }

t_section "a clean constitution is green"
D="$(doc clean '# Rules
> **Path root:** `~/port/harbor` resolves `./` paths (the declared root is exempt).
A rule with a pointer (case: *Something*). Harbor, project-init and projects-orchestrator are its own repos.
Run under `/bin/sh`; deliverables go in `~/Deliverables/<YYYY-MM-DD>-<slug>/`.
```sh
echo 2026-01-01 harbor#1 /Users/x zorbcorp   # a fence is code, not prose
```')"
t_eq "exit 0" "0" "$(rc "$D")"
t_has "...says it judged the registry's workloads" "$(LC "$D")" "judged against 1 registered workload repo(s)"

t_section "each kind of specific is red, named with its line, and carries a fix"
for c in "date|kept since 2026-10-20|a date" "ticket|as harbor#581 says|a ticket" "bare-ticket|see (#1273) for why|a ticket" \
         "path|measured in /Users/someone/repo|an absolute home path" "library|panics in /Library/Logs/x/|an absolute home path" \
         "name|measured on ~/zorbcorp today|a workload repo name" "name-case|the Zorbcorp tree|a workload repo name"; do
  id="${c%%|*}"; rest="${c#*|}"; line="${rest%%|*}"; kind="${rest#*|}"
  D="$(doc "$id" "# Rules
$line")"
  t_eq "$id: red" "1" "$(rc "$D")"
  t_has "$id: names the kind and line 2" "$(LC "$D")" "$id.md:2: $kind"
  t_has "$id: says where the case goes" "$(LC "$D")" "fix: move the case to docs/explanation/case-law.md"
done

t_section "near misses and Harbor's own repos stay green"
D="$(doc near '# Rules
zorbcorporate and xzorbcorp are other words; harbor and project-init are not workloads.
Version 2026 and №2.12 are not dates or tickets; a heading # Title is not a ticket.')"
t_eq "exit 0" "0" "$(rc "$D")"

t_section "no registry: names are not judged, and the run says so; the rest still is"
D="$(doc noreg '# Rules
measured on ~/zorbcorp today')"
t_eq "a workload name with no registry: green" "0" "$(rc "$D" "$T_TMP/none")"
t_has "...and says names were not judged" "$(LC "$D" "$T_TMP/none")" "workload names were not judged"
D="$(doc noreg-date '# Rules
since 2026-10-20')"
t_eq "a date with no registry: still red" "1" "$(rc "$D" "$T_TMP/none")"

t_section "the shipped constitution passes, and the lint rule runs this check"
t_eq "policy/constitution.md: green" "0" "$(CONSTITUTION_FILE="$T_ROOT/policy/constitution.md" sh "$T_ROOT/bin/lint-constitution.sh" >/dev/null 2>&1; echo $?)"
t_has "lint-conventions names the rule" "$(sh "$T_ROOT/bin/lint-conventions.sh" --list)" "doc.constitution-abstract"
t_eq "a missing file is refused" "1" "$(rc "$T_TMP/absent.md")"
# The rule needs the summary line: a lint script that dies early but exits 0 is red, never a clean constitution.
F="$T_TMP/tree"; mkdir -p "$F/bin" "$F/policy"; cp "$T_ROOT/bin/lint-conventions.sh" "$T_ROOT/bin/library-log.sh" "$F/bin/"; printf '# R\n' > "$F/policy/constitution.md"
printf '#!/usr/bin/env sh\necho "line 9: unexpected EOF"\nexit 0\n' > "$F/bin/lint-constitution.sh"
t_has "a lint script that dies but exits 0: the rule is red" "$(sh "$F/bin/lint-conventions.sh" --only doc.constitution-abstract 2>&1)" "1 violation(s)"
cp "$T_ROOT/bin/lint-constitution.sh" "$T_ROOT/bin/scope-roots.sh" "$F/bin/"   # it asks the registry for the platform ids (harbor#966)
mkdir -p "$F/contracts"; cp "$T_ROOT/contracts/roots.tsv" "$F/contracts/"
t_has "...the working script on a clean file: green" "$(sh "$F/bin/lint-conventions.sh" --only doc.constitution-abstract 2>&1)" "0 violations"
t_eq "an unknown argument is a usage error" "2" "$(sh "$T_ROOT/bin/lint-constitution.sh" --bogus >/dev/null 2>&1; echo $?)"

t_done
