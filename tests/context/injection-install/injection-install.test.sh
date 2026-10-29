#!/usr/bin/env sh
# context-injection-install.sh wires the engine AND the provenance announce, the announced token is the
# stamped one, --remove leaves nothing dangling, the closing NEXT tells the truth, the matcher
# covers every pack's tools, and an upgrade replaces its entry (harbor#7, #184, #271, #145).
# Mutants of the installer run from a fake tree, and each must reach its own output first.
# Then the install standard (harbor#765, #771): the interface, and what --remove or a rebuild takes out
# lands in backups/inject-install/<TS>/ instead of being deleted.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset CLAUDECODE HARBOR_DEPLOY
unset CLAUDE_CONFIG_DIR  # every call names its target with --dir or --live
TOOL="$T_ROOT/bin/context-injection-install.sh"; T="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"
CFG="$T/cfg"; S="$CFG/settings.json"; mkdir -p "$CFG/bin"; printf '{"permissions":{"deny":[]}}\n' > "$S"
_cmds() { jq -r '.hooks[]?[]?.hooks[]?.command // empty' "$S" 2>/dev/null; }
_ss() { jq -r '.hooks.SessionStart[]?.hooks[]?.command // empty' "$S" 2>/dev/null; }
FR="$T/fakeroot"; mkdir -p "$FR/bin" "$FR/.claude"  # a real tree, or a mutant dies at the diff -r gate
cp "$T_ROOT/bin/deploy-hooks.sh" "$T_ROOT/bin/govern-token.sh" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/deploy-install-lib.sh" "$T_ROOT/bin/scope-roots.sh" "$FR/bin/"
# the engine in its folder with its manifest (D-88), and the rename register its old name is read from
mkdir -p "$FR/hooks" "$FR/standards/naming"; cp -R "$T_ROOT/hooks/injection-rule" "$FR/hooks/"; cp "$T_ROOT/standards/naming/renames.tsv" "$FR/standards/naming/"
mkdir -p "$FR/contracts"; cp "$T_ROOT/contracts/roots.tsv" "$FR/contracts/"   # scope-roots.sh, which resolves the private layer, reads its table
cp -R "$T_ROOT/context-rules" "$FR/context-rules"
mutant() { sed "$1" "$TOOL" > "$FR/bin/$2"; printf '%s' "$FR/bin/$2"; }  # <sed-expr> <name> → path

t_section "status before install: the announce is NOT wired, and there is no salt"
PRE="$(sh "$TOOL" --dir "$CFG" 2>&1)"
t_has "the announce is reported NOT wired" "$PRE" "  note: announce: NOT wired"
t_has "the absent salt is reported" "$PRE" "  WARN: salt: NO SALT"
t_has "...with the command that mints one" "$(printf '%s\n' "$PRE" | grep -A1 'WARN: salt:' | tail -1)" "  fix: sh $T_ROOT/bin/govern-token.sh --init"

t_section "--apply wires the engine and the announce at SessionStart"
sh "$TOOL" --dir "$CFG" --apply >/dev/null 2>&1
t_has "the engine is wired" "$(_ss)" "injection-rule.sh"
t_has "govern-token is wired" "$(_ss)" "govern-token.sh"
t_has "in --announce mode" "$(_ss | grep govern-token)" "--announce"
t_has "with its path quoted" "$(_ss)" "\"$CFG/bin/govern-token.sh\""

t_section "the announced token is the token the engine stamps"
CLAUDE_CONFIG_DIR="$CFG" sh "$T_ROOT/bin/govern-token.sh" --init >/dev/null 2>&1
t_eq "a salt was minted in the fixture" yes "$([ -f "$CFG/.helm-govern-salt" ] && echo yes)"
SID="sid-inject-install-test"
ANN="$(printf '{"session_id":"%s","hook_event_name":"SessionStart"}' "$SID" | CLAUDE_CONFIG_DIR="$CFG" sh "$CFG/bin/govern-token.sh" --announce 2>/dev/null)"
ATOK="$(printf '%s' "$ANN" | jq -r '.hookSpecificOutput.additionalContext // ""' | grep -oE 'token [0-9a-f]{12}' | awk '{print $2}')"
STOK="$(CLAUDE_CONFIG_DIR="$CFG" sh "$CFG/bin/govern-token.sh" --token "$SID" 2>/dev/null)"
t_eq "the announce emits a token" yes "${ATOK:+yes}"
t_eq "the stamp path yields a token" yes "${STOK:+yes}"
t_eq "announced token = stamped token" "$STOK" "$ATOK"
t_eq "the payload is a SessionStart envelope" SessionStart "$(printf '%s' "$ANN" | jq -r '.hookSpecificOutput.hookEventName // ""')"
t_eq "the payload is valid JSON" 0 "$(printf '%s' "$ANN" | jq -e . >/dev/null 2>&1; echo $?)"
t_has "the announcement cites the rule" "$ANN" "§4"

t_section "with the salt gone the announce is silent, not an empty token"
mv "$CFG/.helm-govern-salt" "$CFG/salt.bak"
t_eq "no salt: no output" "" "$(printf '{"session_id":"%s"}' "$SID" | CLAUDE_CONFIG_DIR="$CFG" sh "$CFG/bin/govern-token.sh" --announce 2>/dev/null)"
mv "$CFG/salt.bak" "$CFG/.helm-govern-salt"

t_section "status after install: wired, with the salt present"
POST="$(sh "$TOOL" --dir "$CFG" 2>&1)"
t_has "the announce is reported wired" "$POST" "  ok: announce: wired"
t_has "the salt is reported present" "$POST" "  ok: salt: present"

t_section "--remove leaves no hook pointing at a file it deleted"
sh "$TOOL" --dir "$CFG" --remove --apply > "$T/rm.out" 2>&1
t_eq "govern-token hooks left" 0 "$(_cmds | grep -c 'govern-token\.sh')"
t_eq "engine hooks left" 0 "$(_cmds | grep -c 'injection-rule\.sh')"
dangling() { _cmds | sed -E 's/^\/bin\/sh "([^"]+)".*/\1/' | while IFS= read -r p; do
  case "$p" in "$CFG"/*) [ -f "$p" ] || echo "$p" ;; esac; done; }
t_eq "hooks naming a missing file under the config dir" "" "$(dangling)"
RMB="$(dirname "$(tail -1 "$T/rm.out" | sed -n 's/^log: //p')")"
t_eq "--remove moved the packs into its backup, never deleted them" yes "$([ -d "$RMB/context-rules/user" ] && [ -n "$(ls "$RMB/context-rules/user")" ] && echo yes || echo no)"
t_eq "...and the engine" yes "$([ -f "$RMB/bin/injection-rule.sh" ] && [ -f "$RMB/bin/govern-token.sh" ] && echo yes || echo no)"
t_eq "...leaving neither in the config dir" "no no" "$([ -e "$CFG/context-rules/user" ] && echo yes || echo no) $([ -e "$CFG/bin/injection-rule.sh" ] && echo yes || echo no)"
t_eq "...with the pre-run settings.json beside them" 2 "$(jq '[.hooks.SessionStart[]?.hooks[]?.command | select(contains("injection-rule.sh") or contains("govern-token.sh"))] | length' "$RMB/settings.json")"

t_section "idempotent: a second --apply adds no duplicate"
sh "$TOOL" --dir "$CFG" --apply >/dev/null 2>&1; N1="$(_ss | grep -c 'govern-token\.sh')"
sh "$TOOL" --dir "$CFG" --apply > "$T/re.out" 2>&1; N2="$(_ss | grep -c 'govern-token\.sh')"
t_eq "announce hook count after one and two applies" "1 1" "$N1 $N2"
REB="$(dirname "$(tail -1 "$T/re.out" | sed -n 's/^log: //p')")"
t_eq "a rebuild moves the previous box tier into its backup" "$(ls "$T_ROOT/context-rules/user" | sort)" "$(ls "$REB/context-rules/user" 2>/dev/null | sort)"

t_section "mutant: the section-2 wiring assertions can fail"
M8="$(mutant '/merge_hook \/dev\/stdin SessionStart "" "\$ANNOUNCE_CMD"/d' mut-announce.sh)"
t_eq "the mutant's sed applied: no announce merge is left" 0 "$(grep -c 'ANNOUNCE_CMD")"$' "$M8")"
CFG2="$T/cfg2"; mkdir -p "$CFG2/bin"; printf '{"permissions":{"deny":[]}}\n' > "$CFG2/settings.json"
t_has "the mutant reached its own output" "$(sh "$M8" --dir "$CFG2" --apply 2>&1)" "backup:"
t_eq "the mutant wired no announce" 0 "$(jq -r '.hooks.SessionStart[]?.hooks[]?.command // empty' "$CFG2/settings.json" | grep -c 'govern-token\.sh')"

t_section "the closing NEXT describes what happened (live branch, fake HOME)"
FH="$T/fh"; mkdir -p "$FH/.claude/bin"
printf '{"permissions":{"deny":[]}}\n' > "$FH/.claude/settings.json"; printf 'be helpful\n' > "$FH/.claude/CLAUDE.md"
for f in pin-instructions.sh guard-lib.sh floor-normalize.awk library-log.sh deploy-install-lib.sh; do cp "$T_ROOT/bin/$f" "$FH/.claude/bin/"; done
NAG='  note: next: sh '"$FH"'/.claude/bin/pin-instructions.sh --apply --live'  # named once (lint F9): the negative below keys on it
pin() { HOME="$FH" sh "$FH/.claude/bin/pin-instructions.sh" --apply --live >/dev/null 2>&1; }
inst() { HOME="$FH" sh "${1:-$TOOL}" --live --apply 2>&1; }
O="$(inst)"
t_has "unpinned: told to pin" "$O" "not pinned"
t_has "unpinned: closes with the re-pin" "$O" "$NAG"
pin; O="$(inst)"
t_has "pinned and clean: reports unchanged" "$O" "unchanged against the pin"
t_hasnt "pinned and clean: no re-pin nag" "$O" "$NAG"
printf 'and one more instruction\n' >> "$FH/.claude/CLAUDE.md"; O="$(inst)"
t_has "drifted: reports the drift" "$O" "DIFFER from the pin"
t_has "drifted: offers the review step, as its fix" "$O" "  fix: sh $FH/.claude/bin/pin-instructions.sh --check --live"
t_has "drifted: closes with the re-pin" "$O" "$NAG"
O="$(HARBOR_DEPLOY=1 inst)"
t_has "under deploy: the drift is still reported" "$O" "DIFFER from the pin"
t_hasnt "under deploy: the re-pin is deploy's step and is not printed (harbor#285)" "$O" "$NAG"
M9="$(mutant 's|elif il_run sh "$DIR/bin/pin-instructions.sh" --check >/dev/null 2>&1; then|elif false; then|' mut-nag.sh)"
t_has "mutant: the sed applied" "$(cat "$M9")" "elif false; then"
pin; O="$(inst "$M9")"
t_has "mutant: reached its own output" "$O" "backup:"
t_has "mutant: a clean config nags (the clean arm is keyed on the check)" "$O" "DIFFER from the pin"

t_section "the wired matcher covers every tool the packs declare (harbor#184)"
rm -rf "$CFG"; mkdir -p "$CFG"; printf '{"permissions":{"allow":[],"deny":[]}}\n' > "$S"
sh "$TOOL" --dir "$CFG" --apply >/dev/null 2>&1
M="$(jq -r '[.hooks.PostToolUse[]? | select((.hooks[]?.command // "") | contains("injection-rule.sh")) | .matcher] | first // ""' "$S")"
t_eq "a PostToolUse matcher was written for the engine" yes "${M:+yes}"
fm() { awk -v k="$2" 'NR==1 && $0 !~ /^---/ {exit} NR>1 && /^---/ {exit} $0 ~ "^"k":" {sub("^"k":[[:space:]]*",""); print; exit}' "$1"; }
uncovered() { for f in "$T_ROOT"/context-rules/*/*.md; do
  [ -f "$f" ] && [ "$(fm "$f" event)" = PostToolUse ] || continue
  tl="$(fm "$f" tool)"; printf '%s\n' "${tl:-.*}" | tr '|' '\n' | while IFS= read -r alt; do  # a pattern is probed by an instance
    [ -n "$alt" ] && ! printf '%s\n' "$alt" | sed 's/\.\*/xyz/g' | grep -qE "^($M)$" && printf '%s(%s) ' "$alt" "${f##*/}"; done; done; }
t_eq "pack tools outside the matcher" "" "$(uncovered)"
t_eq "browser_batch is inside the matcher" 1 "$(printf 'mcp__claude-in-chrome__browser_batch\n' | grep -cE "^($M)$")"

t_section "an upgrade replaces the engine's entry, and keeps foreign hooks (harbor#271)"
U="$T/upgrade"; STALE='Read|Bash|Grep|WebFetch'
seed() { rm -rf "$U"; mkdir -p "$U/bin"  # /opt/my-inject-hook.sh CONTAINS our basename (PR #276)
  jq -n --arg stale "$STALE" --arg eng "/bin/sh \"$U/bin/inject-hook.sh\"" '{permissions:{allow:[],deny:[]},
    hooks:{PostToolUse:[{matcher:$stale, hooks:[{type:"command", command:$eng, timeout:10},
      {type:"command", command:"/bin/sh /somebody/else.sh", timeout:10}, {type:"command", command:"/bin/sh /opt/my-inject-hook.sh", timeout:10}]},
      {matcher:"Write", hooks:[{type:"command", command:"/bin/sh /third/party.sh", timeout:10}]}]}}' > "$U/settings.json"; }
# the engine under either name: the seed is a box as it stands before harbor#1272, its entry still inject-hook.sh
ours() { jq -r --arg p "$U/bin/injection-rule.sh" --arg o "$U/bin/inject-hook.sh" "[.hooks.PostToolUse[]? | select([.hooks[]?.command // \"\"] | map(contains(\$p) or contains(\$o)) | index(true) != null) | $1]" "$U/settings.json"; }
has_cmd() { jq -r --arg c "$1" '[.hooks.PostToolUse[]?.hooks[]?.command] | index($c) != null' "$U/settings.json"; }
seed
t_eq "the fixture seeds one engine entry, under the old name" 1 "$(ours 1 | jq length)"
sh "$TOOL" --dir "$U" --apply >/dev/null 2>&1
t_eq "after the upgrade, one engine entry" 1 "$(ours 1 | jq length)"
t_eq "...under the new name, and none under the old" "0 1" "$(jq -r '[.hooks[]?[]?.hooks[]?.command] | "\(map(select(contains("inject-hook.sh") and (contains("/opt/") | not))) | length) \(map(select(contains("injection-rule.sh"))) | length > 0 | if . then 1 else 0 end)"' "$U/settings.json")"
M11="$(ours .matcher | jq -r 'first // ""')"
t_eq "the surviving entry has a derived matcher" yes "$([ -n "$M11" ] && [ "$M11" != "$STALE" ] && echo yes)"
t_eq "a foreign hook sharing the stale entry survives" true "$(has_cmd "/bin/sh /somebody/else.sh")"
t_eq "a third-party entry survives" 1 "$(jq '[.hooks.PostToolUse[]? | select(.matcher == "Write")] | length' "$U/settings.json")"
t_eq "a foreign hook whose name contains ours survives" true "$(has_cmd "/bin/sh /opt/my-inject-hook.sh")"

t_section "mutant: the upgrade arm goes red without the render"
M11B="$(mutant 's/^NEW="\$(hooks_run --settings /NEWX="$(hooks_run --settings /' mut-render.sh)"
t_eq "the mutant no longer takes the rendered settings" 0 "$(grep -c '^NEW="$(hooks_run --settings ' "$M11B")"
seed; sh "$M11B" --dir "$U" --apply >/dev/null 2>&1
t_eq "the mutant leaves the old-name entry wired" true "$(has_cmd "/bin/sh \"$U/bin/inject-hook.sh\"")"

t_section "the interface: no positional target, the live dir only by --live, and no env target"
IF="$T/iface"; mkdir -p "$IF"; printf '{"permissions":{"deny":[]}}\n' > "$IF/settings.json"
t_exit "a positional target is a usage error" 2 sh "$TOOL" "$IF" --apply
t_exit "an unknown flag is a usage error" 2 sh "$TOOL" --dir "$IF" --bogus
t_exit "--dir onto the live dir is refused" 1 env HOME="$FH" sh "$TOOL" --apply --dir "$FH/.claude/"
t_exit "CLAUDE_CONFIG_DIR naming another dir is a usage error" 2 env CLAUDE_CONFIG_DIR="$CFG" sh "$TOOL" --dir "$IF"
t_exit "--projects without --live is refused on --apply" 1 sh "$TOOL" --dir "$IF" --apply --projects
t_eq "...and wrote nothing" '{"permissions":{"deny":[]}}' "$(cat "$IF/settings.json")"
t_exit "...and its dry run predicts it (the dry-run exit rule)" 1 sh "$TOOL" --dir "$IF" --projects
t_has "...with the --live command as the fix" "$(sh "$TOOL" --dir "$IF" --projects 2>&1)" "  fix: sh $TOOL --apply --live --projects"
t_exit "a plain dry run exits 0" 0 sh "$TOOL" --dir "$IF"
t_has "...and names the apply command" "$(sh "$TOOL" --dir "$IF" 2>&1)" "  note: next: sh $TOOL --apply --dir '$IF'"
t_section "the install manifest (install standard §3): the engine and the box tier are rows; --remove drops them"
MC="$T/mf"; mkdir -p "$MC/bin"; printf '{"permissions":{"deny":[]}}\n' > "$MC/settings.json"
sh "$TOOL" --dir "$MC" >/dev/null 2>&1
t_eq "a dry run writes no manifest" no "$([ -e "$MC/.harbor-manifest" ] && echo yes || echo no)"
sh "$TOOL" --dir "$MC" --apply >/dev/null 2>&1
t_eq "the engine is a row: its bytes, 100755, the installer and this checkout's commit" \
  "$(git hash-object "$MC/bin/injection-rule.sh") 100755 bin/injection-rule.sh inject-install $(git -C "$T_ROOT" rev-parse HEAD)" \
  "$(grep ' bin/injection-rule.sh ' "$MC/.harbor-manifest")"
t_eq "every box pack is a row" "$(cd "$MC" && find context-rules/user -type f | wc -l | tr -d ' ')" "$(grep -c ' context-rules/user/' "$MC/.harbor-manifest")"
sh "$TOOL" --dir "$MC" --apply --remove >/dev/null 2>&1
t_eq "--remove drops the rows of everything it moved into the backup" 0 "$(grep -cE ' (context-rules/user/|inject\.d/|bin/injection-rule\.sh |bin/govern-token\.sh )' "$MC/.harbor-manifest")"

# ── the private layer (harbor#1149) ─────────────────────────────────────────────────────────────────────────────
# Core ships no pack that names a client or a repo of one: they live in <private>/context-rules (or the old inject.d), read through scope-roots.sh. Every arm below names
# its layer with HARBOR_SCOPE_PRIVATE: t_init unsets it, so the arms above ran on core alone, the "no layer" case, asserted again here.
t_section "core ships no other repo's rule folder: context-rules/ holds the box tier and harbor's own, nothing else"
t_eq "the directories under core's context-rules" "$T_ROOT/context-rules/harbor $T_ROOT/context-rules/user" "$(find "$T_ROOT/context-rules" -mindepth 1 -maxdepth 1 -type d | sort | tr '\n' ' ' | sed 's/ $//')"
t_eq "no registry in core's box tier" "no" "$([ -e "$T_ROOT/context-rules/user/projects.tsv" ] && echo yes || echo no)"
t_eq "no old inject.d/ left in core (harbor#1010)" "no no" "$([ -e "$T_ROOT/inject.d" ] && echo yes || echo no) $([ -e "$T_ROOT/.claude/inject.d" ] && echo yes || echo no)"

t_section "no private layer: the box tier is core's alone, the status says so, --projects has nothing to seed"
t_has "status: core's box tier alone" "$(HARBOR_SCOPE_PRIVATE="$T/no-such-layer" sh "$TOOL" --dir "$CFG" 2>&1)" "private packs: none"
t_hasnt "core alone: no private tool in the matcher" "$M" "ZzPrivateTool"

PL="$T/privlayer"; mkdir -p "$PL/inject.d/box" "$PL/inject.d/demo" "$PL/inject.d/other"
printf '# name\tpath\tcovers\ndemo\t~/port/demo\ta fixture project\n' > "$PL/inject.d/box/projects.tsv"
printf -- '---\nid: private-box-note\nevent: SessionStart\nwhen: always\n---\n\nbody\n' > "$PL/inject.d/box/80-private-box-note.md"
printf -- '---\nid: demo-zz\nevent: PreToolUse\ntool: ZzPrivateTool\nwhen: always\n---\n\nbody\n' > "$PL/inject.d/demo/10-demo-zz.md"
printf -- '---\nid: other-note\nevent: SessionStart\nwhen: always\n---\n\nbody\n' > "$PL/inject.d/other/10-other.md"
: > "$PL/inject.d/box/.DS_Store"
pmatch() { jq -r '[.hooks.PreToolUse[]? | select((.hooks[]?.command // "") | contains("injection-rule.sh")) | .matcher] | first // ""' "$1/settings.json"; }

t_section "a private layer's box tier installs with core's, and its repo packs' tools reach the matcher"
PX="$T/px"; mkdir -p "$PX/bin"; printf '{"permissions":{"allow":[],"deny":[]}}\n' > "$PX/settings.json"
PXD="$(HARBOR_SCOPE_PRIVATE="$PL" sh "$TOOL" --dir "$PX" 2>&1)"
t_has "the dry run says what it would add" "$PXD" "and the private layer's box tier (2 file(s))"
PXO="$(HARBOR_SCOPE_PRIVATE="$PL" sh "$TOOL" --dir "$PX" --apply 2>&1)"
t_has "the run reports the private files it installed" "$PXO" "and 2 private file(s)"
t_eq "the install holds core's box tier plus the two private files, no stray .DS_Store" \
  "$( { ls "$T_ROOT/context-rules/user"; printf '80-private-box-note.md\nprojects.tsv\n'; } | sort | tr '\n' ' ')" "$(ls "$PX/context-rules/user" | sort | tr '\n' ' ')"
t_eq "the registry arrives byte for byte" "" "$(diff "$PL/inject.d/box/projects.tsv" "$PX/context-rules/user/projects.tsv" 2>&1)"
t_eq "the private box pack arrives byte for byte" "" "$(diff "$PL/inject.d/box/80-private-box-note.md" "$PX/context-rules/user/80-private-box-note.md" 2>&1)"
t_eq "a hidden file in the private box tier is not installed" "no" "$([ -e "$PX/context-rules/user/.DS_Store" ] && echo yes || echo no)"
t_has "a private repo pack's tool is in the wired matcher" "$(pmatch "$PX")" "ZzPrivateTool"
PXS="$(HARBOR_SCOPE_PRIVATE="$PL" sh "$TOOL" --dir "$PX" 2>&1)"
t_has "status: the private box files are counted" "$PXS" "private packs: 2 box file(s) from $PL/inject.d"
t_has "status: a repo pack folder is named with its project's state" "$PXS" "repo pack demo: port/demo no such project"
t_has "status: a folder with no registry row is named too" "$PXS" "repo pack other:  no such project"
t_eq "every private file is a manifest row" 2 "$(grep -cE ' context-rules/user/(80-private-box-note\.md|projects\.tsv) ' "$PX/.harbor-manifest")"

t_section "--projects seeds a project from the private layer's folder, backs up what it overwrites, skips a folder the registry does not name"
mkph() { rm -rf "$T/ph"; PH="$T/ph"; mkdir -p "$PH/.claude/bin" "$PH/port/demo/context-rules/demo" "$PH/port/other"
  printf '{"permissions":{"deny":[]}}\n' > "$PH/.claude/settings.json"; printf 'be helpful\n' > "$PH/.claude/CLAUDE.md"
  for f in pin-instructions.sh guard-lib.sh floor-normalize.awk library-log.sh deploy-install-lib.sh; do cp "$T_ROOT/bin/$f" "$PH/.claude/bin/"; done
  printf 'old\n' > "$PH/port/demo/context-rules/demo/10-demo-zz.md"; }   # demo has the pack, edited in place; other is on disk, in no registry row
mkph
PJ="$(HOME="$PH" HARBOR_SCOPE_PRIVATE="$PL" sh "$TOOL" --live --apply --projects 2>&1)"
t_has "the registered project is seeded" "$PJ" "demo: seeded port/demo/context-rules/demo"
t_eq "...with the layer's pack, byte for byte" "" "$(diff -r "$PL/inject.d/demo" "$PH/port/demo/context-rules/demo" 2>&1)"
t_eq "...and what it overwrote is in the run's backup" old "$(cat "$(find "$PH/.claude/backups/inject-install" -path '*/projects/demo/demo/10-demo-zz.md' | head -1)" 2>/dev/null)"
t_eq "...and nothing was seeded into the old .claude/inject.d (harbor#1010)" no "$([ -e "$PH/port/demo/.claude/inject.d" ] && echo yes || echo no)"
t_has "a folder the registry does not name is skipped, with the reason" "$PJ" "other: no such project in the private projects.tsv"
t_eq "...and wrote nothing into the project of that name" "no" "$([ -e "$PH/port/other/.claude" ] && echo yes || echo no)"
mkph
PN="$(HOME="$PH" HARBOR_SCOPE_PRIVATE="$T/no-such-layer" sh "$TOOL" --live --apply --projects 2>&1)"
t_has "no private layer: --projects is skipped and says why" "$PN" "core ships no repo packs"
t_eq "...and the project keeps what it had" old "$(cat "$PH/port/demo/context-rules/demo/10-demo-zz.md")"

t_section "harbor#1010: a project seeded before the move, in .claude/inject.d, is named and left in place"
mkph; mkdir -p "$PH/port/demo/.claude/inject.d"; cp "$PL/inject.d/demo/10-demo-zz.md" "$PH/port/demo/.claude/inject.d/"; rm -rf "$PH/port/demo/context-rules"
t_has "status: current in the old place only asks for a re-seed" "$(HOME="$PH" HARBOR_SCOPE_PRIVATE="$PL" sh "$TOOL" --live --projects 2>&1)" \
  "repo pack demo: port/demo current in the old .claude/inject.d only: re-seed"
PJO="$(HOME="$PH" HARBOR_SCOPE_PRIVATE="$PL" sh "$TOOL" --live --apply --projects 2>&1)"
t_has "the re-seed lands in context-rules/demo" "$PJO" "demo: seeded port/demo/context-rules/demo"
t_has "...says the old folder is still there and still read" "$PJO" "port/demo/.claude/inject.d is still there and still read until rename-0031's date"
t_eq "...and leaves it, byte for byte (it may hold the repo's own rules)" "" "$(diff "$PL/inject.d/demo/10-demo-zz.md" "$PH/port/demo/.claude/inject.d/10-demo-zz.md" 2>&1)"
t_has "status: current" "$(HOME="$PH" HARBOR_SCOPE_PRIVATE="$PL" sh "$TOOL" --live --projects 2>&1)" "repo pack demo: port/demo current"

t_section "the private repo folders are data too: --projects refuses a script, a link, a subfolder or another file, and writes nothing"
# The box tier is data (below); a repo folder is seeded into a registered repository, where the engine runs a pack's
# `run:` script on every tool call, so the same rule has to hold on this path or private code runs in someone else's tree.
mklayer() { rm -rf "$T/lay-$1"; cp -R "$PL" "$T/lay-$1"; printf '%s' "$T/lay-$1"; }
prefusal() { # <label> <layer> <expect> → the dry run exits 1, --apply exits 1, the project and the config dir are untouched
  mkph
  t_exit "$1: the dry run predicts the refusal" 1 env HOME="$PH" HARBOR_SCOPE_PRIVATE="$2" sh "$TOOL" --live --projects
  _po="$(HOME="$PH" HARBOR_SCOPE_PRIVATE="$2" sh "$TOOL" --live --apply --projects 2>&1)"; _pc=$?
  t_eq "$1: --apply exits 1" 1 "$_pc"
  t_has "$1: it says why" "$_po" "$3"
  t_eq "$1: the project keeps what it had, and nothing else" "10-demo-zz.md old" "$(ls -A "$PH/port/demo/context-rules/demo" | tr '\n' ' ')$(cat "$PH/port/demo/context-rules/demo/10-demo-zz.md")"
  t_eq "$1: the config dir got no pack tier and no engine" "no no" "$([ -e "$PH/.claude/context-rules/user" ] && echo yes || echo no) $([ -e "$PH/.claude/bin/injection-rule.sh" ] && echo yes || echo no)"; }
LP="$(mklayer script)"; printf '#!/bin/sh\necho hi\n' > "$LP/inject.d/demo/90-evil.sh"
printf -- '---\nid: evil\nevent: PreToolUse\ntool: Bash\nwhen: always\nrun: 90-evil.sh\n---\n' > "$LP/inject.d/demo/20-evil.md"
prefusal script "$LP" "only .md packs are seeded into a repository"
LP="$(mklayer data)"; printf 'x\n' > "$LP/inject.d/demo/notes.txt"
prefusal "another file" "$LP" "only .md packs are seeded into a repository"
LP="$(mklayer link)"; ln -s /etc/hosts "$LP/inject.d/demo/20-link.md"
prefusal link "$LP" "which is not a plain file"
LP="$(mklayer subdir)"; mkdir "$LP/inject.d/demo/sub"
prefusal subfolder "$LP" "which is not a plain file"
LP="$(mklayer folderlink)"; mv "$LP/inject.d/demo" "$T/lay-folderlink-target"; ln -s "$T/lay-folderlink-target" "$LP/inject.d/demo"
prefusal "folder link" "$LP" "is a link, not a directory"
LP="$(mklayer ds)"; : > "$LP/inject.d/demo/.DS_Store"
mkph; PDS="$(HOME="$PH" HARBOR_SCOPE_PRIVATE="$LP" sh "$TOOL" --live --apply --projects 2>&1)"; _pc=$?
t_eq "a folder holding only .md packs and a .DS_Store seeds, exit 0" 0 "$_pc"
t_has "...and says so" "$PDS" "demo: seeded port/demo/context-rules/demo"
t_eq "...the pack arrives byte for byte, the .DS_Store stays behind" "10-demo-zz.md |" "$(ls -A "$PH/port/demo/context-rules/demo" | tr '\n' ' ')|$(diff "$LP/inject.d/demo/10-demo-zz.md" "$PH/port/demo/context-rules/demo/10-demo-zz.md" 2>&1)"
t_has "...and the status calls the project current, a .DS_Store notwithstanding" "$PDS" "repo pack demo: port/demo current"
LP="$(mklayer noseed)"; printf '#!/bin/sh\necho hi\n' > "$LP/inject.d/demo/90-evil.sh"
t_exit "a script in a repo folder does not stop a run that seeds nothing (no --projects)" 0 env HOME="$PH" HARBOR_SCOPE_PRIVATE="$LP" sh "$TOOL" --live

t_section "the private box tier is data: a script, a link or a name core already ships is refused, and nothing is written"
refusal() { # <label> <layer> <expect> → one refusal arm: dry run exits 1, --apply exits 1 and leaves the config untouched
  _rd="$T/ref-$1"; rm -rf "$_rd"; mkdir -p "$_rd/bin"; printf '{"permissions":{"allow":[],"deny":[]}}\n' > "$_rd/settings.json"
  t_exit "$1: the dry run predicts the refusal" 1 env HARBOR_SCOPE_PRIVATE="$2" sh "$TOOL" --dir "$_rd"
  _ro="$(HARBOR_SCOPE_PRIVATE="$2" sh "$TOOL" --dir "$_rd" --apply 2>&1)"; _rc=$?
  t_eq "$1: --apply exits 1" 1 "$_rc"
  t_has "$1: it says why" "$_ro" "$3"
  t_eq "$1: nothing was installed" "no no" "$([ -e "$_rd/context-rules/user" ] && echo yes || echo no) $([ -e "$_rd/bin/injection-rule.sh" ] && echo yes || echo no)"
  t_eq "$1: settings.json is untouched" '{"permissions":{"allow":[],"deny":[]}}' "$(cat "$_rd/settings.json")"; }
LS="$T/layer-script"; mkdir -p "$LS/inject.d/box"; printf '#!/bin/sh\necho hi\n' > "$LS/inject.d/box/90-evil.sh"
refusal script "$LS" "only .md packs and projects.tsv are installed from the private layer"
LL="$T/layer-link"; mkdir -p "$LL/inject.d/box"; ln -s /etc/hosts "$LL/inject.d/box/90-link.md"
refusal link "$LL" "is not a plain file"
CORE1="$(ls "$T_ROOT/context-rules/user" | grep '\.md$' | head -1)"
LC="$T/layer-collide"; mkdir -p "$LC/inject.d/box"; printf 'shadow\n' > "$LC/inject.d/box/$CORE1"
refusal collide "$LC" "a private file never replaces a shipped pack"
t_exit "a PORT_ROOT that cannot name a layer is a refusal, not a silent core-alone install" 1 \
  env -u HARBOR_SCOPE_PRIVATE PORT_ROOT="$(printf 'a\tb')" sh "$TOOL" --dir "$T/ref-script" 

t_section "mutants: each private-layer guard goes red when it is cut"
# (a) the collision guard
MC1="$(mutant 's#if \[ -e "\$COREBOX/\$_pn" \]; then#if false; then#' mut-collide.sh)"
t_has "mutant: the sed applied" "$(cat "$MC1")" 'if false; then'
MD1="$T/mut-c"; mkdir -p "$MD1/bin"; printf '{"permissions":{"deny":[]}}\n' > "$MD1/settings.json"
t_has "mutant: reached its own output" "$(HARBOR_SCOPE_PRIVATE="$LC" sh "$MC1" --dir "$MD1" --apply 2>&1)" "backup:"
t_eq "mutant: the shadowing file replaced the shipped pack" shadow "$(cat "$MD1/context-rules/user/$CORE1")"
# (b) the data-only guard
MC2="$(mutant 's#\*\.md|projects\.tsv) ;;#*) ;;#' mut-data.sh)"
t_has "mutant: the sed applied" "$(cat "$MC2")" '*) ;;'
MD2="$T/mut-d"; mkdir -p "$MD2/bin"; printf '{"permissions":{"deny":[]}}\n' > "$MD2/settings.json"
t_has "mutant: reached its own output" "$(HARBOR_SCOPE_PRIVATE="$LS" sh "$MC2" --dir "$MD2" --apply 2>&1)" "backup:"
t_eq "mutant: the private script was installed into every session's hook directory" yes "$([ -f "$MD2/context-rules/user/90-evil.sh" ] && echo yes || echo no)"
# (c) the matcher reads the private packs
MC3="$(mutant 's#for _f in "\$PRIVINJ"/\*/\*\.md; do#for _f in /nonexistent/\*/\*.md; do#' mut-matcher.sh)"
t_has "mutant: the sed applied" "$(cat "$MC3")" '/nonexistent/'
MD3="$T/mut-m"; mkdir -p "$MD3/bin"; printf '{"permissions":{"allow":[],"deny":[]}}\n' > "$MD3/settings.json"
t_has "mutant: reached its own output" "$(HARBOR_SCOPE_PRIVATE="$PL" sh "$MC3" --dir "$MD3" --apply 2>&1)" "backup:"
t_hasnt "mutant: a private pack's tool is missing from the matcher" "$(pmatch "$MD3")" "ZzPrivateTool"
# (d) --projects seeds from the private folders
MC4="$(mutant 's#for _d in "\$PRIVINJ"/\*/; do#for _d in "$ROOT"/inject.d/*/; do#' mut-seed.sh)"
t_has "mutant: the sed applied" "$(cat "$MC4")" 'for _d in "$ROOT"/inject.d/*/; do'
mkph; HOME="$PH" HARBOR_SCOPE_PRIVATE="$PL" sh "$MC4" --live --apply --projects >/dev/null 2>&1
t_eq "mutant: the project keeps its stale pack, the layer's was never seeded" old "$(cat "$PH/port/demo/context-rules/demo/10-demo-zz.md")"
# (e) the repo folders are data: each guard of the --projects pre-check, cut in turn
seedmut() { mkph; HOME="$PH" HARBOR_SCOPE_PRIVATE="$2" sh "$1" --live --apply --projects >/dev/null 2>&1; }  # <mutant> <layer>
ME1="$(mutant 's#^        \*\.md) ;;#        *) ;;#' mut-repodata.sh)"
t_has "mutant: the sed applied" "$(cat "$ME1")" '        *) ;;'
seedmut "$ME1" "$T/lay-script"
t_eq "mutant: a private script was seeded into the repository" yes "$([ -f "$PH/port/demo/context-rules/demo/90-evil.sh" ] && echo yes || echo no)"
ME2="$(mutant 's#if \[ -L "\$_rf" \] || \[ ! -f "\$_rf" \]; then#if false; then#' mut-repoplain.sh)"
t_has "mutant: the sed applied" "$(cat "$ME2")" 'if false; then'
seedmut "$ME2" "$T/lay-link"
t_eq "mutant: a private link was seeded into the repository" yes "$([ -e "$PH/port/demo/context-rules/demo/20-link.md" ] && echo yes || echo no)"
ME3="$(mutant 's#if \[ -L "\${_rd%/}" \]; then#if false; then#' mut-repofolder.sh)"
t_has "mutant: the sed applied" "$(cat "$ME3")" 'if false; then'
seedmut "$ME3" "$T/lay-folderlink"
t_eq "mutant: a linked folder was seeded over the project's pack" seeded "$(grep -qx old "$PH/port/demo/context-rules/demo/10-demo-zz.md" && echo kept || echo seeded)"
ME4="$(mutant 's#if \[ -f "\$_f" \] \&\& \[ "\${_f\#\#\*/}" != .DS_Store \]; then cp#if [ -f "$_f" ]; then cp#' mut-repods.sh)"
t_hasnt "mutant: the sed applied" "$(cat "$ME4")" '!= .DS_Store ]; then cp'
seedmut "$ME4" "$T/lay-ds"
t_eq "mutant: the .DS_Store was seeded into the repository" yes "$([ -e "$PH/port/demo/context-rules/demo/.DS_Store" ] && echo yes || echo no)"
t_section "harbor#1010: a private layer in the new layout (context-rules/user), and the old installed tier retired"
PN2="$T/privnew"; mkdir -p "$PN2/context-rules/user" "$PN2/context-rules/demo"
printf '# name\tpath\tcovers\ndemo\t~/port/demo\ta fixture project\n' > "$PN2/context-rules/user/projects.tsv"
printf -- '---\nevent: SessionStart\nwhen: always\n---\n\nbody\n' > "$PN2/context-rules/user/private-new-note.md"
printf -- '---\nevent: PreToolUse\ntool: ZzNewTool\nwhen: always\n---\n\nbody\n' > "$PN2/context-rules/demo/demo-new.md"
PY="$T/py"; mkdir -p "$PY/bin" "$PY/inject.d"; printf '{"permissions":{"allow":[],"deny":[]}}\n' > "$PY/settings.json"
printf 'stale\n' > "$PY/inject.d/10-stale.md"
t_has "status: the old installed tier is named" "$(HARBOR_SCOPE_PRIVATE="$PN2" sh "$TOOL" --dir "$PY" 2>&1)" "the old box tier $PY/inject.d is still installed"
PYO="$(HARBOR_SCOPE_PRIVATE="$PN2" sh "$TOOL" --dir "$PY" --apply 2>&1)"
t_eq "the new private box file and registry install beside core's" "yes yes" \
  "$([ -f "$PY/context-rules/user/private-new-note.md" ] && echo yes || echo no) $([ -f "$PY/context-rules/user/projects.tsv" ] && echo yes || echo no)"
t_has "a new-layout private repo rule's tool reaches the matcher" "$(pmatch "$PY")" "ZzNewTool"
t_eq "the old installed tier is gone from the config dir" no "$([ -e "$PY/inject.d" ] && echo yes || echo no)"
t_eq "...and is in the run's backup, never deleted" stale "$(cat "$(dirname "$(printf '%s\n' "$PYO" | sed -n 's/^log: //p' | tail -1)")/inject.d/10-stale.md" 2>/dev/null)"
t_done
