#!/usr/bin/env sh
# hub-tier.sh (harbor#1278) — what a fired rule means on a member laptop: the core default, then the hub, then the sets a hub cannot touch.
#   sh hub-tier.sh lookup <control-id>     one line: tier TAB set TAB label
#   sh hub-tier.sh rules <payload-file>    one line per matched hub rule: id TAB tier TAB target TAB label
#   sh hub-tier.sh mode                    shadow, enforce, or bad when the policy on disk can't be read
#   sh hub-tier.sh hooks                   one line per approved hub hook: pack TAB path TAB sha256
#
# Precedence: a risk-tiers.tsv row, else the control's mode (block very-high, warn high, shadow and off low); then a hub entry on a
# default row; then integrity and fixed, which no hub entry reaches. A hub entry on a fixed, integrity or unregistered row is refused
# here, at read time, and the rest of the policy stands. A hub entry for a row core has since removed names nothing, so it does nothing.
# Failure: policy files that none verify (hub-sync.sh check exits 1), a policy that won't read, or a hub-sync.sh that won't run make every default row very-high and
# mode say bad: a broken file must not drop a hub's raises (F20). No policy at all (check exits 2) reads the same on a marker box, which is joined, so what is missing
# could have raised any call; with no marker it is core defaults in enforce. Unreadable core lists make every row integrity. The sets are data here and in contracts/risk-tiers.tsv.
set -eu
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -- "$HERE" && pwd)"
. "$HERE/library-log.sh"
. "$HERE/library-hub.sh"
log_init hub-tier
LOG_FD=2
hub_env_clean

TAB="$(printf '\t')"
LABEL_DEFAULT='A sensitive action'
LABEL_INTEGRITY='Changing the safety settings on this laptop'
LABEL_UNREADABLE='The safety list could not be read'

# Installed copies sit beside this script; a checkout keeps them under contracts/ and standards/.
TIERS="$HERE/risk-tiers.tsv"; [ -f "$TIERS" ] || TIERS="$HERE/../contracts/risk-tiers.tsv"
CONTROLS="$HERE/controls.tsv"; [ -f "$CONTROLS" ] || CONTROLS="$HERE/../standards/naming/controls.tsv"
VOCAB="$HERE/hub-vocabulary.tsv"; [ -f "$VOCAB" ] || VOCAB="$HERE/../contracts/hub-vocabulary.tsv"

# The file is untrusted input to a hook that runs on every call, so everything this script uses is shape-checked at each read, control
# characters included: a label travels in a TAB-separated line.
JQ_POLICY_OK='
def tier: . == "very-high" or . == "high" or . == "medium" or . == "low";
def kebab: type == "string" and test("^[a-z0-9][a-z0-9.-]{0,63}$");
def clean($n): type == "string" and length >= 1 and length <= $n and (test("[[:cntrl:]]") | not);
def cond: type == "object" and ((keys - ["field","op","value"]) == [])
  and (.field | IN("command","file_path","url","query"))
  and (.op | IN("equals","prefix","suffix","contains","word"))
  and (.value | clean(200));
def rule: type == "object" and ((keys - ["id","label","tier","target","tools","when"]) == [])
  and (.id | kebab) and (.label | clean(60)) and (.tier | tier) and (.target as $t | $targets | split(" ") | index($t) != null)
  and (.tools | type == "array" and length > 0 and all(.[]; clean(200)))
  and (.when | type == "array" and length > 0 and all(.[]; cond));
def hook: type == "object" and (.pack | kebab) and (.sha256 | type == "string" and test("^[0-9a-f]{64}$"))
  and (.path | type == "string" and test("^[A-Za-z0-9._/-]+$") and (contains("..") | not) and (startswith("/") | not));
def ok: type == "object"
  and ((keys - ["schema","hub","serial","issued","core","rollout","approval","silent_days","tiers","rules","packs","hooks","revoked","support","hosts","logs","connectors"]) == [])
  and .schema == 1
  and (.rollout.mode | . == "shadow" or . == "enforce")
  and ((.tiers // {}) | type == "object" and all(.[]; tier))
  and ((.rules // []) | type == "array" and length <= 200 and all(.[]; rule))
  and ((.hooks // []) | type == "array" and all(.[]; hook))
  and ((.hosts // []) | type == "array" and all(.[]; type == "string"));
length == 1 and (.[0] | ok)'

# No policy value ever becomes a program or a pattern: the only regexes are the fixed ones here, and split/1 is a literal split.
JQ_MATCH='
def lc: ascii_downcase;
def wordch: test("^[a-z0-9_]$");
def bounded($v): split($v) as $p | [range(0; ($p | length) - 1)] | any(
    ($p[.] | length == 0 or (.[-1:] | wordch | not)) and ($p[. + 1] | length == 0 or (.[:1] | wordch | not)));
def hit($op; $v):
  if $op == "equals" then . == $v
  elif $op == "prefix" then startswith($v)
  elif $op == "suffix" then endswith($v)
  elif $op == "contains" then (split($v) | length) > 1
  elif $op == "word" then bounded($v)
  else false end;
$payload[0] as $call | ($call.tool_input // {}) as $in |
{ command: ((([$in.command] | map(strings)) + (($norm | split("\n")) | map(select(length > 0))))
            | map(., gsub("[[:space:]]+"; " "))),
  file_path: ([$in.file_path, $in.notebook_path] | map(strings)),
  url: ([$in.url] | map(strings)),
  query: ([$in.query] | map(strings)) } as $subjects |
(.rules // [])[]
| select(.tools | index($call.tool_name) != null)
| select(all(.when[]; . as $w | ($w.value | lc) as $v | any($subjects[$w.field][]; lc | hit($w.op; $v))))
| [.id, .tier, .target, .label] | join("\t")'

# load_policy: POLICY and PSTATE (none, good or bad). hub-sync.sh prints the last good file; what it printed is still re-read here.
load_policy() {
  POLICY=""; PSTATE=bad
  if [ ! -f "$HERE/hub-sync.sh" ]; then return 0; fi
  POLICY="$(sh "$HERE/hub-sync.sh" path 2>/dev/null)" || return 0
  if [ -z "$POLICY" ]; then
    # Nothing printed is "none verifies" as well as "none": only check tells them apart, and tampering must not read as no hub. Nor may a deleted one (harbor#1278).
    _crc=0; sh "$HERE/hub-sync.sh" check >/dev/null 2>&1 || _crc=$?
    if [ "$_crc" = 2 ] && ! hub_marker; then PSTATE=none; fi
    return 0
  fi
  _targets="$(awk -F'\t' '$1 == "target" { printf "%s ", $2 }' "$VOCAB" 2>/dev/null)" || _targets=""
  [ -n "$_targets" ] || return 0
  if jq -se --arg targets "$_targets" "$JQ_POLICY_OK" "$POLICY" >/dev/null 2>&1; then PSTATE=good; fi
  return 0
}

# integrity_rule <id> <emitted-cell>: 0 iff floor_shadow_enforces keeps this rule on. It matches the rule's emitted name, not its id.
integrity_rule() {
  . "$HERE/library-admission.sh"
  case "$2" in
    *:*) floor_shadow_enforces "${2%%:*}" "${2#*:}" ;;
    *) floor_shadow_enforces - "${1#*.}" ;;
  esac
}

lookup() { # <control-id>
  _id="$1"
  if [ ! -r "$TIERS" ] || [ ! -r "$CONTROLS" ]; then
    printf 'very-high\tintegrity\t%s\n' "$LABEL_UNREADABLE"; return 0
  fi
  case "$_id" in ''|*[!abcdefghijklmnopqrstuvwxyz0123456789.-]*) printf 'very-high\tdefault\t%s\n' "$LABEL_DEFAULT"; return 0 ;; esac
  _row="$(awk -F'\t' -v k="$_id" '/^#/ { next } $1 == k { print $2 "\t" $3 "\t" $4; exit }' "$TIERS")" || _row=""
  _reg="$(awk -F'\t' -v k="$_id" '/^#/ { next } $1 == k { print $2 "\t" $12; exit }' "$CONTROLS")" || _reg=""
  _mode="${_reg%%"$TAB"*}"; _emit="${_reg#*"$TAB"}"
  case "$_mode" in
    block) _tier=very-high ;;
    warn|advisory|inform) _tier=high ;;
    shadow|off) _tier=low ;;
    *) _tier=very-high ;;
  esac
  _set=default; _label="$LABEL_DEFAULT"
  if [ -n "$_row" ]; then
    _tier="${_row%%"$TAB"*}"; _rest="${_row#*"$TAB"}"; _set="${_rest%%"$TAB"*}"; _label="${_rest#*"$TAB"}"
  fi
  if integrity_rule "$_id" "$_emit"; then
    [ -n "$_row" ] || _label="$LABEL_INTEGRITY"
    _set=integrity
  fi
  case "$_set" in fixed|integrity) _tier=very-high ;; esac

  load_policy
  case "$PSTATE" in
    bad) [ "$_set" != default ] || _tier=very-high ;;
    good)
      _hub="$(jq -r --arg k "$_id" '(.tiers // {})[$k] // empty' "$POLICY")" || _hub=""
      if [ -n "$_hub" ]; then
        if [ "$_set" = default ] && [ -n "$_reg" ]; then _tier="$_hub"
        else printf 'hub-tier: refused: the hub may not move %s (%s)\n' "$_id" "$_set" >&2; fi
      fi ;;
  esac
  printf '%s\t%s\t%s\n' "$_tier" "$_set" "$_label"
}

rules() { # <payload-file>
  load_policy
  case "$PSTATE" in none) return 0 ;; bad) return 1 ;; esac
  [ "$(jq '(.rules // []) | length' "$POLICY")" -gt 0 ] || return 0
  _rt="$(mktemp "${TMPDIR:-/tmp}/hub-tier.XXXXXX")"
  trap 'rm -f "$_rt"' EXIT
  # The guards' own normaliser, so a quoted or wrapped spelling of a command matches as what will run.
  case "$(jq -r '.tool_name // ""' "$1")" in
    Bash|Monitor)
      . "$HERE/library-admission.sh"
      floor_bash_targets "$(jq -r '.tool_input.command // ""' "$1")" > "$_rt" ;;
  esac
  jq -r --slurpfile payload "$1" --rawfile norm "$_rt" "$JQ_MATCH" "$POLICY"
}

case "${1:-}" in
  -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  lookup)
    [ $# -eq 2 ] || { log_fail "lookup wants one control id"; log_nofix "sh $0 --help"; log_end || :; exit 2; }
    lookup "$2" ;;
  rules)
    { [ $# -eq 2 ] && [ -f "$2" ]; } || { log_fail "rules wants a payload file"; log_nofix "sh $0 --help"; log_end || :; exit 2; }
    rules "$2" ;;
  mode)
    load_policy
    case "$PSTATE" in
      none) printf 'enforce\n' ;;
      good) jq -r '.rollout.mode' "$POLICY" ;;
      *) printf 'bad\n' ;;
    esac ;;
  hooks)
    load_policy
    case "$PSTATE" in
      none) ;;
      good) jq -r '(.hooks // [])[] | [.pack, .path, .sha256] | join("\t")' "$POLICY" ;;
      *) exit 1 ;;
    esac ;;
  *) log_fail "unknown verb: ${1:-none}"; log_nofix "sh $0 --help"; log_end || :; exit 2 ;;
esac
exit 0
