#!/usr/bin/env sh
# The floor suite, part b6 (harbor#727): B6, the fail-CLOSED SessionStart integrity gate. Its
# recovery messages must recover and must name the dir they measured (harbor#103, #110), its
# verified set is derived from the pins on disk (X15), the restore path is not a lockout (Q-R6),
# settings.json is watched as a file (harbor#221), and floor-verify cannot report a block it did
# not observe (VERIFY-1). Stateful: K1b's $B6 is SEAM-1's fixture.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/fixture.sh"
SCANNERS='admission-bash.sh admission-egress.sh admission-self-edit.sh annotate-web.sh pin-instructions.sh library-admission.sh admission-normalize.awk'
EMPTY_SETTINGS='{"permissions":{"allow":[],"deny":[],"disableBypassPermissionsMode":"disable","disableAutoMode":"disable"}}'
pinned_dir() { # <dir> — the scanners and B6 copied in, every scanner content-pinned, a bare deny
  mkdir -p "$1/bin" "$1/.helm-pins"
  for _g in $SCANNERS admission-integrity.sh; do cp "$SRC/$_g" "$1/bin/" 2>/dev/null; done
  printf '{"permissions":{"deny":[]}}' > "$1/settings.json"
  for _g in $SCANNERS; do _x9sha < "$1/bin/$_g" > "$1/.helm-pins/$_g.sha256"; done
}
b6msg() { # <cfg> — the systemMessage B6 emits for that config dir
  CLAUDE_CONFIG_DIR="$1" sh "$1/bin/admission-integrity.sh" </dev/null 2>/dev/null | jq -r '.systemMessage // ""' 2>/dev/null
}
installed_b6() { # <dir> — a clean floor-install --with-b6 into an empty config dir
  mkdir -p "$1/bin"; printf '%s\n' "$EMPTY_SETTINGS" > "$1/settings.json"
  env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-install.sh" --dir "$1" --apply --with-b6 >/dev/null 2>&1
}
no_live() { # <text> — "live" if a recovery in it is aimed at --live, bare or shell-quoted
  case "$1" in (*" --live "*|*" --live"|*"'--live'"*) echo live ;; (*) echo sandbox ;; esac
}

t_section "X9 · a blocked session must be handed a recovery that RECOVERS"
X9="$TMP/x9"; pinned_dir "$X9"
printf '\n# content drift\n' >> "$X9/bin/library-admission.sh"
X9_CONTENT="$(b6msg "$X9")"
t_has "X9 content drift: the recovery names the content pin" "$X9_CONTENT" '.helm-pins'
t_hasnt "X9 content drift must not recommend admission-deny.sh, which never writes .helm-pins" "$X9_CONTENT" 'admission-deny.sh'
t_has "X9 content drift names WHICH file drifted" "$X9_CONTENT" 'library-admission.sh'
# Settings drift is the class admission-deny.sh does fix (harbor#103).
_x9sha < "$X9/bin/library-admission.sh" > "$X9/.helm-pins/library-admission.sh.sha256"
printf 'deliberately-not-a-hash\n' > "$X9/.sec0-baseline.sha256"
X9_SETTINGS="$(b6msg "$X9")"
t_has "X9 settings drift keeps the floor-deny recovery" "$X9_SETTINGS" 'admission-deny.sh'

t_section "X9b (harbor#110) · the recovery names the dir the verdict was measured on"
t_eq "X9b a sandbox verdict must not print a recovery aimed at LIVE" sandbox "$(no_live "$X9_SETTINGS")"
t_has "X9b the sandbox recovery names the sandbox it measured" "$X9_SETTINGS" "'$X9' --repin"
t_has "X9b ...as --dir, the only target form floor-deny takes (harbor#800)" "$X9_SETTINGS" "admission-deny.sh --dir '$X9' --repin"
# The discrimination half: when the config dir IS live, --live is the only spelling the tools take.
H110="$TMP/h110"; pinned_dir "$H110/.claude"
printf 'deliberately-not-a-hash\n' > "$H110/.claude/.sec0-baseline.sha256"
X9_LIVE="$(env HOME="$H110" CLAUDE_CONFIG_DIR="$H110/.claude" sh "$H110/.claude/bin/admission-integrity.sh" \
             </dev/null 2>/dev/null | jq -r '.systemMessage // ""' 2>/dev/null)"
t_has "X9b a LIVE verdict keeps the --live spelling those tools require" "$X9_LIVE" "admission-deny.sh '--live' --repin"
t_has "X9b a LIVE verdict names deploy-restore.sh --live" "$X9_LIVE" "deploy-restore.sh '--live'"
t_has "X9b ...in the form deploy-restore.sh's gate takes: --live --apply (harbor#765)" "$X9_LIVE" "deploy-restore.sh '--live' --apply"
# session-verdicts.sh prints the same idiom; its live spelling is shell-quoted, so the bare
# forms alone could never match (the legacy negative was blind to it). Positive control first.
t_has "X9b session-verdicts on the LIVE dir names --live (the needle below can appear)" \
  "$(env HOME="$H110" CLAUDE_CONFIG_DIR="$H110/.claude" sh "$T_ROOT/hooks/session-verdicts/session-verdicts.sh" 2>/dev/null)" "'--live' --repin"
SV110="$(env HOME="$H110" CLAUDE_CONFIG_DIR="$X9" sh "$T_ROOT/hooks/session-verdicts/session-verdicts.sh" 2>/dev/null || true)"
t_eq "X9b session-verdicts must not print a LIVE recovery from a sandbox" sandbox "$(no_live "$SV110")"
t_has "X9b ...its sandbox re-pin is --dir spelled, the only target form floor-deny takes (harbor#800)" "$SV110" "admission-deny.sh --dir '$X9' --repin"

t_section "X15 (2026-08-14): what B6 verifies is DERIVED from the pins on disk"
X15="$TMP/x15"; installed_b6 "$X15"
t_eq "X15 a CLEAN --with-b6 install is silent" "" "$(b6msg "$X15")"
for _g in admission-cloud.sh admission-destroy.sh admission-deliverables.sh; do
  cp "$X15/bin/$_g" "$X15/bin/$_g.keep"
  printf '#!/usr/bin/env sh\n[ "${HELM_DISABLE_FLOOR:-0}" = "1" ] && exit 0\nexit 0\n' > "$X15/bin/$_g"
  t_has "X15 gutting $_g to 'exit 0' reaches B6 through its pin" "$(b6msg "$X15")" "$_g"
  mv "$X15/bin/$_g.keep" "$X15/bin/$_g"
done
t_eq "X15 restoring the guards clears the verdict" "" "$(b6msg "$X15")"
# Unwiring is cheaper than editing; gated on the pin so an older box is not false-alarmed.
jq 'del(.hooks.PreToolUse[]?.hooks[]? | select(.command | test("admission-cloud")))' \
   "$X15/settings.json" > "$X15/s.tmp" && mv "$X15/s.tmp" "$X15/settings.json"
env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-deny.sh" --dir "$X15" --repin >/dev/null 2>&1
t_has "X15 admission-cloud.sh unwired from PreToolUse(Bash) is reported" "$(b6msg "$X15")" 'admission-cloud.sh'
rm -f "$X15/.helm-pins/admission-cloud.sh.sha256" "$X15/bin/admission-cloud.sh"
t_eq "X15 an install with no guard-cloud pin is not blocked for a guard it never had" absent \
  "$(case "$(b6msg "$X15")" in (*admission-cloud.sh*) echo present ;; (*) echo absent ;; esac)"
# Every pinned file carries the kill-switch or is in B6's NO-KILLSWITCH case, read from the source.
_x15_exempt="$(grep -A1 'NO-KILLSWITCH' "$SRC/admission-integrity.sh" | tail -1 \
                 | tr '|)' '\n\n' | sed 's/^[[:space:]]*//' | grep -E '\.(sh|awk)$' | sort -u)"
_x15_naked=""
for _pf in "$X15"/.helm-pins/*.sha256; do
  [ -f "$_pf" ] || continue
  _g="${_pf##*/}"; _g="${_g%.sha256}"
  [ "$_g" = "admission-integrity.sh" ] && continue
  case " $(echo $_x15_exempt) " in *" $_g "*) continue ;; esac
  [ -f "$SRC/$_g" ] || continue
  _l="$(grep -vE '^[[:space:]]*(#|$)' "$SRC/$_g" 2>/dev/null | grep -vE '^#!' | head -1)"
  case "$_l" in *HELM_DISABLE_FLOOR*) ;; *) _x15_naked="$_x15_naked $_g" ;; esac
done
t_eq "X15 every pinned file carries a kill-switch or is in B6's exemption case" "" "$_x15_naked"
_x15_en="$(printf '%s\n' "$_x15_exempt" | grep -c .)"
t_eq "X15 B6's kill-switch exemption case is readable (>= 6 entries), or the loop above is vacuous" yes \
  "$([ "$_x15_en" -ge 6 ] && echo yes || echo "no ($_x15_en)")"
# harbor#110's second half: a content drift on a SANDBOX must not say deploy-restore.sh --live.
X15S="$TMP/x15sbx"; installed_b6 "$X15S"
printf '\n# drift\n' >> "$X15S/bin/admission-bash.sh"
X15S_MSG="$(b6msg "$X15S")"
t_eq "X15 a sandbox content drift names deploy-restore.sh, never deploy-restore.sh --live (harbor#110)" sandbox \
  "$(case "$X15S_MSG" in (*"deploy-restore.sh '--live'"*|*"deploy-restore.sh --live"*) echo live ;; (*deploy-restore.sh*) echo sandbox ;; (*) echo none ;; esac)"
t_has "X15 the content-drift recovery names the measured dir, shell-quoted" "$X15S_MSG" "'$X15S'/bin/deploy-restore.sh"
t_has "X15 ...as --dir, since deploy-restore.sh takes no positional target (harbor#765)" "$X15S_MSG" "deploy-restore.sh --dir '$X15S' --apply"
# The installer's report must widen with the gate: runtime-install replacing a pinned deploy-restore.sh.
X15R="$TMP/x15rt"; installed_b6 "$X15R"
cp "$SRC/deploy-restore.sh" "$X15R/bin/deploy-restore.sh"
printf '\n# an older release\n' >> "$X15R/bin/deploy-restore.sh"
_x9sha < "$X15R/bin/deploy-restore.sh" > "$X15R/.helm-pins/deploy-restore.sh.sha256"
X15R_OUT="$(env -u CLAUDE_CONFIG_DIR sh "$SRC/deploy-runtime-install.sh" --dir "$X15R" --apply 2>&1 || true)"
t_has "X15 runtime-install names the PINNED deploy-restore.sh it replaced (a note: floor-install re-pins it, harbor#285)" "$X15R_OUT" 'content pins behind for: deploy-restore.sh'
t_has "X15 B6 actually blocks on the deploy-restore.sh the installer warned about" "$(b6msg "$X15R")" 'deploy-restore.sh'
# floor-verify fires guard-cloud and guard-destroy (cli.md: firing every guard is its job), red-green.
X15V="$(cd -P "$TMP" && pwd -P)/x15v"; installed_b6 "$X15V"  # physical: floor-verify reports the dir it resolved
X15V_OUT="$(env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-verify.sh" --dir "$X15V" 2>&1 || true)"
t_eq "X15 floor-verify fires admission-cloud.sh" yes \
  "$(case "$X15V_OUT" in (*decides*"BigQuery table delete"*) echo yes ;; (*) echo no ;; esac)"
t_eq "X15 floor-verify fires admission-destroy.sh" yes \
  "$(case "$X15V_OUT" in (*decides*"diskutil wipe"*) echo yes ;; (*) echo no ;; esac)"
for _g in admission-cloud.sh admission-destroy.sh; do
  printf '#!/usr/bin/env sh\n[ "${HELM_DISABLE_FLOOR:-0}" = "1" ] && exit 0\nexit 0\n' > "$X15V/bin/$_g"
done
X15V_GUT="$(env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-verify.sh" --dir "$X15V" 2>&1 || true)"
t_has "X15 floor-verify fails the decides() probe on two gutted guards (№2.10)" "$X15V_GUT" 'NO DECISION'
t_has "X15 floor-verify's verdict line honours its own failed probes" "$X15V_GUT" 'FLOOR IS NOT FULLY ON'

t_section "X13 (2026-08-03): a blocked gate may only name commands that exist"
_x13_payload=" $(echo $(ff_payload)) "
# $CFGQ? — the quoted spelling counts too (harbor#110's second half).
_x13_bad=""
for _r in $(grep -oE '\$CFGQ?/bin/[a-z0-9-]+\.sh' "$SRC/admission-integrity.sh" | sed 's#.*/##' | sort -u); do
  case "$_x13_payload" in *" $_r "*) ;; *) _x13_bad="$_x13_bad $_r" ;; esac
done
t_eq "X13 every \$CFG/bin script admission-integrity.sh names is in an installer payload" "" "$_x13_bad"
_x13_n="$(grep -oE '\$CFGQ?/bin/[a-z0-9-]+\.sh' "$SRC/admission-integrity.sh" | sed 's#.*/##' | sort -u | grep -c .)"
t_eq "X13 the recovery-path scan still reaches >= 3 scripts, or the check above is vacuous" yes \
  "$([ "${_x13_n:-0}" -ge 3 ] && echo yes || echo "no (${_x13_n:-0})")"
# --apply re-adds the whole B1 set and resurrects withdrawn entries; re-pinning is --repin. Code only.
t_exit "X13 admission-integrity.sh must not tell the operator to re-pin with --apply" 1 \
  sh -c 'grep -v "^[[:space:]]*#" "$1" | grep -q "admission-deny\.sh --live --apply"' _ "$SRC/admission-integrity.sh"
for _x13p in bin/admission-integrity.sh hooks/session-verdicts/session-verdicts.sh; do _x13="${_x13p##*/}"
  t_exit "X13 $_x13 names the re-pin command its twin prints" 0 grep -q 'bin/admission-deny\.sh \$TGTQ --repin' "$T_ROOT/$_x13p"
  t_exit "X13 $_x13 resolves the recovery target against the live dir" 0 grep -q 'TGT="--live"' "$T_ROOT/$_x13p"
  t_exit "X13 $_x13 shell-quotes the path it prints (PR #113)" 0 grep -q '_shq()' "$T_ROOT/$_x13p"
done
X13SP="$TMP/x13 space/.claude"; pinned_dir "$X13SP"
printf 'deliberately-not-a-hash\n' > "$X13SP/.sec0-baseline.sha256"
t_has "X13 a config dir containing a space is pasted quoted" "$(b6msg "$X13SP")" "'$X13SP'"
# A pasted recovery must name a file the session cannot edit; an installer line — deploy.sh, the one
# live entry since harbor#800, counts as one — may name the checkout only beside
# `git -C ~/port/harbor diff --quiet` ON THAT LINE (git status --short always exits 0).
for _sv in admission-integrity.sh session-verdicts.sh; do
  _x13_ck="$(grep -v '^[[:space:]]*#' "$(t_src "$_sv")" | grep -E '(~|\$HOME)/(port/)?harbor/bin/[a-z0-9-]+\.sh' || true)"
  _x13_n="$(printf '%s\n' "$_x13_ck" | grep -c . || true)"
  if [ -z "$_x13_ck" ]; then _x13_v=clean
  elif [ "$_x13_n" = "$(printf '%s\n' "$_x13_ck" | grep -E '(install|deploy)\.sh' | grep -c 'git -C ~/port/harbor diff --quiet' || true)" ]; then _x13_v=clean
  else _x13_v="unchecked: $_x13_ck"; fi
  t_eq "X13 $_sv names no checkout script without an integrity check (5/5 writes allowed there)" clean "$_x13_v"
done

t_section "QA PLAN Q-R6: the restore path is not a lockout"
QW="$TMP/qa-recover"; mkdir -p "$QW/bin"; printf '%s' "$EMPTY_SETTINGS" > "$QW/settings.json"
for _g in library-admission.sh admission-normalize.awk admission-self-edit.sh admission-bash.sh admission-egress.sh annotate-web.sh \
          admission-integrity.sh admission-deny.sh admission-install.sh deploy-restore.sh deploy-harden.sh; do
  cp "$SRC/$_g" "$QW/bin/" 2>/dev/null
done
env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-install.sh" --dir "$QW" --apply --with-b6 >/dev/null 2>&1
# deploy's snapshot in deploy's format, over deploy's own SNAP_SET (baseline-pin is retired, harbor#765).
_qs="$QW/backups/deploy-20260101-000000-1"; mkdir -p "$_qs"
_qset="$(sed -n "s/^SNAP_SET='\(.*\)'$/\1/p" "$SRC/deploy.sh")"
set -f; printf '%s\n' $_qset > "$_qs/set.txt"; set +f
_qp=''; while IFS= read -r _e; do for _p in "$QW"/$_e; do [ -e "$_p" ] && _qp="$_qp ${_p##*/}"; done; done < "$_qs/set.txt"
(cd "$QW" && tar -czf "$_qs/config.tgz" $_qp)
printf '%s backups/deploy-20260101-000000-1/config.tgz 2026-01-01T00:00:00Z set=%s\n' \
  "$(_x9sha < "$_qs/config.tgz")" "$(_x9sha < "$_qs/set.txt")" >> "$QW/.helm-snapshots"  # deploy's ledger row (harbor#769)
_arcls="$(tar -tzf "$_qs/config.tgz" 2>/dev/null)"
t_has "Q-R6 deploy's snapshot holds .helm-pins" "$_arcls" '.helm-pins'
t_has "Q-R6 deploy's snapshot holds .helm-floor-teeth" "$_arcls" '.helm-floor-teeth'
rm -rf "$QW/.helm-pins" "$QW/.helm-floor-teeth"; printf 'garbage' > "$QW/settings.json"
env -u CLAUDE_CONFIG_DIR sh "$SRC/deploy-restore.sh" --apply --dir "$QW" >/dev/null 2>&1
t_eq "Q-R6 after restore the integrity gate does not block (recovery is not a lockout)" "" \
  "$(printf '{"hook_event_name":"SessionStart"}' | CLAUDE_CONFIG_DIR="$QW" sh "$QW/bin/admission-integrity.sh" 2>/dev/null)"

t_section "K1b: B6 integrity gate (fail-CLOSED SessionStart)"
# exit 2 does not block at SessionStart; {"continue": false} on stdout is the only hard stop.
B6="$TMP/b6"; mkdir -p "$B6/bin"; printf '%s\n' "$EMPTY_SETTINGS" > "$B6/settings.json"
for _g in library-admission.sh admission-normalize.awk admission-self-edit.sh admission-bash.sh admission-egress.sh annotate-web.sh \
          admission-deny.sh admission-install.sh admission-integrity.sh; do
  cp "$SRC/$_g" "$B6/bin/$_g"
done
chmod +x "$B6"/bin/*.sh
env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-install.sh" --dir "$B6" --apply >/dev/null 2>&1
b6run() { printf '{"hook_event_name":"SessionStart","source":"startup"}' \
  | CLAUDE_CONFIG_DIR="$B6" sh "$B6/bin/admission-integrity.sh" 2>/dev/null; }
b6cont() { b6run | jq -r '.continue' 2>/dev/null; }
b6edit() { jq "$1" "$B6/settings.json" > "$B6/s.tmp" && mv "$B6/s.tmp" "$B6/settings.json"; }  # <jq filter>
not_false() { case "$1" in (false) echo false ;; (*) echo 'not false' ;; esac; }
t_eq "K1b B6 is silent on a clean state" "" "$(b6run)"
b6edit '.permissions.deny = []'
t_eq "K1b B6 blocks after the deny array is tampered" false "$(b6cont)"
env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-deny.sh" --dir "$B6" --apply >/dev/null 2>&1
t_eq "K1b B6 is silent once the baseline is re-pinned" "" "$(b6run)"
printf '#!/bin/sh\nexit 0\n' > "$B6/bin/admission-bash.sh"
t_eq "K1b B6 blocks after a guard is neutered" false "$(b6cont)"
cp "$SRC/admission-bash.sh" "$B6/bin/admission-bash.sh"
b6edit 'del(.hooks.PreToolUse)'
t_eq "K1b B6 blocks after the floor hooks are unwired" false "$(b6cont)"
t_eq "K1b HARBOR_ADMISSION_DISABLE=1 opens the gate even with drift present" "" \
  "$(printf '{}' | HARBOR_ADMISSION_DISABLE=1 CLAUDE_CONFIG_DIR="$B6" sh "$B6/bin/admission-integrity.sh" 2>/dev/null)"

t_section "SEAM-1 (harbor#221): B6 owns settings.json as a FILE, not four fields"
# Rebuilt, not inherited: K1b ends with PreToolUse deleted.
env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-install.sh" --dir "$B6" --apply >/dev/null 2>&1
env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-deny.sh" --dir "$B6" --apply >/dev/null 2>&1
t_eq "SEAM-1 the fixture starts clean" "" "$(b6run)"
b6edit '.permissions.allow += ["Bash(curl:*)"]'
t_has "SEAM-1 an allow entry added outside Edit is seen (the 2026-08-16 seam)" "$(b6run)" "outside the floor's teeth"
t_eq "SEAM-1 an allow entry is advisory, never a hard stop (§2.11)" 'not false' "$(not_false "$(b6cont)")"
env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-deny.sh" --dir "$B6" --repin >/dev/null 2>&1
t_eq "SEAM-1 silent after the baseline is re-pinned" "" "$(b6run)"
b6edit '.autoMode = {"enabled":true}'
t_has "SEAM-1 a NEW TOP-LEVEL KEY is seen" "$(b6run)" "outside the floor's teeth"
env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-deny.sh" --dir "$B6" --repin >/dev/null 2>&1
t_eq "SEAM-1 silent after re-pin over the new key" "" "$(b6run)"
b6edit '.permissions.defaultMode = "bypassPermissions"'
t_has "SEAM-1 a changed permissions.defaultMode is reported" "$(b6run)" "outside the floor's teeth"
env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-deny.sh" --dir "$B6" --repin >/dev/null 2>&1
b6edit '.permissions.deny = []'
t_eq "SEAM-1 an emptied deny array still HARD STOPS (the teeth tier is unchanged)" false "$(b6cont)"
env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-deny.sh" --dir "$B6" --apply >/dev/null 2>&1
t_eq "SEAM-1 clean again after the teeth test" "" "$(b6run)"
b6edit '.enabledPlugins = {"acme@marketplace":true}'
t_eq "SEAM-1 a plugin install does not block the session (red-team pass 3)" 'not false' "$(not_false "$(b6cont)")"
t_has "SEAM-1 a plugin install is still reported" "$(b6run)" "outside the floor's teeth"
env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-deny.sh" --dir "$B6" --repin >/dev/null 2>&1
# Pin with the WRITER, check with the GUARD. sec0-harden takes --dir now; CLAUDE_CONFIG_DIR must agree with it.
# $B6's settings.json has never held an `env` key (EMPTY_SETTINGS has none): this is also harbor#816's
# first-time case — a NEW top-level key sec0-harden adds itself, re-pinned by the same apply that added it.
CLAUDE_CONFIG_DIR="$B6" sh "$SRC/deploy-harden.sh" --apply --dir "$B6" >/dev/null 2>&1
t_eq "harbor#816: the four decided env keys are set" '1 1 1 1' \
  "$(jq -r '[.env.DISABLE_ERROR_REPORTING, .env.DISABLE_FEEDBACK_COMMAND, .env.CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY, .env.CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL] | @tsv' "$B6/settings.json" | tr '\t' ' ')"
t_eq "...and sec0-harden's own re-pin already covered the new env key: no B6 block right after apply, before floor-deny --repin" "" "$(b6run)"
env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-deny.sh" --dir "$B6" --repin >/dev/null 2>&1
t_eq "SEAM-1 the baseline a WRITER pins is the one the GUARD checks (lint F10's behavioural half)" "" "$(b6run)"

t_section "VERIFY-1: floor-verify cannot report a block it did not observe"
FV="$(cd -P "$TMP" && pwd -P)/fv"; mkdir -p "$FV/empty/bin"; printf '{}\n' > "$FV/empty/settings.json"
_fvo="$(env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-verify.sh" --dir "$FV/empty" 2>&1 || true)"
t_hasnt "VERIFY-1 no guard on disk: no block may be claimed" "$_fvo" 'blocks:'
t_has "VERIFY-1 an uninstalled guard says nothing was tested" "$_fvo" 'CANNOT PROBE'
# The header wording is named once (harbor#145, F9): the negative and its positive share it.
_FV_HDR='── floor-verify · '
mkdir -p "$FV/home/.claude/bin"; printf '{}\n' > "$FV/home/.claude/settings.json"
_fvl="$(env -u CLAUDE_CONFIG_DIR HOME="$FV/home" sh "$SRC/admission-verify.sh" --live 2>&1 || true)"
t_hasnt "VERIFY-1 --live is a flag, never the config dir" "$_fvl" "$_FV_HDR--live"
t_has "VERIFY-1 --live is \$HOME/.claude, the only way to name the live dir (harbor#800)" "$_fvl" "$_FV_HDR$FV/home/.claude"
t_exit "VERIFY-1 a CLAUDE_CONFIG_DIR naming another dir never picks the target: usage exit 2 (harbor#800)" 2 \
  env HOME="$FV/home" CLAUDE_CONFIG_DIR="$FV/empty" sh "$SRC/admission-verify.sh" --live
t_exit "VERIFY-1 a positional config dir is a usage error: there is none (harbor#800)" 2 env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-verify.sh" "$FV/empty"
t_exit "VERIFY-1 no target is a usage error: it is named, never implied" 2 env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-verify.sh"
t_exit "VERIFY-1 --apply is a usage error: floor-verify is read-only" 2 env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-verify.sh" --apply --dir "$FV/empty"
# The fix for the LIVE box is deploy, the one live entry (the install standard §4); a sandbox's is its installer.
t_has "VERIFY-1 a live box missing its guards is fixed by deploy's floor component (harbor#800)" "$_fvl" \
  "  fix: sh '$FV/home/port/harbor/bin/deploy.sh' --only floor --apply --live"
# drift-install.sh (install-drift.sh before W3) is the read-only drift check, not an installer.
t_eq "VERIFY-1 ...no live fix line runs an installer bare, where the sandbox's all do (the control)" "0 yes" \
  "$(printf '%s\n' "$_fvl" | grep '^  fix: ' | grep -v 'drift-install\.sh' | grep -c 'install\.sh') $([ "$(env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-verify.sh" --dir "$FV/empty" 2>&1 | grep '^  fix: ' | grep -c 'admission-install\.sh')" -gt 0 ] && echo yes || echo no)"
t_has "VERIFY-1 a live box without B1 is fixed by deploy too, not floor-deny run bare" \
  "$(printf '{"permissions":{"deny":[]}}\n' > "$FV/home/.claude/settings.json"; env -u CLAUDE_CONFIG_DIR HOME="$FV/home" sh "$SRC/admission-verify.sh" --live 2>&1 | grep -A1 '^  FAIL: B1:')" \
  "  fix: sh '$FV/home/port/harbor/bin/deploy.sh' --only floor --apply --live"
t_exit "VERIFY-1 an unknown option is the contract's usage exit 2" 2 sh "$SRC/admission-verify.sh" --nonesuch
t_exit "VERIFY-1 an absent config dir is floor-not-on (exit 1), not a usage error" 1 \
  env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-verify.sh" --dir "$TMP/no-such-config-dir"
# sh exits 2 on a syntax error too, so a broken guard used to read as a block.
mkdir -p "$FV/broken/bin"; printf '{}\n' > "$FV/broken/settings.json"
for _g in admission-bash.sh admission-egress.sh admission-self-edit.sh; do printf '#!/bin/sh\nif [ broken\n' > "$FV/broken/bin/$_g"; done
_fvb="$(env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-verify.sh" --dir "$FV/broken" 2>&1 || true)"
t_hasnt "VERIFY-1 a syntactically broken guard is not reported as blocking" "$_fvb" '  ok: blocks:'
t_has "VERIFY-1 a broken guard's exit 2 is told apart from a verdict" "$_fvb" '  FAIL: EXITED 2 WITHOUT BLOCKING'
t_eq "VERIFY-1 every FAIL is followed by its fix line (contracts/logging.md)" "$(printf '%s\n' "$_fvb" | grep -c '^  FAIL: ')" \
  "$(printf '%s\n' "$_fvb" | grep -A1 '^  FAIL: ' | grep -c '^  fix: ')"
t_has "VERIFY-1 ...and the fix reinstalls the floor at that dir, spelled for floor-install's gate" "$_fvb" \
  "  fix: sh $SRC/admission-install.sh --apply --dir '$FV/broken'"
t_eq "VERIFY-1 every line is a header, a TAG line or the summary" "" \
  "$(printf '%s\n' "$_fvb" | grep -vE '^(── floor-verify · |  (ok|FAIL|WARN|note|skip|fix): |floor-verify: [0-9]+ ok, [0-9]+ failed, [0-9]+ warnings$)')"
t_has "VERIFY-1 a fully installed fixture still reports a real block (№2.11)" \
  "$(env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-verify.sh" --dir "$CFG" 2>&1 || true)" '  ok: blocks: pipe-to-shell'

t_section "VERIFY-2 (harbor#767): a B6 block fails the verify; a B6 advisory does not"
V2="$(cd -P "$TMP" && pwd -P)/verify2"; installed_b6 "$V2"; cp "$V2/settings.json" "$TMP/v2.clean"
b6out() { CLAUDE_CONFIG_DIR="$1" sh "$1/bin/admission-integrity.sh" </dev/null 2>/dev/null; }
# The verdict is the line before the summary (contracts/logging.md: the summary ends every run).
fv2() { _v2="$(env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-verify.sh" --dir "$V2" 2>&1)"; _v2rc=$?; _v2last="$(printf '%s\n' "$_v2" | tail -2 | head -1)"; _v2sum="$(printf '%s\n' "$_v2" | tail -1)"; }
fv2
t_eq "VERIFY-2 CONTROL: a clean --with-b6 install verifies" "0 yes" \
  "$_v2rc $(case "$_v2" in (*'  ok: B6: installed, reports clean'*) echo yes ;; (*) echo no ;; esac)"
t_has "VERIFY-2 CONTROL: the verdict line is a note before the summary" "$_v2last" '  note: FLOOR IS ON'
t_has "VERIFY-2 CONTROL: ...and the summary says none failed, agreeing with exit 0" "$_v2sum" ' 0 failed, '
jq '.permissions.deny += ["Bash(verify2-planted-teeth-drift)"]' "$TMP/v2.clean" > "$V2/settings.json"
t_has "VERIFY-2 the planted teeth drift is a session-blocking verdict" "$(b6out "$V2")" '"continue":false'
fv2
t_eq "VERIFY-2 teeth drift: floor-verify exits 1" 1 "$_v2rc"
t_has "VERIFY-2 teeth drift: the block is a failing line" "$_v2" '  FAIL: B6 BLOCKS THE NEXT SESSION'
t_hasnt "VERIFY-2 teeth drift: the block is not an advisory" "$_v2" '  WARN: B6 reports drift'
t_eq "VERIFY-2 teeth drift: the fix under it is B6's own restore command" \
  "  fix: sh '$V2'/bin/deploy-restore.sh --dir '$V2' --apply" "$(printf '%s\n' "$_v2" | grep -A1 '^  FAIL: B6 BLOCKS' | sed -n 2p)"
t_has "VERIFY-2 teeth drift: the summary counts the failure" "$_v2sum" ' 1 failed, '
t_hasnt "VERIFY-2 teeth drift: the verdict is not FLOOR IS ON" "$_v2last" 'FLOOR IS ON'
t_has "VERIFY-2 teeth drift: the verdict names the block" "$_v2last" 'B6 WILL BLOCK THE NEXT SESSION'
t_has "VERIFY-2 teeth drift: the failing line keeps the recovery B6 gave" "$_v2" 'bin/deploy-restore.sh'
jq '. + {verify2PlantedKey: true}' "$TMP/v2.clean" > "$V2/settings.json"
t_has "VERIFY-2 a new top-level key is advisory-only drift" "$(b6out "$V2")" '"systemMessage"'
t_hasnt "VERIFY-2 …and no block" "$(b6out "$V2")" '"continue":false'
fv2
t_eq "VERIFY-2 advisory drift: floor-verify exits 0" 0 "$_v2rc"
t_has "VERIFY-2 advisory drift: reported as an advisory" "$_v2" '  WARN: B6 reports drift'
t_has "VERIFY-2 advisory drift: the verdict is FLOOR IS ON, with the advisory counted" "$_v2last" 'FLOOR IS ON'
cp "$TMP/v2.clean" "$V2/settings.json"; cp "$V2/bin/admission-integrity.sh" "$TMP/v2.gi"
printf '#!/bin/sh\necho "not a verdict"\n' > "$V2/bin/admission-integrity.sh"
fv2
t_eq "VERIFY-2 output that is no verdict fails: it cannot be ruled out as a block" "1 yes" \
  "$_v2rc $(case "$_v2" in (*'  FAIL: B6 printed output that is not a verdict'*) echo yes ;; (*) echo no ;; esac)"
cp "$TMP/v2.gi" "$V2/bin/admission-integrity.sh"

t_section "VERIFY-3 (harbor#767): a B6 that cannot run is never read as clean"
# guard-integrity's contract: exit 0 always, and silence IS the clean verdict. Silence from a gate
# that crashed, exited non-zero or was killed is not that verdict.
v3() { # <label> <stub-body> <needle> — the stub replaces B6; floor-verify must fail and say why
  printf '#!/bin/sh\n%s\n' "$2" > "$V2/bin/admission-integrity.sh"; fv2
  t_eq "VERIFY-3 $1: floor-verify exits 1" 1 "$_v2rc"
  t_has "VERIFY-3 $1: a failing B6 line names what happened" "$_v2" "$3"
  t_hasnt "VERIFY-3 $1: it is not reported clean" "$_v2" 'B6: installed, reports clean'
  t_hasnt "VERIFY-3 $1: the verdict is not FLOOR IS ON" "$_v2last" 'FLOOR IS ON'
}
v3 "exit 3, no output" 'exit 3' '  FAIL: B6 exited 3'
v3 "a crash (syntax error)" 'if [ broken' '  FAIL: B6 exited 2'
# bash says `syntax error`, dash (ubuntu's /bin/sh) says `Syntax error`: fold case, same needle (harbor#865).
t_has "VERIFY-3 a crash: the failing line carries the shell's own error" "$(printf '%s' "$_v2" | tr 'A-Z' 'a-z')" 'syntax error'
v3 "killed by a signal" 'kill -KILL $$' '  FAIL: B6 was killed by signal 9'
v3 "garbage on stdout, exit 0" 'echo "{not json"' '  FAIL: B6 printed output that is not a verdict'
v3 "a clean-looking stdout with a non-zero exit" 'exit 1' '  FAIL: B6 exited 1'
cp "$TMP/v2.gi" "$V2/bin/admission-integrity.sh"; fv2
t_eq "VERIFY-3 CONTROL: the real B6 on the clean install still verifies" 0 "$_v2rc"
t_has "VERIFY-3 CONTROL: …and is the one reported clean (F9's positive control)" "$_v2" 'B6: installed, reports clean'

t_section "B6-SEP (install standard §3): B6 never reads .harbor-manifest, the record the installers write"
_code() { sed -e '/^[[:space:]]*#/d' -e 's/[[:space:]]#.*$//' "$1"; }
t_eq "B6-SEP admission-integrity.sh names no .harbor-manifest in its code" 0 "$(_code "$SRC/admission-integrity.sh" | grep -c 'harbor-manifest')"
t_eq "B6-SEP ...nor does the guard-lib it sources" 0 "$(_code "$SRC/library-admission.sh" | grep -c 'harbor-manifest')"
t_eq "B6-SEP ...and it does not source deploy-install-lib.sh, where the manifest's readers live" 0 \
  "$(_code "$SRC/admission-integrity.sh" | grep -cE '(^|[;&|[:space:]])\.[[:space:]]+[^;]*deploy-install-lib\.sh')"
SEP="$TMP/b6sep"; installed_b6 "$SEP"
sepv() { printf '{"hook_event_name":"SessionStart","source":"startup"}' | CLAUDE_CONFIG_DIR="$SEP" sh "$SEP/bin/admission-integrity.sh" 2>/dev/null; }
t_eq "B6-SEP the fixture's install wrote a manifest (so its absence below is a real change)" yes "$([ -s "$SEP/.harbor-manifest" ] && echo yes || echo no)"
V0="$(sepv)"
t_eq "B6-SEP a clean floor is silent" "" "$V0"
mv "$SEP/.harbor-manifest" "$SEP/manifest.saved"
t_eq "B6-SEP the same verdict with the manifest gone" "$V0" "$(sepv)"
printf 'garbage\n%s 100755 bin/admission-bash.sh floor-install deadbeef\n' "$(printf x | git hash-object --stdin)" > "$SEP/.harbor-manifest"
t_eq "B6-SEP ...and with a forged one" "$V0" "$(sepv)"
printf '#!/bin/sh\nexit 0\n' > "$SEP/bin/admission-bash.sh"
printf '%s 100755 bin/admission-bash.sh floor-install -\n' "$(git hash-object "$SEP/bin/admission-bash.sh")" > "$SEP/.harbor-manifest"
t_eq "B6-SEP a neutered guard still blocks when a forged row records its bytes as installed" false \
  "$(sepv | jq -r '.continue' 2>/dev/null)"

t_section "WIRE-960 (harbor#960): every hook command wired into the bin dir must name a file that runs"
# A wired file that is gone never runs. bash-as-sh (macOS) exits 127, which Claude Code reads as
# non-blocking: the hook is silently off. dash (Debian/Ubuntu) exits 2, a blocking error: every call refused.
WH="$TMP/w960"; W9="$WH/.claude"; installed_b6 "$W9"; cp "$W9/settings.json" "$TMP/w960.clean"
w9() { env HOME="$WH" CLAUDE_CONFIG_DIR="$W9" sh "${1:-$W9/bin/admission-integrity.sh}" </dev/null 2>/dev/null; }
w9c() { w9 "$@" | jq -r 'if has("continue") then (.continue|tostring) else "advisory" end' 2>/dev/null | grep . || echo silent; }
w9wire() { jq --arg c "$1" '.hooks.SessionStart += [{matcher:"", hooks:[{type:"command", command:$c}]}]' \
  "$TMP/w960.clean" > "$W9/settings.json"; }  # <command> — one extra SessionStart hook over the clean wiring
t_eq "WIRE-960 CONTROL: a clean --with-b6 install is silent" silent "$(w9c)"
# Probe 3 (research/07 T2): script and pin renamed together, settings.json still wires the old path.
mv "$W9/bin/admission-deliverables.sh" "$W9/bin/guard-filing.sh"
mv "$W9/.helm-pins/admission-deliverables.sh.sha256" "$W9/.helm-pins/guard-filing.sh.sha256"
t_eq "WIRE-960 the premise: the old wired command cannot run (127 under bash, 2 under dash)" dead \
  "$(printf '{}' | /bin/sh "$W9/bin/admission-deliverables.sh" >/dev/null 2>&1; rc=$?
     if [ "$rc" = 127 ] || [ "$rc" = 2 ]; then echo dead; else echo "ran: exit $rc"; fi)"
t_eq "WIRE-960 probe 3: script and pin renamed, old wiring left — the session is refused" false "$(w9c)"
W9MSG="$(w9 | jq -r .systemMessage)"
t_has "WIRE-960 probe 3: the refusal names the dangling path" "$W9MSG" "$W9/bin/admission-deliverables.sh"
t_has "WIRE-960 probe 3: the recovery names the wiring as a way out" "$W9MSG" "settings.json at its new path"
t_hasnt "WIRE-960 probe 3: ...and not floor-deny, which re-pins neither file nor wiring" "$W9MSG" 'admission-deny.sh'
sed "s#/bin/admission-deliverables.sh#/bin/guard-filing.sh#g" "$TMP/w960.clean" > "$W9/settings.json"
t_eq "WIRE-960 probe 3 CONTROL: rewired to the new name, it passes (the rename is not the fault)" silent "$(w9c)"
mv "$W9/bin/guard-filing.sh" "$W9/bin/admission-deliverables.sh"
mv "$W9/.helm-pins/guard-filing.sh.sha256" "$W9/.helm-pins/admission-deliverables.sh.sha256"
# The wrapper behind three guards (probe 1 case C), renamed with its pin.
cp "$TMP/w960.clean" "$W9/settings.json"
mv "$W9/bin/admission-hook.sh" "$W9/bin/floor-wrap.sh"; mv "$W9/.helm-pins/admission-hook.sh.sha256" "$W9/.helm-pins/floor-wrap.sh.sha256"
t_eq "WIRE-960 admission-hook.sh renamed with its pin, old wiring left — refused" false "$(w9c)"
mv "$W9/bin/floor-wrap.sh" "$W9/bin/admission-hook.sh"; mv "$W9/.helm-pins/floor-wrap.sh.sha256" "$W9/.helm-pins/admission-hook.sh.sha256"
# B6 itself, as far as it can see: run from a new name while settings.json wires the old one.
mv "$W9/bin/admission-integrity.sh" "$W9/bin/guard-integrity2.sh"
t_eq "WIRE-960 admission-integrity.sh wired but gone (B6 run from another name) — refused" false "$(w9c "$W9/bin/guard-integrity2.sh")"
mv "$W9/bin/guard-integrity2.sh" "$W9/bin/admission-integrity.sh"
t_eq "WIRE-960 CONTROL: restored, silent again" silent "$(w9c)"
# Unpinned hooks have no other net. Every spelling the boxes use: bare, quoted, $HOME, ~, a symlinked dir.
ln -s "$W9" "$TMP/w960link"
for _w in "/bin/sh $W9/bin/no-such-hook.sh" "/bin/sh \"$W9/bin/no-such-hook.sh\" --x" '/bin/sh "$HOME/.claude/bin/no-such-hook.sh"' \
          '/bin/sh ~/.claude/bin/no-such-hook.sh' "/bin/sh $TMP/w960link/bin/no-such-hook.sh" "$W9/bin/no-such-hook.sh"; do
  w9wire "$_w"; t_eq "WIRE-960 an unpinned wired hook that is missing is refused: $_w" false "$(w9c)"
done
: > "$W9/bin/empty-hook.sh"; w9wire "/bin/sh $W9/bin/empty-hook.sh"
t_eq "WIRE-960 a wired hook that is EMPTY exits 0 and checks nothing — refused" false "$(w9c)"
printf '#!/bin/sh\nexit 0\n' > "$W9/bin/noexec-hook.sh"; chmod 0644 "$W9/bin/noexec-hook.sh"
w9wire "$W9/bin/noexec-hook.sh"
t_eq "WIRE-960 a hook EXECUTED directly but not executable (exit 126) — refused" false "$(w9c)"
w9wire "/bin/sh $W9/bin/noexec-hook.sh"
t_eq "WIRE-960 CONTROL: the same file run through /bin/sh needs no exec bit — not refused (§2.11)" silent "$(w9c)"
w9wire "/bin/sh $TMP/elsewhere/no-such-hook.sh"
t_eq "WIRE-960 CONTROL: a hook outside the Harbor bin dir is not this gate's to judge" silent "$(w9c)"
cp "$TMP/w960.clean" "$W9/settings.json"

ff_sealed
t_done
