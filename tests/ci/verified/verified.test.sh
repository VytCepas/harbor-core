#!/usr/bin/env sh
# ci-verified.sh against a stubbed curl and a real throwaway repo (harbor#679). The stub serves each API path
# from a fixture file and fails on any path it was not given, so GitHub is never reached. The one `true` case
# is the control; every other case breaks exactly one condition and must come back `false`.
. "$(dirname "$0")/../../lib/core.sh"; t_init
CV="$T_ROOT/bin/ci-verified.sh"
FX="$T_TMP/fx"; R="$T_TMP/repo"; CURL="$T_TMP/curl"; mkdir -p "$FX" "$R"
cat > "$CURL" <<'STUB'
#!/bin/sh
for a in "$@"; do last="$a"; done
printf '%s\n' "$*" >> "$FX/calls.log"
p="${last#https://api.github.com/repos/o/r/}"
f="$FX/$(printf '%s' "$p" | tr '/?&=' '____')"
[ -f "$f" ] && { cat "$f"; exit 0; }
echo "curl: (22) The requested URL returned error: 404" >&2; exit 22
STUB
chmod +x "$CURL"

# B is main's previous tip; H is the PR head on top of it; S is the squash: H's tree, B's child.
git -C "$R" init -q; git -C "$R" config user.email t@t; git -C "$R" config user.name t
echo a > "$R/f"; git -C "$R" add f; git -C "$R" commit -qm B; B="$(git -C "$R" rev-parse HEAD)"
echo b > "$R/f"; git -C "$R" commit -qam H; H="$(git -C "$R" rev-parse HEAD)"; HT="$(git -C "$R" rev-parse "HEAD^{tree}")"
S="$(git -C "$R" commit-tree "$HT" -p "$B" -m S)"
key() { printf '%s' "$1" | tr '/?&=' '____'; }
fixtures() { # the control: every condition holds
  rm -f "$FX"/*
  printf '[{"number":7,"merge_commit_sha":"%s"}]' "$S" > "$FX/$(key "commits/$S/pulls")"
  printf '{"head":{"sha":"%s"}}' "$H" > "$FX/$(key "pulls/7")"
  printf '{"tree":{"sha":"%s"}}' "$HT" > "$FX/$(key "git/commits/$H")"
  printf '{"status":"ahead"}' > "$FX/$(key "compare/$B...$H")"
  printf '{"workflow_runs":[{"html_url":"https://x/run/1"}]}' \
    > "$FX/$(key "actions/workflows/governance.yml/runs?head_sha=$H&event=pull_request&status=success&per_page=1")"
}
cv() { ( cd "$R" && env FX="$FX" HARBOR_CURL="$CURL" GITHUB_REPOSITORY=o/r GH_TOKEN=sekrit GITHUB_OUTPUT="$FX/out" \
  sh "$CV" "$@" 2>&1 ) | grep '^verified=' ; }
cb() { ( cd "$R" && env FX="$FX" HARBOR_CURL="$CURL" GITHUB_REPOSITORY=o/r GH_TOKEN=sekrit GITHUB_OUTPUT="$FX/out" \
  sh "$CV" "$@" 2>&1 ) | grep '^base=' ; }   # harbor#1289: the merge-base line, "base=" when empty

t_section "verified only when the tree is one CI already passed"
fixtures; t_eq "control: same tree, head holds before, PR run passed" verified=true "$(cv "$S" "$B")"
t_eq "and it is written to GITHUB_OUTPUT for the workflow" verified=true "$(grep '^verified=' "$FX/out")"
t_hasnt "the token goes in a header, never a URL" "$(grep -o 'https://[^ ]*' "$FX/calls.log")" sekrit

fixtures; printf '[]' > "$FX/$(key "commits/$S/pulls")"
t_eq "a direct push (no PR) runs the suites" verified=false "$(cv "$S" "$B")"
fixtures; printf '[{"number":7,"merge_commit_sha":"%s"}]' "$B" > "$FX/$(key "commits/$S/pulls")"
t_eq "a PR whose merge commit is another sha runs the suites" verified=false "$(cv "$S" "$B")"
fixtures; printf '{"tree":{"sha":"%s"}}' "$(git -C "$R" rev-parse "$B^{tree}")" > "$FX/$(key "git/commits/$H")"
t_eq "a head tree that is not main's runs the suites" verified=false "$(cv "$S" "$B")"
fixtures; printf '{"status":"diverged"}' > "$FX/$(key "compare/$B...$H")"
t_eq "a head that did not hold main's previous tip runs the suites" verified=false "$(cv "$S" "$B")"
fixtures; printf '{"workflow_runs":[]}' \
  > "$FX/$(key "actions/workflows/governance.yml/runs?head_sha=$H&event=pull_request&status=success&per_page=1")"
t_eq "no passing PR run runs the suites" verified=false "$(cv "$S" "$B")"
fixtures; rm -f "$FX/$(key "pulls/7")"
t_eq "an API that does not answer runs the suites" verified=false "$(cv "$S" "$B")"
fixtures; t_eq "no previous tip (a new branch) runs the suites" verified=false "$(cv "$S" 0000000000000000000000000000000000000000)"
t_exit "a missing argument is a usage error" 2 sh "$CV" "$S"

# harbor#1289: base = merge-base(the PR head, before) when the PR is identified, else empty (the full pool).
t_section "base: the merged PR's merge-base, empty on any doubt"
MB="$(git -C "$R" rev-parse "$B")"; MAIN2="$(printf '%040d' 0 | tr 0 a)"
behind() { # a PR that branched at $B while main moved on: compare is diverged and names $B
  fixtures; printf '{"status":"diverged","merge_base_commit":{"sha":"%s"}}' "$MB" > "$FX/$(key "compare/$MAIN2...$H")"; }
behind
t_eq "behind-main merge: verified is false and base is the PR's merge-base" "verified=false base=$MB" \
  "$(cd "$R" && env FX="$FX" HARBOR_CURL="$CURL" GITHUB_REPOSITORY=o/r GH_TOKEN=x GITHUB_OUTPUT="$FX/out" sh "$CV" "$S" "$MAIN2" 2>&1 | grep -E '^(verified|base)=' | tr '\n' ' ' | sed 's/ $//')"
t_has "and it is written to GITHUB_OUTPUT for the workflow" "$(cat "$FX/out")" "base=$MB"
fixtures; printf '{"status":"ahead","merge_base_commit":{"sha":"%s"}}' "$MB" > "$FX/$(key "compare/$B...$H")"
t_eq "an up-to-date merge also names its merge-base" "base=$MB" "$(cb "$S" "$B")"
fixtures; printf '[]' > "$FX/$(key "commits/$S/pulls")"
t_eq "a direct push (no PR): base is empty" "base=" "$(cb "$S" "$B")"
fixtures; printf '[{"number":7,"merge_commit_sha":"%s"}]' "$B" > "$FX/$(key "commits/$S/pulls")"
t_eq "a PR whose merge commit is another sha: base is empty" "base=" "$(cb "$S" "$B")"
fixtures; rm -f "$FX/$(key "commits/$S/pulls")"
t_eq "the pulls API failing: base is empty" "base=" "$(cb "$S" "$B")"
fixtures; rm -f "$FX/$(key "pulls/7")"
t_eq "the PR head unreadable: base is empty" "base=" "$(cb "$S" "$B")"
fixtures; rm -f "$FX/$(key "compare/$B...$H")"
t_eq "the compare API failing: base is empty" "base=" "$(cb "$S" "$B")"
fixtures; printf '{"status":"diverged","merge_base_commit":{"sha":"abc123"}}' > "$FX/$(key "compare/$B...$H")"
t_eq "a merge-base that is not a full sha: base is empty" "base=" "$(cb "$S" "$B")"
fixtures; printf '{"status":"diverged","merge_base_commit":{"sha":"%s;rm"}}' "$MB" > "$FX/$(key "compare/$B...$H")"
t_eq "a merge-base with junk in it: base is empty" "base=" "$(cb "$S" "$B")"
fixtures; printf '{"status":"weird","merge_base_commit":{"sha":"%s"}}' "$MB" > "$FX/$(key "compare/$B...$H")"
t_eq "an unknown compare status: base is empty" "base=" "$(cb "$S" "$B")"
fixtures; t_eq "no previous tip: base is empty" "base=" "$(cb "$S" 0000000000000000000000000000000000000000)"
t_done
