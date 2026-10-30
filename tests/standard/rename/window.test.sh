#!/usr/bin/env sh
# standard-rename.sh (harbor#996): a row with remove_by keeps the old name working until then, a symlink shim for a path and a
# dual read for an env name, and a form no rewrite decides is residual. Split from tests/standard/rename/rename.test.sh at the
# 500-line budget (tests/README.md T2); the fixture repos come from tests/checks/standard-rename-fixture.sh.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/standard-rename.sh"
command -v python3 >/dev/null 2>&1 || { t_section "python3 is absent"; t_exit "the codemod is unchecked without python3" 3 sh "$TOOL" --plan --id rename-0001; t_done; }
H="$HOME"   # a sandbox HOME of its own
unset CLAUDE_CONFIG_DIR
. "$T_ROOT/tests/checks/standard-rename-fixture.sh"
# ── shims. A row with remove_by asks for the old path to keep working until then: a relative symlink to the new file, and for a
# bin/*.sh the two register lines lint asks of it. The codemod used to refuse such a row (exit 3), then wrote an `exec` forwarder.
mkshim() { # <dir> [noregs] — an executable, a sourced executable library, a python job, a test script and a data file, each renamed with a shim until 2099
  mkfix "$1"; mkdir -p "$CR/data"
  printf '#!/bin/sh\necho "tool args=$* in=$(cat)"\n' > "$CR/bin/old-tool.sh"; chmod +x "$CR/bin/old-tool.sh"
  printf '#!/usr/bin/env sh\nlib_fn() { echo "lib says $1"; }\n' > "$CR/bin/old-lib.sh"; chmod +x "$CR/bin/old-lib.sh"
  printf '#!/usr/bin/env python3\nimport sys\nprint("py args=%%s" %% sys.argv[1:])\n' > "$CR/bin/old-job.py"; chmod +x "$CR/bin/old-job.py"
  printf '#!/bin/sh\n: a check\n' > "$CR/bin/old-check-test.sh"; chmod +x "$CR/bin/old-check-test.sh"
  printf '#!/bin/sh\n. "$(dirname "$0")/old-lib.sh"; lib_fn user\n' > "$CR/bin/user.sh"
  printf '# list\n' > "$CR/data/old-list.md"
  printf 'run bin/old-tool.sh and source bin/old-lib.sh; the list is data/old-list.md\nnot it: xold-tool.sh, old-tool.sh-bak\n' > "$CR/docs/use.md"
  printf 'legacy-0001\tname.alias\tbin/old-tool.sh\tlegacy\t2027-02-22\tfirst scan\n' >> "$CR/standards/naming/exemptions.tsv"
  printf 'rename-0001\tbin/old-tool.sh\tbin/standard-tool.sh\tbin\tW4\t2099-12-31\ta shim until 2099\n' >> "$CR/standards/naming/renames.tsv"
  printf 'rename-0002\tbin/old-lib.sh\tbin/standard-lib.sh\tbin\tW4\t2099-12-31\ta sourced library\n' >> "$CR/standards/naming/renames.tsv"
  printf 'rename-0003\tdata/old-list.md\tdocs/archive/list.md\tpath\tW4\t2099-12-31\ta data file into another directory\n' >> "$CR/standards/naming/renames.tsv"
  printf 'rename-0006\tbin/old-job.py\tbin/standard-job.py\tbin\tW4\t2099-12-31\tan executable run through an interpreter\n' >> "$CR/standards/naming/renames.tsv"
  printf 'rename-0007\tbin/old-check-test.sh\tbin/standard-check-test.sh\tbin\tW4\t2099-12-31\ta test script\n' >> "$CR/standards/naming/renames.tsv"
  if [ "${2:-}" != noregs ]; then   # the two registers lint reads for a bin tool
    mkdir -p "$CR/contracts"
    printf '# idle tools (fixture)\n#\nold-lib.sh             IDLE  a library nothing calls\n' > "$CR/contracts/idle-tools.txt"
    printf '# cli (fixture)\n\n## Internal scripts\n\n| Script | Why it is not a verb |\n|---|---|\n| `old-tool.sh` | internal |\n\n**Out of scope:** prose after the table.\n' > "$CR/contracts/cli.md"
  fi
  git -C "$CR" init -q; cc base
}
t_section "a row with remove_by leaves a symlink at the old path, and the references still move"
mkshim "$H/shim"
t_exit "plan: a shim row is planned (it used to be refused as unchecked)" 0 crun --plan --wave W4
t_has "...saying where the shim goes and until when" "$(crun --plan --wave W4 2>&1)" "leave a symlink shim at bin/old-tool.sh until 2099-12-31"
t_exit "apply" 0 crun --apply --wave W4
REP="$(cat "$CR/build/rename-report.tsv")"
t_eq "the residual is 0" "residual 0" "$(crun --residual --wave W4 2>/dev/null)"
t_eq "the old executable path is tracked again, as a symlink" "120000" "$(git -C "$CR" ls-files -s bin/old-tool.sh | cut -d' ' -f1)"
t_eq "...and so is the executable library's, which a caller sources" "120000" "$(git -C "$CR" ls-files -s bin/old-lib.sh | cut -d' ' -f1)"
t_eq "...and the python job's, which an interpreter runs" "120000" "$(git -C "$CR" ls-files -s bin/old-job.py | cut -d' ' -f1)"
t_eq "...and the data file's, into another directory" "../docs/archive/list.md" "$(readlink "$CR/data/old-list.md")"
t_eq "the new paths are tracked as the real files, executable ones still executable" "100755 bin/standard-job.py
100755 bin/standard-lib.sh
100755 bin/standard-tool.sh
100644 docs/archive/list.md" "$(git -C "$CR" ls-files -s bin/standard-job.py bin/standard-lib.sh bin/standard-tool.sh docs/archive/list.md | awk '{print $1, $4}')"
printf piped > "$H/in"
t_eq "the shim runs the new file with its arguments and its stdin" "tool args=a b in=piped" "$(sh "$CR/bin/old-tool.sh" a b < "$H/in")"
t_eq "...executed directly too, through the kernel" "tool args=d in=" "$("$CR/bin/old-tool.sh" d </dev/null)"
mkdir -p "$H/pathbin"; ln -sf "$CR/bin/old-tool.sh" "$H/pathbin/tool"
t_eq "...through a symlink on PATH too" "tool args=x in=" "$(PATH="$H/pathbin:$PATH" tool x </dev/null)"
t_eq "a caller that sources the old library path gets the library and keeps running (a forwarder replaced it)" "lib says u
caller continues" "$(sh -c ". '$CR/bin/old-lib.sh'; lib_fn u; echo caller continues")"
command -v python3 >/dev/null 2>&1 && t_eq "an interpreter run on the old path gets the python job (a forwarder handed it a shell script)" "py args=['a', 'b']" "$(python3 "$CR/bin/old-job.py" a b)"
t_has "the repo's own references name the new path" "$(cat "$CR/docs/use.md")" "run bin/standard-tool.sh and source bin/standard-lib.sh; the list is docs/archive/list.md"
t_has "...and the caller sources the new library" "$(cat "$CR/bin/user.sh")" 'standard-lib.sh'
t_has "...a lookalike stays" "$(cat "$CR/docs/use.md")" "not it: xold-tool.sh, old-tool.sh-bak"
t_eq "the old name's exemption row stays while the shim lives" 1 "$(grep -c 'bin/old-tool.sh' "$CR/standards/naming/exemptions.tsv")"
t_has "the report names each shim" "$REP" "shim	rename-0001	bin/old-tool.sh	symlink	2099-12-31"
# What lint asks of a bin/*.sh: its name in a contracts/cli.md table and a caller or an idle line. The rewrite moved the register's
# own rows to the new names, so the old names need their own, marked with the row, and only a bin/*.sh needs them.
M1='forwarding shim (harbor#996 rename-0001)'
t_eq "the register's own rows moved to the new names" "1 1" "$(grep -c '`standard-tool.sh`' "$CR/contracts/cli.md") $(grep -c '^standard-lib.sh' "$CR/contracts/idle-tools.txt")"
t_eq "a bin/*.sh shim has its line in the idle list (lint.tool-has-caller)" 1 "$(grep -c "^old-tool.sh .*$M1" "$CR/contracts/idle-tools.txt")"
t_eq "...and its row in the internal-scripts table (lint.cli-contract)" 1 "$(grep -c "^| \`old-tool.sh\` | $M1" "$CR/contracts/cli.md")"
t_eq "...the row sits inside the table, before the prose that follows it" yes "$(awk '/^\| `old-lib.sh`/ { r = NR } /^\*\*Out of scope/ { o = NR } END { print (r && o && r < o) ? "yes" : "no" }' "$CR/contracts/cli.md")"
t_eq "a test script needs a table row and no idle line" "0 1" "$(grep -c '^old-check-test.sh' "$CR/contracts/idle-tools.txt") $(grep -c '^| `old-check-test.sh`' "$CR/contracts/cli.md")"
t_eq "a python job and a data file are no bin/*.sh: neither register hears of them" 0 "$(grep -c 'old-job.py\|old-list.md' "$CR/contracts/idle-tools.txt" "$CR/contracts/cli.md" | awk -F: '{s += $2} END {print s}')"
t_has "the report names the register lines" "$REP" "shim-rows	rename-0001	contracts/idle-tools.txt"
cc applied
t_exit "a second --apply is a no-op" 0 crun --apply --wave W4
t_eq "...and changes nothing, the register lines included" "" "$(git -C "$CR" status --porcelain -- . ':!build')"
t_exit "the register lines name the old path on purpose: they are no residual" 0 crun --residual --wave W4
sed -i.bak '/rename-0001/d' "$CR/contracts/idle-tools.txt"; rm -f "$CR/contracts/idle-tools.txt.bak"
t_exit "a shim whose line was dropped from the idle list is residual" 1 crun --residual --wave W4
t_has "...naming the rule that would fail" "$(crun --residual --wave W4 2>/dev/null)" "no line for the shim at bin/old-tool.sh (lint.tool-has-caller)"
t_exit "...and --apply writes it again" 0 crun --apply --wave W4
t_eq "...once" 1 "$(grep -c "^old-tool.sh .*$M1" "$CR/contracts/idle-tools.txt")"
git -C "$CR" checkout -q -- contracts/idle-tools.txt
# The box. A hook command may name the new file only once it is installed; a shim at the old path does not install it.
SB="$H/shimbox/.claude"; mkdir -p "$SB/bin"
git -C "$CR" show "$(git -C "$CR" rev-list --max-parents=0 HEAD):bin/old-tool.sh" > "$SB/bin/old-tool.sh"; chmod +x "$SB/bin/old-tool.sh"
printf '# .harbor-manifest\n%s 100755 bin/old-tool.sh component c0\n' "$(git hash-object "$SB/bin/old-tool.sh")" > "$SB/.harbor-manifest"
printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/bin/sh %s/bin/old-tool.sh"}]}]}}\n' "$SB" > "$SB/settings.json"
SB0="$(cat "$SB/settings.json")"
t_exit "a shim row's box half is refused while the new file is not deployed" 1 crun --apply --wave W4 --dir "$SB"
t_has "...and says deploy first" "$(crun --plan --wave W4 --dir "$SB" 2>&1)" "deploy the renamed tree first"
t_eq "...settings.json untouched: a hook rewired now would name a missing file" "$SB0" "$(cat "$SB/settings.json")"
cp "$CR/bin/standard-tool.sh" "$SB/bin/"
t_exit "with the new file deployed, the box half plans clean: the old deployed copy is the old path working, no residual" 0 crun --plan --wave W4 --dir "$SB"
t_has "...and the copy is said to stay, until the date" "$(crun --plan --wave W4 --dir "$SB" 2>&1)" "bin/old-tool.sh is deployed and kept: it keeps working until 2099-12-31"
t_exit "apply" 0 crun --apply --wave W4 --dir "$SB"
t_has "the hook names the new file" "$(cat "$SB/settings.json")" "bin/standard-tool.sh"
t_eq "...the old deployed copy is kept (a plain rename removes it)" present "$([ -e "$SB/bin/old-tool.sh" ] && echo present || echo absent)"
t_eq "...and so is its manifest row" 1 "$(grep -c 'bin/old-tool.sh' "$SB/.harbor-manifest")"
printf 'late: bin/old-tool.sh\n' >> "$CR/docs/use.md"
t_exit "a reference added after the apply is residual, the shim is not" 1 crun --residual --wave W4
t_has "...and only that line is listed" "$(crun --residual --wave W4 2>/dev/null)" "docs/use.md:3"
git -C "$CR" checkout -q -- docs/use.md
sed -i.bak 's/^\(rename-0001.*\)2099-12-31\(.*\)$/\12000-01-01\2/' "$CR/standards/naming/renames.tsv"; rm -f "$CR/standards/naming/renames.tsv.bak"
t_exit "past its date the shim is residual" 1 crun --residual --id rename-0001
t_has "...named as outliving remove_by" "$(crun --residual --id rename-0001 2>/dev/null)" "the shim outlived its remove_by 2000-01-01"
t_hasnt "...its register lines are not listed as references on top of that" "$(crun --residual --id rename-0001 2>/dev/null)" "CONTRACTS/"
t_has "plan says --apply removes it" "$(crun --plan --id rename-0001 2>&1)" "outlived 2000-01-01: --apply removes it"
t_exit "apply removes it" 0 crun --apply --id rename-0001
t_eq "the old path is gone" "" "$(git -C "$CR" ls-files bin/old-tool.sh)"
t_eq "...the new file stays" "bin/standard-tool.sh" "$(git -C "$CR" ls-files bin/standard-tool.sh)"
t_eq "...its exemption row is retired" 0 "$(grep -c 'bin/old-tool.sh' "$CR/standards/naming/exemptions.tsv")"
t_eq "...and its lines leave both registers, the other shims' stay" "0 0 1 1" "$(grep -c 'rename-0001' "$CR/contracts/idle-tools.txt") $(grep -c 'rename-0001' "$CR/contracts/cli.md") $(grep -c 'rename-0002' "$CR/contracts/idle-tools.txt") $(grep -c 'rename-0002' "$CR/contracts/cli.md")"
t_exit "...and the residual is 0 again" 0 crun --residual --id rename-0001
t_eq "the other shims are untouched" "120000" "$(git -C "$CR" ls-files -s bin/old-lib.sh | cut -d' ' -f1)"
cc "expired"
printf '#!/bin/sh\necho fresh\n' > "$CR/bin/old-late.sh"; chmod +x "$CR/bin/old-late.sh"; printf 'x\n' > "$CR/docs/Case.md"
printf 'rename-0004\tbin/old-late.sh\tbin/standard-other.sh\tbin\tW4\t2000-01-01\ta date already past\n' >> "$CR/standards/naming/renames.tsv"
printf 'rename-0005\tdocs/Case.md\tdocs/case.md\tpath\tW4\t2099-12-31\tcase only, with a shim\n' >> "$CR/standards/naming/renames.tsv"
cc late
t_exit "a date already past when the row first runs writes no shim" 0 crun --apply --id rename-0004
t_eq "...the old path is simply gone" "" "$(git -C "$CR" ls-files bin/old-late.sh)"
t_eq "...and no register hears of it" 0 "$(grep -c 'old-late' "$CR/contracts/idle-tools.txt" "$CR/contracts/cli.md" | awk -F: '{s += $2} END {print s}')"
t_exit "a case-only move cannot have a shim: it would be the file itself" 1 crun --plan --id rename-0005
t_has "...and says so" "$(crun --plan --id rename-0005 2>&1)" "would be the file docs/case.md itself"
mkshim "$H/shim-noregs" noregs
t_exit "a tree without the two registers gets its shim and no invented register" 0 crun --apply --wave W4
t_eq "...CONTRACTS was not created" "absent" "$([ -e "$CR/CONTRACTS" ] && echo present || echo absent)"
t_eq "...the shim is there" "120000" "$(git -C "$CR" ls-files -s bin/old-tool.sh | cut -d' ' -f1)"

# ── env. A name that is read, set and quoted. In a window a reader reads the new name, then the old.
mkenv() { # <dir> — a switch read in a window, a posture renamed plain, and the forms in between
  mkfix "$1"; mkdir -p "$CR/tests"
  printf '#!/bin/sh\n# HELM_FLOOR_SHADOW: record instead of blocking\n[ "${HELM_FLOOR_SHADOW:-0}" = "1" ] && { echo shadow; exit 0; }\necho "posture=${HELM_DESTROY_POSTURE:-ask} again=$HELM_DESTROY_POSTURE"\necho "note=$HELM_FLOOR_SHADOW_NOTE x=${XHELM_FLOOR_SHADOW:-}"\n' > "$CR/bin/probe.sh"
  printf 'HELM_FLOOR_SHADOW=1 sh bin/probe.sh\nenv HELM_DESTROY_POSTURE=deny sh bin/probe.sh\nexport HELM_FLOOR_SHADOW\n' > "$CR/tests/probe-test.sh"
  printf 'echo "set \\$HELM_DESTROY_POSTURE to deny"\n' >> "$CR/tests/probe-test.sh"
  # what CLEARS the switch: a script that must see it off, whichever spelling the environment holds
  printf '#!/bin/sh\nunset HELM_FLOOR_SHADOW\nunset HELM_UNRELATED\nsh "$(dirname "$0")/probe.sh" | sed -n 1p\n' > "$CR/bin/clear.sh"
  printf '#!/bin/sh\nHELM_FLOOR_SHADOW= sh "$(dirname "$0")/probe.sh" | sed -n 1p\n' > "$CR/bin/clear2.sh"
  printf 'Set `HELM_FLOOR_SHADOW=1`, or read `${HELM_FLOOR_SHADOW:-0}`; the posture is HELM_DESTROY_POSTURE.\n' > "$CR/docs/knobs.md"
  printf '  HELM_FLOOR_SHADOW: "1"\n"HELM_DESTROY_POSTURE": "deny"\n' > "$CR/tests/env.yml"
  printf 'legacy-0010\tname.env\tenv:HELM_FLOOR_SHADOW\tlegacy\t2027-02-15\tfirst scan\n' >> "$CR/standards/naming/exemptions.tsv"
  printf 'legacy-0011\tname.env\tenv:HELM_DESTROY_POSTURE\tlegacy\t2027-02-15\tfirst scan\n' >> "$CR/standards/naming/exemptions.tsv"
  printf 'rename-0001\tenv:HELM_FLOOR_SHADOW\tenv:HARBOR_ADMISSION_SHADOW\tenv\tW5\t2099-12-31\ta switch read under both names\n' >> "$CR/standards/naming/renames.tsv"
  printf 'rename-0002\tenv:HELM_DESTROY_POSTURE\tenv:HARBOR_ADMISSION_DESTROY_POSTURE\tenv\tW5\t-\ta plain rename\n' >> "$CR/standards/naming/renames.tsv"
  # two forms no rewrite decides: an awk reader and an operator a dual read cannot wrap
  printf 'BEGIN { s = ENVIRON["HELM_FLOOR_SHADOW"] }\n' > "$CR/bin/probe.awk"
  printf '#!/bin/sh\necho "${HELM_FLOOR_SHADOW:+on}"\n' > "$CR/bin/alt.sh"
  printf '#!/bin/sh\ntrap '"'"'echo $HELM_FLOOR_SHADOW'"'"' EXIT\n' > "$CR/bin/sq.sh"
  printf '#!/bin/sh\nf() { local HELM_FLOOR_SHADOW; :; }\n' > "$CR/bin/shadowfn.sh"
  printf '#!/bin/sh\necho "set \\$HELM_FLOOR_SHADOW to 1 to record instead of blocking"\n' > "$CR/bin/msg.sh"
  git -C "$CR" init -q; cc base
}
probe() { env -u HELM_FLOOR_SHADOW -u HELM_DESTROY_POSTURE -u HARBOR_ADMISSION_SHADOW -u HARBOR_ADMISSION_DESTROY_POSTURE "$@" sh "$CR/bin/probe.sh"; }
t_section "the env surface: readers read both names in the window, and a form no rewrite decides is residual"
mkenv "$H/env"
CL0="$(env -u HARBOR_ADMISSION_SHADOW HELM_FLOOR_SHADOW=1 sh "$CR/bin/clear.sh") | $(env -u HARBOR_ADMISSION_SHADOW HELM_FLOOR_SHADOW=1 sh "$CR/bin/clear2.sh")"
t_exit "plan: forms a dual read cannot wrap are residual, not guessed" 1 crun --plan --wave W5
P="$(crun --plan --wave W5 2>/dev/null)"
t_has "...the awk reader is listed" "$P" "bin/probe.awk:1"
t_has "...and so is the operator" "$P" "bin/alt.sh:2"
t_has "...and a name inside single quotes, which may be a program for another language" "$P" "bin/sq.sh:2"
t_has "...and a function-local declaration, which would hide only the old name" "$P" "bin/shadowfn.sh:2"
t_has "...and an escaped \$NAME, which may be a message or a script this one writes" "$P" "bin/msg.sh:2"
t_has "...as forms no rewrite decides" "$P" "no rewrite decides this form"
t_hasnt "the lines it can rewrite are not residual" "$P" "bin/probe.sh"
git -C "$CR" rm -q bin/probe.awk bin/alt.sh bin/sq.sh bin/shadowfn.sh bin/msg.sh; cc "drop the undecidable forms"
t_exit "plan: residual 0 once they are gone" 0 crun --plan --wave W5
t_has "...saying which name gets a window" "$(crun --plan --wave W5 2>&1)" "readers read the new name, then the old, until 2099-12-31"
t_exit "apply" 0 crun --apply --wave W5
REP="$(cat "$CR/build/rename-report.tsv")"
t_eq "residual 0, the fallback reads are not residual" "residual 0" "$(crun --residual --wave W5 2>/dev/null)"
PR="$(cat "$CR/bin/probe.sh")"
t_has "a reader in the window reads the new name, then the old" "$PR" '[ "${HARBOR_ADMISSION_SHADOW:-${HELM_FLOOR_SHADOW:-0}}" = "1" ]'
t_has "...in the default form and the bare form" "$PR" 'posture=${HARBOR_ADMISSION_DESTROY_POSTURE:-ask} again=$HARBOR_ADMISSION_DESTROY_POSTURE'
t_has "a comment takes the new name" "$PR" "# HARBOR_ADMISSION_SHADOW: record instead of blocking"
t_has "lookalikes stay: HELM_FLOOR_SHADOW_NOTE and XHELM_FLOOR_SHADOW" "$PR" 'note=$HELM_FLOOR_SHADOW_NOTE x=${XHELM_FLOOR_SHADOW:-}'
t_has "an escaped \$NAME in a plain rename is a mention: it takes the new name" "$(cat "$CR/tests/probe-test.sh")" 'echo "set \$HARBOR_ADMISSION_DESTROY_POSTURE to deny"'
t_has "what clears the switch clears both names: unset" "$(cat "$CR/bin/clear.sh")" 'unset HARBOR_ADMISSION_SHADOW HELM_FLOOR_SHADOW
unset HELM_UNRELATED'
t_has "...and an empty assignment for one command" "$(cat "$CR/bin/clear2.sh")" 'HARBOR_ADMISSION_SHADOW= HELM_FLOOR_SHADOW= sh'
t_eq "BEHAVIOUR: the script still clears the switch when the environment holds the OLD spelling" "$CL0" "$(env -u HARBOR_ADMISSION_SHADOW HELM_FLOOR_SHADOW=1 sh "$CR/bin/clear.sh") | $(env -u HARBOR_ADMISSION_SHADOW HELM_FLOOR_SHADOW=1 sh "$CR/bin/clear2.sh")"
t_eq "...and the new spelling too" "$CL0" "$(env -u HELM_FLOOR_SHADOW HARBOR_ADMISSION_SHADOW=1 sh "$CR/bin/clear.sh") | $(env -u HELM_FLOOR_SHADOW HARBOR_ADMISSION_SHADOW=1 sh "$CR/bin/clear2.sh")"
t_has "setters take the new name: an assignment, env, export" "$(cat "$CR/tests/probe-test.sh")" "HARBOR_ADMISSION_SHADOW=1 sh bin/probe.sh
env HARBOR_ADMISSION_DESTROY_POSTURE=deny sh bin/probe.sh
export HARBOR_ADMISSION_SHADOW"
t_has "...and a YAML key (window) and a quoted key (plain)" "$(cat "$CR/tests/env.yml")" '  HARBOR_ADMISSION_SHADOW: "1"
"HARBOR_ADMISSION_DESTROY_POSTURE": "deny"'
t_has "prose takes the new name, with no dual read" "$(cat "$CR/docs/knobs.md")" 'Set `HARBOR_ADMISSION_SHADOW=1`, or read `${HARBOR_ADMISSION_SHADOW:-0}`; the posture is HARBOR_ADMISSION_DESTROY_POSTURE.'
t_eq "the window's name keeps its exemption row, the plain one's is retired" "1 0" "$(grep -c 'env:HELM_FLOOR_SHADOW' "$CR/standards/naming/exemptions.tsv") $(grep -c 'env:HELM_DESTROY_POSTURE' "$CR/standards/naming/exemptions.tsv")"
t_eq "BEHAVIOUR: the old spelling still switches it" "shadow" "$(probe HELM_FLOOR_SHADOW=1)"
t_eq "...the new spelling too" "shadow" "$(probe HARBOR_ADMISSION_SHADOW=1)"
t_eq "...neither: the default" "posture=ask again=
note= x=" "$(probe)"
t_eq "...the plain rename reads the new name" "posture=deny again=deny" "$(probe HARBOR_ADMISSION_DESTROY_POSTURE=deny | sed -n 1p)"
t_eq "...and not the old one: a plain rename has no window" "posture=ask again=" "$(probe HELM_DESTROY_POSTURE=deny | sed -n 1p)"
t_has "the report names the window" "$REP" "env	rename-0001	HELM_FLOOR_SHADOW	HARBOR_ADMISSION_SHADOW	window"
cc applied
t_exit "a second --apply is a no-op" 0 crun --apply --wave W5
t_eq "...and changes nothing" "" "$(git -C "$CR" status --porcelain -- . ':!build')"
printf 'HELM_FLOOR_SHADOW=1 sh bin/probe.sh   # the OLD spelling on purpose: it keeps the window proved\n' > "$CR/tests/window-test.sh"; cc "a suite sets the old name"
t_exit "a re-run once the new name is in the tree" 0 crun --apply --wave W5
t_has "...leaves a suite that sets the old name on purpose (harbor#961)" "$(cat "$CR/tests/window-test.sh")" "HELM_FLOOR_SHADOW=1 sh bin/probe.sh"
t_eq "...and the tree clean" "" "$(git -C "$CR" status --porcelain -- . ':!build')"
git -C "$CR" rm -q tests/window-test.sh; cc "drop it"
printf 'echo "$HELM_FLOOR_SHADOW"\n' >> "$CR/bin/probe.sh"
t_exit "a reader added after the apply is not applied yet: the window would wrap it" 1 crun --residual --wave W5
git -C "$CR" checkout -q -- bin/probe.sh
sed -i.bak 's/^\(rename-0001.*\)2099-12-31\(.*\)$/\12000-01-01\2/' "$CR/standards/naming/renames.tsv"; rm -f "$CR/standards/naming/renames.tsv.bak"
t_has "past its date the window is to be closed" "$(crun --plan --id rename-0001 2>&1)" "closing the window of 2000-01-01"
t_exit "...and a leftover dual read is not applied yet" 1 crun --residual --id rename-0001
t_exit "apply closes it" 0 crun --apply --id rename-0001
t_has "the fallback is collapsed" "$(cat "$CR/bin/probe.sh")" '[ "${HARBOR_ADMISSION_SHADOW:-0}" = "1" ]'
t_hasnt "...no old-name read is left in the script" "$(cat "$CR/bin/probe.sh")" '{HELM_FLOOR_SHADOW'
t_has "the clearings collapse with it: unset" "$(cat "$CR/bin/clear.sh")" 'unset HARBOR_ADMISSION_SHADOW
unset HELM_UNRELATED'
t_has "...and the empty assignment" "$(cat "$CR/bin/clear2.sh")" 'HARBOR_ADMISSION_SHADOW= sh "$(dirname'
t_eq "BEHAVIOUR: the old spelling no longer switches it" "posture=ask again=" "$(probe HELM_FLOOR_SHADOW=1 | sed -n 1p)"
t_eq "...the new one still does" "shadow" "$(probe HARBOR_ADMISSION_SHADOW=1)"
t_eq "the exemption row goes with the window" 0 "$(grep -c 'env:HELM_FLOOR_SHADOW' "$CR/standards/naming/exemptions.tsv")"
t_exit "...and the residual is 0" 0 crun --residual --wave W5
printf 'rename-0003\tenv:HELM_OTHER\tenv:HARBOR_NOTAFAMILY_X\tenv\tW5\t-\ta name the registry rejects\n' >> "$CR/standards/naming/renames.tsv"
printf 'echo "$HELM_OTHER"\n' >> "$CR/bin/probe.sh"
t_exit "the registry rejects a new env name: refused" 1 crun --apply --id rename-0003
t_has "...naming the rule" "$(crun --plan --id rename-0003 2>&1)" "name.env"
t_has "...and nothing was rewritten" "$(cat "$CR/bin/probe.sh")" 'echo "$HELM_OTHER"'
t_done
