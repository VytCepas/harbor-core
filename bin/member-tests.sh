#!/usr/bin/env sh
# member-tests.sh (harbor#1278) — check `member.tests`, holds contracts/member-law.md §8: a code change in a registered project comes with a test.
#   <hook json> | sh member-tests.sh snap     UserPromptSubmit: remembers each registered project's git state; prints nothing
#   <hook json> | sh member-tests.sh          Stop: prints {"decision":"block","reason":…} or nothing; exit 0 on every path
#
# THE SIGNAL is git, not the transcript: the project's state at prompt submit against its state at Stop, so a write made by a subagent or by
# Bash is seen as well as an Edit. State = HEAD plus every dirty path with the hash of its content. A path is CHANGED in the turn when its
# line differs between the two, when it was dirty at the prompt and is not now, or when HEAD moved and the commits touched it.
# A turn is sent back once when a path of the code class changed and no path of the test class did. stop_hook_active stands it down, so it
# can never block twice. The reason names the architecture (contracts/agent-architectures.tsv): `test-writing-trivial` for one code file and
# under 20 changed lines, `test-writing` for the rest.
#
# PATH CLASSES (a case on the path, class_of below). TEST: tests/, test/, spec/, __tests__/ at any depth, *.test.*, *.spec.*, *_test.*,
# test_*, conftest.py, and only a file with a code extension: a README or a data file in tests/ is OTHER. OTHER, never asked for a test: docs/, doc/, .github/, .claude/, .agents/, dependency and build
# folders, and every extension that is not logic (md, txt, json, yaml, yml, toml, ini, cfg, env, csv, tsv, svg, png, lock, a dotfile). Why:
# a words-only or settings-only change has nothing a test can fail on, and asking for one teaches the person to ignore the check.
# CODE: a script or source file (sh py js ts go rs rb java php sql c cpp cs ps1 gs ipynb and kin). A .yml under models/ is a TEST (a SQL model's
# schema tests live there). Only a path that is PRESENT counts: a deleted test is not a test written, a deleted code file is not a code change,
# and a pure rename (the same bytes under a new name, in the work tree or committed) is neither.
# GIT SAFETY: the hook runs outside the sandbox on a repo the agent can write, so every git call goes through library-git-safe.sh, which never reads
# the repo's config or attributes (a filter, textconv, fsmonitor, hooksPath, pager or include.path there would run a program) and hashes bytes only.
# FAILS OPEN: a linked worktree, a .git file or symlink, a split-index repo (unchecked, see library-git-safe.sh), no jq or git, no hook input, a project not in the registry, no snapshot for it, a repo of the floor itself, a state it cannot
# read, a bound passed (snap 5 s, stop 8 s), any error: nothing is printed and the exit is 0. Registered = a row of the private layer's
# repos.tsv (scope-roots.sh --repos); with no repos.tsv nothing is registered.
# Measured on a labelled corpus: tests/member/tests/measure.sh. Off: the hub policy drops this hook from the managed settings
# (bin/member-managed.sh); the member has no switch, by design. On the operator's box hooks/box-tests wires it (runtime-install); off there: <config dir>/box-tests.off.
set -u
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -- "$HERE" && pwd)" || exit 0
. "$HERE/library-log.sh"
[ -r "$HERE/library-git-safe.sh" ] || exit 0
. "$HERE/library-git-safe.sh"
log_init member-tests

MODE=stop
case "${1:-}" in
  -h|--help) sed -n '2,3p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  snap) MODE=snap ;;
  '') ;;
  *) exit 0 ;;
esac
JQ=/usr/bin/jq
[ -x "$JQ" ] || JQ="$(command -v jq 2>/dev/null || printf '')"
[ -n "$JQ" ] || exit 0
command -v git >/dev/null 2>&1 || exit 0
IN="$(cat 2>/dev/null)" || exit 0
[ -n "$IN" ] || exit 0
SID="$(printf '%s' "$IN" | "$JQ" -r '.session_id // ""' 2>/dev/null)" || exit 0
case "$SID" in ''|*[!A-Za-z0-9._-]*) exit 0 ;; esac
if [ "$MODE" = stop ]; then
  [ "$(printf '%s' "$IN" | "$JQ" -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0
fi
[ -n "${HOME:-}" ] || exit 0
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/harbor/member-tests"
LC_ALL=C; export LC_ALL

W="$(mktemp -d "${TMPDIR:-/tmp}/member-tests.XXXXXX" 2>/dev/null)" || exit 0
BOUNDED_PID=''
trap 'rm -rf "$W"' EXIT
trap 'exit 0' HUP INT TERM

kill_tree() { for _k in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$_k"; done; kill "$1" 2>/dev/null || :; }
# bounded <seconds> <function>: runs it in the background, ends it and what it started past the bound; the exit is then 124.
bounded() {
  "$2" & _bp=$!
  ( sleep "$1"; kill_tree "$_bp" ) >/dev/null 2>&1 </dev/null & _bw=$!
  _brc=0; wait "$_bp" 2>/dev/null || _brc=$?
  kill "$_bw" 2>/dev/null || :
  wait "$_bw" 2>/dev/null || :
  [ "$_brc" -lt 128 ] || return 124
  return "$_brc"
}

# registered_projects -> <name> TAB <checkout> for each registered project that is a git checkout and not the floor's own repo.
registered_projects() {
  _pv="$(sh "$HERE/scope-roots.sh" --private 2>/dev/null)" || return 0
  [ -f "$_pv/repos.tsv" ] || return 0
  sh "$HERE/scope-roots.sh" --repos 2>/dev/null | head -n 24 | while IFS="$(printf '\t')" read -r _n _p; do
    case "$_n" in ''|*[!A-Za-z0-9._-]*) continue ;; esac
    case "$_p" in /*) ;; *) continue ;; esac
    [ -e "$_p/.git" ] || continue
    { [ -f "$_p/bin/harbor" ] && [ -f "$_p/contracts/roots.tsv" ]; } && continue
    printf '%s\t%s\n' "$_n" "$_p"
  done
}

# state_of <checkout> -> the state on stdout: "HEAD <sha|none>", then "<path> TAB <content hash|gone>" per dirty path, sorted. Non-zero on any doubt.
# Every git call goes through library-git-safe.sh (gs_open, gs_git): the repo's own config and attributes are never read, and the hash is of the
# bytes (--no-filters), so nothing the agent wrote into the repo makes git run a program on this hook's behalf.
state_of() {
  gs_open "$1" "$W/g" || return 1
  _head="$(gs_git rev-parse -q --verify HEAD 2>/dev/null)" || _head=none
  gs_git status --porcelain -z -uall 2>/dev/null | tr '\0' '\n' | awk '
    skip { skip = 0; print substr($0, 1); next }
    length($0) < 4 { next }
    { s = substr($0, 1, 2); print substr($0, 4); if (s ~ /[RC]/) skip = 1 }' | sort -u > "$W/dirty" || return 1
  [ "$(wc -l < "$W/dirty" | tr -d ' ')" -le 600 ] || return 1
  printf 'HEAD %s\n' "$_head"
  : > "$W/exist"
  while IFS= read -r _f; do [ -f "$1/$_f" ] && [ ! -L "$1/$_f" ] && printf '%s\n' "$_f" >> "$W/exist"; done < "$W/dirty"
  gs_git hash-object --no-filters --stdin-paths < "$W/exist" > "$W/hashes" 2>/dev/null || return 1
  i=0
  while IFS= read -r _f; do
    if [ -f "$1/$_f" ] && [ ! -L "$1/$_f" ]; then i=$((i + 1)); printf '%s\t%s\n' "$_f" "$(sed -n "${i}p" "$W/hashes")"
    else printf '%s\tgone\n' "$_f"; fi
  done < "$W/dirty" | sort -u
}

class_of() { # <path> -> test | code | other
  _lp="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
  case "$_lp" in
    .git/*|.github/*|.claude/*|.agents/*|docs/*|doc/*|node_modules/*|*/node_modules/*|vendor/*|dist/*|build/*|.venv/*|venv/*|__pycache__/*|*/__pycache__/*|.idea/*|.vscode/*) echo other; return ;;
    tests/*|test/*|spec/*|specs/*|__tests__/*|*/tests/*|*/test/*|*/__tests__/*|*/spec/*|*.test.*|*.spec.*|*_test.*|*_spec.*|test_*|*/test_*|conftest.py|*/conftest.py)
      # a test path counts only as a file with a code extension: a README or a data file inside tests/ is not a test written
      case "${_lp##*/}" in
        *.sh|*.bash|*.zsh|*.py|*.js|*.mjs|*.cjs|*.jsx|*.ts|*.tsx|*.go|*.rs|*.rb|*.java|*.kt|*.php|*.sql|*.c|*.cc|*.cpp|*.h|*.hpp|*.cs|*.swift|*.lua|*.r|*.pl|*.ps1|*.gs|*.vue|*.svelte|*.ipynb) echo test ;;
        *) echo other ;;
      esac
      return ;;
    models/*.yml|models/*.yaml|*/models/*.yml|*/models/*.yaml) echo test; return ;;
  esac
  case "${_lp##*/}" in
    *.sh|*.bash|*.zsh|*.py|*.js|*.mjs|*.cjs|*.jsx|*.ts|*.tsx|*.go|*.rs|*.rb|*.java|*.kt|*.php|*.sql|*.c|*.cc|*.cpp|*.h|*.hpp|*.cs|*.swift|*.lua|*.r|*.pl|*.ps1|*.gs|*.vue|*.svelte|*.ipynb) echo code ;;
    *) echo other ;;
  esac
}

snap_work() {
  mkdir -p "$STATE/$SID" 2>/dev/null || return 0
  find "$STATE" -mindepth 1 -maxdepth 1 -type d -mtime +2 -exec rm -rf {} + 2>/dev/null || :
  registered_projects > "$W/projects"
  while IFS="$(printf '\t')" read -r _n _p; do
    state_of "$_p" > "$W/s.$_n" 2>/dev/null && cp "$W/s.$_n" "$STATE/$SID/$_n" 2>/dev/null
  done < "$W/projects"
  return 0
}

# changed_paths <checkout> <snapshot file> -> "present <path>" or "gone <path>" per path changed in the turn, a pure rename (same bytes, new name) left out.
# A path is changed when its line is new or different since the prompt, or when commits made in the turn touched it. A path that was dirty at the
# prompt and is clean now was committed (the commit diff names it) or reverted (not a change).
changed_paths() {
  state_of "$1" > "$W/now" 2>/dev/null || return 1
  _h0="$(sed -n '1s/^HEAD //p' "$2")"; _h1="$(sed -n '1s/^HEAD //p' "$W/now")"
  sed '1d' "$2" > "$W/a"; sed '1d' "$W/now" > "$W/b"
  comm -13 "$W/a" "$W/b" | awk -F'\t' '{ print ($2 == "gone" ? "gone" : "present") "\t" $1 }' > "$W/c0"
  if [ -n "$_h0" ] && [ "$_h0" != none ] && [ "$_h1" != "$_h0" ] && [ "$_h1" != none ]; then
    gs_git diff --name-status -M100% --no-ext-diff --no-textconv "$_h0" "$_h1" 2>/dev/null | awk -F'\t' '
      $1 == "D" { print "gone\t" $2; next }
      $1 ~ /^R100/ { print "gone\t" $2; print "renamed\t" $3; next }
      $1 ~ /^R/ { print "gone\t" $2; print "present\t" $3; next }
      { print "present\t" $2 }' >> "$W/c0"
  fi
  # a pure rename in the work tree: a present path whose bytes are a deleted path's bytes at the prompt's HEAD
  : > "$W/gone_blobs"
  awk -F'\t' '$1 == "gone" { print $2 }' "$W/c0" | while IFS= read -r _d; do
    [ -z "$_h0" ] || [ "$_h0" = none ] || printf '%s\t%s\n' "$(gs_git rev-parse -q --verify "$_h0:$_d" 2>/dev/null)" "$_d"
  done > "$W/gone_blobs"
  sort -u "$W/c0" | while IFS="$(printf '\t')" read -r _st _p; do
    case "$_st" in
      renamed) continue ;;
      present)
        _hb="$(awk -F'\t' -v p="$_p" '$1 == p { print $2 }' "$W/now")"
        if [ -n "$_hb" ] && awk -F'\t' -v h="$_hb" '$1 == h { f = 1 } END { exit f ? 0 : 1 }' "$W/gone_blobs"; then continue; fi ;;
    esac
    printf '%s\t%s\n' "$_st" "$_p"
  done
}

# size_of <checkout> <snapshot file> <code paths file> -> changed lines over those paths, about (a path dirty at the prompt counts from HEAD at the prompt)
size_of() {
  _h0="$(sed -n '1s/^HEAD //p' "$2")"; _n=0
  while IFS= read -r _f; do
    if [ -n "$_h0" ] && [ "$_h0" != none ] && gs_git cat-file -e "$_h0:$_f" 2>/dev/null; then
      _c="$(gs_git diff --numstat --no-ext-diff --no-textconv "$_h0" -- "$_f" 2>/dev/null | awk '{ s += $1 + $2 } END { print s + 0 }')"
      [ "$_c" -gt 0 ] || _c="$(gs_git diff --numstat --no-ext-diff --no-textconv "$_h0" HEAD -- "$_f" 2>/dev/null | awk '{ s += $1 + $2 } END { print s + 0 }')"
    else _c="$(wc -l < "$1/$_f" 2>/dev/null | tr -d ' ')"; fi
    _n=$((_n + ${_c:-0}))
  done < "$3"
  echo "$_n"
}

# architecture <trivial|full> -> the register's words for it; the case id alone when the register did not travel
architecture() {
  _case=test-writing; [ "$1" = trivial ] && _case=test-writing-trivial
  _row=''
  [ -f "$HERE/agent-architectures.tsv" ] && _row="$(awk -F'\t' -v c="$_case" '$1 == c { print $3 "; rule: " $7; exit }' "$HERE/agent-architectures.tsv")"
  if [ -n "$_row" ]; then printf '%s: roles %s' "$_case" "$_row"; else printf '%s' "$_case"; fi
}

stop_work() {
  [ -d "$STATE/$SID" ] || return 0
  registered_projects > "$W/projects"
  : > "$W/out"
  while IFS="$(printf '\t')" read -r _n _p; do
    [ -f "$STATE/$SID/$_n" ] || continue
    changed_paths "$_p" "$STATE/$SID/$_n" | sort -u > "$W/changed" || continue
    awk -F'\t' '$1 == "present" { print $2 }' "$W/changed" > "$W/changed.present"   # a deleted path is neither a code change nor a test written
    : > "$W/code"; _t=0
    while IFS= read -r _f; do
      [ -n "$_f" ] || continue
      case "$(class_of "$_f")" in code) printf '%s\n' "$_f" >> "$W/code" ;; test) _t=1 ;; esac
    done < "$W/changed.present"
    [ -s "$W/code" ] && [ "$_t" -eq 0 ] || continue
    gs_open "$_p" "$W/g" || continue
    _nf="$(wc -l < "$W/code" | tr -d ' ')"; _nl="$(size_of "$_p" "$STATE/$SID/$_n" "$W/code")"
    _arch=full; { [ "$_nf" -le 1 ] && [ "$_nl" -lt 20 ]; } && _arch=trivial
    _list="$(head -n 3 "$W/code" | tr '\n' ' ' | sed 's/ $//; s/ /, /g')"; [ "$_nf" -le 3 ] || _list="$_list and $((_nf - 3)) more"
    printf 'member.tests: you changed code in the project %s (%s) and no test changed with it. Company rules §8: write the test now, by the architecture %s. Run it with the project'"'"'s own `sh tests/run.sh`, showing it red without the change and green with it. If no test can apply here, say so in one line.\n' "$_n" "$_list" "$(architecture "$_arch")" > "$W/out"
    return 0
  done < "$W/projects"
  return 0
}

if [ "$MODE" = snap ]; then bounded 5 snap_work || :; exit 0; fi
bounded 8 stop_work || exit 0
[ -s "$W/out" ] || exit 0
"$JQ" -nc --arg r "$(cat "$W/out")" '{decision: "block", reason: $r}'
exit 0
