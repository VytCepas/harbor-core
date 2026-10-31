#!/usr/bin/env sh
# deploy installs the packs harbor.toml `packs` lists, through bin/pack.sh (harbor#1149). The REAL deploy.sh runs in the
# deploy suites' throwaway repo; pack.sh is a stub that logs its argv and refuses on PACK_STUB_REFUSE=dry|apply|both,
# in the line shape the real one prints (pack.sh's own behaviour is tests/scope/pack/pack.test.sh).
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset CLAUDECODE HARBOR_DEPLOY_ACTIVE HARBOR_DEPLOY
T_TMP="$(cd "$T_TMP" && pwd -P)"
. "$(dirname "$0")/../../install/deploy-fixture.sh"
PV="$T_TMP/pv"; mkdir -p "$PV"; HARBOR_SCOPE_PRIVATE="$PV"; export HARBOR_SCOPE_PRIVATE
PACK_STUB='#!/bin/sh
printf "pack.sh %s\n" "$*" >> "$STUB_LOG"
[ "${HARBOR_DEPLOY_ACTIVE:-${HARBOR_DEPLOY:-}}" = 1 ] || printf "pack.sh\n" >> "$STUB_LOG.nodeploy"
case " $* " in *" --apply "*) m=apply ;; *) m=dry ;; esac
if [ "${PACK_STUB_REFUSE:-}" = "$m" ] || [ "${PACK_STUB_REFUSE:-}" = both ]; then
  echo "  FAIL: skipped demo: dirty: harbor-pack/ has uncommitted or untracked changes"
  echo "  fix: commit or discard them in the pack repo"
  echo "pack: 0 ok, 1 failed, 0 warnings"; exit 1
fi
case "$1:$m" in remove:apply) [ -n "${PACK_STUB_KEEP:-}" ] || rm -rf "$HOME/.claude/.harbor-packs" "$HOME/.claude/checks.d" ;; esac
[ -z "${PACK_STUB_RECOMPOSE:-}" ] || [ "$m" != apply ] || printf "| demo row |\n" >> "$HOME/.claude/bin/docs/reference/checks.md"
echo "  ok: pack.sh stub ran ($1 $m)"; echo "pack: 1 ok, 0 failed, 0 warnings"'
packcase() { # <case> [listed]: a deploy fixture whose pack.sh is the stub above; harbor.toml lists "demo" unless told not
  fixture "$1"
  printf '%s\n' "$PACK_STUB" > "$REPO/bin/pack.sh"; chmod +x "$REPO/bin/pack.sh"; commit_push packstub
  if [ "${2-listed}" = listed ]; then printf 'packs = ["demo"]\n' > "$PV/harbor.toml"; else : > "$PV/harbor.toml"; fi
  unset PACK_STUB_REFUSE
}
# The installers' names in the order the APPLY ran them (the dry runs before it are not part of the order).
order() { sed -n '/ --apply/,$p' "$LOGF" | awk '{ print $1 }' | awk '!s[$0]++' | tr '\n' ' ' | sed 's/ $//'; }

t_section "harbor.toml packs: the dry run plans the pack install through pack.sh's own dry run"
packcase listed; run '' --live
t_eq "a dry run exits 0" 0 "$RC"
t_has "pack.sh ran its own dry run, on the live dir" "$(cat "$LOGF")" "pack.sh install --live"
t_has "...and its verdict is deploy's" "$(out)" "  ok: pack.sh: its dry run passes (1 pack(s) in harbor.toml)"
t_eq "nothing was applied" "" "$(applied)"

t_section "apply: packs install after inject (which rebuilds inject.d) and before the skill catalog"
packcase apply; run 'y\n' --apply --live
t_eq "the apply exits 0" 0 "$RC"
t_has "pack.sh installed with --apply" "$(applied)" "pack.sh install,"
t_exit "inject-install runs, then pack.sh, then skill-catalog.sh" 0 sh -c "echo '$(order)' | grep -q 'context-injection-install.sh pack.sh skill-catalog.sh'"
t_eq "every pack.sh run carried HARBOR_DEPLOY_ACTIVE=1" no "$(grep -q pack.sh "$T/calls.nodeploy" 2>/dev/null && echo yes || echo no)"

t_section "no packs key: no packs, with a note, and pack.sh is never run"
packcase nokey none; rm -f "$PV/harbor.toml"; run '' --live
t_eq "a dry run exits 0" 0 "$RC"
t_has "the note says why" "$(out)" "  note: packs: harbor.toml lists no packs (no packs key, or an empty one), so none are installed"
t_hasnt "pack.sh did not run" "$(cat "$LOGF")" "pack.sh"
printf 'packs = []\n' > "$PV/harbor.toml"; run '' --live
t_has "an empty list says the same" "$(out)" "harbor.toml lists no packs"
t_hasnt "...and pack.sh did not run" "$(cat "$LOGF")" "pack.sh"
rm -f "$PV/harbor.toml"; run 'y\n' --apply --live
t_eq "an apply with no key exits 0" 0 "$RC"
t_hasnt "...and does not run pack.sh" "$(cat "$LOGF")" "pack.sh"

t_section "a pack that refuses fails the deploy, and the failure names the pack and the refusal"
packcase refdry; PACK_STUB_REFUSE=dry; export PACK_STUB_REFUSE; run '' --live
t_eq "a refusing dry run exits 1" 1 "$RC"
t_has "the preflight failed" "$(out)" "PREFLIGHT FAILED"
t_has "the failure names the pack and the refusal" "$(out)" "pack.sh: its own dry run FAILED (rc=1), so its install would too: skipped demo: dirty: harbor-pack/ has uncommitted or untracked changes"
t_has "...and the pack's own fix line is relayed" "$(out)" "  fix: commit or discard them in the pack repo"
unset PACK_STUB_REFUSE; packcase refapply; PACK_STUB_REFUSE=apply; export PACK_STUB_REFUSE; run 'y\nn\n' --apply --live
t_eq "a pack refusing at apply time exits 1" 1 "$RC"
t_has "the install stops at pack.sh, with the refusal" "$(out)" "stopped at: pack.sh install --apply --live: skipped demo: dirty"
t_has "...and offers the snapshot back" "$(out)" "restore puts the config dir back as it was"
unset PACK_STUB_REFUSE

t_section "--only: inject rebuilds inject.d, so it re-runs the packs; skills alone does not"
packcase only; run '' --only inject --live
t_has "--only inject plans the packs" "$(cat "$LOGF")" "pack.sh install --live"
: > "$LOGF"; run '' --only skills --live
t_eq "--only skills does not" "" "$(grep pack.sh "$LOGF")"
: > "$LOGF"; run '' --only packs --live
t_has "--only packs runs only them" "$(cat "$LOGF")" "pack.sh install --live"
t_has "...and is a component" "$(out)" "only:       packs"

t_section "preflight: a note a pack installed is not 'bytes in no commit'"
packcase owned; printf 'pack note\n' > "$C/inject.d/pack-demo--n.md"
run '' --live
t_eq "without its manifest the file is refused" 1 "$RC"
t_has "...as bytes in no commit" "$(out)" "inject.d holds packs whose bytes are in no commit"
mkdir -p "$C/.harbor-packs"; printf '# repo\tdemo\nF\tinject.d/pack-demo--n.md\n' > "$C/.harbor-packs/demo.tsv"
run '' --live
t_eq "with the pack's manifest the same file passes" 0 "$RC"
t_has "...and inject.d is judged clean" "$(out)" "inject.d: every installed pack is one the repo holds or once held"
packcase ownednew; mkdir -p "$C/context-rules/user"; printf 'pack note\n' > "$C/context-rules/user/pack-demo--n.md"
run '' --live
t_has "the new box tier is judged too (harbor#1010)" "$(out)" "context-rules/user holds packs whose bytes are in no commit"
mkdir -p "$C/.harbor-packs"; printf '# repo\tdemo\nF\tcontext-rules/user/pack-demo--n.md\n' > "$C/.harbor-packs/demo.tsv"
run '' --live
t_has "...and passes with the pack's manifest" "$(out)" "context-rules/user: every installed pack is one the repo holds or once held"

t_section "uninstall: every installed pack goes with the floor, and the skill catalog is regenerated without them"
packcase unin; printf '#!/bin/sh\necho "  ok: stub floor-uninstall"\n' > "$REPO/bin/floor-uninstall.sh"; chmod +x "$REPO/bin/floor-uninstall.sh"
git -C "$REPO" add bin/floor-uninstall.sh; commit_push stubun
mkdir -p "$C/.harbor-packs" "$C/checks.d" "$C/skill-packs/topology"; printf '# repo\tdemo\nF\tchecks.d/demo.md\nF\tskill-packs/topology/demo.md\n' > "$C/.harbor-packs/demo.tsv"; printf 'rows\n' > "$C/checks.d/demo.md"
printf -- '---\npack: demo\n---\n' > "$C/skill-packs/topology/demo.md"
run '' --only floor --uninstall --live
t_eq "the uninstall dry run exits 0" 0 "$RC"
t_has "...names the packs that go with the floor" "$(out)" "packs installed here, removed with the floor: demo"
t_has "...through pack.sh's own dry run" "$(cat "$LOGF")" "pack.sh remove demo --live"
t_eq "...and removes nothing" yes "$([ -f "$C/checks.d/demo.md" ] && echo yes || echo no)"
run 'y\n' --only floor --uninstall --apply --live
t_eq "the uninstall apply exits 0" 0 "$RC"
SNAPD="$(ls -d "$C"/backups/deploy-* 2>/dev/null | head -1)"
t_has "the snapshot taken first holds the pack's manifest and fragment" "$(tar -tzf "$SNAPD/config.tgz" 2>/dev/null | tr '\n' ' ')" ".harbor-packs/demo.tsv"
t_has "...fragment included" "$(tar -tzf "$SNAPD/config.tgz" 2>/dev/null | tr '\n' ' ')" "checks.d/demo.md"
t_has "...and the pack file it put under skill-packs/, which a restore must put back" "$(tar -tzf "$SNAPD/config.tgz" 2>/dev/null | tr '\n' ' ')" "skill-packs/topology/demo.md"
t_has "pack.sh removed the pack" "$(cat "$LOGF")" "pack.sh remove demo --apply --live"
t_exit "...then the installed book was written from what is left" 0 sh -c "echo '$(order)' | grep -q 'pack.sh skill-catalog.sh'"
t_has "...by skill-catalog.sh install on the live dir" "$(grep '^skill-catalog.sh' "$LOGF")" "skill-catalog.sh install --apply --live"
t_eq "...and never reinstalled from the tracked file" 0 "$(grep -c 'skill-install.sh skill-catalog' "$LOGF")"
t_has "verify finds no pack left" "$(out)" "  ok: no pack is left: no manifest in .harbor-packs and no fragment in checks.d"
t_eq "no manifest remains" no "$([ -e "$C/.harbor-packs/demo.tsv" ] && echo yes || echo no)"
t_eq "no fragment remains" no "$([ -e "$C/checks.d/demo.md" ] && echo yes || echo no)"
packcase unin2; printf '#!/bin/sh\necho "  ok: stub floor-uninstall"\n' > "$REPO/bin/floor-uninstall.sh"; chmod +x "$REPO/bin/floor-uninstall.sh"
git -C "$REPO" add bin/floor-uninstall.sh; commit_push stubun2
mkdir -p "$C/.harbor-packs" "$C/checks.d"; printf '# repo\tdemo\nF\tchecks.d/demo.md\n' > "$C/.harbor-packs/demo.tsv"
PACK_STUB_REFUSE=apply; export PACK_STUB_REFUSE; run 'y\nn\n' --only floor --uninstall --apply --live
t_eq "a pack that will not come out fails the uninstall" 1 "$RC"
t_has "...naming the step" "$(out)" "stopped at: pack.sh remove --apply --live"
unset PACK_STUB_REFUSE
t_section "a harbor.toml that cannot be read fails the preflight, never reads as 'no packs'"
packcase badtoml; printf 'packz = ["demo"]\n' > "$PV/harbor.toml"; run '' --only packs --live
t_eq "the dry run exits 1" 1 "$RC"
t_has "...saying scope-roots.sh could not read it" "$(out)" "  FAIL: harbor.toml packs: scope-roots.sh could not read it (exit 2)"
t_eq "...and pack.sh did not run" "" "$(grep pack.sh "$LOGF")"
unset PACK_STUB_REFUSE
packcase unin3; printf '#!/bin/sh\necho "  ok: stub floor-uninstall"\n' > "$REPO/bin/floor-uninstall.sh"; chmod +x "$REPO/bin/floor-uninstall.sh"
git -C "$REPO" add bin/floor-uninstall.sh; commit_push stubun3
mkdir -p "$C/.harbor-packs" "$C/checks.d"; printf '# repo\tdemo\nF\tchecks.d/demo.md\n' > "$C/.harbor-packs/demo.tsv"; printf 'rows\n' > "$C/checks.d/demo.md"
PACK_STUB_KEEP=1; export PACK_STUB_KEEP; run 'y\nn\n' --only floor --uninstall --apply --live
t_eq "a removal that leaves a pack behind fails verify" 1 "$RC"
t_has "...naming the pack" "$(out)" "  FAIL: a pack is still installed after the removal: demo"
unset PACK_STUB_KEEP

t_section "the packs step recomposed bin/docs/reference/checks.md after runtime-install recorded it: runtime-install records it again (harbor#1044)"
# runtime-install's stub records bin/docs/reference/checks.md as it finds it (creating it once), as the real one records what it composed.
STUB_HOOK_deployruntimeinstallsh='f="$HOME/.claude/bin/docs/reference/checks.md"; m="$HOME/.claude/.harbor-manifest"; mkdir -p "${f%/*}"; [ -f "$f" ] || printf "core\n" > "$f"
b=$(git hash-object --no-filters "$f"); { grep -v " bin/docs/reference/checks.md " "$m" 2>/dev/null; printf "%s 100644 bin/docs/reference/checks.md runtime-install t\n" "$b"; } > "$m.new"; mv "$m.new" "$m"'
export STUB_HOOK_deployruntimeinstallsh
rr_applies() { grep -c '^deploy-runtime-install.sh .*--apply' "$LOGF"; }
packcase rerec; PACK_STUB_RECOMPOSE=1; export PACK_STUB_RECOMPOSE; run 'y\nn\n' --apply --live
t_eq "the apply exits 0" 0 "$RC"
t_eq "runtime-install applies twice" 2 "$(rr_applies)"
t_eq "...the second after pack.sh's apply" "pack.sh deploy-runtime-install.sh" "$(grep -E '^(pack\.sh install|deploy-runtime-install\.sh).*--apply' "$LOGF" | tail -2 | awk '{ print $1 }' | tr '\n' ' ' | sed 's/ $//')"
t_eq "the recorded blob is the installed register's" "$(git hash-object --no-filters "$C/bin/docs/reference/checks.md")" "$(awk '$3 == "bin/docs/reference/checks.md" { print $1 }' "$C/.harbor-manifest")"
t_has "...and deploy says why it ran it again" "$(out)" "running runtime-install again to record it"
unset PACK_STUB_RECOMPOSE
packcase rerec0; run 'y\nn\n' --apply --live
t_eq "control: a pack step that leaves bin/docs/reference/checks.md alone, runtime-install applies once" 1 "$(rr_applies)"
unset STUB_HOOK_deployruntimeinstallsh
t_done
