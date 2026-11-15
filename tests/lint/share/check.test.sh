#!/usr/bin/env sh
# bin/lint-share.sh and lint.share: a file of a known kind lives in a share its kind allows (D-83, harbor#1274).
# Each case is a throwaway git checkout with its own kinds and layers; kinds here are made up.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
NOPRIV="$T_TMP/no-private"
LS() { HARBOR_SCOPE_ROOT="$1" HARBOR_SCOPE_PRIVATE="${PV:-$NOPRIV}" sh "$T_ROOT/bin/lint-share.sh" "$2" ${3:+"$3" "$4"} 2>&1; }
mk() { # <name> → a checkout: notes/ is personal-only, bin/ core or workload, docs/ core; plus a dev file and an unknown path
  _d="$T_TMP/$1"; mkdir -p "$_d/bin" "$_d/contracts" "$_d/standards/naming" "$_d/notes" "$_d/docs" "$_d/misc" "$_d/devonly"
  printf 'path\tlayer\tnote\nbin/\tcore\t\ncontracts/\tcore\t\nstandards/\tcore\t\nnotes/\tcore\t\ndocs/\tcore\t\nmisc/\tcore\t\ndevonly/\tdev\t\n' > "$_d/contracts/layers.tsv"
  printf '# kinds\nid\tfolder\tpath_pattern\tshare\nnote\tnotes/\tnotes/<x>.md\tpersonal\nscript\tbin/\tbin/<x>.sh\tcore,workload\ndoc\tdocs/\tdocs/<x>.md\tcore\ndev\tdevonly/\tdevonly/<x>\tpersonal\nnone\t-\ta secret store\tpersonal\n' > "$_d/standards/naming/kinds.tsv"
  printf 'x\n' > "$_d/bin/a.sh"; printf 'x\n' > "$_d/docs/d.md"; printf 'x\n' > "$_d/misc/m.md"; printf 'x\n' > "$_d/devonly/v"
  cp "$T_ROOT/contracts/roots.tsv" "$_d/contracts/"
  cp "$T_ROOT/bin/lint-share.sh" "$T_ROOT/bin/scope-layers.sh" "$T_ROOT/bin/scope-roots.sh" "$T_ROOT/bin/library-log.sh" "$_d/bin/"
  ( cd "$_d" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm x ) >/dev/null 2>&1
  printf '%s' "$_d"
}

t_section "a clean checkout: every file of a known kind is in its set"
D="$(mk clean)"
t_eq "no file is outside its set" "0" "$(LS "$D" --count)"
t_has "bin/a.sh is judged core, of kind script" "$(LS "$D" --list)" "bin/a.sh	core	script	core,workload"
t_hasnt "a path with no kind is not judged" "$(LS "$D" --list)" "misc/m.md"
t_hasnt "a dev path has no share and is not judged" "$(LS "$D" --list)" "devonly/v"
t_has "--check says so and exits 0" "$(LS "$D" --check)" "each in a share its kind allows"

t_section "a personal file planted in core is a warning, never a failure"
D="$(mk planted)"; printf 'x\n' > "$D/notes/me.md"
t_eq "one file is outside its set" "1" "$(LS "$D" --count)"
OUT="$(LS "$D" --check)"
t_has "--check names the file, its share and the set" "$OUT" "notes/me.md — share core is not in {personal}"
t_exit "...and exits 0: warn mode" 0 env HARBOR_SCOPE_ROOT="$D" HARBOR_SCOPE_PRIVATE="$NOPRIV" sh "$T_ROOT/bin/lint-share.sh" --check
t_exit "...but --strict exits 1" 1 env HARBOR_SCOPE_ROOT="$D" HARBOR_SCOPE_PRIVATE="$NOPRIV" sh "$T_ROOT/bin/lint-share.sh" --check --strict
t_has "an untracked file counts as well" "$(LS "$D" --list)" "notes/me.md	core	note	personal"

t_section "the share comes from where the file lives"
D="$(mk trees)"; mkdir -p "$T_TMP/tree-w/docs" "$T_TMP/tree-p/docs"; printf 'x\n' > "$T_TMP/tree-w/docs/w.md"; printf 'x\n' > "$T_TMP/tree-p/docs/p.md"
t_has "a docs file in a workload tree is outside docs' core-only set" "$(LS "$D" --list --tree "$T_TMP/tree-w=workload")" "docs/w.md	workload	doc	core"
t_eq "...and counted" "1" "$(LS "$D" --count --tree "$T_TMP/tree-w=workload")"
t_eq "a script in a workload tree is fine" "0" "$(mkdir -p "$T_TMP/tree-s/bin"; printf 'x\n' > "$T_TMP/tree-s/bin/s.sh"; LS "$D" --count --tree "$T_TMP/tree-s=workload")"
PV="$T_TMP/priv"; mkdir -p "$PV/notes" "$PV/hub/notes" "$PV/docs"; printf 'x\n' > "$PV/notes/n.md"; printf 'x\n' > "$PV/hub/notes/h.md"; printf 'x\n' > "$PV/docs/d.md"
t_has "a private-layer file is personal" "$(LS "$D" --list)" "private:notes/n.md	personal	note	personal"
t_has "...and one under hub/ is hub, judged by its path inside it" "$(LS "$D" --list)" "private:hub/notes/h.md	hub	note	personal"
t_eq "so a hub note and a private docs file are the two outside their sets" "2" "$(LS "$D" --count)"
PV=""

t_section "kind lookup"
D="$(mk case)"; printf 'x\n' > "$D/contracts/u.md"; printf 'contract\tcontracts/\tc\tpersonal\n' >> "$D/standards/naming/kinds.tsv"
t_has "a folder is matched case-folded (contracts/ against contracts/)" "$(LS "$D" --list)" "contracts/u.md	core	contract	personal"

t_section "a register that does not parse refuses the run, never counts as clean"
D="$(mk badshare)"; printf 'x\tz/\tz\tprivate\n' >> "$D/standards/naming/kinds.tsv"
t_exit "an unknown share term" 2 env HARBOR_SCOPE_ROOT="$D" HARBOR_SCOPE_PRIVATE="$NOPRIV" sh "$T_ROOT/bin/lint-share.sh" --check
D="$(mk nocol)"; printf '# kinds\nid\tfolder\tpath_pattern\nx\tz/\tz\n' > "$D/standards/naming/kinds.tsv"
t_exit "no share column" 2 env HARBOR_SCOPE_ROOT="$D" HARBOR_SCOPE_PRIVATE="$NOPRIV" sh "$T_ROOT/bin/lint-share.sh" --check
D="$(mk nokinds)"; rm "$D/standards/naming/kinds.tsv"
t_exit "no kinds register" 2 env HARBOR_SCOPE_ROOT="$D" HARBOR_SCOPE_PRIVATE="$NOPRIV" sh "$T_ROOT/bin/lint-share.sh" --check

t_section "lint.share turns each finding into a violation (block since the tree reached zero, harbor#1274)"
D="$(mk lintok)"; cp "$T_ROOT/bin/lint-conventions.sh" "$D/bin/" 2>/dev/null
D="$(mk lintwarn)"; printf 'x\n' > "$D/notes/me.md"
OUT="$(lint1 lint.share "$D")"
t_has "a violation names the file" "$OUT" "VIOLATION [lint.share] notes/me.md"
t_eq "...and counts once" "1" "$(vcount "$OUT")"
D="$(mk lintclean)"
t_eq "a clean tree has no violation" "0" "$(vcount "$(lint1 lint.share "$D")")"
t_done
