#!/usr/bin/env sh
# The security floor, part: its installers and their live-dir gates (harbor#727, from bin/floor-test.sh).
# marker-backfill (H3, harbor#4); floor-deny, floor-install and runtime-install on throwaway config dirs
# (red-team pass 8: X7, X8, X10, X11; harbor#275, #276, #313); the physical live-dir compare (pass 11,
# P11-01); withdrawals (harbor#58); one wiring whichever order (WIRE-1, harbor#95) and the Stop gate
# only when asked (WIRE-3, harbor#291); every printed command passes its own gate (WIRE-2, harbor#95); one decider per command class (harbor#954 item 8).
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$(dirname "$0")/floor-fixture.sh"
PERM='{"permissions":{"allow":[],"deny":[],"disableBypassPermissionsMode":"disable","disableAutoMode":"disable"}}'
SCANNERS='guard-bash.sh guard-egress.sh guard-selfedit.sh annotate-web.sh pin-instructions.sh guard-lib.sh floor-normalize.awk guard-integrity.sh'
mkcfg() { # <dir> <settings-json> [script…] — a config dir holding its settings and a copy of each script
  _md="$1"; mkdir -p "$_md/bin"; printf '%s\n' "$2" > "$_md/settings.json"; shift 2
  for _mg in "$@"; do cp "$SRC/$_mg" "$_md/bin/" 2>/dev/null; done
}
gate() { CLAUDE_CONFIG_DIR="$1" sh "$1/bin/guard-integrity.sh" </dev/null 2>/dev/null || true; }  # <dir> → B6's stdout
live_gate() { # <output> → "refused-live" only when the refusal is a live-dir gate's own message
  case "$1" in (*refusing*"the live "*"dir"*"without an explicit --live"*) echo refused-live ;; (*) echo other ;; esac
}
phys() { (CDPATH='' cd -P -- "$1" && pwd -P); }  # install-lib reports and wires the PHYSICAL target
fi_run() { _fr="$1"; _fd="$2"; shift 2; env -u CLAUDE_CONFIG_DIR sh "$SRC/$_fr" --dir "$_fd" "$@"; }  # <tool> <dir> [flags…]

t_section "H3 (harbor#4): the marker back-fill cannot reach the config dir"
BF="$TMP/backfill"; mkdir -p "$BF/bin" "$BF/po" "$CFG/.agents"
printf 'project:\n  name: "cfg"\n' > "$CFG/.agents/config.yaml"
cat > "$BF/bin/projects-orchestrator" <<EOF
#!/bin/sh
printf '[{"descriptor":{"name":"cfg","path":"%s","config_root":".agents"}}]\n' "$CFG"
EOF
chmod +x "$BF/bin/projects-orchestrator"
_bf_out="$(PATH="$BF/bin:$PATH" HARBOR_ORCHESTRATOR="$BF/po" CLAUDE_CONFIG_DIR="$CFG" \
  sh "$SRC/marker-backfill.sh" --apply --include-dirty 2>&1 || true)"
t_has "H3: the back-fill refuses a config-dir target" "$_bf_out" 'REFUSED'
t_exit "H3: the back-fill did not write into the config surface" 1 /usr/bin/grep -q '^context: repo' "$CFG/.agents/config.yaml"
# Where it DOES write, the file stays one YAML document: the key lands after %YAML/--- (PR #96).
_bf_doc="$TMP/backfill-doc"; mkdir -p "$_bf_doc/bin" "$_bf_doc/po" "$_bf_doc/repo/.agents"
printf -- '%%YAML 1.2\n---\nproject:\n  name: "hdr"\n' > "$_bf_doc/repo/.agents/config.yaml"
cat > "$_bf_doc/bin/projects-orchestrator" <<EOF
#!/bin/sh
printf '[{"descriptor":{"name":"hdr","path":"%s","config_root":".agents"}}]\n' "$_bf_doc/repo"
EOF
chmod +x "$_bf_doc/bin/projects-orchestrator"
PATH="$_bf_doc/bin:$PATH" HARBOR_ORCHESTRATOR="$_bf_doc/po" CLAUDE_CONFIG_DIR="$CFG" \
  sh "$SRC/marker-backfill.sh" --apply --include-dirty >/dev/null 2>&1 || true
_bf_lines="$(tr '\n' '|' < "$_bf_doc/repo/.agents/config.yaml")"
t_eq "H3: the back-fill kept the YAML document header ($_bf_lines)" yes \
  "$(case "$_bf_lines" in ('%YAML 1.2|---|context: repo|project:'*) echo yes ;; (*) echo no ;; esac)"

t_section "REGRESSION: red-team pass 8 (installers: X7, X8)"
# X7: a failed `jq >tmp && mv` short-circuits under set -eu and the installer still printed APPLIED.
IW="$TMP/instwrite"; mkcfg "$IW" '{"permissions":{"deny":[]}}'
env -u CLAUDE_CONFIG_DIR sh "$SRC/floor-deny.sh" --dir "$IW" --apply >/dev/null 2>&1
t_eq "X7 floor-deny wrote the deny array it reported" yes \
  "$([ "$(jq '.permissions.deny | length' "$IW/settings.json" 2>/dev/null || echo 0)" -gt 0 ] && echo yes || echo no)"
t_eq "X7 floor-deny kept the pre-run settings.json in backups/floor-deny/<TS>/, beside its log (one scheme, harbor#765)" \
  '{"permissions":{"deny":[]}}' "$(jq -c . "$IW"/backups/floor-deny/*/settings.json 2>/dev/null)"
t_eq "X7 ...with no old-style backups/settings.json.b1-* beside it" 0 "$(find "$IW/backups" -maxdepth 1 -name 'settings.json.*' | wc -l | tr -d ' ')"
t_eq "X7 ...and one run is one dir: the log install-lib opened holds the backup too (harbor#800)" \
  "1 yes yes" "$(find "$IW/backups/floor-deny" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ') $([ -f "$(ls -d "$IW"/backups/floor-deny/*/ | head -1)log" ] && echo yes || echo no) $([ -f "$(ls -d "$IW"/backups/floor-deny/*/ | head -1)settings.json" ] && echo yes || echo no)"
t_exit "H769 the applied deny set covers deploy's snapshot ledger" 0 \
  jq -e '.permissions.deny | index("Edit(~/.claude/.helm-snapshots)") != null' "$IW/settings.json"
# harbor#779: every integrity row of CONTRACTS/helm-state.md, read from the table, not copied here.
_h779="$(awk '/^## The table/ { s = 1; next } s && /^## / { s = 0 }
  s && /^\| `\.helm-/ { split($0, c, "|"); for (i = 2; i <= 4; i++) gsub(/^[ \t]+|[ \t]+$|`/, "", c[i])
                        if (c[4] == "integrity" && c[3] !~ /^<cfg>\/bin\//) print c[2] }' "$T_ROOT/CONTRACTS/helm-state.md")"
t_eq "H779 the table names integrity files to check" yes "$([ -n "$_h779" ] && echo yes || echo no)"
for _h in $_h779; do
  t_exit "H779 the applied deny set covers $_h" 0 jq -e --arg a "Edit(~/.claude/$_h)" --arg b "Edit(~/.claude/$_h/**)" \
    '.permissions.deny | (index($a) != null) or (index($b) != null)' "$IW/settings.json"
done
B6FILES='guard-lib.sh floor-normalize.awk guard-selfedit.sh guard-bash.sh guard-egress.sh annotate-web.sh guard-integrity.sh floor-deny.sh restore.sh sec0-harden.sh'
B8="$TMP/b6install"; mkcfg "$B8" "$PERM" $B6FILES
_x8out="$(fi_run floor-install.sh "$B8" --apply --with-b6 2>&1)"
t_eq "X8 --with-b6 wired the SessionStart integrity gate" yes "$([ "$(jq -r '[.hooks.SessionStart[]?.hooks[]?.command] | map(select(test("guard-integrity"))) | length' "$B8/settings.json" 2>/dev/null || echo 0)" -gt 0 ] && echo yes || echo no)"
t_eq "X8 --with-b6 pinned guard-integrity content" yes "$([ -f "$B8/.helm-pins/guard-integrity.sh.sha256" ] && echo yes || echo no)"
# harbor#1313 L6: Read deny binds only the directory a Grep searches, so guard-egress judges the filter.
t_eq "X8 Grep is wired to guard-egress under its own matcher" 1 \
  "$(jq '[.hooks.PreToolUse[]? | select(.matcher == "Grep") | .hooks[].command | select(test("guard-egress"))] | length' "$B8/settings.json")"
# X8b: the closing NEXT must not be the work just done, and must stay when B6 was not asked for.
t_hasnt "X8b --with-b6 does not print the NEXT telling the operator to run --with-b6" "$_x8out" 'B6 installs LAST'
t_has "X8b --with-b6 reports what it installed" "$_x8out" 'guard-integrity.sh installed'
_x8c="$TMP/b6nag"; mkcfg "$_x8c" "$PERM" $B6FILES
t_has "X8b a plain --apply still prints the B6 NEXT" "$(fi_run floor-install.sh "$_x8c" --apply 2>&1)" 'B6 installs LAST'
# harbor#285: deploy prints its own B6 advice, so under it the installer's --with-b6 step is not repeated.
_x8d="$TMP/b6deploy"; mkcfg "$_x8d" "$PERM" $B6FILES
_x8do="$(env -u CLAUDE_CONFIG_DIR HARBOR_DEPLOY=1 sh "$SRC/floor-install.sh" --apply --dir "$_x8d" 2>&1)"
t_hasnt "X8b under deploy (HARBOR_DEPLOY=1) no --with-b6 next step is printed" "$_x8do" '--with-b6'
t_has "X8b ...while outside deploy it is, as a command its own gate takes" "$(fi_run floor-install.sh "$_x8c" --apply 2>&1)" \
  "  note: next: sh $SRC/floor-install.sh --apply --dir '$(phys "$_x8c")' --with-b6"
t_eq "X8b an apply keeps its pre-run settings.json beside its log, in backups/floor-install/<TS>/" "$(printf '%s\n' "$PERM" | jq -c .)" \
  "$(jq -c . "$_x8d"/backups/floor-install/*/settings.json 2>/dev/null)"
t_eq "X8b ...and that dir holds the log the run named" yes \
  "$(_l="$(printf '%s\n' "$_x8do" | sed -n 's/^log: //p')"; [ -f "$_l" ] && case "$_l" in ("$(phys "$_x8d")"/backups/floor-install/*/log) echo yes ;; (*) echo "no: $_l" ;; esac)"
t_eq "X8b ...and no old-style backups/settings.json.floor-install-* file" 0 "$(find "$_x8d/backups" -maxdepth 1 -name 'settings.json.*' | wc -l | tr -d ' ')"

t_section "X10: the installer says which pins it just invalidated"
X10="$TMP/x10"; mkcfg "$X10" '{"permissions":{"deny":[]}}'; mkdir -p "$X10/.helm-pins"
printf 'a-stale-pin-that-matches-nothing\n' > "$X10/.helm-pins/guard-lib.sh.sha256"
printf 'a-stale-pin-that-matches-nothing\n' > "$X10/.helm-pins/pulse.sh.sha256"
X10_OUT="$(fi_run runtime-install.sh "$X10" --apply 2>&1 || true)"
# harbor#285: only a pin floor-install does not re-pin (pulse.sh) earns the banner; guard-lib.sh is a note.
t_has "X10 runtime-install warns that it replaced a content-pinned file" "$X10_OUT" 'B6 CONTENT PINS ARE NOW STALE — the next SessionStart will be BLOCKED: this install replaced content-pinned file(s): pulse.sh ('
t_has "X10 a pin floor-install re-pins is a note naming it" "$X10_OUT" 'content pins behind for: guard-lib.sh — floor-install re-pins them'
t_has "X10 the warning prints a working re-pin command" "$X10_OUT" '.helm-pins/$g.sha256'
t_has "X10 the undo hint names restore.sh in a form its gate takes (harbor#765)" "$X10_OUT" "restore.sh --dir '$(phys "$X10")'"
_x9sha < "$X10/bin/guard-lib.sh" > "$X10/.helm-pins/guard-lib.sh.sha256"
_x9sha < "$X10/bin/context-resolve.sh" > "$X10/.helm-pins/context-resolve.sh.sha256"
_x9sha < "$X10/bin/pulse.sh" > "$X10/.helm-pins/pulse.sh.sha256"
t_hasnt "X10 runtime-install is silent when the pins are current" \
  "$(fi_run runtime-install.sh "$X10" --apply 2>&1 || true)" 'B6 CONTENT PINS ARE NOW STALE'

t_section "X10b (harbor#275): both installers, in the documented order"
# The broken order on purpose; the fixture seeds only a STALE recovery file, or it hides the defect.
X10B="$TMP/x10b"; mkcfg "$X10B" "$PERM" $SCANNERS
printf '#!/usr/bin/env sh\n# a previous deploy of restore.sh\nexit 0\n' > "$X10B/bin/restore.sh"
fi_run floor-install.sh   "$X10B" --apply --with-b6 >/dev/null 2>&1 || true
fi_run runtime-install.sh "$X10B" --apply           >/dev/null 2>&1 || true
t_eq "X10b the two installers in their documented order leave the gate quiet" "" "$(gate "$X10B")"
t_eq "X10b the gate is quiet with restore.sh still PINNED" yes "$([ -f "$X10B/.helm-pins/restore.sh.sha256" ] && echo yes || echo no)"
t_eq "X10b restore.sh on the box is the checkout's copy" "$(_x9sha < "$SRC/restore.sh")" "$(_x9sha < "$X10B/bin/restore.sh")"
t_eq "X10b the retired baseline-pin.sh is neither installed nor pinned (harbor#765)" no \
  "$([ -e "$X10B/bin/baseline-pin.sh" ] || [ -e "$X10B/.helm-pins/baseline-pin.sh.sha256" ] && echo yes || echo no)"
for g in restore.sh sec0-harden.sh; do
  t_eq "X10b floor-install installs the $g it pins" yes "$([ -s "$X10B/bin/$g" ] && echo yes || echo no)"
done
# The libraries the recovery path sources are the recovery path (harbor#771, #765): copied AND pinned.
for g in log-lib.sh install-lib.sh; do
  t_eq "X10b floor-install installs the $g the recovery tools source" same "$(cmp -s "$SRC/$g" "$X10B/bin/$g" && echo same || echo differs)"
  t_eq "X10b ...and content-pins it" "$(_x9sha < "$SRC/$g")" "$(cat "$X10B/.helm-pins/$g.sha256" 2>/dev/null)"
done

t_section "X10c (PR #276): floor-install does not roll the runtime back"
x10c() { # <name> <runtime-ts> <floor-ts> → a dir whose restore.sh came from a newer runtime deploy
  _d="$TMP/$1"; mkcfg "$_d" "$PERM" $SCANNERS
  printf '#!/usr/bin/env sh\n# X10C-NEWER-RUNTIME\nexit 0\n' > "$_d/bin/restore.sh"
  printf 'runtime-install %s %s aaaaaaa\nfloor-install %s %s bbbbbbb\n' \
    aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "$2" bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb "$3" > "$_d/.helm-install-stamp"
  printf '%s' "$_d"
}
X10C="$(x10c x10c-keep 2026-08-22T20:35:07+03:00 2026-08-22T18:25:07+03:00)"
X10C_OUT="$(fi_run floor-install.sh "$X10C" --apply 2>&1 || true)"
t_has "X10c floor-install kept restore.sh from the newer runtime deploy" "$(cat "$X10C/bin/restore.sh")" 'X10C-NEWER-RUNTIME'
t_eq "X10c the declined rollback is reported" yes \
  "$(case "$X10C_OUT" in (*"KEPT the installed copy of"*restore.sh*) echo yes ;; (*) echo no ;; esac)"
t_eq "X10c the kept file is pinned to the bytes on disk" "$(_x9sha < "$X10C/bin/restore.sh")" "$(cat "$X10C/.helm-pins/restore.sh.sha256" 2>/dev/null)"
t_eq "X10c the gate is quiet after a KEPT file" "" "$(gate "$X10C")"
X10D="$(x10c x10c-copy 2026-08-22T18:25:07+03:00 2026-08-22T20:35:07+03:00)"
fi_run floor-install.sh "$X10D" --apply >/dev/null 2>&1 || true
t_eq "X10c CONTROL: with the floor stamped last the copy overwrites" "$(_x9sha < "$SRC/restore.sh")" "$(_x9sha < "$X10D/bin/restore.sh")"

t_section "MANIFEST (install standard §3): both installers record every file they wrote, and only those"
_mfrow() { grep " $2 " "$1/.harbor-manifest" 2>/dev/null | awk '{print $1, $2, $4, $5}'; }  # <dir> <relpath>
_head="$(git -C "$T_ROOT" rev-parse HEAD)"
for g in guard-bash.sh floor-normalize.awk guard-deliverables.sh; do
  t_eq "MANIFEST floor-install recorded bin/$g: its blob, mode, installer and this checkout's commit" \
    "$(git hash-object "$X10B/bin/$g") $([ -x "$X10B/bin/$g" ] && echo 100755 || echo 100644) floor-install $_head" "$(_mfrow "$X10B" "bin/$g")"
done
t_eq "MANIFEST a file both install is the last writer's row (runtime-install ran second)" \
  "$(git hash-object "$X10B/bin/restore.sh") 100755 runtime-install $_head" "$(_mfrow "$X10B" bin/restore.sh)"
t_eq "MANIFEST ...and so is B6, which runtime-install refreshes because it is installed (REFRESH_ONLY)" \
  "$(git hash-object "$X10B/bin/guard-integrity.sh") 100755 runtime-install $_head" "$(_mfrow "$X10B" bin/guard-integrity.sh)"
t_eq "MANIFEST runtime-install recorded lib/core.sh, which lives outside bin/" \
  "$(git hash-object "$X10B/lib/core.sh") 100644 runtime-install $_head" "$(_mfrow "$X10B" lib/core.sh)"
t_eq "MANIFEST no row for a file neither installer wrote (the retired baseline-pin.sh)" "" "$(_mfrow "$X10B" bin/baseline-pin.sh)"
t_eq "MANIFEST every row's blob is the bytes on disk" 0 "$(grep -v '^#' "$X10B/.harbor-manifest" | while read -r _b _m _r _i _c; do [ "$(git hash-object "$X10B/$_r")" = "$_b" ] || echo "$_r"; done | grep -c .)"
t_eq "MANIFEST B6's pin dir stays its own store: no .helm-pins path is a manifest row" 0 "$(grep -c ' \.helm-pins/' "$X10B/.harbor-manifest")"
X10K="$(x10c x10c-mf 2026-08-22T20:35:07+03:00 2026-08-22T18:25:07+03:00)"
fi_run floor-install.sh "$X10K" --apply >/dev/null 2>&1 || true
t_eq "MANIFEST a KEPT file gets no floor-install row: it did not write it" "" "$(_mfrow "$X10K" bin/restore.sh)"
t_eq "MANIFEST ...while the files it did copy have theirs" floor-install "$(_mfrow "$X10K" bin/sec0-harden.sh | awk '{print $3}')"
X10M="$TMP/x10m"; mkcfg "$X10M" "$PERM" $SCANNERS
fi_run floor-install.sh "$X10M" >/dev/null 2>&1 || true
t_eq "MANIFEST a dry run writes no manifest" no "$([ -e "$X10M/.harbor-manifest" ] && echo yes || echo no)"
fi_run floor-install.sh "$X10M" --apply --with-stop-gate >/dev/null 2>&1 || true
t_eq "MANIFEST the Stop gate, when asked for, is a row" floor-install "$(_mfrow "$X10M" bin/guard-stop.sh | awk '{print $3}')"
t_eq "MANIFEST ...and B6, not asked for, is not" "" "$(_mfrow "$X10M" bin/guard-integrity.sh)"

t_section "X11: B6 has an update path, and it is refresh-only"
X11="$TMP/x11"; mkcfg "$X11" '{"permissions":{"deny":[]}}'
fi_run runtime-install.sh "$X11" --apply >/dev/null 2>&1 || true
t_eq "X11 runtime-install does not INSTALL guard-integrity.sh on a box without the scanners" no \
  "$([ -e "$X11/bin/guard-integrity.sh" ] && echo yes || echo no)"
printf '#!/usr/bin/env sh\n[ "${HELM_DISABLE_FLOOR:-0}" = "1" ] && exit 0\n# stale B6\nexit 0\n' > "$X11/bin/guard-integrity.sh"
fi_run runtime-install.sh "$X11" --apply >/dev/null 2>&1 || true
t_eq "X11 runtime-install refreshes an installed guard-integrity.sh" "$(_x9sha < "$SRC/guard-integrity.sh")" "$(_x9sha < "$X11/bin/guard-integrity.sh")"
mkdir -p "$X11/.helm-pins"
printf 'a-stale-pin-that-matches-nothing\n' > "$X11/.helm-pins/guard-integrity.sh.sha256"
printf '#!/usr/bin/env sh\n[ "${HELM_DISABLE_FLOOR:-0}" = "1" ] && exit 0\nexit 0\n' > "$X11/bin/guard-integrity.sh"
X11_OUT="$(fi_run runtime-install.sh "$X11" --apply 2>&1 || true)"
t_eq "X11 a refreshed B6 is reported quietly, never under the session-blocked banner" quiet-note \
  "$(case "$X11_OUT" in (*"B6 CONTENT PINS ARE NOW STALE"*) echo blocked-banner ;; (*"guard-integrity.sh was refreshed, so its pin"*) echo quiet-note ;; (*) echo silent ;; esac)"
# The premise of the quiet note, behaviourally: B6 must not content-check its own pin.
X11S="$TMP/x11self"; mkcfg "$X11S" '{"permissions":{"deny":[]}}' $SCANNERS; mkdir -p "$X11S/.helm-pins"
for g in $SCANNERS; do _x9sha < "$X11S/bin/$g" > "$X11S/.helm-pins/$g.sha256"; done
env -u CLAUDE_CONFIG_DIR sh "$SRC/floor-deny.sh" --dir "$X11S" --repin >/dev/null 2>&1
printf 'deliberately-stale-b6-pin\n' > "$X11S/.helm-pins/guard-integrity.sh.sha256"
t_hasnt "X11 B6 does not content-check ITSELF" "[$(gate "$X11S" | jq -r '.systemMessage // ""' 2>/dev/null)]" 'guard-integrity.sh'
printf '\n# drift\n' >> "$X11S/bin/guard-bash.sh"
t_has "X11 control: B6 names a drifted guard-bash.sh in the same dir" "$(gate "$X11S" | jq -r '.systemMessage // ""')" 'guard-bash.sh'

t_section "harbor#313: an unrunnable regression check is not a regression verdict"
X313="$TMP/x313/.claude"; mkdir -p "$X313/bin" "$X313/.helm-pins"
# An installed copy carries the libraries every installer sources (runtime-install ships them, harbor#771).
for _g in $(sed -n "s/^GUARDS='\(.*\)'/\1/p" "$SRC/floor-install.sh") floor-install.sh floor-deny.sh floor-verify.sh log-lib.sh install-lib.sh; do
  cp "$SRC/$_g" "$X313/bin/" 2>/dev/null || :
done
printf '{"permissions":{"deny":[]},"hooks":{}}\n' > "$X313/settings.json"
X313OUT="$(cd "$X313/bin" && env -u CLAUDE_CONFIG_DIR sh ./floor-install.sh --dir "$X313" --apply 2>&1)"; X313RC=$?  # no install-stamp.sh here
t_eq "harbor#313 floor-install refuses with install-stamp.sh absent" 1 "$X313RC"
t_has "harbor#313 floor-install says the check could not RUN" "$X313OUT" 'regression check could not run'
t_has "harbor#313 the regression verdict is still a message floor-install can print" "$(cat "$SRC/floor-install.sh")" 'missing work that is already installed'
t_hasnt "harbor#313 a MISSING install-stamp.sh is not reported as a regression" "$X313OUT" 'missing work that is already installed'
cp "$SRC/install-stamp.sh" "$SRC/merged-check.sh" "$X313/bin/" 2>/dev/null || :
t_hasnt "harbor#313 with install-stamp.sh present the check is not called unrunnable" \
  "$(cd "$X313/bin" && env -u CLAUDE_CONFIG_DIR sh ./floor-install.sh --dir "$X313" --apply 2>&1 || true)" 'regression check could not run'
# Every script sandbox-make EXECUTES is in an installer payload, and the scan must find some.
PL=" $(echo $(ff_payload)) "
_x313_all="$(grep -v '^[[:space:]]*#' "$SRC/sandbox-make.sh" | grep -oE 'sh "\$SRC/[a-z0-9-]+\.sh"' | sed 's#.*/##; s/"$//' | sort -u)"
_x313_sm=""; [ -n "$_x313_all" ] || _x313_sm=" (the scan matched no sh \"\$SRC/…\" call)"
for _r in $_x313_all; do case "$PL" in *" $_r "*) ;; *) _x313_sm="$_x313_sm $_r" ;; esac; done
t_eq "harbor#313 sandbox-make.sh executes only \$SRC scripts an installer ships" "" "$_x313_sm"
for _x313_need in floor-install.sh install-stamp.sh merged-check.sh; do
  t_has "harbor#313 $_x313_need is in an installer payload" "$PL" " $_x313_need "
done

t_section "REGRESSION: pass 11 · the live-dir gate is a PHYSICAL path compare"
# One trailing character defeated a string compare (P11-01); each refusal must be the live gate's own.
FH="$TMP/fakehome"; mkcfg "$FH/.claude" '{"permissions":{"deny":[]}}'
for spelling in "/.claude/" "/.claude/." "/.claude//" "/.claude/../.claude"; do
  for tool in floor-deny.sh floor-install.sh floor-uninstall.sh; do
    # The install-standard interface for all three now: --dir, no positional (harbor#766, #765, #800).
    _o="$(env -u CLAUDE_CONFIG_DIR HOME="$FH" sh "$SRC/$tool" --dir "$FH$spelling" --apply 2>&1)"; c=$?
    t_eq "P11: $tool refuses live via the spelling '$spelling' with no --live" "rc=1 refused-live" "rc=$c $(live_gate "$_o")"
  done
done
# CLAUDE_CONFIG_DIR never picks the target (harbor#765): pointed at live with a trailing slash and no
# target, sec0-harden is a usage error; aimed at live by --dir, the live gate itself refuses it.
t_exit "P11: sec0-harden with a trailing-slash CLAUDE_CONFIG_DIR and no target is a usage error" 2 \
  env HOME="$FH" CLAUDE_CONFIG_DIR="$FH/.claude/" sh "$SRC/sec0-harden.sh" --apply
_o="$(env HOME="$FH" CLAUDE_CONFIG_DIR="$FH/.claude/" sh "$SRC/sec0-harden.sh" --apply --dir "$FH/.claude/" 2>&1)"; c=$?
t_eq "P11: sec0-harden refuses live via a trailing-slash --dir" "rc=1 refused-live" "rc=$c $(live_gate "$_o")"
# sandbox-make's rm -rf ran above its live gate: assert the SURVIVORS, not only the exit code.
for spelling in "" "/" "/." "//" "/../.claude"; do
  SM="$TMP/sandboxmake"; rm -rf "$SM"; mkcfg "$SM/.claude" '{"permissions":{"deny":[]}}'
  printf 'live doctrine\n' > "$SM/.claude/CLAUDE.md"
  _o="$(env HOME="$SM" CLAUDE_CONFIG_DIR="$SM/.claude" sh "$SRC/sandbox-make.sh" "$SM/.claude$spelling" --fresh 2>&1)"; c=$?
  t_eq "P11: sandbox-make refuses live via '.claude$spelling'" "rc=1 live" \
    "rc=$c $(case "$_o" in (*"refusing to target the live config dir"*) echo live ;; (*) echo other ;; esac)"
  t_eq "P11: sandbox-make kept live content via '.claude$spelling'" yes \
    "$([ -f "$SM/.claude/CLAUDE.md" ] && [ -d "$SM/.claude/bin" ] && echo yes || echo no)"
done
GC="$TMP/gatecheck"; mkcfg "$GC" '{"permissions":{"deny":[]}}'
t_exit "P11: the physical-path gate still applies to an ordinary sandbox target" 0 env HOME="$FH" env -u CLAUDE_CONFIG_DIR sh "$SRC/floor-deny.sh" --dir "$GC/" --apply
env HOME="$SM" CLAUDE_CONFIG_DIR="$SM/.claude" sh "$SRC/sandbox-make.sh" "$SM/box" --fresh >/dev/null 2>&1; c=$?
t_eq "P11: sandbox-make still builds an ordinary sandbox" "rc=0 settings" "rc=$c $([ -f "$SM/box/settings.json" ] && echo settings || echo none)"
# --with-floor runs floor-install through the install standard's --dir interface (harbor#765), with the
# SOURCE dir in CLAUDE_CONFIG_DIR; the floor must land and verify, or the sandbox is not this checkout's.
_smf="$(env HOME="$SM" CLAUDE_CONFIG_DIR="$SM/.claude" sh "$SRC/sandbox-make.sh" "$SM/boxf" --fresh --with-floor 2>&1)"; c=$?
t_eq "P11: sandbox-make --with-floor installs this checkout's floor" "rc=0 same" \
  "rc=$c $(cmp -s "$SRC/guard-bash.sh" "$SM/boxf/bin/guard-bash.sh" && echo same || echo differs)"
t_has "P11: ...and says the floor verifies there" "$_smf" '  ok: the floor verifies in the new sandbox'

t_section "harbor#58: a withdrawal is DATA, and it cannot be resurrected"
WD="$TMP/withdraw"; mkdir -p "$WD"
_wd_list="$(sed -n "/^WITHDRAWN='\[/,/^\]'/p" "$SRC/floor-deny.sh" | grep -oE '"[^"]+"' | tr -d '"')"
t_eq "harbor#58: WITHDRAWN parses non-empty" parsed "$([ -n "$_wd_list" ] && echo parsed || echo empty)"
_add_list="$(env -u CLAUDE_CONFIG_DIR sh "$SRC/floor-deny.sh" --dir "$CFG" 2>/dev/null | sed -n 's/^  note: + //p')"
_both=""; [ -n "$_add_list" ] || _both=" (the ADD list parsed empty — nothing was compared)"
for _e in $(printf '%s\n' "$_wd_list" | tr ' ' '\001'); do
  _e="$(printf '%s' "$_e" | tr '\001' ' ')"
  printf '%s\n' "$_add_list" | grep -qxF "$_e" && _both="$_both $_e"
done
t_eq "harbor#58: no entry is in both ADD and WITHDRAWN" "" "$_both"
jq -n '{permissions:{deny:[]}}' > "$WD/settings.json"
env -u CLAUDE_CONFIG_DIR sh "$SRC/floor-deny.sh" --dir "$WD" --apply >/dev/null 2>&1
_res=0
for _e in $(printf '%s\n' "$_wd_list" | tr ' ' '\001'); do
  _e="$(printf '%s' "$_e" | tr '\001' ' ')"
  jq -e --arg p "$_e" '.permissions.deny | index($p)' "$WD/settings.json" >/dev/null 2>&1 && _res=1
done
t_eq "harbor#58: --apply resurrects no withdrawn entry" 0 "$_res"
jq -n --argjson w "$(printf '%s\n' "$_wd_list" | jq -R . | jq -s .)" \
  '{permissions:{deny:($w + ["Edit(~/.ssh/**)","Read(//**/.env)"])}}' > "$WD/settings.json"
env -u CLAUDE_CONFIG_DIR sh "$SRC/floor-deny.sh" --dir "$WD" --withdraw --apply >/dev/null 2>&1
t_eq "harbor#58: --withdraw removes the recorded entries and nothing else" "Edit(~/.ssh/**) Read(//**/.env) " \
  "$(jq -r '.permissions.deny[]' "$WD/settings.json" 2>/dev/null | sort | tr '\n' ' ')"
t_eq "harbor#58: --withdraw re-pins" yes "$([ -f "$WD/.helm-floor-teeth" ] && [ -f "$WD/.sec0-baseline.sha256" ] && echo yes || echo no)"
t_exit "harbor#58: --withdraw with nothing present exits 0" 0 env -u CLAUDE_CONFIG_DIR sh "$SRC/floor-deny.sh" --dir "$WD" --withdraw
for _pair in '--withdraw --prune-inert' '--withdraw --repin' '--prune-inert --repin'; do
  _o="$(env -u CLAUDE_CONFIG_DIR sh "$SRC/floor-deny.sh" --dir "$WD" $_pair 2>&1)"; c=$?
  t_eq "harbor#58: '$_pair' is refused — two acts, one write" "rc=1 refused" \
    "rc=$c $(case "$_o" in (*"are different acts"*) echo refused ;; (*) echo other ;; esac)"
done

t_section "sec0-harden (harbor#765): written like floor-deny writes — temp, validate, mv — and the teeth re-pinned"
S0="$TMP/sec0w"; mkcfg "$S0" '{"permissions":{"allow":["Bash(python3 x)"],"deny":[],"defaultMode":"acceptEdits"}}'
printf 'stale-teeth\n' > "$S0/.helm-floor-teeth"
_s0i="$(ls -i "$S0/settings.json" | awk '{print $1}')"
_s0o="$(fi_run sec0-harden.sh "$S0" --apply 2>&1)"; _s0c=$?
t_eq "sec0 --apply --dir exits 0" 0 "$_s0c"
t_eq "sec0 hardened the file (the interpreter allow is gone, the lock is set)" '[] disable' \
  "$(jq -c '.permissions.allow' "$S0/settings.json") $(jq -r '.permissions.disableBypassPermissionsMode' "$S0/settings.json")"
t_eq "sec0 replaced settings.json by a move, never a truncate in place (a new inode)" yes \
  "$([ "$(ls -i "$S0/settings.json" | awk '{print $1}')" != "$_s0i" ] && echo yes || echo no)"
t_eq "sec0 kept the pre-run settings.json in backups/sec0-harden/<TS>/" '["Bash(python3 x)"]' \
  "$(jq -c '.permissions.allow' "$S0"/backups/sec0-harden/*/settings.json 2>/dev/null)"
t_eq "sec0 re-pinned the floor teeth from the file it wrote, as floor-deny does" \
  "$(jq -S '{deny:.permissions.deny, locks:{bypass:.permissions.disableBypassPermissionsMode, auto:.permissions.disableAutoMode}}' "$S0/settings.json" | _x9sha)" \
  "$(cat "$S0/.helm-floor-teeth")"
t_has "sec0 says so" "$_s0o" '  ok: re-pinned the floor teeth'
S0N="$TMP/sec0noteeth"; mkcfg "$S0N" '{"permissions":{"deny":[]}}'
fi_run sec0-harden.sh "$S0N" --apply >/dev/null 2>&1
t_eq "sec0 creates no teeth pin where the floor never installed one" no "$([ -e "$S0N/.helm-floor-teeth" ] && echo yes || echo no)"

t_section "WIRE-1 (harbor#95): two installers, one wiring, whichever order"
dup_after() { # <first> <second> → commands wired twice under one event AND one selector
  # The selector is part of the key, as in reference-check REF-2: guard-egress and the pass-14 Monitor rows
  # wire one command under disjoint matchers on purpose. A missing matcher is the same selector as "".
  _wd="$TMP/wire-$1-$2"; mkcfg "$_wd" '{}'
  for _s in "$1" "$2"; do fi_run "$_s-install.sh" "$_wd" --apply >/dev/null 2>&1 || true; done
  _wl="$(jq -r '.hooks // {} | to_entries[] | .key as $e | .value[] | (.matcher // "") as $m | .hooks[]?.command | "\($e)|\($m)|\(.)"' "$_wd/settings.json" 2>/dev/null)"
  [ -n "$_wl" ] || { echo " (no hook was wired at all)"; return 0; }
  printf '%s\n' "$_wl" | sort | uniq -c | awk '$1 > 1 { $1=""; print }' || true
  chmod -R u+w "$_wd" 2>/dev/null || true
}
t_eq "WIRE-1: runtime-then-floor duplicates no hook" "" "$(dup_after runtime floor)"
t_eq "WIRE-1: floor-then-runtime duplicates no hook" "" "$(dup_after floor runtime)"

t_section "WIRE-3 (harbor#291): the Stop gate is wired ONLY when it is asked for"
stops() { jq -r --arg p "$2" '[.hooks.Stop[]?.hooks[]?.command // empty] | map(select(test($p))) | length' "$1/settings.json" 2>/dev/null; }
_sd_off="$TMP/wire3-off"; mkcfg "$_sd_off" '{}'
fi_run floor-install.sh "$_sd_off" --apply >/dev/null 2>&1 || true
t_eq "WIRE-3 a default install wires no Stop gate" 0 "$(stops "$_sd_off" guard-stop)"
t_eq "WIRE-3 a default install does not copy guard-stop.sh" no "$([ -f "$_sd_off/bin/guard-stop.sh" ] && echo yes || echo no)"
_sd_on="$TMP/wire3-on"; mkcfg "$_sd_on" '{}'
fi_run floor-install.sh "$_sd_on" --apply --with-stop-gate >/dev/null 2>&1 || true
t_eq "WIRE-3 --with-stop-gate wires exactly one Stop hook" 1 "$(stops "$_sd_on" guard-stop)"
t_eq "WIRE-3 --with-stop-gate copies guard-stop.sh" yes "$([ -f "$_sd_on/bin/guard-stop.sh" ] && echo yes || echo no)"
t_eq "WIRE-3 guard-stop.sh is installed executable" yes "$([ -x "$_sd_on/bin/guard-stop.sh" ] && echo yes || echo no)"
t_eq "WIRE-3 guard-stop.sh is content-pinned" yes "$([ -f "$_sd_on/.helm-pins/guard-stop.sh.sha256" ] && echo yes || echo no)"
_p3a="$(_x9sha < "$_sd_on/bin/guard-stop.sh" 2>/dev/null)"
t_eq "WIRE-3 the pin matches the installed bytes" "$(cat "$_sd_on/.helm-pins/guard-stop.sh.sha256" 2>/dev/null)" "${_p3a:-<no installed bytes>}"
fi_run floor-install.sh "$_sd_on" --apply --with-stop-gate >/dev/null 2>&1 || true
t_eq "WIRE-3 a re-apply keeps one Stop hook" 1 "$(stops "$_sd_on" guard-stop)"
fi_run runtime-install.sh "$_sd_on" --apply >/dev/null 2>&1 || true
t_eq "WIRE-3 runtime-install leaves the Stop gate wiring alone" 1 "$(stops "$_sd_on" guard-stop)"
t_eq "WIRE-3 the gate does not displace runtime-install's own Stop hook" 1 "$(stops "$_sd_on" memory-harvest)"
chmod -R u+w "$_sd_off" "$_sd_on" 2>/dev/null || true

t_section "WIRE-2 (harbor#95): every command these tools PRINT is one their own gate accepts"
# No printed self-invocation, in any phase, names the live dir positionally or omits --live.
w2_offenders() { # <output> <live-dir> → offending lines; empty means clean
  printf '%s\n' "$1" | grep -Ee 'sh [^ ]*(floor-install|floor-uninstall|floor-deny|sec0-harden|deploy)\.sh' | grep -v 'usage:' \
    | while IFS= read -r _l; do
        case "$_l" in
          *"$2"*)   printf '    names the live dir positionally: %s\n' "$_l" ;;
          *--live*) ;;
          *)        printf '    omits --live: %s\n' "$_l" ;;
        esac
      done
}
_wn=0
for _m in floor-install.sh floor-uninstall.sh sec0-harden.sh floor-deny.sh; do
  for _phase in dry apply; do
    _wn=$((_wn+1)); _wh="$TMP/wire2/h$_wn.$_phase"  # never named after the tool: its hook paths would match
    chmod -R u+w "$_wh" 2>/dev/null || true; rm -rf "$_wh"
    mkcfg "$_wh/.claude" '{"permissions":{"deny":[]}}'
    [ "$_phase" = dry ] && _wa="" || _wa="--apply"
    _out="$(env HOME="$_wh" CLAUDE_CONFIG_DIR="$_wh/.claude" sh "$SRC/$_m" --live $_wa 2>&1 || true)"
    t_eq "WIRE-2: $_m ($_phase) prints only commands its own gate accepts" "" "$(w2_offenders "$_out" "$_wh/.claude")"
    # A live apply goes through deploy (install standard §4), an uninstall too (#808); the rest keep their own.
    case "$_m" in floor-install.sh) _w2c=floor ;; floor-uninstall.sh) _w2c='floor --uninstall' ;; sec0-harden.sh) _w2c=sec0 ;; *) _w2c='' ;; esac
    if [ "$_phase" = dry ] && [ -n "$_w2c" ]; then
      t_has "WIRE-2: $_m's live dry-run hint is deploy --only $_w2c, with --live" "$_out" "deploy.sh' --apply --only $_w2c --live"
    elif [ "$_phase" = dry ]; then
      t_exit "WIRE-2: $_m prints a dry-run hint" 0 \
        sh -c 'printf "%s\n" "$1" | grep -Eq "sh [^ ]*$2\.sh .*--apply"' _ "$_out" "${_m%.sh}"
    fi
  done
done
# The converse: an ordinary sandbox target gets a hint naming that target. The install-lib tools,
# floor-deny among them since harbor#800, print it as `next: … --dir '<physical path>'`.
_w2s="$TMP/wire2/sandbox"; rm -rf "$_w2s"; mkcfg "$_w2s" '{"permissions":{"deny":[]}}'
for _m in floor-install.sh floor-uninstall.sh sec0-harden.sh floor-deny.sh; do
  _w2o="$(fi_run "$_m" "$_w2s" 2>/dev/null)"
  # The hint is the first printed self-invocation with --apply; install-lib tools name the PHYSICAL target.
  _w2h="$(printf '%s\n' "$_w2o" | grep -m1 -E "sh [^ ]*${_m%.sh}\.sh .*--apply" || true)"
  t_eq "WIRE-2: $_m's sandbox dry-run hint names the target" yes \
    "$(case "$_w2h" in (*"'$(phys "$_w2s")'"*|*"'$_w2s'"*|*" $_w2s "*|*" $_w2s") echo yes ;; (*) echo "no: ${_w2h:-<no hint>}" ;; esac)"
done

t_section "G516 (harbor#516): the installed backstop denies a refused merge from a \$HOME project dir"
# Runs the command floor-install wired, not the script: absent wiring leaves nothing to run.
G5="$TMP/g516"; G5P="$G5/port"; G5G="$G5P/gov"; G5H="$G5/home"; mkdir -p "$G5G/bin" "$G5H"
mkcfg "$G5/cfg" "$PERM" $SCANNERS
fi_run floor-install.sh "$G5/cfg" --apply >/dev/null 2>&1 || true
git -C "$G5G" init -q; git -C "$G5G" remote add origin https://github.com/Own/Gov.git
mkdir -p "$G5/cfg/inject.d"; printf 'gov\t%s\tfixture\n' "$G5G" > "$G5/cfg/inject.d/projects.tsv"
printf '#!/usr/bin/env sh\necho "REFUSED  a check is not passing on #7"\nexit 1\n' > "$G5G/bin/merge-check.sh"
_g5c="$(jq -r '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[].command | select(test("govern-hook"))][0] // empty' "$G5/cfg/settings.json")"
_g5o="$(jq -n --arg c "$G5H" '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$c,tool_input:{command:"gh pr merge 7 -R Own/Gov --squash"}}' \
  | CLAUDE_PROJECT_DIR="$G5H" CLAUDE_CONFIG_DIR="$G5/cfg" PORT_ROOT="$G5P" sh -c "${_g5c:-exit 0}" 2>/dev/null)"
t_has "G516 floor-install wired govern-hook --box under Bash" "$_g5c" 'govern-hook.sh --box'
t_has "G516 the wired command denies a refused merge from a \$HOME session" "$_g5o" '"permissionDecision":"deny"'

t_section "one decider per command class (harbor#954 item 8, from #1004)"
# controls.tsv names each class's decider as the engine of admission.class-<class>. A second row
# (admission.class-<class>.<x>) or a second engine in the cell is a second decider. The probe proves
# the registered engine is the only PreToolUse(Bash) decider floor-install wires that answers it.
_cc_reg="$HROOT/standards/naming/controls.tsv"; _cc_dir="$TMP/cc-proj"; mkdir -p "$_cc_dir"
_cc_bash="$(sed -n "/^floor_hooks() { cat <<'ROWS'/,/^ROWS\$/p" "$SRC/floor-install.sh" \
  | awk -F';' '$1 == "PreToolUse" && ("|" $2 "|") ~ /[|]Bash[|]/ { sub(/^floor-hook[.]sh /, "", $3); print $3 }' | sort -u)"
t_has "the wired Bash deciders were parsed from floor-install.sh (else the parser broke, not the rule)" "$_cc_bash" guard-cloud.sh
_cc_answers() { # <json> -> each wired Bash decider that asks, denies or blocks on it, space-separated
  printf '%s\n' "$_cc_bash" | while IFS= read -r _g; do
    _s="${_g%% *}"; _a=''; [ "$_s" = "$_g" ] || _a="${_g#* }"
    _o="$(cd "$_cc_dir" && printf '%s' "$1" | CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$_cc_dir" HOME="$TMP/.no-home" \
      PORT_ROOT="$TMP/.no-port-root" sh "$CFG/bin/$_s" $_a 2>/dev/null)"; _rc=$?
    _d="$(printf '%s' "$_o" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
    if [ "$_rc" -ne 0 ] || [ "$_d" = ask ] || [ "$_d" = deny ]; then echo "$_s"; fi
  done | sort -u | tr '\n' ' ' | sed 's/ $//'
}
while IFS='|' read -r _cc _cp; do
  _eng="$(awk -F'\t' -v c="admission.class-$_cc" '$1 == c || index($1, c ".") == 1 { print $4 }' "$_cc_reg" \
    | tr ',' '\n' | awk 'NF && $0 != "-"' | sort -u)"
  t_eq "class $_cc has exactly one decider registered in controls.tsv" 1 "$(printf '%s' "$_eng" | grep -c .)"
  t_eq "class $_cc is answered by its registered decider and no other wired one" "${_eng##*/}" \
    "$(_cc_answers "$(bash_j "$_cp")")"
done <<'CLASSES'
cloud-destroy|bq rm -f -t proj:ds.table
force-push|git push --force origin main
secret-read|cat ~/.ssh/id_rsa
deploy|sh bin/deploy.sh --apply --live
CLASSES

t_section "P13E-2: a veto that times out or crashes blocks the call (onFailure, harbor#1149)"
# A PreToolUse hook past its timeout does not block unless onFailure is set (code.claude.com/docs/en/hooks;
# probed 2026-10-16 on 2.1.301: `sleep 6` at timeout 2 blocked with it, ran without it).
_of_pre() { jq -r '[.hooks.PreToolUse[]?.hooks[]? | (.onFailure // "none")] | unique | join(",")' "$1/settings.json"; }
_of_rest() { jq -r '[.hooks | to_entries[] | select(.key != "PreToolUse") | .value[]?.hooks[]? | (.onFailure // "none")] | unique | join(",")' "$1/settings.json"; }
OF1="$TMP/onfail-on"; mkcfg "$OF1" "$PERM"
FLOOR_ONFAILURE=1 fi_run floor-install.sh "$OF1" --apply >/dev/null 2>&1 || true
t_eq "OF1 every PreToolUse veto carries onFailure block" block "$(_of_pre "$OF1")"
t_eq "OF1 ...and no other event does" none "$(_of_rest "$OF1")"
OF2="$TMP/onfail-off"; mkcfg "$OF2" "$PERM"
FLOOR_ONFAILURE=0 fi_run floor-install.sh "$OF2" --apply >/dev/null 2>&1 || true
t_eq "OF2 a client too old for the key gets none" none "$(_of_pre "$OF2")"
_of2n="$(jq '[.hooks.PreToolUse[]?.hooks[]?] | length' "$OF2/settings.json")"
FLOOR_ONFAILURE=1 fi_run floor-install.sh "$OF2" --apply >/dev/null 2>&1 || true
t_eq "OF3 a re-install sets it on hooks already wired" block "$(_of_pre "$OF2")"
t_eq "OF3 ...without wiring any of them twice" "$_of2n" "$(jq '[.hooks.PreToolUse[]?.hooks[]?] | length' "$OF2/settings.json")"

ff_sealed
t_done
