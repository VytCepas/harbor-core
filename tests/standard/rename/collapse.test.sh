#!/usr/bin/env sh
# standard-rename.sh (harbor#968): closing a dual-read window collapses it to ONE read of the new name, never a repeat; a file that
# declares rename-fixture keeps its old names; vendor/ is left to bin/standard-vendor.sh; a workflow edit becomes a patch the operator
# applies. Each defect measured on the 2026-11-15 rows has its case here. Fixture repos come from tests/checks/standard-rename-fixture.sh.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/standard-rename.sh"
command -v python3 >/dev/null 2>&1 || { t_section "python3 is absent"; t_exit "the codemod is unchecked without python3" 3 sh "$TOOL" --plan --id rename-0001; t_done; }
H="$HOME"   # a sandbox HOME of its own
unset CLAUDE_CONFIG_DIR
. "$T_ROOT/tests/checks/standard-rename-fixture.sh"
TAB="$(printf '\t')"
WF=".github/workflows"
# Two switches whose window closed in 2000: every site that read both names by hand now holds the new name beside the old one.
mkclose() { # <dir>
  mkfix "$1"; mkdir -p "$CR/tests" "$CR/vendor/naming" "$CR/$WF"
  printf 'rename-0001\tenv:XOLD_FLOOR_SHADOW\tenv:HARBOR_ADMISSION_SHADOW\tenv\tW5\t2000-01-01\ta switch read under both names\n' >> "$CR/standards/naming/renames.tsv"
  printf 'rename-0002\tenv:XOLD_DISABLE_FLOOR\tenv:HARBOR_ADMISSION_DISABLE\tenv\tW5\t2000-01-01\tthe kill switch, read under both names\n' >> "$CR/standards/naming/renames.tsv"
  { printf '#!/bin/sh\n'
    printf 'env -u HARBOR_ADMISSION_SHADOW -u XOLD_FLOOR_SHADOW -u HARBOR_ADMISSION_DISABLE -u XOLD_DISABLE_FLOOR sh x\n'                                  # 2  repeated -u
    printf 'case "$1" in *HARBOR_ADMISSION_DISABLE*|*XOLD_DISABLE_FLOOR*) ;; esac\n'                                                                       # 3  alternation
    printf "grep -qE 'floor_block|HARBOR_ADMISSION_SHADOW|XOLD_FLOOR_SHADOW' \"\$f\"\n"                                                                      # 4  alternation in a regex
    printf 'HARBOR_ADMISSION_SHADOW="$a" HARBOR_ADMISSION_DISABLE="$b" XOLD_FLOOR_SHADOW="$a" XOLD_DISABLE_FLOOR="$b" sh y\n'                       # 5  setters
    printf '[ -n "${HARBOR_ADMISSION_SHADOW+x}${XOLD_FLOOR_SHADOW+x}" ] && echo on\n'                                                               # 6  adjacent expansions
    printf '# the shadow switch (HARBOR_ADMISSION_SHADOW, or XOLD_FLOOR_SHADOW until 2000-01-01): records instead of blocking\n'                     # 7  prose
    printf 'for _n in HARBOR_ADMISSION_DISABLE HARBOR_ADMISSION_SHADOW XOLD_DISABLE_FLOOR XOLD_FLOOR_SHADOW; do :; done\n'                                  # 8  a name list
    printf 'echo "$XOLD_FLOOR_SHADOW"\n'                                                                                                                 # 9  an old read alone: a plain rename
    printf '# it was XOLD_FLOOR_SHADOW and is HARBOR_ADMISSION_SHADOW\n'                                                                                # 10 history: no rewrite decides it
  } > "$CR/bin/dual.sh"
  cat > "$CR/bin/lines.mjs" <<'EOF'
const C = [
  process.env.HARBOR_ADMISSION_SHADOW,
  process.env.XOLD_FLOOR_SHADOW,   // the old name, read until 2000-01-01
  "x",
];
const P = process.env.HARBOR_ADMISSION_DISABLE
  || process.env.XOLD_DISABLE_FLOOR   // the old name, read until 2000-01-01
  || "d";
elif [ -n "${XOLD_FLOOR_SHADOW+x}" ]; then   # the old name, read until 2000-01-01
EOF
  { printf 'jobs:\n  a:\n    runs-on: ${{ (inputs.runner || vars.HARBOR_ADMISSION_SHADOW || vars.XOLD_FLOOR_SHADOW) }}\n'; } > "$CR/$WF/ci.yml"
  printf '# vendored copy\nREAD="${XOLD_FLOOR_SHADOW:-0}"\n' > "$CR/vendor/naming/copy.sh"
  { printf '#!/bin/sh\n# rename-fixture[XOLD_FLOOR_SHADOW]: feeds the old spelling on purpose, to prove the window\n'
    printf 'XOLD_FLOOR_SHADOW=1 sh bin/dual.sh\nXOLD_DISABLE_FLOOR=1 sh bin/dual.sh\n'; } > "$CR/tests/partial.test.sh"
  { printf '#!/bin/sh\n# rename-fixture: a suite of old inputs, kept whole\n'
    printf 'XOLD_FLOOR_SHADOW=1 sh bin/dual.sh\nenv -u HARBOR_ADMISSION_SHADOW -u XOLD_FLOOR_SHADOW sh x\n'; } > "$CR/tests/whole.test.sh"
  { printf 'W5_ALIASES='"'"'XOLD_FLOOR_SHADOW\tHARBOR_ADMISSION_SHADOW\nXOLD_DISABLE_FLOOR\tHARBOR_ADMISSION_DISABLE'"'"'\nROOT_ALIASES="$W5_ALIASES"\n'; } > "$CR/bin/aliases.sh"
  git -C "$CR" init -q; cc base
}
dup() { # <file> — a line that holds one name twice in a row (a repeated token, alternation member or setter): its text, else nothing
  awk '{ n = split($0, w, /[^A-Za-z0-9_]+/); for (i = 1; i <= n; i++) if (w[i] ~ /^HARBOR_/ && (w[i+1] == w[i] || w[i+2] == w[i] && w[i+1] ~ /^HARBOR_/ && w[i+3] == w[i+1])) { print NR ": " $0; break } }' "$1"
}
t_section "a collapse leaves exactly one read of the new name"
mkclose "$H/c1"
P="$(crun --plan --wave W5 2>/dev/null)"
t_exit "plan: lines it cannot decide are residual, the rest is predicted" 1 crun --plan --wave W5
t_has "...the history line (old and new name, no repeat shape) is listed as undecided" "$P" "bin/dual.sh:10"
t_exit "apply" 1 crun --apply --wave W5
D="$(cat "$CR/bin/dual.sh")"
t_eq "no repeated name in the rewritten script" "" "$(dup "$CR/bin/dual.sh")"
t_has "1. a repeated -u keeps one of each" "$D" 'env -u HARBOR_ADMISSION_SHADOW -u HARBOR_ADMISSION_DISABLE sh x'
t_has "...an alternation member goes" "$D" 'case "$1" in *HARBOR_ADMISSION_DISABLE*) ;; esac'
t_has "...so does one in a regex" "$D" "grep -qE 'floor_block|HARBOR_ADMISSION_SHADOW' \"\$f\""
t_has "...a setter written twice stays once" "$D" 'HARBOR_ADMISSION_SHADOW="$a" HARBOR_ADMISSION_DISABLE="$b" sh y'
t_has "...adjacent expansions of both names stay one (\${NEW+x}\${NEW+x})" "$D" '[ -n "${HARBOR_ADMISSION_SHADOW+x}" ] && echo on'
t_has "3. dual-read prose reads as one name, the date gone with it" "$D" '# the shadow switch (HARBOR_ADMISSION_SHADOW): records instead of blocking'
t_has "...a name list" "$D" 'for _n in HARBOR_ADMISSION_DISABLE HARBOR_ADMISSION_SHADOW; do :; done'
t_has "an old read alone is still a plain rename" "$D" 'echo "$HARBOR_ADMISSION_SHADOW"'
t_has "2. a line naming both names that is no repeat is left as written, never rewritten into 'it was NEW and is NEW'" "$D" '# it was XOLD_FLOOR_SHADOW and is HARBOR_ADMISSION_SHADOW'
t_eq "...a line that reads the old name beside the same line for the new one goes (NEW,/OLD, and a || continuation)" "0" "$(grep -c 'process.env.XOLD_\|the old name, read until' "$CR/bin/lines.mjs" | awk '{ print $1 - 1 }')"
t_eq "...leaving the new reads and the continuation's tail" "const C = [
  process.env.HARBOR_ADMISSION_SHADOW,
  \"x\",
];
const P = process.env.HARBOR_ADMISSION_DISABLE
  || \"d\";" "$(sed -n 1,6p "$CR/bin/lines.mjs")"
t_eq "...and a window-tagged line with no twin to match is left for a person, never rewritten to a repeat" 'elif [ -n "${XOLD_FLOOR_SHADOW+x}" ]; then   # the old name, read until 2000-01-01' "$(sed -n 7p "$CR/bin/lines.mjs")"
t_eq "6. the retired alias pairs are dropped, not left as NEW<TAB>NEW" "W5_ALIASES=''
ROOT_ALIASES=\"\$W5_ALIASES\"" "$(sed -n '1,2p' "$CR/bin/aliases.sh" | grep -v '^#!')"
t_has "...and the residual names the history line, the tagged line and the workflow" "$(crun --residual --wave W5 2>/dev/null | sed -n 1p)" "residual 3"

t_section "a table keeps the pairs that are not retired"
mkclose "$H/c1b"
printf 'ALIASES='"'"'XOLD_FLOOR_SHADOW\tHARBOR_ADMISSION_SHADOW\nKEEP_OLD\tKEEP_NEW\nXOLD_DISABLE_FLOOR\tHARBOR_ADMISSION_DISABLE'"'"'\n' > "$CR/bin/aliases.sh"; cc t
crun --apply --wave W5 >/dev/null 2>&1
t_eq "...the first and last go, the quote moves to the line that stays" "ALIASES='KEEP_OLD${TAB}KEEP_NEW'" "$(cat "$CR/bin/aliases.sh")"

t_section "4. a file that declares rename-fixture keeps its old names"
mkclose "$H/c2"
crun --apply --wave W5 >/dev/null 2>&1
t_eq "a scoped marker keeps the name it lists, and the other name in the file is rewritten" "XOLD_FLOOR_SHADOW=1 sh bin/dual.sh
HARBOR_ADMISSION_DISABLE=1 sh bin/dual.sh" "$(grep -v '^#' "$CR/tests/partial.test.sh")"
t_eq "...a whole-file marker keeps every line, the repeated -u included" "XOLD_FLOOR_SHADOW=1 sh bin/dual.sh
env -u HARBOR_ADMISSION_SHADOW -u XOLD_FLOOR_SHADOW sh x" "$(grep -v '^#' "$CR/tests/whole.test.sh")"
t_hasnt "...and neither is in the residual" "$(crun --residual --wave W5 2>/dev/null)" "tests/"
t_has "...the report counts what was kept" "$(cat "$CR/build/rename-report.tsv")" "fixture-kept	tests/whole.test.sh"
t_eq "...the marker line itself is untouched" "# rename-fixture[XOLD_FLOOR_SHADOW]: feeds the old spelling on purpose, to prove the window" "$(sed -n 2p "$CR/tests/partial.test.sh")"

t_section "5. vendor/ is never rewritten, and the report says to re-vendor"
mkclose "$H/c3"
V="$(crun --plan --wave W5 2>&1)"
t_has "plan says where the vendored copy is brought up to date" "$V" "sh bin/standard-vendor.sh ."
crun --apply --wave W5 >/dev/null 2>&1
t_eq "the vendored copy is byte-identical" "READ=\"\${XOLD_FLOOR_SHADOW:-0}\"" "$(sed -n 2p "$CR/vendor/naming/copy.sh")"
t_has "...the report names it" "$(cat "$CR/build/rename-report.tsv")" "vendor	vendor/naming/copy.sh"
t_hasnt "...and it is no residual" "$(crun --residual --wave W5 2>/dev/null)" "vendor/"

t_section "7. a workflow edit is a patch, never a write"
mkclose "$H/c4"
WF0="$(cat "$CR/$WF/ci.yml")"
t_has "plan writes the patch and names it" "$(crun --plan --wave W5 2>&1)" "rename-workflows.patch"
crun --apply --wave W5 >/dev/null 2>&1
t_eq "the workflow is untouched" "$WF0" "$(cat "$CR/$WF/ci.yml")"
t_eq "...git agrees: nothing under $WF is modified" "" "$(git -C "$CR" status --porcelain -- "$WF")"
t_has "...the patch holds the collapsed edit" "$(cat "$CR/build/rename-workflows.patch")" '+    runs-on: ${{ (inputs.runner || vars.HARBOR_ADMISSION_SHADOW) }}'
t_exit "...and applies cleanly" 0 git -C "$CR" apply --check "$CR/build/rename-workflows.patch"
t_has "the workflow is residual until the operator applies it" "$(crun --residual --wave W5 2>/dev/null)" "$WF/ci.yml"
git -C "$CR" apply "$CR/build/rename-workflows.patch"
t_eq "applied by hand, it reads the new name once" '    runs-on: ${{ (inputs.runner || vars.HARBOR_ADMISSION_SHADOW) }}' "$(sed -n 3p "$CR/$WF/ci.yml")"
t_has "...and the residual is the two undecided lines" "$(crun --residual --wave W5 2>/dev/null | sed -n 1p)" "residual 2"

t_section "a path rename's references in a workflow are a patch too"
mkfix "$H/c5"; mkdir -p "$CR/$WF"
printf '#!/bin/sh\n:\n' > "$CR/bin/old-tool.sh"; chmod +x "$CR/bin/old-tool.sh"
printf 'jobs:\n  a:\n    steps:\n      - run: sh bin/old-tool.sh\n' > "$CR/$WF/ci.yml"
printf 'rename-0001\tbin/old-tool.sh\tbin/standard-tool.sh\tbin\tW4\t-\ta plain rename\n' >> "$CR/standards/naming/renames.tsv"
git -C "$CR" init -q; cc base
crun --apply --id rename-0001 >/dev/null 2>&1
t_eq "the file moved" "bin/standard-tool.sh" "$(git -C "$CR" ls-files bin/standard-tool.sh)"
t_has "...the workflow still names the old path" "$(cat "$CR/$WF/ci.yml")" "sh bin/old-tool.sh"
t_has "...and the patch carries the new one" "$(cat "$CR/build/rename-workflows.patch")" "+      - run: sh bin/standard-tool.sh"
t_done
