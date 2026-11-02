# tests/install/deploy-fixture.sh — the throwaway repo, stub installers and helpers the deploy suites
# share (deploy-test, deploy.standard-test, deploy.prune-test). Sourced after core.sh's t_init; the
# REAL deploy.sh, deploy-restore.sh, library-log.sh and deploy-install-lib.sh run in it (harbor#457, #765).
# STUB_HOOK_* values are shell source run by the stub's `sh -c`, so their quotes are literal.
# shellcheck disable=SC2089,SC2090
INSTALLERS='policy-constitution-install.sh deploy-shim-install.sh deploy-harden.sh deploy-runtime-install.sh admission-install.sh prod-guard-install.sh skill-install.sh skill-catalog.sh context-injection-install.sh pack.sh'
# A stub logs argv, fails when STUB_FAIL names "<script>:dry|apply", runs STUB_HOOK_<name> on apply.
# It records a child run WITHOUT HARBOR_DEPLOY_ACTIVE=1 (#285) or WITH a CLAUDE_CONFIG_DIR, both of which deploy
# must never hand a child, and prints one line in the log shape, for the relay into deploy's log.
_stub_body='#!/bin/sh
n=$(basename "$0")
L="$STUB_LOG"; [ -z "${CLAUDE_CONFIG_DIR:-}" ] || L="$STUB_LOG.rehearse"
printf "%s %s\n" "$n" "$*" >> "$L"
[ "${HARBOR_DEPLOY_ACTIVE:-${HARBOR_DEPLOY:-}}" = 1 ] || printf "%s\n" "$n" >> "$STUB_LOG.nodeploy"
case " $* " in *" --apply "*) m=apply ;; *) m=dry ;; esac
v=$(printf %s "$n" | tr -d ".-"); eval "h=\${STUB_HOOK_$v:-}"
[ "$m" = apply ] && [ -n "$h" ] && sh -c "$h"
[ "${STUB_FAIL:-}" = "$n:$m" ] && { echo "  FAIL: $n: stub failure ($m)"; echo "  fix: none automatic — see the stub"; exit 1; }
echo "  ok: $n stub ran ($m)"
exit 0'

fixture() { # <case> → T (case dir) with origin.git, repo (a clone on main), home H, config C
  T="$T_TMP/$1"; H="$T/home"; C="$H/.claude"; REPO="$T/repo"; LOGF="$T/calls"
  mkdir -p "$T/src/bin" "$T/src/inject.d/box" "$T/src/skills/skill-catalog" "$C/inject.d" "$C/.helm-pins" "$H/.local/bin"
  cp "$T_ROOT/bin/deploy.sh" "$T/src/bin/deploy.sh"; cp "$T_ROOT/bin/deploy-restore.sh" "$T/src/bin/deploy-restore.sh"
  cp "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/deploy-install-lib.sh" "$T/src/bin/"
  for s in $INSTALLERS; do printf '%s\n' "$_stub_body" > "$T/src/bin/$s"; done
  # runtime-install's payload line, in the real one's shape: deploy reads it to know which B6-pinned
  # files a runtime-only run would replace (harbor#916). Both files exist in this fixture's bin.
  printf 'FILES="library-log.sh deploy-install-lib.sh"\n' >> "$T/src/bin/deploy-runtime-install.sh"
  # Per variable: the other repos (harbor#736) resolve to STUB_PI / STUB_PO, unset = no repo there; yard's bootstrap
  # clone (a BOX row, under the sandboxed HOME) is the real reader's answer.
  printf '#!/bin/sh\ncase "$1" in --private|--conf) exec sh "%s/bin/scope-roots.sh" "$@" ;; esac\n[ "$1" = --get ] || exit 0\ncase "$2" in HARBOR_PROJECT_INIT|HARBOR_SCOPE_SCAFFOLDER) printf "%%s" "${STUB_PI:-}" ;; HARBOR_ORCHESTRATOR|HARBOR_SCOPE_FLEET_CONTROLLER) printf "%%s" "${STUB_PO:-}" ;; HARBOR_SCOPE_SCAFFOLDER_CLONE) exec sh "%s/bin/scope-roots.sh" "$@" ;; *) printf "%%s" "$STUB_REPO" ;; esac\n' "$T_ROOT" "$T_ROOT" > "$T/src/bin/scope-roots.sh"
  cat > "$T/src/bin/deploy-install-stamp.sh" <<'EOS'
#!/bin/sh
case "$1" in
  --check) [ "${STUB_STAMP_RC:-0}" = 0 ] && exit 0
           echo "  FAIL: $3 would remove 1 installed commit(s) from $2"; echo "  fix: none automatic — see the stub"
           echo "  note: abc1234 the stubbed lost fix"; exit "$STUB_STAMP_RC" ;;
  --show) echo "stamp shown" ;;
esac
EOS
  printf '#!/bin/sh\ncat "$STUB_GI" 2>/dev/null; exit 0\n' > "$T/src/bin/admission-integrity.sh"
  printf '#!/bin/sh\ncat "$STUB_SKILLS" 2>/dev/null; exit 0\n' > "$T/src/bin/skills-list.stub"
  printf '#!/bin/sh\nexit "${STUB_COLLIDE_RC:-0}"\n' > "$T/src/bin/skill-collision-verify.sh"
  # pin-instructions on the install standard takes --live, never a positional dir (exit 2, as the real one).
  printf '#!/bin/sh\ncase "$*" in\n "--print --live") cat "$STUB_B8" ;;\n "--apply --live") printf "pin-instructions %%s\\n" "$*" >> "$STUB_LOG"; cp "$STUB_B8" "$HOME/.claude/.helm-instructions.sha256" ;;\n *) echo "pin-instructions: usage" >&2; exit 2 ;;\nesac\n' > "$T/src/bin/pin-instructions.sh"
  cat > "$T/src/bin/drift-install.sh" <<'EOS'
#!/bin/sh
echo "── install-drift · [check:install-drift] x/bin vs HEAD"
[ "${STUB_STALE:-0}" = 0 ] || { echo "  FAIL: stale guard-x.sh (installed copy is 1 commit(s) behind HEAD)"; echo "  fix: none automatic — see the stub"; }
echo "  note: current=3 stale=${STUB_STALE:-0} modified=0 unsourced=0"
EOS
  # floor-verify: STUB_FV=b8 fails only B8, STUB_FV=bash fails a guard probe too.
  cat > "$T/src/bin/admission-verify.sh" <<'EOS'
#!/bin/sh
echo "── floor-verify · x"; echo "  ok: present: admission-bash.sh"
case "${STUB_FV:-}" in
  b8)   echo "  FAIL: B8: instruction surfaces changed since pinning"; echo "  fix: none automatic — see B8"
        echo "  note: FLOOR IS NOT FULLY ON — 1 check(s) failed"; echo "floor-verify: 1 ok, 1 failed, 0 warnings"; exit 1 ;;
  bash) echo "  FAIL: B8: instruction surfaces changed since pinning"; echo "  fix: none automatic — see B8"
        echo "  FAIL: DOES NOT BLOCK: pipe-to-shell (exit 0)"; echo "  fix: none automatic — see guard-bash"
        echo "  note: FLOOR IS NOT FULLY ON — 2 check(s) failed"; echo "floor-verify: 1 ok, 2 failed, 0 warnings"; exit 1 ;;
  crash) echo "floor-verify: killed before its verdict"; exit 137 ;;
esac
echo "  note: FLOOR IS ON — guards present, wired, and blocking."; echo "floor-verify: 1 ok, 0 failed, 0 warnings"
EOS
  printf '#!/bin/sh\nexit 0\n' > "$T/src/bin/drift-reference-check.sh"
  printf '#!/bin/sh\nexit 0\n' > "$T/src/bin/harbor"
  # skills-install's dry runs (skills and commands) answer from STUB_SKILLS / STUB_CMDS, in its line shape.
  cat > "$T/src/bin/skill-install.sh" <<'EOS'
#!/bin/sh
case " $* " in *" --apply "*) ;;
  *" commands "*) cat "$STUB_CMDS" 2>/dev/null; exit 0 ;;
  *" --all "*) printf 'skill-install.sh %s\n' "$*" >> "$STUB_LOG.dry"; cat "$STUB_SKILLS" 2>/dev/null; exit "${STUB_SKILLS_RC:-0}" ;;
esac
exec sh "$(dirname "$0")/skills-install.real" "$@"
EOS
  printf '%s\n' "$_stub_body" | sed 's/\$(basename "\$0")/skill-install.sh/' > "$T/src/bin/skills-install.real"
  printf 'pack\n' > "$T/src/inject.d/box/10-a.md"; printf 'old pack\n' > "$T/src/inject.d/box/20-old.md"
  mkdir -p "$T/src/commands"; printf 'v1\n' > "$T/src/commands/x.md"; printf 'book\n' > "$T/src/skills/skill-catalog/SKILL.md"
  chmod +x "$T/src/bin/"*
  git -C "$T/src" init -q -b main && git -C "$T/src" add -A && git -C "$T/src" -c user.name=t -c user.email=t@t commit -q -m init
  # history then holds a withdrawn pack (20-old) and an older command (x v1)
  git -C "$T/src" rm -q inject.d/box/20-old.md && printf 'v2\n' > "$T/src/commands/x.md"
  git -C "$T/src" -c user.name=t -c user.email=t@t commit -qam two
  git clone -q --bare "$T/src" "$T/origin.git" && git clone -q "$T/origin.git" "$REPO"
  cp "$REPO/inject.d/box/10-a.md" "$C/inject.d/10-a.md"; printf '{}\n' > "$C/settings.json"
  printf 'aaa  CLAUDE.md\n' > "$C/.helm-instructions.sha256"; cp "$C/.helm-instructions.sha256" "$T/b8"
  ln -s "$REPO/bin/harbor" "$H/.local/bin/harbor"; : > "$LOGF"
  # Both other repos reachable, as on a set-up box: deploy fails an unreachable one it was asked to
  # install. A case models an absent repo by unsetting STUB_PI / STUB_PO.
  STUB_PI="$T/pi"; STUB_PO="$T/po"; export STUB_PI STUB_PO; xrepo "$STUB_PI" install; xrepo "$STUB_PO" install
}
# BSD `script -q FILE cmd...`; util-linux wants `script -qec "cmd" FILE` (harbor#865).
pty() { # <cmd> [args...]
  if [ "$(uname -s)" = Darwin ]; then script -q /dev/null "$@"; return; fi
  _pc=''; for _pa in "$@"; do _pc="$_pc '$(printf '%s' "$_pa" | sed "s/'/'\\\\''/g")'"; done
  script -qec "$_pc" /dev/null
}
# A suite that answers prompts calls this first. The confinement refuses openpty (harbor#555), which failed every
# prompted case as a deploy defect: say it once, red, and stop. CI and a terminal open one.
need_pty() {
  pty true </dev/null >/dev/null 2>&1 && return 0
  t_fail "no pseudo-terminal can be opened here (inside the confinement, openpty is refused): run this suite from CI or a terminal"
  t_done
}
run() { # [answers] -- deploy args. With answers, under a pty; without, stdin is /dev/null.
  _ans="$1"; shift
  _env="HOME=$H STUB_LOG=$LOGF STUB_REPO=$REPO STUB_GI=$T/gi STUB_SKILLS=$T/skills STUB_CMDS=$T/cmds STUB_B8=$T/b8"
  [ -z "${STUB_FV:-}" ] || _env="$_env STUB_FV=$STUB_FV"
  [ -z "${STUB_PI:-}" ] || _env="$_env STUB_PI=$STUB_PI"
  [ -z "${STUB_PO:-}" ] || _env="$_env STUB_PO=$STUB_PO"
  # VIA=harbor: deploy reached as `harbor deploy`, through the repo's own dispatcher, from / (not the repo).
  _cwd=.; if [ "${VIA:-}" = harbor ]; then _cwd=/; set -- "$REPO/bin/harbor" deploy "$@"; else set -- "$REPO/bin/deploy.sh" "$@"; fi
  if [ -n "$_ans" ]; then
    rm -f "$T/done"
    { sleep 1; printf "$_ans"; _i=0; while [ ! -f "$T/done" ] && [ "$_i" -lt 90 ]; do sleep 1; _i=$((_i + 1)); done; } \
      | { cd "$_cwd" && pty env -u CLAUDE_CONFIG_DIR -u HARBOR_SCOPE_LOCAL_BIN -u HARBOR_LOCAL_BIN CLAUDECODE="${CC:-}" $_env sh "$@" >"$T/out" 2>&1; echo $? >"$T/rc"; touch "$T/done"; }
    RC="$(cat "$T/rc")"
  else
    RC=0
    ( cd "$_cwd" && env -u CLAUDE_CONFIG_DIR -u HARBOR_SCOPE_LOCAL_BIN -u HARBOR_LOCAL_BIN CLAUDECODE="${CC:-}" $_env sh "$@" ) >"$T/out" 2>&1 </dev/null || RC=$?
  fi
  tr -d '\r' <"$T/out" >"$T/out.txt"
}
out() { cat "$T/out.txt"; }
applied() { grep -- '--apply' "$LOGF" | awk '{print $1, $2}' | tr '\n' ','; }
pins() { grep -c '^pin-instructions' "$LOGF"; }
refuse() { # <label> <reason> — a preflight refusal stops before any --apply
  run '' --live
  t_eq "$1: exit" 1 "$RC"
  t_has "$1: preflight failed" "$(out)" "PREFLIGHT FAILED"
  t_has "$1: reason" "$(out)" "$2"
  t_eq "$1: nothing applied" "" "$(applied)"
  t_exit "$1: every FAIL is followed by its fix line" 0 fixfollows
}
fixfollows() { awk '/^  FAIL: / { f = 1; next } f && !/^  fix: / { bad = 1 } { f = 0 } END { exit bad }' "$T/out.txt"; }
dlog() { cat "$C"/backups/deploy/*/log 2>/dev/null; }  # deploy's own log file(s) under the case's config dir
commit_push() { git -C "$REPO" -c user.name=t -c user.email=t@t commit -qam "$1" && git -C "$REPO" push -q origin main; }

# A `just` first on PATH (harbor#736): `--summary` reads <dir>/.recipes; `install [--apply|--check]` logs
# its argv to STUB_LOG, prints <dir>/.out.<mode> if there is one, and exits with <dir>/.rc.<dry|apply|check>
# (default 0). No real repo is touched.
cat > "$T_BIN/just" <<'EOS'
#!/bin/sh
jf=''; wd=''
while [ $# -gt 0 ]; do case "$1" in --justfile) jf="$2"; shift 2 ;; --working-directory) wd="$2"; shift 2 ;; *) break ;; esac; done
case "${1:-}" in
  --summary) cat "$wd/.recipes" 2>/dev/null; exit 0 ;;
  install) shift; m=dry; case " $* " in *" --apply "*) m=apply ;; *" --check "*) m=check ;; esac
    printf 'just %s install%s\n' "$wd" "${*:+ $*}" >> "$STUB_LOG"
    rc="$(cat "$wd/.rc.$m" 2>/dev/null || echo 0)"
    echo "just install ($m) in $wd: rc $rc"
    # The child's own words on that mode (a refusal's FAIL and fix lines), when a case wrote them.
    [ ! -f "$wd/.out.$m" ] || cat "$wd/.out.$m"
    exit "$rc" ;;
esac
exit 0
EOS
chmod +x "$T_BIN/just"
xrepo() { # <dir> <recipes> — a repo deploy reaches through STUB_PI / STUB_PO
  mkdir -p "$1"; printf 'install:\n\techo stub\n' > "$1/justfile"; printf '%s\n' "$2" > "$1/.recipes"
}
xgit() { # <dir> — make an xrepo dir a real clone of a bare origin beside it (harbor#736: deploy fetches it)
  git -C "$1" init -q -b main && git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@t commit -qm init
  git clone -q --bare "$1" "$1.origin.git" && git -C "$1" remote add origin "$1.origin.git"
  git -C "$1" fetch -q origin && git -C "$1" branch -q --set-upstream-to=origin/main main
}
xadvance() { # <dir> — merge a commit into the clone's origin that the clone has not fetched
  rm -rf "$1.other"; git clone -q "$1.origin.git" "$1.other" && printf 'merged elsewhere\n' > "$1.other/merged.txt"
  git -C "$1.other" add -A && git -C "$1.other" -c user.name=t -c user.email=t@t commit -qm merged && git -C "$1.other" push -q origin main
}
