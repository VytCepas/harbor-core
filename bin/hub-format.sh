#!/usr/bin/env sh
# hub-format.sh (harbor#1278) — checks a hub file against contracts/hub.md. Reads and reports; writes nothing.
#   sh hub-format.sh policy <file>     a policy.json
#   sh hub-format.sh event <file>      one event, or an array of events
#   sh hub-format.sh board <file>      a batch as a board comment holds it: events, with activity and session refused in clear
#   sh hub-format.sh manifest <file>   an extension.json
#   sh hub-format.sh tiers [file]      contracts/risk-tiers.tsv
# One line per finding on stderr. Exit 0 clean, 1 findings, 2 usage or an unreadable file.
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
VOCAB="$HERE/../contracts/hub-vocabulary.tsv"
[ -f "$VOCAB" ] || VOCAB="$HERE/hub-vocabulary.tsv"
UPTERM="$HERE/support-upterm.tsv"; [ -f "$UPTERM" ] || UPTERM="$HERE/../contracts/support-upterm.tsv"
LOG_FD=2; export LOG_FD
. "$HERE/library-log.sh"
log_init hub-format

usage() { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
vocab() { # the vocabulary as {set: [values]}
  grep -v '^#' "$VOCAB" | jq -R -s 'split("\n") | map(select(length > 0) | split("\t")) | .[1:]
    | group_by(.[0]) | map({key: .[0][0], value: map(.[1])}) | from_entries'
}
report() { # <findings as a JSON array>: print each, exit 1 if any
  _n="$(printf '%s' "$1" | jq 'length')"
  [ "$_n" -eq 0 ] && exit 0
  printf '%s' "$1" | jq -r '.[]' | while IFS= read -r _l; do log_fail "$_l"; done
  log_nofix "the format is contracts/hub.md"
  log_end || :
  exit 1
}

# shared jq: a value is a kebab id, a digest or a login, never free text
JQ_DEFS='
def kebab: type == "string" and test("^[a-z0-9][a-z0-9.-]{0,63}$");
def hex($n): type == "string" and test("^[0-9a-f]{" + ($n|tostring) + "}$");
def login: type == "string" and test("^[A-Za-z0-9][A-Za-z0-9-]{0,38}$");
def utc: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
def int: type == "number" and . == floor and . >= 0;
def closed($k): (keys - $k) | map("unknown key: " + .);
def need($k): ($k - keys) | map("missing key: " + .);
def ck($c; $m): if $c then [] else [$m] end;
# No control character: `$` also matches before a final newline, and one key line must stay one line of authorized_keys.
def oneline: type == "string" and (test("[[:cntrl:]]") | not);
def sshkey: oneline and test("^(ssh-ed25519|sk-ssh-ed25519@openssh\\.com|ecdsa-sha2-nistp(256|384|521)|sk-ecdsa-sha2-nistp256@openssh\\.com|ssh-rsa) AAAA[A-Za-z0-9+/]+={0,2}( [A-Za-z0-9@._-]{1,64})?$");
def hostkey: oneline and test("^(ssh-ed25519|ecdsa-sha2-nistp(256|384|521)|ssh-rsa) AAAA[A-Za-z0-9+/]+={0,2}$");
def relayurl: oneline and test("^(wss|ssh)://[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?(:[0-9]{1,5})?$");
# A host in sandbox.network.allowedDomains shape: one optional `*.` prefix, two labels or more, never a bare `*` (contracts/confinement-hosts.txt).
def hostrow: oneline and length <= 253 and test("^(\\*\\.)?[a-z0-9-]+(\\.[a-z0-9-]+)+$");
# covers($h): this row admits host $h, itself or through its `*.` prefix.
def covers($h): . as $r | $r == $h or (($r | startswith("*.")) and ($h | endswith($r[1:])));
# An age recipient, and an age file to an X25519 recipient as base64: the only shape the laptop id and its counts may take on the board.
def agerecipient: type == "string" and test("^age1[02-9ac-hj-np-z]{58}$");
def sealed: type == "string" and length <= 60000 and test("^YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0\\+IFgyNTUx[A-Za-z0-9+/]{100,}={0,2}$");
'

check_policy() {
  _pub="$(awk -F'\t' '$1 == "public-relay" { print $2; exit }' "$UPTERM" 2>/dev/null)" || _pub=''
  [ -n "$_pub" ] || { log_fail "no public-relay row in $UPTERM, so a policy naming it can't be refused"; log_nofix "contracts/support-upterm.tsv"; return 2; }
  jq --argjson v "$(vocab)" --arg pub "$_pub" "$JQ_DEFS"'
    def cword: type == "string" and length >= 1 and length <= 500 and (test("[[:cntrl:]]") | not) and (contains("${") | not);
    def nodots: ((split("/") | map(select(. == ".." or . == ".")) | length) == 0);
    def inf($n): type == "string" and startswith("/opt/company-mcp/" + $n + "/") and nodots;
    def banned: type == "string" and (IN("-e","-m","-c","-r","-p","--require","--import","--preload","--eval","--print") or test("^--(eval|require|import|preload|print)="));
    def plain: type == "string" and (contains("/") | not) and (startswith(".") | not) and (startswith("-") | not);
    def flagok: type == "string" and test("^--[A-Za-z0-9][A-Za-z0-9_-]*(=([^/.][^/]*)?)?$");
    def argok($n): inf($n) or plain or flagok;
    def bn: split("/") | last;
    def noway: IN("sh","bash","dash","zsh","ksh","ash","fish","csh","tcsh","bunx","deno");
    def interp: IN("bun","node","nodejs","python","python3") or test("^python3\\.[0-9]+$");
    def subcmd: IN("x","run","install","add","pm","create");
    def sysbin: (split("/") | .[:-1] | join("/")) | IN("/usr/bin","/usr/local/bin","/bin");
    def okcmd($c; $n): ($c | type == "array" and length >= 1 and length <= 16 and all(.[]; cword and (banned | not))
      and (.[0] | startswith("/") and nodots and ((bn | noway) | not))
      and (if (.[0] | bn | interp) then
             (.[0] | (sysbin or inf($n))) and (if (.[0] | bn) == "bun" then (.[1] == "--no-install") and (.[2] | inf($n)) and all(.[3:][]; argok($n) and ((subcmd) | not))
              else (.[1] | inf($n)) and all(.[2:][]; argok($n)) end)
           else (.[0] | inf($n)) and all(.[1:][]; argok($n)) end));
  . as $p
  | (if type == "object" and (.support | type) == "object" and (.support.relay | type) == "string"
     then .support.relay | sub("^[a-z]+://"; "") | sub(":[0-9]+$"; "") else "" end) as $relayhost
  | if type != "object" then ["policy is not an object"] else
    closed(["schema","hub","serial","issued","core","rollout","approval","silent_days","tiers","rules","packs","hooks","revoked","support","hosts","logs","connectors"])
    # connectors (harbor#1278, lane I): the MCP servers a colleague key may reach. bin/member-managed.sh composes them and re-checks every row.
    + (if $p | has("connectors") then
        ck(($p.connectors | type == "array" and length <= 20
            and all(.[]; type == "object" and ((keys - ["name","ref","env","service","command"]) | length == 0) and ((["name","ref","env","service","command"] - keys) | length == 0)
              and (.name | type == "string" and test("^[A-Za-z0-9_-]{1,48}$"))
              and (.ref | type == "string" and test("^[a-z0-9][a-z0-9._-]{0,63}$") and (test("^hub-") | not))
              and (.env | type == "string" and test("^[A-Z][A-Z0-9_]{0,63}$"))
              and (.service | oneline and length >= 1 and length <= 120)
              and okcmd(.command; .name)));
           "connectors: up to 20 rows of exactly name, ref (never hub-*), env, service and command (an absolute path first)")
        + ck(($p.connectors | type != "array") or ([$p.connectors[]? | .ref?] | length == (unique | length)); "connectors: a ref listed twice")
      else [] end)
    # logs (harbor#1278): the age key of the loader. Without it a laptop seals nothing and the logs get nothing from it.
    + (if $p | has("logs") then
        ($p.logs | if type != "object" then ["logs: not an object"] else closed(["recipient"]) + need(["recipient"]) end)
        + ck(($p.logs.recipient // 0) | agerecipient; "logs.recipient: not an age X25519 recipient (age1...)")
      else [] end)
    + need(["schema","hub","serial","issued","core","rollout","approval","silent_days"])
    + ck($p.schema == 1; "schema: only 1 is known")
    + ck(($p.hub // 0) | kebab; "hub: not a kebab id")
    + ck((($p.serial // 0) | int) and ($p.serial // 0) >= 1; "serial: not a whole number from 1")
    + ck(($p.issued // 0) | utc; "issued: not a UTC time")
    + ck(($p.core.commit // 0) | hex(40); "core.commit: not a 40-hex commit")
    + ck(($p.core.contract // -1) | int; "core.contract: not a whole number")
    + ck((($p.rollout.mode // "") as $m | $v.mode | index($m)) != null; "rollout.mode: not in the vocabulary")
    + ck(($p.approval.approvers | type == "array" and length > 0 and all(.[]; login)); "approval.approvers: needs logins")
    + ck((($p.approval.ttl_hours // 0) | int) and ($p.approval.ttl_hours // 0) >= 1 and ($p.approval.ttl_hours // 0) <= 168; "approval.ttl_hours: not 1 to 168")
    + ck((($p.silent_days // 0) | int) and ($p.silent_days // 0) >= 1 and ($p.silent_days // 0) <= 90; "silent_days: not 1 to 90")
    + (($p.tiers // {}) | to_entries | map(select((.value as $t | $v.tier | index($t)) == null) | "tiers." + .key + ": not a tier"))
    + ck((($p.rules // []) | length) <= 200; "rules: more than 200")
    + (($p.rules // []) | map(. as $r |
        closed(["id","label","tier","target","tools","when"]) + need(["id","label","tier","target","tools","when"])
        + ck(($r.id // 0) | kebab; "rule id: not a kebab id")
        + ck((($r.label // "") | type == "string" and length >= 1 and length <= 60); "rule " + ($r.id|tostring) + ": label not 1 to 60 characters")
        + ck((($r.tier // "") as $t | $v.tier | index($t)) != null; "rule " + ($r.id|tostring) + ": not a tier")
        + ck((($r.target // "") as $t | $v.target | index($t)) != null; "rule " + ($r.id|tostring) + ": not a target")
        + ck(($r.tools | type == "array" and length > 0 and all(.[]; type == "string")); "rule " + ($r.id|tostring) + ": tools")
        + ck(($r.when | type == "array" and length > 0); "rule " + ($r.id|tostring) + ": when is empty")
        + (($r.when // []) | map(. as $w |
            closed(["field","op","value"])
            + ck((["command","file_path","url","query"] | index($w.field // "")) != null; "rule " + ($r.id|tostring) + ": bad field")
            + ck((["equals","prefix","suffix","contains","word"] | index($w.op // "")) != null; "rule " + ($r.id|tostring) + ": bad op")
            + ck((($w.value // "") | type == "string" and length >= 1 and length <= 200); "rule " + ($r.id|tostring) + ": value not 1 to 200 characters")
          ) | add // [])
      ) | add // [])
    + ck((($p.rules // []) | map(.id) | length == (unique | length)); "rules: duplicate id")
    + (($p.packs // []) | map(ck((.id // 0) | kebab; "packs: bad id") + ck((.commit // 0) | hex(40); "packs: bad commit")) | add // [])
    + (($p.hooks // []) | map(ck((.pack // 0) | kebab; "hooks: bad pack") + ck((.sha256 // 0) | hex(64); "hooks: bad sha256") + ck(((.path // "") | type == "string" and test("^[A-Za-z0-9._/-]+$") and (contains("..") | not) and (test("^/|//|(^|/)\\.(/|$)") | not)); "hooks: bad path")) | add // [])
    + ck((($p.revoked // []) | type == "array" and all(.[]; login)); "revoked: needs logins")
    # Hosts the sandbox may reach beyond the core and member lists. Never one that admits a relay: the agent must not reach a session.
    + (if $p | has("hosts") then
        ck(($p.hosts | type == "array" and length <= 200 and all(.[]; hostrow)); "hosts: up to 200 host names, each with at most one leading *. and never a bare *")
        + ck(($p.hosts | type != "array" or (length == (unique | length))); "hosts: a host listed twice")
        + ck(($p.hosts | type != "array") or ([$p.hosts[] | select(type == "string") | select(covers($pub) or ($relayhost != "" and covers($relayhost)))] | length == 0);
             "hosts: a row admits a support relay, which stays denied")
      else [] end)
    + (if $p | has("support") then
        ($p.support) as $s
        | if ($s | type) != "object" then ["support: not an object"] else
            ($s | closed(["keys","relay","relay_key","max_minutes"]) + need(["keys"]))
            + ck(($s.keys | type == "array" and length >= 1 and length <= 20 and all(.[]; sshkey)); "support.keys: needs 1 to 20 plain public key lines, no options")
            + ck(($s.keys | type == "array" and (length == (unique | length))); "support.keys: a key listed twice")
            # The hub relay or none: no default, and never the public one, which reads the session and vouches for guests.
            + ck(($s | has("relay")) == ($s | has("relay_key")); "support.relay and support.relay_key come together, or neither (support stays off)")
            + (if $s | has("relay") then
                ck($s.relay | relayurl; "support.relay: not wss://host[:port] or ssh://host[:port]")
                + ck(($relayhost == $pub or ($relayhost | endswith("." + $pub))) | not; "support.relay: the public relay is never used; name the hub relay")
              else [] end)
            + (if $s | has("relay_key") then ck($s.relay_key | hostkey; "support.relay_key: not a plain host key") else [] end)
            + (if $s | has("max_minutes") then
                ck(($s.max_minutes | int) and $s.max_minutes >= 5 and $s.max_minutes <= 240; "support.max_minutes: not 5 to 240")
              else [] end)
          end
      else [] end)
  end' "$1"
}

check_event() {
  jq --argjson v "$(vocab)" "$JQ_DEFS"'
  def inset($s): . as $x | ($v[$s] | index($x)) != null;
  def shape($kind):
    {heartbeat: ["core","contract","floor","serial","mode","refusals","asks","requests","packs"],
     refusal: ["rule","tier","target","count"],
     ask: ["rule","tier","target","outcome","count"],
     request: ["id","rule","tier","target","outcome"],
     check: ["check","outcome"],
     token: ["days_left","outcome"],
     support: ["id","reason","outcome"],
     activity: ["tool","verb_class","verdict","count"],
     session: ["outcome","count"]}[$kind];
  def one:
    . as $e
    | if type != "object" then ["event is not an object"]
      elif (($e.kind // "") | inset("kind")) | not then ["kind: not in the vocabulary"]
      else shape($e.kind) as $k
        | closed(["v","kind","ts","member"] + $k + (if $e.kind == "heartbeat" then ["sealed"] else [] end)) + need(["v","kind","ts","member"] + $k)
        + (if $e | has("sealed") then ck($e.sealed | sealed; "sealed: not an age file to an X25519 key: the laptop id never travels in clear") else [] end)
        + ck($e.v == 1; "v: only 1 is known")
        + ck(($e.ts // 0) | utc and test("T[0-9]{2}:00:00Z$"); "ts: not coarsened to the hour")
        # D4: activity and session are counts per person per day, so their ts is the day
        + (if $e.kind == "activity" or $e.kind == "session" then ck(($e.ts // "") | test("T00:00:00Z$"); "ts: not coarsened to the day") else [] end)
        + (if $e.kind == "session" then ck($e.outcome == "started" or $e.outcome == "ended"; "outcome: a session is started or ended") else [] end)
        + (if $e | has("tool") then ck($e.tool | inset("tool"); "tool: not in the vocabulary") else [] end)
        + (if $e | has("verb_class") then ck($e.verb_class | inset("verb_class"); "verb_class: not in the vocabulary") else [] end)
        + (if $e | has("verdict") then ck($e.verdict | inset("verdict"); "verdict: not in the vocabulary") else [] end)
        + ck(($e.member // 0) | login; "member: not a login")
        + (if $e | has("rule") then ck($e.rule | kebab; "rule: not a kebab id") else [] end)
        + (if $e | has("check") then ck($e.check | kebab; "check: not a kebab id") else [] end)
        + (if $e | has("tier") then ck($e.tier | inset("tier"); "tier: not in the vocabulary") else [] end)
        + (if $e | has("target") then ck($e.target | inset("target"); "target: not in the vocabulary") else [] end)
        + (if $e | has("outcome") then ck($e.outcome | inset("outcome"); "outcome: not in the vocabulary") else [] end)
        + (if $e | has("mode") then ck($e.mode | inset("mode"); "mode: not in the vocabulary") else [] end)
        + (if $e | has("id") then ck($e.id | type == "string" and test(if $e.kind == "support" then "^s-[0-9a-f]{16}$" else "^r-[0-9a-f]{16}$" end); "id: not a request id") else [] end)
        + (if $e | has("reason") then ck($e.reason | inset("reason"); "reason: not in the vocabulary") else [] end)
        + (if $e | has("core") then ck($e.core | hex(12); "core: not 12 hex") else [] end)
        + (if $e | has("floor") then ck($e.floor | hex(16); "floor: not 16 hex") else [] end)
        + (if $e | has("packs") then ck($e.packs | type == "array" and all(.[]; kebab); "packs: not kebab ids") else [] end)
        + ([$e.contract, $e.serial, $e.refusals, $e.asks, $e.requests, $e.count, $e.days_left] | map(select(. != null)) | map(ck(int; "a count is not a whole number")) | add // [])
      end;
  if type == "array" then map(one) | add // [] else one end' "$1"
}

# check_board <file>: a comment's batch as the board may hold it. activity and session (D9) never travel in clear: colleagues would see
# each other's tool-call counts (legal/dpia.md R10). They ride inside the heartbeat's sealed field only.
check_board() {
  _cbe="$(check_event "$1")" || return 1
  jq --argjson ev "$_cbe" '$ev + ((if type == "array" then . else [.] end)
    | map(select(type == "object" and (.kind == "activity" or .kind == "session")))
    | if length > 0 then ["kind: activity and session travel sealed, never in clear on the board"] else [] end)' "$1"
}

check_manifest() {
  jq "$JQ_DEFS"'
  . as $x
  | closed(["schema","id","version","harbor_version","provides","files"])
  + need(["schema","id","version","harbor_version","provides","files"])
  + ck($x.schema == 1; "schema: only 1 is known")
  + ck(($x.id // 0) | kebab; "id: not a kebab id")
  + ck((($x.version // "") | type == "string" and test("^[0-9]+\\.[0-9]+(\\.[0-9]+)?$")); "version: not N.M or N.M.P")
  + ck((($x.harbor_version // "") | type == "string" and test("^(>=|<=|>|<|=)?[0-9]+(\\.[0-9]+)?(,(>=|<=|>|<|=)?[0-9]+(\\.[0-9]+)?)*$")); "harbor_version: not the pack grammar")
  + ck(($x.provides | type == "array" and length > 0 and all(.[]; . == "skill" or . == "hook" or . == "script" or . == "rule")); "provides: skill, hook, script or rule")
  + (($x.files // []) | map(ck(((.path // "") | type == "string" and test("^[A-Za-z0-9._/-]+$") and (contains("..") | not) and (test("^/|//|(^|/)\\.(/|$)") | not)); "files: bad path") + ck((.sha256 // 0) | hex(64); "files: bad sha256")) | add // [])' "$1"
}

check_tiers() {
  awk -F'\t' -v vocab="$VOCAB" '
    BEGIN { while ((getline l < vocab) > 0) { split(l, a, "\t"); if (a[1] == "tier") t[a[2]] = 1 } }
    /^#/ { next } $1 == "key" { next } NF == 0 { next }
    NF != 4 { print "row " NR ": not 4 columns"; bad = 1; next }
    !($2 in t) { print $1 ": tier " $2 " is not in the vocabulary"; bad = 1 }
    $3 != "fixed" && $3 != "integrity" && $3 != "default" { print $1 ": set " $3 " is not known"; bad = 1 }
    $3 == "fixed" && $2 != "very-high" { print $1 ": a fixed row must be very-high"; bad = 1 }
    length($4) < 1 || length($4) > 60 { print $1 ": label not 1 to 60 characters"; bad = 1 }
    seen[$1]++ { print $1 ": duplicate key"; bad = 1 }
    END { exit bad }' "$1" >&2
}

verb="${1:-}"; [ -n "$verb" ] || usage
case "$verb" in --help|-h) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
file="${2:-}"
[ "$verb" = tiers ] && [ -z "$file" ] && file="$HERE/../contracts/risk-tiers.tsv"
[ -n "$file" ] || usage
[ -r "$file" ] || { log_fail "cannot read $file"; log_nofix "name a readable file"; log_end || :; exit 2; }
case "$verb" in
  policy|event|board|manifest)
    jq -e . "$file" >/dev/null 2>&1 || { log_fail "$file is not JSON"; log_nofix "the format is contracts/hub.md"; log_end || :; exit 1; }
    # a check that crashes must not read as clean
    out="$("check_$verb" "$file")" || { log_fail "the $verb check failed to run"; log_nofix "the jq error is above"; log_end || :; exit 2; }
    report "$out" ;;
  tiers) check_tiers "$file" ;;
  *) usage ;;
esac
