#!/usr/bin/env sh
# B10 (harbor#56): bin/prod-guard-ambient.sh, the ambient prod_guard shim, and its installer.
# The shim runs against a STUB python guard, so every branch of "run the guard or stand down"
# is observable without a plugin tree. Byte-identity of the installed guard with the plugin copy
# BLOCKS here where both exist (harbor#696); lint X5 stays as the advisory second signal.
# Read before t_init, which sandboxes HOME and the config dir: the parity subject is the real install.
REAL_CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; REQ_PARITY="${HARBOR_REQUIRE_PROD_GUARD_PARITY:-0}"
. "$(dirname "$0")/../lib/core.sh"; t_init
SHIM="$T_ROOT/bin/prod-guard-ambient.sh"; T="$T_TMP"; DEL='gcloud sql instances delete prod-db'
yn() { if "$@"; then echo yes; else echo no; fi; }
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{print $1}'; }

cat > "$T/stub_guard.py" <<'PY'
import json, sys
p = json.load(sys.stdin)
cmd = p.get("tool_input", {}).get("command", "")
if "gcloud" in cmd:
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse", "permissionDecision": "ask",
        "permissionDecisionReason": "STUB_ASKED"}}))
PY
pay() { # <cwd> <command>
  printf '{"session_id":"s-%s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"}}' \
    "${SID:-fixed}" "$1" "$2"
}
# TMPDIR holds the shim's once-per-session stamp; HOME and the config dir are pinned, never inherited.
run() { pay "$1" "$2" | env -u CLAUDE_CONFIG_DIR TMPDIR="$T" HOME="$T/nohome" sh "$SHIM" "${3:-$T/stub_guard.py}" 2>/dev/null; }
rune() { # <cwd> <command> <guard> <env-args...> — for the cases whose subject is the config dir's name
  _c="$1"; _cmd="$2"; _g="$3"; shift 3
  pay "$_c" "$_cmd" | env "$@" sh "$SHIM" "$_g" 2>/dev/null
}
wire() { mkdir -p "$1/.claude"; cat > "$1/.claude/settings.json" <<J
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"\$CLAUDE_PROJECT_DIR/.agents/hooks/_py.sh \$CLAUDE_PROJECT_DIR/.agents/hooks/prod_guard.py"}]}]}}
J
}
# The AMBIENT config dir wires THIS shim, a different string from a project's wiring (#77).
wire_shim() { mkdir -p "$1/.claude"; cat > "$1/.claude/${2:-settings.json}" <<J
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/bin/sh $1/.claude/bin/prod-guard-ambient.sh $1/.claude/hooks/prod_guard.py"}]}]}}
J
}
amb() { mkdir -p "$1/.claude/hooks" "$1/work"; cp "$T/stub_guard.py" "$1/.claude/hooks/prod_guard.py"; }  # <home>

t_section "the guard runs when nothing else owns the message"
mkdir -p "$T/plain"
t_has "a matching command asks when no project wires prod_guard" "$(run "$T/plain" "$DEL")" STUB_ASKED
t_eq "a non-matching command produces no verdict" "" "$(run "$T/plain" 'echo hello')"

t_section "stand-down where the repo wires its own"
mkdir -p "$T/wired/deep/deeper"; wire "$T/wired"
t_eq "stands down where the repo wires its own prod_guard" "" "$(run "$T/wired" "$DEL")"
t_eq "the stand-down applies from a subdirectory (up-walk)" "" "$(run "$T/wired/deep/deeper" "$DEL")"
pay "$T/wired" "$DEL" | env -u CLAUDE_CONFIG_DIR TMPDIR="$T" HOME="$T/nohome" sh "$SHIM" "$T/stub_guard.py" >/dev/null 2>&1
t_eq "a stand-down exits 0, never a deny" 0 "$?"

t_section "the ambient config dir is NOT a project (2026-07-31)"
AMB="$T/fakehome/.claude"; amb "$T/fakehome"; mkdir -p "$T/fakehome/work/deep"; wire_shim "$T/fakehome"
t_has "does NOT stand down on the config dir that wires this shim" \
  "$(run "$T/fakehome/work/deep" "$DEL" "$AMB/hooks/prod_guard.py")" STUB_ASKED
mkdir -p "$T/fakehome/work/proj"; wire "$T/fakehome/work/proj"
t_eq "a project below the config dir still stands down" "" "$(run "$T/fakehome/work/proj" "$DEL" "$AMB/hooks/prod_guard.py")"

t_section "the exclusion is per-COMMAND, not per-directory (#77)"
FH2="$T/fh2"; AMB2="$FH2/.claude"; amb "$FH2"
cat > "$AMB2/settings.json" <<J
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[
 {"type":"command","command":"/bin/sh $AMB2/bin/prod-guard-ambient.sh $AMB2/hooks/prod_guard.py"},
 {"type":"command","command":"/usr/bin/env python3 $AMB2/hooks/prod_guard.py"}]}]}}
J
t_eq "an INDEPENDENT prod_guard in the ambient dir still owns the message" "" \
  "$(rune "$FH2/work" "$DEL" "$AMB2/hooks/prod_guard.py" -u CLAUDE_CONFIG_DIR TMPDIR="$T" HOME="$FH2")"
wire_shim "$FH2"
t_has "this shim alone in the ambient dir does NOT stand itself down" \
  "$(rune "$FH2/work" "$DEL" "$AMB2/hooks/prod_guard.py" -u CLAUDE_CONFIG_DIR TMPDIR="$T" HOME="$FH2")" STUB_ASKED
# A path component may carry the shim's name: the config dir itself is named for it here.
FH3="$T/prod-guard-ambient-user"; AMB3="$FH3/.claude"; amb "$FH3"
cat > "$AMB3/settings.json" <<J
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[
 {"type":"command","command":"/bin/sh $AMB3/bin/prod-guard-ambient.sh $AMB3/hooks/prod_guard.py"},
 {"type":"command","command":"/usr/bin/env python3 $AMB3/hooks/prod_guard.py"}]}]}}
J
t_eq "an independent guard is recognised under a path named for the shim" "" \
  "$(rune "$FH3/work" "$DEL" "$AMB3/hooks/prod_guard.py" -u CLAUDE_CONFIG_DIR TMPDIR="$T" HOME="$FH3")"
# Quoting is not tokenisation: stripping only `"` reads our own single-quoted command as foreign.
FH4="$T/fh4"; AMB4="$FH4/.claude"; amb "$FH4"
cat > "$AMB4/settings.json" <<J
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[
 {"type":"command","command":"/bin/sh '$AMB4/bin/prod-guard-ambient.sh' '$AMB4/hooks/prod_guard.py'"}]}]}}
J
t_has "a single-quoted shim path is still recognised as our own" \
  "$(rune "$FH4/work" "$DEL" "$AMB4/hooks/prod_guard.py" -u CLAUDE_CONFIG_DIR TMPDIR="$T" HOME="$FH4")" STUB_ASKED
# One command, one record: a hook command may carry shell continuations between its tokens.
FH5="$T/fh5"; AMB5="$FH5/.claude"; amb "$FH5"
python3 - "$AMB5" <<'PY'
import json, sys
amb = sys.argv[1]
cmd = "/bin/sh \\\n  %s/bin/prod-guard-ambient.sh \\\n  %s/hooks/prod_guard.py" % (amb, amb)
json.dump({"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": cmd}]}]}},
          open(amb + "/settings.json", "w"))
PY
t_has "a multiline shim command is still recognised as our own" \
  "$(rune "$FH5/work" "$DEL" "$AMB5/hooks/prod_guard.py" -u CLAUDE_CONFIG_DIR TMPDIR="$T" HOME="$FH5")" STUB_ASKED

t_section "the config dir has THREE names, and each is its own route to the bug"
mkdir -p "$T/ccd/work"; wire_shim "$T/ccd"
t_has "CLAUDE_CONFIG_DIR alone identifies the config dir" \
  "$(rune "$T/ccd/work" "$DEL" "$T/stub_guard.py" TMPDIR="$T" HOME="$T/nohome" CLAUDE_CONFIG_DIR="$T/ccd/.claude")" STUB_ASKED
t_has "an unset HOME still yields a verdict (set -u must not abort the shim)" \
  "$(rune "$T/plain" "$DEL" "$T/stub_guard.py" -u HOME -u CLAUDE_CONFIG_DIR TMPDIR="$T")" STUB_ASKED
mkdir -p "$T/wiredlocal/.claude" "$T/wiredlocal/work"
cat > "$T/wiredlocal/.claude/settings.local.json" <<J
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"\$CLAUDE_PROJECT_DIR/.agents/hooks/prod_guard.py"}]}]}}
J
t_eq "settings.local.json also stands the guard down" "" "$(run "$T/wiredlocal/work" "$DEL")"
LOC="$T/lochome"; amb "$LOC"; wire_shim "$LOC" settings.local.json
t_has "the config dir is skipped for settings.local.json too" \
  "$(rune "$LOC/work" "$DEL" "$LOC/.claude/hooks/prod_guard.py" -u CLAUDE_CONFIG_DIR TMPDIR="$T" HOME="$LOC")" STUB_ASKED
# Only where the volume is case-insensitive: elsewhere the two spellings are two directories.
mkdir -p "$T/CaseProbe"
if [ -d "$T/caseprobe" ]; then
  CH="$T/CaseHome"; amb "$CH"; wire_shim "$CH"
  t_has "a case-skewed config-dir spelling does NOT stand the guard down" "$(rune "$CH/work" "$DEL" \
    "$T/casehome/.claude/hooks/prod_guard.py" -u CLAUDE_CONFIG_DIR TMPDIR="$T" HOME="$T/casehome")" STUB_ASKED
else
  echo "  SKIP: the case-skew case needs a case-insensitive volume; this one is case-sensitive"
fi

t_section "the two ways a stand-down must NOT be reachable"
mkdir -p "$T/forged/.claude"; ln -sf "$T/wired/.claude/settings.json" "$T/forged/.claude/settings.json"
t_has "a SYMLINKED settings.json cannot talk the guard into standing down" "$(run "$T/forged" "$DEL")" STUB_ASKED
mkdir -p "$T/mention/.claude"
printf '{"env":{"NOTE":"prod_guard is deliberately not wired here"}}\n' > "$T/mention/.claude/settings.json"
t_has "'prod_guard' outside a PreToolUse command does not stand it down" "$(run "$T/mention" "$DEL")" STUB_ASKED

t_section "dependency failure announces itself, once per session"
SID="broken-once"
t_has "a missing guard file announces itself as an ask" \
  "$(run "$T/plain" 'echo hello' "$T/nonexistent.py")" "INSTALLED BUT NOT FUNCTIONING"
t_eq "the same session is not prompted a second time" "" "$(run "$T/plain" 'echo hello' "$T/nonexistent.py")"
SID="broken-twice"
t_has "a NEW session is announced again" \
  "$(run "$T/plain" 'echo hello' "$T/nonexistent.py")" "INSTALLED BUT NOT FUNCTIONING"
unset SID

t_section "argument contract"
t_exit "no argument" 2 sh -c 'printf "{}" | sh "$1"' _ "$SHIM"
t_exit "two arguments" 2 sh -c 'printf "{}" | sh "$1" a b' _ "$SHIM"

t_section "the installer's SOURCE SELECTION, which is a security decision"
# The marketplace mirror ships the pre-PI-903 guard a symlink defeats; both sources are built here.
INST="$T_ROOT/bin/prod-guard-install.sh"
mkgd() { # <file> <with-refusal:0|1> <marker>
  mkdir -p "$(dirname "$1")"
  { printf 'import json,sys\n# %s\n' "$3"
    [ "$2" = 1 ] && printf 'def _f(p):\n    if p.is_symlink(): return None\n'
    printf 'print("")\n'; } > "$1"
}
IT="$T/inst"; mkdir -p "$IT/cfg" "$IT/pi/templates/base/dot_agents/hooks"
printf '{"env":{}}\n' > "$IT/cfg/settings.json"
mkgd "$IT/cfg/plugins/marketplaces/project-init/plugins/project-init-workflow/hooks/prod_guard.py" 0 MIRROR_COPY
mkgd "$IT/pi/templates/base/dot_agents/hooks/prod_guard.py" 1 SOURCE_COPY
out="$(HOME="$T/nohome" CLAUDE_CONFIG_DIR="$IT/cfg" PROJECT_INIT_SRC="$IT/pi" sh "$INST" --dir "$IT/cfg" 2>&1)"
t_has "the installer prefers the source repo over the marketplace mirror" "$out" "upstream source repo"
t_has "the installer names the mirror as stale when it differs from the source" "$out" "mirror differs from the source repo"
# harbor#925: a CURRENT mirror over a STALE install read green; the installed copy is the one loaded.
cp "$IT/pi/templates/base/dot_agents/hooks/prod_guard.py" "$IT/cfg/plugins/marketplaces/project-init/plugins/project-init-workflow/hooks/prod_guard.py"
PC="$IT/cfg/plugins/cache/project-init/project-init-workflow"
mkgd "$PC/0.9.20/hooks/prod_guard.py" 1 OLD_INSTALL
mkdir -p "$PC/0.9.33/hooks"; cp "$IT/pi/templates/base/dot_agents/hooks/prod_guard.py" "$PC/0.9.33/hooks/prod_guard.py"
printf '{"version":2,"plugins":{"project-init-workflow@project-init":[{"scope":"project","projectPath":"/p/a","installPath":"%s/0.9.20","version":"0.9.20"},{"scope":"project","projectPath":"/p/b","installPath":"%s/0.9.20","version":"0.9.20"},{"scope":"user","installPath":"%s/0.9.33","version":"0.9.33"}]}}\n' "$PC" "$PC" "$PC" > "$IT/cfg/plugins/installed_plugins.json"
out="$(HOME="$T/nohome" CLAUDE_CONFIG_DIR="$IT/cfg" PROJECT_INIT_SRC="$IT/pi" sh "$INST" --dir "$IT/cfg" 2>&1)"
t_hasnt "a current mirror is not called stale" "$out" "mirror differs from the source repo"
t_has "a stale INSTALL under a current mirror WARNS, naming its projects" "$out" \
  "WARN: the INSTALLED project-init-workflow 0.9.20 differs from the source repo, and it is the copy Claude Code loads (project:/p/a, project:/p/b)"
t_has "and names the update" "$out" "claude plugin update project-init-workflow@project-init --scope"
t_has "positive control: the current install is named as matching" "$out" "installed project-init-workflow 0.9.33 matches the source repo (user:-)"
rm -f "$PC/0.9.33/hooks/prod_guard.py"
out="$(HOME="$T/nohome" CLAUDE_CONFIG_DIR="$IT/cfg" PROJECT_INIT_SRC="$IT/pi" sh "$INST" --dir "$IT/cfg" 2>&1)"
t_has "an install with no guard at all warns too" "$out" "WARN: the INSTALLED project-init-workflow 0.9.33 has no hooks/prod_guard.py at $PC/0.9.33"
printf 'not json\n' > "$IT/cfg/plugins/installed_plugins.json"
out="$(HOME="$T/nohome" CLAUDE_CONFIG_DIR="$IT/cfg" PROJECT_INIT_SRC="$IT/pi" sh "$INST" --dir "$IT/cfg" 2>&1)"
t_has "an unreadable install record WARNS that it compared nothing" "$out" "WARN: could not read $(cd "$IT/cfg" && pwd -P)/plugins/installed_plugins.json, so the installed plugin was not compared"
# review #932: an empty field must not shift the columns, and an entry with no installPath names nothing
mkdir -p "$PC/v	tab/hooks"; cp "$IT/pi/templates/base/dot_agents/hooks/prod_guard.py" "$PC/v	tab/hooks/prod_guard.py"
printf '{"plugins":{"project-init-workflow@project-init":[{"scope":"user","version":""},{"scope":"","installPath":"%s/0.9.20","version":""},{"scope":"user","installPath":"%s/v\\ttab","version":"9"}]}}\n' "$PC" "$PC" > "$IT/cfg/plugins/installed_plugins.json"
out="$(HOME="$T/nohome" CLAUDE_CONFIG_DIR="$IT/cfg" PROJECT_INIT_SRC="$IT/pi" sh "$INST" --dir "$IT/cfg" 2>&1)"
t_has "empty version and scope stay in their columns" "$out" "WARN: the INSTALLED project-init-workflow ? differs from the source repo, and it is the copy Claude Code loads (?:-)"
t_has "a tab inside an install path is read as the path, not escaped" "$out" "installed project-init-workflow 9 matches the source repo (user:-)"
t_eq "an entry with no installPath compares nothing: one WARN for the one stale path" 1 "$(printf '%s\n' "$out" | grep -c 'WARN: the INSTALLED')"
rm -rf "$IT/cfg/plugins/cache" "$IT/cfg/plugins/installed_plugins.json"
mkgd "$IT/cfg/plugins/marketplaces/project-init/plugins/project-init-workflow/hooks/prod_guard.py" 0 MIRROR_COPY
out="$(HOME="$T/nohome" CLAUDE_CONFIG_DIR="$IT/cfg" PROJECT_INIT_SRC=/nonexistent sh "$INST" --dir "$IT/cfg" 2>&1)"
t_eq "the installer refuses a source with no PI-903 refusal" 1 "$?"
t_has "that refusal is the PI-903 one" "$out" 'has no symlink refusal (PI-903)'
out="$(env -u CLAUDE_CONFIG_DIR HOME="$T/nohome" PROJECT_INIT_SRC=/nonexistent sh "$INST" --dir "$IT/cfg" 2>&1)"
t_has "the mirror is the TARGET's own, never one CLAUDE_CONFIG_DIR names (harbor#765)" "$out" \
  "  note: source: $(cd "$IT/cfg" && pwd -P)/plugins/marketplaces/project-init/plugins/project-init-workflow/hooks/prod_guard.py (marketplace mirror (source repo absent))"
# The re-pin, asserted by the pin's CONTENT: a printed "re-pinned" over a stale pin is the bug.
RP="$T/repin"; mkdir -p "$RP"
printf '{"env":{}}\n' > "$RP/settings.json"; printf 'stale-teeth-value\n' > "$RP/.helm-floor-teeth"
env -u CLAUDE_CONFIG_DIR HOME="$T/nohome" PROJECT_INIT_SRC="$IT/pi" sh "$INST" --dir "$RP" --apply >/dev/null 2>&1
t_eq "applying re-pins the teeth to the settings it wrote" \
  "$(jq -S '{deny:.permissions.deny, locks:{bypass:.permissions.disableBypassPermissionsMode, auto:.permissions.disableAutoMode}}' "$RP/settings.json" | sha)" \
  "$(cat "$RP/.helm-floor-teeth" 2>/dev/null || echo MISSING)"

t_section "the installer on the install standard: interface, one backup scheme, the dry-run exit rule"
# A source that carries the PI-903 refusal AND asks, so the installer's own verify step can pass.
PGP="$T/pgpi/templates/base/dot_agents/hooks"; mkdir -p "$PGP"
{ cat "$T/stub_guard.py"; printf '# carries the p.is_symlink() refusal\n'; } > "$PGP/prod_guard.py"
pgi() { env -u CLAUDE_CONFIG_DIR HOME="$T/pgh" PROJECT_INIT_SRC="$T/pgpi" sh "$INST" "$@" >"$T/pg.out" 2>"$T/pg.err"; echo $?; }
PG="$T/pgi"; mkdir -p "$PG" "$T/pgh/.claude"; printf '{"env":{}}\n' > "$PG/settings.json"
printf '{"env":{}}\n' > "$T/pgh/.claude/settings.json"
t_eq "a positional target is a usage error" 2 "$(pgi "$PG")"
t_eq "an unknown flag is a usage error, not a refusal" 2 "$(pgi --dir "$PG" --bogus)"
t_eq "--dir onto the live dir is refused" 1 "$(pgi --apply --dir "$T/pgh/.claude")"
t_eq "...and the live settings.json is untouched" '{"env":{}}' "$(cat "$T/pgh/.claude/settings.json")"
t_eq "CLAUDE_CONFIG_DIR naming another dir is a usage error" 2 \
  "$(env HOME="$T/pgh" CLAUDE_CONFIG_DIR="$IT/cfg" PROJECT_INIT_SRC="$T/pgpi" sh "$INST" --dir "$PG" >/dev/null 2>&1; echo $?)"
t_eq "a clean dry run exits 0" 0 "$(pgi --dir "$PG")"
t_has "...naming its source for deploy to check" "$(cat "$T/pg.out")" "  note: source: $PGP/prod_guard.py (upstream source repo)"
t_has "...and the command that applies it" "$(cat "$T/pg.out")" "  note: next: sh $INST --apply --dir '$(cd "$PG" && pwd -P)'"
t_eq "...and writes nothing" "settings.json" "$(ls -A "$PG")"
t_eq "a missing source fails the dry run" 1 "$(env -u CLAUDE_CONFIG_DIR HOME="$T/pgh" PROJECT_INIT_SRC=/nonexistent sh "$INST" --dir "$PG" >"$T/pg.out" 2>&1; echo $?)"
t_has "...as the FAIL deploy reads, then its fix" "$(grep -A1 '  FAIL: no prod_guard.py at' "$T/pg.out" | tail -1)" "  fix: none automatic"
INO0="$(ls -i "$PG/settings.json" | awk '{print $1}')"
t_eq "an apply succeeds" 0 "$(pgi --apply --dir "$PG")"
t_eq "...and leaves no settings.json.bak.* in the config dir (harbor#765)" "" "$(ls -A "$PG" | grep 'settings.json.bak' || true)"
PGB="$(tail -1 "$T/pg.out" | sed -n 's/^log: //p')"
t_has "...its backup is beside its log, in backups/prod-guard-install/<TS>/" "$PGB" "$(cd "$PG" && pwd -P)/backups/prod-guard-install/"
t_eq "...holding the pre-run settings.json" '{"env":{}}' "$(cat "$(dirname "$PGB")/settings.json" 2>/dev/null)"
t_has "...and the log holds the run" "$(cat "$PGB" 2>/dev/null)" "  ok: verified: a destructive gcloud command now returns ask"
t_eq "...and settings.json was replaced, not truncated in place" yes "$([ "$(ls -i "$PG/settings.json" | awk '{print $1}')" != "$INO0" ] && echo yes || echo no)"
t_eq "...wiring the shim" 1 "$(jq '[.hooks.PreToolUse[]?.hooks[]?.command | select(contains("prod-guard-ambient.sh"))] | length' "$PG/settings.json")"
t_eq "a second apply is idempotent" '0 1' "$(pgi --apply --dir "$PG") $(jq '[.hooks.PreToolUse[]?.hooks[]?.command | select(contains("prod-guard-ambient.sh"))] | length' "$PG/settings.json")"
t_has "...and says it was already wired" "$(cat "$T/pg.out")" "already wired"
# harbor#1277: prod_guard is a veto, and a hook that times out without onFailure lets the call through.
pgo() { _o="$1"; shift; env -u CLAUDE_CONFIG_DIR FLOOR_ONFAILURE="$_o" HOME="$T/pgh" PROJECT_INIT_SRC="$T/pgpi" sh "$INST" "$@" >"$T/pg.out" 2>"$T/pg.err"; echo $?; }
_pgof() { jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.command | contains("prod-guard-ambient.sh")) | (.onFailure // "none")] | join(",")' "$1/settings.json"; }
PO="$T/pgof"; mkdir -p "$PO"; printf '{"env":{}}\n' > "$PO/settings.json"
pgo 0 --apply --dir "$PO" >/dev/null
t_eq "OF-1 a client too old for the key gets none" none "$(_pgof "$PO")"
t_eq "OF-2 a dry run names the missing key on a hook already wired" 0 "$(pgo 1 --dir "$PO")"
t_has "...as the change it would make" "$(cat "$T/pg.out")" "would set onFailure block on it"
pgo 1 --apply --dir "$PO" >/dev/null
t_eq "OF-3 a re-install sets onFailure block on the hook already wired" block "$(_pgof "$PO")"
PO2="$T/pgof2"; mkdir -p "$PO2"; printf '{"env":{}}\n' > "$PO2/settings.json"
pgo 1 --apply --dir "$PO2" >/dev/null
t_eq "OF-4 a first install wires it with onFailure block" block "$(_pgof "$PO2")"
pgo 1 --apply --dir "$PO2" >/dev/null
t_eq "OF-5 ...once, and a second run says it is already wired" "block 1" "$(_pgof "$PO2") $(grep -c 'already wired' "$T/pg.out")"
# The install manifest (install standard §3): two rows, each carrying its own source's commit.
git -C "$T/pgpi" init -q && git -C "$T/pgpi" add -A && git -C "$T/pgpi" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm pi
t_eq "an apply from a project-init checkout" 0 "$(pgi --apply --dir "$PG")"
t_eq "...records prod_guard.py with project-init's commit" \
  "$(git hash-object "$PG/hooks/prod_guard.py") 100644 hooks/prod_guard.py prod-guard-install $(git -C "$T/pgpi" rev-parse HEAD)" \
  "$(grep ' hooks/prod_guard.py ' "$PG/.harbor-manifest" 2>/dev/null)"
t_eq "...and the shim with this checkout's" \
  "$(git hash-object "$PG/bin/prod-guard-ambient.sh") 100755 bin/prod-guard-ambient.sh prod-guard-install $(git -C "$T_ROOT" rev-parse HEAD)" \
  "$(grep ' bin/prod-guard-ambient.sh ' "$PG/.harbor-manifest" 2>/dev/null)"

t_section "the ledger (harbor#320)"
# floor_log_decision resolves its sink from $0, so the shim runs from a copy with a sink.
# 0500 is the contract: the writer refuses a WRITABLE host dir, and L-0 catches a silent sink.
LT="$T/ledger"; mkdir -p "$LT/bin" "$LT/MEMORY/OBSERVABILITY/probehost"
cp "$SHIM" "$T_ROOT/bin/guard-lib.sh" "$LT/bin/"
printf 'probehost\n' > "$LT/.helm-obs-host"
LSINK="$LT/MEMORY/OBSERVABILITY/probehost/guard-decisions.jsonl"
: > "$LSINK"; chmod 0500 "$LT/MEMORY/OBSERVABILITY/probehost"
lrun() { # <cwd> <command> — shim run from the ledger copy, sink reset first
  : > "$LSINK"
  pay "$1" "$2" | env -u CLAUDE_CONFIG_DIR TMPDIR="$T" HOME="$T/nohome" sh "$LT/bin/prod-guard-ambient.sh" "$T/stub_guard.py" >/dev/null 2>&1
}
mkdir -p "$T/ledgerplain"
lrun "$T/ledgerplain" "$DEL"
t_has "L-0 the fixture ledger receives records (control)" "$(cat "$LSINK")" '"v":1'
t_has "L-1 a delegated ASK reaches the ledger" "$(cat "$LSINK")" '"d":"ask"'
t_has "L-2 the record is filed under g=prod" "$(cat "$LSINK")" '"g":"prod"'
t_eq "L-2b nothing from this shim lands in the catch-all" 0 "$(grep -c '"g":"other"' "$LSINK")"
lrun "$T/ledgerplain" 'echo hello'
t_has "L-3 a delegated ALLOW is logged as allow" "$(cat "$LSINK")" '"d":"allow"'
mkdir -p "$T/ledgerproj"; wire "$T/ledgerproj"
lrun "$T/ledgerproj" "$DEL"
t_has "L-4 a stand-down is recorded as armed, not allow" "$(cat "$LSINK")" '"d":"armed"'
# L-5 (harbor#309): the shim hands its payload to the writer, so a prod decision carries the session key.
printf '0123456789abcdef0123456789abcdef\n' > "$LT/.helm-obs-salt"
lrun "$T/ledgerplain" "$DEL"
_l5="$(grep '"d":"ask"' "$LSINK" | tail -1 | jq -r '.sk // "absent"')"
t_eq "L-5 a prod ask carries a 16-hex session key" yes \
  "$(case "$_l5" in ([0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef]) echo yes ;; (*) echo "no: $_l5" ;; esac)"
rm -f "$LT/.helm-obs-salt"

t_section "the delegate path stays byte-transparent"
# $(...) strips trailing newlines, so both output shapes are compared byte for byte.
cat > "$T/nl_guard.py" <<'PY2'
import json, sys
sys.stdout.write(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
    "permissionDecision": "ask", "permissionDecisionReason": "NO_TRAILING_NEWLINE"}}))
PY2
cat > "$T/nl2_guard.py" <<'PY2'
import json, sys
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
    "permissionDecision": "ask", "permissionDecisionReason": "WITH_TRAILING_NEWLINE"}}))
PY2
for _g in nl nl2; do
  pay "$T/ledgerplain" 'gcloud x' | python3 "$T/${_g}_guard.py" > "$T/${_g}.direct" 2>/dev/null
  pay "$T/ledgerplain" 'gcloud x' | env -u CLAUDE_CONFIG_DIR TMPDIR="$T" HOME="$T/nohome" \
    sh "$LT/bin/prod-guard-ambient.sh" "$T/${_g}_guard.py" > "$T/${_g}.shim" 2>/dev/null
  t_eq "L-5 the shim reproduces the guard's stdout byte for byte ($_g)" yes "$(yn cmp -s "$T/${_g}.direct" "$T/${_g}.shim")"
done
# L-6: a non-zero PreToolUse hook is a hard block, so a capture must not launder a crash into 0.
printf 'import sys\nsys.exit(3)\n' > "$T/crash_guard.py"
pay "$T/ledgerplain" 'gcloud x' | env -u CLAUDE_CONFIG_DIR TMPDIR="$T" HOME="$T/nohome" \
  sh "$LT/bin/prod-guard-ambient.sh" "$T/crash_guard.py" >/dev/null 2>&1
t_eq "L-6 a crashing guard's exit code is re-raised" 3 "$?"
# L-7: the installer copies the shim and not guard-lib, so a box without the floor is real.
NL="$T/nolib"; mkdir -p "$NL/bin"; cp "$SHIM" "$NL/bin/"
t_has "L-7 the shim still returns its verdict with guard-lib absent" "$(pay "$T/ledgerplain" "$DEL" \
  | env -u CLAUDE_CONFIG_DIR TMPDIR="$T" HOME="$T/nohome" sh "$NL/bin/prod-guard-ambient.sh" "$T/stub_guard.py" 2>/dev/null)" STUB_ASKED

t_section "the installed guard matches the plugin copy (harbor#696)"
# One assertion on both arms (HOST-COUNT-STABLE): a host with no installed copy, e.g. a hosted
# runner, takes a loud SKIP instead of failing over an environment fact.
PG_PLUG="$REAL_CFG/plugins/marketplaces/project-init/plugins/project-init-workflow/hooks/prod_guard.py"
PG_INST="$REAL_CFG/hooks/prod_guard.py"
if [ -f "$PG_PLUG" ] && [ -f "$PG_INST" ]; then
  t_eq "the installed prod_guard.py is byte-identical to the plugin copy" yes "$(yn cmp -s "$PG_PLUG" "$PG_INST")"
else
  t_eq "installed or plugin prod_guard.py absent on this host, so HARBOR_REQUIRE_PROD_GUARD_PARITY must be off" 0 "$REQ_PARITY"
  echo "prod-guard-test: SKIPPED the installed-vs-plugin parity check (needs $PG_INST and $PG_PLUG)"
fi

t_done
