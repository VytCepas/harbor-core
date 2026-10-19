#!/usr/bin/env sh
# tests/lib/check.sh [root] — the rules in tests/README.md, checked (harbor#667).
# Prints one line per violation, prefixed with the rule id; exits 1 if there are any.
R="${1:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}"
G="$R/tests/guards"
V="$(mktemp "${TMPDIR:-/tmp}/check.XXXXXX")"; trap 'rm -f "$V"' EXIT
v() { printf '%s %s\n' "$1" "$2" >> "$V"; }  # <rule> <message>
rel() { printf '%s' "${1#"$R"/}"; }
SHARED='guards.jsonl shapes.jsonl benign.jsonl exemptions.jsonl'
tables() { find "$G" \( -name "$1.jsonl" -o -name "$1.*.jsonl" \) ! -name '*.msg.jsonl' 2>/dev/null | sort; }  # <guard> — its verdict tables

# T1 every suite under tests/ runs on the harness and asserts only through it.
for f in $(find "$R/tests" \( -name '*-test.sh' -o -name '*.test.sh' \) | sort); do
  grep -Eq '^[[:space:]]*\. .*core\.sh' "$f" || v T1 "$(rel "$f"): does not source tests/lib/core.sh"
  grep -Eq '(^|[[:space:];])t_init([[:space:];]|$)' "$f" || v T1 "$(rel "$f"): never calls t_init"
  grep -Eq '(^|[[:space:];])t_done([[:space:];]|$)' "$f" || v T1 "$(rel "$f"): never calls t_done"
  grep -En '^[[:space:]]*(ok|bad|pass|fail|check|assert[A-Za-z_]*|expect[A-Za-z_]*)[[:space:]]*\(\)' "$f" \
    | while IFS=: read -r n _; do v T1 "$(rel "$f"):$n: defines its own assertion helper"; done
done

# T2 budgets: 500 lines a file; a header of at most 8 comment lines, then comment runs of at most 3.
for f in $(find "$R/tests" -type f \( -name '*.sh' -o -name '*.jq' -o -name '*.jsonl' \) | sort); do
  n=$(wc -l < "$f" | tr -d ' '); [ "$n" -le 500 ] || v T2 "$(rel "$f"): $n lines (budget 500)"
  case "$f" in *.jsonl) continue ;; esac
  awk -v f="$(rel "$f")" '
    NR == 1 && /^#!/ { next }
    /^[[:space:]]*#/ { run++; if (!code) head++; next }
    { if (code && run > 3) printf "T2 %s:%d: %d comment lines in a row (budget 3)\n", f, NR - run, run
      code = 1; run = 0 }
    END { if (head > 8) printf "T2 %s: header is %d comment lines (budget 8)\n", f, head
          if (code && run > 3) printf "T2 %s:%d: %d comment lines in a row (budget 3)\n", f, NR - run + 1, run }' "$f" >> "$V"
done

# T3 every table row has the shape its runner expects.
PAYLOAD='(select([$r.cmd, $r.path, $r.input] | map(select(. != null)) | length != 1) | "needs exactly one of cmd, path or input"),
         (select(($r.tool != null) == ($r.cmd != null)) | "tool goes with path or input, never with cmd")'
for f in $(find "$G" -name '*.jsonl' 2>/dev/null | sort); do
  jq -c . "$f" > /dev/null 2>&1 || { v T3 "$(rel "$f"): not valid JSONL"; continue; }
  case "$(basename "$f")" in
    guards.jsonl)     prog='(["guard","rules","reps"][] as $k | select($r[$k] == null) | "missing \($k)")' ;;
    shapes.jsonl)     prog='(select($r.shape == null) | "missing shape"), (select($r.expect | IN("same","allow","no-human") | not) | "expect must be same, allow or no-human")' ;;
    benign.jsonl)     prog='(["id","cmd"][] as $k | select($r[$k] == null) | "missing \($k)")' ;;
    exemptions.jsonl) prog='(["guard","id","want","why"][] as $k | select($r[$k] == null) | "missing \($k)")' ;;
    *.msg.jsonl)      prog='(($r | keys) - ["id","why","cmd","tool","path","input","env","ctx","pad","fixture","has","hasnt"] | select(length > 0) | "unknown keys \(join(","))"),
                            (select($r.id == null) | "missing id"),
                            (select(($r.has != null) == ($r.hasnt != null)) | "needs exactly one of has or hasnt"),
                            '"$PAYLOAD" ;;
    *)                prog='(($r | keys) - ["id","rule","want","todo","why","cmd","tool","path","input","env","ctx","pad","fixture"] | select(length > 0) | "unknown keys \(join(","))"),
                            (["id","rule","want"][] as $k | select($r[$k] == null) | "missing \($k)"),
                            '"$PAYLOAD"',
                            (select($r.want != null and ($r.want | IN("allow","ask","deny","block") | not)) | "want \($r.want) is not a verdict"),
                            (select($r.todo != null and (($r.todo | IN("allow","ask","deny","block") | not) or $r.todo == $r.want)) | "todo must be a verdict other than want"),
                            (select($r.fixture != null and ($r.fixture | IN("nonorm","copy") | not)) | "unknown fixture \($r.fixture)")' ;;
  esac
  case "$(basename "$f")" in
    guards.jsonl) key='.guard' ;; shapes.jsonl) key='.shape' ;; exemptions.jsonl) key='[.guard, .id]' ;; *) key='.id' ;;
  esac
  jq -r -s --arg f "$(rel "$f")" "
    (to_entries[] | .value as \$r | (.key + 1) as \$n | ($prog) | \"T3 \(\$f):\(\$n): \(.)\"),
    (map(select($key != null)) | group_by($key)[] | select(length > 1) | \"T3 \(\$f): duplicate \(.[0] | $key)\")" "$f" >> "$V"
done

# T4 routing: every guard table belongs to a registered guard, and every registered guard is wired.
REG="$(jq -r '.guard' "$G/guards.jsonl" 2>/dev/null)"
for f in $(find "$G" -name '*.jsonl' 2>/dev/null | sort); do
  b="$(basename "$f")"; case " $SHARED " in *" $b "*) continue ;; esac
  g="${b%%.*}"  # <guard>.jsonl, <guard>.<part>.jsonl, <guard>.msg.jsonl
  printf '%s\n' "$REG" | grep -qx "$g" || v T4 "$(rel "$f"): no guard '$g' in tests/guards/guards.jsonl"
done
for g in $REG; do
  [ -f "$R/bin/guard-$g.sh" ] || v T4 "guards.jsonl: '$g' has no bin/guard-$g.sh"
  [ -n "$(tables "$g")" ] || v T4 "guards.jsonl: '$g' has no tests/guards/$g.jsonl"
  [ -f "$G/$g-test.sh" ] || v T4 "guards.jsonl: '$g' has no tests/guards/$g-test.sh"
done
for f in $(find "$G" -name '*-test.sh' 2>/dev/null | sort); do  # <guard>-test.sh, or <guard>.<part>-test.sh for one part
  n="$(basename "$f" -test.sh)"; g="${n%%.*}"
  printf '%s\n' "$REG" | grep -qx "$g" || v T4 "$(rel "$f"): no guard '$g' in guards.jsonl"
  [ "$n" = "$g" ] || [ -f "$G/$n.jsonl" ] || v T4 "$(rel "$f"): has no table tests/guards/$n.jsonl"
done
for f in $(find "$G" -name '*.*.jsonl' ! -name '*.msg.jsonl' 2>/dev/null | sort); do
  n="$(basename "$f" .jsonl)"; [ -f "$G/$n-test.sh" ] || v T4 "$(rel "$f"): no suite tests/guards/$n-test.sh runs it"
done
for f in $(find "$R/tests" \( -name '*-test.sh' -o -name '*.test.sh' \) | sort); do
  grep -qx "$(rel "$f")" "$R/CONTRACTS/suites.txt" 2>/dev/null || v T4 "$(rel "$f"): not listed in CONTRACTS/suites.txt"
done

# T5 coverage: every rule the guard names has a row that fires it and an allow row beside it.
for g in $REG; do
  src="$R/bin/guard-$g.sh"; [ -n "$(tables "$g")" ] && [ -f "$src" ] || continue
  t="$(mktemp "${TMPDIR:-/tmp}/check-rows.XXXXXX")"; cat $(tables "$g") > "$t"
  jq -r -s 'group_by(.id)[] | select(length > 1) | .[0].id' "$t" | while read -r i; do v T3 "tests/guards/$g tables: duplicate $i across parts"; done
  pat="$(jq -r --arg g "$g" 'select(.guard == $g) | .rules' "$G/guards.jsonl")"
  rules="$(sed -e ':a' -e '/\\$/{N;s/\\\n[[:space:]]*/ /;ba' -e '}' "$src" | grep -oE "$pat" | sed -E "s|$pat|\\1|" | sort -u)"  # joins \-continued lines
  [ -n "$rules" ] || { v T5 "guards.jsonl: the rules pattern for '$g' matches nothing in bin/guard-$g.sh"; continue; }
  for r in $rules; do
    jq -e --arg r "$r" 'select(.rule == $r and .want != "allow")' "$t" > /dev/null || v T5 "tests/guards/$g tables: rule '$r' has no row that fires it"
    jq -e --arg r "$r" 'select(.rule == $r and .want == "allow")' "$t" > /dev/null || v T5 "tests/guards/$g tables: rule '$r' has no allow row beside it"
  done
  jq -r '.rule // empty' "$t" | sort -u | while read -r r; do
    [ "$r" = none ] || printf '%s\n' "$rules" | grep -qx "$r" || v T5 "tests/guards/$g tables: rule '$r' is not a rule bin/guard-$g.sh names"
  done
  rm -f "$t"
done

# T6 every exemption matches a shared row and changes its verdict or records a todo.
for g in $REG; do
  rows="$(jq -c -n --arg g "$g" -f "$R/tests/lib/shared.jq" --argjson ex '[]' \
    --slurpfile reg "$G/guards.jsonl" --slurpfile shapes "$G/shapes.jsonl" --slurpfile benign "$G/benign.jsonl" 2>/dev/null)"
  jq -c --arg g "$g" 'select(.guard == $g)' "$G/exemptions.jsonl" 2>/dev/null | while IFS= read -r e; do
    id="$(printf '%s' "$e" | jq -r .id)"
    def="$(printf '%s\n' "$rows" | jq -r --arg id "$id" 'select(.id == $id) | .want')"
    if [ -z "$def" ]; then v T6 "exemptions.jsonl: '$g' $id matches no shared row"
    elif [ "$def" = "$(printf '%s' "$e" | jq -r .want)" ] && [ "$(printf '%s' "$e" | jq -r '.todo // ""')" = "" ]; then
      v T6 "exemptions.jsonl: '$g' $id changes nothing"
    fi
  done
done

n=$(wc -l < "$V" | tr -d ' ')
cat "$V"
echo "check: 6 rules, $n violations"
[ "$n" -eq 0 ]
