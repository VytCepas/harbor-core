#!/usr/bin/env sh
# verb registers (harbor#1419): contracts/verbs/*.md hold one list of command shapes per CLI. This holds EACH register
# file to the allow and ask rules bin/admission-deny.sh actually writes from it (run, not read), to the one row shape,
# and refuses an allow rule that passes a gated row with no ask over it. Every kind of disagreement is driven red below
# on a mutated copy, once per file; uninstall takes the same rules back out. git's deny entries and guard-bash list
# are held by tests/admission/git/verbs.test.sh.
. "$(dirname "$0")/../../lib/core.sh"; t_init
VD="$T_ROOT/contracts/verbs"; RD="$T_ROOT/bin/gate-verbs.sh"
FILES="cu.md gh.md git.md mail.md"
# The first words each register may use: a row naming another CLI is a row in the wrong file.
clis_of() { case "$1" in git.md) echo git ;; gh.md) echo gh ;; cu.md) echo cu ;; mail.md) echo gmail-read gmail-write gcal-read gcal-write ;; esac; }

vr_glob() { # <rule body> <command> -> 0 iff the rule matches it as a permission rule does; a trailing " *" also matches nothing
  # shellcheck disable=SC2254
  case "$2" in $1) return 0 ;; esac
  case "$1" in *' *') case "$2" in ${1%' *'}) return 0 ;; esac ;; esac
  return 1
}
vr_tree() { # <dir> -> a tree holding floor-deny, its libraries, the reader and a copy of every register
  mkdir -p "$1/bin" "$1/contracts"
  cp "$T_ROOT/bin/admission-deny.sh" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/deploy-install-lib.sh" "$RD" "$1/bin/"
  cp -R "$VD" "$1/contracts/verbs"
}
vr_derive() { # <tree> <dir> -> <dir>/settings.json as floor-deny --apply writes it into an empty one
  mkdir -p "$2"; printf '{"permissions":{"allow":[],"deny":[]}}\n' > "$2/settings.json"
  CLAUDE_CONFIG_DIR="$2" sh "$1/bin/admission-deny.sh" --apply --dir "$2" > "$2/fd.log" 2>&1; echo "$?" > "$2/fd.rc"
}
vr_print() { sh "$1/bin/admission-deny.sh" --print; } # <tree> -> allow|ask TAB Bash(rule) TAB register, one per derived rule
vr_pcheck() { # <register.md> <print-output-file> -> one line per row of that file with no --print rule, and per --print rule with no row
  _f="${1##*/}"; _w="$T_TMP/pchk"; rm -rf "$_w"; mkdir -p "$_w"
  sh "$RD" rows "$1" | awk -F'\t' '($4 == "allow" || $4 == "ask") && ($2 ~ /^[a-z][a-z-]* [a-z][a-z-]*( |$)/ || ($4 == "ask" && $2 ~ /^[a-z][a-z-]* \*$/)) && $2 !~ /[<>`|;&$]/ { print $4 "\tBash(" $2 ")" }' | sort -u > "$_w/want"
  awk -F'\t' -v f="$_f" '$3 == f { print $1 "\t" $2 }' "$2" | sort -u > "$_w/have"
  comm -23 "$_w/want" "$_w/have" | sed "s/^/$_f: register row has no --print rule: /"
  comm -13 "$_w/want" "$_w/have" | sed "s/^/$_f: --print rule has no register row: /"
}
vr_check() { # <register.md> <settings.json> -> one line per disagreement between that file and the rules, nothing when they agree
  _f="${1##*/}"; _w="$T_TMP/chk"; rm -rf "$_w"; mkdir -p "$_w"
  sh "$RD" rows "$1" | cut -f2- > "$_w/rows"        # spelling, class, perm, actor, instead
  [ -s "$_w/rows" ] || echo "$_f: the register has no rows"
  _c="$(clis_of "$_f")"
  awk -F'\t' -v clis="$_c" -v f="$_f" '
    BEGIN { n = split(clis, a, " "); for (i = 1; i <= n; i++) ok[a[i]] = 1 }
    { split($1, w, " ") }
    ($3 == "allow" || $3 == "ask") && !(w[1] in ok) { print f ": row " $1 ": names a CLI this register does not own" }
    $2 !~ /^(read|write|gated)$/ { print f ": row " $1 ": class is " $2 }
    $3 !~ /^(builtin|allow|ask|deny|classifier)$/ { print f ": row " $1 ": perm is " $3 }
    $4 !~ /^(app|own-org|operator)$/ { print f ": row " $1 ": actor is " $4 }
    $4 == "operator" && $3 == "allow" { print f ": row " $1 ": actor operator but perm allow: an allow rule hands an operator step to the agent" }
    ($3 == "allow" || $3 == "ask") && ($1 !~ /^[a-z][a-z-]* [a-z][a-z-]*( |$)/ && !($3 == "ask" && $1 ~ /^[a-z][a-z-]* \*$/) || $1 ~ /[<>`|;&$]/) {
      print f ": row " $1 ": an " $3 " rule must start <cli> <subcommand> and name no <argument>" }
    seen[$1]++ == 1 { print f ": row " $1 ": listed twice" }' "$_w/rows"
  # the rules floor-deny wrote for this file's CLIs, against the rows that imply them
  for _p in allow ask; do
    awk -F'\t' -v p="$_p" '$3 == p && $1 ~ /^[a-z][a-z-]* [a-z][a-z-]*( |$)|^[a-z][a-z-]* \*$/ && $1 !~ /[<>`|;&$]/ { print "Bash(" $1 ")" }' "$_w/rows" | sort -u > "$_w/want.$_p"
    for _k in $_c; do jq -r --arg p "$_p" --arg k "Bash($_k " '.permissions[$p] // [] | .[] | select(startswith($k))' "$2"; done | sort -u > "$_w/have.$_p"
    comm -23 "$_w/want.$_p" "$_w/have.$_p" | sed "s/^/$_f: register $_p row has no rule in settings.json: /"
    comm -13 "$_w/want.$_p" "$_w/have.$_p" | sed "s/^/$_f: settings.json $_p rule has no register row: /"
  done
  # no allow rule passes a gated shape unless an ask or a deny outranks it
  awk -F'\t' '$2 == "gated" { print $1 }' "$_w/rows" | sed -e 's/<[^>]*>/x/g' -e 's/\*/x/g' > "$_w/gated"
  sed -e 's/^Bash(//' -e 's/)$//' "$_w/have.allow" > "$_w/allow"
  { jq -r '.permissions.ask // [] | .[]' "$2"; jq -r '.permissions.deny // [] | .[]' "$2"; } | sed -e 's/^Bash(//' -e 's/)$//' > "$_w/over"
  while IFS= read -r _i; do
    while IFS= read -r _a; do
      vr_glob "$_a" "$_i" || continue
      _ok=0; while IFS= read -r _o; do vr_glob "$_o" "$_i" && _ok=1; done < "$_w/over"
      [ "$_ok" = 1 ] || echo "$_f: allow rule Bash($_a) passes the gated shape '$_i' with no ask or deny over it"
    done < "$_w/allow"
  done < "$_w/gated"
}

t_section "every register parses: the files exist, each has rows, the row shape is one"
t_eq "the register files are exactly the four" "$FILES" "$(find "$VD" -maxdepth 1 -name '*.md' ! -name README.md -exec basename {} \; | sort | tr '\n' ' ' | sed 's/ $//')"
for _f in $FILES; do
  t_eq "$_f has rows" yes "$([ "$(sh "$RD" rows "$VD/$_f" | wc -l)" -gt 5 ] && echo yes || echo no)"
  t_eq "$_f has an allow or ask row" yes "$(sh "$RD" rows "$VD/$_f" | awk -F'\t' '$4 == "allow" || $4 == "ask"' | grep -q . && echo yes || echo no)"
done
t_eq "gh names an operator row" yes "$(sh "$RD" rows "$VD/gh.md" | awk -F'\t' '$5 == "operator"' | grep -q . && echo yes || echo no)"

t_section "the tree agrees: each register, and the rules floor-deny writes from it"
vr_tree "$T_TMP/tree"; vr_derive "$T_TMP/tree" "$T_TMP/real"
t_eq "floor-deny --apply exits 0" 0 "$(cat "$T_TMP/real/fd.rc")"
t_hasnt "floor-deny skipped no row" "$(cat "$T_TMP/real/fd.log")" "so it is skipped"
t_has "the dry-run log names a derived rule" "$(cat "$T_TMP/real/fd.log")" "allow rule (verbs): Bash(gh pr create *)"
for _f in $FILES; do t_eq "$_f: no disagreement" "" "$(vr_check "$VD/$_f" "$T_TMP/real/settings.json")"; done
vr_print "$T_TMP/tree" > "$T_TMP/print.tsv"
for _f in $FILES; do
  t_eq "$_f: --print shows a rule for every allow and ask row, and no other" "" "$(vr_pcheck "$VD/$_f" "$T_TMP/print.tsv")"
done
t_has "gcal-write asks" "$(jq -r '.permissions.ask[]' "$T_TMP/real/settings.json")" "Bash(gcal-write *)"
t_has "cu asks on --anyway" "$(jq -r '.permissions.ask[]' "$T_TMP/real/settings.json")" "Bash(cu set *--anyway*)"
t_hasnt "gh merge has no allow rule" "$(jq -r '.permissions.allow[]' "$T_TMP/real/settings.json")" "Bash(gh pr merge"

# one row per file, flipped from allow to classifier: the register drops it, the rule stays
vr_flip() { # <file> <spelling> -> a copy of the register with that row's perm turned to classifier, at $T_TMP/m/<file>
  mkdir -p "$T_TMP/m"
  awk -F'|' -v s="\`$2\`" 'BEGIN { OFS = "|" } { t = $2; gsub(/^ +| +$/, "", t) } t == s && $4 ~ / allow / { $4 = " classifier " } { print }' "$VD/$1" > "$T_TMP/m/$1"
  [ "$(cmp -s "$VD/$1" "$T_TMP/m/$1" && echo same)" != same ] || echo "vr_flip: no row $2 in $1 was an allow row" >&2
}
for _r in "git.md|git ls-tree *" "gh.md|gh pr create *" "cu.md|cu show *" "mail.md|gmail-read read *"; do
  _f="${_r%%|*}"; _s="${_r#*|}"
  t_section "red, $_f: the row '$_s' stops being allow, and the rule it implied has no row"
  vr_flip "$_f" "$_s"
  t_has "$_f: caught" "$(vr_check "$T_TMP/m/$_f" "$T_TMP/real/settings.json")" "$_f: settings.json allow rule has no register row: Bash($_s)"
  # end to end: floor-deny, run on a tree whose register carries the flipped row, derives no such rule
  vr_tree "$T_TMP/t-$_f"; cp "$T_TMP/m/$_f" "$T_TMP/t-$_f/contracts/verbs/$_f"; vr_derive "$T_TMP/t-$_f" "$T_TMP/d-$_f"
  t_hasnt "$_f: floor-deny reads that file, so the rule is gone" "$(jq -r '.permissions.allow[]' "$T_TMP/d-$_f/settings.json")" "Bash($_s)"
  t_eq "$_f: and the check passes on what it derived" "" "$(vr_check "$T_TMP/m/$_f" "$T_TMP/d-$_f/settings.json")"
  vr_print "$T_TMP/t-$_f" > "$T_TMP/print-$_f.tsv"
  t_has "$_f: --print still lists the rule the flipped row implied, and the check says so" "$(vr_pcheck "$T_TMP/m/$_f" "$T_TMP/print.tsv")" "$_f: --print rule has no register row: allow	Bash($_s)"
  t_eq "$_f: --print on the tree with the flipped register drops it, and the check passes" "" "$(vr_pcheck "$T_TMP/m/$_f" "$T_TMP/print-$_f.tsv")"
done

t_section "red: settings.json lacks a rule a register implies, or carries one no register does"
for _r in "gh.md|gh pr edit *" "cu.md|cu note *" "mail.md|gmail-write new *" "git.md|git add *"; do
  _f="${_r%%|*}"; _s="${_r#*|}"
  jq --arg r "Bash($_s)" '.permissions.allow -= [$r]' "$T_TMP/real/settings.json" > "$T_TMP/s-lack.json"
  t_has "$_f: a missing allow rule" "$(vr_check "$VD/$_f" "$T_TMP/s-lack.json")" "$_f: register allow row has no rule in settings.json: Bash($_s)"
done
jq '.permissions.ask -= ["Bash(gcal-write *)"]' "$T_TMP/real/settings.json" > "$T_TMP/s-ask.json"
t_has "mail.md: a missing ask rule" "$(vr_check "$VD/mail.md" "$T_TMP/s-ask.json")" "mail.md: register ask row has no rule in settings.json: Bash(gcal-write *)"
jq '.permissions.allow += ["Bash(gh pr merge *)"]' "$T_TMP/real/settings.json" > "$T_TMP/s-extra.json"
_x="$(vr_check "$VD/gh.md" "$T_TMP/s-extra.json")"
t_has "gh.md: an allow rule with no row" "$_x" "gh.md: settings.json allow rule has no register row: Bash(gh pr merge *)"
t_has "gh.md: and the gated shape it lets through" "$_x" "gh.md: allow rule Bash(gh pr merge *) passes the gated shape 'gh pr merge x' with no ask or deny over it"

t_section "red: a gated row an allow rule passes, an operator row made allow, a row in the wrong file"
sed 's/^| `cu set \*--anyway\*` | gated | ask |/| `cu set *--anyway*` | gated | classifier |/' "$VD/cu.md" > "$T_TMP/m/cu-gate.md"
mkdir -p "$T_TMP/m/x"; cp "$T_TMP/m/cu-gate.md" "$T_TMP/m/x/cu.md"
vr_tree "$T_TMP/t-cug"; cp "$T_TMP/m/cu-gate.md" "$T_TMP/t-cug/contracts/verbs/cu.md"; vr_derive "$T_TMP/t-cug" "$T_TMP/d-cug"
t_has "cu.md: dropping the --anyway ask lets cu set through" "$(vr_check "$T_TMP/m/x/cu.md" "$T_TMP/d-cug/settings.json")" \
  "cu.md: allow rule Bash(cu set *) passes the gated shape 'cu set x--anywayx'"
mkdir -p "$T_TMP/m/y"; sed 's/^| `gh pr merge \*` | gated | classifier | operator |/| `gh pr merge *` | gated | allow | operator |/' "$VD/gh.md" > "$T_TMP/m/y/gh.md"
t_has "gh.md: an operator row cannot be allow" "$(vr_check "$T_TMP/m/y/gh.md" "$T_TMP/real/settings.json")" \
  "gh.md: row gh pr merge *: actor operator but perm allow"
mkdir -p "$T_TMP/m/z"; { cat "$VD/mail.md"; printf '| `git push *` | write | allow | app | |\n'; } > "$T_TMP/m/z/mail.md"
t_has "mail.md: a git row is refused there" "$(vr_check "$T_TMP/m/z/mail.md" "$T_TMP/real/settings.json")" "mail.md: row git push *: names a CLI this register does not own"
mkdir -p "$T_TMP/m/w"; { cat "$VD/gh.md"; printf '| `gh * view *` | read | allow | app | |\n'; } > "$T_TMP/m/w/gh.md"
t_has "gh.md: an allow row that leads with a wildcard is refused" "$(vr_check "$T_TMP/m/w/gh.md" "$T_TMP/real/settings.json")" "gh.md: row gh * view *: an allow rule must start <cli> <subcommand>"
vr_tree "$T_TMP/t-w"; cp "$T_TMP/m/w/gh.md" "$T_TMP/t-w/contracts/verbs/gh.md"; vr_derive "$T_TMP/t-w" "$T_TMP/d-w"
t_has "floor-deny warns, naming the file, and skips it" "$(cat "$T_TMP/d-w/fd.log")" "verbs/gh.md: an allow row must start '<cli> <subcommand>' and carry no <>|;&\$, so it is skipped: gh * view *"
t_hasnt "and writes no such rule" "$(jq -r '.permissions.allow[]' "$T_TMP/d-w/settings.json")" "Bash(gh * view *)"

t_section "the planner's reader: who runs a command"
actor() { HARBOR_GATE_VERBS_OWN_ORG=acme sh "$RD" --actor "$@"; }
t_eq "pr merge is the operator's, in either org" "operator operator" "$(actor gh pr merge 12 -R acme/r --squash) $(actor gh pr merge 12 -R other/r --squash)"
t_eq "an approval is the operator's, either flag order" "operator operator" "$(actor gh pr review 5 --approve) $(actor gh pr review --approve 5)"
t_eq "a plain review is the App's on its own org (the longer approve row did not swallow it)" app "$(actor gh pr review 5 -c -R acme/r)"
t_eq "rerun, close and issue close are the operator's" "operator operator operator" \
  "$(actor gh run rerun 9 --failed) $(actor gh pr close 4) $(actor gh issue close 4)"
t_eq "create, edit and ready are the App's on its own org" "app app app" \
  "$(actor gh pr create -t x -R acme/r) $(actor gh pr edit 5 --base main -R acme/r) $(actor gh pr ready 5 -R acme/r)"
t_eq "and the operator's on another org's repo" "operator operator operator operator" \
  "$(actor gh pr create -t x -R other/r) $(actor gh pr edit 5 -R other/r) $(actor gh pr ready 5 --repo other/r) $(actor gh pr ready 5 --repo=other/r)"
t_eq "update-branch follows the org" "app operator" "$(actor gh pr update-branch 5 -R acme/r) $(actor gh pr update-branch 5 -R other/r)"
t_eq "--owner names the org when the command does not" "app operator" "$(actor --owner acme gh pr ready 5) $(actor --owner other gh pr ready 5)"
t_eq "the owner compares without case" app "$(actor --owner ACME gh pr ready 5)"
t_eq "a read is the App's in any org" app "$(actor gh pr view 5 -R other/r)"
t_eq "an own-org row with no owner to read says so" "owner?" "$(actor gh pr ready 5; true)"
t_exit "and exits 4" 4 env HARBOR_GATE_VERBS_OWN_ORG=acme sh "$RD" --actor gh pr ready 5
_me="$(sh -c '. "$1/library-log.sh"; repo_slug "$1"' sh "$T_ROOT/bin" 2>/dev/null | sed 's#/.*##')"
t_eq "the checkout's own owner is the default own org" app "$(sh "$RD" --actor --owner "${_me:-unset}" gh pr ready 5)"
t_eq "a bare verb matches its ' *' row" operator "$(actor gh pr merge)"
t_eq "a command no row names is unknown" unknown "$(actor gh nonesuch verb; true)"
t_exit "unknown exits 3" 3 sh "$RD" --actor gh nonesuch verb
t_eq "a cu verb is the App's" app "$(actor cu say --done 5 hi)"
t_exit "a call with no verb is a usage error" 2 sh "$RD" --actor gh

t_section "uninstall takes back exactly the rules the install derived"
mkdir -p "$T_TMP/rm/bin" "$T_TMP/rm/contracts"
cp "$T_ROOT"/bin/admission-remove.sh "$T_ROOT"/bin/admission-install.sh "$T_ROOT"/bin/deploy-runtime-install.sh "$T_ROOT"/bin/library-log.sh "$T_ROOT"/bin/deploy-install-lib.sh "$RD" "$T_TMP/rm/bin/" 2>/dev/null
cp -R "$VD" "$T_TMP/rm/contracts/verbs"
mkdir -p "$T_TMP/rm/cfg"
jq '.permissions.allow += ["Bash(ls *)"] | .permissions.ask += ["Bash(rm *)"]' "$T_TMP/real/settings.json" > "$T_TMP/rm/cfg/settings.json"
_nv="$(jq '[.permissions.allow[], .permissions.ask[] | select(test("^Bash\\((git|gh|cu|gmail-read|gmail-write|gcal-read|gcal-write) "))] | length' "$T_TMP/rm/cfg/settings.json")"
t_eq "the install wrote rules for every register" yes "$([ "$_nv" -gt 100 ] && echo yes || echo no)"
t_has "the dry run lists a rule from each register" "$(env -u CLAUDE_CONFIG_DIR sh "$T_TMP/rm/bin/admission-remove.sh" --dir "$T_TMP/rm/cfg" 2>&1)" "verb-register rule to remove: Bash(gcal-write *)"
t_exit "the uninstall succeeds" 0 env -u CLAUDE_CONFIG_DIR sh "$T_TMP/rm/bin/admission-remove.sh" --dir "$T_TMP/rm/cfg" --apply
t_eq "no register rule is left" 0 "$(jq '[.permissions.allow[]?, .permissions.ask[]? | select(test("^Bash\\((git|gh|cu|gmail-read|gmail-write|gcal-read|gcal-write) "))] | length' "$T_TMP/rm/cfg/settings.json")"
t_eq "a hand-written rule is kept" "Bash(ls *) Bash(rm *)" "$(jq -r '[.permissions.allow[]?, .permissions.ask[]?] | map(select(. == "Bash(ls *)" or . == "Bash(rm *)")) | sort | join(" ")' "$T_TMP/rm/cfg/settings.json")"

t_done
