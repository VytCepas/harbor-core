#!/usr/bin/env sh
# audit-review-config reader (harbor#1497, B3): defaults, each key, absent block, and base-vs-head: a PR-head edit changes nothing.
. "$(dirname "$0")/../../lib/core.sh"; t_init
BIN="$T_ROOT/bin/audit-review-config.sh"; R="$T_TMP/repo"
g() { git -C "$R" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
mkrepo() { rm -rf "$R"; mkdir -p "$R/.agents"; git -C "$R" init -q; }
commit() { g add -A; g commit -q -m "$1"; }   # <msg>
cfg() { printf '%s\n' "$1" > "$R/.agents/config.yaml"; }
rd() { sh "$BIN" read --base "$1" --repo "$R" 2>&1; }              # <rev>
dc() { _rev="$1"; _a="$2"; _n="$3"; shift 3; printf '%s\n' "$@" | sh "$BIN" decide --base "$_rev" --repo "$R" --author "$_a" --lines "$_n" 2>&1; }  # <rev> <author> <lines> <path>...

t_section "an absent file and an absent block give the defaults"
mkrepo; printf 'x\n' > "$R/f"; commit none
t_has "no config file: default tier" "$(rd HEAD)" 'tier=standard'
cfg 'context: repo'; commit noblock
_d="$(rd HEAD)"
t_has "no block: max-inline 10" "$_d" 'max-inline=10'
t_has "no block: dependabot excluded" "$_d" 'exclude-authors=dependabot[bot]'
t_has "no block: renovate excluded" "$_d" 'exclude-authors=renovate[bot]'
t_has "no block: verify on" "$_d" 'verify=on'
t_has "no block: quick keeps a lens" "$_d" 'quick-lenses=1'
cfg 'review: {}'; commit empty; t_eq "review: {} equals no block" "$_d" "$(rd HEAD)"

t_section "each key"
cfg 'review:
  tier: deep'; commit k1; t_has "tier" "$(rd HEAD)" 'tier=deep'
cfg 'review:
  max-inline: 0'; commit k2; t_has "max-inline 0 (summary only)" "$(rd HEAD)" 'max-inline=0'
cfg 'review:
  max-inline: 3'; commit k3; t_has "max-inline 3" "$(rd HEAD)" 'max-inline=3'
cfg 'review:
  quick-under-lines: 5'; commit k4; t_has "quick-under-lines" "$(rd HEAD)" 'quick-under-lines=5'
cfg 'review:
  standard-lenses: 2
  deep-lenses: 5
  quick-lenses: 1'; commit k5; _o="$(rd HEAD)"
t_has "standard-lenses" "$_o" 'standard-lenses=2'; t_has "deep-lenses" "$_o" 'deep-lenses=5'
cfg 'review:
  exclude-authors:
    - "svc-acct"
    - dependabot[bot]  # keeps brackets
  deep-paths:
    - .agents/*'; commit k6; _o="$(rd HEAD)"
t_has "login with brackets" "$_o" 'exclude-authors=dependabot[bot]'
t_has "quoted service account" "$_o" 'exclude-authors=svc-acct'
t_hasnt "an override drops the default authors" "$_o" 'renovate'
t_has "deep-paths" "$_o" 'deep-paths=.agents/*'
cfg 'review:
  exclude-authors: []
  docs-paths: []'; commit k7; _o="$(rd HEAD)"
t_hasnt "empty excludes: no author left" "$_o" 'exclude-authors='
t_hasnt "empty docs-paths: no default left" "$_o" 'docs-paths='
t_has "empty lists leave other defaults" "$_o" 'generated-paths=*.lock'
cfg 'review:
  verify: off'; commit k8; t_exit "verify off is refused by the reader" 1 sh "$BIN" read --base HEAD --repo "$R"
t_exit "an unknown rev is a usage error" 2 sh "$BIN" read --base nosuchrev --repo "$R"
t_exit "no --base is a usage error" 2 sh "$BIN" read --repo "$R"
t_exit "a flag-shaped base is refused" 2 sh "$BIN" read --base --output=x --repo "$R"

t_section "decide, table-driven"
cfg 'review:
  tier: standard
  quick-under-lines: 20
  exclude-authors:
    - dependabot[bot]
    - svc-acct
  docs-paths:
    - docs/*
    - "*.md"
  generated-paths:
    - "*.lock"
  deep-paths:
    - .agents/*'; commit table
row() { _l="$1"; _w="$2"; _rev="$3"; _a="$4"; _n="$5"; shift 5; t_eq "$_l" "$_w" "$(dc "$_rev" "$_a" "$_n" "$@" | tr '\t' ' ')"; }
row "excluded bot author"          'skip author' HEAD 'dependabot[bot]' 500 src/a.sh
row "excluded service account"     'skip author' HEAD svc-acct 500 src/a.sh
row "the harbor app is reviewed"   'review tier=standard lenses=4 verify=on max-inline=10' HEAD 'harbor-claude[bot]' 500 src/a.sh
row "a similar login is not excluded" 'review tier=standard lenses=4 verify=on max-inline=10' HEAD dependabot 500 src/a.sh
row "docs-only goes quick"         'review tier=quick lenses=1 verify=on max-inline=10' HEAD alice 500 docs/a.txt README.md
row "docs plus code stays standard" 'review tier=standard lenses=4 verify=on max-inline=10' HEAD alice 500 docs/a.txt src/a.sh
row "small diff goes quick"        'review tier=quick lenses=1 verify=on max-inline=10' HEAD alice 5 src/a.sh
row "deep path goes deep"          'review tier=deep lenses=6 verify=on max-inline=10' HEAD alice 5 src/a.sh .agents/x.tsv
row "generated-only is skipped"    'skip generated' HEAD alice 500 a.lock b.lock
row "generated plus code is reviewed" 'review tier=standard lenses=4 verify=on max-inline=10' HEAD alice 500 a.lock src/a.sh
row "no files is skipped"          'skip no-files' HEAD alice 5
t_exit "decide needs --lines" 2 sh "$BIN" decide --base HEAD --repo "$R" --author alice

t_section "base versus head: a PR cannot silence its own review"
BASE="$(g rev-parse HEAD)"
cfg 'review:
  exclude-authors:
    - alice
  generated-paths:
    - "src/*"
  max-inline: 0'; commit prhead
t_eq "the working tree and head now differ from the base" 1 "$(git -C "$R" diff --quiet "$BASE" HEAD -- .agents/config.yaml && echo 0 || echo 1)"
row "head edit excludes alice: base still reviews her" 'review tier=standard lenses=4 verify=on max-inline=10' "$BASE" alice 500 src/a.sh
row "head edit marks src generated: base still reviews" 'review tier=standard lenses=4 verify=on max-inline=10' "$BASE" alice 500 src/a.sh
t_has "read at base keeps max-inline 10" "$(rd "$BASE")" 'max-inline=10'
t_has "read at head sees the edit (the rev is what counts)" "$(rd HEAD)" 'max-inline=0'
printf 'review:\n  max-inline: 1\n' > "$R/.agents/config.yaml"
t_has "an uncommitted working-tree edit is never read" "$(rd HEAD)" 'max-inline=0'
t_done
