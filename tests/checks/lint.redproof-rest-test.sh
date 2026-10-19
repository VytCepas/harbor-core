#!/usr/bin/env sh
# lint-conventions.sh (harbor#3), part: red proofs kept, second file (harbor#588): the eleven rules C9
# listed as never watched fail. lint.redproof-test.sh is at the 500-line budget (tests/README.md T2).
# Same shape: a clean twin silent, one planted defect, each rule asked alone about a root holding only what it reads.
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
RP="$TMP/redproof-rest"
_rp()       { lint1 "$1" "${2:-$RP}" || true; }
_rp_fresh() { rm -rf "$RP"; mkdir -p "$RP/bin" "$RP/CONTRACTS" "$RP/skills"; }
_rp_green() { # <ID> <what the clean fixture holds>: silent, and the rule really ran
  _rpo="$(_rp "$1")"
  t_eq "$1 is silent on $2" "" "$(printf '%s\n' "$_rpo" | grep -F -e "VIOLATION [$(lid "$1")]" -e "ADVISORY [$(lid "$1")]")"
  t_has "$1 ran on $2" "$_rpo" '1 rules, 0 violations'
}
_rp_red() { t_has "$1 is red on $3" "$(_rp "$1")" "$2"; }  # <ID> <its own message> <the plant>
_rp_sh() { printf '#!/usr/bin/env sh\n# fixture (harbor#588)\n' > "$1"; }

t_section "C4: a tool CI preflights that doctor.sh never probes (harbor#588)"
_rp_fresh; mkdir -p "$RP/.github/workflows"
printf 'for t in git jq zzprobe; do\n' > "$RP/.github/workflows/governance.yml"
printf 'probe git\nprobe jq\nprobe zzprobe\n' > "$RP/bin/doctor.sh"
_rp_green C4 "every preflighted tool probed"
printf 'probe git\nprobe jq\n' > "$RP/bin/doctor.sh"
_rp_red C4 "CI preflights 'zzprobe' but bin/doctor.sh does not probe it" "a preflighted tool doctor.sh omits"
printf 'steps: []\n' > "$RP/.github/workflows/governance.yml"
_rp_red C4 "could not find preflight's tool list" "a workflow with no preflight list: the rule says it is blind"

t_section "D4: a writer emitting a deny entry the harness never consults (harbor#588)"
_rp_fresh; _rp_sh "$RP/bin/writer.sh"; printf 'D=%s\n' "'\"Edit(/etc/x)\"'" >> "$RP/bin/writer.sh"
_rp_green D4 "a writer emitting an Edit(path) entry"
printf 'D=%s\n' "'\"Write(/etc/x)\"'" >> "$RP/bin/writer.sh"
_rp_red D4 "deny entry for a tool whose path rules are never consulted" "a Write(path) deny entry in a writer"

t_section "F10: the .sec0-baseline projection is ONE shape (harbor#588)"
_rp_fresh
for _f10f in sec0-harden floor-deny guard-integrity; do
  _rp_sh "$RP/bin/$_f10f.sh"; printf "jq -S '{perms:.permissions}' s\n" >> "$RP/bin/$_f10f.sh"
done
_rp_green F10 "three copies of one projection"
printf "jq -S '{perms:.permissions, extra:1}' s\n" >> "$RP/bin/floor-deny.sh"
_rp_red F10 "baseline projection differs from the first copy: bin/floor-deny.sh" "a writer pinning a second projection"
rm "$RP/bin/guard-integrity.sh"; _rp_sh "$RP/bin/floor-deny.sh"; printf "jq -S %s s\n" "'{perms:.permissions}'" >> "$RP/bin/floor-deny.sh"
_rp_red F10 "found 2 copy/copies" "a copy gone missing: the floor of three is not met"

t_section "M1: a private marker walk (harbor#588)"
_rp_fresh; _rp_sh "$RP/bin/hook.sh"; printf 'floor_in_repo\n' >> "$RP/bin/hook.sh"
_rp_green M1 "a hook that calls floor_in_repo"
printf '# was: [ -e "$d/.agents" ] (quoted in a comment)\n' >> "$RP/bin/hook.sh"
_rp_green M1 "a comment quoting the old predicate"
printf '[ -e "$d/.agents" ] && exit 0\n' >> "$RP/bin/hook.sh"
_rp_red M1 "private marker walk (call floor_in_repo instead): bin/hook.sh" "an open-coded .agents test"

t_section "N2: a bespoke frontmatter key (harbor#588)"
_rp_fresh; mkdir -p "$RP/skills/x"
printf -- '---\nname: x\ndescription: d\n---\nbody\n' > "$RP/skills/x/SKILL.md"
_rp_green N2 "a skill with harness-defined keys only"
printf -- '---\nname: x\nzzbespoke: 1\n---\nbody\n' > "$RP/skills/x/SKILL.md"
_rp_red N2 'bespoke frontmatter key "zzbespoke" in skills/x/SKILL.md' "an invented frontmatter key"

t_section "P1 / V2: a ported guard cites the pinned upstream SHA (harbor#588)"
_rp_fresh; mkdir -p "$RP/vendor/skills"
printf '# provenance\n\nupstream pin a4e8e74\n' > "$RP/vendor/skills/PROVENANCE.md"
for _p1f in guard-bash guard-egress guard-selfedit annotate-web; do
  _rp_sh "$RP/bin/$_p1f.sh"; printf '# ported from upstream a4e8e74\n' >> "$RP/bin/$_p1f.sh"
done
_rp_green P1 "four ported guards citing the pin"
_rp_green V2 "a provenance pin the guards cite"
_rp_sh "$RP/bin/guard-egress.sh"; printf '# ported from upstream\n' >> "$RP/bin/guard-egress.sh"
_rp_red P1 "no upstream SHA cited: bin/guard-egress.sh" "a ported guard with no SHA"
_rp_red V2 "guard cites a different upstream SHA than PROVENANCE.md (a4e8e74): bin/guard-egress.sh" "a guard that dropped the pin"
printf '# provenance\n\nno pin here\n' > "$RP/vendor/skills/PROVENANCE.md"
_rp_red V2 "PROVENANCE.md declares no upstream SHA" "a PROVENANCE.md with no SHA at all"

t_section "T6: a not-taken list naming a skill we took (harbor#588)"
_rp_fresh
printf '# notes\n\n## What was NOT taken\n\n- `ZzProbe`\n\n## Next\n' > "$RP/NOTES.md"
_rp_green T6 "a not-taken name with no vendored directory"
mkdir -p "$RP/vendor/skills/zz-probe"
_rp_red T6 "NOTES.md lists ZzProbe as not taken, but vendor/skills/zz-probe exists" "a not-taken name that is vendored"

t_section "ROOT1: a root default that disagrees with roots.tsv or ignores PORT_ROOT (harbor#588, #630)"
# Literal ${VAR:-$HOME/...} tokens in this file would be --check's own findings, so @V@ stands for $.
_rp_fresh; mkdir -p "$RP/CONTRACTS"
cp "$SRC/roots.sh" "$SRC/log-lib.sh" "$RP/bin/"
printf 'var\tbase\trel\tbreaks\nESTATE_DIR\tREPOS\testate\tx\n' > "$RP/CONTRACTS/roots.tsv"
printf 'D="@V@{ESTATE_DIR:-@V@{PORT_ROOT:-@V@HOME/port}/estate}"\n' | sed 's/@V@/$/g' > "$RP/bin/site.sh"
( cd "$RP" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm x ) >/dev/null 2>&1
_rp_green ROOT1 "a default equal to its table row"
printf 'D="@V@{ESTATE_DIR:-@V@HOME/port/estate-old}"\n' | sed 's/@V@/$/g' > "$RP/bin/site.sh"
( cd "$RP" && git add -A && git -c user.email=t@t -c user.name=t commit -qm y ) >/dev/null 2>&1
_rp_red ROOT1 "ESTATE_DIR default is" "a site default that drifted from the table"
printf 'D="@V@{ESTATE_DIR:-@V@HOME/port/estate}"\n' | sed 's/@V@/$/g' > "$RP/bin/site.sh"
( cd "$RP" && git add -A && git -c user.email=t@t -c user.name=t commit -qm z ) >/dev/null 2>&1
_rp_red ROOT1 "ignores PORT_ROOT" "a site default spelled flat, which ignores PORT_ROOT (harbor#630)"

t_section "SHIM1: a shim the table names that the live dir lacks (harbor#588)"
_rp_fresh; mkdir -p "$RP/CONTRACTS"
cp "$SRC/shim-install.sh" "$SRC/roots.sh" "$SRC/log-lib.sh" "$SRC/install-lib.sh" "$RP/bin/"
printf 'var\tbase\trel\tbreaks\nHARBOR_LOCAL_BIN\tBOX\t.local/bin\tx\nHARBOR_REPO\tREPOS\tharbor\tx\n' > "$RP/CONTRACTS/roots.tsv"
printf 'name\troot\trel\nzz-probe\tHARBOR_REPO\tbin/zz-probe\n' > "$RP/CONTRACTS/shims.tsv"
_rp_sh "$RP/bin/zz-probe"; chmod 755 "$RP/bin/zz-probe"
_SH0="$HOME"; HOME="$TMP/rp-shim-home"; export HOME; mkdir -p "$HOME/.local/bin" "$HOME/port"
ln -s "$RP" "$HOME/port/harbor"; ln -s "$HOME/port/harbor/bin/zz-probe" "$HOME/.local/bin/zz-probe"
_rp_green SHIM1 "a live dir whose one shim points where the table says"
rm "$HOME/.local/bin/zz-probe"
_rp_red SHIM1 "1 shim(s) missing, mispointed or blocked" "a table shim absent from the live dir"
HOME="$_SH0"; export HOME

t_section "IJ6: a governed repo whose sessions load no memory (harbor#588)"
_rp_fresh; mkdir -p "$RP/priv/inject.d/box"; cp "$SRC/memory-route.sh" "$SRC/log-lib.sh" "$SRC/roots.sh" "$RP/bin/"; cp "$ROOT/CONTRACTS/roots.tsv" "$RP/CONTRACTS/"   # memory-route sources log-lib (harbor#896) and asks roots.sh, which reads its table, for the registry (harbor#1149)
_IJ_H="$TMP/rp-ij6-home"; rm -rf "$_IJ_H"; mkdir -p "$_IJ_H/repo"; _IJ_H="$(cd -P "$_IJ_H" && pwd -P)"
printf 'repo\t~/repo\n' > "$RP/priv/inject.d/box/projects.tsv"
_IJ_S="$_IJ_H/.claude/projects/$(printf '%s' "$_IJ_H" | sed 's|/|-|g')/memory"; mkdir -p "$_IJ_S"; : > "$_IJ_S/note.md"
_IJ_K="$_IJ_H/.claude/projects/$(printf '%s' "$_IJ_H/repo" | sed 's|/|-|g')"; mkdir -p "$_IJ_K"; ln -s "$_IJ_S" "$_IJ_K/memory"
_IJ_OH="$HOME"; _IJ_OC="${CLAUDE_CONFIG_DIR:-}"; _IJ_OP="${HARBOR_SCOPE_PRIVATE:-}"; HOME="$_IJ_H"; CLAUDE_CONFIG_DIR="$_IJ_H/.claude"; HARBOR_SCOPE_PRIVATE="$RP/priv"; export HOME CLAUDE_CONFIG_DIR HARBOR_SCOPE_PRIVATE
t_has "IJ6 sees the routed repo as loading the store" "$(_rp IJ6)" "every governed repo on this box loads the memory store"
rm "$_IJ_K/memory"
_rp_red IJ6 "ADVISORY [memory.repo-reachable] 1 governed repo(s) start with NO memory" "a governed repo with no memory door"
# harbor#896: the ledger hears this once, as check/memory-route from the receipt the run just wrote
: > "$TMP/ij6.rec"; HARBOR_FINDINGS_OUT="$TMP/ij6.rec" HARBOR_ROOT="$RP" sh "$LINT" --only IJ6 >/dev/null 2>&1 || :
t_eq "IJ6 records that it ran, and no subject of its own" "R memory.repo-reachable" "$(tr '\t' ' ' < "$TMP/ij6.rec" | sort -u | tr '\n' ' ' | sed 's/ $//')"
t_eq "the run wrote memory-route's red receipt" red "$(jq -r .status "$CLAUDE_CONFIG_DIR/cache/checks/memory-route.json" 2>/dev/null)"
# D-49: a stood-down tool is never a finding, whichever code it exits (3 is D-29 unchecked, 2 the code it had before); a 1 still is
cp "$RP/bin/memory-route.sh" "$TMP/ij6.real-route"
for _ij_c in 3 2; do
  printf '#!/bin/sh\nexit %s\n' "$_ij_c" > "$RP/bin/memory-route.sh"
  t_eq "IJ6 is silent on a tool that stood down with exit $_ij_c" "" "$(_rp IJ6 | grep -F 'ADVISORY [memory.repo-reachable]')"
  t_has "...and the rule ran" "$(_rp IJ6)" '1 rules, 0 violations'
done
printf '#!/bin/sh\nexit 1\n' > "$RP/bin/memory-route.sh"
t_has "control: the same stub exiting 1 (a blind repo) is the advisory" "$(_rp IJ6)" 'ADVISORY [memory.repo-reachable]'
cp "$TMP/ij6.real-route" "$RP/bin/memory-route.sh"
HOME="$_IJ_OH"; CLAUDE_CONFIG_DIR="$_IJ_OC"; export HOME CLAUDE_CONFIG_DIR
if [ -n "$_IJ_OP" ]; then HARBOR_SCOPE_PRIVATE="$_IJ_OP"; export HARBOR_SCOPE_PRIVATE; else unset HARBOR_SCOPE_PRIVATE; fi

t_section "X5: a deployed prod_guard.py that is not the source's (harbor#919, finding #886)"
# X5 reads outside the repo: the source template, the plugin mirror, and every .agents/hooks copy under
# HOME and PORT_ROOT. A throwaway home holds all four, so the rule's own reads are what is planted.
_X5_H="$TMP/x5-home"; _X5_P="$_X5_H/pi/templates/base/dot_agents/hooks"
_X5_M="$_X5_H/.claude/plugins/marketplaces/project-init/plugins/project-init-workflow/hooks"
mkdir -p "$_X5_P" "$_X5_M" "$_X5_H/port/r1/.agents/hooks"
printf 'def guard():\n    return path.is_symlink()\n' > "$_X5_P/prod_guard.py"
cp "$_X5_P/prod_guard.py" "$_X5_M/prod_guard.py"; cp "$_X5_P/prod_guard.py" "$_X5_H/port/r1/.agents/hooks/prod_guard.py"
_x5() { HOME="$_X5_H" PORT_ROOT="$_X5_H/port" CLAUDE_CONFIG_DIR="$_X5_H/.claude" PROJECT_INIT_SRC="$_X5_H/pi" _rp X5; }
_x5o="$(_x5)"
t_eq "X5 is silent when the mirror and every copy are the source's" "" "$(printf '%s\n' "$_x5o" | grep -F 'ADVISORY [drift.prod-policy-copy]')"
t_has "X5 ran on that home, and counted the copy" "$_x5o" "1 deployed copy/copies checked against the source repo"
printf '# older\n' >> "$_X5_M/prod_guard.py"
t_has "X5 is red on a mirror behind the source" "$(_x5)" "ADVISORY [drift.prod-policy-copy] the marketplace mirror is STALE against the source repo"
cp "$_X5_P/prod_guard.py" "$_X5_M/prod_guard.py"
printf 'def guard():\n    return True\n' > "$_X5_H/port/r1/.agents/hooks/prod_guard.py"
t_has "X5 is red on a copy missing the symlink refusal" "$(_x5)" "ADVISORY [drift.prod-policy-copy] MISSING the PI-903 symlink refusal: port/r1/.agents/hooks/prod_guard.py"
printf 'def guard():\n    return path.is_symlink() and 1\n' > "$_X5_H/port/r1/.agents/hooks/prod_guard.py"
t_has "X5 is red on a copy that has the refusal but differs" "$(_x5)" "ADVISORY [drift.prod-policy-copy] differs from the source repo (has the refusal): port/r1/.agents/hooks/prod_guard.py"

t_done
