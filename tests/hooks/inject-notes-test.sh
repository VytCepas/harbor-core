#!/usr/bin/env sh
# The notes harbor SHIPS, through the real engine: every row of fixtures/inject/notes.tsv, and every tracked note id must have a FIRE row
# and a SILENT row, or be a named exemption (harbor#173). A throwaway config dir takes the box packs, a throwaway repo the pack under test.
# CORE'S PACKS, AND A PRIVATE LAYER'S WHEN ASKED (harbor#1149). The packs that name a repo or a client live in the private layer's inject.d/,
# with their probe rows in its inject.d/notes.tsv. This suite is hermetic and never looks for that layer by itself; HARBOR_NOTES_PRIVATE=<layer>
# adds its packs, its box files and its rows to the run, with the same rule: a pack with no FIRE row and no SILENT row fails.
# FIXTURE PACKS (fixtures/inject/packs/<name>/) are never installed and name nothing real. They keep an engine predicate that only the private
# layer's packs use (`cmd-contains`) under a default run, which no CI or pre-push sets a layer for: without one, an edit that broke the
# predicate left every default suite green while five live packs went silent.
PRIV="${HARBOR_NOTES_PRIVATE:-}"   # a knob from the caller, read before t_init clears it (harbor#773)
. "$(dirname "$0")/../lib/core.sh"; t_init
ENGINE="$T_ROOT/hooks/injection-rule/injection-rule.sh"; FIX="$T_ROOT/fixtures/inject/notes.tsv"; T="$T_TMP"
# merge-governance and post-merge-state call `gh` against a live PR; their content is
# tests/hooks/govern-hook-test.sh's, and only their wiring is asserted at the end here.
EXEMPT='merge-governance post-merge-state'
# The private layer in either layout for one release (harbor#1010): context-rules/{user,<repo>}/, or inject.d/{box,<repo>}/.
PRR=''; PRB=''
if [ -n "$PRIV" ]; then PRR="$PRIV/context-rules"; PRB=user; [ -d "$PRR" ] || { PRR="$PRIV/inject.d"; PRB=box; }; fi
tracked_ids() { # the id: key, else the file name (D-43)
  for _f in "$T_ROOT"/context-rules/*/*.md "$T_ROOT"/fixtures/inject/packs/*/*.md ${PRR:+"$PRR"/*/*.md}; do
    [ -f "$_f" ] || continue
    awk -v n="${_f##*/}" 'BEGIN { sub(/\.md$/, "", n) } /^---$/{c++; next} c==1 && /^id:/{sub(/^id:[[:space:]]*/,""); print; d=1; exit} END { if (!d) print n }' "$_f"
  done | sort -u
}
BOXD="$T/cfg/context-rules/user"   # the installed box tier
mkdir -p "$BOXD"; cp -R "$T_ROOT"/context-rules/user/. "$BOXD/"; chmod +x "$BOXD"/*.sh
# The registry is the box's own file beside the packs: a fixture here (example names), the private layer's own when one is
# asked for. The project pointer lists only registered projects whose directory exists under $HOME, and $HOME is the
# sandbox, so stand up the directories the registry names.
if [ -n "$PRIV" ]; then
  for _pf in "$PRR/$PRB"/*; do [ -f "$_pf" ] && cp "$_pf" "$BOXD/"; done
else
  printf 'harbor\t~/port/harbor\tthe fixture control plane\ndemo\t~/port/demo\ta fixture project\n' > "$BOXD/projects.tsv"
fi
while IFS="$(printf '\t')" read -r _rn _rp _rest; do
  case "$_rn" in ''|'#'*) continue ;; esac
  case "$_rp" in '~/'*) mkdir -p "$HOME/${_rp#'~/'}" ;; esac
done < "$BOXD/projects.tsv"
# browser-route-harbor-chrome reads the host allowlist from the registered harbor checkout.
_hr="$(awk -F'\t' '$1 == "harbor" { sub(/^~\//, "", $2); print $2; exit }' "$BOXD/projects.tsv")"
mkdir -p "$HOME/$_hr/CONTRACTS"; cp "$T_ROOT/CONTRACTS/browser-agent-hosts.txt" "$HOME/$_hr/CONTRACTS/"

# skill-on-first-use reads the installed skills, the floor's parser beside the pack, and a transcript.
mkdir -p "$T/cfg/skills/agent-routing" "$T/cfg/bin"; cp "$T_ROOT/skills/agent-routing/SKILL.md" "$T/cfg/skills/agent-routing/"
cp "$T_ROOT/bin/guard-lib.sh" "$T_ROOT/bin/floor-normalize.awk" "$T/cfg/bin/"; printf '{}\n' > "$T/transcript.jsonl"

make_repo() { # <dir> <pack> <shape>: skills = a HIDDEN skill, visible = one the model already lists
  rm -rf "$1"; mkdir -p "$1/.claude/inject.d" "$1/vault" "$1/docs"
  ( cd "$1" && git init -q . && git config user.email t@t && git config user.name t ) >/dev/null 2>&1
  printf 'x\n' > "$1/README.md"; printf 'x\n' > "$1/INDEX.md"; printf 'x\n' > "$1/CONSTITUTION.md"
  case "$3" in
    skills)  mkdir -p "$1/.claude/skills/demo"
             printf -- '---\nname: demo\ndescription: USE WHEN demo, probe.\ndisable-model-invocation: true\n---\nbody\n' > "$1/.claude/skills/demo/SKILL.md" ;;
    visible) mkdir -p "$1/.claude/skills/shown"
             printf -- '---\nname: shown\ndescription: USE WHEN shown, probe.\n---\nbody\n' > "$1/.claude/skills/shown/SKILL.md" ;;
    naming)  mkdir -p "$1/bin" "$1/standards"   # a repo that carries the naming standard (name-note judges only these)
             cp "$T_ROOT/bin/lint-name.sh" "$T_ROOT/bin/log-lib.sh" "$1/bin/"; cp -R "$T_ROOT/standards/naming" "$1/standards/" ;;
  esac
  case "$2" in
    box)  : ;;
    self) mkdir -p "$1/context-rules/harbor"; cp -R "$T_ROOT"/context-rules/harbor/. "$1/context-rules/harbor/" ;;
    *)    if [ -d "$T_ROOT/fixtures/inject/packs/$2" ]; then cp -R "$T_ROOT/fixtures/inject/packs/$2/." "$1/.claude/inject.d/"
          else cp -R "$PRR/$2/." "$1/.claude/inject.d/"; fi ;;
  esac
  chmod +x "$1"/.claude/inject.d/*.sh "$1"/context-rules/*/*.sh 2>/dev/null || true
}
BIG="$(awk 'BEGIN{ while (i++ < 40000) printf "x" }')"
# repo-tier-not-loaded's subject is a SECOND tree: @OTHER@ carries packs, @BARE@ has an empty
# .claude/inject.d (a directory check alone would fire on it). gh -R Fixture/Other finds OTHER by origin.
OTHER="$T/other"; make_repo "$OTHER" self plain
BARE="$T/bare";   make_repo "$BARE" box plain
git -C "$OTHER" remote add origin https://github.com/fixture/other.git
# A fixture access book, or access-route-pointer would read the live one under $HOME.
mkdir -p "$T/access"
printf '# example — fixture\n\n    account:  owner@example.com | primary | fixture | gcx me\n' > "$T/access/example.md"
printf 'example-project\texample\n' > "$T/access/routes.tsv"

t_section "every row of fixtures/inject/notes.tsv${PRIV:+ and of the private layer inject.d/notes.tsv}"
seen_fire=''; seen_silent=''; rows=0
cat "$FIX" > "$T/rows.tsv"
if [ -n "$PRIV" ]; then
  [ -f "$PRR/notes.tsv" ] && cat "$PRR/notes.tsv" >> "$T/rows.tsv" || t_fail "HARBOR_NOTES_PRIVATE is set but $PRR/notes.tsv is not a file"
fi
while IFS="$(printf '\t')" read -r pack shape id arm label payload; do
  case "$pack" in ''|'#'*) continue ;; esac
  rows=$((rows + 1)); REPO="$T/repo"; make_repo "$REPO" "$pack" "$shape"
  _p="$(printf '%s' "$payload" | sed "s|@REPO@|$REPO|g; s|@OTHER@|$OTHER|g; s|@BARE@|$BARE|g; s|@TRANSCRIPT@|$T/transcript.jsonl|g")"
  case "$_p" in *'@BIG@'*) _p="$(printf '%s' "$_p" | sed "s|@BIG@|$BIG|")" ;; esac
  out="$(printf '%s' "$_p" | CLAUDE_CONFIG_DIR="$T/cfg" CLAUDE_PROJECT_DIR="$REPO" PORT_ROOT="$T" \
          HARBOR_REPO="$T_ROOT" ACCESS_DIR="$T/access" HARBOR_MANAGED_SETTINGS="$T/managed/managed-settings.json" \
          /bin/sh "$ENGINE" --explain 2>&1)"
  # A run: pack that returns the decision sentinel logs DECIDE, not FIRE: the `deny` arm the
  # fixture header documents, which this loop read as silent until harbor#843 shipped one.
  if printf '%s' "$out" | grep -q "^FIRE $id\$"; then got=fire
  elif printf '%s' "$out" | grep -q "^DECIDE $id: deny\$"; then got=deny
  else got=silent; fi
  t_eq "$id [$arm] $label" "$arm" "$got"
  [ "$got" = "$arm" ] || printf '        %s\n' "$(printf '%s' "$out" | grep "^skip $id:" | head -1)" >&2
  case "$got:$arm" in fire:fire|deny:deny) seen_fire="$seen_fire $id" ;; silent:silent) seen_silent="$seen_silent $id" ;; esac
done < "$T/rows.tsv"

t_section "every tracked note has both arms, or is a named exemption"
for id in $(tracked_ids); do
  case " $EXEMPT " in *" $id "*) continue ;; esac
  t_has "$id has a FIRE (or DENY) row in fixtures/inject/notes.tsv" "$seen_fire " " $id "
  t_has "$id has a SILENT row in fixtures/inject/notes.tsv" "$seen_silent " " $id "
done

t_section "confinement-refused (harbor#1298): the bare phrase fires only while the confinement is installed"
# The rows run with no marker (a macOS privacy refusal is silent); this is the same payload with one.
mkdir -p "$T/managed"; : > "$T/managed/harbor-confinement"
REPO="$T/repo"; make_repo "$REPO" box plain
_cr="$(printf '%s' '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"touch ~/x"},"tool_response":{"stdout":"","stderr":"touch: x: Operation not permitted"}}' \
  | CLAUDE_CONFIG_DIR="$T/cfg" CLAUDE_PROJECT_DIR="$REPO" HARBOR_MANAGED_SETTINGS="$T/managed/managed-settings.json" /bin/sh "$ENGINE" --explain 2>&1)"
t_has "confinement-refused fires on a refused write while the marker is present" "$_cr" "FIRE confinement-refused"
rm -f "$T/managed/harbor-confinement"

t_section "the exempt packs: the engine reaches the script, nothing more"
REPO="$T/repo"; make_repo "$REPO" self plain; mkdir -p "$REPO/bin"
printf '#!/usr/bin/env sh\nprintf "REACHED-%%s\\n" "$(cat | tr -d "\\n" | cut -c1-0)x"\n' > "$REPO/bin/govern-hook.sh"
chmod +x "$REPO/bin/govern-hook.sh"
_w="$(printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"gh pr merge 1"}}' \
      | CLAUDE_CONFIG_DIR="$T/cfg" CLAUDE_PROJECT_DIR="$REPO" /bin/sh "$ENGINE" 2>&1)"
t_has "merge-governance: the engine reaches context-rules/harbor/merge-note.sh" "$_w" 'REACHED-'
printf '  %s rows, %s tracked note(s), %s exempt (%s)\n' \
  "$rows" "$(tracked_ids | wc -l | tr -d ' ')" "$(printf '%s' "$EXEMPT" | wc -w | tr -d ' ')" "$EXEMPT"
t_done
