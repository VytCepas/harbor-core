#!/usr/bin/env sh
# tests.test.sh (harbor#1278; control member.tests): bin/member-tests.sh, the Stop check that sends a turn back once when a registered project's
# code changed and no test did. Scratch repos, the hook run as a laptop runs it (env -i). Each property is seen red on a planted defect (section 5).
. "$(dirname "$0")/../../lib/core.sh"; t_init
H="$T_ROOT/bin/member-tests.sh"
MB="$T_TMP/bin"; mkdir -p "$MB"
cp "$H" "$MB/member-tests.sh"
for f in library-log.sh library-git-safe.sh scope-roots.sh; do cp "$T_ROOT/bin/$f" "$MB/"; done
cp "$T_ROOT/contracts/roots.tsv" "$T_ROOT/contracts/agent-architectures.tsv" "$MB/"
export GIT_AUTHOR_NAME=m GIT_AUTHOR_EMAIL=m@example.invalid GIT_COMMITTER_NAME=m GIT_COMMITTER_EMAIL=m@example.invalid
PORT="$T_TMP/port"; HM="$T_TMP/home"; mkdir -p "$PORT/harbor-private" "$HM"
registry() { printf '%s\tproj\tworkload\t-\tstream-aligned\tx-as-a-service\t-\t-\tyes\t-\ta project\n' "${1:-proj}" > "$PORT/harbor-private/repos.tsv"; }
fresh() { rm -rf "$PORT/proj" "$HM/.local"; mkdir -p "$PORT/proj"; git -C "$PORT/proj" init -q; registry proj
  printf 'x\n' > "$PORT/proj/app.py"; printf 'y\n' > "$PORT/proj/README.md"; git -C "$PORT/proj" add -A; git -C "$PORT/proj" commit -qm base; }
hook() { # <hook file> [snap] -> stdout; JSON on stdin from $IN
  env -i PATH="${HPATH:-/usr/bin:/bin}" HOME="$HM" PORT_ROOT="$PORT" HARBOR_SCOPE_PRIVATE="$PORT/harbor-private" TMPDIR="$T_TMP" sh "$1" ${2:-}; }
snap() { printf '{"session_id":"s1"}' | hook "$MB/member-tests.sh" snap; }
stop() { printf '{"session_id":"s1","stop_hook_active":%s}' "${1:-false}" | hook "${2:-$MB/member-tests.sh}"; }
reason() { printf '%s' "$1" | jq -r '.reason // ""'; }

t_section "1 - code without a test is sent back, once"
fresh; snap
sh -c "printf 'def f():\n    return 2\n' >> '$PORT/proj/app.py'"   # a write by Bash, as a subagent's would be: no transcript is read
O="$(stop)"
t_eq "a code change by a command, no test: blocked" block "$(printf '%s' "$O" | jq -r .decision)"
t_has "the reason carries the control id" "$(reason "$O")" "member.tests:"
t_has "...names the project and the file" "$(reason "$O")" "proj (app.py)"
t_has "...names the small-change architecture" "$(reason "$O")" "test-writing-trivial"
t_has "...and the project's own runner" "$(reason "$O")" "sh tests/run.sh"
t_has "...and the law section" "$(reason "$O")" "§8"
t_eq "stop_hook_active stands it down: never twice" "" "$(stop true)"
t_eq "...and it printed nothing and exited 0" 0 "$(printf '{"session_id":"s1","stop_hook_active":true}' | hook "$MB/member-tests.sh" > /dev/null; echo $?)"
i=0; while [ "$i" -lt 40 ]; do echo "line $i" >> "$PORT/proj/app.py"; i=$((i + 1)); done
t_has "forty more lines names the full architecture" "$(reason "$(stop)")" "test-writing: roles"

t_section "2 - a test changes with it, or the change is not code: not sent back"
fresh; snap; echo 'more' >> "$PORT/proj/app.py"; mkdir -p "$PORT/proj/tests"; echo 't' > "$PORT/proj/tests/test_app.py"
t_eq "code and a test" "" "$(stop)"
fresh; snap; echo 'more' >> "$PORT/proj/README.md"; echo '{}' > "$PORT/proj/settings.json"
t_eq "docs and settings only" "" "$(stop)"
fresh; snap; echo 'more' >> "$PORT/proj/app.py"; git -C "$PORT/proj" add -A; git -C "$PORT/proj" commit -qm turn
t_has "code committed in the turn is still seen" "$(reason "$(stop)")" "member.tests:"
fresh; echo dirty >> "$PORT/proj/app.py"; snap; echo 'more' >> "$PORT/proj/README.md"
t_eq "code dirty before the prompt and untouched since is not this turn's" "" "$(stop)"

t_section "3 - it stays out of the way and fails open"
fresh; snap; echo 'more' >> "$PORT/proj/app.py"; registry other
t_eq "a project that is not registered" "" "$(stop)"
fresh; rm -f "$PORT/harbor-private/repos.tsv"; snap; echo 'more' >> "$PORT/proj/app.py"
t_eq "no registry at all" "" "$(stop)"
fresh; echo 'more' >> "$PORT/proj/app.py"
t_eq "no snapshot for the session (registered mid-session)" "" "$(stop)"
fresh; snap; echo 'more' >> "$PORT/proj/app.py"; printf 'not json' | hook "$MB/member-tests.sh" > "$T_TMP/o"; t_eq "garbage input" "" "$(cat "$T_TMP/o")"
t_eq "an empty input exits 0" 0 "$(printf '' | hook "$MB/member-tests.sh" > /dev/null; echo $?)"
t_eq "a session id with a slash is refused quietly" "" "$(printf '{"session_id":"../x"}' | hook "$MB/member-tests.sh")"
fresh; snap; echo 'more' >> "$PORT/proj/app.py"; rm -rf "$PORT/proj/.git"
t_eq "a project that stopped being a git checkout" "" "$(stop)"
fresh; mkdir -p "$PORT/proj/bin" "$PORT/proj/contracts"; : > "$PORT/proj/bin/harbor"; : > "$PORT/proj/contracts/roots.tsv"; snap; echo 'more' >> "$PORT/proj/app.py"
t_eq "the floor's own checkout is never a member project" "" "$(stop)"

t_section "4 - bounded in time"
mkdir -p "$T_TMP/slow"; printf '#!/bin/sh\nexec sleep 40\n' > "$T_TMP/slow/git"; chmod +x "$T_TMP/slow/git"
fresh; snap; echo 'more' >> "$PORT/proj/app.py"
S0="$(date +%s)"; O="$(HPATH="$T_TMP/slow:/usr/bin:/bin"; stop)"; S1="$(date +%s)"
t_eq "a git that hangs: nothing printed" "" "$O"
t_eq "...and the Stop hook gave up inside 12 seconds" ok "$([ $((S1 - S0)) -le 12 ] && echo ok || echo "$((S1 - S0)) s")"
S0="$(date +%s)"; ( HPATH="$T_TMP/slow:/usr/bin:/bin"; snap ); S1="$(date +%s)"
t_eq "the prompt snapshot gave up inside 9 seconds" ok "$([ $((S1 - S0)) -le 9 ] && echo ok || echo "$((S1 - S0)) s")"

t_section "5 - the corpus (tests/member/tests/corpus, report.md) and the proof that the floors can fail"
# Floors sit a few points under the measured numbers, so a worse hook goes red and noise does not. Measured: report.md.
set -- $(sh "$T_ROOT/tests/member/tests/measure.sh" --pct)
floor() { t_eq "$1 stays at $3 percent or better" ok "$([ "${2:-0}" -ge "$3" ] && echo ok || echo "${2:-none} percent")"; }
floor "send-back precision" "${1:-}" 95
floor "send-back recall" "${2:-}" 95
floor "architecture accuracy" "${3:-}" 90
# Red: a hook that counts a test path as code, and one that has no test class at all, must drop under the floors.
sed 's/tests\/\*|test\/\*|spec\/\*|specs\/\*|__tests__\/\*|\*\/tests\/\*|\*\/test\/\*|\*\/__tests__\/\*|\*\/spec\/\*|\*\.test\.\*|\*\.spec\.\*|\*_test\.\*|\*_spec\.\*|test_\*|\*\/test_\*|conftest\.py|\*\/conftest\.py)/zz_never)/' "$H" > "$T_TMP/m1.sh"
t_eq "mutant 1 (no test class) differs from the hook" 1 "$(cmp -s "$H" "$T_TMP/m1.sh" && echo 0 || echo 1)"
set -- $(sh "$T_ROOT/tests/member/tests/measure.sh" --hook "$T_TMP/m1.sh" --set holdout --pct)
t_eq "mutant 1: precision falls under the floor (red)" low "$([ "${1:-0}" -lt 95 ] && echo low || echo "${1:-0} percent")"
sed 's/^  \[ "\$(printf .%s. "\$IN" | "\$JQ" -r .\.stop_hook_active.*$/  :/' "$H" > "$T_TMP/m2.sh"
t_eq "mutant 2 (no stop_hook_active guard) differs from the hook" 1 "$(cmp -s "$H" "$T_TMP/m2.sh" && echo 0 || echo 1)"
fresh; cp "$T_TMP/m2.sh" "$MB/m2.sh"; snap; echo 'more' >> "$PORT/proj/app.py"
t_eq "mutant 2: with the guard gone it blocks again (red)" block "$(stop true "$MB/m2.sh" | jq -r .decision)"
sed 's/|\*\.py|/|/' "$H" > "$T_TMP/m3.sh"
t_eq "mutant 3 (Python is not code) differs from the hook" 1 "$(cmp -s "$H" "$T_TMP/m3.sh" && echo 0 || echo 1)"
set -- $(sh "$T_ROOT/tests/member/tests/measure.sh" --hook "$T_TMP/m3.sh" --set holdout --pct)
t_eq "mutant 3 (Python is not code): recall falls under the floor (red)" low "$([ "${2:-0}" -lt 95 ] && echo low || echo "${2:-0} percent")"

t_section "7 - nothing the agent writes into the repo makes git run a program (library-git-safe.sh)"
# The hook runs outside the sandbox on a repo the agent can write. Each case plants a program in the repo's own config or attributes, and a marker says
# whether it ran. Three checks per case: the probe (plain git, the call a careless hook would make) fires it, so the attack is live; the real hook does
# not; and, where the hook's own calls reach it, the hook with the helper swapped for plain git does (red).
ATK="$T_TMP/atk"; MK="$ATK/mk"; mkdir -p "$MK" "$ATK/hooks"
printf '#!/bin/sh\ntouch "%s/$1"\nshift\nexec "$@"\n' "$MK" > "$ATK/mark.sh"; chmod +x "$ATK/mark.sh"
printf '#!/bin/sh\ntouch "%s/hooksPath"\n' "$MK" > "$ATK/hooks/pre-commit"; cp "$ATK/hooks/pre-commit" "$ATK/hooks/post-index-change"; chmod +x "$ATK/hooks/"*
MBB="$T_TMP/binbypass"; mkdir -p "$MBB"; cp "$MB"/* "$MBB/"
printf 'gs_open() { GS_DIR="$1/.git"; GS_TREE="$1"; return 0; }\ngs_git() { git -C "$GS_TREE" "$@"; }\n' > "$MBB/library-git-safe.sh"
P="$PORT/proj"
cfg() { git -C "$P" config --local "$@"; }
attr() { printf '*.py filter=x diff=x\n' > "$P/.gitattributes"; }
plant_clean() { attr; cfg filter.x.clean "$ATK/mark.sh clean cat"; }
plant_process() { attr; cfg filter.x.process "$ATK/mark.sh process false"; }
plant_smudge() { attr; cfg filter.x.smudge "$ATK/mark.sh smudge cat"; }
plant_textconv() { attr; cfg diff.x.textconv "$ATK/mark.sh textconv cat"; }
plant_external() { cfg diff.external "$ATK/mark.sh external true"; }
plant_include() { attr; printf '[filter "x"]\n\tclean = %s/mark.sh include cat\n' "$ATK" > "$ATK/inc.cfg"; cfg include.path "$ATK/inc.cfg"; }
plant_fsmonitor() { cfg core.fsmonitor "$ATK/mark.sh fsmonitor true"; }
plant_hooksPath() { cfg core.hooksPath "$ATK/hooks"; }
plant_pager() { cfg core.pager "$ATK/mark.sh pager cat"; }
probe_clean() { git -C "$P" hash-object app.py; }
probe_process() { git -C "$P" hash-object app.py; }
probe_smudge() { git -C "$P" checkout -- app.py; }
probe_textconv() { git -C "$P" diff; }
probe_external() { git -C "$P" diff; }
probe_include() { git -C "$P" hash-object app.py; }
probe_fsmonitor() { git -C "$P" status; }
probe_hooksPath() { git -C "$P" commit -qam probe; }
printf 'import pty, sys\npty.spawn(sys.argv[1:])\n' > "$ATK/spawn_tty.py"   # git pages only on a terminal
probe_pager() { python3 "$ATK/spawn_tty.py" git -C "$P" diff; }
turn() { # <hook file> -> a snapshot, a same-size edit of app.py, a Stop
  printf '{"session_id":"s1"}' | hook "$1" snap; printf 'z\n' > "$P/app.py"; printf '{"session_id":"s1","stop_hook_active":false}' | hook "$1" > /dev/null; }
for A in clean process smudge textconv external include fsmonitor hooksPath pager; do
  fresh; "plant_$A"; printf 'z\n' > "$P/app.py"; rm -f "$MK/$A"; "probe_$A" > /dev/null 2>&1 < /dev/null || :
  t_eq "$A: the probe (plain git) fires the planted program, so the attack is live" yes "$([ -e "$MK/$A" ] && echo yes || echo no)"
  fresh; "plant_$A"; rm -f "$MK/$A"; turn "$MB/member-tests.sh"
  t_eq "$A: the hook (snapshot, a same-size edit, Stop) runs nothing" no "$([ -e "$MK/$A" ] && echo yes || echo no)"
done
for A in clean process include fsmonitor; do
  fresh; "plant_$A"; rm -f "$MK/$A"; turn "$MBB/member-tests.sh"
  t_eq "$A: red, the hook with the helper swapped for plain git runs the program" yes "$([ -e "$MK/$A" ] && echo yes || echo no)"
done
t_eq "the helper opens a repo whose .git is a file as a refusal, not a crash" 1 "$(sh -c '. "$1"; mkdir -p "$2/x"; printf "gitdir: /nowhere\n" > "$2/x/.git"; gs_open "$2/x" "$2/w" && echo 0 || echo 1' sh "$MB/library-git-safe.sh" "$T_TMP")"

t_section "8 - a same-size edit in the second the index was written is still seen (cp -p keeps the index's mtime)"
# Deterministic, no race: the file and the index both carry one old mtime and the entry's stat matches the edited file, so only the racy-entry rule
# (file not older than the index) makes git look at the bytes. A copy with a fresh mtime hides the edit.
MBC="$T_TMP/bincp"; mkdir -p "$MBC"; cp "$MB"/* "$MBC/"; sed 's/cp -p "\$_gr\/.git\/index"/cp "$_gr\/.git\/index"/' "$MB/library-git-safe.sh" > "$MBC/library-git-safe.sh"
t_eq "the red variant (cp without -p) differs from the library" 1 "$(cmp -s "$MB/library-git-safe.sh" "$MBC/library-git-safe.sh" && echo 0 || echo 1)"
racy() { # <hook file> -> the Stop output
  fresh; T0=202001010000
  touch -t $T0 "$P/app.py"; git -C "$P" update-index --refresh > /dev/null 2>&1; touch -t $T0 "$P/.git/index"
  printf '{"session_id":"s1"}' | hook "$1" snap
  printf 'z\n' > "$P/app.py"; touch -t $T0 "$P/app.py"
  printf '{"session_id":"s1","stop_hook_active":false}' | hook "$1"; }
t_eq "a same-size edit with the index's own mtime: blocked" block "$(racy "$MB/member-tests.sh" | jq -r .decision)"
t_eq "red: with the index copied without -p the edit is missed" "" "$(racy "$MBC/member-tests.sh")"

t_section "6 - the law and the register hold the same names"
L="$(cat "$T_ROOT/contracts/member-law.md")"
t_has "the law has the clause" "$L" "## 8. Every code change in a project comes with a test"
t_has "...names the trivial architecture" "$L" "test-writing-trivial"
t_has "...and the full one" "$L" '`test-writing`'
t_has "...and the project runner" "$L" "tests/run.sh"
t_has "...and the check id" "$L" "member.tests"
t_eq "both architectures are rows of the register" 2 "$(awk -F'\t' '$1 == "test-writing" || $1 == "test-writing-trivial"' "$T_ROOT/contracts/agent-architectures.tsv" | wc -l | tr -d ' ')"
t_eq "the register row names this script's suite" 1 "$(awk -F'\t' '$1 == "member.tests" && $11 == "tests/member/tests/tests.test.sh"' "$T_ROOT/standards/naming/controls.tsv" | wc -l | tr -d ' ')"
t_eq "the script travels to the laptop" 1 "$(grep -cx 'bin/member-tests.sh' "$T_ROOT/contracts/member-files.txt")"
t_eq "...and so does the register it reads" 1 "$(grep -cx 'contracts/agent-architectures.tsv agent-architectures.tsv' "$T_ROOT/contracts/member-files.txt")"
t_done
