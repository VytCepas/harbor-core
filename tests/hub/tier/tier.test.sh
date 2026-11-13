#!/usr/bin/env sh
# tier.test.sh (harbor#1278, F18, F19, F20) — hub-tier.sh: core defaults from the lists, a hub merge that can't touch fixed or integrity, a stricter result on any
# policy failure, and a matcher that treats policy as data.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/hub/fixtures/member-root.sh"
TIER="$MB/hub-tier.sh"; TAB="$(printf '\t')"
lk() { sh "$TIER" lookup "$1" 2>/dev/null | cut -f1,2 | tr '\t' ' '; }
pay() { jq -cn --arg t "$1" --argjson i "$2" '{tool_name:$t,tool_input:$i}' > "$T_TMP/p.json"; }
ruled() { sh "$TIER" rules "$T_TMP/p.json" 2>/dev/null | cut -f1 | tr '\n' ' '; }
when() { # <field> <op> <value>: one rule on Bash and Write
  m_enforce "$(jq -cn --arg f "$1" --arg o "$2" --arg v "$3" '[{id:"r",label:"L",tier:"high",target:"other",tools:["Bash","Write","WebFetch","WebSearch"],when:[{field:$f,op:$o,value:$v}]}]' | sed 's/^/.rules = /')"
}
cmd() { pay Bash "$(jq -cn --arg c "$1" '{command:$c}')"; }

t_section "1 - core defaults"
m_reset; m_enforce
t_eq "a fixed row" "very-high fixed" "$(lk admission.key-material-egress)"
t_has "with its label" "$(sh "$TIER" lookup admission.keychain-dump)" "Reading the keychain"
t_eq "an unlisted block row is very-high" "very-high default" "$(lk admission.dd-to-device)"
t_eq "a warn row is high" "high default" "$(lk admission.git-reset-hard)"
t_eq "an unknown control fails strict" "very-high default" "$(lk admission.no-such-rule)"
t_eq "a malformed id fails strict" "very-high default" "$(lk 'admission.$(touch x)')"
awk -F'\t' 'BEGIN { OFS = "\t" } $1 == "admission.dd-to-device" { $2 = "shadow" } $1 == "admission.mkfs-device" { $2 = "off" } { print }' "$MB/controls.tsv" > "$T_TMP/c" && cp "$T_TMP/c" "$MB/controls.tsv"
t_eq "a shadow row runs" "low default" "$(lk admission.dd-to-device)"
t_eq "an off row runs" "low default" "$(lk admission.mkfs-device)"
cp "$T_ROOT/standards/naming/controls.tsv" "$MB/controls.tsv"
printf 'admission.dd-to-device\tmedium\tdefault\tWriting to a disk\n' >> "$MB/risk-tiers.tsv"
t_eq "a listed default row beats its mode" "medium default" "$(lk admission.dd-to-device)"
cp "$T_ROOT/contracts/risk-tiers.tsv" "$MB/risk-tiers.tsv"

t_section "2 - integrity is derived from floor_shadow_enforces, by emitted name"
t_eq "a cfg rule whose id says config" "very-high integrity" "$(lk admission.cd-config-then-fetch)"
t_eq "a surface rule" "very-high integrity" "$(lk admission.redirect-baseline-surface)"
t_eq "a kill-switch rule" "very-high integrity" "$(lk admission.killswitch-assign)"
t_eq "every selfedit row" "very-high integrity" "$(lk admission.switch-in-settings)"
t_eq "not a neighbour" "very-high default" "$(lk admission.force-push)"
_miss=""
for _r in $(awk -F'\t' '/^#/ { next } $3 == "admission" && $12 ~ /:/ { print $1 "\t" $12 }' "$MB/controls.tsv" | tr '\t' '|'); do
  _id="${_r%|*}"; _em="${_r#*|}"
  _want="$(cd "$MB" && (. ./library-admission.sh; floor_shadow_enforces "${_em%%:*}" "${_em#*:}" && echo integrity || echo other))"
  case "$_want:$(lk "$_id")" in integrity:*integrity|other:*fixed|other:*default) ;; *) _miss="$_miss $_id" ;; esac
done
t_eq "the whole register agrees with the function" "" "$_miss"

t_section "3 - the lists hold (F18)"
t_exit "risk-tiers.tsv passes its format" 0 sh "$T_ROOT/bin/hub-format.sh" tiers "$T_ROOT/contracts/risk-tiers.tsv"
_orph="$(awk -F'\t' 'NR == FNR { if ($0 !~ /^#/) c[$1] = 1; next } /^#/ || $1 == "key" { next } !($1 in c) { print $1 }' "$T_ROOT/standards/naming/controls.tsv" "$T_ROOT/contracts/risk-tiers.tsv")"
t_eq "every key is a control id" "" "$_orph"

t_section "3b - every control of the egress guard is fixed, or named here with a reason (harbor#1278)"
# id<TAB>reason, one per line. Empty on purpose: each of these rules concerns a credential leaving the machine or entering the transcript.
NOT_FIXED=''
_eg="$(awk -F'\t' '/^#/ { next } $12 ~ /^egress:/ { print $1 }' "$T_ROOT/standards/naming/controls.tsv")"
t_eq "CONTROL: the register names the guard's controls" 1 "$([ "$(printf '%s\n' "$_eg" | wc -l)" -ge 17 ] && echo 1)"
_fired="$(sed -nE 's/.*[[:space:]]([a-z0-9-]+)\.(path|channel|argv|content)$/\1/p' "$T_ROOT/bin/admission-egress.sh" | sort -u)"
t_eq "CONTROL: the rules were read from the guard" 1 "$([ "$(printf '%s\n' "$_fired" | wc -l)" -ge 15 ] && echo 1)"
_unreg=''
for _r in $_fired; do
  printf '%s\n' "$_eg" | grep -qx "admission.$_r" || _unreg="$_unreg $_r"
done
t_eq "every rule the guard fires is in that set" '' "$_unreg"
m_reset; m_enforce ".tiers = $(printf '%s\n' "$_eg" | jq -Rnc '[inputs | {key: ., value: "low"}] | from_entries')"
for _c in $_eg; do
  if printf '%s\n' "$NOT_FIXED" | grep -q "^$_c$TAB."; then continue; fi
  t_eq "$_c stays fixed, with the hub lowering all of them" "very-high fixed" "$(lk "$_c")"
done
printf '%s\n' "$NOT_FIXED" | while IFS="$TAB" read -r _c _why; do
  [ -n "$_c" ] || continue
  printf '%s\n' "$_eg" | grep -qx "$_c" || echo "NOT_FIXED names $_c, which isn't the guard's"
  [ -n "$_why" ] || echo "NOT_FIXED gives no reason for $_c"
  [ "$(lk "$_c")" != "very-high fixed" ] || echo "NOT_FIXED names $_c, which is fixed"
done > "$T_TMP/stale"
t_eq "the exclusions are live and carry a reason" '' "$(cat "$T_TMP/stale")"
m_reset; m_enforce '.tiers = {"admission.git-push-snapshots":"low"}'
t_eq "and the one judgment call outside that guard: a push of local snapshots" "very-high fixed" "$(lk admission.git-push-snapshots)"

t_section "4 - the hub merge"
m_reset; m_enforce '.tiers = {"admission.dd-to-device":"high","admission.git-reset-hard":"very-high"}'
t_eq "a hub lowers a default row" "high default" "$(lk admission.dd-to-device)"
t_eq "a hub raises a default row" "very-high default" "$(lk admission.git-reset-hard)"
m_reset; m_enforce '.tiers = {"admission.key-material-egress":"low","admission.killswitch-assign":"low","admission.no-such-rule":"low","admission.dd-to-device":"high"}'
t_eq "a hub lowering a fixed row is refused" "very-high fixed" "$(lk admission.key-material-egress)"
t_has "...and says so" "$(sh "$TIER" lookup admission.key-material-egress 2>&1 >/dev/null)" "refused"
t_eq "a hub lowering an integrity row is refused" "very-high integrity" "$(lk admission.killswitch-assign)"
t_eq "an entry for no control names nothing" "very-high default" "$(lk admission.no-such-rule)"
t_eq "the rest of the policy stands" "high default" "$(lk admission.dd-to-device)"
m_reset; m_enforce '.hosts = ["intranet.example.com"] | .tiers = {"admission.dd-to-device":"high"}'
t_eq "a policy that widens the network is still read" enforce "$(sh "$TIER" mode)"
t_eq "...and its tiers apply" "high default" "$(lk admission.dd-to-device)"
m_reset; m_enforce '.logs = {recipient: "age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq"}'
t_eq "a policy that names the logs loader (harbor#1278) is still read: its key is one the floor knows" enforce "$(sh "$TIER" mode)"
m_reset; m_enforce '.connectors = [{name:"acme",ref:"acme-crm",env:"ACME_API_KEY",service:"Acme CRM",command:["/opt/company-mcp/acme/server"]}]'
t_eq "a policy that declares connectors (harbor#1278) is still read: a key the tier does not know made every call deny" enforce "$(sh "$TIER" mode)"

t_section "5 - policy failure: stricter, never lower (F20)"
_bad() { # <label>: a hub-lowered row reads very-high and mode says bad
  t_eq "$1: a default row is very-high" "very-high default" "$(lk admission.git-reset-hard)"
  t_eq "$1: fixed holds" "very-high fixed" "$(lk admission.keychain-dump)"
  t_eq "$1: mode" bad "$(sh "$TIER" mode)"
  t_exit "$1: rules refuses" 1 sh "$TIER" rules "$T_TMP/p.json"
  t_exit "$1: hooks refuses" 1 sh "$TIER" hooks
}
cmd ls
m_reset; printf '%s\n' "$T_TMP/gone.json" > "$MB/stub-policy"; _bad "a named file that's missing"
m_reset; printf '%s\n' "$T_TMP/g.json" > "$MB/stub-policy"; printf '{"schema":1' > "$T_TMP/g.json"; _bad "corrupt JSON"
m_reset; m_policy '. , .'; _bad "two documents"
m_reset; m_policy '.schema = 2'; _bad "a newer schema"
m_reset; m_policy '. + {extra:1}'; _bad "an unknown key"
m_reset; m_policy '.hosts = "intranet.example.com"'; _bad "network hosts that aren't a list"
m_reset; m_policy '.rollout.mode = "off"'; _bad "an unknown mode"
m_reset; m_policy '.tiers = {"admission.git-reset-hard":"none"}'; _bad "a tier outside the vocabulary"
m_reset; m_policy '.rules[0].when[0].op = "regex"'; _bad "a regex op"
m_reset; m_policy '.rules[0].label = "a\tb"'; _bad "a tab in a label"
m_reset; m_policy '.rules[0].target = "client-list"'; _bad "a target outside the vocabulary"
m_reset; m_policy '.hooks = [{pack:"a",path:"../../x",sha256:("0"*64)}]'; _bad "a hook path out of its pack"
m_reset; mv "$MB/hub-sync.sh" "$MB/sync.away"; _bad "no hub-sync.sh"; mv "$MB/sync.away" "$MB/hub-sync.sh"
m_reset; printf '#!/bin/sh\nexit 1\n' > "$T_TMP/s"; cp "$MB/hub-sync.sh" "$T_TMP/s.keep"; cp "$T_TMP/s" "$MB/hub-sync.sh"; _bad "a failing hub-sync.sh"; cp "$T_TMP/s.keep" "$MB/hub-sync.sh"
m_reset; echo 1 > "$MB/stub-check"; _bad "policy files that none verify"
m_reset; echo 7 > "$MB/stub-check"; _bad "a check that answers nothing known"
m_reset; _bad "a marker box, joined, with no policy on disk"
mv "$MB/harbor-member-mode" "$T_TMP/marker"
t_eq "no marker and no policy: core defaults" "high default" "$(lk admission.git-reset-hard)"
t_eq "...in enforce" enforce "$(sh "$TIER" mode)"
t_exit "...with no rules" 0 sh "$TIER" rules "$T_TMP/p.json"
mv "$T_TMP/marker" "$MB/harbor-member-mode"
m_enforce; mv "$MB/hub-vocabulary.tsv" "$T_TMP/vb"
t_eq "the flat copy is what's read: gone, and no checkout beside it, the policy is bad" bad "$(sh "$TIER" mode)"
mv "$T_TMP/vb" "$MB/hub-vocabulary.tsv"; m_reset
mv "$MB/risk-tiers.tsv" "$T_TMP/rt"
t_eq "no core list: integrity, the strictest" "very-high integrity" "$(lk admission.git-reset-hard)"
mv "$T_TMP/rt" "$MB/risk-tiers.tsv"; mv "$MB/controls.tsv" "$T_TMP/ct"
t_eq "no register: integrity" "very-high integrity" "$(lk admission.git-reset-hard)"
mv "$T_TMP/ct" "$MB/controls.tsv"

t_section "6 - the matcher: each op, case-insensitive"
m_reset
when command equals 'ls -la'; cmd 'LS -LA'; t_eq "equals" "r " "$(ruled)"
cmd 'ls -la x'; t_eq "equals is whole" "" "$(ruled)"
when command prefix 'gsutil'; cmd 'gsutil ls'; t_eq "prefix" "r " "$(ruled)"
cmd 'x gsutil'; t_eq "prefix is the start" "" "$(ruled)"
when command suffix '.prod'; cmd 'ping db.prod'; t_eq "suffix" "r " "$(ruled)"
cmd 'ping db.prod.x'; t_eq "suffix is the end" "" "$(ruled)"
when command contains 'prod-'; cmd 'echo a-PROD-b'; t_eq "contains" "r " "$(ruled)"
when command word 'rm'; cmd 'sudo rm x'; t_eq "word, mid-line" "r " "$(ruled)"
cmd 'rm'; t_eq "word, alone" "r " "$(ruled)"
cmd 'farm rmdir warm'; t_eq "word isn't a substring" "" "$(ruled)"
cmd 'farm rm'; t_eq "a later occurrence still counts" "r " "$(ruled)"
when file_path prefix '/secrets/'; pay Write '{"file_path":"/secrets/a","content":"x"}'; t_eq "file_path" "r " "$(ruled)"
when url contains 'example.test'; pay WebFetch '{"url":"https://EXAMPLE.test/a"}'; t_eq "url" "r " "$(ruled)"
when query word 'salary'; pay WebSearch '{"query":"staff salary list"}'; t_eq "query" "r " "$(ruled)"
when command contains 'x'; pay Read '{"command":"x"}'; t_eq "a tool not listed" "" "$(ruled)"
pay Write '{"file_path":"x"}'; t_eq "a field the call lacks" "" "$(ruled)"
m_enforce '.rules = [{id:"two",label:"L",tier:"high",target:"other",tools:["Bash"],when:[{field:"command",op:"contains",value:"aa"},{field:"command",op:"contains",value:"bb"}]}]'
cmd 'aa'; t_eq "every condition must hold" "" "$(ruled)"
cmd 'aa bb'; t_eq "...and then it matches" "two " "$(ruled)"

t_section "7 - the command is normalised like the guards'"
when command contains 'gs://prod-'
cmd 'gsutil ls g"s"://prod-x'; t_eq "split quoting" "r " "$(ruled)"
when command equals 'gsutil ls'
cmd 'gsutil    ls'; t_eq "spaces" "r " "$(ruled)"
when command word 'bq'
cmd "b'q' rm x"; t_eq "a quoted command word" "r " "$(ruled)"

t_section "8 - policy is untrusted: no value is code or a pattern"
CANARY="$T_TMP/canary"
for _v in '.*' 'a|b' '(' '[' '\' '^ls' 'ls$' '$(touch '"$CANARY"')' '`touch '"$CANARY"'`' '"; touch '"$CANARY"'; "' '%s%n' '(a+)+$'; do
  when command contains "$_v"
  cmd 'ls -la'
  t_eq "the value $_v matches nothing here" "" "$(ruled)"
  cmd "x${_v}y"
  t_eq "...and matches itself, literally" "r " "$(ruled)"
done
if [ -e "$CANARY" ]; then t_fail "a policy value ran"; else t_pass; fi
# A relative canary: a label holds 60 characters, and a long TMPDIR would make this a policy refused for its length, not a label read as text.
m_enforce '.rules = [{id:"r",label:"$(touch label-ran)",tier:"high",target:"other",tools:["Bash"],when:[{field:"command",op:"contains",value:"zz"}]}]'
cmd 'zz'; (cd "$T_TMP" && sh "$TIER" rules "$T_TMP/p.json") > "$T_TMP/o"
t_has "a label comes back as text" "$(cat "$T_TMP/o")" '$(touch'
if [ -e "$T_TMP/label-ran" ]; then t_fail "a label ran"; else t_pass; fi
_big="$(jq -cn '[range(200) | {id:("r\(.)"),label:"L",tier:"high",target:"other",tools:["Bash"],when:[{field:"command",op:"word",value:("a" * 200)}]}]')"
m_enforce ".rules = $_big"
cmd "$(printf 'a %.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20)"
t_eq "200 rules at full length answer" "" "$(ruled)"

t_section "9 - bad arguments"
t_exit "no verb" 2 sh "$TIER"
t_exit "lookup with no id" 2 sh "$TIER" lookup
t_exit "rules with no file" 2 sh "$TIER" rules "$T_TMP/none"
t_exit "--help" 0 sh "$TIER" --help
t_done
