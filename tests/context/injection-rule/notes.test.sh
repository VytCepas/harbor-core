#!/usr/bin/env sh
# The notes harbor SHIPS, through the real engine: every row of fixtures/injection-rule/notes.tsv, and every tracked note id must have a FIRE row
# and a SILENT row, or be a named exemption (harbor#173). A throwaway config dir takes the box packs, a throwaway repo the pack under test.
# CORE'S PACKS, AND A PRIVATE LAYER'S WHEN ASKED (harbor#1149). The packs that name a repo or a client live in the private layer's context-rules/,
# with their probe rows in its context-rules/notes.tsv. This suite is hermetic and never looks for that layer by itself; HARBOR_CONTEXT_NOTES_PRIVATE=<layer>
# adds its packs, its box files and its rows to the run, with the same rule: a pack with no FIRE row and no SILENT row fails.
# FIXTURE PACKS (fixtures/injection-rule/packs/<name>/) are never installed and name nothing real. They keep an engine predicate that only the private
# layer's packs use (`cmd-contains`) under a default run, which no CI or pre-push sets a layer for: without one, an edit that broke the
# predicate left every default suite green while five live packs went silent.
PRIV="${HARBOR_CONTEXT_NOTES_PRIVATE:-}"   # a knob from the caller, read before t_init clears it (harbor#773)
. "$(dirname "$0")/../../lib/core.sh"; t_init
ENGINE="$T_ROOT/hooks/injection-rule/injection-rule.sh"; FIX="$T_ROOT/fixtures/injection-rule/notes.tsv"; T="$T_TMP"
# merge-governance and post-merge-state call `gh` against a live PR; their content is
# tests/context/govern-hook/govern-hook.test.sh's, and only their wiring is asserted at the end here.
EXEMPT='merge-governance post-merge-state'
# The private layer: context-rules/{user,<repo>}/ (harbor#1010).
PRR=''; PRB=''
if [ -n "$PRIV" ]; then PRR="$PRIV/context-rules"; PRB=user; fi
tracked_ids() { # the id: key, else the file name (D-43)
  for _f in "$T_ROOT"/context-rules/*/*.md "$T_ROOT"/fixtures/injection-rule/packs/*/*.md ${PRR:+"$PRR"/*/*.md}; do
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
# browser-route-platform-chrome reads the host allowlist from the registered harbor checkout.
_hr="$(awk -F'\t' '$1 == "harbor" { sub(/^~\//, "", $2); print $2; exit }' "$BOXD/projects.tsv")"
mkdir -p "$HOME/$_hr/contracts"; cp "$T_ROOT/contracts/browser-agent-hosts.txt" "$HOME/$_hr/contracts/"

# skill-on-first-use reads the installed skills, the floor's parser beside the pack, and a transcript.
mkdir -p "$T/cfg/skills/agent-routing" "$T/cfg/bin"; cp "$T_ROOT/skills/agent-routing/SKILL.md" "$T/cfg/skills/agent-routing/"
cp "$T_ROOT/bin/library-admission.sh" "$T_ROOT/bin/admission-normalize.awk" "$T/cfg/bin/"; printf '{}\n' > "$T/transcript.jsonl"
# name-note-create ships the mechanism, never a command: a workload pack writes the rows. This neutral one stands in (tests/context/injection-rule/name-note-create.test.sh).
mkdir -p "$T/cfg/name-create.d"; printf 'fixturectl[[:space:]]+create[[:space:]]+\tskill\tUse the form the grammar names.\n' > "$T/cfg/name-create.d/fixture.tsv"
# suggest-tool ships with no rows until the operator names the jobs, so its fire arm reads a neutral table, and the stop tool is a stub.
# Both suggest packs are born shadow, so the rows run them at warn; the shadow arm is its own section below (harbor#1485).
cp "$T_ROOT/fixtures/injection-rule/suggest-tool.tsv" "$BOXD/suggest-tool.tsv"
printf '#!/bin/sh\nexit 0\n' > "$T/cfg/bin/status-suggest.sh"
awk -F'\t' -v OFS='\t' '$3 == "injection" && $12 ~ /^suggest-(tool|start)$/ { $2 = "warn" } { print }' "$T_ROOT/standards/naming/controls.tsv" > "$T/controls-warn.tsv"

make_repo() { # <dir> <pack> <shape>: skills = a HIDDEN skill, visible = one the model already lists
  rm -rf "$1"; mkdir -p "$1/context-rules/repo" "$1/vault" "$1/docs"
  ( cd "$1" && git init -q . && git config user.email t@t && git config user.name t ) >/dev/null 2>&1
  printf 'x\n' > "$1/README.md"; printf 'x\n' > "$1/INDEX.md"; printf 'x\n' > "$1/policy/constitution.md"
  case "$3" in
    skills)  mkdir -p "$1/.claude/skills/demo"
             printf -- '---\nname: demo\ndescription: USE WHEN demo, probe.\ndisable-model-invocation: true\n---\nbody\n' > "$1/.claude/skills/demo/SKILL.md" ;;
    visible) mkdir -p "$1/.claude/skills/shown"
             printf -- '---\nname: shown\ndescription: USE WHEN shown, probe.\n---\nbody\n' > "$1/.claude/skills/shown/SKILL.md" ;;
    naming)  mkdir -p "$1/bin" "$1/standards"   # a repo that carries the naming standard (name-note judges only these)
             cp "$T_ROOT/bin/lint-name.sh" "$T_ROOT/bin/library-log.sh" "$1/bin/"; cp -R "$T_ROOT/standards/naming" "$1/standards/" ;;
  esac
  case "$2" in
    box)  : ;;
    self) mkdir -p "$1/context-rules/platform"; cp -R "$T_ROOT"/context-rules/platform/. "$1/context-rules/platform/" ;;
    *)    if [ -d "$T_ROOT/fixtures/injection-rule/packs/$2" ]; then cp -R "$T_ROOT/fixtures/injection-rule/packs/$2/." "$1/context-rules/repo/"
          else cp -R "$PRR/$2/." "$1/context-rules/repo/"; fi ;;
  esac
  chmod +x "$1"/context-rules/repo/*.sh "$1"/context-rules/*/*.sh 2>/dev/null || true
}
BIG="$(awk 'BEGIN{ while (i++ < 40000) printf "x" }')"
# repo-tier-not-loaded's subject is a SECOND tree: @OTHER@ carries packs, @BARE@ has an empty
# context-rules/repo (a directory check alone would fire on it). gh -R Fixture/Other finds OTHER by origin.
OTHER="$T/other"; make_repo "$OTHER" self plain
BARE="$T/bare";   make_repo "$BARE" box plain
git -C "$OTHER" remote add origin https://github.com/fixture/other.git
# A fixture access book, or access-route-pointer would read the live one under $HOME.
mkdir -p "$T/access"
printf '# example — fixture\n\n    identity: owner@example.com via gcx me\n    account:  owner@example.com | primary | fixture | gcx me\n    via:      api > browser\n    ui-hosts: app.example.invalid, Console.Example.Invalid\n    use:      curl -sS https://api.example.invalid/v1/me. Then read the list.\n' > "$T/access/example.md"
# browser-last-tier (harbor#1507): a browser-only card whose UI host must stay silent, beside the api one above.
printf '# uionly — fixture\n\n    identity: owner@example.com via a browser\n    via:      browser\n    ui-hosts: ui.uionly.invalid\n    use:      https://ui.uionly.invalid/\n' > "$T/access/uionly.md"
printf 'example-project\texample\n' > "$T/access/routes.tsv"
# repo-not-adopted reads PORT_ROOT (here $T): a registry with one governed row, so the fixture repos beside it are unregistered.
mkdir -p "$T/harbor-private"
printf 'id\tpath\tkind\tremote\ttopology\tinteraction\tnote\tdomain\tgoverned\towner\tcovers\nother\tother\tworkload\t-\t-\t-\t-\t-\tyes\t-\t-\n' > "$T/harbor-private/repos.tsv"

t_section "every row of fixtures/injection-rule/notes.tsv${PRIV:+ and of the private layer context-rules/notes.tsv}"
seen_fire=''; seen_silent=''; rows=0
cat "$FIX" > "$T/rows.tsv"
if [ -n "$PRIV" ]; then
  [ -f "$PRR/notes.tsv" ] && cat "$PRR/notes.tsv" >> "$T/rows.tsv" || t_fail "HARBOR_CONTEXT_NOTES_PRIVATE is set but $PRR/notes.tsv is not a file"
fi
while IFS="$(printf '\t')" read -r pack shape id arm label payload; do
  case "$pack" in ''|'#'*) continue ;; esac
  rows=$((rows + 1)); REPO="$T/repo"; make_repo "$REPO" "$pack" "$shape"
  _p="$(printf '%s' "$payload" | sed "s|@REPO@|$REPO|g; s|@OTHER@|$OTHER|g; s|@BARE@|$BARE|g; s|@TRANSCRIPT@|$T/transcript.jsonl|g; s|@CFG@|$T/cfg|g")"
  case "$_p" in *'@BIG@'*) _p="$(printf '%s' "$_p" | sed "s|@BIG@|$BIG|")" ;; esac
  out="$(printf '%s' "$_p" | CLAUDE_CONFIG_DIR="$T/cfg" CLAUDE_PROJECT_DIR="$REPO" PORT_ROOT="$T" \
          HARBOR_SCOPE_REPO="$T_ROOT" ACCESS_DIR="$T/access" HARBOR_SCOPE_MANAGED_SETTINGS="$T/managed/managed-settings.json" \
          HARBOR_CONTEXT_CONTROLS="$T/controls-warn.tsv" /bin/sh "$ENGINE" --explain 2>&1)"
  # A run: pack that returns the decision sentinel logs DECIDE, not FIRE: the `deny` arm the
  # fixture header documents, which this loop read as silent until harbor#843 shipped one.
  if printf '%s' "$out" | grep -q "^FIRE $id\$"; then got=fire
  elif printf '%s' "$out" | grep -q "^DECIDE $id: deny\$"; then got=deny
  else got=silent; fi
  t_eq "$id [$arm] $label" "$arm" "$got"
  [ "$got" = "$arm" ] || printf '        %s\n' "$(printf '%s' "$out" | grep "^skip $id:" | head -1)" >&2
  case "$got:$arm" in fire:fire|deny:deny) seen_fire="$seen_fire $id" ;; silent:silent) seen_silent="$seen_silent $id" ;; esac
done < "$T/rows.tsv"

# A pack whose FIRE or DENY row held went red on its trap: the register's red proof for it (harbor#1422, bin/lint-rule-health.sh).
for _id in $seen_fire; do
  _cid="$(awk -F'\t' -v i="$_id" '$3 == "injection" && $12 == i { print $1; exit }' "$T_ROOT/standards/naming/controls.tsv")"
  [ -z "$_cid" ] || t_red "$_cid"
done

t_section "every tracked note has both arms, or is a named exemption"
for id in $(tracked_ids); do
  case " $EXEMPT " in *" $id "*) continue ;; esac
  t_has "$id has a FIRE (or DENY) row in fixtures/injection-rule/notes.tsv" "$seen_fire " " $id "
  t_has "$id has a SILENT row in fixtures/injection-rule/notes.tsv" "$seen_silent " " $id "
done

t_section "confinement-refused (harbor#1298): the bare phrase fires only while the confinement is installed"
# The rows run with no marker (a macOS privacy refusal is silent); this is the same payload with one.
mkdir -p "$T/managed"; : > "$T/managed/harbor-confinement"
REPO="$T/repo"; make_repo "$REPO" box plain
_cr="$(printf '%s' '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"touch ~/x"},"tool_response":{"stdout":"","stderr":"touch: x: Operation not permitted"}}' \
  | CLAUDE_CONFIG_DIR="$T/cfg" CLAUDE_PROJECT_DIR="$REPO" HARBOR_SCOPE_MANAGED_SETTINGS="$T/managed/managed-settings.json" /bin/sh "$ENGINE" --explain 2>&1)"
t_has "confinement-refused fires on a refused write while the marker is present" "$_cr" "FIRE confinement-refused"
rm -f "$T/managed/harbor-confinement"

t_section "session-title-missing (harbor#1390): the note names the one tool that can write the title"
# A shell redirect into the config dir is refused by admission-bash (bash:redirect-into-cfg); only the Write tool lands it.
REPO="$T/repo"; make_repo "$REPO" box plain
_st="$(printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","session_id":"stm-write","tool_input":{"command":"ls"}}' \
  | CLAUDE_CONFIG_DIR="$T/cfg" CLAUDE_PROJECT_DIR="$REPO" /bin/sh "$ENGINE" 2>&1)"
t_has "session-title-missing tells the model to use the Write tool" "$_st" 'Write tool'

t_section "browser-last-tier (harbor#1507): one note per system per session, and a broken mapping is not \"no route\""
BL='/bin/sh'; BLR="$T/repo"; make_repo "$BLR" box plain
bl() { # <session> <tool> <tool_input json> [access dir] -> the hook's stdout
  printf '{"hook_event_name":"PreToolUse","tool_name":"%s","session_id":"%s","tool_input":%s}' "$2" "$1" "$3" \
    | CLAUDE_CONFIG_DIR="$T/cfg" CLAUDE_PROJECT_DIR="$BLR" PORT_ROOT="$T" HARBOR_SCOPE_REPO="$T_ROOT" ACCESS_DIR="${4:-$T/access}" $BL "$ENGINE" 2>&1
}
_b1="$(bl bl-s1 mcp__harbor_chrome__goto '{"args":["https://app.example.invalid/a"]}')"
t_has "the first open of a mapped host speaks" "$_b1" "context:browser-last-tier"
t_has "...names the tier the card ranks above the browser" "$_b1" 'tier `api`'
t_has "...names the card's first move, cut at its first sentence" "$_b1" 'curl -sS https://api.example.invalid/v1/me.'
t_has "...(the fixture card does carry a second sentence)" "$(cat "$T/access/example.md")" 'Then read the list'
t_hasnt "...and only the first sentence" "$_b1" 'Then read the list'
t_has "...says the browser is the last tier and that it may proceed" "$_b1" 'LAST tier'
t_hasnt "...and is never a denial" "$_b1" 'permissionDecision'
_b2="$(bl bl-s1 mcp__harbor_chrome__tab_new '{"args":["https://console.example.invalid/b"]}')"
t_eq "a second open of the same system's UI (a listed host in capitals, a tab_new) is silent" 0 "$(printf '%s' "$_b2" | grep -c 'context:browser-last-tier')"
_b3="$(bl bl-s2 mcp__harbor_chrome__steps '{"steps":[{"verb":"goto","args":["https://app.example.invalid/c"]},{"verb":"snapshot"}]}')"
t_has "a new session hears it again, through a goto inside steps" "$_b3" "context:browser-last-tier"
_b4="$(bl bl-s3 mcp__harbor_chrome__steps '{"steps":[{"verb":"type","args":["https://app.example.invalid/c"]}]}')"
t_eq "a URL in a step that opens no page is not an open" 0 "$(printf '%s' "$_b4" | grep -c 'context:browser-last-tier')"
_b5="$(bl bl-s4 mcp__harbor_chrome__goto '{"args":["https://ui.uionly.invalid/"]}')"
t_eq "a UI host whose card's top tier IS the browser is silent" 0 "$(printf '%s' "$_b5" | grep -c 'context:browser-last-tier')"
mkdir -p "$T/access-noui"; sed '/ui-hosts:/d' "$T/access/example.md" > "$T/access-noui/example.md"
_b6="$(bl bl-s5 mcp__harbor_chrome__goto '{"args":["https://app.example.invalid/a"]}' "$T/access-noui")"
t_has "a register of cards with no ui-hosts anywhere says the mapping is broken" "$_b6" 'not one `ui-hosts:` line'
_b7="$(bl bl-s5 mcp__harbor_chrome__goto '{"args":["https://app.example.invalid/a"]}' "$T/access-noui")"
t_eq "...once a session" 0 "$(printf '%s' "$_b7" | grep -c 'context:browser-last-tier')"
_b8="$(bl bl-s6 mcp__harbor_chrome__goto '{"args":["https://app.example.invalid/a"]}' "$T/no-such-register")"
t_eq "no register at all is silent, like its siblings" 0 "$(printf '%s' "$_b8" | grep -c 'context:browser-last-tier')"
# Review of harbor#1536: a login in the URL is not the host, a long first move is cut, and old ledgers go.
_b9="$(bl bl-s7 mcp__harbor_chrome__goto '{"args":["https://user:pw@app.example.invalid/a"]}')"
t_has "a URL carrying user:password@ still names its host's route" "$_b9" "context:browser-last-tier"
_x237="$(printf '%237s' '' | tr ' ' 'x')"
mkdir -p "$T/access-long"; sed "s|^\\( *use: *\\).*|\\1${_x237}xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|" "$T/access/example.md" > "$T/access-long/example.md"
_b10="$(bl bl-s8 mcp__harbor_chrome__goto '{"args":["https://app.example.invalid/a"]}' "$T/access-long")"
t_has "a first move past 240 characters is cut with ..." "$_b10" "${_x237}..."
t_has "...(the card's line does run past 240)" "$(cat "$T/access-long/example.md")" "${_x237}x"
t_hasnt "...at 240" "$_b10" "${_x237}x"
mkdir -p "$T/cfg/state/browser-last-tier"; : > "$T/cfg/state/browser-last-tier/ancient.seen"; touch -t 202001010000 "$T/cfg/state/browser-last-tier/ancient.seen"
bl bl-s9 mcp__harbor_chrome__goto '{"args":["https://app.example.invalid/a"]}' >/dev/null
t_eq "a ledger older than 7 days is removed on the way past" gone "$([ -e "$T/cfg/state/browser-last-tier/ancient.seen" ] && echo present || echo gone)"

t_section "the suggest packs are born shadow: recorded, and nothing reaches the person (harbor#1485)"
REPO="$T/repo"; make_repo "$REPO" box plain
_sp='{"hook_event_name":"PreToolUse","tool_name":"Bash","session_id":"sug-shadow","transcript_path":"'"$T/transcript.jsonl"'","tool_input":{"command":"fixturectl report"}}'
_ss='{"hook_event_name":"SessionStart","source":"startup","session_id":"sug-shadow-start"}'
for _a in "$_sp:suggest-tool" "$_ss:suggest-start"; do
  _pl="${_a%:*}"; _pk="${_a##*:}"
  _x="$(printf '%s' "$_pl" | CLAUDE_CONFIG_DIR="$T/cfg" CLAUDE_PROJECT_DIR="$REPO" /bin/sh "$ENGINE" --explain 2>&1)"
  t_has "$_pk under the shipped row is recorded in shadow" "$_x" "SHADOW $_pk: recorded, not spoken"
  _h="$(printf '%s' "$_pl" | CLAUDE_CONFIG_DIR="$T/cfg" CLAUDE_PROJECT_DIR="$REPO" /bin/sh "$ENGINE" 2>&1)"
  t_eq "$_pk under the shipped row: no systemMessage" 0 "$(printf '%s' "$_h" | grep -c systemMessage)"
  t_eq "$_pk under the shipped row: nothing of it in the session" 0 "$(printf '%s' "$_h" | grep -c "context:$_pk")"
done

t_section "the exempt packs: the engine reaches the script, nothing more"
REPO="$T/repo"; make_repo "$REPO" self plain; mkdir -p "$REPO/bin"
printf '#!/usr/bin/env sh\nprintf "REACHED-%%s\\n" "$(cat | tr -d "\\n" | cut -c1-0)x"\n' > "$REPO/bin/govern-hook.sh"
chmod +x "$REPO/bin/govern-hook.sh"
_w="$(printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"gh pr merge 1"}}' \
      | CLAUDE_CONFIG_DIR="$T/cfg" CLAUDE_PROJECT_DIR="$REPO" /bin/sh "$ENGINE" 2>&1)"
t_has "merge-governance: the engine reaches context-rules/platform/merge-note.sh" "$_w" 'REACHED-'
printf '  %s rows, %s tracked note(s), %s exempt (%s)\n' \
  "$rows" "$(tracked_ids | wc -l | tr -d ' ')" "$(printf '%s' "$EXEMPT" | wc -w | tr -d ' ')" "$EXEMPT"
t_done
