#!/usr/bin/env sh
# injection-rule.sh (harbor#173 · A1; renamed from inject-hook.sh, harbor#1272) — the injector. One engine, many rule packs.
#
#   echo '<hook json>' | sh hooks/injection-rule/injection-rule.sh        read the event from stdin
#   sh hooks/injection-rule/injection-rule.sh --list                      what packs exist, and where
#   sh hooks/injection-rule/injection-rule.sh --explain < payload.json    which rules matched, and why
#
# One file on purpose (lint G1, docs/explanation/modularity.md): the predicate vocabulary and the pack loader are one contract.
# Rules are DATA (context-rules/<repo>/<id>.md); the shell is written once. Why inject at the tool call: E6/E8 in docs/reports/evals.md
# (a rule RESIDENT when the model acts binds; one it must fetch does not).
# Inform by default (E6: inform 4/4, veto 3/4); vetoing is the floor's job (admission-bash.sh, admission-egress.sh).
# One opt-in deny exists: the `run:`-only, PreToolUse-only `HARBOR-DECISION deny:` sentinel (harbor#254), rules at its implementation.
# One opt-in person's line exists too: the box-tier `HARBOR-USER-LINE <row-id>:` sentinel, at most one a session (harbor#1485).
# Conditional or nothing (CONSTITUTION 2.11) and fail-open: no jq, bad JSON, unreadable pack, unknown predicate, erroring `run:` all exit 0 silent.
# Removed notes: docs/explanation/code-cases/hooks-injection-rule-injection-rule.md
set -eu

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
# harbor#813: no dirname fork. A failed or unresolvable $(dirname) left SELF_DIR at the cwd, running ./govern-token.sh from it.
case "$0" in */*) SELF_DIR="${0%/*}" ;; *) SELF_DIR=. ;; esac
[ ! -f "$SELF_DIR/manifest.tsv" ] || SELF_DIR="$SELF_DIR/../../bin"  # D-88: in the repo an engine sits beside its manifest in hooks/<engine>/; deployed, flat beside its libraries

# MEMBER MODE (harbor#1278): `--member-root <managed root>` on a member laptop's managed hook. The only rules are the root's own packs
# (<root>/bin/*.md) that <root>/bin/member-context-rules.tsv lists. The session repo, the box tier and every reached tree are never read:
# a repo is writable by the agent, and a `run:` pack there would execute outside the sandbox. Any fault in this mode is silence (exit 0).
MR=''; MHUB="${XDG_STATE_HOME:-${HOME:-/nonexistent}/.local/state}/harbor/hub/rules"
if [ "${1:-}" = --member-root ]; then
  MR="${2:-}"
  case "$MR" in /*) ;; *) exit 0 ;; esac
  shift 2
fi

MODE=hook
case "${1:-}" in
  '')         MODE=hook ;;
  --explain)  MODE=explain ;;
  --list)     MODE=list ;;
  -h|--help)  sed -n '3,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *)          printf '  FAIL: injection-rule: unknown flag %s\n  fix: sh %s --help\n' "$1" "$0" >&2; exit 2 ;;
esac

# -- pack discovery --
# Two tiers, box then repo; the order is the precedence. The repo comes from the session's cwd (CLAUDE_PROJECT_DIR), not from $0:
# the installed copy must serve whatever repo the session stands in.
# Member mode finds it after its fast exit below: the git fork is not paid by a call no rule targets.
set_repo() {
  REPO="$(cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$REPO" ] || REPO="${CLAUDE_PROJECT_DIR:-$PWD}"
}
REPO=''; [ -n "$MR" ] || set_repo

# The two tiers can be the same directory (project dir = $HOME), and then box packs fire twice and `once: session` spends its key early.
# Compared physically (symlinks resolved, lint D2): /tmp and /private/tmp differ as strings.
_phys() { CDPATH='' cd -P -- "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }

# A rule is context-rules/<scope>/<id>.md (harbor#1010, D-43, D-65); the old inject.d/ layout is retired and not read.
# Box tier: $CFG/context-rules/user. A tree: each context-rules/<scope>/ but user (the box
# tier's source, which only the installer delivers). A tree dir that IS a box dir is dropped.
box_dirs() {
  if [ -n "$MR" ]; then
    [ ! -d "$MR/bin" ] || printf '%s\n' "$MR/bin"
    # The signed hub's rules, delivered by hub.sh into the hub's state: a folder the agent cannot write (member_protected), rebuilt at every sync.
    for _hd in "$MHUB"/*/; do [ ! -d "$_hd" ] || printf '%s\n' "${_hd%/}"; done
    return 0
  fi
  for _bd in "$CFG/context-rules/user"; do [ ! -d "$_bd" ] || printf '%s\n' "$_bd"; done
  return 0
}
BOXP=''; [ -n "$MR" ] || BOXP="$(box_dirs | while IFS= read -r _bd; do _phys "$_bd"; printf '\n'; done)"   # member mode reads no tree, so nothing to de-duplicate
tree_dirs() { # <tree>
  [ -z "$MR" ] || return 0   # member mode: no tree is a source of rules
  for _td in "$1"/context-rules/*/; do
    _td="${_td%/}"
    [ -d "$_td" ] || continue
    case "$_td" in "$1/context-rules/user") continue ;; esac
    case "$NL$BOXP$NL" in *"$NL$(_phys "$_td")$NL"*) continue ;; esac
    printf '%s\n' "$_td"
  done
  return 0
}

# ONE TIER'S RULES, IN ORDER (harbor#1010). By `order:`, else an old file name's NN- prefix, else after every
# ordered rule; then by file name, which is what the old glob order was. One awk and one sort per tier, not per file.
rule_files() { # <dir>... (new layout first) -> one rule file per line; an id already seen in an earlier dir is skipped
  for _rd in "$@"; do for _rf in "$_rd"/*.md; do [ ! -f "$_rf" ] || printf '%s\n' "$_rf"; done; done | awk '
    { f = $0; n = f; sub(/^.*\//, "", n); id = n; sub(/\.md$/, "", id); o = ""; hid = 0; hor = 0; ln = 0
      while ((getline l < f) > 0) {
        ln++
        if (ln == 1) { if (l !~ /^---[[:space:]]*$/) break; continue }
        if (l ~ /^---[[:space:]]*$/) break
        if (l ~ /^id:/ && !hid)    { hid = 1; v = l; sub(/^id:[[:space:]]*/, "", v); if (v != "") id = v }
        if (l ~ /^order:/ && !hor) { hor = 1; v = l; sub(/^order:[[:space:]]*/, "", v); o = v }
      }
      close(f)
      if (o !~ /^[0-9]+$/) { o = 1000; if (match(n, /^[0-9]+-/)) o = substr(n, 1, RLENGTH - 1) + 0 }
      if (id in seen) next
      seen[id] = 1
      printf "%d\t%s\t%s\n", o, n, f }' | sort -t "$(printf '\t')" -k1,1n -k2,2 | cut -f3-
}

# Collation pinned: glob order is LC_COLLATE-dependent and a differing order would flap diff-based checks.
LC_ALL=C
export LC_ALL

# -- frontmatter --
# Frontmatter only, never the body: packs are documents ABOUT matching and would classify themselves (as skill-catalog.sh records).
fm()   { awk 'NR==1 && $0 !~ /^---[[:space:]]*$/ { exit }
              NR>1  && $0 ~  /^---[[:space:]]*$/ { exit }
              NR>1' "$1"; }
body() { awk 'BEGIN { n = 0 }
              /^---[[:space:]]*$/ { n++; next }
              n >= 2' "$1"; }
fmv()  { fm "$1" | awk -v k="^$2:[[:space:]]*" '$0 ~ k { sub(k, ""); print; exit }'; }
fmall(){ fm "$1" | awk -v k="^$2:[[:space:]]*" '$0 ~ k { sub(k, ""); print }'; }

# -- the same answers, one awk per pack (harbor#669) --
# fmv is `fm | awk`; the sweep asks every pack on every event, so it reads frontmatter once (fm_load) and answers by string handling.
# Same match as fmv (first `<key>:` line, blanks after the colon stripped); fmv/fmall stay for --list.
NL='
'
fm_load() { _FM="$(fm "$1")"; }
fm_scan() { # <key> <all:0|1> -> FMV, the first value (or every value, one per line)
  FMV=''; _rest="$_FM"
  while [ -n "$_rest" ]; do
    _l="${_rest%%"$NL"*}"
    if [ "$_l" = "$_rest" ]; then _rest=''; else _rest="${_rest#*"$NL"}"; fi
    case "$_l" in
      "$1:"*)
        _x="${_l#"$1":}"; _x="${_x#"${_x%%[! 	]*}"}"
        if [ "$2" = 1 ]; then FMV="$FMV$_x$NL"; else FMV="$_x"; return 0; fi ;;
    esac
  done
  return 0
}
fm_get() { fm_scan "$1" 0; }
fm_all() { fm_scan "$1" 1; }

if [ "$MODE" = list ]; then
  printf 'injection-rule — rule packs visible from %s\n\n' "$REPO"
  # In sweep order, each tier merged across both layouts (harbor#1010), so the list is what fires and in what order.
  for _tier in box repo; do
    if [ "$_tier" = box ]; then _ds="$(box_dirs)"; else _ds="$(if [ -n "$REPO" ]; then tree_dirs "$REPO"; fi)"; fi
    [ -n "$_ds" ] || continue
    printf '%s tier: %s\n' "$_tier" "$(printf '%s\n' "$_ds" | sed "s|^$HOME/|~/|" | tr '\n' ' ')"
    _IFS="$IFS"; IFS="$NL"; set -f; set -- $_ds; set +f; IFS="$_IFS"  # one dir per line
    rule_files "$@" | while IFS= read -r f; do
      printf '  %-40s %-14s %-8s %s\n' "${f#"$HOME"/}" \
        "$(fmv "$f" event)" "$(fmv "$f" tool)" "$(fmall "$f" when | tr '\n' ';')"
    done
    printf '\n'
  done
  exit 0
fi

# -- member mode: a call no rule targets pays almost nothing --
# The managed settings run this on every tool call (a root-owned file the agent-side sync cannot rewrite, so the matcher stays `*`), so before any payload
# parsing: no rule file at all is an exit, and so is a call whose event and tool name no loadable rule names. One awk reads every rule file once.
# The rules folder is protected by the sandbox and the Edit deny rows (member_protected), not by ownership: the worst a hand-written note there does is
# fire as a note, because a rule with run: or spoke: never loads and so no script can run.
if [ -n "$MR" ] && [ "$MODE" = hook ]; then
  _mrf=''; _mrd="$(box_dirs)"
  _IFS="$IFS"; IFS="$NL"; set -f; set -- $_mrd; set +f; IFS="$_IFS"
  _mrn=0; for _d in "$@"; do for _f in "$_d"/*.md; do [ -f "$_f" ] && _mrn=$((_mrn + 1)); done; done
  [ "$_mrn" -gt 0 ] || exit 0
  PAYLOAD="$(cat)"
  [ -n "$PAYLOAD" ] || exit 0
  command -v jq >/dev/null 2>&1 || exit 0
  _mrq="$(printf '%s' "$PAYLOAD" | jq -r '[.hook_event_name // "", .tool_name // ""] | join("\t")' 2>/dev/null || true)"
  _mre=''; _mrt=''
  IFS='	' read -r _mre _mrt <<MRQ
$_mrq
MRQ
  [ -n "$_mre" ] || exit 0
  for _d in "$@"; do for _f in "$_d"/*.md; do [ ! -f "$_f" ] || set -- "$@" "$_f"; done; shift; done
  awk -v mr="$MR/bin/" -v al="$MR/bin/member-context-rules.tsv" -v ev="$_mre" -v tl="$_mrt" '
    BEGIN { while ((getline l < al) > 0) { split(l, a, "\t"); if (a[1] !~ /^#/ && a[1] != "" && a[1] != "id") ok[a[1]] = 1 } }
    function done_file() {
      if (f == "" || e != ev || r) return
      if (index(f, mr) == 1 && !(id in ok)) return
      if (t == "" || tl ~ ("^(" t ")$")) hit = 1
    }
    FNR == 1 { done_file(); f = FILENAME; id = FILENAME; sub(/^.*\//, "", id); sub(/\.md$/, "", id); e = t = ""; r = 0; fm = 0; if ($0 ~ /^---[ \t]*$/) fm = 1; next }
    fm == 1 && /^---[ \t]*$/ { fm = 2; next }
    fm == 1 {
      if ($0 ~ /^id:/) { v = $0; sub(/^id:[ \t]*/, "", v); if (v != "") id = v }
      else if ($0 ~ /^event:/) { e = $0; sub(/^event:[ \t]*/, "", e) }
      else if ($0 ~ /^tool:/) { t = $0; sub(/^tool:[ \t]*/, "", t) }
      else if ($0 ~ /^(run|spoke):/) r = 1
    }
    END { done_file(); exit !hit }' "$@" 2>/dev/null || exit 0
  set_repo
else
# No jq means no valid JSON for arbitrary text: silence, since a missed note costs only a note.
PAYLOAD="$(cat)"
[ -n "$PAYLOAD" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
fi

field() { printf '%s' "$PAYLOAD" | jq -r "$1 // empty" 2>/dev/null || true; }

EVENT="$(field '.hook_event_name')"
[ -n "$EVENT" ] || exit 0
TOOL="$(field '.tool_name')"
SID="$(field '.session_id')"
CMD="$(field '.tool_input.command' | head -c 262144)"
FPATH="$(field '.tool_input.file_path')"
# SessionStart's `source` (startup|resume|clear|compact|fork) is what lets the post-compaction rule exist without firing on every start.
SOURCE="$(field '.source')"

# Written text for Write/Edit and the tool OUTPUT for PostToolUse, capped so the hook cannot stall its tool call.
# The null filter precedes `tostring`, else a missing tool_response became the literal string `null`.
# `.error` is content too: PostToolUseFailure carries no tool_response, so content-contains could never match there.
CONTENT="$(printf '%s' "$PAYLOAD" | jq -r '
  [ (.tool_input.content? // empty),
    (.tool_input.new_string? // empty),
    (.error? // empty),
    (.tool_response? | select(. != null)
      | if type == "string" then . else (tostring) end) ]
  | map(select(. != null and . != "")) | join("\n")
  # Keep both ends: a head-only cap let an injection past byte 262144 evade the scan.
  | if (length > 262144) then (.[:196608] + "\n" + .[-65536:]) else . end
  ' 2>/dev/null || true)"

# -- provenance --
# Not a label: fetched pages ride the same envelope, so the stamp carries a token derived from a box-local salt (bin/govern-token.sh).
# An empty token degrades to an unlabelled note rather than turning reminders off.
TOK=''
[ -f "$SELF_DIR/govern-token.sh" ] && \
  TOK="$(sh "$SELF_DIR/govern-token.sh" --token "$SID" 2>/dev/null || true)"
STAMP='[HARBOR GOVERNANCE]'
[ -n "$TOK" ] && STAMP="[HARBOR GOVERNANCE $TOK]"

# -- the predicate vocabulary --
# Fixed, not a language: payload values are only ever the subject of a `case`, never a pattern, never eval'd or interpolated (CONSTITUTION 4).
# `case` globs, not grep: this box's grep is a ugrep wrapper (see hooks/pre-commit).

# A heredoc body is not code (see govern-hook.sh's header).
strip_heredocs() {
  printf '%s\n' "$1" | awk '
    BEGIN { skip = 0 }
    skip == 1 { if ($0 == marker) { skip = 0 }; next }
    {
      print
      if (match($0, /<<-?[[:space:]]*'"'"'?"?[A-Za-z_][A-Za-z0-9_]*/)) {
        m = substr($0, RSTART, RLENGTH)
        gsub(/^<<-?[[:space:]]*/, "", m); gsub(/['"'"'"]/, "", m)
        marker = m; skip = 1
      }
    }'
}
# A quoted argument is not code either: unblanked, a commit message mentioning `gh pr create` fired a pack and, being `once: session`, disarmed it for the real call.
# Quoted bodies are blanked (length-preserving, quotes kept) before splitting; state carries across lines.
# An unbalanced quote blanks the rest of the command: a missed note beats a false one (2.11).
blank_quoted() {
  printf '%s\n' "$1" | awk '
    BEGIN { q = "" }
    {
      out = ""
      n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (q == "") {
          out = out c
          if (c == "\"" || c == "\047") q = c
        } else {
          if (c == "\\" && q == "\"") { out = out "  "; i++; continue }
          if (c == q) { out = out c; q = "" } else { out = out " " }
        }
      }
      print out
    }'
}

# Whitespace normalisation lives in this one awk: a `tr` per segment cost a fork pair each and exceeded the hook timeout on long `&&` chains.
segments() {
  blank_quoted "$(strip_heredocs "${1:-}")" \
    | tr '\n;&|()' '\012\012\012\012\012\012\012' \
    | awk '{ gsub(/[[:space:]]+/, " "); sub(/^ /, ""); sub(/ $/, ""); if ($0 != "") print }'
}

# The subcommand, not a substring: the predicate is the first N words of a command-position segment.
seg_prefix() { # <words> -> 0 when some segment starts with exactly those words
  _want="$1"
  while IFS= read -r _s; do
    [ -n "$_s" ] || continue
    case "$_s" in
      "$_want"|"$_want "*) ;;
      *) continue ;;
    esac
    # `--help` renders documentation: a consequence note there is noise. `-h` is deliberately not excluded (a value flag: `docker run -h`, `mysql -h`).
    # Quoted bodies are already blanked, so `--help` inside an argument cannot suppress a real invocation.
    case " $_s " in *' --help '*) continue ;; esac
    case "$_s" in *' --help') continue ;; esac
    return 0
  done <<SEGS
$(segments "$CMD")
SEGS
  return 1
}

# The command word, for tools whose invocation varies in front of the name (inst-quiet-predicates): assignments skipped,
# the word must be the name or a path ending `/name`; `--help` excluded as above.
seg_word() { # <name> -> 0 when some segment's command word is <name>
  _want="$1"
  while IFS= read -r _s; do
    [ -n "$_s" ] || continue
    case " $_s " in *' --help '*) continue ;; esac
    set -f; set -- $_s; set +f
    while [ $# -gt 0 ]; do case "$1" in [A-Za-z_]*=*) shift ;; *) break ;; esac; done
    [ $# -gt 0 ] || continue
    case "${1#\`}" in "$_want"|*/"$_want") return 0 ;; esac
  done <<SEGS
$(segments "$CMD" | sed -e 's/"[ ]*"/Q/g' -e "s/'[ ]*'/Q/g")
SEGS
  return 1
}

pred() { # <predicate line> -> 0 when satisfied
  _p="$1"
  _neg=0
  case "$_p" in 'not '*) _neg=1; _p="${_p#not }" ;; esac
  _kind="${_p%% *}"
  if [ "$_kind" = "$_p" ]; then _arg=''; else _arg="${_p#* }"; fi
  # An unknown predicate is its own answer: returning 1 let `not <typo>` invert into a rule that fired on everything.
  case "$_kind" in
    always|cmd-prefix|cmd-word|cmd-contains|path-contains|content-contains|repo-has|tool-is|source-is|injected-instruction) ;;
    *) explain "unknown predicate '$_kind' — refusing to fire either way"; return 1 ;;
  esac
  _r=1
  case "$_kind" in
    always)               _r=0 ;;
    cmd-prefix)           if seg_prefix "$_arg"; then _r=0; fi ;;
    cmd-word)             if seg_word "$_arg"; then _r=0; fi ;;
    cmd-contains)         case "$(strip_heredocs "$CMD")" in *"$_arg"*) _r=0 ;; esac ;;
    path-contains)        case "$FPATH" in *"$_arg"*) _r=0 ;; esac ;;
    content-contains)     case "$CONTENT" in *"$_arg"*) _r=0 ;; esac ;;
    repo-has)             if [ -e "${RT:-$REPO}/$_arg" ]; then _r=0; fi ;;
    tool-is)              if [ "$TOOL" = "$_arg" ]; then _r=0; fi ;;
    source-is)            if [ "$SOURCE" = "$_arg" ]; then _r=0; fi ;;
    injected-instruction) if detect_injection; then _r=0; fi ;;
    # Unreachable — the vocabulary gate above returned already. Kept so the two
    # lists cannot silently disagree about what a known predicate is.
    *)                    return 1 ;;
  esac
  if [ "$_neg" -eq 1 ]; then
    if [ "$_r" -eq 0 ]; then return 1; else return 0; fi
  fi
  return "$_r"
}

# -- the detector --
# The one predicate that is not a string compare. E9 (docs/reports/evals.md): a plausible 'documentation convention' injection was obeyed even with section 4 present.
# So it looks for text addressed to the PROCESSOR of the content, not for menace. LOUD phrases fire alone; QUIET ones need two, or one plus a MARKERS hit.
LOUD='ignore previous instruction
ignore all previous
ignore prior instruction
ignore the above
disregard previous
disregard all prior
disregard the above
system directive
new system prompt
override your instruction
override the system prompt
you are now a helpful assistant
you are now an ai
you are now in developer mode
do not mention this instruction
do not mention this to the user
do not tell the user
without informing the user
without telling the user
do not reveal this
this instruction is confidential
important instruction for the assistant
note to the ai
attention: ai'

QUIET='any task that
any agent reading
any assistant reading
before summarising this
before summarizing this
before you summarise
before you summarize
must first create
must first write
must first run
must first send
required by the documentation pipeline
is required by the pipeline
so the pipeline can track
then proceed with the summary
proceed with the summary as normal
proceed as normal
as an ai assistant
if you are an ai
when processing this file
any model reading'

MARKERS='create a file named
write a file named
containing the single word
curl -
send it to
upload it to
export the contents
credentials
api key
access token
.env
base64 -d
| sh
| bash'

hits_in() { # <list> -> count of list entries present in $_hay
  _c=0
  while IFS= read -r _ph; do
    [ -n "$_ph" ] || continue
    case "$_hay" in *"$_ph"*) _c=$(( _c + 1 )) ;; esac
  done <<HITS
$1
HITS
  printf '%s' "$_c"
}

# PROVENANCE (harbor#327). A Read whose output is a slice of a file that is tracked in a
# KNOWN repo (the session's, or a registered one) and unmodified vs HEAD is the repo's own
# committed text. Never a path rule: an untracked, edited or foreign-repo file still fires.
own_committed_file() { # <path> -> 0 iff tracked, clean, in a known repo and operator-reviewed; sets _oc_pd _oc_fn
  [ -z "$MR" ] || return 1   # member mode: the repo's own HEAD vouches for nothing the agent could have committed
  [ -f "$1" ] && [ ! -L "$1" ] || return 1
  case "$1" in */*) _oc_pd="$(_phys "${1%/*}")" ;; *) _oc_pd="$(_phys .)" ;; esac; _oc_fn="${1##*/}"
  _oc_top="$(git -C "$_oc_pd" rev-parse --show-toplevel 2>/dev/null || true)"; [ -n "$_oc_top" ] || return 1
  _oc_top="$(_phys "$_oc_top")"
  [ "$_oc_top" = "$(_phys "$REPO")" ] || registered "$_oc_top" || return 1
  git -C "$_oc_pd" ls-files --error-unmatch -- "$_oc_fn" >/dev/null 2>&1 || return 1
  git -C "$_oc_pd" diff --quiet HEAD -- "$_oc_fn" 2>/dev/null || return 1
  # Operator-reviewed only: a row of the committed protected-paths register (the CODEOWNERS source).
  # Vendored, captured and fixture text stays external whoever merged it.
  _oc_rel="$(git -C "$_oc_pd" ls-files --full-name -- "$_oc_fn" 2>/dev/null)"; [ -n "$_oc_rel" ] || return 1
  case "$_oc_rel" in vendor/*|evals/*|fixtures/*|tests/*.jsonl|tests/*/*.jsonl|tests/*/*/*.jsonl) return 1 ;; esac
  _oc_ok=1
  while IFS="$(printf '\t')" read -r _oc_g _oc_rest; do
    case "$_oc_g" in ''|'#'*|glob) continue ;; esac
    case "$_oc_g" in
      *'**'*) case "$_oc_rel" in $_oc_g) _oc_ok=0; break ;; esac ;;
      *) # `*` stops at `/` in this register, but not in `case`
         case "$_oc_rel" in $_oc_g) [ "$(printf '%s' "$_oc_rel" | tr -dc /)" = "$(printf '%s' "$_oc_g" | tr -dc /)" ] && { _oc_ok=0; break; } ;; esac ;;
    esac
  done <<REG
$(git -C "$_oc_top" show HEAD:.agents/protected-paths.tsv 2>/dev/null)
REG
  [ "$_oc_ok" = 0 ] || return 1
}
own_committed_read() {
  [ "$TOOL" = Read ] && [ -n "$FPATH" ] || return 1
  _oc_raw="$(printf '%s' "$PAYLOAD" | jq -r '.tool_response
    | if type == "string" then . elif type == "object" then (.file.content // empty) else empty end' 2>/dev/null || true)"
  [ -n "$_oc_raw" ] || return 1
  own_committed_file "$FPATH" || return 1
  _oc_body="$(cat "$_oc_pd/$_oc_fn")"
  case "$_oc_body" in *"$_oc_raw"*) return 0 ;; esac
  # Read may number its lines (`   12<TAB>text`); compare without the gutter.
  _oc_raw="$(printf '%s\n' "$_oc_raw" | sed 's/^ *[0-9][0-9]*[	→]//')"
  case "$_oc_body" in *"$_oc_raw"*) return 0 ;; esac
  return 1
}

# The same provenance for a Bash READER (inst-quiet-predicates): every stage a reader (cat/head/tail/sed -n/grep/wc) over own_committed_file files,
# no separator, redirect or substitution, and EVERY output line found in those files. Any foreign byte fails and the detector still runs.
own_committed_bash() {
  [ "$TOOL" = Bash ] && [ -n "$CMD" ] || return 1
  case "$CMD" in *';'*|*'&'*|*'>'*|*'<'*|*'`'*|*'('*|*')'*|*'
'*) return 1 ;; esac
  _ob_cwd="${CWDP:-${CLAUDE_PROJECT_DIR:-$PWD}}"; _ob_files=''; _ob_names=''; _ob_first=1
  set -f
  for _ob_w in $CMD; do
    if [ "$_ob_first" = 1 ]; then
      case "$_ob_w" in cat|head|tail|grep|wc|sed) _ob_verb="$_ob_w" ;; *) set +f; return 1 ;; esac
      [ "$_ob_verb" != sed ] || case "$CMD" in *' -n '*) ;; *) set +f; return 1 ;; esac
      _ob_first=0; continue
    fi
    case "$_ob_w" in '|') _ob_first=1; continue ;; *'|'*) set +f; return 1 ;; esac
    case "$_ob_verb:$_ob_w" in sed:-i*|sed:--in-place*) set +f; return 1 ;; *:-*) continue ;; esac
    _ob_w="${_ob_w#[\'\"]}"; _ob_w="${_ob_w%[\'\"]}"
    case "$_ob_w" in /*) _ob_p="$_ob_w" ;; *) _ob_p="$_ob_cwd/$_ob_w" ;; esac
    [ -f "$_ob_p" ] || continue
    own_committed_file "$_ob_p" || { set +f; return 1; }
    _ob_files="$_ob_files$_oc_pd/$_oc_fn
"; _ob_names="$_ob_names$_ob_w
"
  done
  set +f
  [ "$_ob_first" = 0 ] && [ -n "$_ob_files" ] || return 1
  # Every string the response carries, not only stdout: a field nobody listed is still output.
  _ob_out="$(printf '%s' "$PAYLOAD" | jq -r '(.error // empty), (.tool_response | .. | strings)' 2>/dev/null || true)"
  [ -n "$_ob_out" ] || return 1
  _ob_rc=0
  # ENVIRON, not -v: BSD awk rejects a newline inside a -v value and -v rewrites backslashes.
  printf '%s\n' "$_ob_out" | OB_FILES="$_ob_files" OB_NAMES="$_ob_names" awk '
    function inb(s) { return s == "" || index(body, s) > 0 }
    BEGIN {
      nf = split(ENVIRON["OB_FILES"], fl, "\n"); n = split(ENVIRON["OB_NAMES"], nm, "\n")
      for (k = 1; k <= nf; k++) if (fl[k] != "") { while ((getline b < fl[k]) > 0) body = body b "\n"; close(fl[k]) }
    }
    {
      if ($0 == "--" || inb($0)) next
      if ($0 ~ /^[ \t]*[0-9]+([ \t]+[0-9]+)*([ \t]+total)?$/) next
      if (match($0, /^[ \t]*[0-9]+[:\t-]/) && inb(substr($0, RLENGTH + 1))) next
      for (i = 1; i <= n; i++) {
        if (nm[i] == "") continue
        if ($0 == "==> " nm[i] " <==") next
        if ($0 ~ /^[ \t]*[0-9]+([ \t]+[0-9]+)*[ \t]/ && substr($0, length($0) - length(nm[i]) + 1) == nm[i]) next
        if (index($0, nm[i]) == 1) {
          r = substr($0, length(nm[i]) + 1); c = substr(r, 1, 1); r = substr(r, 2)
          if ((c == ":" || c == "-") && (inb(r) || (match(r, /^[0-9]+[:-]/) && inb(substr(r, RLENGTH + 1))))) next
        }
      }
      exit 1
    }' || _ob_rc=1
  return "$_ob_rc"
}

detect_injection() {
  [ -n "$CONTENT" ] || return 1
  if own_committed_read; then return 1; fi
  if own_committed_bash; then return 1; fi
  # Case-folded once. `tr` is POSIX and, unlike this box's grep, has no flavour.
  _hay="$(printf '%s' "$CONTENT" | tr '[:upper:]' '[:lower:]')"
  _loud="$(hits_in "$LOUD")"; _loud="${_loud:-0}"
  if [ "$_loud" -gt 0 ]; then return 0; fi
  _quiet="$(hits_in "$QUIET")"; _quiet="${_quiet:-0}"
  if [ "$_quiet" -ge 2 ]; then return 0; fi
  if [ "$_quiet" -ge 1 ]; then
    _mark="$(hits_in "$MARKERS")"; _mark="${_mark:-0}"
    if [ "$_mark" -ge 1 ]; then return 0; fi
  fi
  return 1
}

# -- the once-ledger --
# Default once per session: a note repeated on every Bash call is tuned out (2.11). Keyed on the session id (a file per session shares nothing
# across concurrent sessions); no id means no ledger and every rule fires.
SEEN=''
# Vet the session id before it reaches a path (CONSTITUTION 4).
case "$SID" in *[!A-Za-z0-9._-]*) SID='' ;; esac
if [ -n "$SID" ] && [ "$MODE" = hook ]; then
  _sd="$CFG/state/inject"
  mkdir -p "$_sd" 2>/dev/null || true
  if [ -d "$_sd" ]; then
    SEEN="$_sd/$SID.seen"
    # Prune on the way past. A ledger that only grows is a directory nobody
    # notices until it has 40,000 files in it.
    # `*.seen*` takes the line claim beside each ledger too, a directory (harbor#1485).
    find "$_sd" -name '*.seen*' -mtime +7 -exec rm -rf {} + 2>/dev/null || true
  fi
fi

already() { # <key> -> 0 when this session has already been told
  [ -n "$SEEN" ] || return 1
  [ -f "$SEEN" ] || return 1
  while IFS= read -r _k; do
    if [ "$_k" = "$1" ]; then return 0; fi
  done < "$SEEN"
  return 1
}
remember() {
  if [ -n "$SEEN" ]; then printf '%s\n' "$1" >> "$SEEN" 2>/dev/null || true; fi
}
# ONE LINE A SESSION (harbor#1485): mkdir is atomic, so two parallel calls cannot both speak. No ledger means no line. --explain spends nothing.
claim_line() {
  [ "$MODE" = hook ] || return 0
  [ -n "$SEEN" ] && mkdir "$SEEN.line" 2>/dev/null
}

NOTES=''
USERMSG=''
_GREP=/usr/bin/grep; [ -x "$_GREP" ] || _GREP=grep
explain() { [ "$MODE" = explain ] && printf '%s\n' "$*" >&2 || true; }

# -- the trees this call touches (harbor#599) --
# One definition (contracts/injection-rule.md, "The tree a call touches"), computed here for `scope: box` delivery and for repo-tier.sh (HARBOR_CONTEXT_TOUCHED).
# A file tool: its path. A shell command: .cwd, every `-C <dir>`, a `gh -R/--repo` slug mapped under PORT_ROOT. `cd X &&` is not followed (#599).
# The shell half reuses the floor's parser (library-admission.sh, floor_seg_load); heredoc segments are skipped. No guard-lib or oversize command: no targets, silence.

# The repository holding <path>, physically (a not-yet-existing path walks up to the nearest directory).
_top() {
  _d="$1"
  while [ ! -d "$_d" ]; do _d="$(dirname -- "$_d")"; done
  _t="$(CDPATH='' cd -- "$_d" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$_t" ]; then _phys "$_t"; printf '\n'; fi
  return 0
}

# THE DECISION LOG (harbor#953). A rule that spoke leaves one record (g=inject, d=advise|deny, r=<pack id>, or <pack id>-<row id> for a line) through the
# floor's floor_log_decision, read only on a fire; it fails silent, so a box with no ledger stays blind rather than wrong.
# FLOOR_IN is the writer's session anchor alone (harbor#1485): sk then holds whatever the payload's key order, and `c` still reads no payload text.
log_rule() { # <advise|deny|shadow> <pack id or row token>
  [ -f "$SELF_DIR/library-admission.sh" ] || return 0
  ( DIR="$SELF_DIR"; . "$SELF_DIR/library-admission.sh" >/dev/null 2>&1
    # shellcheck disable=SC2034 # FLOOR_TOOL, FLOOR_IN: read by library-admission.sh
    FLOOR_TOOL="$TOOL"; FLOOR_IN="{\"session_id\":\"$SID\""; floor_log_decision inject "$1" "$2.meta" ) >/dev/null 2>&1 || :
}
# A sentinel the pack got wrong: <pack id>--<defect>, which no row token can equal (a row id never starts with `-`). Once a session,
# or a bad table row writes a record on every tool call. d=shadow: recorded, not spoken.
log_defect() { # <pack id> <defect>
  [ "$MODE" = hook ] || return 0
  if already "$1--$2"; then return 0; fi
  remember "$1--$2"
  log_rule shadow "$1--$2"
}
# 27 characters: the writer keeps a 40-character rule, and suggest-tool- takes 13 of them.
row_ok() { # <row id>
  case "$1" in ''|-*|*[!abcdefghijklmnopqrstuvwxyz0-9-]*) return 1 ;; esac
  [ "${#1}" -le 27 ]
}

# THE MODE IS THE REGISTER'S, READ HERE (harbor#1422). A pack's controls.tsv row (type injection, `emitted` = the pack id)
# says shadow (the rule is recorded, never spoken), warn (a note) or block (a `run:` pack's deny is honoured). A pack with
# no row keeps the behaviour it always had, so a repo's own pack or an unreadable register changes nothing.
CTL="${HARBOR_CONTEXT_CONTROLS:-}"
if [ -z "$CTL" ]; then
  for _c in "$SELF_DIR/controls.tsv" "$SELF_DIR/../standards/naming/controls.tsv"; do [ ! -f "$_c" ] || { CTL="$_c"; break; }; done
fi
ctl_mode() { # <pack id> -> shadow|warn|block, or nothing when no row names it
  [ -n "$CTL" ] && [ -f "$CTL" ] || return 0
  awk -F'\t' -v i="$1" '$3 == "injection" && $12 == i { print $2; exit }' "$CTL" 2>/dev/null || :
}

shell_targets() {
  # A case before the fork: most commands carry no -C, -R or --repo at all.
  case "$CMD" in *-C*|*-R*|*--repo*) ;; *) return 0 ;; esac
  [ -f "$SELF_DIR/library-admission.sh" ] || return 0
  (
    # shellcheck disable=SC2034 # DIR: read by library-admission.sh
    DIR="$SELF_DIR"
    . "$SELF_DIR/library-admission.sh" >/dev/null 2>&1
    floor_seg_load "$CMD"
    [ -n "$FLOOR_SEGS" ] || exit 0
    _port="$(floor_port_root)"
    _hascd=0
    printf '%s\n' "$FLOOR_SEGS" | awk '
      function sid(s,   p) { p = index(s, ":"); return substr(s, 1, p - 1) + 0 }
      function val(s,   p) { p = index(s, ":"); return substr(s, p + 1) }
      /^SEGC:/ { s = substr($0, 6); i = sid(s); C[i] = val(s); if (i > M) M = i; next }
      /^SEGA:/ { s = substr($0, 6); i = sid(s); N[i]++; A[i, N[i]] = val(s); if (i > M) M = i; next }
      /^SEGR:/ { s = substr($0, 6); i = sid(s); r = val(s)
                 if (substr(r, 1, 3) == "<<:") { d = substr(r, 4); sub(/^-/, "", d); H[i] = d }
                 next }
      END {
        delim = ""; out = ""; cd = 0
        for (i = 1; i <= M; i++) {
          if (!(i in C)) continue
          # A heredoc body is data, whatever it looks like, until its delimiter.
          if (delim != "") { if (C[i] == delim) delim = ""; continue }
          w = C[i]; sub(/.*\//, "", w)
          if (w == "cd" || w == "pushd") cd = 1
          for (k = 1; k <= N[i]; k++) {
            t = A[i, k]
            if (t == "-C" && k < N[i]) out = out "DIR\t" A[i, k + 1] "\n"
            if (w != "gh") continue
            if ((t == "-R" || t == "--repo") && k < N[i]) out = out "SLUG\t" A[i, k + 1] "\n"
            else if (substr(t, 1, 7) == "--repo=")     out = out "SLUG\t" substr(t, 8) "\n"
          }
          if (i in H) delim = H[i]
        }
        if (cd) printf "CD\t1\n"
        printf "%s", out
      }' | while IFS="$(printf '\t')" read -r _k _v; do
      case "$_k" in
        CD) _hascd=1 ;;
        DIR)
          case "$_v" in
            # A substitution, a variable or a glob names a directory this
            # cannot know. Silent, never guessed.
            *@SUB@*|*'`'*|*'*'*|*'?'*|*'['*) ;;
            /*)            printf '%s\n' "$_v" ;;
            '~')           printf '%s\n' "$HOME" ;;
            '~/'*)         printf '%s/%s\n' "$HOME" "${_v#\~/}" ;;
            '$HOME')       printf '%s\n' "$HOME" ;;
            '$HOME/'*)     printf '%s/%s\n' "$HOME" "${_v#\$HOME/}" ;;
            *'$'*)         ;;
            # Relative to the working folder only when no cd moved it first.
            *)             if [ "$_hascd" = 0 ] && [ -n "$CWDP" ]; then printf '%s/%s\n' "$CWDP" "$_v"; fi ;;
          esac ;;
        SLUG)
          case "$_v" in */*/*) _v="${_v#*/}" ;; esac   # HOST/OWNER/REPO
          case "$_v" in *[!A-Za-z0-9_./-]*|*/*/*|/*|*/|'') continue ;; */*) ;; *) continue ;; esac
          _want="$(printf '%s' "$_v" | tr '[:upper:]' '[:lower:]')"
          for _d in "$_port"/*/; do
            _d="${_d%/}"
            [ -e "$_d/.git" ] || continue
            _u="$(git -C "$_d" config --get remote.origin.url 2>/dev/null || true)"
            _u="${_u%/}"; _u="${_u%.git}"
            _s="$(printf '%s' "$_u" | awk -F'[/:]' 'NF >= 2 { print tolower($(NF - 1) "/" $NF) }')"
            [ "$_s" = "$_want" ] || continue
            printf '%s\n' "$_d"
            break
          done ;;
      esac
    done
  ) 2>/dev/null || true
  return 0
}

touched_trees() {
  [ -z "$MR" ] || return 0   # member mode: no other tree is reached
  _pp="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty' 2>/dev/null || true)"
  {
    case "$_pp" in
      '')    ;;
      /*)    printf '%s\n' "$_pp" ;;
      '~')   printf '%s\n' "$HOME" ;;
      '~/'*) printf '%s/%s\n' "$HOME" "${_pp#\~/}" ;;
      *)     if [ -n "$CWDP" ]; then printf '%s/%s\n' "$CWDP" "$_pp"; fi ;;
    esac
    if [ "$TOOL" = Bash ]; then
      # The session's own project directory reaches nothing new, so a session that never left it costs no fork here.
      if [ -n "$CWDP" ] && [ "$CWDP" != "${CLAUDE_PROJECT_DIR:-$PWD}" ]; then printf '%s\n' "$CWDP"; fi
      shell_targets
    fi
  } | while IFS= read -r _x; do
    [ -n "$_x" ] || continue
    _top "$_x"
  done | awk 'NF && !seen[$0]++'
  return 0
}

# The registry is the trust boundary: a reached tree's packs are delivered and a `run:` pack executes, so only trees listed in projects.tsv
# (box tier, harbor#1010; a worktree counts as its owner) may do that.
REG="$CFG/context-rules/user/projects.tsv"
registered() { # <physical tree>
  [ -z "$MR" ] || return 1   # member mode: the registry is a user-writable file, so no tree is ever trusted by it
  [ -f "$REG" ] || return 1
  _own="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  case "$_own" in */.git) _own="$(_phys "${_own%/.git}")" ;; *) _own='' ;; esac
  while IFS="$(printf '\t')" read -r _rn _rp _rc; do
    case "$_rn" in ''|'#'*) continue ;; esac
    case "$_rp" in '~/'*) _rp="$HOME/${_rp#\~/}" ;; esac
    [ -d "$_rp" ] || continue
    _rp="$(_phys "$_rp")"
    if [ "$_rp" = "$1" ] || [ "$_rp" = "$_own" ]; then return 0; fi
  done < "$REG"
  return 1
}

TOUCHED=''; REACHED=''
CWDP="$(field '.cwd')"
case "$EVENT" in
  PreToolUse|PostToolUse|PostToolUseFailure)
    TOUCHED="$(touched_trees)"
    _gov="$(_phys "$REPO")"
    while IFS= read -r _t; do
      [ -n "$_t" ] || continue
      [ "$_t" != "$_gov" ] || continue
      [ -n "$(tree_dirs "$_t")" ] || continue
      if registered "$_t"; then
        REACHED="$REACHED$_t
"
        explain "reach $_t: registered — its scope: box packs are in the sweep"
      else
        explain "reach $_t: not in $REG — its packs are not delivered"
      fi
    done <<TREES
$TOUCHED
TREES
    ;;
esac
# repo-tier.sh reports what was delivered and what was withheld, and must read
# the same answer the sweep acted on rather than a copy of how it was reached.
HARBOR_CONTEXT_TOUCHED="$TOUCHED"; HARBOR_CONTEXT_REACHED="$REACHED"
export HARBOR_CONTEXT_TOUCHED HARBOR_CONTEXT_REACHED

# -- evaluate every pack --
# Sweep lines are `<file> TAB <tree it speaks for> TAB <reached>`. Box and repo packs speak for the governed tree;
# a reached tree's packs are read only if they declare `scope: box`.
tier_files() { # <tree it speaks for> <reached> <dirs, one per line> -> the sweep lines of one tier
  _tt="$1"; _tr="$2"; _IFS="$IFS"; IFS="$NL"; set -f; set -- $3; set +f; IFS="$_IFS"
  [ $# -gt 0 ] || return 0
  rule_files "$@" | while IFS= read -r _tf; do printf '%s\t%s\t%s\n' "$_tf" "$_tt" "$_tr"; done
}
sweep_files() {
  tier_files "$REPO" 0 "$(box_dirs)"
  if [ -n "$REPO" ]; then tier_files "$REPO" 0 "$(tree_dirs "$REPO")"; fi
  printf '%s' "$REACHED" | while IFS= read -r _t; do
    if [ -n "$_t" ]; then tier_files "$_t" 1 "$(tree_dirs "$_t")"; fi
  done
  return 0
}

# Member mode: the root's own list of the pack ids that ship to members. No list, or an id not on it, is silence.
MALLOW=''
if [ -n "$MR" ]; then
  MALLOW="$(awk -F'\t' '$1 !~ /^#/ && $1 != "id" && $1 != "" { print $1 }' "$MR/bin/member-context-rules.tsv" 2>/dev/null || true)"
fi
DECISION=''; DREASON=''
# The sweep's one held line (harbor#1485): nothing about it is logged, remembered or spoken until the sweep ends with no deny.
H_ID=''; H_ROW=''; H_LINE=''; H_NOTE=''; H_KEY=''; H_ONCE=''; H_CMODE=''; H_DIR=''; H_SPOKE=''; SPOKEN=''
while IFS="$(printf '\t')" read -r _file RT _reach; do
  [ -n "$_file" ] || continue
  _dir="${_file%/*}"
  # A decision ends the sweep; the `break` below only leaves the inner loop.
  [ "$DECISION" = deny ] && break
  # One pass per file since harbor#1010; the loop stays so `continue` and the deny `break` keep their meaning.
  for _f in "$_file"; do
    [ -f "$_f" ] || continue
    fm_load "$_f"
    fm_get id; _id="$FMV"; [ -n "$_id" ] || { _id="${_f##*/}"; _id="${_id%.md}"; }
    if [ -n "$MR" ]; then
      # A core pack ships only when the register lists it; a hub pack is live because the signed policy pinned it and its manifest listed the file (hub.sh).
      # Either way a rule that runs something never loads here: the second refusal, after pack.sh's and hub.sh's.
      case "$_dir" in
        "$MR/bin") case "$NL$MALLOW$NL" in *"$NL$_id$NL"*) ;; *) explain "skip $_id: not on the member allow-list"; continue ;; esac ;;
        "$MHUB"/*) ;;
        *) explain "skip $_id: not from the managed root or the hub's delivered rules"; continue ;;
      esac
      fm_get run; _mrun="$FMV"; fm_get spoke
      if [ -n "$_mrun" ] || [ -n "$FMV" ]; then explain "skip $_id: a member loads notes only, and this one has run: or spoke:"; continue; fi
    fi
    if [ "$_reach" = 1 ]; then
      fm_get scope
      if [ "$FMV" != box ]; then
        explain "skip $_id: in a reached tree ($RT) without scope: box — it stays home"; continue
      fi
    fi
    fm_get event; _ev="$FMV"
    [ "$_ev" = "$EVENT" ] || { explain "skip $_id: event $_ev != $EVENT"; continue; }
    fm_get tool; _tl="$FMV"
    if [ -n "$_tl" ] && [ "$_tl" != "$TOOL" ]; then
      # -- tool matching is the harness's regex (harbor#184) --
      # Literal alternation skipped packs declaring `mcp__.*` that the harness matcher had passed. The grep is pinned (lint F3);
      # an unparseable pattern makes grep fail, which reads as no match.
      printf '%s\n' "$TOOL" | "$_GREP" -qE "^($_tl)$" 2>/dev/null \
        || { explain "skip $_id: tool $_tl does not match $TOOL"; continue; }
    fi

    fm_all when; _whens="$FMV"
    _ok=1
    _npred=0
    while IFS= read -r _w; do
      [ -n "$_w" ] || continue
      _npred=$(( _npred + 1 ))
      if ! pred "$_w"; then _ok=0; explain "skip $_id: predicate failed -> $_w"; break; fi
    done <<WHEN
$_whens
WHEN
    [ "$_ok" -eq 1 ] || continue
    # No predicate is not "always": a pack missing its `when:` would fire on every event of its type.
    [ "$_npred" -gt 0 ] || { explain "skip $_id: no when: predicate — refusing to fire"; continue; }

    # ONCE: session | match | never.
    # `match` keys the ledger on what matched, so a benign hit on a document ABOUT injection does not spend the session's single note.
    # The known false-positive set is in hooks/injection-rule/detector.test.sh, not here.
    fm_get once; _once="$FMV"; [ -n "$_once" ] || _once=session
    _key="$_id"
    # The command is part of the subject (harbor#180): without it every Bash command hashed to one empty subject and `once: match` acted as `once: session`.
    # Keyed on the raw command, not the matched prefix, so two merges of different PR numbers each speak.
    if [ "$_once" = match ]; then
      _subject="$FPATH"
      [ -n "$_subject" ] || _subject="$(printf '%s' "$CONTENT" | head -c 4096)"
      [ -n "$_subject" ] || _subject="$(printf '%s' "$CMD" | head -c 4096)"
      _key="$_id:$(printf '%s' "$_subject" | cksum | tr -d ' ')"
    fi
    if [ "$_once" != never ] && already "$_key"; then
      explain "skip $_id: already delivered this session ($_key)"; continue
    fi
    _cmode="$(ctl_mode "$_id")"

    # `run:` - the script gets the payload on stdin and its STDOUT is the note; empty stdout is silence. Invoked as an ARGUMENT to sh (CONSTITUTION 4).
    # Resolved next to its pack, run from the session's repo; `..` and absolute paths are refused.
    fm_get run; _run="$FMV"
    _row=''; _line=''
    if [ -n "$_run" ]; then
      case "$_run" in /*|*..*) explain "skip $_id: run: must be a plain filename beside the pack"; continue ;; esac
      if [ ! -f "$_dir/$_run" ]; then explain "skip $_id: run: $_run not found in $_dir"; continue; fi
      _note="$(printf '%s' "$PAYLOAD" | (cd "${RT:-$REPO}" 2>/dev/null && sh "$_dir/$_run") 2>/dev/null || true)"
      # -- a `run:` pack may return a decision (harbor#254) --
      # Prose in additionalContext cannot stop a Bash call; the merge backstop's deny was silently disarmed through `--note`.
      # The sentinel `HARBOR-DECISION deny: <reason>` as first line is opt-in and exact, and only `run:` output is inspected.
      # permissionDecision is PreToolUse-only (contracts/hooks.md): on other events the sentinel is stripped and delivered as a note, downgrade stated.
      case "$_note" in
        'HARBOR-DECISION deny: '*)
          if [ "$EVENT" = PreToolUse ] && [ "$_cmode" != warn ] && [ "$_cmode" != shadow ]; then
            DECISION=deny
            DREASON="${_note#HARBOR-DECISION deny: }"
            explain "DECIDE $_id: deny"
          else
            _note="${_note#HARBOR-DECISION deny: }"
            explain "downgrade $_id: a deny cannot ride on $EVENT, or its row is $_cmode — delivered as a note"
          fi ;;
        # -- a `run:` pack may supply the person's line (harbor#1485) --
        # Box tier and `mode: notify` only: a repo pack's computed text never reaches a line the operator reads, so there the sentinel is stripped and
        # `summary:` stands. Not re-read after the deny arm: this is one case on the first line, and the rest of the output is only ever a note.
        'HARBOR-USER-LINE '*)
          _ul="${_note%%"$NL"*}"
          if [ "$_ul" = "$_note" ]; then _note=''; else _note="${_note#*"$NL"}"; fi
          fm_get mode
          if [ "$_dir" = "$CFG/context-rules/user" ] && [ "$FMV" = notify ]; then
            _ul="${_ul#HARBOR-USER-LINE }"; _row="${_ul%%: *}"; _line="${_ul#*: }"
            case "$_ul" in *': '*) ;; *) _row='' ;; esac
            case "$_line" in *[![:space:]]*) ;; *) _row='' ;; esac
            if ! row_ok "$_row"; then
              explain "skip $_id: its line sentinel names a bad row, output dropped"
              log_defect "$_id" bad-row
              continue
            fi
          else
            explain "fallback $_id: a line comes only from a box-tier mode: notify pack — summary: stands"
          fi ;;
      esac
    else
      _note="$(body "$_f")"
    fi
    # Collapse to one paragraph. A note arrives inside a JSON string; hard-wrapped
    # source lines read as broken prose once they land.
    _note="$(printf '%s' "$_note" | tr '\n' ' ' | tr -s ' ')"
    _note="${_note# }"; _note="${_note% }"
    if [ "${DECISION:-}" = deny ]; then
      # The reason travels in its own field, so it is not also appended as a note.
      DREASON="$(printf '%s' "$DREASON" | tr '\n' ' ' | tr -s ' ')"
      DREASON="${DREASON# }"; DREASON="${DREASON% }"
      if [ "$_once" != never ]; then remember "$_key"; fi
      log_rule deny "$_id"
      break
    fi
    # A held line needs a note the agent can read: tabs alone are none, and only the space collapse above has seen them (harbor#1485).
    if [ -n "$_row" ]; then case "$_note" in *[![:space:]]*) ;; *) _note='' ;; esac; fi
    if [ -z "$_note" ]; then
      explain "skip $_id: empty note"
      [ -z "$_row" ] || log_defect "$_id" no-note
      continue
    fi

    # A line waits for the sweep's verdict, so a later deny spends nothing (harbor#1485).
    if [ -n "$_row" ]; then
      if [ "$_cmode" = shadow ]; then explain "SHADOW $_id: recorded, not spoken"; else explain "FIRE $_id"; fi
      if [ -n "$H_ID" ]; then explain "skip $_id: $H_ID holds this sweep's line"; continue; fi
      H_ID="$_id"; H_ROW="$_row"; H_LINE="$_line"; H_NOTE="$_note"; H_KEY="$_key"; H_ONCE="$_once"; H_CMODE="$_cmode"; H_DIR="$_dir"
      fm_get spoke; H_SPOKE="$FMV"
      continue
    fi

    if [ "$_cmode" = shadow ]; then
      explain "SHADOW $_id: recorded, not spoken"
      log_rule shadow "$_id"
      if [ "$_once" != never ]; then remember "$_key"; fi
      continue
    fi

    explain "FIRE $_id"
    log_rule advise "$_id"
    # Each note names the rule that raised it, so an alert reaches its owner and off-switch in one
    # lookup (harbor#957): `<id>` is the front-matter id, which controls.tsv maps in its `emitted` column.
    NOTES="$NOTES[context:$_id] $_note "
    if [ "$_once" != never ]; then remember "$_key"; fi

    # `mode: notify` also speaks to the HUMAN (systemMessage): a line the operator reads never has to be believed by the model.
    fm_get mode
    if [ "$FMV" = notify ]; then
      fm_get summary; _um="$FMV"; [ -n "$_um" ] || _um="$_id"
      USERMSG="$USERMSG$_um; "
    fi
  done
done <<PACKS
$(sweep_files)
PACKS

# -- the held line (harbor#1485) --
# The claim and the once key sit together, just before the emit. The loser drops its note with its line: the note says the person was told.
if [ -n "$H_ID" ] && [ "${DECISION:-}" != deny ]; then
  if [ "$H_CMODE" = shadow ]; then
    if [ "$MODE" = hook ]; then log_rule shadow "$H_ID-$H_ROW"; fi
  elif claim_line; then
    if [ "$MODE" = hook ]; then log_rule advise "$H_ID-$H_ROW"; fi
    NOTES="$NOTES[context:$H_ID] $H_NOTE "
    USERMSG="$USERMSG$H_LINE; "
    SPOKEN=1
  else
    explain "skip $H_ID: this session's line is already spent"
  fi
  if [ "$H_ONCE" != never ]; then remember "$H_KEY"; fi
fi

# `spoke:` runs after a line really left, with the row id as its one argument, and fails silent. Same plain-filename check as `run:`.
# A watchdog bounds it: the hook has 10 s, and a timed-out hook loses the line already claimed. TERM first, so the stop tool frees its lock.
SPOKE_SECS=3
run_spoke() {
  [ "$SPOKEN" = 1 ] && [ -n "$H_SPOKE" ] || return 0
  case "$H_SPOKE" in /*|*..*) explain "skip spoke $H_ID: spoke: must be a plain filename beside the pack"; return 0 ;; esac
  if [ ! -f "$H_DIR/$H_SPOKE" ]; then explain "skip spoke $H_ID: $H_SPOKE not found in $H_DIR"; return 0; fi
  [ "$MODE" = hook ] || return 0
  ( cd "$REPO" 2>/dev/null && exec sh "$H_DIR/$H_SPOKE" "$H_ROW" ) </dev/null >/dev/null 2>&1 &
  _spk=$!
  ( sleep "$SPOKE_SECS"; kill -TERM "$_spk"; sleep 1; kill -KILL "$_spk" ) </dev/null >/dev/null 2>&1 &
  _dog=$!
  wait "$_spk" 2>/dev/null || :
  kill "$_dog" 2>/dev/null || :
}

NOTES="${NOTES% }"
# A deny with no other note is still an answer: its text rides in its own field, so NOTES is empty in exactly that case.
[ -n "$NOTES" ] || [ "${DECISION:-}" = deny ] || exit 0

# -- the emit, and which events can carry a note --
# additionalContext is accepted on the events below and REJECTED elsewhere, and a rejection discards the WHOLE object, notify systemMessage included.
# PreCompact accepts only the top-level `decision` pattern, so the post-compaction rule is SessionStart + `source-is compact`; lint IJ1 refuses a
# context-less event without `mode: notify`. The list was read off the harness's own schema (2.1.258); PostCompact is not in it.
# When it changes, this line and contracts/injection-rule.md's table change together.
case "$EVENT" in
  SessionStart|Setup|SubagentStart|UserPromptSubmit|UserPromptExpansion|PostModelSwitch|Notification|PreToolUse|PostToolUse|PostToolUseFailure|PostToolBatch|Stop|SubagentStop)
    _ctx=yes ;;
  *) _ctx=no ;;
esac

if [ "$_ctx" = no ]; then
  # No model-visible channel: tell the operator instead of emitting JSON the harness would discard.
  explain "event $EVENT carries no model-visible channel — operator note only"
  if [ -n "$USERMSG" ]; then
    jq -cn --arg m "harbor: ${USERMSG%; }" '{systemMessage:$m}' 2>/dev/null && run_spoke || true
  fi
  exit 0
fi

# A decision short-circuits the note; its reason travels as `permissionDecisionReason` (contracts/hooks.md).
if [ "${DECISION:-}" = deny ]; then
  jq -cn --arg e "$EVENT" --arg r "$STAMP $DREASON" \
    '{hookSpecificOutput:{hookEventName:$e,permissionDecision:"deny",permissionDecisionReason:$r}}' \
    2>/dev/null || true
  exit 0
fi

if [ -n "$USERMSG" ]; then
  jq -cn --arg e "$EVENT" --arg c "$STAMP $NOTES" --arg m "harbor: ${USERMSG%; }" \
    '{systemMessage:$m,hookSpecificOutput:{hookEventName:$e,additionalContext:$c}}' 2>/dev/null && run_spoke || true
else
  jq -cn --arg e "$EVENT" --arg c "$STAMP $NOTES" \
    '{hookSpecificOutput:{hookEventName:$e,additionalContext:$c}}' 2>/dev/null || true
fi
exit 0
