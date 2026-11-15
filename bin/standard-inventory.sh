#!/usr/bin/env sh
# standard-inventory.sh (harbor#1431, harbor#1432, harbor#1433) — the box inventories: every environment variable, every bin/ file
# and every scheduled job is a row of a register, judged both ways.
#
#   sh bin/standard-inventory.sh facts            `G TAB <rule> TAB <subject> TAB <message>` records for standard.env-registered and
#                                                 standard.script-registered, the form bin/lint-name.sh judges
#   sh bin/standard-inventory.sh env [VAR]        a name read in code and the files that read it (derived, never stored)
#   sh bin/standard-inventory.sh callers [FILE]   a bin/ file and the callers the sweep finds: ci, schedule, hook, rule, verb, just,
#                                                 script, shim (derived, never stored; the sweep is lint.tool-has-caller's)
#   sh bin/standard-inventory.sh uncalled         check.script-uncalled: bin/ files nothing calls, as retirement proposals
#   sh bin/standard-inventory.sh schedule         check.schedule-registered: scheduled jobs with no row in the composed check register
#   sh bin/standard-inventory.sh coverage         check.standard.coverage: what the standard does not reach on this box (below)
#   sh bin/standard-inventory.sh page env|cli [--check|--write]   docs/reference/env.md and contracts/cli.md, generated
#   sh bin/standard-inventory.sh --help
#
#   --root <dir>   the tree judged (default: this checkout)    --map <file>  `<path> TAB <file to read>` for every tracked file
#   --local-bin <dir>  coverage: the PATH folder judged beside <config>/bin (default ~/.local/bin)
#   --access <dir>     coverage: the access register's folder (default scope-roots.sh --access)
#
# COVERAGE (harbor#978, layer 3 of the standardization loop) is red on three things, each a finding with its age:
#   surface:<id>  a standards/naming/surfaces.tsv row with checked = no whose note names no owner issue (`owner <repo>#<n>`)
#                 and no YYYY-MM-DD by which it gets a checker, or whose date has passed
#   rule:<id>     a context rule installed on the box whose data (contracts/standard-coverage.tsv, rule-data) is missing or
#                 holds no row: it judges nothing and says nothing
#   tool:<path>   a file in ~/.local/bin or <config>/bin whose bytes no registered repo holds (scope-roots.sh --repos, the
#                 private layer, this tree): untracked, or changed since it was committed, so no colleague ever gets it. A tool
#                 that resolves into a package manager's folder (standard-coverage.tsv, tool-origin) is that manager's
#
# THE REGISTERS HOLD ONLY WHAT NOTHING CAN DERIVE. contracts/env.tsv: kind, default, meaning, owner, controls. contracts/bin.tsv: form,
# layer, purpose, ticket. The readers of a name and the callers of a file come from the tree at the moment of asking, so they cannot drift.
# A name registered in contracts/roots.tsv is a root variable, held there (scope.root-defaults reads it): it is registered once, so a
# name in both registers is red. A kill-switch row names the controls it switches; the schema resolves them against controls.tsv.
#
# A READER of a name is a non-comment line of a tracked file under bin, hooks, skills, tools, runners, launchd, systemd, context-rules,
# registries, worklog, .github or the justfile (prose and tests excluded). A test-only row is read by tests as well.
#
# THE TWO CHECKS REPORT THE DELTA AND THE AGES, never the census (contracts/finding.md): the previous run's subjects are kept in
# <config>/cache/<check>.tsv with the day each was first seen; the report prints what is new, what is fixed and one line for what
# stands. The receipt, <config>/cache/checks/<id>.json, is what the findings channel files as a PROPOSE-lane finding.
#
# exit 0 read or clean · 1 a finding (facts, page --check, or a new finding of a check) · 2 usage · 3 unchecked
set -u
LC_ALL=C; export LC_ALL

case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -- "$HERE" && pwd)"
SELF="$HERE/${0##*/}"
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2   # stdout carries the records and the pages; the log goes to stderr
. "$HERE/library-log.sh"
log_init standard-inventory

usage() { awk 'NR < 2 { next } /^# THE REGISTERS/ || !/^#/ { exit } { sub(/^# ?/, ""); print }' "$SELF"; }
die2() { log_fail "$1"; log_fix "sh $SELF --help"; log_end || :; exit 2; }
die3() { log_fail "$1"; log_fix "${2:-sh $SELF --help}"; log_end || :; exit 3; }

ROOT=""; MAP=""; CMD=""; ARGS=""
REPOS_F=""; REGISTER_F=""; EXEMPT_F=""; LAUNCHD_DIRS=""; LOCAL_BIN="$HOME/.local/bin"; ACCESS_DIR=""; CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; TODAY=""; PRIV_DIR=""; NO_INSTALLED=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --root) [ $# -ge 2 ] || die2 "--root needs a directory"; ROOT="$2"; shift ;;
    --map) [ $# -ge 2 ] || die2 "--map needs a file"; MAP="$2"; shift ;;
    --repos) [ $# -ge 2 ] || die2 "--repos needs a file (name TAB path)"; REPOS_F="$2"; shift ;;
    --register) [ $# -ge 2 ] || die2 "--register needs a file"; REGISTER_F="$2"; shift ;;
    --exempt) [ $# -ge 2 ] || die2 "--exempt needs a file"; EXEMPT_F="$2"; shift ;;
    --launchd-dir) [ $# -ge 2 ] || die2 "--launchd-dir needs a directory"; LAUNCHD_DIRS="$LAUNCHD_DIRS $2"; shift ;;
    --no-installed) NO_INSTALLED=1 ;;
    --local-bin) [ $# -ge 2 ] || die2 "--local-bin needs a directory"; LOCAL_BIN="$2"; shift ;;
    --access) [ $# -ge 2 ] || die2 "--access needs a directory"; ACCESS_DIR="$2"; shift ;;
    --private) [ $# -ge 2 ] || die2 "--private needs a directory"; PRIV_DIR="$2"; shift ;;
    --config-dir) [ $# -ge 2 ] || die2 "--config-dir needs a directory"; CFG="$2"; shift ;;
    --today) [ $# -ge 2 ] || die2 "--today needs YYYY-MM-DD"; TODAY="$2"; shift ;;
    -*) die2 "unknown option: $1" ;;
    *) CMD="$1"; shift; ARGS="$*"; break ;;
  esac
  shift
done
[ -n "$CMD" ] || die2 "no command"
[ -n "$TODAY" ] || TODAY="$(date -u +%Y-%m-%d)"
case "$TODAY" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) die2 "--today needs YYYY-MM-DD, not: $TODAY" ;; esac
[ -n "$ROOT" ] || ROOT="$HERE/.."
ROOT="$(CDPATH='' cd -- "$ROOT" 2>/dev/null && pwd -P)" || die2 "--root is not a directory"

T="$(mktemp -d "${TMPDIR:-/tmp}/standard-inventory.XXXXXX")" || exit 2
trap 'rm -rf "$T"' EXIT INT TERM HUP
TAB="$(printf '\t')"

# The tracked files of the tree, `path TAB file to read`; a caller's --map overlays a fixture.
if [ -z "$MAP" ]; then
  MAP="$T/map"
  if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then git -C "$ROOT" ls-files
  else (cd "$ROOT" && find . -type f ! -path './.git/*' ! -path './build/*' | sed 's#^\./##'); fi \
    | awk -v r="$ROOT" '{ print $0 "\t" r "/" $0 }' > "$MAP"
fi
[ -r "$MAP" ] || die2 "--map is not readable: $MAP"

mapped() { awk -F'\t' -v p="$1" '$1 == p { print $2; exit }' "$MAP"; }

# reg <path> <col>... → the register's columns by NAME through its row in schemas.tsv (one reader, harbor#1424).
reg() {
  _rp="$1"; shift
  sh "$HERE/standard-register.sh" --root "$ROOT" --map "$MAP" get "$_rp" "$@"
}

# ── the readers of a name, and the callers of a file ────────────────────────
# $T/code: the tracked code files a name can be read in
code_files() {
  awk -F'\t' '$1 !~ /\.md$/ && $1 !~ /(^|\/)(tests?|fixtures)\// &&
    ($1 ~ /^(bin|hooks|skills|tools|runners|launchd|systemd|context-rules|registries|worklog|\.github)\// || $1 == "justfile") { print $1 "\t" $2 }' "$MAP"
}

# name_readers <files: path TAB file> → `NAME TAB path` for every HARBOR_* on a non-comment line
name_readers() {
  while IFS="$TAB" read -r _p _f; do [ -r "$_f" ] && printf '%s\t%s\n' "$_p" "$_f"; done < "$1" > "$T/rd.list"
  # shellcheck disable=SC2046 # tracked paths hold no blank
  awk -F'\t' 'FNR == NR { P[$2] = $1; next }
    /^[ \t]*(#|\/\/|\*|<!--)/ { next }
    { l = $0; while (match(l, /HARBOR_[A-Z0-9_]+/)) { n = substr(l, RSTART, RLENGTH); l = substr(l, RSTART + RLENGTH)
        # a trailing underscore is a prefix glob in prose (HARBOR_<FAMILY>_*), not a name
        if (substr(n, length(n)) == "_") continue
        # HARBOR_<SEGMENT>_EOF is a here-document delimiter, not a variable
        if (n ~ /_EOF$/) continue
        k = n SUBSEP P[FILENAME]; if (!(k in S)) { S[k] = 1; print n "\t" P[FILENAME] } } }' "$T/rd.list" $(cut -f2 "$T/rd.list" | tr '\n' ' ') 2>/dev/null | LC_ALL=C sort -u
}

# callers: `file TAB class` for every bin/ file, the sweep of lint.tool-has-caller (harbor#466) widened to every form of file:
# a call is the file's name in COMMAND POSITION (a path, or after sh/bash/exec/python3/bun/node) on a non-comment line of CI, a plist,
# a hook, a rule pack, the dispatcher or the justfile, plus a BARE mention inside another bin/ script, because an installer's
# payload list and a `for h in ...` wiring check are wirings. A file naming itself is not a caller; a test calling a tool is not either.
callers_sweep() {
  awk -F'\t' '$1 ~ /^bin\// { print $1 }' "$MAP" | sed 's#^bin/##' | LC_ALL=C sort -u > "$T/cn.names"
  awk -F'\t' '$1 ~ /^(\.github\/workflows|launchd|systemd|context-rules|runners|worklog)\// || ($1 ~ /^hooks\// && $1 !~ /\.md$/) ||
               $1 ~ /^bin\/[^\/]*\.sh$/ || $1 == "bin/harbor" || $1 == "justfile" || $1 == "contracts/shims.tsv" { print $1 "\t" $2 }' "$MAP" > "$T/cn.surf"
  while IFS="$TAB" read -r _p _f; do [ -r "$_f" ] && printf '%s\t%s\n' "$_p" "$_f"; done < "$T/cn.surf" > "$T/cn.list"
  # shellcheck disable=SC2046 # tracked paths hold no blank
  awk -F'\t' -v NAMES="$(tr '\n' ',' < "$T/cn.names")" 'FNR == NR { P[$2] = $1; next }
    BEGIN { k = split(NAMES, a, ","); for (i = 1; i <= k; i++) if (a[i] != "") { names[a[i]] = 1; if (a[i] !~ /\./) bare[a[i]] = 1 } }
    FNR == 1 { path = P[FILENAME]
      cls = "script"
      if (path ~ /^\.github\//) cls = "ci"; else if (path ~ /^(launchd|systemd)\//) cls = "schedule"
      else if (path ~ /^(hooks|worklog)\//) cls = "hook"; else if (path ~ /^context-rules\//) cls = "rule"
      else if (path == "bin/harbor") cls = "verb"; else if (path == "justfile") cls = "just"
      else if (path == "contracts/shims.tsv") cls = "shim"; else if (path ~ /^runners\//) cls = "runner"
      inbin = (path ~ /^bin\// && path !~ /^bin\/(access-github-app\/)?$/) }
    /^[ \t]*#/ { next }
    { line = $0; gsub(/<[^>]*>/, " ", line); m = split(line, F, /[ \t]+/)
      for (i = 1; i <= m; i++) {
        t = F[i]; gsub(/^[^A-Za-z0-9_.$\/~-]+/, "", t); gsub(/[^A-Za-z0-9_.\/~-]+$/, "", t)
        if (t == "") continue
        b = t; sub(/.*\//, "", b)
        if (!(b in names)) continue
        if (path == "bin/" b) continue
        if (b in bare) { if (t !~ /\//) { if (cls != "shim") continue } }
        else if (b !~ /\.(sh|py|ts|mjs|awk)$/ && t !~ /\//) continue
        if (t ~ /\// || cls == "shim") { print b "\t" cls; continue }
        p = (i > 1) ? F[i - 1] : ""
        if (p == "sh" || p == "bash" || p == "exec" || p == "python3" || p == "python" || p == "bun" || p == "node") { print b "\t" cls; continue }
        if (inbin) print b "\t" cls
      } }' "$T/cn.list" $(cut -f2 "$T/cn.list" | tr '\n' ' ') 2>/dev/null | LC_ALL=C sort -u > "$T/cn.out"
  # a named file sourced by a sibling is a caller too: `. "$HERE/library-log.sh"`, whose token is a path, is found above
  awk -F'\t' 'FNR == NR { C[$1] = (($1 in C) ? C[$1] "," : "") $2; next } { print "bin/" $0 "\t" (($0 in C) ? C[$0] : "-") }' "$T/cn.out" "$T/cn.names"
}

# ── the registers, read ─────────────────────────────────────────────────────
ENV_KINDS="switch kill-switch path tuning value test-only handoff"
BIN_FORMS="command library helper"

# fnd <rule> <subject> <message>
fnd() { printf 'G\t%s\t%s\t%s\n' "$1" "$2" "$3"; }

# env_facts: contracts/env.tsv against the code, both ways (standard.env-registered, harbor#1431)
env_facts() {
  [ -n "$(mapped contracts/env.tsv)" ] || return 0   # a workload carries no env register
  reg contracts/env.tsv var repo kind controls > "$T/env.reg" 2> "$T/env.err" || { log_note "contracts/env.tsv was not read: $(head -n 1 "$T/env.err")"; return 0; }
  if [ -n "$(mapped contracts/roots.tsv)" ] && reg contracts/roots.tsv var > "$T/roots.reg" 2> /dev/null; then :; else : > "$T/roots.reg"; fi
  code_files > "$T/code.files"; name_readers "$T/code.files" > "$T/env.readers"
  awk -F'\t' '$1 ~ /^tests\// && $1 !~ /\.md$/ { print $1 "\t" $2 }' "$MAP" > "$T/test.files"; name_readers "$T/test.files" > "$T/env.treaders"
  # An env name in a dual-read window (renames.tsv, remove_by not past) is read on purpose, and its row is the new name's (harbor#1097).
  _rn="$(mapped standards/naming/renames.tsv)"; : > "$T/env.window"
  [ -z "$_rn" ] || [ ! -r "$_rn" ] || awk -F'\t' -v t="$TODAY" '!/^#/ && $4 == "env" && $2 ~ /^env:/ && $6 >= t { sub(/^env:/, "", $2); print $2 }' "$_rn" | LC_ALL=C sort -u > "$T/env.window"
  awk -F'\t' -v kinds=" $ENV_KINDS " -v OFS='\t' '
    FILENAME == ARGV[1] { R[$1] = 1; next }
    FILENAME == ARGV[2] { if (!($1 in firstp)) firstp[$1] = $2; seen[$1] = 1; next }
    FILENAME == ARGV[3] { T[$1] = 1; next }
    FILENAME == ARGV[4] { W[$1] = 1; next }
    { v = $1; rp = $2; k = $3; c = $4
      if (rp != "harbor") next                     # another repo'"'"'s variable is judged in that repo'"'"'s overlay
      reg_[v] = 1
      if (index(kinds, " " k " ") == 0) print "G", "standard.env-registered", "kind:" v, "contracts/env.tsv row " v " has kind " k ", which is none of:" kinds
      if (k == "kill-switch" && (c == "" || c == "-")) print "G", "standard.env-registered", "switch:" v, "contracts/env.tsv row " v " is a kill-switch and names no control in controls.tsv: say what it switches off"
      if (v in R) print "G", "standard.env-registered", "dup:" v, v " is a row of contracts/env.tsv and of contracts/roots.tsv: a name is registered once (roots.tsv holds root variables)"
      if (!(v in seen) && !(k == "test-only" && (v in T))) print "G", "standard.env-registered", "row:" v, "contracts/env.tsv row " v " is read by nothing in the tree: delete the row or restore the reader"
    }
    END { for (n in seen) if (!(n in reg_) && !(n in R) && !(n in W)) print "G", "standard.env-registered", "var:" n, n " is read in " firstp[n] " and has no row in contracts/env.tsv: add one with its kind, default and meaning" }
  ' "$T/roots.reg" "$T/env.readers" "$T/env.treaders" "$T/env.window" "$T/env.reg" | LC_ALL=C sort
}

# bin_facts: contracts/bin.tsv against bin/, both ways (standard.script-registered, harbor#1432)
bin_facts() {
  [ -n "$(mapped contracts/bin.tsv)" ] || return 0
  reg contracts/bin.tsv path form layer purpose > "$T/bin.reg" 2> "$T/bin.err" || { log_note "contracts/bin.tsv was not read: $(head -n 1 "$T/bin.err")"; return 0; }
  awk -F'\t' -v forms=" $BIN_FORMS " -v OFS='\t' '
    FILENAME == ARGV[1] { if ($1 ~ /^bin\//) F[$1] = 1; next }
    { p = $1; R[p] = 1
      if (!(p in F)) print "G", "standard.script-registered", "row:" p, "contracts/bin.tsv row " p " names a file that is not in the tree: delete the row or restore the file"
      if (index(forms, " " $2 " ") == 0) print "G", "standard.script-registered", "form:" p, "contracts/bin.tsv row " p " has form " $2 ", which is none of:" forms
      want = (p ~ /\.py$/ ? "trio" : (p ~ /\.(ts|mjs)$/ ? "tool" : "floor"))
      if ($3 != want) print "G", "standard.script-registered", "layer:" p, "contracts/bin.tsv row " p " has layer " $3 ", and its language is " want ": layer is floor (sh), trio (Python) or tool (TypeScript)"
      if ($4 == "" || $4 == "-") print "G", "standard.script-registered", "purpose:" p, "contracts/bin.tsv row " p " has no purpose"
    }
    END { for (p in F) if (!(p in R)) print "G", "standard.script-registered", "file:" p, p " is a file under bin/ and has no row in contracts/bin.tsv: add one with its form and purpose" }
  ' "$MAP" "$T/bin.reg" | LC_ALL=C sort
}

# ── the delta and the ages (contracts/finding.md) ───────────────────────────
# delta_report <check id> <state file> <current: subject TAB message> → prints the report, writes state and receipt; sets DELTA_NEW
delta_report() {
  _id="$1"; _st="$2"; _cur="$3"; mkdir -p "$(dirname "$_st")" 2>/dev/null || :
  [ -f "$_st" ] || : > "$_st"
  LC_ALL=C sort -u "$_cur" -o "$_cur"
  awk -F'\t' -v today="$TODAY" -v OFS='\t' 'FILENAME == ARGV[1] { old[$2] = $1; next } { print (($1 in old) ? old[$1] : today), $1, $2 }' "$_st" "$_cur" > "$T/d.next"
  awk -F'\t' 'FILENAME == ARGV[1] { c[$1] = 1; next } !($2 in c) { print $2 }' "$_cur" "$_st" | LC_ALL=C sort > "$T/d.fixed"
  awk -F'\t' 'FILENAME == ARGV[1] { s[$2] = 1; next } !($2 in s) { print $2 "  " $3 }' "$_st" "$T/d.next" | LC_ALL=C sort > "$T/d.new"
  _nn="$(grep -c . "$T/d.new" | tr -d ' ')"; _nf="$(grep -c . "$T/d.fixed" | tr -d ' ')"; _nc="$(grep -c . "$T/d.next" | tr -d ' ')"
  _ns=$((_nc - _nn))
  _tmp="$(mktemp "$(dirname "$_st")/.inv.XXXXXX" 2>/dev/null)" || _tmp=""
  if [ -n "$_tmp" ] && cut -f1,2 "$T/d.next" > "$_tmp" && mv -f "$_tmp" "$_st"; then :; else
    [ -z "$_tmp" ] || rm -f "$_tmp"; log_warn "the state could not be written at $_st, so the next run reports these findings as new again"; fi
  if [ "$_nc" -eq 0 ]; then _rs=green; else _rs=red; fi
  set --; while IFS="$TAB" read -r _a _s _m; do set -- "$@" "$_s"; done < "$T/d.next"
  LOG_RECEIPT_FRESH_DAYS="${INV_FRESH_DAYS:-9}" log_receipt "$(receipt_dir "$CFG")" "$_id" "$_rs" "$@" \
    || log_warn "no receipt could be written under $(receipt_dir "$CFG"), so the findings channel does not see this run"
  printf '[check:%s] %s: %s finding(s): %s new, %s fixed, %s standing\n' "$_id" "$TODAY" "$_nc" "$_nn" "$_nf" "$_ns"
  [ "$_nn" -gt 0 ] || [ "$_nf" -gt 0 ] || printf '  nothing new\n'
  _i=0; while IFS= read -r _x; do _i=$((_i + 1)); [ "$_i" -le 20 ] || break; printf '  new      %s\n' "$_x"; done < "$T/d.new"
  [ "$_nn" -le 20 ] || printf '  new      ... and %s more\n' "$((_nn - 20))"
  _i=0; while IFS= read -r _x; do _i=$((_i + 1)); [ "$_i" -le 20 ] || break; printf '  fixed    %s\n' "$_x"; done < "$T/d.fixed"
  if [ "$_ns" -gt 0 ]; then
    awk -F'\t' 'FILENAME == ARGV[1] { sub(/  .*/, "", $0); n[$0] = 1; next } !($2 in n) { print $1 "\t" $2 }' "$T/d.new" "$T/d.next" | LC_ALL=C sort | head -n 1 > "$T/d.oldest"
    _od="$(cut -f1 "$T/d.oldest")"
    _age="$(awk -v a="$_od" -v b="$TODAY" 'function jd(s, y, m, d) { y = substr(s,1,4)+0; m = substr(s,6,2)+0; d = substr(s,9,2)+0; if (m <= 2) { y--; m += 12 } return int(365.25*y) + int(30.6001*(m+1)) + d } BEGIN { print jd(b) - jd(a) }')"
    printf '  standing %s finding(s) already filed, oldest %s day(s): %s\n' "$_ns" "$_age" "$(cut -f2 "$T/d.oldest" | cut -c1-110)"
  fi
  DELTA_NEW="$_nn"
}

# ── commands ────────────────────────────────────────────────────────────────
cmd_facts() { env_facts; bin_facts; }

cmd_env() {
  code_files > "$T/code.files"; name_readers "$T/code.files" > "$T/env.readers"
  awk -F'\t' -v v="$ARGS" '{ if (v != "" && $1 != v) next; R[$1] = (($1 in R) ? R[$1] ", " : "") $2 } END { for (n in R) print n "\t" R[n] }' "$T/env.readers" | LC_ALL=C sort
}

cmd_callers() {
  callers_sweep | awk -F'\t' -v f="$ARGS" 'f == "" || $1 == f || $1 == "bin/" f'
}

cmd_uncalled() {
  callers_sweep > "$T/cal"
  [ -s "$T/cal" ] || die3 "the caller sweep saw no bin/ file, so nothing is judged" "ls $ROOT/bin"
  awk -F'\t' '$2 == "-" { print $1 }' "$T/cal" | LC_ALL=C sort > "$T/unc"
  # a caller sweep that finds NOTHING called broke: every file would read as a retirement candidate
  [ "$(grep -c . "$T/unc")" -lt "$(( $(grep -c . "$T/cal") * 3 / 4 ))" ] || die3 "the caller sweep found calls for under a quarter of bin/, so its surfaces are broken and nothing is judged" "sh $SELF callers"
  idle="$(mapped contracts/idle-tools.txt)"
  : > "$T/cur"; _verb=0
  while IFS= read -r _f; do
    _b="${_f#bin/}"
    _k="$( [ -z "$idle" ] || awk -v b="$_b" '!/^[ \t]*(#|$)/ && $1 == b { print $2; exit }' "$idle")"
    if [ "$_k" = VERB ]; then _verb=$((_verb + 1)); continue; fi
    printf '%s\t%s\n' "$_f" "no caller in CI, a schedule, a hook, a rule, the dispatcher, the justfile or another script (${_k:-undeclared in idle-tools.txt}): a retirement proposal, a person decides" >> "$T/cur"
  done < "$T/unc"
  delta_report standard.script-uncalled "$CFG/cache/standard-script-uncalled.tsv" "$T/cur"
  [ "$_verb" -eq 0 ] || printf '  (%s more are declared VERB in contracts/idle-tools.txt: typed by a person, not candidates)\n' "$_verb"
  log_end || :
  [ "${DELTA_NEW:-0}" -eq 0 ] || exit 1
  exit 0
}

# schedule: every scheduled job on the box has a row in the composed box check register (harbor#1433)
sched_workflows() { # <repo> <path> → `subject TAB cron`
  find "$2/.github/workflows" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | LC_ALL=C sort | while IFS= read -r _w; do
    awk -v s="$1/.github/workflows/${_w##*/}" '
      /^[ \t]*#/ { next }
      /^on:.*schedule/ { hit = 1; cron = "inline"; next }
      /^[ \t]?[ \t]?[ \t]?[ \t]?schedule:[ \t]*(#.*)?$/ { ins = 12; next }
      ins > 0 { ins--; if ($0 ~ /cron:/) { hit = 1; c = $0; sub(/.*cron:[ \t]*/, "", c); sub(/[ \t]+#.*/, "", c); gsub(/["'"'"']/, "", c); cron = (cron == "" ? c : cron " + " c); ins = 0 } }
      END { if (hit) print s "\t" cron }' "$_w"
  done
}
sched_labels() { # <dir> → `label` for every com.harbor.* plist
  [ -d "$1" ] || return 0
  find "$1" -maxdepth 1 -type f -name 'com.harbor.*.plist' 2>/dev/null | LC_ALL=C sort | while IFS= read -r _p; do
    _l="$(sed -n 's#.*<key>Label</key><string>\(com\.harbor\.[^<]*\)</string>.*#\1#p' "$_p" | head -n 1)"
    printf '%s\n' "${_l:-$(basename "$_p" .plist)}"
  done
}

cmd_schedule() {
  # the repos judged: a file of `name TAB path`, else the registry, with this tree always among them
  if [ -n "$REPOS_F" ]; then [ -r "$REPOS_F" ] || die2 "--repos is not readable: $REPOS_F"; grep -v '^#' "$REPOS_F" > "$T/repos"
  else sh "$HERE/scope-roots.sh" --repos 2>/dev/null | grep -v '^#' > "$T/repos" || : > "$T/repos"
    awk -F'\t' -v r="$ROOT" '$2 == r { f = 1 } END { exit !f }' "$T/repos" || printf 'harbor\t%s\n' "$ROOT" >> "$T/repos"; fi
  [ -s "$T/repos" ] || die3 "no repo registry: no scheduled workflow can be enumerated" "sh $HERE/scope-roots.sh --repos"
  [ -n "$PRIV_DIR" ] || PRIV_DIR="$(sh "$HERE/scope-roots.sh" --private 2>/dev/null)" || PRIV_DIR=""
  [ -n "$EXEMPT_F" ] || { [ -z "$PRIV_DIR" ] || EXEMPT_F="$PRIV_DIR/schedule-exempt.tsv"; }
  # the composed register: core, the private layer, installed packs and each governed repo's own harbor-pack/checks.md
  if [ -n "$REGISTER_F" ]; then [ -r "$REGISTER_F" ] || die2 "--register is not readable: $REGISTER_F"; cp "$REGISTER_F" "$T/register"
  else
    sh "$HERE/check-registry-generate.sh" --core "$ROOT/docs/reference/checks.md" ${PRIV_DIR:+--private "$PRIV_DIR"} --packs "$CFG/checks.d" --repos "$T/repos" > "$T/register" 2> "$T/reg.err" \
      || die3 "the check register does not compose, so no job is judged against it: $(head -n 1 "$T/reg.err")" "sh $HERE/check-registry-generate.sh --help"
  fi
  # exemptions: repo TAB reason TAB remove_by; a lapsed one exempts nothing
  : > "$T/exempt"
  if [ -n "$EXEMPT_F" ] && [ -r "$EXEMPT_F" ]; then
    grep -v '^#' "$EXEMPT_F" | awk -F'\t' -v t="$TODAY" 'NF >= 3 && $1 != "repo" { if ($3 >= t) print $1 "\t" $2; else print "LAPSED\t" $1 }' > "$T/exempt"
  fi
  # a repo renamed in the standard is cited by its new name too: a legacy alias row whose note says `repo renamed <new>` (aliases.tsv)
  : > "$T/codename"
  if [ -n "$(mapped standards/naming/aliases.tsv)" ]; then
    reg standards/naming/aliases.tsv id kind note 2> /dev/null | awk -F'\t' '$2 == "legacy" && match($3, /repo renamed [a-z-]+/) { w = substr($3, RSTART + 13, RLENGTH - 13); print $1 "\t" w }' > "$T/codename"
  fi
  : > "$T/jobs"; : > "$T/unread"; _nrepo=0
  while IFS="$TAB" read -r _n _p; do
    [ -n "$_n" ] || continue
    awk -F'\t' -v n="$_n" '$1 == n { f = 1 } END { exit !f }' "$T/exempt" && continue
    if [ ! -d "$_p/.github" ] && [ ! -d "$_p" ]; then printf '%s\n' "$_n" >> "$T/unread"; continue; fi
    _nrepo=$((_nrepo + 1))
    _alt="$(awk -F'\t' -v n="$_n" '$1 == n { print $2 }' "$T/codename")"
    sched_workflows "$_n" "$_p" | while IFS="$TAB" read -r _s _c; do
      printf 'workflow\t%s\t%s\t%s\n' "$_s" "$_c" "${_alt:+$_alt/${_s#*/}}"; done >> "$T/jobs"
  done < "$T/repos"
  [ "$_nrepo" -gt 0 ] || die3 "none of the registry's repos could be read, so no workflow is judged" "sh $HERE/scope-roots.sh --repos"
  { for _d in $LAUNCHD_DIRS; do sched_labels "$_d"; done
    if [ -z "$LAUNCHD_DIRS" ]; then
      sched_labels "$ROOT/launchd"; [ -z "$PRIV_DIR" ] || sched_labels "$PRIV_DIR/jobs"
      [ "$NO_INSTALLED" = 1 ] || { sched_labels "$HOME/Library/LaunchAgents"; sched_labels /Library/LaunchDaemons; }
    fi; } | LC_ALL=C sort -u | while IFS= read -r _l; do printf 'launchd\t%s\t-\t\n' "$_l"; done >> "$T/jobs"
  # a job is covered when its token stands in the register as a whole word: a prefix of a longer label is not it
  awk -F'\t' '
    function covered(tok, kind,   rest, i, b, a, bad) {
      bad = (kind == "launchd") ? "[A-Za-z0-9_.-]" : "[A-Za-z0-9_.\/-]"
      rest = TEXT
      while ((i = index(rest, tok)) > 0) {
        b = (i > 1) ? substr(rest, i - 1, 1) : " "; a = substr(rest, i + length(tok), 2)
        if (b !~ bad && (a == "" || substr(a, 1, 1) !~ /[A-Za-z0-9_-]/) && !(substr(a, 1, 1) == "." && substr(a, 2, 1) ~ /[A-Za-z0-9]/)) return 1
        rest = substr(rest, i + length(tok))
      }
      return 0
    }
    FILENAME == ARGV[1] { TEXT = TEXT $0 "\n"; next }
    { if (!covered($2, $1) && !($4 != "" && covered($4, $1))) {
        if ($1 == "workflow") print $2 "\t" "scheduled (cron " $3 ") and no row of the box check register names it: add a row whose schedule cell cites the path, in that repo harbor-pack/checks.md or in core"
        else print $2 "\t" "a launchd job and no row of the box check register names it: add a row with its schedule, where it notifies and the disable command" } }
  ' "$T/register" "$T/jobs" > "$T/cur"
  # a repo that could not be read keeps its earlier findings standing; an exemption that lapsed is a finding of its own
  while IFS= read -r _u; do printf 'unread:%s\tthe checkout of %s is not readable, so its scheduled workflows were not judged\n' "$_u" "$_u" >> "$T/cur"; done < "$T/unread"
  awk -F'\t' '$1 == "LAPSED" { print "exemption:" $2 "\tthe exemption of " $2 " in schedule-exempt.tsv has lapsed (remove_by is past): its scheduled workflows are judged again" }' "$T/exempt" >> "$T/cur"
  _nj="$(grep -c . "$T/jobs" | tr -d ' ')"
  delta_report standard.schedule-registered "$CFG/cache/standard-schedule-registered.tsv" "$T/cur"
  printf '  %s scheduled job(s) read in %s repo(s); %s exempt repo(s)\n' "$_nj" "$_nrepo" "$(awk -F'\t' '$1 != "LAPSED"' "$T/exempt" | grep -c . | tr -d ' ')"
  log_end || :
  [ "${DELTA_NEW:-0}" -eq 0 ] || exit 1
  exit 0
}

# coverage: what the standard does not reach on this box (harbor#978): the three kinds in the header, as one delta
cov_count() { # <header row|none> <file>... → data rows over the files: no blank or # line, and each file's header row dropped
  _ch="$1"; shift
  awk -v h="$_ch" 'FNR == 1 { first = 1 } /^[ \t]*$/ || /^[ \t]*#/ { next } { if (first && h == "row") { first = 0; next } first = 0; n++ } END { print n + 0 }' "$@" 2>/dev/null
}
resolve() { # <path> → the file a chain of links ends at, made absolute
  _r="$1"; _k=0
  while [ -L "$_r" ] && [ "$_k" -lt 20 ]; do
    _l="$(readlink "$_r")"; case "$_l" in /*) _r="$_l" ;; *) _r="${_r%/*}/$_l" ;; esac; _k=$((_k + 1))
  done
  _d="$(CDPATH='' cd -- "${_r%/*}" 2>/dev/null && pwd -P)" && _r="$_d/${_r##*/}"
  printf '%s\n' "$_r"
}

cmd_coverage() {
  : > "$T/cur"
  _cv="$(mapped contracts/standard-coverage.tsv)"
  [ -n "$_cv" ] && [ -r "$_cv" ] || die3 "no contracts/standard-coverage.tsv, so no rule's data and no tool origin is known" "git log -- contracts/standard-coverage.tsv"
  reg contracts/standard-coverage.tsv id kind path header note > "$T/cv" 2> "$T/cv.err" || die3 "contracts/standard-coverage.tsv does not read: $(head -n 1 "$T/cv.err")" "sh $HERE/standard-register.sh check"

  # 1. a surface no checker judges carries an owner issue and a date, and the date has not passed
  reg standards/naming/surfaces.tsv id checked note > "$T/sf" 2> "$T/sf.err" || die3 "standards/naming/surfaces.tsv does not read: $(head -n 1 "$T/sf.err")" "sh $HERE/standard-register.sh check"
  awk -F'\t' -v t="$TODAY" -v OFS='\t' '$2 == "no" {
      o = ""; if (match($3, /owner[: ]+[^;(]*/)) o = substr($3, RSTART, RLENGTH)
      own = (o !~ /owner[: ]+none/ && (o ~ /#[0-9]+/ || o ~ /[A-Z][A-Z0-9]*-[0-9]+/))
      d = ""; if (match($3, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) d = substr($3, RSTART, RLENGTH)
      m = (own ? "" : "no owner issue"); if (d == "") m = m (m == "" ? "" : " and ") "no date"
      if (m != "") print "surface:" $1, "surfaces.tsv row " $1 " is checked = no and its note names " m ": write `owner <repo>#<n> by <YYYY-MM-DD>` into it, or give the surface a checker"
      else if (d < t) print "surface:" $1, "surfaces.tsv row " $1 " is checked = no and its date " d " has passed: give it a checker or a new date in its owner issue" }' "$T/sf" >> "$T/cur"
  _nsf="$(awk -F'\t' '$2 == "no"' "$T/sf" | grep -c . | tr -d ' ')"

  # 2. an installed context rule has data to judge with
  if [ -z "$ACCESS_DIR" ]; then ACCESS_DIR="$(sh "$HERE/scope-roots.sh" --access 2>/dev/null)" || ACCESS_DIR=""; fi
  _nr=0
  while IFS="$TAB" read -r _id _kind _path _hdr _note; do
    [ "$_kind" = rule-data ] || continue
    [ -f "$CFG/context-rules/user/$_id.md" ] || continue
    _nr=$((_nr + 1))
    case "$_path" in
      '{access}'*) if [ -z "$ACCESS_DIR" ]; then
          printf 'rule:%s\tcontext rule %s is installed and the access register has no folder on this box, so it judges nothing: %s\n' "$_id" "$_id" "$_note" >> "$T/cur"; continue; fi ;;
    esac
    _p="$(printf '%s' "$_path" | sed -e "s|{rules}|$CFG/context-rules/user|" -e "s|{cfg}|$CFG|" -e "s|{access}|$ACCESS_DIR|")"
    # shellcheck disable=SC2086 # the last segment is a glob on purpose
    set -- $_p; _have=0; for _f in "$@"; do [ -f "$_f" ] && _have=1; done
    if [ "$_have" -eq 0 ]; then
      printf 'rule:%s\tcontext rule %s is installed and %s does not exist, so it judges nothing: %s\n' "$_id" "$_id" "$_path" "$_note" >> "$T/cur"
    elif [ "$(cov_count "$_hdr" "$@")" -eq 0 ]; then
      printf 'rule:%s\tcontext rule %s is installed and %s holds no row, so it judges nothing: %s\n' "$_id" "$_id" "$_path" "$_note" >> "$T/cur"
    fi
  done < "$T/cv"

  # 3. every PATH tool's bytes are held by a registered repo
  if [ -n "$REPOS_F" ]; then [ -r "$REPOS_F" ] || die2 "--repos is not readable: $REPOS_F"; grep -v '^#' "$REPOS_F" > "$T/repos"
  else sh "$HERE/scope-roots.sh" --repos 2>/dev/null | grep -v '^#' > "$T/repos" || : > "$T/repos"
    [ -n "$PRIV_DIR" ] || PRIV_DIR="$(sh "$HERE/scope-roots.sh" --private 2>/dev/null)" || PRIV_DIR=""
    [ -z "$PRIV_DIR" ] || printf 'private\t%s\n' "$PRIV_DIR" >> "$T/repos"; fi
  printf 'tree\t%s\n' "$ROOT" >> "$T/repos"
  # paths compare as the file system resolves them (/tmp is /private/tmp on macOS), as resolve() gives a tool's
  canon() { while IFS="$TAB" read -r _a _b; do _c="$(CDPATH='' cd -- "$_b" 2>/dev/null && pwd -P)" || _c="$_b"; printf '%s\t%s\n' "$_a" "$_c"; done; }
  canon < "$T/repos" > "$T/repos.c" && mv -f "$T/repos.c" "$T/repos"
  _hp="$(CDPATH='' cd -- "$HOME" 2>/dev/null && pwd -P)" || _hp="$HOME"
  awk -F'\t' -v h="$_hp" '$2 == "tool-origin" { p = $3; sub(/^\{home\}/, h, p); print p }' "$T/cv" > "$T/origins"
  : > "$T/tools"
  for _dir in "$LOCAL_BIN" "$CFG/bin"; do
    [ -d "$_dir" ] || continue
    for _e in "$_dir"/*; do
      [ -f "$_e" ] && [ -x "$_e" ] || continue   # a tool is an executable file: not a folder, a library, data or a dangling link
      _rp="$(resolve "$_e")"
      awk -v p="$_rp" 'index(p, $0) == 1 { f = 1 } END { exit !f }' "$T/origins" && continue
      printf '%s\t%s\n' "$_e" "$_rp" >> "$T/tools"
    done
  done
  _nt="$(grep -c . "$T/tools" | tr -d ' ')"
  if [ "$_nt" -gt 0 ]; then
    cut -f2 "$T/tools" | git hash-object --stdin-paths > "$T/hashes" 2> "$T/hash.err" || die3 "git hash-object could not read the PATH tools: $(head -n 1 "$T/hash.err")" "git --version"
    # a registered root need not be a repo itself (one holds its repos one level down): the repo around a tool that resolves
    # inside a root is read too
    awk -F'\t' 'FILENAME == ARGV[1] { if ($2 != "") R[$2 "/"] = 1; next }
      { for (r in R) if (index($2, r) == 1) { d = $2; sub(/\/[^\/]*$/, "", d); print d; next } }' "$T/repos" "$T/tools" | LC_ALL=C sort -u |
      while IFS= read -r _d; do _top="$(git -C "$_d" rev-parse --show-toplevel 2>/dev/null)" && printf 'enclosing\t%s\n' "$_top"; done |
      LC_ALL=C sort -u >> "$T/repos"
    : > "$T/held"; _nrepo=0
    while IFS="$TAB" read -r _n _p; do
      [ -n "$_p" ] && [ -d "$_p" ] || continue
      git -C "$_p" rev-parse --git-dir > /dev/null 2>&1 || continue
      _nrepo=$((_nrepo + 1))
      git -C "$_p" cat-file --batch-check < "$T/hashes" 2> /dev/null | awk '$2 == "blob" { print $1 }' >> "$T/held"
    done < "$T/repos"
    [ "$_nrepo" -gt 0 ] || die3 "no registered repo could be read, so no PATH tool is judged" "sh $HERE/scope-roots.sh --repos"
    paste "$T/hashes" "$T/tools" | awk -F'\t' -v h="$HOME" -v hp="$_hp" 'FILENAME == ARGV[1] { H[$1] = 1; next }
      function tilde(x) { if (index(x, h "/") == 1) return "~" substr(x, length(h) + 1); if (index(x, hp "/") == 1) return "~" substr(x, length(hp) + 1); return x }
      !($1 in H) { e = tilde($2); r = tilde($3)
        print "tool:" e "\t" "no registered repo holds the bytes of " e (r != e ? " (it resolves to " r ")" : "") ": untracked, or changed since it was committed, so no colleague gets it; move it into the repo and share that owns it, installed by a pack shim or core shims.tsv" }' "$T/held" - >> "$T/cur"
  fi

  delta_report standard.coverage "$CFG/cache/standard-coverage.tsv" "$T/cur"
  printf '  judged %s unchecked surface(s), %s installed rule(s) with declared data, %s PATH tool(s)\n' "$_nsf" "$_nr" "$_nt"
  log_end || :
  [ "${DELTA_NEW:-0}" -eq 0 ] || exit 1
  exit 0
}

# ── the generated pages ─────────────────────────────────────────────────────
esc() { sed -e 's/|/\\|/g'; }

page_env() {
  reg contracts/env.tsv var repo kind default meaning stability owner controls > "$T/p.env" 2> "$T/p.err" || die3 "contracts/env.tsv does not read: $(head -n 1 "$T/p.err")" "sh $HERE/standard-register.sh check"
  if [ -n "$(mapped contracts/roots.tsv)" ]; then reg contracts/roots.tsv var base rel breaks > "$T/p.roots" 2> /dev/null || : > "$T/p.roots"; else : > "$T/p.roots"; fi
  cmd_env > "$T/p.readers"
  printf -- '---\nkind: reference\nowner: harbor#1431\nstatus: generated\n---\n'
  printf '<!-- generated by sh bin/standard-inventory.sh page env --write from contracts/env.tsv and contracts/roots.tsv — do not edit -->\n'
  printf '<!-- generated-by: sh bin/standard-inventory.sh page env --write -->\n\n'
  printf '# Environment variables\n\nEvery environment variable harbor reads: its kind, default, meaning and owner, from `contracts/env.tsv`. The files that read a name are\nfound in the tree when this page is generated, never typed. A kill-switch names the controls it switches. A root variable (a path under\nthe repos or the box tier) is in `contracts/roots.tsv`, listed after the table.\n\n'
  printf '| variable | kind | default | meaning | owner | controls | read in |\n|---|---|---|---|---|---|---|\n'
  awk -F'\t' 'FILENAME == ARGV[1] { R[$1] = $2; next }
    function e(s) { gsub(/\|/, "\\|", s); return s }
    { n = split(R[$1], a, ", "); r = a[1]; for (i = 2; i <= n && i <= 3; i++) r = r "<br>" a[i]; if (n > 3) r = r "<br>and " (n - 3) " more"; if (n < 1 || a[1] == "") r = "tests only"
      printf "| `%s` | %s | %s | %s | %s | %s | %s |\n", $1, $3, ($4 == "-" ? "none" : "`" e($4) "`"), e($5), $7, ($8 == "-" ? "" : e($8)), r }' "$T/p.readers" "$T/p.env"
  if [ -s "$T/p.roots" ]; then
    printf '\n## Root variables\n\nHeld in `contracts/roots.tsv`, which `scope.root-defaults` reads; a name is registered in one of the two registers, never both.\n\n| variable | base | path | breaks when wrong |\n|---|---|---|---|\n'
    awk -F'\t' 'function e(s) { gsub(/\|/, "\\|", s); return s } { printf "| `%s` | %s | `%s` | %s |\n", $1, $2, $3, e($4) }' "$T/p.roots"
  fi
}

page_cli() {
  _tmpl="$(mapped contracts/cli.md.tmpl)"; [ -n "$_tmpl" ] && [ -r "$_tmpl" ] || die3 "no contracts/cli.md.tmpl: the verb table has no page to land in" "git log -- contracts/cli.md.tmpl"
  reg contracts/verbs.tsv verb script json notes > "$T/p.verbs" 2> "$T/p.err" || die3 "contracts/verbs.tsv does not read: $(head -n 1 "$T/p.err")" "sh $HERE/standard-register.sh check"
  printf '<!-- generated by sh bin/standard-inventory.sh page cli --write from contracts/cli.md.tmpl and contracts/verbs.tsv — do not edit -->\n'
  printf '<!-- generated-by: sh bin/standard-inventory.sh page cli --write -->\n'
  awk -F'\t' 'FILENAME == ARGV[1] { n++; V[n] = $0; next }
    $0 == "<!-- gen:verbs -->" {
      print "| Verb | Script | `--json` | Notes |"; print "|---|---|---|---|"
      for (i = 1; i <= n; i++) { split(V[i], f, "\t"); printf "| `%s` | `%s` | %s | %s |\n", f[1], f[2], f[3], f[4] }
      next }
    { print }' "$T/p.verbs" "$_tmpl"
}

cmd_page() {
  set -- $ARGS; _which="${1:-}"; _mode="${2:---write}"
  case "$_which" in env) _file=docs/reference/env.md; _gen=page_env ;; cli) _file=contracts/cli.md; _gen=page_cli ;; *) die2 "page needs env or cli" ;; esac
  $_gen > "$T/page.out" || exit $?
  case "$_mode" in
    --check) _cur="$(mapped "$_file")"
      if [ -n "$_cur" ] && cmp -s "$T/page.out" "$_cur"; then log_ok "$_file is what $_which generates"; log_end || :; exit 0; fi
      log_fail "$_file is stale or missing against its register"; log_fix "sh bin/standard-inventory.sh page $_which --write"; log_end || :; exit 1 ;;
    --write) mkdir -p "$ROOT/$(dirname "$_file")"; cp "$T/page.out" "$ROOT/$_file"; log_ok "wrote $_file"; log_end || :; exit 0 ;;
    *) die2 "page $_which takes --check or --write" ;;
  esac
}

case "$CMD" in
  coverage) cmd_coverage ;;
  facts) cmd_facts; exit 0 ;;
  env) cmd_env; exit 0 ;;
  callers) cmd_callers; exit 0 ;;
  uncalled) cmd_uncalled ;;
  schedule) cmd_schedule ;;
  page) cmd_page ;;
  *) die2 "unknown command: $CMD" ;;
esac
