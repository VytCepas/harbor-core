#!/usr/bin/env sh
# lint.locale-ranges: no sh case pattern holds a range that follows the locale's collation (harbor#1149).
# Each arm is a throwaway git checkout holding one planted file. The verdict is read from the rule's own
# output, and must be the same under the default locale and LC_ALL=C: the rule is awk under LC_ALL=C.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
R="VIOLATION [lint.locale-ranges]"
mk() { # <name> <file> <body…> → a checkout whose only sh file is <file>
  _d="$T_TMP/lr-$1"; mkdir -p "$_d/bin"; cp "$T_ROOT/bin/lint-locale-ranges.awk" "$_d/bin/"
  _f="$2"; shift 2; mkdir -p "$_d/$(dirname "$_f")"; printf "$@" > "$_d/$_f"
  ( cd "$_d" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm x ) >/dev/null 2>&1
  printf '%s' "$_d"
}
both() { # <name> <file> <body…> → the rule's output, from the default locale and from LC_ALL=C, which must agree
  _b="$(mk "$@")"; _o1="$(lint1 lint.locale-ranges "$_b")"; _o2="$(LC_ALL=C lint1 lint.locale-ranges "$_b")"
  [ "$(printf '%s' "$_o1" | grep -c "$R")" = "$(printf '%s' "$_o2" | grep -c "$R")" ] || printf 'LOCALE-DEPENDENT VERDICT\n'
  printf '%s\n' "$_o1"
}

t_section "red: the ranges that follow the locale"
for pat in '*[!a-z]*' '*[!a-z0-9-]*' '[A-Z]*' '*[!0-9a-f]*' '*[!!-~]*' '*[!\ -~]*' '[a-m]*'; do
  _o="$(both red bin/bad.sh '#!/bin/sh\ncase "$1" in\n  %s) echo no ;;\nesac\n' "$pat")"
  t_has "$pat" "$_o" "$R bin/bad.sh:3 "
  t_hasnt "$pat: same verdict in both locales" "$_o" "LOCALE-DEPENDENT"
done
t_has "the planted one-liner from the ticket" "$(both one bin/new.sh 'case x in *[!a-z]*) echo bad;; esac\n')" "$R bin/new.sh:1 "
t_has "a pattern after |" "$(both alt bin/a.sh 'case $1 in\n  x|[!a-z]*|y) : ;;\nesac\n')" "$R bin/a.sh:2 "
t_has "a bracket inside a \$( ) inside double quotes" "$(both sub bin/s.sh 'x="$(case $1 in [A-Z]*) echo U ;; esac)"\n')" "$R bin/s.sh:1 "
t_has "an extensionless file with a sh shebang" "$(both noext bin/tool '#!/usr/bin/env bash\ncase $1 in [A-Z]*) : ;; esac\n')" "$R bin/tool:2 "
t_has "the fix line is there" "$(both fix bin/bad.sh 'case x in *[!a-z]*) : ;; esac\n')" "fix: spell the letters out"

t_section "green: the same intent, locale-independent, and what is not a case pattern"
for pat in '*[!A-Za-z0-9_-]*' '*[!a-zA-Z]*' '*[!0-9]*' '*[!0-9A-Fa-f]*' '*[A-Fa-f0-9]*' '*[!abcdefghijklmnopqrstuvwxyz0-9-]*' '[0-9][0-9]' '*[[:alpha:]]*'; do
  t_hasnt "$pat" "$(both ok bin/ok.sh 'case "$1" in\n  %s) echo ok ;;\nesac\n' "$pat")" "$R"
done
t_hasnt "a comment" "$(both c1 bin/c.sh '# case x in *[!a-z]*) is what the old code said\n: # [A-Z]*)\n')" "$R"
t_hasnt "quoted awk, grep and sed regexes" "$(both c2 bin/q.sh "awk '\$1 ~ /^[a-z]+\$/ { print }' f; grep -E '^[a-z]+)' f; sed 's/[A-Z]*|/x/' f\n")" "$R"
t_hasnt "a double-quoted string" "$(both c3 bin/q2.sh 'echo "case x in *[!a-z]*) ;;"\n')" "$R"
t_hasnt "a heredoc body" "$(both c4 bin/h.sh 'cat <<EOF\ncase x in *[!a-z]*) ;; esac\nEOF\n:\n')" "$R"
t_hasnt "a [ ] test and a parameter expansion are not case patterns" "$(both c5 bin/t.sh '[ -f x ] && y=${z#[a-z]}\n')" "$R"
t_hasnt "a python file is not sh" "$(both c6 bin/p.py 'case x in *[!a-z]*) pass\n')" "$R"
t_hasnt "an extensionless file with a python shebang" "$(both c7 bin/py '#!/usr/bin/env python3\ncase x in *[!a-z]*) pass\n')" "$R"

t_section "the rule fails closed"
_d="$(mk gone bin/ok.sh ':\n')"; rm "$_d/bin/lint-locale-ranges.awk"
t_has "a missing scanner is red, not a pass" "$(lint1 lint.locale-ranges "$_d")" "$R bin/lint-locale-ranges.awk is missing"

t_section "the tree itself, and the behaviour the rule exists for"
t_eq "harbor has no such pattern" "0" "$(vcount "$(lint1 lint.locale-ranges "$T_ROOT")")"
# the probe from the ticket, run in a shell: a capital passes [!a-z] only where collation interleaves
t_eq "under LC_ALL=C [!a-z0-9-] flags BadName" "flagged" "$(LC_ALL=C sh -c 'case BadName in *[!a-z0-9-]*) echo flagged;; *) echo NOT;; esac')"
t_eq "...and the spelled-out form flags it in the default locale too" "flagged" "$(sh -c 'case BadName in *[!abcdefghijklmnopqrstuvwxyz0-9-]*) echo flagged;; *) echo NOT;; esac')"
t_done
