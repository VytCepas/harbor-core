# fixture.sh (harbor#1278) — sourced by the robust-*.test.sh suites after t_init and tests/member/e2e/fixture.sh: company packs built on disk, put in the gate's
# hub (make_hub) and in a laptop's hub (HUBDIR) alike, so each pack is judged by both without sharing a verdict.
#   bp <id> <skill> [front-matter line]   a pack of one skill: pack.toml, SKILL.md, extension.json listing every file but pack.toml (the admin's generator)
#   bm <id>                               regenerate extension.json after a change to the pack's files
#   gate_leg <id>      sets G_RC G_OUT: hub-gate.sh over a signed hub holding the pack
#   laptop_leg <id>... sets L_OUT (the skipped line, or empty) and E_OUT: the pack pinned by the signed policy, one real session start
#   rulecut <file> <from> <to> <out>           a copy of a file with one rule cut (a literal replaced); fails the suite if nothing changed
PK="$T_TMP/packs"; mkdir -p "$PK"
GL="$T_TMP/gitleaks-ok"; printf '#!/bin/sh\nexit 0\n' > "$GL"; chmod +x "$GL"   # the scanner is not what these suites judge
export LEAKS_OWN_USER=fixture-own
bm() {
  ( cd "$PK/$1/harbor-pack" && find . -type f ! -name pack.toml | sed 's|^\./||' | LC_ALL=C sort | while IFS= read -r _f; do
      jq -n --arg p "$_f" --arg s "$(e_sha < "$_f")" '{path:$p,sha256:$s}'; done ) |
    jq -s --arg i "$1" '{schema:1,id:$i,version:"1.0.0",harbor_version:">=1",provides:["skill"],files:.}' > "$PK/$1/extension.json"
}
bp() {
  rm -rf "$PK/$1"; _p="$PK/$1/harbor-pack"; mkdir -p "$_p/skills/$2"
  printf 'name = "%s"\nversion = "1.0.0"\nharbor_version = ">=1"\ndescription = "a robustness fixture"\n' "$1" > "$_p/pack.toml"
  printf -- '---\nname: %s\ndescription: A robustness fixture skill.\n%s---\n\n# %s\n' "$2" "${3:+$3
}" "$2" > "$_p/skills/$2/SKILL.md"
  bm "$1"
}
. "$T_ROOT/tests/hub/fixtures/make-hub.sh"   # make_hub, resign: the gate's hub, signed with its own throwaway key
GH="$T_TMP/gate-hub"
gate_leg() { # <id> [bindir]: the gate run from bindir (a mutant copy) when given; gate_edit takes it from $GBIN
  make_hub "$GH"; mkdir -p "$GH/packs"; cp -R "$PK/$1" "$GH/packs/"
  G_OUT="$(HARBOR_HUB_GATE_GITLEAKS="$GL" sh "${2:-$T_ROOT/bin}/hub-gate.sh" "$GH" --core "$T_ROOT" 2>&1)" && G_RC=0 || G_RC=$?
}
gate_edit() { # <jq edit of policy.json> <id>...: the gate's hub with those packs, a policy edited as given and signed again
  make_hub "$GH"; mkdir -p "$GH/packs"; _e="$1"; shift; for _i in "$@"; do cp -R "$PK/$_i" "$GH/packs/"; done
  jq "$_e" "$GH/policy.json" > "$GH/p.new" && mv "$GH/p.new" "$GH/policy.json"; resign "$GH"
  G_OUT="$(HARBOR_HUB_GATE_GITLEAKS="$GL" sh "${GBIN:-$T_ROOT/bin}/hub-gate.sh" "$GH" --core "$T_ROOT" 2>&1)" && G_RC=0 || G_RC=$?
}
BASE=''
pins() { for _i in "$@"; do printf '{id:"%s",commit:"%s"}' "$_i" "$(e_git rev-parse HEAD)"; [ "$_i" = "$_last" ] || printf ','; done; }
laptop_leg() { # <id>...: pins the packs (as copied from $PK) at a new hub commit; the laptop's session start does the rest. L_OUT: why the last one was skipped
  [ -n "$BASE" ] || BASE="$(e_git rev-parse HEAD)"
  e_git reset -q --hard "$BASE"; e_git clean -fdxq
  for _i in "$@"; do cp -R "$PK/$_i" "$HUBDIR/packs/"; _last="$_i"; done
  e_git add -Af; e_git commit -qm "packs $*"
  e_policy ".packs = [$(pins "$@")]"
  e_session start
  # hub.sh keeps one pack.out, which the removal of the pack before overwrites: the reason is read from the same install, run once more, by hand
  L_OUT="$(HOME="$MH" sh "$MB/pack.sh" install "$_last" --hub --apply --live 2>&1 | sed -n "s/.*skipped hub-$_last: //p" | head -n 1)"
}
rulecut() { # <file> <from> <to> <out>: <file> with the literal <from> replaced by <to> wherever it stands, written to <out>; a cut that changes nothing fails the suite
  CUT_FROM="$2" CUT_TO="$3" awk 'BEGIN { RS = "\001"; ORS = ""; f = ENVIRON["CUT_FROM"]; t = ENVIRON["CUT_TO"] }
    { o = ""; while ((i = index($0, f)) > 0) { o = o substr($0, 1, i - 1) t; $0 = substr($0, i + length(f)) } print o $0 }' "$1" > "$4"
  if cmp -s "$1" "$4"; then t_fail "the cut changed nothing in ${1##*/}: $2"; fi
}
