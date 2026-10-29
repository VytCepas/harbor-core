#!/usr/bin/env sh
# RECOVER (harbor#34, #765): deploy-restore.sh parses every flag, writes only with --apply, restores exactly a
# deploy snapshot's entries, never touches MEMORY, keeps every harbor#110 refusal, and restores only
# bytes the hash ledger records (harbor#769). On the install standard its apply run keeps its log and
# its move-aside together in <dir>/backups/restore/<TS>/, and every FAIL is followed by its fix line.
# The live config is a FIXTURE at the sandbox HOME's .claude, carrying a log token and a MEMORY git
# remote so sandbox-make's exclusions can fail; section 9 witnesses it. runtime-install ships this file
# and core.sh to the box's bin/ and lib/ (harbor#727); there it tests the installed scripts.
T_STANDALONE=1
# harbor#961 W2: in the repo the harness is two levels up; runtime-install ships this file as <cfg>/bin/recover-test.sh beside <cfg>/lib/core.sh
_rh="$(dirname "$0")/../lib"; [ -f "$_rh/core.sh" ] || _rh="$(dirname "$0")/../../lib"
. "$_rh/core.sh"; t_init
unset CLAUDE_CONFIG_DIR  # the live dir is then $HOME/.claude, as on CI; each step names its dir
# deploy-restore.sh reports physical paths (install-lib's il_target), so the sandbox is named physically.
T_TMP="$(cd "$T_TMP" && pwd -P)"; HOME="$T_TMP/home"; export HOME
B="$T_ROOT/bin"; L="$HOME/.claude"; SB="$HOME/.claude-recover-test"; OUT="$T_TMP/restore.out"
yn() { if "$@"; then echo yes; else echo no; fi; }
rs() { env -u CLAUDE_CONFIG_DIR sh "$B/deploy-restore.sh" "$@" >"$OUT" 2>&1; echo "exit $?"; }  # → "exit N"
out() { cat "$OUT"; }
tree() { (cd "$1" && find . -print | LC_ALL=C sort | while IFS= read -r f; do if [ -f "$f" ]; then cksum "$f"; else echo "$f"; fi; done) | cksum; }
wired() { printf '{"hooks":{"%s":[{"matcher":"Bash","hooks":[{"type":"command","command":"sh %s/bin/guard-bash.sh"}]}]}}\n' "$1" "$2"; }
guard() { printf '#!/bin/sh\n[ "${HELM_DISABLE_FLOOR:-0}" = "1" ] && exit 0\nexit 0\n' > "$1"; }
b6stub() { printf '#!/bin/sh\n%s\n' "$2" > "$1/bin/guard-integrity.sh"; }  # <cfg> <body>
snap() { # <cfg> <name> <set entry…> — deploy's format: config.tgz of the entries present, set.txt of all
  _c="$1"; _d="$1/backups/$2"; shift 2; mkdir -p "$_d"; printf '%s\n' "$@" > "$_d/set.txt"; _have=''
  for _e in "$@"; do for _p in "$_c"/$_e; do [ -e "$_p" ] && _have="$_have ${_p##*/}"; done; done
  # shellcheck disable=SC2086
  (cd "$_c" && tar -czf "$_d/config.tgz" $_have); record "$_c" "$_d/config.tgz"
}
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{print $1}'; }
record() { # <cfg> <archive> — append the row deploy appends to <cfg>/.helm-snapshots (harbor#769, #770)
  _rel="${2#"$1"/}"; _st="${2%/*}/set.txt"; _lbt="${2%/*}/local-bin.tsv"; _s=''
  [ "${2##*/}" = config.tgz ] && [ -f "$_st" ] && _s=" set=$(sha < "$_st")"
  [ "${2##*/}" = config.tgz ] && [ -f "$_lbt" ] && _s="$_s bin=$(sha < "$_lbt")"
  printf '%s %s 2026-01-01T00:00:00Z%s\n' "$(sha < "$2")" "$_rel" "$_s" >> "$1/.helm-snapshots"
}
# The last run's own dir, read from its `log:` line: its log and what it moved aside live there.
rundir() { sed -n 's|^log: \(.*\)/log$|\1|p' "$OUT" | tail -1; }
aside() { rundir; }
held() { _rd="$(rundir)"; [ -n "$_rd" ] && (cd "$_rd" && ls -A | grep -vx log | tr '\n' ' '); }  # beside the log
# A refused --apply keeps its log (the install standard), so "wrote nothing" is read outside it.
tree_but_log() { (cd "$1" && find . -path ./backups/restore -prune -o -print | LC_ALL=C sort | while IFS= read -r f; do if [ -f "$f" ]; then cksum "$f"; else echo "$f"; fi; done) | cksum; }
fixfollows() { awk '/^  FAIL: / { f = 1; next } f && !/^  fix: / { bad = 1 } { f = 0 } END { exit bad }' "$OUT"; }
SET='settings.json bin lib hooks skills .helm-pins .sec0-baseline.sha256 settings.json.bak.*'

mkdir -p "$L/skills/demo" "$L/bin" "$L/plugins" "$L/MEMORY/.git" "$L/backups"
wired PreToolUse "$L" > "$L/settings.json"
printf 'fixture-sec0\n' > "$L/.sec0-baseline.sha256"; printf '# demo\n' > "$L/skills/demo/SKILL.md"
guard "$L/bin/guard-bash.sh"; guard "$L/bin/deploy-restore.sh"; printf 'plugin\n' > "$L/plugins/p.txt"
printf 'identity\n' > "$L/MEMORY/IDENTITY.md"; printf '[remote "origin"]\n\turl = fixture\n' > "$L/MEMORY/.git/config"
printf 'fixture-token-not-a-secret\n' > "$L/.helm-log-token"
snap "$L" deploy-20260101-000000-1 $SET
LIVE_BEFORE="$(tree "$L")"

t_section "0 the live dir under test is the fixture inside the suite's sandbox"
t_eq "0 the live dir resolves under the suite's temp dir" yes "$(case "$L" in ("$T_TMP"/*) echo yes ;; (*) echo no ;; esac)"

t_section "1 a sandbox from the live config carries no credential and no git remote"
t_eq "1 precondition: the live fixture holds a log token" yes "$(yn [ -e "$L/.helm-log-token" ])"
t_eq "1 precondition: the live fixture holds a MEMORY git remote" yes "$(yn [ -e "$L/MEMORY/.git" ])"
t_exit "1 sandbox-make builds the sandbox" 0 sh "$B/test-sandbox-make.sh" "$SB" --fresh
t_eq "1 the sandbox marker is written" yes "$(yn [ -f "$SB/.helm-sandbox" ])"
t_eq "1 MEMORY itself is copied" yes "$(yn [ -f "$SB/MEMORY/IDENTITY.md" ])"
t_eq "1 the log token did not leak into the sandbox" no "$(yn [ -e "$SB/.helm-log-token" ])"
t_eq "1 the MEMORY git remote did not leak into the sandbox" no "$(yn [ -e "$SB/MEMORY/.git" ])"
LIVE_BEFORE="$(tree "$L")"  # sandbox-make reads live; re-baseline after it, before any restore runs

t_section "2 every flag is parsed, in any position, and only --apply writes (harbor#765)"
t_eq "2 --live --dry-run is a dry run" "exit 0" "$(rs --live --dry-run)"
t_has "2 --live --dry-run says so" "$(out)" "── restore · plan for $L (dry run: nothing is written)"
t_has "2 the dry run names the snapshot it would restore" "$(out)" "deploy-20260101-000000-1/config.tgz"
t_eq "2 --live --dry-run wrote nothing" "$LIVE_BEFORE" "$(tree "$L")"
t_has "2 --live --dry-run: its apply hint names the snapshot" "$(out)" "  note: next: sh $B/deploy-restore.sh --apply --from '$L/"
t_hasnt "2 ...and drops --dry-run, which beside --apply is a usage error" "$(out)" "--dry-run"
t_eq "2 --live --help exits 0" "exit 0" "$(rs --live --help)"
t_has "2 --live --help prints the usage" "$(out)" "--from SNAPSHOT"
t_hasnt "2 --live --help plans nothing" "$(out)" "── restore · plan for"
t_eq "2 --live --help wrote nothing" "$LIVE_BEFORE" "$(tree "$L")"
t_eq "2 --live alone is a dry run" "exit 0" "$(rs --live)"; t_has "2 --live alone says so" "$(out)" "── restore · plan for"
t_has "2 the dry run ends on the summary line" "$(tail -1 "$OUT")" "restore: 0 ok, 0 failed, 0 warnings"
t_has "2 ...after the command that applies it, which its own gate takes" "$(out)" "  note: next: sh $B/deploy-restore.sh --apply --from '$L/backups/deploy-20260101-000000-1' --live"
t_hasnt "2 a dry run names no log file" "$(out)" "log: "
t_eq "2 an unknown flag last exits 2" "exit 2" "$(rs --live --bogus)"
t_eq "2 an unknown flag first exits 2, even beside --apply" "exit 2" "$(rs --bogus --apply --live)"
t_has "2 an unknown flag prints the usage" "$(out)" "--from SNAPSHOT"
t_eq "2 a positional target is refused" "exit 2" "$(rs "$L")"
t_eq "2 --apply --dry-run together is refused" "exit 2" "$(rs --apply --dry-run --live)"
t_eq "2 --live and --dir together are refused" "exit 2" "$(rs --live --dir "$SB")"
t_eq "2 no target is refused" "exit 2" "$(rs --apply)"
t_eq "2 --dir with no value is refused" "exit 2" "$(rs --dir)"
t_eq "2 --from given twice is refused" "exit 2" "$(rs --live --from "$L/backups" --from "$L/backups")"
t_has "2 ...saying so" "$(out)" "restore: --from given twice"
t_eq "2 --dir cannot swallow the next flag" "exit 2" "$(rs --dir --apply)"
t_eq "2 a trailing-slash live path without --live is refused" "exit 1" "$(rs --apply --dir "$L/")"
t_has "2 the refusal says why" "$(out)" "explicit --live"
t_has "2 ...and its fix is the --live spelling" "$(out)" "  fix: sh $B/deploy-restore.sh --apply --live"
t_eq "2 ...and so is its dry run" "exit 1" "$(rs --dir "$L/")"
ln -s "$L" "$HOME/cfg-link"
t_eq "2 a symlink to the live dir without --live is refused" "exit 1" "$(rs --apply --dir "$HOME/cfg-link")"
_r="$(env CLAUDE_CONFIG_DIR="$SB" sh "$B/deploy-restore.sh" --apply --live >/dev/null 2>&1; echo "exit $?")"
t_eq "2 CLAUDE_CONFIG_DIR naming another dir is refused, never followed" "exit 2" "$_r"
t_eq "2 no refusal above wrote anything" "$LIVE_BEFORE" "$(tree "$L")"

t_section "3 a deploy snapshot comes back exactly; the current copies move aside"
R="$HOME/cfg-r"; mkdir -p "$R/bin" "$R/lib" "$R/skills/demo" "$R/MEMORY/.git" "$R/MEMORY/OBSERVABILITY" "$R/projects"
printf '{"v":1}\n' > "$R/settings.json"; guard "$R/bin/guard-bash.sh"; b6stub "$R" 'exit 0'
printf 'core v1\n' > "$R/lib/core.sh"; printf '# demo\n' > "$R/skills/demo/SKILL.md"; printf 'sec0 v1\n' > "$R/.sec0-baseline.sha256"
printf 'identity\n' > "$R/MEMORY/IDENTITY.md"; printf 'fixture remote\n' > "$R/MEMORY/.git/config"
printf 'ledger\n' > "$R/MEMORY/OBSERVABILITY/l.jsonl"; printf 'h1\n' > "$R/history.jsonl"; printf 'p\n' > "$R/projects/p.jsonl"
snap "$R" deploy-20260101-000000-1 $SET; RS="$R/backups/deploy-20260101-000000-1"
cp "$R/settings.json" "$T_TMP/settings.v1"; cp "$R/.sec0-baseline.sha256" "$T_TMP/sec0.v1"
printf '{"v":2}\n' > "$R/settings.json"; printf 'core v2\n' > "$R/lib/core.sh"; printf 'x\n' > "$R/lib/extra.sh"
mkdir -p "$R/skills/new" "$R/hooks"; printf '# new\n' > "$R/skills/new/SKILL.md"; printf 'h\n' > "$R/hooks/h.py"
printf '{}\n' > "$R/settings.json.bak.20260102T000000Z"; rm -f "$R/.sec0-baseline.sha256"; rm -rf "$R/skills/demo"
printf 'identity, edited after the snapshot\n' > "$R/MEMORY/IDENTITY.md"; printf 'h2\n' > "$R/history.jsonl"
R_BEFORE="$(tree "$R")"
t_eq "3 the dry run" "exit 0" "$(rs --dir "$R")"
t_has "3 the dry run names what the snapshot does not hold" "$(out)" "moved aside and not put back: hooks settings.json.bak.20260102T000000Z"
t_eq "3 the dry run wrote nothing" "$R_BEFORE" "$(tree "$R")"
t_eq "3 --apply restores" "exit 0" "$(rs --apply --dir "$R")"
A="$(aside "$RS")"
t_eq "3 the current copies went to <dir>/backups/restore/<TS>/, beside the run's log" yes \
  "$(case "$A" in ("$R"/backups/restore/*) [ -f "$A/log" ] && [ -d "$A/bin" ] && echo yes || echo no ;; (*) echo no ;; esac)"
t_eq "3 ...and not into the snapshot dir" "" "$(ls -d "$RS"/after-restore-* 2>/dev/null)"
t_has "3 the log holds the run's lines, timestamped" "$(cat "$A/log" 2>/dev/null)" "Z   ok: restored $R from $RS/config.tgz"
t_has "3 the apply ends on the summary, then the log" "$(tail -2 "$OUT" | head -1)" "restore: 2 ok, 0 failed, 0 warnings"
t_exit "3 settings.json is the snapshot's, byte for byte" 0 cmp -s "$T_TMP/settings.v1" "$R/settings.json"
t_eq "3 the replaced settings.json was moved aside, not deleted" '{"v":2}' "$(cat "$A/settings.json" 2>/dev/null)"
t_exit "3 an entry the run deleted is back" 0 cmp -s "$T_TMP/sec0.v1" "$R/.sec0-baseline.sha256"
t_eq "3 a skill the run deleted is back" "# demo" "$(cat "$R/skills/demo/SKILL.md" 2>/dev/null)"
t_eq "3 lib/ comes back from the snapshot" "core v1" "$(cat "$R/lib/core.sh")"
t_eq "3 a file added under lib/ is not left live" no "$(yn [ -e "$R/lib/extra.sh" ])"
t_eq "3 ...it is aside" yes "$(yn [ -f "$A/lib/extra.sh" ])"
t_eq "3 a skill added after the snapshot is not left live" no "$(yn [ -e "$R/skills/new" ])"
t_eq "3 ...it is aside" yes "$(yn [ -f "$A/skills/new/SKILL.md" ])"
t_eq "3 an entry the snapshot recorded as absent is moved aside" no "$(yn [ -e "$R/hooks" ])"
t_eq "3 ...not deleted" yes "$(yn [ -f "$A/hooks/h.py" ])"
t_eq "3 a glob in the set covers prod-guard's settings.json.bak.*" yes "$(yn [ -f "$A/settings.json.bak.20260102T000000Z" ])"
t_eq "3 MEMORY is untouched: the edit made after the snapshot survives" "identity, edited after the snapshot" "$(cat "$R/MEMORY/IDENTITY.md")"
t_eq "3 MEMORY/.git survives" "fixture remote" "$(cat "$R/MEMORY/.git/config" 2>/dev/null)"
t_eq "3 MEMORY/OBSERVABILITY survives" ledger "$(cat "$R/MEMORY/OBSERVABILITY/l.jsonl" 2>/dev/null)"
t_eq "3 MEMORY is not moved aside" no "$(yn [ -e "$A/MEMORY" ])"
t_eq "3 an entry outside the set is untouched" h2 "$(cat "$R/history.jsonl")"
t_eq "3 ...and so is a directory outside it" p "$(cat "$R/projects/p.jsonl" 2>/dev/null)"
t_has "3 it prints the next session's B6 verdict" "$(out)" "the next session's B6 verdict: clean"

t_section "3b a snapshot that holds MEMORY (the retired baseline's shape) still leaves MEMORY alone"
G="$HOME/cfg-g"; mkdir -p "$G/MEMORY/.git"; printf 'old identity\n' > "$G/MEMORY/IDENTITY.md"; printf '{"v":1}\n' > "$G/settings.json"
(cd "$G" && tar -czf "$T_TMP/with-memory.tgz" settings.json MEMORY); record "$G" "$T_TMP/with-memory.tgz"
printf 'identity now\n' > "$G/MEMORY/IDENTITY.md"; printf 'remote now\n' > "$G/MEMORY/.git/config"; printf '{"v":2}\n' > "$G/settings.json"
t_eq "3b a bare .tgz holding MEMORY restores" "exit 0" "$(rs --apply --dir "$G" --from "$T_TMP/with-memory.tgz")"
t_eq "3b its settings.json came back" '{"v":1}' "$(cat "$G/settings.json")"
t_eq "3b MEMORY was not overwritten from it" "identity now" "$(cat "$G/MEMORY/IDENTITY.md")"
t_eq "3b MEMORY/.git was not touched" "remote now" "$(cat "$G/MEMORY/.git/config" 2>/dev/null)"
t_eq "3b MEMORY was not moved aside" no "$(yn [ -e "$(aside)/MEMORY" ])"
t_eq "3b the run dir is the target's, not beside the bare .tgz" yes "$(case "$(aside)" in ("$G"/backups/restore/*) echo yes ;; (*) echo no ;; esac)"
t_has "3b the plan says MEMORY was left alone" "$(out)" "the snapshot names: MEMORY"

t_section "4 which snapshot: the newest by name, or --from; an unrecorded or unreadable one is refused"
N="$HOME/cfg-n"; mkdir -p "$N/bin"; b6stub "$N" 'exit 0'
printf '{"v":"old"}\n' > "$N/settings.json"; snap "$N" deploy-20260101-000000-1 $SET
b6stub "$N" "printf '{\"continue\":false,\"stopReason\":\"stub block\"}'"
printf '{"v":"new"}\n' > "$N/settings.json"; snap "$N" deploy-20260201-000000-2 $SET
touch "$N/backups/deploy-20260101-000000-1/config.tgz"  # the older one is newer by mtime: the name decides
printf '{"v":"now"}\n' > "$N/settings.json"
t_eq "4 restore with no --from" "exit 0" "$(rs --apply --dir "$N")"
t_eq "4 it restored the newest snapshot by name" '{"v":"new"}' "$(cat "$N/settings.json")"
t_has "4 a blocking B6 verdict is printed" "$(out)" "B6 verdict: BLOCKED"
t_has "4 ...with the gate's reason" "$(out)" "stub block"
t_has "4 ...as a WARN the operator acts on" "$(out)" "  WARN: the next session's B6 verdict: BLOCKED"
t_exit "4 ...followed by its fix line" 0 fixfollows
t_eq "4 --from names an older snapshot" "exit 0" "$(rs --apply --dir "$N" --from "$N/backups/deploy-20260101-000000-1")"
t_eq "4 ...and it is the one restored" '{"v":"old"}' "$(cat "$N/settings.json")"
t_eq "4 --from also takes the config.tgz itself" "exit 0" "$(rs --dir "$N" --from "$N/backups/deploy-20260201-000000-2/config.tgz")"
mkdir -p "$N/backups/deploy-20260301-000000-3"; printf 'not a tarball\n' > "$N/backups/deploy-20260301-000000-3/config.tgz"
N_BEFORE="$(tree_but_log "$N")"
t_eq "4 an unrecorded newest snapshot is refused, not skipped" "exit 1" "$(rs --apply --dir "$N")"
t_has "4 the refusal lists the snapshots to pick from" "$(out)" "deploy-20260201-000000-2"
t_eq "4 the refusal wrote nothing but its log" "$N_BEFORE" "$(tree_but_log "$N")"
t_eq "4 ...which holds only the log, and the refusal" " log" "$(held) $(ls "$(rundir)" 2>/dev/null)"
t_has "4 ...the kept log names the refusal (a refused preflight is logged)" "$(cat "$(rundir)/log" 2>/dev/null)" "FAIL: refusing $N/backups/deploy-20260301-000000-3/config.tgz"
t_exit "4 every FAIL is followed by its fix line" 0 fixfollows
record "$N" "$N/backups/deploy-20260301-000000-3/config.tgz"; N_BEFORE="$(tree_but_log "$N")"
t_eq "4 a recorded snapshot that is not a tarball is refused" "exit 1" "$(rs --apply --dir "$N")"
t_has "4 ...as unreadable" "$(out)" "is unreadable"
t_eq "4 ...and wrote nothing but its log" "$N_BEFORE" "$(tree_but_log "$N")"
t_exit "4 ...with its fix line" 0 fixfollows

t_section "5 refusals: no snapshot, no dir, a member outside the config dir"
E="$HOME/cfg-empty"; mkdir -p "$E/backups"; printf '{}\n' > "$E/settings.json"; E_BEFORE="$(tree_but_log "$E")"
t_eq "5 no deploy snapshot is refused" "exit 1" "$(rs --apply --dir "$E")"
t_has "5 the refusal names where snapshots come from" "$(out)" "no deploy snapshot"
t_eq "5 ...and wrote nothing but its log" "$E_BEFORE" "$(tree_but_log "$E")"
t_exit "5 ...with its fix line" 0 fixfollows
t_eq "5 a target that is not a dir is refused" "exit 1" "$(rs --dir "$HOME/no-such-dir")"
t_has "5 ...as not a config dir, before any snapshot is looked for" "$(out)" "  FAIL: no config dir at $HOME/no-such-dir"
mkdir -p "$T_TMP/evil"; printf 'x\n' > "$T_TMP/evil/f"
if (cd "$T_TMP/evil" && tar -czf "$T_TMP/evil.tgz" -s ',^f,../f,' f) 2>/dev/null && tar -tzf "$T_TMP/evil.tgz" | grep -q '^\.\./f'; then
  record "$E" "$T_TMP/evil.tgz"; E_BEFORE="$(tree_but_log "$E")"
  t_eq "5 a member outside the config dir is refused, even when recorded" "exit 1" "$(rs --apply --dir "$E" --from "$T_TMP/evil.tgz")"
  t_has "5 ...by the member check" "$(out)" "member outside the config dir"
  t_eq "5 ...before anything moved" "$E_BEFORE" "$(tree_but_log "$E")"
else echo "  SKIP 5: this tar cannot write a ../ member"; fi

t_section "6 a snapshot that predates the floor is refused (harbor#110)"
F="$HOME/cfg-f"; mkdir -p "$F/bin"; printf '{"hooks":{}}\n' > "$F/settings.json"
snap "$F" deploy-20260101-000000-1 $SET; FS="$F/backups/deploy-20260101-000000-1"
guard "$F/bin/guard-bash.sh"
t_eq "6 a snapshot that would remove a guard is refused" "exit 1" "$(rs --apply --dir "$F")"
t_has "6 the refusal names the guard" "$(out)" "bin/guard-bash.sh"
t_eq "6 the refusal was clean: the guard is still there" yes "$(yn [ -f "$F/bin/guard-bash.sh" ])"
t_eq "6 ...and nothing was moved aside: the run dir holds only its log" "" "$(held)"
t_exit "6 ...and the FAIL is followed by its fix line" 0 fixfollows
t_has "6 ...which is the --accept-loss command, spelled for this dir" "$(out)" "  fix: sh $B/deploy-restore.sh --apply --from '$FS' --dir '$F' --accept-loss"
t_eq "6 its dry run refuses too" "exit 1" "$(rs --dir "$F")"
t_has "6 ...saying what --apply would refuse" "$(out)" "  FAIL: --apply would refuse: this snapshot does not hold floor surfaces"
t_eq "6 --accept-loss proceeds" "exit 0" "$(rs --apply --dir "$F" --accept-loss)"
t_has "6 ...with a WARN naming exactly what is lost" "$(out)" "  WARN: --accept-loss: this snapshot does not hold floor surfaces the target has, so restoring it removes them: bin/guard-bash.sh"
t_eq "6 --accept-loss really removes the guard" no "$(yn [ -f "$F/bin/guard-bash.sh" ])"
t_eq "6 ...into the aside dir" yes "$(yn [ -f "$(aside)/bin/guard-bash.sh" ])"
rm -rf "$FS"; snap "$F" deploy-20260101-000000-1 settings.json; guard "$F/bin/guard-bash.sh"
t_eq "6 a snapshot that does not cover bin/ leaves the guard alone, so no refusal" "exit 0" "$(rs --apply --dir "$F")"
t_eq "6 ...and the guard is still there" yes "$(yn [ -f "$F/bin/guard-bash.sh" ])"
rm -rf "$F/backups"; wired PreToolUse "$F" > "$F/settings.json"; snap "$F" deploy-20260101-000000-1 $SET
t_eq "6 a snapshot that agrees with the target restores (no false positive)" "exit 0" "$(rs --apply --dir "$F")"
rm -rf "$F/backups"; printf '{"hooks":{}}\n' > "$F/settings.json"; snap "$F" deploy-20260101-000000-1 $SET
wired PreToolUse "$F" > "$F/settings.json"
t_eq "6 guard present but its wiring absent from the snapshot is refused" "exit 1" "$(rs --apply --dir "$F")"
t_has "6 ...named as wiring" "$(out)" "wiring:guard-bash.sh"
if command -v jq >/dev/null 2>&1; then
  rm -rf "$F/backups"; wired PostToolUse "$F" > "$F/settings.json"; snap "$F" deploy-20260101-000000-1 $SET
  wired PreToolUse "$F" > "$F/settings.json"
  t_eq "6 the guard wired under the wrong event is still a loss" "exit 1" "$(rs --apply --dir "$F")"
else echo "  SKIP 6: no jq, and the coarse fallback cannot see the wrong-event case by construction"; fi
rm -rf "$F/backups"; mkdir -p "$F/.helm-pins"; printf 'aaa\n' > "$F/.helm-pins/guard-bash.sh.sha256"
snap "$F" deploy-20260101-000000-1 $SET; printf 'bbb\n' > "$F/.helm-pins/annotate-web.sh.sha256"
t_eq "6 a snapshot missing one pin the target holds is refused" "exit 1" "$(rs --apply --dir "$F")"
t_has "6 ...named per pin" "$(out)" ".helm-pins/annotate-web.sh.sha256"
rm -rf "$F/backups" "$F/.helm-pins"; snap "$F" deploy-20260101-000000-1 $SET; guard "$F/bin/deploy-restore.sh"
t_eq "6 a snapshot that would drop deploy-restore.sh itself is refused" "exit 1" "$(rs --apply --dir "$F")"
t_eq "6 ...and deploy-restore.sh is still there" yes "$(yn [ -f "$F/bin/deploy-restore.sh" ])"
rm -rf "$F/backups"; snap "$F" deploy-20260101-000000-1 bin
printf 'settings.json\n' >> "$F/backups/deploy-20260101-000000-1/set.txt"; record "$F" "$F/backups/deploy-20260101-000000-1/config.tgz"
t_eq "6 a snapshot whose set covers settings.json but holds none is refused" "exit 1" "$(rs --apply --dir "$F")"
t_has "6 ...as a floor loss" "$(out)" "settings.json(absent-or-unreadable-in-snapshot)"

t_section "7 a move that fails puts back what was already moved"
M="$HOME/cfg-m"; mkdir -p "$M/bin" "$M/skills/s"; printf '{"v":1}\n' > "$M/settings.json"
snap "$M" deploy-20260101-000000-1 $SET; printf '{"v":2}\n' > "$M/settings.json"
mkdir -p "$T_TMP/probe/d" "$T_TMP/probe/to"; chmod 0500 "$T_TMP/probe/d"
if mv "$T_TMP/probe/d" "$T_TMP/probe/to/" 2>/dev/null; then echo "  SKIP 7: this system moves a read-only dir"
else
  chmod 0500 "$M/skills"; M_BEFORE="$(tree_but_log "$M")"
  t_eq "7 a move aside that fails is a failure" "exit 1" "$(rs --apply --dir "$M")"
  t_has "7 ...that says it put things back" "$(out)" "putting back what was moved"
  t_eq "7 the target is exactly as it was, but for the run's log" "$M_BEFORE" "$(tree_but_log "$M")"
  t_eq "7 ...and nothing is left aside" "" "$(held)"
  chmod 0755 "$M/skills"
fi
chmod 0755 "$T_TMP/probe/d" 2>/dev/null || :

t_section "8 only bytes the hash ledger records are restored (harbor#769)"
K="$HOME/cfg-k"; mkdir -p "$K/bin"; printf '{"v":1}\n' > "$K/settings.json"
snap "$K" deploy-20260101-000000-1 $SET; KS="$K/backups/deploy-20260101-000000-1"; cp "$KS/config.tgz" "$T_TMP/k.good.tgz"
mkdir -p "$T_TMP/kt"; printf '{"v":"forged"}\n' > "$T_TMP/kt/settings.json"
(cd "$T_TMP/kt" && tar -czf "$KS/config.tgz" settings.json)  # a valid tarball, rewritten after the snapshot
printf '{"v":2}\n' > "$K/settings.json"; cp "$K/.helm-snapshots" "$T_TMP/k.ledger"; K_BEFORE="$(tree_but_log "$K")"
t_eq "8 a tampered snapshot is refused" "exit 1" "$(rs --apply --dir "$K")"
t_has "8 ...and the refusal says it changed after deploy recorded it" "$(out)" "CHANGED after deploy recorded it"
t_hasnt "8 ...and does not offer to record the tampered bytes" "$(out)" "record it from your own terminal"
t_eq "8 --accept-loss does not bypass the ledger" "exit 1" "$(rs --apply --dir "$K" --accept-loss)"
t_eq "8 its dry run refuses too" "exit 1" "$(rs --dir "$K")"
t_eq "8 the refusals wrote nothing but their logs" "$K_BEFORE" "$(tree_but_log "$K")"
cp "$T_TMP/k.good.tgz" "$KS/config.tgz"
t_eq "8 the recorded snapshot restores" "exit 0" "$(rs --apply --dir "$K")"
t_eq "8 ...its bytes" '{"v":1}' "$(cat "$K/settings.json")"
t_exit "8 a restore leaves the ledger byte-identical" 0 cmp -s "$T_TMP/k.ledger" "$K/.helm-snapshots"
mkdir -p "$T_TMP/kf"; printf '{"v":"foreign"}\n' > "$T_TMP/kf/settings.json"; (cd "$T_TMP/kf" && tar -czf "$T_TMP/foreign.tgz" settings.json)
t_eq "8 --from an unrecorded path is refused" "exit 1" "$(rs --apply --dir "$K" --from "$T_TMP/foreign.tgz")"
t_has "8 ...naming the ledger it is missing from" "$(out)" "/.helm-snapshots, the ledger deploy appends"
t_has "8 ...and how the operator records one they have checked" "$(out)" "record it from your own terminal"
t_eq "8 --accept-loss does not bypass it either, with no set.txt to trip over" "exit 1" \
  "$(rs --apply --dir "$K" --from "$T_TMP/foreign.tgz" --accept-loss)"
_fs="$(sha < "$T_TMP/foreign.tgz")"; _last="$(printf '%s' "$_fs" | cut -c64)"; [ "$_last" = 0 ] && _flip=1 || _flip=0
printf '%s%s %s 2026-01-01T00:00:00Z\n' "$(printf '%s' "$_fs" | cut -c1-63)" "$_flip" "$T_TMP/foreign.tgz" >> "$K/.helm-snapshots"
printf '%s0 %s 2026-01-01T00:00:00Z\n' "$_fs" "$T_TMP/foreign.tgz" >> "$K/.helm-snapshots"
printf 'junk %s 2026-01-01T00:00:00Z\n' "$_fs" >> "$K/.helm-snapshots"; K_BEFORE="$(tree_but_log "$K")"
t_eq "8 rows that share 63 characters, add one, or hold the hash in another field do not match" "exit 1" \
  "$(rs --apply --dir "$K" --from "$T_TMP/foreign.tgz")"
t_eq "8 ...and wrote nothing but its log" "$K_BEFORE" "$(tree_but_log "$K")"
cp "$T_TMP/k.ledger" "$K/.helm-snapshots"; printf 'projects\n' >> "$KS/set.txt"
t_eq "8 a set.txt changed after the snapshot is refused" "exit 1" "$(rs --apply --dir "$K")"
t_has "8 ...named as the set" "$(out)" "set.txt is not the set deploy recorded"
sed '$d' "$KS/set.txt" > "$T_TMP/set.tmp" && mv "$T_TMP/set.tmp" "$KS/set.txt"
mv "$K/.helm-snapshots" "$T_TMP/k.ledger.moved"; K_BEFORE="$(tree_but_log "$K")"
t_eq "8 with no ledger at all, nothing is restored" "exit 1" "$(rs --apply --dir "$K")"
t_has "8 ...and the refusal says the ledger is missing" "$(out)" "the ledger does not exist"
t_eq "8 ...and wrote nothing but its log" "$K_BEFORE" "$(tree_but_log "$K")"
_line="$(sed -n "s/^  fix: \(.*>> '.*\)$/\1/p" "$OUT")"
t_has "8 the refusal's fix line is the one command that records it" "$_line" "/.helm-snapshots'"
t_eq "8 ...exactly one such line" 1 "$(grep -c ">> '" "$OUT")"
sh -c "$_line"
t_eq "8 after the operator runs that line, the snapshot restores" "exit 0" "$(rs --apply --dir "$K")"
J="$HOME/cfg-j"; mkdir -p "$J"; printf '{"v":1}\n' > "$J/settings.json"; snap "$J" deploy-20260101-000000-1 settings.json '.helm-*'
cp "$J/.helm-snapshots" "$T_TMP/j.ledger"
t_eq "8 a recorded set whose glob matches .helm-* restores" "exit 0" "$(rs --apply --dir "$J")"
t_exit "8 ...and the ledger is never one of the entries it moves" 0 cmp -s "$T_TMP/j.ledger" "$J/.helm-snapshots"

t_section "8b a copy with no libraries beside it says what it needs (install standard)"
LB="$T_TMP/libless"; mkdir -p "$LB"; cp "$B/deploy-restore.sh" "$LB/"
t_eq "8b no library-log.sh beside deploy-restore.sh: exit 1" "exit 1" "$(env -u CLAUDE_CONFIG_DIR sh "$LB/deploy-restore.sh" --live >"$OUT" 2>&1; echo "exit $?")"
t_has "8b ...naming the missing file" "$(out)" "restore: library-log.sh is missing beside $LB"
t_has "8b ...and the checkout copy to run instead, with the same arguments" "$(out)" "/bin/deploy-restore.sh --live"
cp "$B/library-log.sh" "$LB/"
env -u CLAUDE_CONFIG_DIR sh "$LB/deploy-restore.sh" --live >"$OUT" 2>&1
t_has "8b with library-log.sh and no deploy-install-lib.sh it names that one" "$(out)" "restore: deploy-install-lib.sh is missing beside $LB"
cp "$B/deploy-install-lib.sh" "$LB/"
t_eq "8b with both beside it the copy runs" "exit 0" "$(env -u CLAUDE_CONFIG_DIR sh "$LB/deploy-restore.sh" --live >"$OUT" 2>&1; echo "exit $?")"

t_section "8c one log format: no status glyph, a summary on every run (contracts/logging.md)"
for _c in "--live" "--apply --dir $K" "--apply --dir $E" "--dir $F"; do
  # shellcheck disable=SC2086
  rs $_c >/dev/null
  t_hasnt "8c restore $_c prints no ✓ ✗ • !! or REFUSING mark" "$(out)" "REFUSING"
  t_eq "8c restore $_c: no check-mark glyph" 0 "$(grep -cE '✓|✗|•|!!' "$OUT")"
  t_eq "8c restore $_c: every line is a header, a TAG line, the summary or the log" 0 \
    "$(grep -cvE '^(── restore · |  (ok|FAIL|WARN|note|skip|fix): |restore: [0-9]+ ok, [0-9]+ failed, [0-9]+ warnings$|log: )' "$OUT")"
  t_exit "8c restore $_c: every FAIL has its fix" 0 fixfollows
  t_eq "8c restore $_c: exactly one summary line" 1 "$(grep -cE '^restore: [0-9]+ ok, [0-9]+ failed, [0-9]+ warnings$' "$OUT")"
done
t_has "8c the positive control: a refusal does print its FAIL" "$(rs --apply --dir "$E"; out)" "  FAIL: no deploy snapshot"

t_section "8d ~/.local/bin: the snapshot's record puts its links back, and nothing it does not name (harbor#770)"
# Another HOME, so the live fixture section 9 witnesses stays untouched.
H2="$T_TMP/home2"; L2="$H2/.claude"; LB2="$H2/.local/bin"; mkdir -p "$L2/bin" "$LB2"
printf '{"v":1}\n' > "$L2/settings.json"; printf 'tool\n' > "$LB2/t"
ln -s /opt/target-a "$LB2/a"; ln -s /opt/target-b "$LB2/b"; ln -s /opt/target-c "$LB2/c"
S2="$L2/backups/deploy-20260101-000000-1"; mkdir -p "$S2"
{ printf '# local-bin.tsv (harbor#770): <name> TAB <link|copy|file> TAB <link target | git blob of a copy or file>\n'
  printf '# dir: %s\n' "$(cd -P "$LB2" && pwd -P)"
  printf 'a\tlink\t/opt/target-a\nb\tlink\t/opt/target-b\nc\tlink\t/opt/target-c\nt\tfile\t%s\n' "$(git hash-object "$LB2/t")"; } > "$S2/local-bin.tsv"
snap "$L2" deploy-20260101-000000-1 settings.json
ln -sfn /opt/elsewhere "$LB2/a"; rm "$LB2/b"; rm "$LB2/c"; printf 'a file now\n' > "$LB2/c"; ln -s /opt/new "$LB2/new"
r2() { _h="$1"; shift; env -u CLAUDE_CONFIG_DIR HOME="$_h" sh "$B/deploy-restore.sh" "$@" >"$OUT" 2>&1; echo "exit $?"; }
t_eq "8d the dry run" "exit 0" "$(r2 "$H2" --live)"
t_has "8d ...plans a repointed link back" "$(out)" "  note: ~/.local/bin/a: put back -> /opt/target-a (the link there now, -> /opt/elsewhere, is moved aside)"
t_has "8d ...and a removed one" "$(out)" "  note: ~/.local/bin/b: put back -> /opt/target-b (absent now)"
t_has "8d ...never a file where the snapshot had a link" "$(out)" "  WARN: ~/.local/bin/c: the snapshot had a link -> /opt/target-c, and a file is there now; it is not touched"
t_has "8d ...with the fix that moves it and re-runs" "$(out)" "  fix: mv '$LB2/c' '$LB2/c.not-a-link' && sh $B/deploy-restore.sh --apply --from"
t_has "8d ...and names what the record does not hold, left as it is" "$(out)" "not in the record, so left as they are: new"
t_eq "8d ...and moved nothing" "/opt/elsewhere no" "$(readlink "$LB2/a") $(yn [ -L "$LB2/b" ])"
t_eq "8d a --dir restore of the same snapshot" "exit 0" "$(r2 "$T_TMP/home3" --apply --dir "$L2")"
t_hasnt "8d ...leaves ~/.local/bin alone: the record is the live box's" "$(out)" "~/.local/bin/"
t_eq "8d ...b is still absent" no "$(yn [ -L "$LB2/b" ])"
t_eq "8d --apply --live" "exit 0" "$(r2 "$H2" --apply --live)"
t_eq "8d ...puts the repointed link back" /opt/target-a "$(readlink "$LB2/a")"
t_eq "8d ...and the removed one" /opt/target-b "$(readlink "$LB2/b")"
t_eq "8d ...keeps the link it replaced, as a link, beside its log" /opt/elsewhere "$(readlink "$(rundir)/local-bin/a")"
t_eq "8d ...leaves the file where a link was" 'a file now' "$(cat "$LB2/c")"
t_eq "8d ...and the entry it does not name" /opt/new "$(readlink "$LB2/new")"
t_eq "8d ...and the recorded file" tool "$(cat "$LB2/t")"
printf 'd\tlink\t/tmp/planted\n' >> "$S2/local-bin.tsv"; rm "$LB2/b"
t_eq "8d a record changed after deploy recorded it is refused" "exit 1" "$(r2 "$H2" --apply --live)"
t_has "8d ...naming it" "$(out)" "local-bin.tsv is not the ~/.local/bin record deploy made for this snapshot"
t_eq "8d ...and nothing is linked from it" "no no" "$(yn [ -L "$LB2/d" ]) $(yn [ -L "$LB2/b" ])"

t_section "9 the live config dir was not written"
t_eq "9 nothing under the live dir changed" "$LIVE_BEFORE" "$(tree "$L")"
t_done
