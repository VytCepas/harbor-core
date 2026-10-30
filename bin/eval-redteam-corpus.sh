#!/usr/bin/env sh
# eval-redteam-corpus.sh (harbor#1313, decision 23 on harbor#1149) — score the pinned external red-team corpora against this
# checkout's guards, and report only what changed since the last run.
#
#   sh eval-redteam-corpus.sh               fetch the pinned corpora if missing or moved, run them, report the delta
#   sh eval-redteam-corpus.sh --no-refresh  run the corpora already on disk
#   sh eval-redteam-corpus.sh --fuzz        also run shguard's fuzz corpus (about 1,400 cases)
#   sh eval-redteam-corpus.sh --print       the last run against the baseline, nothing run: exit 0 green, 1 red, 3 never run
#   sh eval-redteam-corpus.sh --judge       one hook event on stdin through the sandbox floor in $RT_SBX (the ccg adapter's
#                                      callback): prints `<allow|ask|deny>\t<guard>`
#
# WHY. Pass 14's own lenses were stopped before lens D probed anything, so decision 23 publishes what was untested and
# counts an outside corpus's misses as known findings. This is the instrument that keeps those findings counted.
# PINNED. contracts/redteam-sources.tsv pins each upstream to a commit; a refresh fetches that commit, never HEAD. ccg's
# harness is JavaScript this job executes, and a corpus that moves would move the ratchet for reasons that are not
# Harbor's. Upstream ahead of its pin is a note; adopting it is a reviewed edit to the pin.
# ISOLATION. The guards are this checkout's bin/, installed by admission-install.sh into a throwaway HOME and config dir, so
# no live ledger records a run. A case is judged by every PreToolUse hook that install wires to its tool, as Claude
# Code runs them, for a main-loop session with a human present: exit 2 or a deny refuses, an ask asks, else allow.
# NO CASE TEXT. A case is `<corpus>:<kind>:<n>`, n a JSONL line number or ccg's row index. Nothing here prints, logs or
# stores a case's text; payloads go from the corpus file into the guards through pipes only.
# THE BASELINE. contracts/redteam-baseline.tsv accepts a miss or false positive by id, with its reason. A run is red
# while any is not accepted; deploy-push's release gate reads that through --print. A row added needs the operator's
# review (CODEOWNERS); a row removed is an ordinary commit. --print is also red when the guards or pins changed since.
# FINDINGS: one `[check:eval.redteam-corpus]` line per corpus per run in cache/checks.log: new, cleared, standing of the
# total, unaccepted and the oldest standing age. A new one opens obligation `redteam-corpus`; none unaccepted closes it.
# POSIX sh, jq, git; node for ccg (absent: ccg is skipped, and a skipped corpus is red, never green).
set -eu
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
SELF="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/$(basename -- "$0")"
ROOT="$(dirname -- "$(dirname -- "$SELF")")"

# ── --judge: the ccg adapter's callback, before any logging (its stdout is the verdict) ──
# guard: the last *.sh word of the hook command, so `admission-hook.sh admission-bash.sh` names guard-bash.
rt_judge() { # <sandbox> ; stdin: one hook event
  _ev="$(cat)"; _cfg="$1/cfg"
  _tool="$(printf '%s' "$_ev" | jq -r '.tool_name // ""' 2>/dev/null)" || _tool=''
  _hf="$1/hooks/$(printf '%s' "$_tool" | tr -c 'A-Za-z0-9_.-' '_')"
  [ -f "$_hf" ] || jq -r --arg t "$_tool" '.hooks.PreToolUse[]? | (.matcher // "") as $m
      | select($m == "" or $m == "*" or ($t | test("^(" + $m + ")$"))) | .hooks[]?.command' "$_cfg/settings.json" > "$_hf"
  _v=allow; _g=-
  while IFS= read -r _c; do
    [ -n "$_c" ] || continue
    _r=0
    _o="$(printf '%s' "$_ev" | (cd "$1/work" && env -u HARBOR_ADMISSION_DISABLE -u HARBOR_ADMISSION_SHADOW -u HELM_DISABLE_FLOOR -u HELM_FLOOR_SHADOW -u CLAUDE_PROJECT_DIR \
            HOME="$1/home" CLAUDE_CONFIG_DIR="$_cfg" TMPDIR="$1/tmp" sh -c "$_c") 2>/dev/null)" || _r=$?
    _d=''
    if [ "$_r" = 2 ]; then _d=deny
    elif [ -n "$_o" ]; then _d="$(printf '%s' "$_o" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null)" || _d=''
    fi
    _n="$(printf '%s\n' $_c | grep '\.sh$' | tail -1)"; _n="$(basename -- "${_n:-?}" .sh)"
    case "$_d" in
      deny) _v=deny; _g="$_n"; break ;;
      ask) [ "$_v" = ask ] || { _v=ask; _g="$_n"; } ;;
    esac
  done < "$_hf"
  printf '%s\t%s\n' "$_v" "$_g"
}
if [ "${1:-}" = --judge ]; then
  [ -n "${RT_SBX:-}" ] && [ -f "$RT_SBX/cfg/settings.json" ] || { printf 'error\t-\n'; exit 3; }
  rt_judge "$RT_SBX"; exit 0
fi

. "$ROOT/bin/library-log.sh"
log_init redteam-corpus
# the command a fix line names: a scheduled run executes a temp clone that is gone by the time anyone reads it
SELFCMD="${HARBOR_REDTEAM_SELF:-sh $0}"
MODE=run; REFRESH=1; FUZZ=0
for _a in "$@"; do
  case "$_a" in
    --no-refresh) REFRESH=0 ;;
    --fuzz) FUZZ=1 ;;
    --print) MODE=print ;;
    *) log_fail "unknown option $_a"; log_fix "$SELFCMD --help"; log_end || :; exit 2 ;;
  esac
done
command -v jq >/dev/null 2>&1 || { log_fail "jq is required"; log_fix "$(pkg_hint jq)"; log_end || :; exit 2; }

CORPDIR="${HARBOR_REDTEAM_DIR:-$(sh "$ROOT/bin/scope-roots.sh" --get HARBOR_REDTEAM_DIR)}"
CACHE_DIR="${HARBOR_SCOPE_CACHE_DIR:-${HARBOR_CACHE_DIR:-$HOME/.claude/cache}}"
STATE="$CACHE_DIR/redteam"; LOG="$CACHE_DIR/checks.log"
SOURCES="${HARBOR_REDTEAM_SOURCES:-$ROOT/contracts/redteam-sources.tsv}"
BASELINE="${HARBOR_REDTEAM_BASELINE:-$ROOT/contracts/redteam-baseline.tsv}"
NOW="${HARBOR_TEST_NOW:-${HARBOR_NOW:-$(date +%s)}}"; case "$NOW" in ''|*[!0-9]*) NOW="$(date +%s)" ;; esac
NODE="${HARBOR_NODE:-node}"
iso() { date -u -r "$NOW" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$NOW" +%Y-%m-%dT%H:%M:%SZ; }
age() { # <seconds>
  if [ "$1" -lt 3600 ]; then printf '%dm' $(($1 / 60)); elif [ "$1" -lt 86400 ]; then printf '%dh' $(($1 / 3600))
  else printf '%dd' $(($1 / 86400)); fi
}
rows() { grep -v '^#' "$1" | sed '1d' | grep -v '^[[:space:]]*$' || :; }  # a register's data rows

# the guard tree a run judged: floor-install's own file lists, then the pins. A change to either makes a run stale.
digest() { # <root>
  _fi="$1/bin/admission-install.sh"
  { for _f in $(sed -nE "s/^(GUARDS|RECOVERY|EVENTS)='([^']*)'.*/\2/p" "$_fi" 2>/dev/null) admission-install.sh admission-deny.sh; do
      [ -f "$1/bin/$_f" ] && cat "$1/bin/$_f"; printf '%s\n' "$_f"
    done; cat "$SOURCES" 2>/dev/null; } | cksum | cut -d' ' -f1
}

# ── --print: the last run against TODAY's baseline, so an acceptance or a fix of the baseline applies at once ──
if [ "$MODE" = print ]; then
  [ -f "$STATE/last.tsv" ] || { log_fail "redteam-corpus has never run here"; log_fix "$SELFCMD"; log_end || :; exit 3; }
  _red=0
  [ "$(awk -F'\t' '$1 == "#digest" { print $2 }' "$STATE/last.tsv")" = "$(digest "$ROOT")" ] ||
    { _red=1; log_fail "stale: the guards or the pins changed since the last run"; log_fix "$SELFCMD"; }
  while IFS='	' read -r _c _st _tot _mis _fp _new _clr _old _why; do
    case "$_c" in ''|'#'*) continue ;; esac
    if [ "$_st" != ok ]; then _red=1; log_fail "$_c: $_st - ${_why:-no reason recorded}"; log_fix "$SELFCMD"; continue; fi
    _f="$STATE/$(printf '%s' "$_c" | tr '/' '.').misses"
    _un="$(cut -f1 "$_f" 2>/dev/null | while IFS= read -r _id; do
             rows "$BASELINE" | cut -f1-2 | grep -qxF "$_c	$_id" || echo x; done | wc -l | tr -d ' ')"
    _line="$_c: $_mis miss(es) and $_fp false positive(s) of $_tot, $_un not accepted"
    if [ "$_un" = 0 ]; then log_ok "$_line"; else _red=1; log_fail "$_line"
      log_fix "adjudicate each on harbor#1313: fix and pin it, or accept it in contracts/redteam-baseline.tsv with docs/explanation/admission-baseline.md's residual"; fi
  done < "$STATE/last.tsv"
  log_end || :; exit "$_red"
fi

# ── refresh: the pinned commit, exported without .git/.github/.claude, renamed over the old copy ──
refresh() { # <name> <url> <commit>
  _have="$(cut -d' ' -f1 "$CORPDIR/$1.SOURCE" 2>/dev/null)" || _have=''
  if [ "$_have" = "$3" ] && [ -d "$CORPDIR/$1" ]; then return 0; fi
  _t="$(mktemp -d "$TMP/fetch.XXXXXX")"
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0 \
    git -c core.hooksPath=/dev/null clone -q --filter=blob:none --no-checkout "$2" "$_t/repo" 2>/dev/null ||
    { log_fail "$1: could not clone $2"; log_fix "git ls-remote $2"; return 1; }
  git -C "$_t/repo" cat-file -e "$3^{commit}" 2>/dev/null ||
    { log_fail "$1: the pinned commit $3 is not in $2"; log_fix "a new pin in contracts/redteam-sources.tsv"; return 1; }
  mkdir "$_t/new"
  git -C "$_t/repo" archive "$3" | tar -x -C "$_t/new" --exclude .github --exclude .claude --exclude .gitmodules ||
    { log_fail "$1: git archive of $3 failed"; log_fix "git -C <a clone of $2> archive $3 | tar -t"; return 1; }
  _ahead="$(git -C "$_t/repo" rev-list --count "$3..origin/HEAD" 2>/dev/null)" || _ahead='?'
  [ "$_ahead" = 0 ] || log_note "$1: upstream is $_ahead commit(s) ahead of the pin; adopting them is a reviewed pin change"
  mkdir -p "$CORPDIR"
  [ ! -e "$CORPDIR/$1" ] || mv "$CORPDIR/$1" "$_t/old"
  mv "$_t/new" "$CORPDIR/$1"
  printf '%s %s %s\n' "$3" "$(git -C "$_t/repo" log -1 --format=%cs "$3")" "$2" > "$CORPDIR/$1.SOURCE.tmp" &&
    mv -f "$CORPDIR/$1.SOURCE.tmp" "$CORPDIR/$1.SOURCE"
  log_ok "$1: fetched the pinned $(printf '%s' "$3" | cut -c1-7)"
}

# ── the sandbox floor: this checkout's guards, a throwaway HOME, the config dir beside it (never inside HOME:
# floor-install refuses $HOME/.claude as the live dir). A trailing / is stripped from TMPDIR: a // breaks the guards'
# glob walk (pass 14, E-5). ──
_tb="${TMPDIR:-/tmp}"; _tb="${_tb%/}"
TMP="$(mktemp -d "$_tb/redteam.XXXXXX")"
# the sandbox floor writes its ledgers read-only, so the clean-up makes them writable first
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT INT TERM
SBX="$TMP/sbx"; mkdir -p "$SBX/home" "$SBX/cfg/bin" "$SBX/tmp" "$SBX/work" "$SBX/hooks"
printf '{"permissions":{"allow":[],"deny":[],"disableBypassPermissionsMode":"disable","disableAutoMode":"disable"}}\n' \
  > "$SBX/cfg/settings.json"
# Never the live config dir: floor-install refuses it as well, and this says so before anything is written.
_phys() { (CDPATH='' cd -- "$1" 2>/dev/null && pwd -P); }
LIVE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
[ "$(_phys "$SBX/cfg")" != "$(_phys "$LIVE_DIR")" ] ||
  { log_fail "the sandbox config dir resolves to the live one ($LIVE_DIR)"; log_fix "TMPDIR=<a scratch dir> $SELFCMD"; log_end || :; exit 3; }
if ! (cd "$SBX/work" && env -u HARBOR_ADMISSION_DISABLE -u HARBOR_ADMISSION_SHADOW -u HELM_DISABLE_FLOOR -u HELM_FLOOR_SHADOW HOME="$SBX/home" CLAUDE_CONFIG_DIR="$SBX/cfg" \
        TMPDIR="$SBX/tmp" sh -c 'sh "$1/bin/deploy-harden.sh" --apply --dir "$2" && sh "$1/bin/admission-install.sh" --apply --dir "$2"' \
        _ "$ROOT" "$SBX/cfg") > "$TMP/install.out" 2>&1; then
  log_fail "the sandbox floor did not install: $(grep FAIL "$TMP/install.out" | head -1 | sed 's/^ *//')"
  log_fix "sh $ROOT/bin/admission-install.sh --apply --dir <empty dir>"; log_end || :; exit 3
fi
# Canaries: a Write onto the sandbox's own settings must be refused and a bare `true` allowed. Either one wrong means
# the floor is not judging, and scoring a corpus through it would report a lie.
_cw="$(jq -nc --arg p "$SBX/cfg/settings.json" '{tool_name:"Write",tool_input:{file_path:$p,content:"{}"}}' | rt_judge "$SBX" | cut -f1)"
_ct="$(jq -nc '{tool_name:"Bash",tool_input:{command:"true"}}' | rt_judge "$SBX" | cut -f1)"
if [ "$_cw" != deny ] || [ "$_ct" != allow ]; then
  log_fail "the sandbox floor is not judging (settings write: $_cw, true: $_ct); nothing was scored"
  log_fix "sh $ROOT/bin/admission-verify.sh --dir $SBX/cfg"; log_end || :; exit 3
fi

if [ "$REFRESH" = 1 ]; then
  rows "$SOURCES" > "$TMP/sources"   # a file, not a pipe: refresh's log lines must count in this shell
  while IFS='	' read -r _n _u _c; do refresh "$_n" "$_u" "$_c" || echo "$_n" >> "$TMP/refresh.failed"; done < "$TMP/sources"
fi
mkdir -p "$STATE"
DIG="$(digest "$ROOT")"
printf '#digest\t%s\n' "$DIG" > "$TMP/last.tsv"

# ── scoring: each runner writes "<kind>:<n>" per finding to $TMP/<corpus>.found and prints the case total ──
# Measured (harbor#1060, 2026-10-24, load ~18): a full run is 1913 s, 90% of it the 1,343 shguard cases at 1.0-1.9 s
# each, one core: every case runs six guard shells (sys-heavy process spawns), serially. ccg's 200 cases are 10%.
# So the shguard cases fan out over RT_JOBS workers (default: the cgroup's cpus, at least 2, at most 4).
rt_jobs() {
  case "${RT_JOBS:-}" in ''|*[!0-9]*|0) ;; *) echo "$RT_JOBS"; return 0 ;; esac
  _q=''; _p=1
  if [ -r /sys/fs/cgroup/cpu.max ]; then read -r _q _p < /sys/fs/cgroup/cpu.max || _q=''; fi
  case "$_q" in
    ''|*[!0-9]*|0) _c="$(getconf _NPROCESSORS_ONLN 2>/dev/null)" || _c=2 ;;
    *) _c=$(( (_q + _p - 1) / _p )) ;;
  esac
  case "$_c" in ''|*[!0-9]*) _c=2 ;; esac
  [ "$_c" -ge 2 ] || _c=2; [ "$_c" -le 4 ] || _c=4
  echo "$_c"
}
rt_shguard_worker() { # <w> <k> <in> <out> ; judges the cases whose line number % w == k
  awk -v w="$1" -v k="$2" 'NR % w == k { print NR "\t" $0 }' "$3" |
  { while IFS= read -r _l; do
      _i="${_l%%	*}"; _r="${_l#*	}"; _exp="${_r%%	*}"
      if [ -n "${RT_CASE_TRACE:-}" ]; then echo "s $_i" >> "$RT_CASE_TRACE"; sleep 1; echo "e $_i" >> "$RT_CASE_TRACE"; fi
      _v="$(printf '%s' "${_r#*	}" | rt_judge "$SBX" | cut -f1)"
      case "$_exp:$_v" in
        Block:allow|Ask:allow) echo "miss:$_i" ;;
        Allow:ask|Allow:deny) echo "fp:$_i" ;;
        Block:*|Ask:*|Allow:*) ;;
        *) echo "error:$_i" ;;
      esac
    done; echo '#done'; } > "$4"
}
run_shguard() { # <jsonl> ; dangerous = Block or Ask, benign = Allow
  jq -r '(.decision // "") + "\t" + ({tool_name: "Bash", tool_input: {command: (.command // "")}} | tojson)' "$1" > "$TMP/sg.in"
  _w="$(rt_jobs)"; _k=0; _pids=''
  while [ "$_k" -lt "$_w" ]; do
    rt_shguard_worker "$_w" "$_k" "$TMP/sg.in" "$TMP/sg.out.$_k" & _pids="$_pids $!"; _k=$((_k + 1))
  done
  for _p in $_pids; do wait "$_p" || :; done
  : > "$TMP/cur.found"; _k=0
  while [ "$_k" -lt "$_w" ]; do   # a worker that died before its marker lost findings: that is an error, never a green
    if [ "$(tail -1 "$TMP/sg.out.$_k" 2>/dev/null)" = '#done' ]; then grep -v '^#done$' "$TMP/sg.out.$_k" >> "$TMP/cur.found" || :
    else echo "error:0" >> "$TMP/cur.found"; fi
    _k=$((_k + 1))
  done
  sort -t: -k2,2n "$TMP/cur.found" > "$TMP/cur.sorted" && mv -f "$TMP/cur.sorted" "$TMP/cur.found"
  wc -l < "$TMP/sg.in" | tr -d ' '
}
run_ccg() { # <ccg dir> ; the corpus's own harness, through an adapter that calls back into --judge
  cat > "$SBX/adapter.js" <<'EOF'
const { spawnSync } = require('child_process'); const fs = require('fs');
const r = spawnSync('/bin/sh', [process.env.RT_SELF, '--judge'], { input: fs.readFileSync(0), encoding: 'utf8' });
const [v, g] = (r.stdout || '').trim().split('\t');
fs.appendFileSync(process.env.RT_SBX + '/ccg.calls', (v || 'error') + '\n');
if (v === 'deny' || v === 'ask') { process.stderr.write('Rule: ' + g + '\n'); process.exit(2); }
process.exit(v === 'allow' ? 0 : 3);
EOF
  : > "$SBX/ccg.calls"
  (cd "$SBX/work" && HOME="$SBX/home" RT_SELF="$SELF" RT_SBX="$SBX" \
     "$NODE" "$1/tests/red-team.js" --hook "$SBX/adapter.js" --json > "$TMP/ccg.json" 2>/dev/null) || :
  _tot="$(jq -r '.total // empty' "$TMP/ccg.json" 2>/dev/null)" || _tot=''
  [ -n "$_tot" ] && [ "$(wc -l < "$SBX/ccg.calls" | tr -d ' ')" = "$_tot" ] && ! grep -qx error "$SBX/ccg.calls" ||
    { echo error; return 0; }
  jq -r '.cases | to_entries[] | select(.value.pass | not)
         | (if .value.expected == "BLOCK" then "miss" else "fp" end) + ":" + ((.key + 1) | tostring)' "$TMP/ccg.json" > "$TMP/cur.found"
  echo "$_tot"
}

# ── the delta against the previous run's state, its ages, and the line each corpus leaves in checks.log ──
NEWALL=0; UNALL=0; NEWUN=0
unacc() { # <corpus>, ids on stdin -> how many the baseline does not accept
  while IFS= read -r _id; do rows "$BASELINE" | cut -f1-2 | grep -qxF "$1	$_id" || echo x; done | wc -l | tr -d ' '
}
record() { # <corpus> <status> <total> [reason]
  _f="$STATE/$(printf '%s' "$1" | tr '/' '.').misses"
  if [ "$2" != ok ]; then
    printf '%s\t%s\t-\t-\t-\t-\t-\t-\t%s\n' "$1" "$2" "${4:-}" >> "$TMP/last.tsv"
    printf '[check:eval.redteam-corpus] %s %s %s: %s\n' "$(iso)" "$1" "$2" "${4:-}" >> "$LOG" 2>/dev/null || :
    log_fail "$1: $2 - ${4:-}"; log_fix "a skipped or failed corpus is red, never green: fix the cause above, then $SELFCMD"
    UNALL=$((UNALL + 1)); return 0
  fi
  touch "$_f"
  # FILENAME, not NR == FNR: with no previous state the first file is empty and NR == FNR would hold for the second.
  awk -F'\t' -v now="$NOW" -v pf="$_f" 'FILENAME == pf { seen[$1] = $2; next }
      { print $1 "\t" (($1 in seen) ? seen[$1] : now) }' "$_f" "$TMP/cur.found" > "$_f.tmp"
  awk -F'\t' -v pf="$_f" 'FILENAME == pf { p[$1]; next } !($1 in p) { print $1 }' "$_f" "$_f.tmp" > "$TMP/new.ids"
  _new="$(wc -l < "$TMP/new.ids" | tr -d ' ')"; _nu="$(unacc "$1" < "$TMP/new.ids")"
  _clr="$(awk -F'\t' -v pf="$_f.tmp" 'FILENAME == pf { p[$1]; next } !($1 in p)' "$_f.tmp" "$_f" | wc -l | tr -d ' ')"
  mv -f "$_f.tmp" "$_f"
  _mis="$(grep -c '^miss:' "$_f" || :)"; _fp="$(grep -c '^fp:' "$_f" || :)"
  _old="$(cut -f2 "$_f" | sort -n | head -1)"
  _un="$(cut -f1 "$_f" | unacc "$1")"
  printf '%s\tok\t%s\t%s\t%s\t%s\t%s\t%s\t\n' "$1" "$3" "$_mis" "$_fp" "$_new" "$_clr" "${_old:--}" >> "$TMP/last.tsv"
  _oa=''; [ -z "$_old" ] || _oa=" oldest=$(age $((NOW - _old)))"
  printf '[check:eval.redteam-corpus] %s %s new=%s cleared=%s standing=%s of %s unaccepted=%s%s\n' \
    "$(iso)" "$1" "$_new" "$_clr" "$((_mis + _fp))" "$3" "$_un" "$_oa" >> "$LOG" 2>/dev/null || :
  _line="$1: $_mis miss(es), $_fp false positive(s) of $3; new $_new, cleared $_clr, $_un not accepted$_oa"
  if [ "$_un" = 0 ]; then log_ok "$_line"
  else log_fail "$_line"; log_fix "$SELFCMD --print; adjudicate each on harbor#1313, fixed and pinned or accepted in contracts/redteam-baseline.tsv"; fi
  NEWALL=$((NEWALL + _new)); UNALL=$((UNALL + _un)); NEWUN=$((NEWUN + _nu))
}

score() { # <corpus> <total-or-error>
  case "$2" in
    ''|*[!0-9]*) record "$1" error 0 "the run did not complete; nothing was scored" ;;
    *) if grep -q '^error:' "$TMP/cur.found"; then record "$1" error "$2" "a guard answered with no verdict"
       else record "$1" ok "$2"; fi ;;
  esac
}

log_head "corpora in $CORPDIR, guards from $ROOT/bin"
for _c in shguard/guardfall shguard/denials shguard/benign_corpus shguard/bypass_corpus shguard/fuzz; do
  [ "$_c" != shguard/fuzz ] || [ "$FUZZ" = 1 ] || continue
  _j="$CORPDIR/shguard/tests/golden/${_c#shguard/}.jsonl"
  if grep -qx shguard "$TMP/refresh.failed" 2>/dev/null; then record "$_c" skipped 0 "the refresh failed"; continue; fi
  [ -f "$_j" ] || { record "$_c" skipped 0 "no $_j"; continue; }
  : > "$TMP/cur.found"; score "$_c" "$(run_shguard "$_j")"
done
if grep -qx ccg "$TMP/refresh.failed" 2>/dev/null; then record ccg skipped 0 "the refresh failed"
elif ! command -v "$NODE" >/dev/null 2>&1; then record ccg skipped 0 "node is not installed, so ccg's harness cannot run"
elif [ ! -f "$CORPDIR/ccg/tests/red-team.js" ]; then record ccg skipped 0 "no $CORPDIR/ccg/tests/red-team.js"
else : > "$TMP/cur.found"; score ccg "$(run_ccg "$CORPDIR/ccg")"; fi

mv -f "$TMP/last.tsv" "$STATE/last.tsv"
EB="$ROOT/bin/event-bus.sh"
# The bus speaks for the live box, so only a run on the live state talks to it (or one handed a bus): a benchmark on
# a scratch cache read all 453 accepted findings as new and opened a handoff on the operator's row.
_live="$(CDPATH= cd -- "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/cache" 2>/dev/null && pwd -P)" || _live=""
_this="$(CDPATH= cd -- "$CACHE_DIR" 2>/dev/null && pwd -P)" || _this=""
if [ -z "${HARBOR_EVENT_DIR:-}" ] && { [ -z "$_live" ] || [ "$_this" != "$_live" ]; }; then :
elif [ "$NEWUN" -gt 0 ]; then  # an accepted finding is already adjudicated: nothing waits on the operator
  sh "$EB" emit obligation.open redteam-corpus --src redteam-corpus \
    --data "$(jq -nc --arg n "$NEWUN" --arg d "$((NOW + 604800))" \
      '{title: ("redteam-corpus: " + $n + " new to adjudicate, harbor#1313"), deadline_ts: ($d | tonumber | todate)}')" >/dev/null 2>&1 || :
  # a week, the check's own cadence, as ISO: the ledger reads no other form, so an epoch fell back to the default 24 h
elif [ "$UNALL" = 0 ]; then
  sh "$EB" emit obligation.close redteam-corpus --src redteam-corpus >/dev/null 2>&1 || :
fi
log_end || :
[ "$UNALL" = 0 ]
