#!/usr/bin/env sh
# deploy.sh, the unified deploy (harbor#457, #646): preflight refusals, install order, the [y/N]
# gates, failure and restore, and the B8 re-pin split. The REAL deploy.sh runs in a throwaway
# repo whose installers are stubs that log their argv, beside the REAL deploy-restore.sh (harbor#765);
# prompts are answered through script(1). The stubs speak the install standard's line shape
# (contracts/logging.md) and the output contracts deploy reads (wave-b conventions §8).
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset CLAUDECODE HARBOR_DEPLOY  # a run inside a session or a deploy must not decide a case
T_TMP="$(cd "$T_TMP" && pwd -P)"  # deploy reports the config dir physically (install-lib's il_target)
. "$(dirname "$0")/../../install/deploy-fixture.sh"
need_pty

t_section "flags: [--apply] --live [--accept-loss], parsed by install-lib"
fixture flags
run '' --help; t_eq "--help" 0 "$RC"; t_has "--help prints the header" "$(out)" "DRY RUN"
run '' --bogus; t_eq "an unknown flag" 2 "$RC"
run '' --live --bogus; t_eq "an unknown flag after --live" 2 "$RC"
run '' --apply; t_eq "--apply without --live is a usage error: no target" 2 "$RC"
t_has "...naming both targets" "$(out)" "no target: give --live or --dir PATH"
t_eq "--apply without --live runs nothing (log bytes)" 0 "$(wc -c < "$LOGF" | tr -d ' ')"
run ''; t_eq "no arguments is a usage error: the target is named, never implied" 2 "$RC"
run '' --dir "$T_TMP"; t_eq "--dir is a usage error: deploy is live only" 2 "$RC"
t_has "...saying so" "$(out)" "deploy targets the live box only"
run '' --apply --live --dir "$C"; t_eq "--live with --dir is a usage error" 2 "$RC"
t_eq "no usage error ran anything (log bytes)" 0 "$(wc -c < "$LOGF" | tr -d ' ')"

t_section "dry run"
fixture dry; run '' --live
t_eq "a clean dry run" 0 "$RC"
t_has "a clean dry run passes preflight" "$(out)" "Preflight passed"
t_eq "a clean dry run applies nothing" "" "$(applied)"
t_has "it ends on deploy's summary line" "$(tail -1 "$T/out.txt")" "deploy: "
t_exit "...in the log-lib shape" 0 grep -qE '^deploy: [0-9]+ ok, 0 failed, [0-9]+ warnings$' "$T/out.txt"
t_has "its next step is the apply, which its own gate takes" "$(out)" "  note: next: sh '$REPO/bin/deploy.sh' --apply --live"
t_eq "no check-mark, cross, bar or bullet glyph in the output" 0 "$(grep -cE '✓|✗|│|•|!!' "$T/out.txt")"
t_eq "every line is a header, a TAG line, a summary or a log line" 0 \
  "$(grep -cvE '^(── [a-z0-9.-]+ · |  (ok|FAIL|WARN|note|skip|fix): |[A-Za-z0-9_.-]+: [0-9]+ ok, [0-9]+ failed, [0-9]+ warnings$|log: )' "$T/out.txt")"
t_has "the positive control: the output holds deploy's own TAG lines" "$(out)" "  ok: working tree clean"
t_eq "a dry run keeps no log file" no "$([ -d "$C/backups/deploy" ] && echo yes || echo no)"
t_eq "every child ran with HARBOR_DEPLOY=1 (#285)" no "$([ -s "$LOGF.nodeploy" ] && echo yes || echo no)"
t_has "the positive control: a stub run outside deploy records its missing HARBOR_DEPLOY" \
  "$(env -u HARBOR_DEPLOY STUB_LOG="$T/ctl" sh "$REPO/bin/context-injection-install.sh" >/dev/null; cat "$T/ctl.nodeploy")" context-injection-install.sh
t_eq "no child saw a CLAUDE_CONFIG_DIR" no "$([ -s "$LOGF.rehearse" ] && echo yes || echo no)"
t_eq "constitution-install's own dry run replaces the rehearsal on a copy" "policy-constitution-install.sh --live" \
  "$(grep '^policy-constitution-install.sh' "$LOGF")"
CC=1 run '' --live; CC=''  # VAR=x before a function call persists in sh, so it is reset by hand
t_eq "a dry run inside a Claude session still exits 0" 0 "$RC"
t_has "...and notes that --apply would answer No there" "$(out)" "  note: --apply would refuse here, inside a Claude session"

t_section "components from harbor.toml (harbor#1149)"
# The stub scope-roots.sh hands --private/--conf to the real one; HARBOR_SCOPE_PRIVATE keeps it off the real layer.
PV="$T_TMP/pv1149"; mkdir -p "$PV"; HARBOR_SCOPE_PRIVATE="$PV"; export HARBOR_SCOPE_PRIVATE
fixture comp; : > "$PV/harbor.toml"; run '' --live
t_eq "no components key: dry run exits 0" 0 "$RC"
t_has "...says it installs the legacy default" "$(out)" "components unset, so it installs the legacy default"
t_has "...and still runs prod-guard" "$(out)" "prod-guard"
t_has "...and project-init" "$(out)" "project-init"
rm -f "$PV/harbor.toml"; run '' --live
t_has "no private layer file at all: the same legacy note" "$(out)" "components unset, so it installs the legacy default"
printf 'components = ["core"]\n' > "$PV/harbor.toml"; run '' --live
t_eq "components = [core]: exit 0" 0 "$RC"
t_hasnt "...no legacy note" "$(out)" "legacy default"
t_hasnt "...prod-guard is not planned" "$(out)" "prod-guard"
t_hasnt "...nor project-init" "$(out)" "project-init"
t_has "...core still is" "$(out)" "floor"
printf 'components = ["yard", "prod-guard"]\n' > "$PV/harbor.toml"; run '' --live
t_eq "components = [yard, prod-guard]: exit 0" 0 "$RC"
t_has "...names them" "$(out)" "components: core + yard prod-guard"
t_has "...prod-guard is planned" "$(out)" "prod-guard"
t_has "...project-init is planned" "$(out)" "project-init"
t_hasnt "...projects-orchestrator is not" "$(out)" "projects-orchestrator"
printf 'components = ["collector"]\n' > "$PV/harbor.toml"; run '' --live
t_eq "components = [collector]: exit 0" 0 "$RC"
t_has "...names the root installer instead of skipping silently" "$(out)" "audit-collector-install.sh"
printf 'components = ["yardd"]\n' > "$PV/harbor.toml"; run '' --live
t_eq "an unknown component name is a usage error" 2 "$RC"
t_has "...naming it" "$(out)" "'yardd' is not a component"
t_eq "...and ran nothing" "" "$(applied)"
printf 'components = []\n' > "$PV/harbor.toml"; run '' --live
t_eq "components = []: unset, so exit 0" 0 "$RC"
t_has "...and the legacy note, as for an unset key" "$(out)" "components unset, so it installs the legacy default"
t_has "...and plans prod-guard, which the legacy set has and core does not" "$(out)" "prod-guard"
printf 'packs = zorbcorp\n' > "$PV/harbor.toml"; run '' --live
t_eq "a malformed harbor.toml is a usage error, though it names no components key" 2 "$RC"
t_has "...and scope-roots.sh names the bad line" "$(out)" "harbor.toml:1"
run '' --only skills --live
t_eq "--only wins over a bad components key" 0 "$RC"
printf 'components = ["core"]\n' > "$PV/harbor.toml"; run '' --only prod-guard --live
t_eq "--only prod-guard overrides components = [core]" 0 "$RC"
t_has "...and plans prod-guard" "$(out)" "prod-guard"
t_hasnt "...and nothing else: floor is not planned" "$(out)" "floor-install"
rm -f "$PV/harbor.toml"; unset HARBOR_SCOPE_PRIVATE

t_section "preflight: the checkout"
fixture dirty; echo x > "$REPO/stray"; refuse "a dirty tree" "uncommitted changes"
fixture gen; echo y > "$REPO/skills/skill-catalog/SKILL.md"; refuse "an edited tracked skill catalog (a deploy no longer rewrites it, so no path is allowed dirty)" "uncommitted changes"
fixture ahead; git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m x; refuse "unpushed commits" "ahead 1"
fixture branch; git -C "$REPO" checkout -q -b feature; refuse "a non-main branch" "not main"
fixture wt; git -C "$REPO" worktree add -q --detach "$T/wt" 2>/dev/null; REPO="$T/wt"; refuse "a linked worktree" "linked worktree"
fixture root; mkdir -p "$T/elsewhere"
env -u CLAUDE_CONFIG_DIR CLAUDECODE= HOME="$H" STUB_LOG="$LOGF" STUB_REPO="$T/elsewhere" STUB_GI="$T/gi" STUB_SKILLS="$T/skills" STUB_B8="$T/b8" sh "$REPO/bin/deploy.sh" --live >"$T/out.txt" 2>&1 </dev/null; RC=$?
t_eq "HARBOR_REPO at another checkout" 1 "$RC"; t_has "HARBOR_REPO at another checkout: reason" "$(out)" "not this checkout"
fixture ccd
env CLAUDE_CONFIG_DIR="$T_TMP" CLAUDECODE= HOME="$H" STUB_LOG="$LOGF" STUB_REPO="$REPO" STUB_GI="$T/gi" STUB_SKILLS="$T/skills" STUB_B8="$T/b8" sh "$REPO/bin/deploy.sh" --live >"$T/out.txt" 2>&1 </dev/null; RC=$?
t_eq "CLAUDE_CONFIG_DIR elsewhere is refused before any work, exit 2" 2 "$RC"; t_has "CLAUDE_CONFIG_DIR elsewhere: reason" "$(out)" "CLAUDE_CONFIG_DIR is $T_TMP, not the target $C"
t_eq "CLAUDE_CONFIG_DIR elsewhere: nothing ran (log bytes)" 0 "$(wc -c < "$LOGF" | tr -d ' ')"
env CLAUDE_CONFIG_DIR="$C/" CLAUDECODE= HOME="$H" STUB_LOG="$LOGF" STUB_REPO="$REPO" STUB_GI="$T/gi" STUB_SKILLS="$T/skills" STUB_B8="$T/b8" sh "$REPO/bin/deploy.sh" --live >"$T/out.txt" 2>&1 </dev/null; RC=$?
t_eq "CLAUDE_CONFIG_DIR naming the live dir itself is accepted" 0 "$RC"
t_eq "...and no child saw it" no "$([ -s "$LOGF.rehearse" ] && echo yes || echo no)"

t_section "preflight: the box"
fixture nosettings; rm -f "$C/settings.json"; refuse "no settings.json (Claude Code never ran here)" "no settings.json in $C"
t_has "...its fix is the exact first-run command, from this checkout" "$(out)" "  fix: sh '$REPO/bin/harbor' scope install"
fixture stamp; STUB_STAMP_RC=1; export STUB_STAMP_RC; refuse "an install-stamp regression" "REMOVE installed work"
t_has "...relaying install-stamp's own lines" "$(out)" "  note: abc1234 the stubbed lost fix"
t_has "...with the --accept-loss deploy as its fix" "$(out)" "  fix: sh '$REPO/bin/deploy.sh' --apply --live --accept-loss"
run '' --live --accept-loss
t_eq "with --accept-loss the regression does not refuse the dry run" 0 "$RC"
t_has "...it is a WARN naming the loss" "$(out)" "  WARN: --accept-loss: runtime-install would REMOVE installed work"
t_eq "...and --accept-loss reaches the installers that take it" "deploy-runtime-install.sh floor-install.sh policy-constitution-install.sh" \
  "$(grep -- ' --accept-loss' "$LOGF" | awk '{print $1}' | sort -u | tr '\n' ' ' | sed 's/ $//')"
t_eq "...and not the ones that do not" "" "$(grep -- ' --accept-loss' "$LOGF" | grep -E '^(prod-guard|inject|shim)-install' || true)"
unset STUB_STAMP_RC
fixture b6; printf '{"continue":false,"stopReason":"deny changed"}\n' > "$T/gi"; refuse "a box already drifted (B6 block)" "ALREADY drifted"
fixture b6adv; printf '{"systemMessage":"plugin drift"}\n' > "$T/gi"; run '' --live
t_eq "a B6 advisory does not block" 0 "$RC"; t_has "a B6 advisory is reported" "$(out)" "B6 advisory"
fixture sec0; printf '{"systemMessage":"settings.json changed outside the floor'"'"'s teeth since the baseline"}\n' > "$T/gi"
refuse "settings drift the installers would re-pin" "settings.json drifted"
fixture inj; echo mine > "$C/inject.d/99-mine.md"; refuse "a box-only inject pack" "99-mine.md"
fixture injed; echo edited > "$C/inject.d/10-a.md"; refuse "a hand-edited inject pack" "10-a.md"
fixture injold; printf 'old pack\n' > "$C/inject.d/20-old.md"; echo x > "$C/inject.d/.DS_Store"; run '' --live
t_eq "a withdrawn pack and .DS_Store do not block" 0 "$RC"
fixture cmdold; mkdir -p "$C/commands"; printf 'v1\n' > "$C/commands/x.md"; printf '  note: x: would update (drifted)\n' > "$T/cmds"; run '' --live
t_eq "a stale command the repo once held does not block" 0 "$RC"
fixture cmdmine; mkdir -p "$C/commands"; printf 'mine\n' > "$C/commands/x.md"; printf '  note: x: would update (drifted)\n' > "$T/cmds"
refuse "a command edited on the box" "command x"
fixture nob8; rm -f "$T/b8"; refuse "an unbuildable B8 manifest" "could not be built"

t_section "preflight: inject.d accepts bytes the private layer once held (harbor#1149)"
# The project registry and the private box packs install into <config>/inject.d, so a past version of one is as much an
# install's as a core pack is. The layer is a throwaway repo here (HARBOR_SCOPE_PRIVATE keeps scope-roots.sh off the real one).
PVH="$T_TMP/pvhist"; rm -rf "$PVH"; mkdir -p "$PVH/inject.d/box"; git -C "$PVH" init -q -b main
printf 'registry v1\n' > "$PVH/inject.d/box/projects.tsv"; git -C "$PVH" add -A; git -C "$PVH" -c user.name=t -c user.email=t@t commit -qm v1
printf 'registry v2\n' > "$PVH/inject.d/box/projects.tsv"; git -C "$PVH" -c user.name=t -c user.email=t@t commit -qam v2
HARBOR_SCOPE_PRIVATE="$PVH"; export HARBOR_SCOPE_PRIVATE
fixture privold; printf 'registry v1\n' > "$C/inject.d/projects.tsv"; run '' --live
t_eq "a registry only the private layer's history holds does not block the dry run" 0 "$RC"
t_has "...and the preflight counts every installed pack as accounted for" "$(out)" "inject.d: every installed pack is one the repo holds or once held"
fixture privnone; printf 'registry mine\n' > "$C/inject.d/projects.tsv"; refuse "a registry in no commit of either repo" "projects.tsv"
# mutants of the fallback, committed into the clone deploy runs from (the same route the prod-guard case above takes)
fixture privmut1; sed 's|^_in_private_history() {|_in_private_history() { return 1;|' "$REPO/bin/deploy.sh" > "$T/mut.sh" && cp "$T/mut.sh" "$REPO/bin/deploy.sh"
t_has "mutant: the sed applied" "$(cat "$REPO/bin/deploy.sh")" '_in_private_history() { return 1;'
commit_push m1; printf 'registry v1\n' > "$C/inject.d/projects.tsv"; run '' --live
t_eq "mutant: a fallback that never answers refuses a registry the layer once held" 1 "$RC"
fixture privmut2; sed 's|^_in_private_history() {|_in_private_history() { return 0;|' "$REPO/bin/deploy.sh" > "$T/mut.sh" && cp "$T/mut.sh" "$REPO/bin/deploy.sh"
commit_push m2; printf 'registry mine\n' > "$C/inject.d/projects.tsv"; run '' --live
t_eq "mutant: a fallback that always answers lets a registry in no commit through" 0 "$RC"
fixture privmut3; sed 's#|| _in_private_history "inject.d/box/\$_f"#|| _in_private_history "inject.d/\$_f"#' "$REPO/bin/deploy.sh" > "$T/mut.sh" && cp "$T/mut.sh" "$REPO/bin/deploy.sh"
t_has "mutant: the sed applied" "$(cat "$REPO/bin/deploy.sh")" '_in_private_history "inject.d/$_f"'
commit_push m3; printf 'registry v1\n' > "$C/inject.d/projects.tsv"; run '' --live
t_eq "mutant: asking about the wrong path refuses a registry the layer once held" 1 "$RC"
unset HARBOR_SCOPE_PRIVATE

t_section "preflight: the installers' own dry runs"
fixture constfail; STUB_FAIL=policy-constitution-install.sh:dry; export STUB_FAIL
refuse "constitution's own dry run refusing (its loss check runs there now)" "policy-constitution-install.sh: its own dry run FAILED"; unset STUB_FAIL
t_has "...relaying the child's FAIL line" "$(out)" "  FAIL: policy-constitution-install.sh: stub failure (dry)"
t_eq "...from a dry run, with --live and no --apply, on the live dir itself" "policy-constitution-install.sh --live" "$(grep '^policy-constitution-install.sh' "$LOGF")"
fixture pgsrc; PI="$T/pi"; mkdir -p "$PI/hooks"; echo g > "$PI/hooks/prod_guard.py"
git -C "$PI" init -q -b main && git -C "$PI" add -A && git -C "$PI" -c user.name=t -c user.email=t@t commit -qm pi && git -C "$PI" checkout -q -b feature
printf '#!/bin/sh\nprintf "%%s %%s\\n" prod-guard-install.sh "$*" >> "$STUB_LOG"\necho "  note: guard: /x/hooks/prod_guard.py"\necho "  note: source: %s/hooks/prod_guard.py (upstream source repo)"\n' "$PI" > "$REPO/bin/prod-guard-install.sh"
commit_push pg; refuse "prod_guard.py from a project-init feature branch" "on 'feature'"
t_has "...naming the source line's path, not the guard's" "$(out)" "$PI/hooks/prod_guard.py is on 'feature'"
t_has "...with the switch back to main as its fix" "$(out)" "  fix: git -C '$PI/hooks' switch main"
# Deploy fetches each other repo's origin (harbor#736), so this clone needs one, and to be level with it.
git -C "$PI" checkout -q main; git clone -q --bare "$PI" "$PI.origin.git"; git -C "$PI" remote add origin "$PI.origin.git"; git -C "$PI" fetch -q origin
git -C "$PI" branch -q --set-upstream-to=origin/main main; run '' --live
t_eq "prod_guard.py from a clean project-init main" 0 "$RC"
fixture shim; printf '#!/bin/sh\necho "  FAIL: harbor: /x is a regular file, not a shim — not touched"; echo "  fix: none automatic — see shims.tsv"; exit 1\n' > "$REPO/bin/deploy-shim-install.sh"
commit_push s; refuse "a regular file where a shim belongs" "regular file sits"
t_has "an old runtime-install copy of harbor is named" "$(out)" "older runtime-installs made"
t_has "with its rm" "$(out)" "rm '$H/.local/bin/harbor'"
t_has "shim-install's own FAIL line is relayed" "$(out)" "  FAIL: harbor: /x is a regular file, not a shim"
# skills-install's dry run now detects what makes its --apply fail (skills-install-test pins the detection);
# deploy refuses on its exit 1 and relays its FAIL lines.
skills_refuse() { # <label> <FAIL text>
  mkdir -p "$C/skills"; printf '  FAIL: topo: %s\n  fix: none automatic — see the stub\n' "$2" > "$T/skills"
  STUB_SKILLS_RC=1; export STUB_SKILLS_RC; refuse "$1" "$2"; unset STUB_SKILLS_RC
  t_has "$1: skills-install's FAIL line is relayed" "$(out)" "  FAIL: topo: $2"
}
fixture nested; skills_refuse "a NESTED skill" "NESTED (topo/topo): an earlier hand-typed cp"
fixture collide; skills_refuse "a skill newer on the box" "the installed copy is NEWER than the repo (skills-collide)"
fixture extra; skills_refuse "a skill with box-only files" "the installed copy has files the repo does not: only-here.md"
fixture cache; mkdir -p "$C/skills"; printf '  note: topo: would update (drifted)\n' > "$T/skills"; run '' --live
t_eq "a passing skills dry run is not refused" 0 "$RC"; t_has "...and its counts are reported" "$(out)" "skills: 1 to update, 0 new, none blocked"
t_eq "the skills dry run is --all --live" "skill-install.sh --all --live" "$(cat "$LOGF.dry" 2>/dev/null)"
fixture dryfail; STUB_FAIL=floor-install.sh:dry; export STUB_FAIL; refuse "a failing installer dry run" "its own dry run FAILED"; unset STUB_FAIL

t_section "prod-guard fails preflight when project-init is absent, unless --only excludes it"
fixture pg
printf '#!/bin/sh\nprintf "%%s %%s\\n" prod-guard-install.sh "$*" >> "$STUB_LOG"\necho "  FAIL: no prod_guard.py at /x"; echo "  fix: none automatic — see project-init"; exit 1\n' > "$REPO/bin/prod-guard-install.sh"
commit_push pg; run 'y\nn\n' --apply --live
t_eq "deploy without prod-guard's source" 1 "$RC"
t_has "...fails preflight, before the prompt" "$(out)" "PREFLIGHT FAILED (1) — nothing was installed"
t_has "...naming prod-guard and why" "$(out)" "  note: prod-guard: no prod_guard.py at /x"
t_eq "...and nothing is applied" "" "$(applied)"
PGFIX="$(grep -A1 '^  FAIL: cannot install ' "$T/out.txt" | sed -n 2p)"
t_eq "...its fix: the apply with --only every other component" \
  "  fix: sh '$REPO/bin/deploy.sh' --apply --only constitution,shim,sec0,runtime,floor,skills,inject,packs,project-init,projects-orchestrator --live" "$PGFIX"
: > "$LOGF"
# shellcheck disable=SC2046
run 'y\nn\n' $(printf '%s' "$PGFIX" | sed "s|^  fix: sh '$REPO/bin/deploy.sh' ||")
t_eq "that fix, run as printed, installs" 0 "$RC"
t_hasnt "...and prod-guard is never applied" "$(applied)" "prod-guard"
t_has "...while the floor is" "$(applied)" "floor-install.sh --live"
run '' --only floor,prod-guard --live
t_eq "--only floor,prod-guard on that box fails too" 1 "$RC"
t_eq "...its fix keeps the rest of that selection" "  fix: sh '$REPO/bin/deploy.sh' --only floor --live" "$(grep -A1 '^  FAIL: cannot install ' "$T/out.txt" | sed -n 2p)"

t_section "the [y/N] gate: nothing is written without a person's yes"
fixture eof  # a pty with stdin from /dev/null, so a real terminal running this suite is never read
pty env -u CLAUDE_CONFIG_DIR -u HARBOR_LOCAL_BIN CLAUDECODE= HOME="$H" STUB_LOG="$LOGF" STUB_REPO="$REPO" STUB_GI="$T/gi" STUB_SKILLS="$T/skills" STUB_B8="$T/b8" \
  sh "$REPO/bin/deploy.sh" --apply --live </dev/null >"$T/out" 2>&1; RC=$?
tr -d '\r' <"$T/out" >"$T/out.txt"
t_eq "end of input answers No" 1 "$RC"; t_has "and says nothing was installed" "$(out)" "nothing was installed"
t_eq "end of input: nothing applied" "" "$(applied)"
t_eq "end of input: no snapshot" no "$(ls -d "$C"/backups/deploy-* >/dev/null 2>&1 && echo yes || echo no)"
t_has "end of input: the declined run keeps its log, naming the refusal" "$(dlog)" "FAIL: declined at the prompt"
t_has "...and the fix: the same command, from a terminal" "$(out)" "  fix: sh '$REPO/bin/deploy.sh' --apply --live"
fixture cc; CC=1 run 'y\n' --apply --live; CC=''
t_eq "inside a Claude session a y is ignored" 1 "$RC"; t_has "and it says why" "$(out)" "inside a Claude session"
t_eq "inside a Claude session: nothing applied" "" "$(applied)"
fixture no; run 'n\n' --apply --live
t_eq "answering n" 1 "$RC"; t_eq "answering n installs nothing" "" "$(applied)"

t_section "--unattended: the ship runner's apply, and only the runner's (harbor#1018, ship contract §6)"
fixture unattflags; : > "$T/snap"
SHIP_SNAPSHOT="$T/snap"; export SHIP_SNAPSHOT  # valid, so only the missing SHIP_UNATTENDED can refuse
run '' --apply --live --unattended; t_eq "without SHIP_UNATTENDED=1: a usage error" 2 "$RC"
t_has "...naming it" "$(out)" "SHIP_UNATTENDED=1"
SHIP_UNATTENDED=1; export SHIP_UNATTENDED; unset SHIP_SNAPSHOT
run '' --apply --live --unattended; t_eq "without SHIP_SNAPSHOT: a usage error" 2 "$RC"
SHIP_SNAPSHOT="$T/snap"; export SHIP_SNAPSHOT
run '' --live --unattended; t_eq "on a dry run: a usage error" 2 "$RC"
printf 'old\n' > "$T/snap"; run '' --apply --live --unattended; t_eq "a SHIP_SNAPSHOT that is not empty: a usage error" 2 "$RC"; : > "$T/snap"
run '' --apply --live --unattended --accept-loss; t_eq "with --accept-loss: a usage error" 2 "$RC"
t_eq "no usage error applied anything" "" "$(applied)"
CC=1 run 'y\n' --apply --live; CC=''
t_eq "SHIP_UNATTENDED=1 without the flag is still refused in a session" 1 "$RC"; t_eq "...and applies nothing" "" "$(applied)"
fixture unatt; SHIP_SNAPSHOT="$T/snap"; : > "$SHIP_SNAPSHOT"
printf 'bbb  CLAUDE.md\n' > "$T/b8"  # B8 drift, so the re-pin is reached
CC=1 run '' --apply --live --unattended; CC=''
t_eq "inside a session, with no terminal, it installs" 0 "$RC"
t_eq "...in the one order that works" "policy-constitution-install.sh --apply,deploy-shim-install.sh --live,deploy-harden.sh --apply,deploy-runtime-install.sh --live,floor-install.sh --live,prod-guard-install.sh --live,skill-install.sh --all,skill-install.sh commands,context-injection-install.sh --live,deploy-shim-install.sh --live,skill-catalog.sh install,just $T/pi,just $T/po," \
  "$(grep -e '--apply' -e '^skill-catalog' "$LOGF" | awk '{print $1, $2}' | tr '\n' ',')"
t_eq "the snapshot id the runner reads is this run's snapshot" "$(ls -d "$C"/backups/deploy-*)" "$(cat "$SHIP_SNAPSHOT")"
t_has "the install question is answered yes, saying why" "$(out)" "yes: --unattended"
t_eq "the B8 re-pin is never made unattended" 0 "$(pins)"; t_has "...and says so" "$(out)" "answering No: --unattended asks nobody"
t_hasnt "no next line hands a person the runner's flag" "$(grep -E '^  (fix|note: next):' "$T/out.txt" || :)" "--unattended"
# `harbor ship night` from a terminal: a tty is there to answer, and --unattended must still ask nobody
fixture unatttty; SHIP_SNAPSHOT="$T/snap"; : > "$SHIP_SNAPSHOT"; printf 'bbb  CLAUDE.md\n' > "$T/b8"
run 'y\ny\ny\n' --apply --live --unattended
t_eq "at a terminal, it installs" 0 "$RC"; t_eq "...and a y typed there re-pins nothing" 0 "$(pins)"
fixture unattwt; SHIP_SNAPSHOT="$T/snap"; : > "$SHIP_SNAPSHOT"
MAIN="$REPO"; git -C "$REPO" worktree add -q --detach "$T/wt" 2>/dev/null; REPO="$T/wt"
CC=1 run '' --apply --live --unattended; CC=''; REPO="$MAIN"
t_eq "from a linked worktree, unattended is refused up front too" 1 "$RC"; t_eq "...writing no snapshot id" "" "$(cat "$SHIP_SNAPSHOT")"
t_eq "...its fix the terminal apply from the main checkout, without the runner's flag" \
  "  fix: sh '$MAIN/bin/deploy.sh' --apply --live   # from a terminal window" "$(grep -A1 'linked worktree' "$T/out.txt" | sed -n 2p)"
fixture unattfail; SHIP_SNAPSHOT="$T/snap"; : > "$SHIP_SNAPSHOT"
STUB_FAIL=floor-install.sh:apply; STUB_HOOK_deployruntimeinstallsh="printf MODIFIED > '$C/settings.json'"; export STUB_FAIL STUB_HOOK_deployruntimeinstallsh
CC=1 run '' --apply --live --unattended; CC=''
t_eq "a failed unattended install" 1 "$RC"
t_eq "...is not restored by deploy: the restore is the runner's" MODIFIED "$(cat "$C/settings.json")"
_uid="$(cat "$SHIP_SNAPSHOT")"; t_has "...which already has the id" "$_uid" "$C/backups/deploy-"
t_hasnt "...and no fix line hands a person the runner's flag" "$(grep -E '^  (fix|note: next):' "$T/out.txt" || :)" "--unattended"
# ship.conf's restore line, from the id, inside a session as the gate's runner runs it
( cd "$REPO" && env -u CLAUDE_CONFIG_DIR HOME="$H" CLAUDECODE=1 sh bin/deploy-restore.sh --apply --live --from "$_uid" --accept-loss ) >"$T/rs" 2>&1 </dev/null
t_eq "the runner's restore from that id puts the box back" "{}" "$(cat "$C/settings.json")"
unset STUB_FAIL STUB_HOOK_deployruntimeinstallsh SHIP_UNATTENDED SHIP_SNAPSHOT

t_section "a refused preflight on --apply keeps its log (contracts/logging.md)"
fixture refusedlog; echo x > "$REPO/stray"; run '' --apply --live
t_eq "the refused apply" 1 "$RC"; t_eq "...applies nothing" "" "$(applied)"
t_eq "...and keeps exactly one log, under backups/deploy/<TS>/" 1 "$(ls "$C"/backups/deploy/*/log 2>/dev/null | grep -c .)"
t_has "...holding the refusal" "$(dlog)" "  FAIL: uncommitted changes in"
t_has "...and its verdict" "$(dlog)" "  note: PREFLIGHT FAILED"
t_exit "...every line timestamped" 0 awk '!/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z / { bad = 1 } END { exit bad }' "$(ls "$C"/backups/deploy/*/log | head -1)"
t_eq "the last screen line names the log" "log: $(ls "$C"/backups/deploy/*/log | head -1)" "$(tail -1 "$T/out.txt")"
t_eq "...and no snapshot was taken" no "$(ls -d "$C"/backups/deploy-* >/dev/null 2>&1 && echo yes || echo no)"

t_section "the happy path: order, snapshot, the installed skill catalog written after the packs"
fixture happy; mkdir -p "$C/lib"; echo core > "$C/lib/core.sh"; run 'y\n' --apply --live
WANT='policy-constitution-install.sh --apply,deploy-shim-install.sh --live,deploy-harden.sh --apply,deploy-runtime-install.sh --live,floor-install.sh --live,prod-guard-install.sh --live,skill-install.sh --all,skill-install.sh commands,context-injection-install.sh --live,deploy-shim-install.sh --live,skill-catalog.sh install,'"just $T/pi,just $T/po,"
t_eq "the happy path" 0 "$RC"
t_eq "installs run in the one order that works" "$WANT" "$(grep -e '--apply' -e '^skill-catalog' "$LOGF" | awk '{print $1, $2}' | tr '\n' ',')"
t_has "a snapshot of the config dir is taken first" "$(tar -tzf "$C"/backups/deploy-*/config.tgz 2>/dev/null)" "settings.json"
t_has "the snapshot covers lib/ (harbor#765)" "$(tar -tzf "$C"/backups/deploy-*/config.tgz 2>/dev/null)" "lib/core.sh"
t_has "set.txt records lib/ for deploy-restore.sh" "$(cat "$C"/backups/deploy-*/set.txt 2>/dev/null)" "lib"
t_has "set.txt records prod-guard's backups as a glob" "$(cat "$C"/backups/deploy-*/set.txt 2>/dev/null)" "settings.json.bak.*"
_sd="$(ls -d "$C"/backups/deploy-* | head -1)"; _sh() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{print $1}'; }
t_eq "the snapshot step writes one ledger row (harbor#769)" 1 "$(grep -c . "$C/.helm-snapshots" 2>/dev/null || echo 0)"
t_eq "...whose hash is the snapshot's" "$(_sh < "$_sd/config.tgz")" "$(awk '{print $1}' "$C/.helm-snapshots" 2>/dev/null)"
t_eq "...whose path is the snapshot's, relative to the config dir" "backups/${_sd##*/}/config.tgz" "$(awk '{print $2}' "$C/.helm-snapshots" 2>/dev/null)"
t_exit "...with a UTC time" 0 grep -qE '^[0-9a-f]{64} [^ ]+ [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z ' "$C/.helm-snapshots"
t_eq "...and the hash of the set it covered" "set=$(_sh < "$_sd/set.txt")" "$(awk '{print $4}' "$C/.helm-snapshots" 2>/dev/null)"
t_hasnt "the ledger is not in the snapshot it records" "$(tar -tzf "$_sd/config.tgz")" ".helm-snapshots"
t_eq "the skill catalog is written by skill-catalog.sh install on the live dir, and never through skills-install from the tracked file" "skill-catalog.sh install --apply --live" "$(grep '^skill-catalog.sh' "$LOGF")"
t_has "B8 unchanged: nothing to re-pin" "$(out)" "nothing to re-pin"; t_eq "B8 unchanged: no pin-instructions call" 0 "$(pins)"
t_has "a child's lines are relayed on screen" "$(out)" "  ok: deploy-runtime-install.sh stub ran (apply)"
t_has "...and kept in deploy's log, timestamped" "$(dlog)" "Z   ok: deploy-runtime-install.sh stub ran (apply)"
t_has "deploy's own lines are in its log too" "$(dlog)" "  ok: snapshot: "
t_has "the run ends naming its log" "$(tail -1 "$T/out.txt")" "log: $C/backups/deploy/"
t_eq "every child of the apply ran with HARBOR_DEPLOY=1 (#285)" no "$([ -s "$LOGF.nodeploy" ] && echo yes || echo no)"
t_eq "no check-mark, cross or bar glyph in an apply's output" 0 "$(grep -cE '✓|✗|│' "$T/out.txt")"
fixture happyloss; run 'y\n' --apply --live --accept-loss
t_eq "an apply with --accept-loss" 0 "$RC"
t_eq "--accept-loss reaches constitution, runtime, floor and the two skills-install runs" \
  "policy-constitution-install.sh --apply,deploy-runtime-install.sh --live,floor-install.sh --live,skill-install.sh --all,skill-install.sh commands," \
  "$(grep -- '--apply' "$LOGF" | grep -- ' --accept-loss' | awk '{print $1, $2}' | tr '\n' ',')"
t_eq "...and no other installer" "" "$(grep -- '--apply' "$LOGF" | grep -- ' --accept-loss' | grep -E '^(shim|prod-guard|inject)-install' || true)"

t_section "a failure midway stops the run and offers the snapshot"
fixture midfail; STUB_FAIL=floor-install.sh:apply; export STUB_FAIL
STUB_HOOK_deployruntimeinstallsh="printf MODIFIED > '$C/settings.json'"; export STUB_HOOK_deployruntimeinstallsh
run 'y\nn\n' --apply --live
t_eq "a failed install" 1 "$RC"; t_has "names where it stopped" "$(out)" "stopped at: floor-install.sh"
t_eq "later steps do not run" "policy-constitution-install.sh --apply,deploy-shim-install.sh --live,deploy-harden.sh --apply,deploy-runtime-install.sh --live,floor-install.sh --live," "$(applied)"
t_eq "declining the restore leaves the partial install" MODIFIED "$(cat "$C/settings.json")"
fixture restore; STUB_HOOK_deployruntimeinstallsh="printf MODIFIED > '$C/settings.json'; mkdir -p '$C/skills/added'; : > '$C/settings.json.bak.1'"
run 'y\ny\n' --apply --live
t_eq "accepting the restore" 1 "$RC"; t_has "says restored" "$(out)" "restored"
t_eq "settings.json is put back" "{}" "$(cat "$C/settings.json")"
t_eq "a dir the run added is not left live" no "$([ -d "$C/skills/added" ] && echo yes || echo no)"
t_eq "it is moved aside, into restore's own backups/restore/<TS>/" yes "$(ls -d "$C"/backups/restore/*/skills/added >/dev/null 2>&1 && echo yes)"
t_eq "a top-level file the run created is not left live" no "$([ -e "$C/settings.json.bak.1" ] && echo yes || echo no)"
t_eq "it is moved aside too" yes "$(ls "$C"/backups/restore/*/settings.json.bak.1 >/dev/null 2>&1 && echo yes)"
t_has "the restore plan was shown before the question" "$(out)" "── restore · plan for $C (dry run: nothing is written)"
t_has "the kept log holds the restore's outcome" "$(dlog)" "restored; the next session"
t_has "...and restore's own lines, relayed" "$(dlog)" "  ok: restored $C from "
unset STUB_FAIL STUB_HOOK_deployruntimeinstallsh

t_section "the restore offer has one code path: deploy-restore.sh (harbor#765)"
fixture viarestore; STUB_FAIL=floor-install.sh:apply; export STUB_FAIL
STUB_HOOK_deployruntimeinstallsh="printf MODIFIED > '$C/settings.json'"; export STUB_HOOK_deployruntimeinstallsh
printf '#!/bin/sh\nprintf "deploy-restore.sh %%s\\n" "$*" >> "$STUB_LOG"\n' > "$REPO/bin/deploy-restore.sh"; commit_push stubrestore
run 'y\ny\n' --apply --live
SNAPD="$(ls -d "$C"/backups/deploy-* 2>/dev/null | head -1)"
t_eq "the plan is deploy-restore.sh's dry run on this run's snapshot" 1 "$(grep -cxF -- "deploy-restore.sh --live --from $SNAPD --accept-loss" "$LOGF")"
t_eq "a yes runs deploy-restore.sh --apply on the same snapshot" 1 "$(grep -cxF -- "deploy-restore.sh --apply --live --from $SNAPD --accept-loss" "$LOGF")"
t_eq "deploy restores nothing itself: with deploy-restore.sh stubbed, settings.json stays as the run left it" MODIFIED "$(cat "$C/settings.json")"
fixture restorefail; STUB_HOOK_deployruntimeinstallsh="printf MODIFIED > '$C/settings.json'"
printf '#!/bin/sh\nprintf "deploy-restore.sh %%s\\n" "$*" >> "$STUB_LOG"; echo "restore: stub refusal" >&2; exit 1\n' > "$REPO/bin/deploy-restore.sh"; commit_push stubrefuse
run 'y\ny\n' --apply --live
t_has "a plan deploy-restore.sh refuses is reported" "$(out)" "cannot restore this run's snapshot"
t_hasnt "...and no restore is asked" "$(out)" "Restore the snapshot now?"
t_eq "...or applied" 0 "$(grep -c '^deploy-restore.sh --apply' "$LOGF")"
unset STUB_FAIL STUB_HOOK_deployruntimeinstallsh

t_section "verify: the next session would be blocked"
fixture vblock; STUB_HOOK_floorinstallsh="printf '{\"continue\":false,\"stopReason\":\"x\"}' > '$T/gi'"; export STUB_HOOK_floorinstallsh
printf 'zzz  CLAUDE.md\n' > "$T/b8"; run 'y\nn\n' --apply --live; unset STUB_HOOK_floorinstallsh
t_eq "a B6 block after install" 1 "$RC"; t_has "fails the deploy" "$(out)" "next session would be BLOCKED"
t_has "the re-pin is not offered" "$(out)" "not offered: verification failed"
t_hasnt "no re-pin prompt" "$(out)" "Re-pin the instruction"; t_eq "no pin-instructions call" 0 "$(pins)"
fixture vdrift; STUB_STALE=2; export STUB_STALE; run 'y\nn\n' --apply --live; unset STUB_STALE
t_eq "installed bin/ not matching the commit" 1 "$RC"; t_has "fails the deploy" "$(out)" "installed bin/ differs"
t_has "...naming the stale file from install-drift's FAIL row" "$(out)" "  note: stale guard-x.sh (installed copy is 1 commit(s) behind HEAD)"

t_section "floor-verify: its FAIL lines decide, and a B8-only failure after a declined re-pin is a note"
fixture fvb8; printf 'zzz  CLAUDE.md\n' > "$T/b8"; STUB_FV=b8; run 'y\nn\n' --apply --live; unset STUB_FV
t_eq "only B8 fails and the re-pin was declined" 0 "$RC"
t_has "...said as a note" "$(out)" "only B8 fails, because no re-pin was made"
fixture fvbash; printf 'zzz  CLAUDE.md\n' > "$T/b8"; STUB_FV=bash; run 'y\nn\n' --apply --live; unset STUB_FV
t_eq "a non-B8 floor-verify FAIL beside the B8 one fails the deploy" 1 "$RC"
t_has "...with floor-verify's verdict" "$(out)" "  FAIL: floor-verify: FLOOR IS NOT FULLY ON — 2 check(s) failed"
t_has "...and its FAIL lines relayed" "$(out)" "  FAIL: DOES NOT BLOCK: pipe-to-shell (exit 0)"
fixture fvcrash; printf 'zzz  CLAUDE.md\n' > "$T/b8"; STUB_FV=crash; run 'y\nn\n' --apply --live; unset STUB_FV
t_eq "a floor-verify that died with no FAIL line fails the deploy, even after a declined re-pin" 1 "$RC"
t_hasnt "...and is never read as a B8-only failure" "$(out)" "only B8 fails, because no re-pin was made"
fixture fvok; run 'y\nn\n' --apply --live
t_has "a clean floor-verify's verdict is deploy's ok line" "$(out)" "  ok: floor-verify: FLOOR IS ON — guards present, wired, and blocking."

t_section "B8: the re-pin is asked, split into this deploy and before it"
fixture repin  # pin -> before the deploy -> after it; CLAUDE.md drifted before AND by the deploy
printf 'aaa  CLAUDE.md\nlink:/b  skills/l\n' > "$C/.helm-instructions.sha256"
printf 'bbb  CLAUDE.md\nbbb  memory/old.md\nlink:/a  skills/l\n' > "$T/b8"
STUB_HOOK_skillinstallsh="printf 'ccc  CLAUDE.md\nbbb  memory/old.md\nlink:/a  skills/l\nccc  skills/new/SKILL.md\n' > '$T/b8'"; export STUB_HOOK_skillinstallsh
run 'y\nn\n' --apply --live
t_eq "re-pin declined" 0 "$RC"; t_has "the re-pin is asked" "$(out)" "Re-pin the instruction"
t_has "declined: the command is printed" "$(out)" "not re-pinned"; t_eq "declined: nothing pinned" 0 "$(pins)"
t_exit "changes are split into THIS deploy and BEFORE it" 0 awk '/Changed by THIS/{f=1} /Changed BEFORE/{f=2} f==1 && /skills\/new/{a=1} f==2 && /memory\/old/{b=1} END{exit !(a && b)}' "$T/out.txt"
t_exit "a path changed before AND by the deploy is this deploy's, starred" 0 awk '/Changed by THIS/{f=1} /Changed BEFORE/{f=2} f==1 && /CLAUDE.md  \*/{a=1} f==2 && /CLAUDE.md/{b=1} END{exit !(a && !b)}' "$T/out.txt"
t_has "link: prefixes are stripped to the path" "$(out)" "skills/l"; t_hasnt "no link: prefix is shown" "$(out)" "link:/"
fixture repin2; printf 'aaa  CLAUDE.md\nccc  skills/new/SKILL.md\n' > "$T/b8"
run 'y\ny\n' --apply --live; unset STUB_HOOK_skillinstallsh
t_eq "re-pin accepted" 0 "$RC"
t_eq "pin-instructions --apply runs with --live, the only target spelling it takes" 1 "$(grep -cx 'pin-instructions --apply --live' "$LOGF")"

t_section "harbor uninstall is deploy --only floor --uninstall: flags (harbor#808)"
fixture unflags
run '' --uninstall --live; t_eq "--uninstall without --only floor" 2 "$RC"
t_has "...names the one component it takes" "$(out)" "--uninstall takes --only floor"
run '' --only skills --uninstall --live; t_eq "--uninstall of a component with no uninstaller" 2 "$RC"
run '' --only floor,skills --uninstall --live; t_eq "--uninstall of the floor and another component" 2 "$RC"
run '' --only floor --uninstall --with-b6 --live; t_eq "--uninstall with an opt-in" 2 "$RC"
t_eq "no usage error ran anything (log bytes)" 0 "$(wc -c < "$LOGF" | tr -d ' ')"

# The REAL floor-uninstall, reading the real floor-install and runtime-install beside it, on a floor it
# recognises: floor-hook + guard-bash wired and present, a pin, the teeth; and a foreign hook it keeps.
unfloor() {
  cp "$T_ROOT/bin/floor-uninstall.sh" "$T_ROOT/bin/floor-install.sh" "$T_ROOT/bin/deploy-runtime-install.sh" "$REPO/bin/"
  git -C "$REPO" add bin/floor-uninstall.sh; commit_push realfloor
  mkdir -p "$C/bin"; printf '#!/bin/sh\nexit 0\n' > "$C/bin/floor-hook.sh"; cp "$C/bin/floor-hook.sh" "$C/bin/guard-bash.sh"
  printf 'x  bin/guard-bash.sh\n' > "$C/.helm-pins/guard-bash.sh.sha256"; printf 'teeth\n' > "$C/.helm-floor-teeth"
  jq -n --arg g "/bin/sh $C/bin/floor-hook.sh $C/bin/guard-bash.sh" --arg m "/bin/sh $H/mine.sh" \
    '{hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: $g}, {type: "command", command: $m}]}]}}' > "$C/settings.json"
  cp "$C/settings.json" "$T/settings.before"
}
unmanifest() { # the two floor files' rows, and one row for a file the uninstall keeps (harbor#815)
  { printf '# .harbor-manifest (install standard §3, bin/deploy-install-lib.sh): <git-blob> <mode> <relpath> <installer> <commit>\n'
    for _f in floor-hook.sh guard-bash.sh; do printf '%s 100755 bin/%s floor-install -\n' "$(git hash-object "$C/bin/$_f")" "$_f"; done
    printf '%s 100644 lib/core.sh runtime-install -\n' "$(git hash-object "$C/bin/floor-hook.sh")"
  } > "$C/.harbor-manifest"
  cp "$C/.harbor-manifest" "$T/manifest.before"
}
t_section "harbor uninstall: a dry run plans through floor-uninstall's own dry run and removes nothing"
fixture undry; unfloor; run '' --only floor --uninstall --live
t_eq "the uninstall dry run" 0 "$RC"
t_has "it relays what floor-uninstall would remove" "$(out)" "  note: floor file to remove: bin/guard-bash.sh"
t_eq "...and removes nothing" "$(cat "$T/settings.before")" "$(cat "$C/settings.json")"
t_has "its next step is the apply, which its own gate takes" "$(out)" "  note: next: sh '$REPO/bin/deploy.sh' --apply --only floor --uninstall --live"
t_eq "no installer ran" "" "$(applied)"
CC=1 run 'y\n' --only floor --uninstall --apply --live; CC=''
t_eq "inside a Claude session its --apply is refused up front" 1 "$RC"
t_has "...before any plan" "$(out)" "refused up front: running inside a Claude session"
t_eq "...and nothing is removed" "$(cat "$T/settings.before")" "$(cat "$C/settings.json")"

t_section "harbor uninstall --apply: snapshot first, remove, verify the floor is GONE, offer the snapshot back"
fixture unapply; unfloor; unmanifest; run 'y\n' --only floor --uninstall --apply --live
SNAPD="$(ls -d "$C"/backups/deploy-* 2>/dev/null | head -1)"
t_eq "the uninstall" 0 "$RC"
t_has "a snapshot was taken before the removal" "$(tar -tzf "$SNAPD/config.tgz" 2>/dev/null)" "bin/guard-bash.sh"
t_eq "...recorded in the ledger deploy-restore.sh demands" 1 "$(grep -c "backups/${SNAPD##*/}/config.tgz" "$C/.helm-snapshots" 2>/dev/null || echo 0)"
t_eq "the floor's hook is unwired and the foreign one kept" "/bin/sh $H/mine.sh" "$(jq -r '[.hooks.PreToolUse[]?.hooks[]?.command] | join(",")' "$C/settings.json")"
t_eq "the floor's files are gone from bin/" no "$([ -e "$C/bin/guard-bash.sh" ] && echo yes || echo no)"
t_has "the snapshot holds .harbor-manifest as it was" "$(tar -tzf "$SNAPD/config.tgz" 2>/dev/null)" ".harbor-manifest"
t_eq ".harbor-manifest drops the moved files' rows and keeps the rest (harbor#815)" \
  "$(grep ' lib/core.sh ' "$T/manifest.before")" "$(grep -v '^#' "$C/.harbor-manifest")"
t_has "verify reads the floor as absent, by floor-uninstall's own dry run" "$(out)" "  ok: the floor is gone: floor-uninstall's own dry run finds no hook and no file left to remove"
t_hasnt "...and floor-verify is not run on the floor it just removed" "$(out)" "floor-verify:"
t_has "the snapshot is offered back as the command that restores it" "$(out)" \
  "  note: next: sh '$REPO/bin/deploy-restore.sh' --apply --live --from '$SNAPD' --accept-loss"
t_has "the run keeps its log" "$(dlog)" "  ok: the floor is gone: "
_rcmd="$(sed -n "s|^  note: next: \(sh '$REPO/bin/deploy-restore.sh' .*\)$|\1|p" "$T/out.txt" | head -1)"
t_has "the restore command was printed, to run as printed" "$_rcmd" "/bin/deploy-restore.sh' --apply --live --from '$SNAPD' --accept-loss"
env -u CLAUDE_CONFIG_DIR HOME="$H" sh -c "$_rcmd" </dev/null >"$T/restore.out" 2>&1; _rrc=$?
t_eq "the printed restore command runs as printed" 0 "$_rrc"
t_eq "...and puts the floor's wiring back, byte for byte" "$(cat "$T/settings.before")" "$(cat "$C/settings.json")"
t_eq "...and the floor's files" yes "$([ -f "$C/bin/guard-bash.sh" ] && [ -f "$C/.helm-pins/guard-bash.sh.sha256" ] && echo yes || echo no)"
t_eq "...and their .harbor-manifest rows, byte for byte (harbor#815)" "$(cat "$T/manifest.before")" "$(cat "$C/.harbor-manifest")"

t_section "harbor uninstall: a floor still present after the removal fails verify and offers the snapshot back"
fixture unfail; unfloor
printf '#!/bin/sh\ncase " $* " in *" --apply "*) printf MODIFIED > "$HOME/.claude/settings.json"; echo "  ok: stub removed nothing"; exit 0 ;; esac\necho "  note: hook to remove: PreToolUse: /bin/sh x/guard-bash.sh"\n' > "$REPO/bin/floor-uninstall.sh"
commit_push stubun; run 'y\ny\n' --only floor --uninstall --apply --live
t_eq "an uninstall that left the floor" 1 "$RC"
t_has "verify names it" "$(out)" "  FAIL: the floor is still present after floor-uninstall"
t_has "...relaying what is left" "$(out)" "  note: hook to remove: PreToolUse: /bin/sh x/guard-bash.sh"
t_has "the restore plan is deploy-restore.sh's, on this run's snapshot" "$(out)" "── restore · plan for $C (dry run: nothing is written)"
t_eq "accepting the restore puts settings.json back" "$(cat "$T/settings.before")" "$(cat "$C/settings.json")"
t_has "...and every check runs again on the restored box" "$(out)" "── deploy · re-check · every check again, on the restored box"
t_section "harbor#916 · runtime without floor refuses a pinned file it would replace, before any write"
fixture pin916
printf 'stale-pin\n' > "$C/.helm-pins/library-log.sh.sha256"
commit_push pin916; run '' --only runtime --apply --live
t_eq "--only runtime fails the preflight" 1 "$RC"
t_has "naming the pinned file" "$(out)" "would replace B6-pinned library-log.sh"
t_has "with the run that re-pins it" "$(out)" "--only runtime,floor"
t_has "refused in the preflight" "$(out)" "PREFLIGHT FAILED"
t_eq "so no installer applied anything" "" "$(applied)"
run '' --only runtime,floor --live
t_hasnt "with floor selected it is not refused" "$(out)" "would replace B6-pinned"
_sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{print $1}'; }
_sha256 < "$REPO/bin/library-log.sh" > "$C/.helm-pins/library-log.sh.sha256"
run '' --only runtime --live
t_has "and a pin that already matches lets runtime go alone" "$(out)" "runtime replaces no B6-pinned file"
printf '#!/bin/sh\necho stub\n' > "$REPO/bin/deploy-runtime-install.sh"; commit_push nofiles916
run '' --only runtime --live
t_has "a runtime-install with no FILES line is a FAIL, never a pass" "$(out)" "cannot read runtime-install's FILES"

fixture unpre; unfloor
printf '#!/bin/sh\necho "  FAIL: stub: cannot read the floor payload"; echo "  fix: none automatic — see the stub"; exit 1\n' > "$REPO/bin/floor-uninstall.sh"
commit_push stubpre; run '' --only floor --uninstall --live
t_eq "a floor-uninstall dry run that refuses fails the preflight" 1 "$RC"
t_has "...saying so" "$(out)" "PREFLIGHT FAILED"
t_has "...relaying its FAIL line" "$(out)" "  FAIL: stub: cannot read the floor payload"
t_done
