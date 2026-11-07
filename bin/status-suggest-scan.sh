#!/usr/bin/env sh
# status-suggest-scan.sh (harbor#1485) — repeated work in recent sessions that could become a skill, hook, job or mod.
#   sh bin/status-suggest-scan.sh --vocabulary        every step and kind the scan can print, as JSON; reads no session
#   sh bin/status-suggest-scan.sh --json [--days N] (--live | --dir PATH)
#                                     one JSON object on stdout:
#                                     {"schema":1,"days":14,"sessions":12,"candidates":[{"id","kind","shape","sessions","count"}]}
#                                     --days defaults to 14. At most 3 candidates, best first: more sessions, then more repeats, then a longer shape.
#                                     Read-only: it writes no file, not even into the suggest state folder.
#
# THE INPUT is the sequence of ALL tool calls of every session in the window, read in place from <config dir>/projects/*/*.jsonl
# (as bin/skill-catalog.sh usage does): built-in tools, file writes, web lookups and connectors, not Bash alone, because a person's
# repeated work often runs through a connector and leaves no shell trace. A call is reduced at read time to one token of a CLOSED
# vocabulary and nothing is copied from its arguments (the review's finding 28: a scrubber still lets a secret through; a closed
# vocabulary cannot):
#   Bash          "run <tool> [<subcommand>]" for a tool and subcommand on the lists in the jq program below, else "run a command" or
#                 "run a script"; flags, paths, URLs and every other word are dropped before anything leaves jq
#   Write, Edit  "write|edit <document|spreadsheet|slides|web page|data file|code|file>", from the extension class only
#   MCP           "connector update" for a known write verb anywhere in the tool's name, "connector report" when the name opens with a known
#                 read verb, and "use a connector" for a name that says neither (ad_performance, whoami): claiming a write would be false,
#                 and unknown is not read-only, so it cannot make a mod. "use the browser" for a browser driver;
#                 the server name is never kept
#   web           "search the web", "read a web page"
#   plumbing      Read, Grep, Glob, a Skill call, a todo, an agent hand-off and the like are not steps of a person's process: dropped
# A shape is 2 to 4 such tokens in order: "connector report, then write document". `kind` is derived from it: mod (decision 9: every
# step is a read-only lookup and they average at least 4 a session, so it is a thing to keep in view, not a task to run), skill (it
# touches a connector, the web, a document or the browser), hook (it edits code and then runs something), job (the rest).
#
# A CANDIDATE is a shape that appears in at least 3 distinct sessions and holds at least two steps that are more than plumbing (an
# edit of code, a bare `git status` and "run a command" are not), or an edit of code followed by a named tool. It is not a part of a
# longer shape that has the same sessions. Consecutive repeats of one token are one step. A tool call copied into a resumed session counts once (by its id); subagent calls are not read.
# Ids in <state folder>/stopped.tsv (first column) are dropped BEFORE the cap of 3, so a dismissed candidate never starves the rest.
# The id is a stable hash of the shape: 8 hex digits, the same id on every scan. State folder: ${HARBOR_STATUS_SUGGEST_DIR:-$HOME/.local/state/harbor/suggest}.
#
# Deterministic, no model call, and nothing derived from a transcript is written anywhere: the pipe is the whole data path.
# Exit 0 with the JSON; 1 with no JSON when the transcript store or jq is missing (unavailable is never a zero); 2 on bad usage.
# Removed notes: none yet.
set -eu

case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"; exit 0 ;;
esac
# C collation: sort order and string compares are the same on every box, so two runs over one store agree.
LC_ALL=C
export LC_ALL

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)" || HERE=''
[ -n "$HERE" ] && [ -f "$HERE/library-log.sh" ] && [ -f "$HERE/deploy-install-lib.sh" ] || { echo "status-suggest-scan: library-log.sh or deploy-install-lib.sh is missing beside $0" >&2; exit 1; }
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh. Stdout is the JSON; the log goes to stderr.
LOG_FD=2
. "$HERE/library-log.sh"; log_init status-suggest-scan
. "$HERE/deploy-install-lib.sh"
IL_LOG=0   # a read-only reporter keeps no run log: no file

JSON=0; DAYS=14
il_opt() {
  case "$1" in
    --json) JSON=1; IL_TAKE=1 ;;
    --days) il_value --days "${2-}"
            case "$2" in *[!0-9]*|0|0[0-9]*) il_usage_error "--days needs a whole number of days, 1 or more" ;; esac
            DAYS="$2"; IL_TAKE=2 ;;
    *) IL_TAKE=0 ;;
  esac
}
# --vocabulary names no target: it reads no session, so it leaves before the target is resolved.
VOCAB=0
if [ "${1:-}" = --vocabulary ]; then
  [ "$#" -eq 1 ] || il_usage_error "--vocabulary takes nothing else"
  VOCAB=1
else
  il_parse "$@"
  [ "$IL_APPLY" -eq 0 ] || il_usage_error "the scan is read-only: --apply writes nothing here"
  [ "$JSON" -eq 1 ] || il_usage_error "the scan needs --json"
  il_target
fi

command -v jq >/dev/null 2>&1 || { log_fail "jq is required"; log_fix "$(pkg_hint jq)"; log_end || :; exit 1; }
PROJ="${IL_TARGET:-}/projects"
[ "$VOCAB" -eq 1 ] || [ -d "$PROJ" ] || { log_fail "no transcript store at $PROJ, so no work can be scanned and this is not zero"; log_nofix "the header of bin/status-suggest-scan.sh"; log_end || :; exit 1; }

# The ids a person dismissed: read only, the first column of every line. The membership test below is a plain substring match
# on " id ", so a header, a comment or a malformed line matches nothing. The folder is a confinement write row and this runs outside the
# sandbox: a link there is not read, and only hex ids leave this awk, to be compared and never printed, so a raced read shows nothing.
STATE="${HARBOR_STATUS_SUGGEST_DIR:-$HOME/.local/state/harbor/suggest}"
STOPPED=' '
if [ ! -L "$STATE" ] && [ -f "$STATE/stopped.tsv" ] && [ ! -L "$STATE/stopped.tsv" ]; then
  STOPPED="$(awk -F'\t' '$1 ~ /^[0-9a-f]+$/ { printf " %s", $1 } END { printf " " }' "$STATE/stopped.tsv" 2>/dev/null || :)"
  [ -n "$STOPPED" ] || STOPPED=' '
fi

UGREP=/usr/bin/grep; [ -x "$UGREP" ] || UGREP=grep   # grep is ugrep on the operator's box and skips what git ignores
CUT="$(jq -n -r --argjson d "$DAYS" '(now - $d * 86400) | todate')"

# The reduction: one line in (`<file>:<record>` from grep -H), one line out per tool call, `session TAB line TAB index TAB id TAB epoch TAB token`.
# The session is the file's own name and stays inside this pipe. A "-" token is plumbing: it counts the session, it is not a step.
SCAN_JQ="$(cat <<'EOF'
def fix(f): . as $x | f | if . == $x then . else fix(f) end;
def ext_classes: [
  ["document", "md","markdown","txt","rst","docx","doc","pdf","rtf","odt"],
  ["spreadsheet", "xlsx","xls","csv","tsv","ods"],
  ["slides", "pptx","ppt","key","odp"],
  ["web page", "html","htm","css","svg"],
  ["data file", "json","yaml","yml","toml","xml","sql","ini","env"],
  ["code", "py","js","mjs","cjs","ts","tsx","jsx","sh","bash","zsh","rb","go","rs","java","kt","swift","php","c","h","cc","cpp","lua","r","pl","ps1"]];
def subcommand_tools: ["git","gh","harbor","npm","pnpm","yarn","docker","gcloud","cargo","go","kubectl","terraform","make","pip","uv","bun","cu"];
def subcommands: ["status","diff","log","add","commit","push","pull","checkout","switch","branch","merge","rebase","stash","fetch","clone","show","pr","issue","run","api","release","workflow","repo","auth","test","build","install","lint","start","dev","format","publish","compose","exec","logs","ps","query","ls","cp","deploy","check","doctor","verify","fresh","cite","observe","inject","event","ship","merge-stack","skills","chrome"];
def plain_tools: ["python","python3","node","npx","deno","curl","wget","jq","pytest","ruff","eslint","tsc","open","gsutil","rsync","scp","ssh","zip","unzip","pandoc","ffmpeg"];
# The whole closed vocabulary, from the lists the reduction itself reads: --vocabulary prints this.
def vocabulary:
  ["run a command", "run a script", "connector report", "connector update", "use a connector", "use the browser", "search the web", "read a web page"]
  + (subcommand_tools + plain_tools | map("run " + .))
  + [subcommand_tools[] as $w | subcommands[] | "run \($w) \(.)"]
  + [("write", "edit") as $v | ((ext_classes | map(.[0])) + ["file"])[] | "\($v) \(.)"];
def ext_class:
  (if type == "string" then ((capture("\\.(?<e>[A-Za-z0-9]{1,8})$")? // {e: ""}).e | ascii_downcase) else "" end) as $e
  | ([ext_classes[] | select(.[1:] | any(. == $e)) | .[0]][0] // "file");
def strip_head:
  sub("^\\s+"; "")
  | sub("^(cd\\s+(\"[^\"]*\"|'[^']*'|[^\\s;&|]+)\\s*(&&|;)\\s*|[A-Za-z_][A-Za-z0-9_]*=(\"[^\"]*\"|'[^']*'|[^\\s]*)\\s+|(sudo|time|nohup|command|exec|env|builtin|!)\\s+|\\(\\s*)"; "");
def bash_token:
  ((.input.command // "") | if type == "string" then .[0:400] else "" end | fix(strip_head)) as $c
  | ($c | capture("^(?<w>[A-Za-z0-9_.+-][A-Za-z0-9_./+-]*)(?<r>\\s.*)?$")? // {w: "", r: ""}) as $m
  | ($m.w | split("/") | last // "") as $w
  | (($m.r // "") | sub("^\\s+"; "") | fix(sub("^-\\S*\\s+"; ""))) as $r
  | (($r | capture("^(?<s>[a-z][a-z-]{1,14})(\\s|$)")? // {s: ""}).s) as $s
  | if $w == "" then "run a command"
    elif ($w | IN("sh","bash","zsh")) then "run a script"
    elif ($w | IN(subcommand_tools[])) then
      (if ($s | IN(subcommands[])) then "run \($w) \($s)" else "run \($w)" end)
    elif ($w | IN(plain_tools[])) then "run \($w)"
    else "run a command" end;
def mcp_token:
  (.name | split("__")) as $p
  | ($p[1] // "") as $srv
  | (($p[2:] // []) | join("_") | gsub("(?<a>[a-z0-9])(?<b>[A-Z])"; "\(.a)_\(.b)") | gsub("-"; "_") | ascii_downcase) as $t
  | if ($srv | test("chrome|browser|playwright|puppeteer|computer|devtools"; "i")) then "use the browser"
    elif ($t | test("(^|_)(create|update|send|write|delete|post|set|upload|insert|batch|reply|draft|move|merge|publish|comment|add|remove|edit|append|submit|import|run|execute|trigger|cancel|archive)(_|$)")) then "connector update"
    elif ($t | test("^(get|list|read|search|query|find|show|describe|fetch|view|lookup|retrieve)(_|$)")) then "connector report"
    else "use a connector" end;
def token:
  .name as $n
  | if $n == "Bash" then bash_token
    elif $n == "Write" then "write " + (.input.file_path | ext_class)
    elif ($n | IN("Edit","MultiEdit","NotebookEdit")) then "edit " + ((.input.file_path // .input.notebook_path) | ext_class)
    elif $n == "WebSearch" then "search the web"
    elif $n == "WebFetch" then "read a web page"
    elif (($n | type) == "string" and ($n | startswith("mcp__"))) then mcp_token
    else "-" end;
EOF
)"
if [ "$VOCAB" -eq 1 ]; then
  jq -n -c "$SCAN_JQ
    {schema: 1, steps: vocabulary, kinds: [\"mod\", \"skill\", \"hook\", \"job\"], most_steps: 4, joiner: \", then \"}"
  exit 0
fi
SCAN_JQ="$SCAN_JQ
$(cat <<'EOF'
split(".jsonl:{") as $p
| select(($p | length) > 1)
| ($p[0] | split("/") | last) as $f
| ("{" + ($p[1:] | join(".jsonl:{")) | fromjson? | select(type == "object" and .type == "assistant" and .isSidechain != true)) as $r
| ($r.timestamp // "") as $ts
| select($ts >= $cut)
| (try (($ts[0:19] + "Z") | fromdateiso8601) catch 0) as $e
| input_line_number as $n
| ($r.message.content? | arrays | to_entries[] | select(.value | type == "object" and .type == "tool_use")) as $c
| [$f, $n, $c.key, ($c.value.id // ""), $e, ($c.value | token)] | @tsv
EOF
)"

# The steps of an ordered, de-duplicated session become shapes. A gram counts once per session for `sessions` and every time for `count`.
SCAN_AWK="$(cat <<'EOF'
function weak(t) {
  return (t ~ /^(write|edit) (code|file|data file)$/ || t ~ /^run (a command|a script)$/ || t ~ /^run git( (status|diff|log|add|branch|show|stash|checkout|switch))?$/)
}
function flush(   i, j, l, key, strong) {
  if (n >= 2) {
    for (i = 1; i <= n; i++) strong[i] = !weak(seq[i])
    for (l = 2; l <= 4; l++) for (i = 1; i + l - 1 <= n; i++) {
      ok = 0; key = seq[i]
      for (j = i; j < i + l; j++) {
        if (strong[j]) ok++
        if (j > i) { key = key SEP seq[j]; if (strong[j] && seq[j] ~ /^run / && seq[j - 1] ~ /^(write|edit) code$/) ok = 2 }
      }
      if (ok < 2) continue
      cnt[key]++
      if (last[key] != cur) { last[key] = cur; sess[key]++ }
    }
  }
  n = 0
}
# A stable 8-hex id from the shape: no bit operators (BSD awk has none), only modular arithmetic.
function hid(s,   i, h, c, o, d) {
  h = 7
  for (i = 1; i <= length(s); i++) { c = index(CH, substr(s, i, 1)); h = (h * 131 + c) % 4294967291 }
  o = ""
  for (i = 0; i < 8; i++) { d = h % 16; o = substr("0123456789abcdef", d + 1, 1) o; h = (h - d) / 16 }
  return o
}
# Read-only by its own words: `gh pr` is out, because it may be `gh pr create`.
function lookup(t) { return (t == "connector report" || t == "read a web page" || t ~ /^run [a-z0-9]+ (status|log|logs|show|ps|ls|diff|doctor|verify)$/) }
function kind(key,   m, p, i, sk, hk, lk) {
  m = split(key, p, SEP); sk = 0; hk = 0; lk = 1
  for (i = 1; i <= m; i++) if (!lookup(p[i])) lk = 0
  if (lk && cnt[key] * m >= KEEP * sess[key]) return "mod"
  for (i = 1; i <= m; i++) {
    if (p[i] ~ /^(connector |use a connector|search the web|read a web page|use the browser|(write|edit) (document|spreadsheet|slides|web page))/) sk = 1
    if (p[i] ~ /^(write|edit) (code|file|data file)$/ && i < m && p[i + 1] ~ /^run /) hk = 1
  }
  return sk ? "skill" : (hk ? "hook" : "job")
}
function shape(key,   m, p, i, s) { m = split(key, p, SEP); s = p[1]; for (i = 2; i <= m; i++) s = s ", then " p[i]; return s }
function dropLast(k,   i, at) { for (i = length(k); i > 0; i--) if (substr(k, i, 1) == SEP) { at = i; break }; return substr(k, 1, at - 1) }
function better(a, b) { # is key a ranked above key b
  if (sess[a] != sess[b]) return sess[a] > sess[b]
  if (cnt[a] != cnt[b]) return cnt[a] > cnt[b]
  if (len[a] != len[b]) return len[a] > len[b]
  return a < b
}
BEGIN { FS = "\t"; SEP = "\034"; CH = " abcdefghijklmnopqrstuvwxyz,0123456789-"; cur = ""; n = 0; nsess = 0 }
{
  if ($4 != "") { if ($4 in seen) next; seen[$4] = 1 }
  if ($1 != cur) { flush(); cur = $1; nsess++ }
  if ($6 == "-") next
  if (n > 0 && seq[n] == $6) next
  seq[++n] = $6
}
END {
  flush()
  q = 0
  for (k in cnt) if (sess[k] >= MIN) { q++; qk[q] = k; len[k] = split(k, tmp, SEP) }
  for (i = 1; i <= q; i++) {   # a part of a longer shape with the same sessions is the longer shape
    k = qk[i]
    if (len[k] < 3) continue
    pre = dropLast(k)
    suf = substr(k, index(k, SEP) + 1)
    if ((pre in sess) && sess[pre] == sess[k]) dead[pre] = 1
    if ((suf in sess) && sess[suf] == sess[k]) dead[suf] = 1
  }
  top = 0
  for (i = 1; i <= q; i++) {
    k = qk[i]
    if (k in dead) continue
    if (index(STOPPED, " " hid(shape(k)) " ")) continue
    pos = top + 1
    while (pos > 1 && better(k, best[pos - 1])) { if (pos <= CAP) best[pos] = best[pos - 1]; pos-- }
    if (pos <= CAP) { best[pos] = k; if (top < CAP) top++ }
  }
  printf "S\t%d\n", nsess
  for (i = 1; i <= top; i++) { k = best[i]; s = shape(k); printf "C\t%s\t%s\t%s\t%d\t%d\n", hid(s), kind(k), s, sess[k], cnt[k] }
}
EOF
)"

export UGREP SCAN_JQ CUT
find "$PROJ" -mindepth 2 -maxdepth 2 -name '*.jsonl' -type f -mtime "-$DAYS" -print0 \
  | xargs -0 -n 20 -P 4 sh -c '[ "$#" -gt 0 ] || exit 0; "$UGREP" -H -F -e "\"type\":\"tool_use\"" "$@" | jq --unbuffered -R -r --arg cut "$CUT" "$SCAN_JQ"' sh 2>/dev/null \
  | sort -t "$(printf '\t')" -k1,1 -k2,2n -k3,3n -k4,4 \
  | awk -v MIN=3 -v CAP=3 -v KEEP=4 -v STOPPED="$STOPPED" "$SCAN_AWK" \
  | jq -R -s -c --argjson days "$DAYS" '
      split("\n") | map(select(. != "") | split("\t")) as $r
      | {schema: 1, days: $days,
         sessions: ([$r[] | select(.[0] == "S") | .[1] | tonumber][0] // 0),
         candidates: [$r[] | select(.[0] == "C") | {id: .[1], kind: .[2], shape: .[3], sessions: (.[4] | tonumber), count: (.[5] | tonumber)}]}'
