#!/usr/bin/env sh
# admission-remove.sh on throwaway config dirs (moved out of floor.install-test for T2's 500 lines, harbor#815):
# it removes what it lists and lists what the install wired (UNINSTALL-1, harbor#766), takes the install
# standard's interface (UNINSTALL-2), keeps what runtime-install co-owns (UNINSTALL-3), and drops the
# .harbor-manifest rows of exactly the files it moves, a partial run included (UNINSTALL-4, harbor#815).
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/../baseline/fixture.sh"
PERM='{"permissions":{"allow":[],"deny":[],"disableBypassPermissionsMode":"disable","disableAutoMode":"disable"}}'
mkcfg() { # <dir> <settings-json> [script…] — a config dir holding its settings and a copy of each script
  _md="$1"; mkdir -p "$_md/bin"; printf '%s\n' "$2" > "$_md/settings.json"; shift 2
  for _mg in "$@"; do cp "$SRC/$_mg" "$_md/bin/" 2>/dev/null; done
}
phys() { (CDPATH='' cd -P -- "$1" && pwd -P); }  # install-lib reports and wires the PHYSICAL target
fi_run() { _fr="$1"; _fd="$2"; shift 2; env -u CLAUDE_CONFIG_DIR sh "$SRC/$_fr" --dir "$_fd" "$@"; }  # <tool> <dir> [flags…]
FH="$TMP/fakehome"; mkcfg "$FH/.claude" '{"permissions":{"deny":[]}}'

t_section "UNINSTALL-1 (harbor#766): the uninstall removes what it lists, and lists what the install wired"
# A box as an operator has it: read denies, the mode locks, a plugin, a FOREIGN hook in the very
# bucket the floor merges into and one at Stop, and the trees an uninstall must keep.
U_PRE='{"permissions":{"allow":[],"deny":["Read(~/.ssh/**)","Edit(~/.ssh/**)"],"disableBypassPermissionsMode":"disable","disableAutoMode":"disable"},"enabledPlugins":{"x@y":true},"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/usr/local/bin/foreign-bash.sh"}]}],"Stop":[{"matcher":"","hooks":[{"type":"command","command":"echo foreign-stop"}]}]}}'
u_cmds() { jq -r '.hooks // {} | to_entries[] | .key as $e | .value[]? | .hooks[]? | "\($e): \(.command)"' "$1" | sort; }
u_dangling() { # <dir> → each wired path, or a file one of them sources, that is not on disk
  jq -r '.hooks // {} | .[]?[]?.hooks[]?.command // empty' "$1/settings.json" | tr -d '"' | tr ' ' '\n' \
    | grep '^/' | grep -v -e '^/bin/sh$' -e '^/usr/local/bin/foreign-bash.sh$' | sort -u > "$TMP/u.paths"
  while read -r _p; do
    [ -e "$_p" ] || { echo "wired: ${_p##*/}"; continue; }
    for _d in $(sed -n 's/^[[:space:]]*\. "\$DIR\/\([^"]*\)".*/\1/p' "$_p"); do
      [ -e "${_p%/*}/$_d" ] || echo "sourced: $_d by ${_p##*/}"
    done
  done < "$TMP/u.paths"
}
U_PAYLOAD="$(sed -n "s/^GUARDS='\(.*\)'/\1/p" "$SRC/admission-install.sh") admission-integrity.sh admission-stop.sh"
for _uv in plain b6 stop both runtime; do
  _ud="$TMP/uninstall-$_uv"; mkdir -p "$_ud/bin" "$_ud/skills/s" "$_ud/MEMORY" "$_ud/plugins"
  printf '%s\n' "$U_PRE" | jq . > "$_ud/settings.json"
  printf 'skill\n' > "$_ud/skills/s/SKILL.md"; printf 'memory\n' > "$_ud/MEMORY/m.md"; printf 'plugin\n' > "$_ud/plugins/p.json"
  [ "$_uv" = runtime ] && fi_run deploy-runtime-install.sh "$_ud" --apply >/dev/null 2>&1
  cp "$_ud/settings.json" "$TMP/u-$_uv.pre"
  case "$_uv" in plain) _uf="" ;; b6) _uf=--with-b6 ;; stop) _uf=--with-stop-gate ;; *) _uf="--with-b6 --with-stop-gate" ;; esac
  fi_run admission-install.sh "$_ud" --apply $_uf >/dev/null 2>&1
  cp "$_ud/settings.json" "$TMP/u-$_uv.installed"; ls -A "$_ud/bin" | sort > "$TMP/u-$_uv.bin0"
  cp "$_ud/.harbor-manifest" "$TMP/u-$_uv.mf0"
  _udry="$(env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-remove.sh" --dir "$_ud" 2>&1)"
  t_eq "UNINSTALL-1 $_uv: the dry run writes nothing" same \
    "$(cmp -s "$_ud/settings.json" "$TMP/u-$_uv.installed" && ls -A "$_ud/bin" | sort | cmp -s - "$TMP/u-$_uv.bin0" && echo same || echo changed)"
  t_eq "UNINSTALL-1 $_uv: the dry run leaves .harbor-manifest as it was (harbor#815)" same \
    "$(cmp -s "$_ud/.harbor-manifest" "$TMP/u-$_uv.mf0" && echo same || echo changed)"
  t_exit "UNINSTALL-1 $_uv: --apply succeeds" 0 env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-remove.sh" --dir "$_ud" --apply
  t_eq "UNINSTALL-1 $_uv: settings.json minus permissions.deny is what it was before the install" \
    "$(jq -S 'del(.permissions.deny)' "$TMP/u-$_uv.pre")" "$(jq -S 'del(.permissions.deny)' "$_ud/settings.json")"
  t_eq "UNINSTALL-1 $_uv: permissions.deny is untouched (SEC-0 and B1 alike)" \
    "$(jq -c '.permissions.deny' "$TMP/u-$_uv.installed")" "$(jq -c '.permissions.deny' "$_ud/settings.json")"
  t_eq "UNINSTALL-1 $_uv: no wired hook points at a file the uninstall deleted" "" "$(u_dangling "$_ud")"
  u_cmds "$TMP/u-$_uv.installed" > "$TMP/u.before"; u_cmds "$_ud/settings.json" > "$TMP/u.after"
  t_eq "UNINSTALL-1 $_uv: the dry-run hook listing is exactly what was removed" \
    "$(comm -23 "$TMP/u.before" "$TMP/u.after" | tr '\n' '|')" \
    "$(printf '%s\n' "$_udry" | sed -n 's/^  note: hook to remove: \([A-Za-z]*: .*\)$/\1/p' | sort | tr '\n' '|')"
  ls -A "$_ud/bin" | sort > "$TMP/u.after.bin"
  t_eq "UNINSTALL-1 $_uv: the dry-run file listing is exactly what left bin/" \
    "$(ls -A "$_ud/bin" | sort | comm -13 - "$TMP/u-$_uv.bin0" | sed 's#^#bin/#' | tr '\n' '|')" \
    "$(printf '%s\n' "$_udry" | sed -n 's/^  note: floor file to remove: \(bin\/.*\)$/\1/p' | sort | tr '\n' '|')"
  t_eq "UNINSTALL-1 $_uv: skills, MEMORY and plugins are untouched" "skill memory plugin" \
    "$(cat "$_ud/skills/s/SKILL.md" "$_ud/MEMORY/m.md" "$_ud/plugins/p.json" | tr '\n' ' ' | sed 's/ $//')"
  _ul=""; for _g in $U_PAYLOAD; do [ -e "$_ud/bin/$_g" ] && _ul="$_ul $_g"; done
  # runtime-install ships these two and its own hooks load them (memory-harvest, context-resolve).
  if [ "$_uv" = runtime ]; then _uw=" library-admission.sh context-resolve.sh"; else _uw=""; fi
  t_eq "UNINSTALL-1 $_uv: the floor files left in bin/ are only the runtime's shared ones" "$_uw" "$_ul"
  t_eq "UNINSTALL-1 $_uv: every file it removed is in the run's backup, backups/floor-uninstall/<TS>/" "" \
    "$(for _f in $(comm -13 "$TMP/u.after.bin" "$TMP/u-$_uv.bin0" 2>/dev/null); do ls "$_ud"/backups/floor-uninstall/*/bin/"$_f" >/dev/null 2>&1 || printf ' %s' "$_f"; done)"
  t_eq "UNINSTALL-1 $_uv: the pins, teeth and B8 pin are gone" "" \
    "$(for _s in .helm-pins .helm-floor-teeth .helm-instructions.sha256; do [ -e "$_ud/$_s" ] && printf ' %s' "$_s"; done)"
  # harbor#815: the manifest is the record of what is installed, so a moved file's row goes with it.
  comm -13 "$TMP/u.after.bin" "$TMP/u-$_uv.bin0" | sed 's#^#bin/#' > "$TMP/u.moved"
  grep -v '^#' "$TMP/u-$_uv.mf0" | awk '{print $3}' | sort | comm -12 - "$TMP/u.moved" > "$TMP/u.mfmoved"
  t_eq "UNINSTALL-1 $_uv: CONTROL — the install recorded rows for files the uninstall moves" yes \
    "$([ -s "$TMP/u.mfmoved" ] && echo yes || echo no)"
  t_eq "UNINSTALL-1 $_uv: no floor-install row names a file it moved (harbor#815)" "" \
    "$(grep -v '^#' "$_ud/.harbor-manifest" | awk '$4 == "floor-install" {print $3}' | sort | comm -12 - "$TMP/u.moved" | tr '\n' ' ')"
  t_eq "UNINSTALL-1 $_uv: ...nor any other installer's row" "" \
    "$(grep -v '^#' "$_ud/.harbor-manifest" | awk '{print $3}' | sort | comm -12 - "$TMP/u.moved" | tr '\n' ' ')"
  t_eq "UNINSTALL-1 $_uv: every row of a file it kept is unchanged, byte for byte" \
    "$(grep -v '^#' "$TMP/u-$_uv.mf0" | awk 'NR == FNR { m[$1] = 1; next } !($3 in m)' "$TMP/u.moved" - | sort)" \
    "$(grep -v '^#' "$_ud/.harbor-manifest" | sort)"
  t_eq "UNINSTALL-1 $_uv: the dry run listed exactly the rows the apply dropped" \
    "$(tr '\n' '|' < "$TMP/u.mfmoved")" \
    "$(printf '%s\n' "$_udry" | sed -n 's/^  note: \.harbor-manifest row to drop: \([^ ]*\) (.*)$/\1/p' | sort | tr '\n' '|')"
  t_eq "UNINSTALL-1 $_uv: the pre-run manifest is in the run's backup (backup, temp, mv)" same \
    "$(cmp -s "$TMP/u-$_uv.mf0" "$(ls -d "$_ud"/backups/floor-uninstall/*/.harbor-manifest 2>/dev/null | head -1)" && echo same || echo changed)"
  t_eq "UNINSTALL-1 $_uv: no manifest temp file is left beside it" "" "$(ls -A "$_ud" | grep '^\.harbor-manifest\.' || :)"
done

# A hook no table row describes (an older install's wiring, another event) still goes when it names
# a file the uninstall deletes: the invariant is the deleted files, not the current table.
_uo="$TMP/uninstall-older"; mkcfg "$_uo" "$PERM"; fi_run admission-install.sh "$_uo" --apply >/dev/null 2>&1
jq --arg c "/bin/sh $_uo/bin/admission-hook.sh $_uo/bin/admission-cloud.sh" --arg n "/bin/sh $_uo/bin/library-admission.sh" \
  '.hooks.PreToolUse += [{matcher: "Bash", hooks: [{type: "command", command: $c}]}]
   | .hooks.Notification = [{matcher: "", hooks: [{type: "command", command: $n}]}]' \
  "$_uo/settings.json" > "$_uo/s.tmp" && mv "$_uo/s.tmp" "$_uo/settings.json"
_uod="$(env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-remove.sh" --dir "$_uo" 2>&1)"
t_has "UNINSTALL-1 an older floor-hook wiring of guard-cloud is listed" "$_uod" "PreToolUse: /bin/sh $_uo/bin/admission-hook.sh $_uo/bin/admission-cloud.sh"
t_has "UNINSTALL-1 a hook at an event the floor never wires is listed when it names a floor file" "$_uod" "Notification: /bin/sh $_uo/bin/library-admission.sh"
env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-remove.sh" --dir "$_uo" --apply >/dev/null 2>&1
t_eq "UNINSTALL-1 …and after the apply nothing wired points at a deleted file" "" "$(u_dangling "$_uo")"

t_section "UNINSTALL-2 (harbor#766): the install-standard interface — --live or --dir PATH, never a positional"
_ui="$TMP/uninstall-iface"; mkcfg "$_ui" '{"permissions":{"deny":[]}}'
t_exit "UNINSTALL-2 a positional target is a usage error" 2 env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-remove.sh" "$_ui"
t_exit "UNINSTALL-2 a positional after --live is a usage error, not a target" 2 \
  env -u CLAUDE_CONFIG_DIR HOME="$FH" sh "$SRC/admission-remove.sh" --live "$_ui" --apply
t_exit "UNINSTALL-2 an unknown flag before the target is a usage error" 2 env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-remove.sh" --nonesuch --dir "$_ui"
t_exit "UNINSTALL-2 an unknown flag after the target is a usage error" 2 env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-remove.sh" --dir "$_ui" --nonesuch
t_exit "UNINSTALL-2 no target is a usage error" 2 env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-remove.sh" --apply
t_exit "UNINSTALL-2 --dir with no path is a usage error" 2 env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-remove.sh" --dir
t_exit "UNINSTALL-2 --live with a --dir elsewhere is a usage error" 2 \
  env -u CLAUDE_CONFIG_DIR HOME="$FH" sh "$SRC/admission-remove.sh" --live --dir "$_ui"
t_exit "UNINSTALL-2 a CLAUDE_CONFIG_DIR that is not the target is refused as usage" 2 \
  env CLAUDE_CONFIG_DIR="$CFG" sh "$SRC/admission-remove.sh" --dir "$_ui"
t_exit "UNINSTALL-2 a CLAUDE_CONFIG_DIR that IS the target, spelled differently, is accepted" 0 \
  env CLAUDE_CONFIG_DIR="$_ui/." sh "$SRC/admission-remove.sh" --dir "$_ui"
t_exit "UNINSTALL-2 --help answers without work" 0 sh "$SRC/admission-remove.sh" --dir "$_ui" --help
t_eq "UNINSTALL-2 no refusal wrote anything" '{"permissions":{"deny":[]}}' "$(jq -c . "$_ui/settings.json")"

t_section "UNINSTALL-3 (harbor#766): a row marked runtime-install is exactly what runtime-install wires"
# floor-uninstall keeps those rows wired while the runtime is on the box, so the mark is a claim.
_urt="$TMP/uninstall-rtonly"; mkcfg "$_urt" '{}'
fi_run deploy-runtime-install.sh "$_urt" --apply >/dev/null 2>&1
_urows="$(awk '/^floor_hooks\(\)/ { f = 1; next } f && /^ROWS$/ { exit } f && !/^#/ && /;/' "$SRC/admission-install.sh")"
t_eq "UNINSTALL-3 the wiring table parses non-empty" yes "$([ -n "$_urows" ] && echo yes || echo no)"
t_eq "UNINSTALL-3 runtime-install wired hooks in the fixture" true "$(jq -r '(.hooks // {}) | length > 0' "$_urt/settings.json")"
_uboth=""; _umark=""; _urtp="$(phys "$_urt")"  # the installer wires the physical target
while IFS=';' read -r _ev _m _argv _opt _co; do
  _c="/bin/sh"; for _t in $_argv; do case "$_t" in -*) _c="$_c $_t" ;; *) _c="$_c $_urtp/bin/$_t" ;; esac; done
  jq -e --arg e "$_ev" --arg c "$_c" '[.hooks[$e][]?.hooks[]?.command] | index($c)' "$_urt/settings.json" >/dev/null 2>&1 \
    && _uboth="$_uboth $_ev:${_argv##* }"
  [ "$_co" = runtime-install ] && _umark="$_umark $_ev:${_argv##* }"
done <<EOF
$_urows
EOF
t_eq "UNINSTALL-3 the rows runtime-install wires on its own are the rows marked runtime-install" "$_umark" "$_uboth"

t_section "UNINSTALL-4 (harbor#815): a partial uninstall drops only the rows of what moved; a reinstall writes them back"
_up="$TMP/uninstall-partial"; mkcfg "$_up" "$PERM"; fi_run admission-install.sh "$_up" --apply >/dev/null 2>&1
cp "$_up/.harbor-manifest" "$TMP/up.mf0"; ls -A "$_up/bin" | sort > "$TMP/up.bin0"
# An mv that refuses one floor file, so the run moves the rest and then fails.
mkdir -p "$TMP/mvstub"
printf '#!/bin/sh\ncase "$1" in */bin/admission-cloud.sh) echo "mv: stub refusal" >&2; exit 1 ;; esac\nexec %s "$@"\n' \
  "$(command -v mv)" > "$TMP/mvstub/mv"; chmod +x "$TMP/mvstub/mv"
_upo="$(env -u CLAUDE_CONFIG_DIR PATH="$TMP/mvstub:$PATH" sh "$SRC/admission-remove.sh" --dir "$_up" --apply 2>&1)"; _uprc=$?
t_eq "UNINSTALL-4 a file that cannot move fails the run" 1 "$_uprc"
t_has "UNINSTALL-4 ...naming it" "$_upo" "could not move: bin/admission-cloud.sh"
t_eq "UNINSTALL-4 CONTROL: that file is still in bin/" yes "$([ -f "$_up/bin/admission-cloud.sh" ] && echo yes || echo no)"
ls -A "$_up/bin" | sort | comm -13 - "$TMP/up.bin0" | sed 's#^#bin/#' > "$TMP/up.moved"
t_eq "UNINSTALL-4 CONTROL: the other floor files moved" yes "$([ -s "$TMP/up.moved" ] && echo yes || echo no)"
t_eq "UNINSTALL-4 the rows of what moved are dropped, and every other row is unchanged" \
  "$(grep -v '^#' "$TMP/up.mf0" | awk 'NR == FNR { m[$1] = 1; next } !($3 in m)' "$TMP/up.moved" - | sort)" \
  "$(grep -v '^#' "$_up/.harbor-manifest" | sort)"
t_eq "UNINSTALL-4 ...so the file that stayed keeps its floor-install row" \
  "$(grep ' bin/admission-cloud.sh floor-install ' "$TMP/up.mf0")" "$(grep ' bin/admission-cloud.sh ' "$_up/.harbor-manifest")"
t_exit "UNINSTALL-4 the re-run its fix line names finishes the job" 0 \
  env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-remove.sh" --dir "$_up" --apply
t_eq "UNINSTALL-4 ...and drops that last row" "" "$(grep ' bin/admission-cloud.sh ' "$_up/.harbor-manifest")"
fi_run admission-install.sh "$_up" --apply >/dev/null 2>&1
t_eq "UNINSTALL-4 the next floor install writes a floor-install row back for every guard it copied" "" \
  "$(for _g in $(sed -n "s/^GUARDS='\(.*\)'/\1/p" "$SRC/admission-install.sh"); do
       [ "$(grep " bin/$_g " "$_up/.harbor-manifest" | awk '{print $4}')" = floor-install ] || printf ' %s' "$_g"; done)"
t_eq "UNINSTALL-4 ...each row's blob the bytes on disk" 0 \
  "$(grep -v '^#' "$_up/.harbor-manifest" | while read -r _b _m _r _i _c; do [ "$(git hash-object "$_up/$_r")" = "$_b" ] || echo "$_r"; done | grep -c .)"
_un="$TMP/uninstall-nomf"; mkcfg "$_un" "$PERM"; fi_run admission-install.sh "$_un" --apply >/dev/null 2>&1
mv "$_un/.harbor-manifest" "$TMP/nomf.was"
t_exit "UNINSTALL-4 a box installed before the manifest existed uninstalls" 0 \
  env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-remove.sh" --dir "$_un" --apply
t_eq "UNINSTALL-4 ...and is not handed a manifest it never had" no "$([ -e "$_un/.harbor-manifest" ] && echo yes || echo no)"

ff_sealed
t_done
