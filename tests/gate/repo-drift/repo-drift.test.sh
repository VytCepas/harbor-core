#!/usr/bin/env sh
# bin/gate-repo-drift.sh against a stubbed gh (harbor#1418): declaration vs live per repo, each outcome seen red by
# mutation. The stub answers GETs only and fails on any other call, so "applies nothing" is a measured fact.
. "$(dirname "$0")/../../lib/core.sh"; t_init
FX="$T_TMP/fx"; GH="$T_TMP/gh"; mkdir -p "$FX"
cat > "$GH" <<'STUB'
#!/bin/sh
echo "$*" >> "$FX/calls"
[ "$1" = api ] || { echo "UNEXPECTED gh call: $*" >&2; exit 1; }
s="$(printf '%s' "$2" | cut -d/ -f2,3)"; d="$FX/$(printf '%s' "$s" | tr / _)"; rest="${2#repos/$s}"
[ -d "$d" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
case "$rest" in
  "") [ -f "$d/repo.fail" ] && { echo "gh: HTTP 502" >&2; exit 1; }; cat "$d/repo.json" ;;
  /rules/branches/main) cat "$d/rules.json" ;;
  "/contents/.agents/ship.conf?ref=main") [ -f "$d/ship" ] && { cat "$d/ship"; exit 0; }; echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
  /branches/main/protection)
    case "$(cat "$d/prot" 2>/dev/null)" in
      403) echo "gh: Resource not accessible by integration (HTTP 403)" >&2; exit 1 ;;
      ""|404) echo "gh: Branch not protected (HTTP 404)" >&2; exit 1 ;;
      *) cat "$d/prot" ;;
    esac ;;
  /rulesets/*) f="$d/rs-${rest##*/}.json"; [ -f "$f" ] && cat "$f" || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; } ;;
  *) echo "UNEXPECTED gh call: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$GH"
run() { FX="$FX" HARBOR_TEST_GH="$GH" HARBOR_GATE_REPO_DRIFT_STATE="$T_TMP/state.tsv" sh "$T_ROOT/bin/gate-repo-drift.sh" "$@" 2>&1; }
rc() { FX="$FX" HARBOR_TEST_GH="$GH" HARBOR_GATE_REPO_DRIFT_STATE="$T_TMP/state.tsv" sh "$T_ROOT/bin/gate-repo-drift.sh" "$@" >/dev/null 2>&1; echo $?; }
# mk <owner/name> <SMR mask, - = off> <delete_branch_on_merge> <rules-json> [ship.conf text] [protection: 403 | 404 | json]
mk() {
  _d="$FX/$(printf '%s' "$1" | tr / _)"; rm -rf "$_d"; mkdir -p "$_d"
  jq -n --arg m "$2" --argjson del "$3" '{default_branch: "main", allow_squash_merge: ($m[0:1] == "S"), allow_merge_commit: ($m[1:2] == "M"),
    allow_rebase_merge: ($m[2:3] == "R"), delete_branch_on_merge: $del}' > "$_d/repo.json"
  printf '%s\n' "$4" > "$_d/rules.json"
  [ -z "${5:-}" ] || printf '%s\n' "$5" > "$_d/ship"
  [ -z "${6:-}" ] || printf '%s\n' "$6" > "$_d/prot"
}
rule() { # <approvals> <code-owner true|false> <ruleset id> [methods json]
  printf '[{"type":"pull_request","ruleset_source_type":"Repository","ruleset_id":%s,"parameters":{"required_approving_review_count":%s,"require_code_owner_review":%s,"allowed_merge_methods":%s}}]' "$3" "$1" "$2" "${4:-[\"merge\",\"squash\",\"rebase\"]}"
}
DECL='repo o/a
method merge-commit
review 0 code-owner
delete-branch yes'
ID="[check:gate.repo-drift]"
reset() { rm -rf "$FX" "$T_TMP/state.tsv"; mkdir -p "$FX"; }

t_section "clean: the declaration equals the live repo"
reset; mk o/a -M- true "$(rule 0 true 11 '["merge"]')" "$DECL"
OUT="$(run --print --repo o/a)"
t_has "the repo is listed clean" "$OUT" "o/a clean"
t_hasnt "no finding" "$OUT" "o/a drift"
t_hasnt "...nor undeclared, unreadable or unread" "$OUT" "o/a un"
t_eq "exit 0" 0 "$(rc --print --repo o/a)"

t_section "drift: the method the repo allows is wider than the one declared"
reset; mk o/a SM- true "$(rule 0 true 11)" "$DECL"
OUT="$(run --print --repo o/a)"
t_has "named as drift with both sides" "$OUT" "o/a drift method: declared merge, live allows: squash merge"
t_has "the exact operator command" "$OUT" "fix: gh api -X PATCH repos/o/a -F allow_squash_merge=false"
t_hasnt "the declared method is not turned off" "$OUT" "allow_merge_commit=false"
t_eq "exit 1" 1 "$(rc --print --repo o/a)"
reset; mk o/a SM- true "$(rule 0 true 11 '["merge"]')" "$DECL"
t_has "control: a rule that narrows the methods is not drift" "$(run --print --repo o/a)" "o/a clean"
reset; mk o/a S-- true "$(rule 0 true 11)" "$DECL"
t_has "the declared method is off: turn it on" "$(run --print --repo o/a)" "-F allow_squash_merge=false -F allow_merge_commit=true"

t_section "drift: delete-branch"
reset; mk o/a -M- false "$(rule 0 true 11 '["merge"]')" "$DECL"
OUT="$(run --print --repo o/a)"
t_has "named" "$OUT" "o/a drift delete-branch: declared yes, live delete_branch_on_merge is false"
t_has "the command" "$OUT" "gh api -X PATCH repos/o/a -F delete_branch_on_merge=true"

t_section "drift: review, fixed by editing the ruleset that holds it without dropping its other fields"
reset; mk o/a -M- true "$(rule 0 true 11 '["merge"]')" "repo o/a
method merge-commit
review 1
delete-branch yes"
printf '{"name":"wall","target":"branch","enforcement":"active","conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},"rules":[{"type":"pull_request","parameters":{"required_approving_review_count":0,"require_code_owner_review":true,"dismiss_stale_reviews_on_push":true,"allowed_merge_methods":["merge"]}},{"type":"deletion"}]}\n' > "$FX/o_a/rs-11.json"
OUT="$(run --print --repo o/a)"
t_has "named" "$OUT" "o/a drift review: declared 1, live requires 0 code-owner"
t_has "a PUT to that ruleset" "$OUT" "| gh api -X PUT repos/o/a/rulesets/11 --input -"
t_has "...with the declared count" "$OUT" '"required_approving_review_count":1'
t_has "...and the code-owner flag the declaration keeps off" "$OUT" '"require_code_owner_review":false'
t_has "...and the rules it does not touch" "$OUT" '{"type":"deletion"}'
t_has "...and the conditions" "$OUT" '"conditions":{"ref_name"'

t_section "undeclared: no ship.conf and no row"
reset; mk o/a -M- true "$(rule 0 true 11 '["merge"]')"
OUT="$(run --print --repo o/a)"
t_has "listed, with the keys" "$OUT" "o/a undeclared declaration: no ship.conf or --declared row for: method, delete-branch, review"
t_hasnt "never clean" "$OUT" "o/a clean"
t_eq "exit 1" 1 "$(rc --print --repo o/a)"
printf 'o/a\tmethod\tmerge-commit\no/a\treview\t0 code-owner\no/a\tdelete-branch\tyes\n' > "$T_TMP/decl.tsv"
t_has "control: --declared rows declare it" "$(run --print --repo o/a --declared "$T_TMP/decl.tsv")" "o/a clean"
mk o/a -M- true "$(rule 0 true 11 '["merge"]')" "repo o/a
method merge-commit"
OUT="$(run --print --repo o/a)"
t_has "a ship.conf that lacks keys is undeclared for just those" "$OUT" "for: delete-branch, review"

t_section "unreadable: classic protection answers 403, so the review rule is never read as clean"
reset; mk o/a -M- true "[]" "$DECL" 403
OUT="$(run --print --repo o/a)"
t_has "named unreadable" "$OUT" "o/a unreadable review: classic branch protection answers 403"
t_hasnt "not clean" "$OUT" "o/a clean"
t_has "the migration: a ruleset carrying the declared review" "$OUT" '"required_approving_review_count":0'
t_has "...only the declared method allowed" "$OUT" '"allowed_merge_methods":["merge"]'
t_has "...then the classic rule goes" "$OUT" "gh api -X DELETE repos/o/a/branches/main/protection"
t_eq "the ruleset is created before the classic rule is removed" "POST" "$(printf '%s\n' "$OUT" | grep -oE 'X (POST|DELETE)' | head -n 1 | cut -c3-)"
t_eq "exit 3, not a drift" 3 "$(rc --print --repo o/a)"
reset; mk o/a -M- true "[]" "$DECL" 404
t_has "control: not protected at all is readable: no review required, so a code-owner declaration drifts" "$(run --print --repo o/a)" "o/a drift review: declared 0 code-owner, live requires 0"
reset; mk o/a -M- true "[]" "repo o/a
method merge-commit
review none
delete-branch yes" 404
t_has "control: and 'none' matches it" "$(run --print --repo o/a)" "o/a clean"
reset; mk o/a -M- true "[]" "$DECL" '{"required_pull_request_reviews":{"required_approving_review_count":0,"require_code_owner_reviews":true}}'
t_has "control: classic protection the caller CAN read is compared" "$(run --print --repo o/a)" "o/a clean"

t_section "unread: a gh call that fails is never a pass"
reset; mk o/a -M- true "$(rule 0 true 11 '["merge"]')" "$DECL"; touch "$FX/o_a/repo.fail"
OUT="$(run --print --repo o/a)"
t_has "named" "$OUT" "o/a unread repo: could not read the repo"
t_eq "exit 3" 3 "$(rc --print --repo o/a)"
reset; mk o/a SM- true "$(rule 0 true 11)" "$DECL"; mk o/b -M- true "$(rule 0 true 12 '["merge"]')" "$DECL"; touch "$FX/o_b/repo.fail"
t_eq "unread wins over drift in the exit code" 3 "$(rc --print --repo o/a --repo o/b)"

t_section "every line names its check"
reset; mk o/a SM- false "$(rule 0 true 11)" "$DECL"; mk o/c -M- true "[]" "$DECL" 403
OUT="$(run --print --repo o/a --repo o/c)"
t_eq "no line without the id" 0 "$(printf '%s\n' "$OUT" | grep -vc -F "$ID")"
t_eq "...in delta mode too" 0 "$(run --repo o/a --repo o/c | grep -vc -F "$ID")"

t_section "the delta: a new finding in full, a standing one as its age, a fixed one gone"
reset; mk o/a SM- true "$(rule 0 true 11)" "$DECL"
OUT="$(run --repo o/a)"
t_has "first run: shown in full with its command" "$OUT" "-F allow_squash_merge=false"
OUT="$(run --repo o/a)"
t_has "second run: standing, with an age" "$OUT" "o/a drift method: standing 0d"
t_hasnt "...and not reprinted" "$OUT" "-F allow_squash_merge=false"
awk -F'\t' '{ print $1 "\t" ($2 - 3 * 86400) }' "$T_TMP/state.tsv" > "$T_TMP/aged" && cp "$T_TMP/aged" "$T_TMP/state.tsv"
t_has "the age grows" "$(run --repo o/a)" "standing 3d"
mk o/a -M- true "$(rule 0 true 11 '["merge"]')" "$DECL"
run --repo o/a >/dev/null
t_eq "fixed: it leaves the state" 0 "$(grep -c . "$T_TMP/state.tsv")"
mk o/a SM- true "$(rule 0 true 11)" "$DECL"
t_has "...and when it comes back it is new again" "$(run --repo o/a)" "-F allow_squash_merge=false"
reset; mk o/a SM- true "$(rule 0 true 11)" "$DECL"
run --print --repo o/a >/dev/null
t_eq "--print writes no state" 0 "$([ -e "$T_TMP/state.tsv" ] && echo 1 || echo 0)"

t_section "--commands: only what can be pasted, on stdout, in run order"
reset; mk o/a SM- false "$(rule 0 true 11)" "$DECL"
OUT="$(FX="$FX" HARBOR_TEST_GH="$GH" HARBOR_GATE_REPO_DRIFT_STATE="$T_TMP/state.tsv" sh "$T_ROOT/bin/gate-repo-drift.sh" --commands --repo o/a 2>/dev/null)"
t_eq "the two fixes, nothing else" "gh api -X PATCH repos/o/a -F allow_squash_merge=false|gh api -X PATCH repos/o/a -F delete_branch_on_merge=true" "$(printf '%s\n' "$OUT" | paste -sd'|' -)"

t_section "it applies nothing: the stub answers GETs only and the tool made no other call"
reset; mk o/a SM- false "$(rule 0 true 11)" "$DECL"; : > "$FX/calls"
run --print --repo o/a >/dev/null
t_eq "no call with -X" 0 "$(grep -c -e ' -X ' -e '^api -X' "$FX/calls")"

t_section "the repo list comes from a registry, and a repo it cannot map is unread"
reset; mk o/a -M- true "$(rule 0 true 11 '["merge"]')" "$DECL"
mkdir -p "$T_TMP/co"; git -C "$T_TMP/co" init -q && git -C "$T_TMP/co" remote add origin https://github.com/o/a.git
printf 'alpha\t%s\nghost\t%s/none\n' "$T_TMP/co" "$T_TMP" > "$T_TMP/reg.tsv"
OUT="$(run --print --registry "$T_TMP/reg.tsv")"
t_has "a registry row is judged by its checkout's origin" "$OUT" "o/a clean"
t_has "a row with no checkout is unread" "$OUT" "ghost unread registry: no checkout at its registry path"
t_eq "exit 3" 3 "$(rc --print --registry "$T_TMP/reg.tsv")"

t_section "a registry row with no origin is a parent folder: its child checkouts are judged, each GitHub repo once"
reset; mk o/a -M- true "$(rule 0 true 11 '["merge"]')" "$DECL"
for c in A A-wt B; do mkdir -p "$T_TMP/par/$c"; git -C "$T_TMP/par/$c" init -q; done
git -C "$T_TMP/par/A" remote add origin https://github.com/o/a.git; git -C "$T_TMP/par/A-wt" remote add origin https://github.com/o/a.git
mkdir -p "$T_TMP/empty"; printf 'parent\t%s\nbare\t%s\n' "$T_TMP/par" "$T_TMP/empty" > "$T_TMP/reg2.tsv"
OUT="$(run --print --registry "$T_TMP/reg2.tsv")"
t_eq "the child's repo is judged once, though two checkouts carry it" 1 "$(printf '%s\n' "$OUT" | grep -c 'o/a clean')"
t_has "a folder with no origin and no child checkout is unread" "$OUT" "bare unread registry: no GitHub origin"
t_hasnt "the parent itself is not reported unread" "$OUT" "parent unread"

t_section "usage"
t_eq "an unknown flag is 2" 2 "$(rc --nope)"
t_eq "a malformed --repo is 2" 2 "$(rc --repo notaslug)"
t_eq "an unreadable --registry is 2" 2 "$(rc --registry "$T_TMP/none.tsv")"
t_done
