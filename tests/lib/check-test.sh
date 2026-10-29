#!/usr/bin/env sh
# tests/lib/check.sh must pass the real tree and go red on each rule it enforces;
# every guard table must fail against a guard that always allows, and one that always denies.
set -u
. "$(dirname "$0")/core.sh"
. "$(dirname "$0")/table.sh"
t_init

C="$T_ROOT/tests/lib/check.sh"
t_section "the real tree"
t_exit 'tests/ passes its own rules' 0 sh "$C" "$T_ROOT"

F="$T_TMP/fx"
mk() { # a clean fixture tree at $F
  rm -rf "$F"; mkdir -p "$F/CONTRACTS" "$F/bin" "$F/tests/guards"
  ln -s "$T_ROOT/tests/lib" "$F/tests/lib"
  echo 'tests/guards/x-test.sh' > "$F/CONTRACTS/suites.txt"
  echo 'RULE="a"' > "$F/bin/guard-x.sh"
  printf '%s\n' '{"guard":"x","posture":null,"rules":"RULE=\"([a-z]+)\"","reps":{"deny":"zap it","allow":"ls"}}' > "$F/tests/guards/guards.jsonl"
  printf '%s\n' '{"id":"a1","rule":"a","want":"deny","cmd":"zap it"}' '{"id":"a2","rule":"a","want":"allow","cmd":"zap --dry"}' > "$F/tests/guards/x.jsonl"
  printf '%s\n' '#!/usr/bin/env sh' '. "$(dirname "$0")/../lib/core.sh"' 't_init' 't_done' > "$F/tests/guards/x-test.sh"
  echo '{"shape":"bare","reps":["deny","allow"],"expect":"same"}' > "$F/tests/guards/shapes.jsonl"
  echo '{"id":"b","cmd":"true"}' > "$F/tests/guards/benign.jsonl"
  : > "$F/tests/guards/exemptions.jsonl"
}
red() { # <rule> <expected line fragment> — check.sh on the (now broken) fixture
  _o="$(sh "$C" "$F" 2>&1)"; _r=$?
  t_eq "$1 exits 1: $2" 1 "$_r"
  t_has "$1 says: $2" "$_o" "$2"
}

t_section "a clean fixture passes"
mk; t_has 'no violations' "$(sh "$C" "$F")" "check: 6 rules, 0 violations"

part() { mv "$F/tests/guards/x.jsonl" "$F/tests/guards/x.a.jsonl"; cp "$F/tests/guards/x-test.sh" "$F/tests/guards/x.a-test.sh"
  echo 'tests/guards/x.a-test.sh' >> "$F/CONTRACTS/suites.txt"; }
mk; part; t_has 'a guard split into parts passes' "$(sh "$C" "$F")" "check: 6 rules, 0 violations"

t_section "each rule goes red"
mk; printf 'ok() { :; }\n' >> "$F/tests/guards/x-test.sh";                red T1 'defines its own assertion helper'
mk; sed -i.bak '2d' "$F/tests/guards/x-test.sh";                          red T1 'does not source tests/lib/core.sh'
mk; printf '#a\n#b\n#c\n#d\nt_done\n' >> "$F/tests/guards/x-test.sh";     red T2 '4 comment lines in a row'
mk; awk 'BEGIN { for (i = 3; i <= 501; i++) printf "{\"id\":\"n%d\",\"rule\":\"a\",\"want\":\"allow\",\"cmd\":\"ls\"}\n", i }' >> "$F/tests/guards/x.jsonl"
                                                                           red T2 '501 lines (budget 500)'
mk; echo '{"id":"a3","rule":"a","want":"maybe","cmd":"x"}' >> "$F/tests/guards/x.jsonl";              red T3 'want maybe is not a verdict'
mk; echo '{"id":"a1","rule":"a","want":"deny","cmd":"x"}' >> "$F/tests/guards/x.jsonl";               red T3 'duplicate a1'
mk; echo '{"id":"a3","rule":"a","want":"deny","cmd":"x","tool":"Write","path":"/p"}' >> "$F/tests/guards/x.jsonl"
                                                                           red T3 'needs exactly one of cmd, path or input'
mk; echo '{"id":"a3","rule":"a","want":"deny","cmd":"x","tool":"Bash"}' >> "$F/tests/guards/x.jsonl";   red T3 'tool goes with path or input'
mk; echo '{"id":"a1","rule":"a","want":"deny","cmd":"x"}' > "$F/tests/guards/x.more.jsonl";            red T3 'duplicate a1 across parts'
mk; echo '{"id":"a3","rule":"a","want":"deny","cmd":"x","colour":"red"}' >> "$F/tests/guards/x.jsonl"   red T3 'unknown keys colour'
mk; echo '{"id":"a3","rule":"a","want":"deny","todo":"deny","cmd":"x"}' >> "$F/tests/guards/x.jsonl"   red T3 'todo must be a verdict other than want'
mk; echo '{"id":"m1","cmd":"x","has":"a","hasnt":"b"}' > "$F/tests/guards/x.msg.jsonl";               red T3 'needs exactly one of has or hasnt'
mk; echo '{"id":"y1","rule":"a","want":"deny","cmd":"x"}' > "$F/tests/guards/y.jsonl";                 red T4 "no guard 'y'"
mk; rm "$F/bin/guard-x.sh";                                                red T4 'has no bin/guard-x.sh'
mk; echo '{"id":"y1","rule":"a","want":"deny","cmd":"x"}' > "$F/tests/guards/y.part.jsonl";            red T4 "no guard 'y'"
mk; part; rm "$F/tests/guards/x.a-test.sh"; sed -i.bak '/x.a-test/d' "$F/CONTRACTS/suites.txt";        red T4 'no suite tests/guards/x.a-test.sh runs it'
mk; part; mv "$F/tests/guards/x.a.jsonl" "$F/tests/guards/x.jsonl";                                     red T4 'has no table tests/guards/x.a.jsonl'
mk; : > "$F/CONTRACTS/suites.txt";                                         red T4 'not listed in CONTRACTS/suites.txt'
mk; echo 'RULE="b"' >> "$F/bin/guard-x.sh";                                red T5 "rule 'b' has no row that fires it"
mk; sed -i.bak 's/RULE=/RULE=[[:space:]]*/' "$F/tests/guards/guards.jsonl"; printf 'RULE= \\\n  "c"\n' >> "$F/bin/guard-x.sh"
                                                                           red T5 "rule 'c' has no row that fires it"
mk; echo '{"id":"a3","rule":"zzz","want":"deny","cmd":"x"}' >> "$F/tests/guards/x.jsonl";             red T5 "rule 'zzz' is not a rule"
mk; sed -i.bak 's/RULE=/NOPE=/' "$F/tests/guards/guards.jsonl";           red T5 'matches nothing'
# harbor#957: a guard whose rules are ledger ids set per tier arm (guard-cloud's shape). Its default arm is no rule.
idmk() { printf '  A) _crule=x-a ;;\n  *) _crule=x-unclassified ;;\n' > "$F/bin/guard-x.sh"
  printf '%s\n' '{"guard":"x","posture":null,"rules":"^ +[A-Z]+\\) .*_crule=(x-[a-z-]+)","reps":{"deny":"zap it","allow":"ls"}}' > "$F/tests/guards/guards.jsonl"
  printf '%s\n' '{"id":"a1","rule":"x-a","want":"deny","cmd":"zap it"}' '{"id":"a2","rule":"x-a","want":"allow","cmd":"zap --dry"}' > "$F/tests/guards/x.jsonl"; }
mk; idmk; t_has 'ledger-id rows cover a ledger-id guard; its default arm needs none' "$(sh "$C" "$F")" "check: 6 rules, 0 violations"
mk; idmk; echo '{"id":"a3","rule":"A","want":"deny","cmd":"x"}' >> "$F/tests/guards/x.jsonl";          red T5 "rule 'A' is not a rule"
mk; idmk; printf '  B) _crule=x-b ;;\n' >> "$F/bin/guard-x.sh";                                         red T5 "rule 'x-b' has no row that fires it"
mk; echo '{"guard":"x","id":"shape:gone/deny","want":"allow","why":"w"}' > "$F/tests/guards/exemptions.jsonl"
                                                                           red T6 'matches no shared row'
mk; echo '{"guard":"x","id":"shape:bare/deny","want":"deny","why":"w"}' > "$F/tests/guards/exemptions.jsonl"
                                                                           red T6 'changes nothing'

# Canary root: the real lib and guard tables, run against stub guards.
K="$T_TMP/canary"; mkdir -p "$K/CONTRACTS" "$K/tests/x"; : > "$K/CONTRACTS/suites.txt"
ln -s "$T_ROOT/tests/lib" "$K/tests/lib"; ln -s "$T_ROOT/tests/guards" "$K/tests/guards"
printf '#!/bin/sh\ncat >/dev/null\nexit 0\n' > "$K/allow.sh"
printf '#!/bin/sh\ncat >/dev/null\nprintf %s\n' "'{\"hookSpecificOutput\":{\"permissionDecision\":\"deny\"}}'" > "$K/deny.sh"
fails() { # <stub> <runner call> — how many assertions a child suite failed
  printf '. "%s/tests/lib/core.sh"; . "%s/tests/lib/table.sh"; . "%s/tests/lib/stub-rows.sh"; t_init; S="%s"; %s; t_done\n' "$K" "$K" "$K" "$1" "$2" > "$K/tests/x/c-test.sh"
  sh "$K/tests/x/c-test.sh" 2>/dev/null | sed -n 's/.* passed, \([0-9]*\) failed$/\1/p'
}
must_fail() { # <jq filter> <file> — rows a stub must fail
  jq -s "map(select($1)) | length" "$2"
}
t_section "every table can fail"
for g in $(jq -r .guard "$T_ROOT/tests/guards/guards.jsonl"); do
  for t in $(find "$T_ROOT/tests/guards" \( -name "$g.jsonl" -o -name "$g.*.jsonl" \) ! -name '*.msg.jsonl' | sort); do
    n="$(basename "$t")"
    t_eq "$n vs allow-all" "$(must_fail '.want != "allow"' "$t")" "$(fails "$K/allow.sh" "t_table \$S $t")"
    t_eq "$n vs deny-all"  "$(must_fail '.want != "deny"' "$t")"  "$(fails "$K/deny.sh" "t_table \$S $t")"
  done
  m="$T_ROOT/tests/guards/$g.msg.jsonl"
  [ ! -f "$m" ] || t_eq "$g.msg.jsonl vs allow-all" "$(must_fail 'true' "$m")" "$(fails "$K/allow.sh" "t_msgs \$S $m")"
  sh_rows="$T_TMP/shared-$g.jsonl"
  jq -c -n --arg g "$g" -f "$T_ROOT/tests/lib/shared.jq" --slurpfile reg "$T_ROOT/tests/guards/guards.jsonl" \
    --slurpfile shapes "$T_ROOT/tests/guards/shapes.jsonl" --slurpfile benign "$T_ROOT/tests/guards/benign.jsonl" \
    --slurpfile ex "$T_ROOT/tests/guards/exemptions.jsonl" > "$sh_rows"
  t_eq "shared rows ($g) vs deny-all" "$(must_fail '.want != "deny"' "$sh_rows")" "$(fails "$K/deny.sh" "t_shared \$S $g")"
  t_eq "shared rows ($g) vs allow-all" "$(must_fail '.want != "allow"' "$sh_rows")" "$(fails "$K/allow.sh" "t_shared \$S $g")"
done
t_done
