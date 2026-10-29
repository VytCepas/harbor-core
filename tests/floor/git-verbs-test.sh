#!/usr/bin/env sh
# git verbs (harbor#1291): CONTRACTS/git-verbs.md is the one list of git shapes. This holds it to the three things
# that must agree with it: the allow/ask/deny rules bin/floor-deny.sh actually WRITES (run, not read), guard-bash's
# read-only git list, and the floor rule ids it cites. And it refuses any derived allow rule that matches a gated
# shape with no ask, deny or floor block over it. Every disagreement kind is driven red below on a mutated copy.
. "$(dirname "$0")/../lib/core.sh"; t_init
REG="$T_ROOT/CONTRACTS/git-verbs.md"; GB="$T_ROOT/bin/guard-bash.sh"; GD="$T_ROOT/bin/guard-destroy.sh"
TAB="$(printf '\t')"

gv_rows() { # <register> -> spelling, class, perm, floor, calls, refused (tab-separated, one row per line)
  awk -F'|' '/^\| `/ { for (i = 2; i <= 7; i++) { v = $i; gsub(/^[ \t`]+|[ \t`]+$/, "", v); printf "%s%s", v, (i < 7 ? "\t" : "\n") } }' "$1"
}
gv_ro() { # <guard-bash> -> the subcommands _git_seg_is_ro returns 0 for, one per line
  awk '/^_git_seg_is_ro\(\)/ { f = 1 } f && /\) return 0 ;;/ { sub(/^[ \t]+/, ""); sub(/\).*/, ""); n = split($0, a, "|"); for (i = 1; i <= n; i++) print a[i]; exit }' "$1"
}
gv_glob() { # <rule body> <command> -> 0 iff the rule matches it as a permission rule does; a trailing " *" also matches nothing
  # shellcheck disable=SC2254
  case "$2" in $1) return 0 ;; esac
  case "$1" in *' *') case "$2" in ${1%' *'}) return 0 ;; esac ;; esac
  return 1
}
gv_derive() { # <tree> <dir> -> <dir>/settings.json as floor-deny --apply writes it into an empty one
  mkdir -p "$2"; printf '{"permissions":{"allow":[],"deny":[]}}\n' > "$2/settings.json"
  CLAUDE_CONFIG_DIR="$2" sh "$1/bin/floor-deny.sh" --apply --dir "$2" > "$2/fd.log" 2>&1; echo "$?" > "$2/fd.rc"
}
gv_tree() { # <dir> -> a tree holding floor-deny and the libraries it sources, with a copy of the register
  mkdir -p "$1/bin" "$1/CONTRACTS"
  cp "$T_ROOT/bin/floor-deny.sh" "$T_ROOT/bin/log-lib.sh" "$T_ROOT/bin/install-lib.sh" "$1/bin/"
  cp "$REG" "$1/CONTRACTS/git-verbs.md"
}
# Spellings no allow rule may pass unguarded. The register's own gated rows are checked too; these are the
# attack shapes beside them: abbreviations, a flag after the subcommand, a config injection behind -C.
PROBES='git push --force origin feat
git push --force-with-lease origin feat
git push origin --delete feat
git push origin :feat
git push origin +feat
git push --no-verify origin feat
git push origin main
git reset --hard HEAD
git clean -fdx
git stash drop
git stash clear
git reflog expire --all
git worktree remove --force ../x
git branch -D feat
git checkout -- .
git restore .
git switch -c x --discard-changes
git switch -c x --disc
git switch -c x -f
git switch -c x --force
git fetch --upload-pack=sh origin
git fetch --upl=sh origin
git fetch origin --upload-pack sh
git fetch origin +main:main
git worktree add -B main ../x
git worktree add ../x -B main origin/main
git ls-remote -u sh origin
git -c core.pager=sh log
git -C /x -c core.pager=sh log
git diff --output=x
git log --outp=x
git grep -Osh x
git config core.pager sh
git config --global alias.x !sh'

gv_check() { # <register> <guard-bash> <guard-destroy> <settings.json> -> one line per disagreement, nothing when they agree
  _w="$T_TMP/chk"; rm -rf "$_w"; mkdir -p "$_w"
  gv_rows "$1" > "$_w/rows"
  [ -s "$_w/rows" ] || echo "the register has no rows"
  awk -F'\t' '
    $2 !~ /^(read|write|gated)$/ { print "row " $1 ": class is " $2 }
    $3 !~ /^(builtin|allow|ask|deny|classifier)$/ { print "row " $1 ": perm is " $3 }
    $4 !~ /^(ro|-|block:[a-z-]+|ask:[a-z-]+)$/ { print "row " $1 ": floor is " $4 }
    $5 !~ /^[0-9]+$/ || $6 !~ /^[0-9]+$/ { print "row " $1 ": calls and refused must be counts" }
    ($3 == "allow" || $3 == "ask") && ($1 !~ /^git [a-z][a-z-]*( |$)/ || $1 ~ /[<>|;&$]/) {
      print "row " $1 ": an " $3 " rule must start git <subcommand> and name no <argument>" }
    seen[$1]++ == 1 { print "row " $1 ": listed twice" }' "$_w/rows"
  # guard-bash's read-only list and the floor column
  gv_ro "$2" > "$_w/ro"
  [ -s "$_w/ro" ] || echo "guard-bash: no read-only git list in _git_seg_is_ro"
  awk -F'\t' 'NR == FNR { G[$1] = 1; next }
    { split($1, w, " "); sc = (w[1] == "git" && w[2] !~ /^-/) ? w[2] : "" }
    $4 == "ro" && !(sc in G) { print "row " $1 ": says floor ro, but guard-bash does not list " sc " as read-only" }
    sc != "" && (sc in G) && $4 == "-" { print "row " $1 ": guard-bash lists " sc " as read-only, but the row says -" }
    $4 == "ro" { R[sc] = 1 }
    END { for (g in G) if (!(g in R)) print "guard-bash lists " g " as read-only, but no register row says floor ro for it" }' \
    "$_w/ro" "$_w/rows"
  # every cited floor rule exists
  awk -F'\t' '$4 ~ /^(block|ask):/ { print $4 }' "$_w/rows" | sort -u | while IFS=: read -r _k _r; do
    if [ "$_k" = block ]; then grep -Fq " $_r." "$2" || echo "floor block:$_r names no rule in guard-bash"
    else grep -Fq "RULE=\"$_r\"" "$3" || echo "floor ask:$_r names no rule in guard-destroy"; fi
  done
  # the rules floor-deny wrote, against the rows that imply them
  for _p in allow ask deny; do
    awk -F'\t' -v p="$_p" '$3 == p { print "Bash(" $1 ")" }' "$_w/rows" | sort -u > "$_w/want.$_p"
    jq -r --arg p "$_p" '.permissions[$p] // [] | .[] | select(startswith("Bash(git "))' "$4" | sort -u > "$_w/have.$_p"
    comm -23 "$_w/want.$_p" "$_w/have.$_p" | sed "s/^/register $_p row has no rule in settings.json: /"
    comm -13 "$_w/want.$_p" "$_w/have.$_p" | sed "s/^/settings.json $_p rule has no register row: /"
  done
  # no allow rule passes a gated shape unless an ask, a deny or a floor block outranks it
  { awk -F'\t' '$2 == "gated" { print $1 "\t" $4 }' "$_w/rows" | sed -e 's/<[^>]*>/x/g' -e 's/\*/x/g'
    printf '%s\n' "$PROBES" | sed "s/\$/$TAB-/"; } > "$_w/gated"
  sed -e 's/^Bash(//' -e 's/)$//' "$_w/have.allow" > "$_w/allow"
  sed -e 's/^Bash(//' -e 's/)$//' "$_w/have.ask" "$_w/have.deny" > "$_w/over"
  while IFS="$TAB" read -r _i _fl; do
    while IFS= read -r _a; do
      gv_glob "$_a" "$_i" || continue
      _ok=0; case "$_fl" in block:*) _ok=1 ;; esac
      while IFS= read -r _o; do gv_glob "$_o" "$_i" && _ok=1; done < "$_w/over"
      [ "$_ok" = 1 ] || echo "allow rule Bash($_a) passes the gated shape '$_i' with no ask, deny or floor block over it"
    done < "$_w/allow"
  done < "$_w/gated"
}

t_section "the register parses, and every class has rows"
gv_rows "$REG" > "$T_TMP/rows"
t_eq "more than 90 rows" yes "$([ "$(wc -l < "$T_TMP/rows")" -gt 90 ] && echo yes || echo no)"
for _c in read write gated; do
  t_eq "a $_c row exists" yes "$(cut -f2 "$T_TMP/rows" | grep -qx "$_c" && echo yes || echo no)"
done
t_eq "guard-bash's read-only list is found and non-trivial" yes "$([ "$(gv_ro "$GB" | wc -l)" -ge 10 ] && echo yes || echo no)"

t_section "the tree agrees: register, the rules floor-deny writes, its deny list and guard-bash"
gv_derive "$T_ROOT" "$T_TMP/real"
t_eq "floor-deny --apply exits 0" 0 "$(cat "$T_TMP/real/fd.rc")"
_n_allow="$(awk -F'\t' '$3 == "allow"' "$T_TMP/rows" | wc -l | tr -d ' ')"
t_eq "every allow row became an allow rule" "$_n_allow" "$(jq '[.permissions.allow[] | select(startswith("Bash(git "))] | length' "$T_TMP/real/settings.json")"
t_has "the dry-run log names a derived rule" "$(cat "$T_TMP/real/fd.log")" "allow rule (git-verbs): Bash(git ls-tree *)"
t_eq "no disagreement" "" "$(gv_check "$REG" "$GB" "$GD" "$T_TMP/real/settings.json")"

t_section "red: guard-bash drops a verb the register says is read-only"
sed 's/|ls-tree|/|/' "$GB" > "$T_TMP/gb-drop"
t_has "caught" "$(gv_check "$REG" "$T_TMP/gb-drop" "$GD" "$T_TMP/real/settings.json")" \
  "row git ls-tree *: says floor ro, but guard-bash does not list ls-tree as read-only"

t_section "red: guard-bash gains a read-only verb the register does not mark"
sed 's/grep|show|log|/grep|show|name-rev|log|/' "$GB" > "$T_TMP/gb-add"
t_has "caught" "$(gv_check "$REG" "$T_TMP/gb-add" "$GD" "$T_TMP/real/settings.json")" \
  "row git name-rev *: guard-bash lists name-rev as read-only, but the row says -"

t_section "red: settings.json lacks a rule the register implies, or carries one it does not"
jq '.permissions.allow -= ["Bash(git ls-tree *)"]' "$T_TMP/real/settings.json" > "$T_TMP/s-lack.json"
t_has "a missing allow rule" "$(gv_check "$REG" "$GB" "$GD" "$T_TMP/s-lack.json")" \
  "register allow row has no rule in settings.json: Bash(git ls-tree *)"
jq '.permissions.deny -= ["Bash(git push -f*main*)"]' "$T_TMP/real/settings.json" > "$T_TMP/s-deny.json"
t_has "a missing deny entry" "$(gv_check "$REG" "$GB" "$GD" "$T_TMP/s-deny.json")" \
  "register deny row has no rule in settings.json: Bash(git push -f*main*)"
jq '.permissions.allow += ["Bash(git push *)"]' "$T_TMP/real/settings.json" > "$T_TMP/s-extra.json"
_x="$(gv_check "$REG" "$GB" "$GD" "$T_TMP/s-extra.json")"
t_has "an allow rule with no row" "$_x" "settings.json allow rule has no register row: Bash(git push *)"
t_has "and the gated shape it lets through" "$_x" \
  "allow rule Bash(git push *) passes the gated shape 'git push origin --delete x' with no ask, deny or floor block over it"

t_section "red, end to end: a register row that would allow a gated shape is derived, then refused"
gv_tree "$T_TMP/tree"
sed 's/^| `git push \*` | write | classifier |/| `git push *` | write | allow |/' "$REG" > "$T_TMP/tree/CONTRACTS/git-verbs.md"
t_has "the mutation applied" "$(cat "$T_TMP/tree/CONTRACTS/git-verbs.md")" '| `git push *` | write | allow |'
gv_derive "$T_TMP/tree" "$T_TMP/mut"
t_has "floor-deny derived it" "$(jq -r '.permissions.allow[]' "$T_TMP/mut/settings.json")" "Bash(git push *)"
t_has "the check refuses it" "$(gv_check "$T_TMP/tree/CONTRACTS/git-verbs.md" "$GB" "$GD" "$T_TMP/mut/settings.json")" \
  "allow rule Bash(git push *) passes the gated shape 'git push --force-with-lease origin feat'"

t_section "red: an allow row that leads with a flag is skipped by floor-deny and named by the check"
gv_tree "$T_TMP/tree2"
printf '| `git -C * log *` | read | allow | - | 0 | 0 | |\n' >> "$T_TMP/tree2/CONTRACTS/git-verbs.md"
gv_derive "$T_TMP/tree2" "$T_TMP/mut2"
t_has "floor-deny warns and skips it" "$(cat "$T_TMP/mut2/fd.log")" \
  "git-verbs: an allow row must start 'git <subcommand>' and carry no <>|;&\$, so it is skipped: git -C * log *"
t_eq "and writes no such rule" 0 "$(jq '[.permissions.allow[] | select(. == "Bash(git -C * log *)")] | length' "$T_TMP/mut2/settings.json")"
t_has "the check names the row" "$(gv_check "$T_TMP/tree2/CONTRACTS/git-verbs.md" "$GB" "$GD" "$T_TMP/mut2/settings.json")" \
  "row git -C * log *: an allow rule must start git <subcommand> and name no <argument>"

t_section "red: a malformed row, and a floor rule id that does not exist"
sed -e 's/^| `git ls-tree \*` | read | allow |/| `git ls-tree *` | read | alow |/' \
    -e 's/| block:force-push | 0/| block:force-pusher | 0/' "$REG" > "$T_TMP/reg-bad.md"
_x="$(gv_check "$T_TMP/reg-bad.md" "$GB" "$GD" "$T_TMP/real/settings.json")"
t_has "a bad perm" "$_x" "row git ls-tree *: perm is alow"
t_has "a rule id guard-bash does not have" "$_x" "floor block:force-pusher names no rule in guard-bash"

t_done
