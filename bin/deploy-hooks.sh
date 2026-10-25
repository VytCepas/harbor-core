#!/usr/bin/env sh
# deploy-hooks.sh (harbor#1272 step 5, D-88) — a config dir's settings.json hook wiring, RENDERED from the hook engines'
# manifests (hooks/<engine>/manifest.tsv), never kept by hand. It owns harbor's own entries and no other: an entry is an
# engine's when the script it runs is that engine's, under its name or an old name standards/naming/renames.tsv records.
#
#   sh bin/deploy-hooks.sh --engines [--root DIR]                  every engine script, one absolute path a line: hooks/<e>/<e>.sh,
#                                                                  manifest or not, never the tests beside it (the one definition)
#   sh bin/deploy-hooks.sh --check [--root DIR]                    every manifest is valid; exit 1 on the first doubt
#   sh bin/deploy-hooks.sh --plan <cfg> [options]                  one line per binding: wire, keep, prune, off, removed
#   sh bin/deploy-hooks.sh --settings <cfg> [options]              the new settings.json on stdout; nothing is written
#   sh bin/deploy-hooks.sh --record <cfg> [options]                after the caller wrote settings.json: remember what is wired
#
#   --root DIR                 the tree whose hooks/*/manifest.tsv are read (default: this script's repo)
#   --in FILE                  the settings.json to start from (default: <cfg>/settings.json; absent reads as {})
#   --matcher ENGINE:EVENT=M   the value of a manifest matcher written `@derived`; its payload's installer supplies it
#   --rewire ENGINE            wire an engine again that was removed by hand (it forgets the engine's record)
#   --installer NAME           only the engines whose manifest says `installer NAME`: each installer renders, records and
#                              prunes its own engines, and leaves the others' entries as they are
#
# FAIL CLOSED: a bad manifest, a `@derived` matcher nobody supplied, or a binding whose script is not deployed at
# <cfg>/bin/<engine>.sh prints FAIL lines and nothing on stdout, exit 1. Exit 2 is usage.
# DESIRED STATE (operator decision 2026-10-24): an engine whose entries already equal its bindings is left untouched;
# otherwise every entry of it goes and its bindings are appended, so a changed matcher never leaves a second copy.
# OFF (the same decision): <cfg>/<engine>.off unwires it, and a binding <cfg>/.harbor-hooks-wired says was
# wired before but is absent now was removed by hand and stays removed (harbor#362's ticket-note rule, for every engine).
set -eu
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -- "$HERE" && pwd)"; ROOT="$(CDPATH='' cd -- "$HERE/.." && pwd)"
LOG_FD=2
. "$HERE/log-lib.sh"
log_init deploy-hooks
usage() { log_fail "$1"; log_fix "sh $0 --plan ~/.claude"; log_end || :; exit 2; }
MODE=''; CFG=''; IN=''; MATCHERS=''; REWIRE=''; INSTALLER=''
case "${1:-}" in
  --check|--engines) MODE="${1#--}"; shift ;;
  --plan|--settings|--record) MODE="${1#--}"; [ $# -ge 2 ] || usage "$1 needs a config dir"; CFG="${2%/}"; shift 2 ;;
  -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) usage "a mode is required" ;;
esac
NL='
'
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || usage "--root needs a dir"; ROOT="${2%/}"; shift 2 ;;
    --in) [ $# -ge 2 ] || usage "--in needs a file"; IN="$2"; shift 2 ;;
    --matcher) [ $# -ge 2 ] || usage "--matcher needs ENGINE:EVENT=M"
      case "$2" in ?*:?*=?*) ;; *) usage "--matcher takes ENGINE:EVENT=M, not '$2'" ;; esac
      MATCHERS="$MATCHERS$2$NL"; shift 2 ;;
    --rewire) [ $# -ge 2 ] || usage "--rewire needs an engine"; REWIRE="$REWIRE$2$NL"; shift 2 ;;
    --installer) [ $# -ge 2 ] || usage "--installer needs a name"; INSTALLER="$2"; shift 2 ;;
    *) usage "unknown argument '$1'" ;;
  esac
done
if [ "$MODE" = engines ]; then
  for _ed in "$ROOT"/hooks/*/; do _en="${_ed%/}"; _en="${_en##*/}"; [ ! -f "$_ed$_en.sh" ] || printf '%s\n' "$_ed$_en.sh"; done
  exit 0
fi
command -v jq >/dev/null 2>&1 || { log_fail "jq is not installed"; log_fix "$(pkg_hint jq)"; log_end || :; exit 1; }
T="$(mktemp -d "${TMPDIR:-/tmp}/deploy-hooks.XXXXXX")"; trap 'rm -rf "$T"' EXIT
REC="$CFG/.harbor-hooks-wired"  # top level, so deploy's snapshot restores it with the settings.json it describes

# ── read and judge every manifest: $T/wires holds engine TAB event TAB matcher TAB timeout ────────────────────────────
# The events the harness accepts a command hook on (CONTRACTS/hooks.md); a misspelt event would be wired and never fire.
EVENTS=' PreToolUse PostToolUse PostToolUseFailure PostToolBatch PermissionRequest SessionStart SessionEnd Stop SubagentStart SubagentStop UserPromptSubmit UserPromptExpansion Notification PreCompact PostCompact InstructionsLoaded PostModelSwitch '
: > "$T/wires"; : > "$T/errors"; : > "$T/engines"; : > "$T/installers"
for _m in "$ROOT"/hooks/*/manifest.tsv; do
  [ -f "$_m" ] || continue
  _d="${_m%/manifest.tsv}"; _e="${_d##*/}"
  printf '%s\n' "$_e" >> "$T/engines"
  [ -f "$_d/$_e.sh" ] || printf '%s: no %s.sh beside the manifest (D-88: the file is named after its folder)\n' "$_m" "$_e" >> "$T/errors"
  awk -F'\t' -v OFS='\t' -v f="$_m" -v dir="$_e" -v ev="$EVENTS" -v W="$T/wires" -v E="$T/errors" -v I="$T/installers" '
    function bad(m) { print f ":" NR ": " m >> E }
    /^#/ || /^[[:space:]]*$/ { next }
    !hdr { hdr = 1; if ($1 != "key" || $2 != "value") bad("the first row is the header `key<TAB>value`"); next }
    $1 == "engine"   { n["engine"]++; if ($2 != dir) bad("engine `" $2 "` is not its folder `" dir "`"); next }
    $1 == "wire"     {
      if (NF != 4) { bad("a wire row is wire<TAB>event<TAB>matcher<TAB>timeout, not " NF " fields"); next }
      if (index(ev, " " $2 " ") == 0) bad("`" $2 "` is not a hook event the harness accepts")
      if ($3 == "") bad("an empty matcher is written `-`")
      if ($4 != "-" && ($4 !~ /^[0-9]+$/ || $4 + 0 < 1 || $4 + 0 > 600)) bad("timeout `" $4 "` is not - or 1..600 seconds")
      if (seen[$2 "\t" $3]++) bad("`" $2 "` `" $3 "` is bound twice")
      print dir, $2, $3, $4 >> W; w++; next }
    $1 == "installer" { n["installer"]++
      if ($2 !~ /^[a-z][a-z0-9-]*-install$/) bad("installer `" $2 "` is not an installer name (<what>-install)")
      print dir, $2 >> I; next }
    $1 == "senses" || $1 == "acts-on" || $1 == "findings" || $1 == "closer" {
      n[$1]++; if ($2 == "") bad("`" $1 "` is empty"); next }
    { bad("unknown key `" $1 "`") }
    END {
      if (!hdr) bad("the manifest is empty")
      split("engine installer senses acts-on findings closer", req, " ")
      for (i = 1; i <= 6; i++) if (n[req[i]] != 1) bad("`" req[i] "` must appear once, not " (n[req[i]] + 0) " times")
      if (!w) bad("no wire row: an engine bound to no event is not a hook")
    }' "$_m"
done
if [ ! -s "$T/engines" ]; then
  log_fail "no hooks/*/manifest.tsv under $ROOT"; log_fix "run from a tree that carries the hook engines (D-88)"; log_end || :; exit 1
fi
# ONE INSTALLER'S ENGINES: the others are not this run's to plan, record or prune, and their @derived matchers are not ours.
if [ -n "$INSTALLER" ] && [ ! -s "$T/errors" ]; then
  awk -F'\t' -v i="$INSTALLER" '$2 == i { print $1 }' "$T/installers" > "$T/engines"
  if [ ! -s "$T/engines" ]; then
    log_fail "no engine's manifest says installer $INSTALLER"; log_fix "grep -l '^installer' $ROOT/hooks/*/manifest.tsv"; log_end || :; exit 1
  fi
  awk -F'\t' 'NR == FNR { k[$1] = 1; next } $1 in k' "$T/engines" "$T/wires" > "$T/w1"; mv "$T/w1" "$T/wires"
fi
_errs() { # <fix> — every collected error, each with its fix, then stop
  while IFS= read -r _l; do log_fail "${_l#"$ROOT"/}"; log_fix "$1"; done < "$T/errors"; log_end || :; exit 1
}
[ ! -s "$T/errors" ] || _errs "correct the manifest; its format is in hooks/README.md"
# --check judges the manifests; a @derived matcher is a valid manifest value, supplied by its installer at render time.
if [ "$MODE" = check ]; then
  log_ok "$(wc -l < "$T/engines" | tr -d ' ') engine(s), $(wc -l < "$T/wires" | tr -d ' ') binding(s), every manifest valid"
  log_end; exit $?
fi
# A `@derived` matcher is a value the payload's installer computes (inject-install derives the injection rule's from its
# packs). Substituted here, or refused: an empty matcher would be wired as "every tool", which nobody asked for.
: > "$T/w2"
while IFS="$(printf '\t')" read -r _e _ev _mt _to; do
  if [ "$_mt" = '@derived' ]; then
    _v="$(printf '%s' "$MATCHERS" | awk -v k="$_e:$_ev" 'index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }')"
    if [ -z "$_v" ]; then printf '%s %s: the matcher is @derived and no --matcher %s:%s=… was given\n' "$_e" "$_ev" "$_e" "$_ev" >> "$T/errors"; continue; fi
    _mt="$_v"
  fi
  printf '%s\t%s\t%s\t%s\n' "$_e" "$_ev" "$_mt" "$_to" >> "$T/w2"
done < "$T/wires"
mv "$T/w2" "$T/wires"
[ ! -s "$T/errors" ] || _errs "run the engine's installer, which derives the matcher, or pass --matcher ENGINE:EVENT=M"

# ── the names each engine answers to: its own and every old name renames.tsv moved to hooks/<engine>/<engine>.sh ──────
awk -F'\t' 'NR == FNR { e[$1] = 1; next } !/^#/ && $3 ~ /^hooks\/[^\/]+\/[^\/]+\.sh$/ {
    split($3, p, "/"); if ((p[2] in e) && p[3] == p[2] ".sh") { n = $2; sub(/.*\//, "", n); print p[2] "\t" n } }' \
  "$T/engines" "$ROOT/standards/naming/renames.tsv" 2>/dev/null > "$T/names" || :
while IFS= read -r _e; do printf '%s\t%s.sh\n' "$_e" "$_e"; done < "$T/engines" >> "$T/names"

# ── the starting settings and the record ────────────────────────────────────────────────────────────────────────────
[ -n "$IN" ] || IN="$CFG/settings.json"
if [ -f "$IN" ]; then
  jq -e 'type == "object"' "$IN" >/dev/null 2>&1 || { log_fail "$IN is not a JSON object"; log_nofix "$IN"; log_end || :; exit 1; }
  cp "$IN" "$T/in.json"
else printf '{}' > "$T/in.json"; fi
# Every binding of an engine that is wired now, by the script it runs: engine TAB event TAB matcher TAB timeout TAB command.
jq -r --rawfile names "$T/names" '
  ($names | split("\n") | map(select(length > 0) | split("\t") | {key: .[1], value: .[0]}) | from_entries) as $own
  | (.hooks // {}) | to_entries[] | .key as $ev | .value[]? | (.matcher // "") as $m | .hooks[]?
  | ((.command // "") | gsub("\""; "") | split(" ") | map(select(test("\\.(sh|py)$"))) | .[0] // "" | sub(".*/"; "")) as $s
  | select($own[$s] != null)
  | [$own[$s], $ev, (if $m == "" then "-" else $m end), ((.timeout // "-") | tostring), .command] | @tsv' "$T/in.json" > "$T/now"
if [ -f "$REC" ]; then cp "$REC" "$T/rec"
elif { [ -n "$INSTALLER" ] && grep -q "^$INSTALLER " "$CFG/.helm-install-stamp" 2>/dev/null; } \
  || { [ -z "$INSTALLER" ] && [ -s "$CFG/.helm-install-stamp" ]; }; then
  # NO RECORD YET ON A BOX THIS INSTALLER ALREADY INSTALLED: every binding counts as wired before, so one an operator
  # took out by hand under the installers' append-only merge stays out on the first render too (harbor#362). Another
  # installer's stamp proves nothing about these engines: floor-install first, then runtime-install, wires them all.
  cut -f1-3 "$T/wires" > "$T/rec"
else : > "$T/rec"; fi

# The command an engine is wired with. Quoted only when the path needs it: the harness runs it through a shell, so a
# config dir with a space would be word-split (inject-install's measured failure), and an unquoted plain path keeps a
# box that already runs it byte-identical.
_cmd() { case "$CFG/bin/$1.sh" in *[!A-Za-z0-9_./:@%+,=-]*) printf '/bin/sh "%s"' "$CFG/bin/$1.sh" ;; *) printf '/bin/sh %s' "$CFG/bin/$1.sh" ;; esac; }
case "$CFG" in *[\\\"\$\`]*) log_fail "$CFG holds a backslash, double quote, dollar or backtick, which a double-quoted command cannot carry"; log_nofix "a config dir without them"; log_end || :; exit 1 ;; esac
while IFS= read -r _e; do printf '%s\t%s\n' "$_e" "$(_cmd "$_e")"; done < "$T/engines" > "$T/cmds"

# ── decide each binding ─────────────────────────────────────────────────────────────────────────────────────────────
# One line per binding: verdict TAB engine TAB event TAB matcher TAB timeout. An engine is left alone (`keep`) only when
# the set it has wired equals the set it wants, as sets; any difference re-renders the whole engine (`wire` + `prune`).
: > "$T/off"
while IFS= read -r _e; do [ ! -e "$CFG/$_e.off" ] || printf '%s\n' "$_e" >> "$T/off"; done < "$T/engines"
# --rewire forgets an engine's record, so a binding removed by hand is wired again.
printf '%s' "$REWIRE" > "$T/rewire"
awk -F'\t' 'FILENAME == ARGV[1] { f[$0] = 1; next } !($1 in f)' "$T/rewire" "$T/rec" > "$T/rec2"
awk -F'\t' -v OFS='\t' '
  FILENAME == ARGV[1] { off[$1] = 1; next }
  FILENAME == ARGV[2] { rec[$1 "\t" $2 "\t" $3] = 1; next }
  FILENAME == ARGV[3] { k = $1 "\t" $2 "\t" $3; nowk[k] = 1; next }
  { k = $1 "\t" $2 "\t" $3
    print (($1 in off) ? "off" : ((k in rec) && !(k in nowk)) ? "removed" : "want"), $0 }' \
  "$T/off" "$T/rec2" "$T/now" "$T/wires" > "$T/verdicts"
: > "$T/plan"
while IFS= read -r _e; do
  # Equal means the same command too: an entry under an old name or path is re-rendered, never kept.
  awk -F'\t' -v OFS='\t' -v e="$_e" -v c="$(_cmd "$_e")" '$1 == "want" && $2 == e { print $2, $3, $4, $5, c }' "$T/verdicts" | sort > "$T/want.e"
  awk -F'\t' -v e="$_e" '$1 == e' "$T/now" | sort > "$T/now.e"
  if cmp -s "$T/want.e" "$T/now.e"; then _v=keep; else _v=wire; awk '{ print "prune\t" $0 }' "$T/now.e" >> "$T/plan"; fi
  awk -F'\t' -v OFS='\t' -v e="$_e" -v v="$_v" '$2 == e { if ($1 == "want") $1 = v; print }' "$T/verdicts" >> "$T/plan"
done < "$T/engines"

case "$MODE" in
  plan)
    cat "$T/plan"
    log_ok "$(grep -c '^keep' "$T/plan" || :) keep, $(grep -c '^wire' "$T/plan" || :) wire, $(grep -c '^prune' "$T/plan" || :) prune, $(grep -c '^off' "$T/plan" || :) off, $(grep -c '^removed' "$T/plan" || :) removed by hand"
    log_end; exit $? ;;
esac

# Nothing is wired to a script the config dir does not hold: that is the dangling command an upgrade must never leave.
awk -F'\t' '$1 == "wire" || $1 == "keep" { print $2 }' "$T/plan" | sort -u > "$T/live-engines"
while IFS= read -r _e; do
  [ -f "$CFG/bin/$_e.sh" ] || printf '%s is to be wired but %s/bin/%s.sh is not deployed\n' "$_e" "$CFG" "$_e" >> "$T/errors"
done < "$T/live-engines"
if [ -s "$T/errors" ]; then
  while IFS= read -r _l; do log_fail "$_l"; done < "$T/errors"
  log_fix "deploy the engine's files before its wiring"; log_end || :; exit 1
fi

if [ "$MODE" = record ]; then
  mkdir -p "${REC%/*}"
  # An engine switched off is forgotten, so deleting its .off wires it again rather than reading as removed by hand.
  { awk -F'\t' 'FILENAME == ARGV[1] { off[$1] = 1; next } !($1 in off)' "$T/off" "$T/rec2"
    awk -F'\t' -v OFS='\t' '$1 == "keep" { print $2, $3, $4 }' "$T/plan"; } | sort -u > "$T/rec.new"
  mv "$T/rec.new" "$REC"
  log_ok "recorded $(wc -l < "$REC" | tr -d ' ') wired binding(s) in $REC"
  log_end; exit $?
fi

# ── settings: drop every entry of a re-rendered or unwired engine, then append its wanted bindings ─────────────────────
awk -F'\t' '$1 == "wire" || $1 == "prune" { print $2 }' "$T/plan" | sort -u > "$T/redo"
awk -F'\t' -v OFS='\t' 'NR == FNR { c[$1] = $2; next } $1 == "wire" { print $2, $3, $4, $5, c[$2] }' "$T/cmds" "$T/plan" > "$T/add"
jq --rawfile names "$T/names" --rawfile redo "$T/redo" --rawfile add "$T/add" --arg cfg "$CFG" '
  def script: (.command // "") | gsub("\""; "") | split(" ") | map(select(test("\\.(sh|py)$"))) | .[0] // "" | sub(".*/"; "");
  ($names | split("\n") | map(select(length > 0) | split("\t") | {key: .[1], value: .[0]}) | from_entries) as $own
  | ($redo | split("\n") | map(select(length > 0)) | map({key: ., value: true}) | from_entries) as $drop
  | .hooks //= {}
  | .hooks |= with_entries(.value |= (map(.hooks |= map(select(($own[script] // "") as $e | ($drop[$e] // false) | not)))
                                     | map(select((.hooks | length) > 0))))
  | reduce ($add | split("\n")[] | select(length > 0) | split("\t")) as $b (.;
      .hooks[$b[1]] = ((.hooks[$b[1]] // []) + [{matcher: (if $b[2] == "-" then "" else $b[2] end),
        hooks: [{type: "command", command: $b[4]}
                + (if $b[3] == "-" then {} else {timeout: ($b[3] | tonumber)} end)]}]))
  | .hooks |= with_entries(select((.value | length) > 0))' "$T/in.json"
log_end
