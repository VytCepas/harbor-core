#!/usr/bin/env sh
# The memory store's two readers, memory.sh (engine and grep rungs) and memory-lint.sh, and
# the work-log reconciler memory-harvest.sh, against fixtures/memory (harbor#6: D1 D3 D7 K3).
# Staleness defects: harbor#216. Symlinked stores: harbor#608. Secret gate: harbor#81.
# HARBOR_REQUIRE_BUN=1 and HARBOR_REQUIRE_GITLEAKS=1 turn a missing tool into a failure.
LIVE_CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"  # read before t_init sandboxes it
# The caller's knobs too, before t_init clears every HARBOR_* (harbor#773). memory.sh reads the bun one.
MEM_BUN="${HARBOR_MEMORY_BUN:-}"; REQ_BUN="${HARBOR_REQUIRE_BUN:-0}"; REQ_GITLEAKS="${HARBOR_REQUIRE_GITLEAKS:-0}"
. "$(dirname "$0")/../lib/core.sh"; t_init
[ -z "$MEM_BUN" ] || { HARBOR_MEMORY_BUN="$MEM_BUN"; export HARBOR_MEMORY_BUN; }
FIX="$T_ROOT/fixtures/memory"; CORPUS="$FIX/corpus"; EXPECT="$FIX/expected.json"
MEM="$T_ROOT/bin/memory.sh"; LINT="$T_ROOT/bin/memory-lint.sh"; NOBUN=/nonexistent/bun
want() { jq -r "$1" "$EXPECT"; }
jqr() { printf '%s' "$1" | jq -r "$2" 2>/dev/null || echo PARSE_ERROR; }  # <json> <filter>
DSET='[.dangling[] | {path, line, dialect, target}]'; PSET='[.dead_paths[] | {path, line, cites}]'
W_NOTES="$(want '.corpus.notes_indexed')"; W_DANGLING="$(want '.dangling | length')"
W_DEADPATH="$(want '.dead_paths | length')"; W_COLLISION="$(want '.collisions | length')"
W_QUERY="$(want '.queries[0].query')"; W_GREP_COUNT="$(want '.grep_tier.count')"
seed() { # <repo-dir> <message> <date> — commit everything, back-dated
  git -C "$1" add . >/dev/null 2>&1
  GIT_AUTHOR_DATE="$3" GIT_COMMITTER_DATE="$3" git -C "$1" commit -qm "$2" >/dev/null 2>&1
}
repo() { mkdir -p "$1"; git -C "$1" init -q; git -C "$1" config user.email t@t; git -C "$1" config user.name t; }
note() { printf -- '---\ntitle: %s\n---\nNothing links anywhere.\n' "$2" > "$1"; }  # <path> <title>
stale_n() { sh "$LINT" --root "$1" --json --stale-days 30 2>/dev/null | jq -r "${2:-.stale}"; }
stalerows() { sh "$LINT" --root "$1" --stale-days 30 2>/dev/null | grep '^STALE ' | sed 's/ (.*//'; }
fingerprint() { find "$1" -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r p; do
    printf '%s %s\n' "$(wc -c < "$p" | tr -d ' ')" "${p#"$1"}"; done; }

# The top rung is a property of the host: bm25 with bun, grep without (harbor#165).
# No ~/.bun/bin fallback here: memory.sh resolves bun from PATH alone, and so must this.
BUN="$MEM_BUN"; [ -n "$BUN" ] || BUN="$(command -v bun 2>/dev/null || true)"
if [ -n "$BUN" ] && [ -x "$BUN" ]; then
  HAVE_BUN=1; TOP_TIER=bm25; TOP_COUNT="$(want '.queries[0].count')"; TOP_ID="$(want '.queries[0].top')"; TOP_FIELD='.results[0].slug'
else
  HAVE_BUN=0; TOP_TIER=grep; TOP_COUNT="$W_GREP_COUNT"; TOP_ID="$(want '.grep_tier.top_path')"; TOP_FIELD='.results[0].path'
fi

t_section "the front door, top rung on this host ($TOP_TIER)"
OUT="$(sh "$MEM" --root "$CORPUS" --json $W_QUERY 2>/dev/null)"
t_eq "top rung reports its tier" "$TOP_TIER" "$(jqr "$OUT" '.tier // "null"')"
t_eq "top rung best hit" "$TOP_ID" "$(jqr "$OUT" "$TOP_FIELD // \"null\"")"
t_eq "top rung result count" "$TOP_COUNT" "$(jqr "$OUT" '.count // "null"')"

t_section "the front door, rung 2: grep, with bun masked (D7)"
GOUT="$(HARBOR_MEMORY_BUN=$NOBUN sh "$MEM" --root "$CORPUS" --json $W_QUERY 2>/dev/null)"
t_has "rung 2 reports tier grep" "$GOUT" '"tier":"grep"'
t_eq "rung 2 result count" "$W_GREP_COUNT" "$(jqr "$GOUT" '.count // "null"')"

t_section "a query with no hits is a normal answer, not a failure"
t_exit "rung 1 zero-hit" 0 sh "$MEM" --root "$CORPUS" zznosuchtokenzz
t_exit "rung 2 zero-hit" 0 env HARBOR_MEMORY_BUN=$NOBUN sh "$MEM" --root "$CORPUS" zznosuchtokenzz

t_section "the grep rung respects the engine's scope"
# .agents/ is an L3 store and indexes/ the derived tier. The legacy query `scope` missed
# indexes/derived.md, so that negative could not fail; both fixtures carry `fixture note`.
t_has "the L3 fixture carries the query" "$(cat "$CORPUS/.agents/memory/hidden-note.md")" 'fixture note'
t_has "the derived-tier fixture carries the query" "$(cat "$CORPUS/indexes/derived.md")" 'fixture note'
SCOPE="$(HARBOR_MEMORY_BUN=$NOBUN sh "$MEM" --root "$CORPUS" fixture note 2>/dev/null)"
t_has "the in-scope note is found" "$SCOPE" 'TELOS/goals-probe.md'
t_hasnt "no hit inside an L3 .agents/ store" "$SCOPE" '.agents'
t_hasnt "no hit inside the derived indexes/ tier" "$SCOPE" 'indexes/'

t_section "the anti-rot lint reproduces the pinned answers"
LOUT="$(sh "$LINT" --root "$CORPUS" --json 2>/dev/null)"
t_eq "lint note count" "$W_NOTES" "$(jqr "$LOUT" '.notes // "null"')"
t_eq "lint dangling count" "$W_DANGLING" "$(jqr "$LOUT" '.dangling | length')"
t_eq "lint dead-path count" "$W_DEADPATH" "$(jqr "$LOUT" '.dead_paths | length')"
t_eq "lint collision count" "$W_COLLISION" "$(jqr "$LOUT" '.collisions | length')"
# Both readers are held to expected.json, never to each other: two can drift together.
t_eq "lint dangling set is expected.json's" "$(jq -Sc "$DSET" "$EXPECT")" "$(printf '%s' "$LOUT" | jq -Sc "$DSET")"
t_eq "lint dead-path set is expected.json's" "$(jq -Sc "$PSET" "$EXPECT")" "$(printf '%s' "$LOUT" | jq -Sc "$PSET")"

t_section "--strict fails on a rotten store and passes on a healthy one"
t_exit "strict on the deliberately rotten fixture" 1 sh "$LINT" --root "$CORPUS" --strict
CLEAN="$T_TMP/clean"; mkdir -p "$CLEAN"
printf -- '---\ntitle: Alpha\nrelated: [beta]\n---\nLinks to [[beta]] and cites [a sibling](./beta.md).\n' > "$CLEAN/alpha.md"
printf -- '---\ntitle: Beta\n---\nNo outbound links at all.\n' > "$CLEAN/beta.md"
t_exit "strict on a healthy store" 0 sh "$LINT" --root "$CLEAN" --strict

t_section "staleness reports but never fails the gate"
STALEDIR="$T_TMP/stale"; repo "$STALEDIR"; note "$STALEDIR/ancient.md" Ancient
seed "$STALEDIR" seed 2001-01-01T00:00:00
t_eq "an old note is reported as stale" 1 "$(stale_n "$STALEDIR")"
t_exit "staleness alone never fails --strict" 0 sh "$LINT" --root "$STALEDIR" --strict --stale-days 30

t_section "the stale rows come in the sorted note-list order"
# zulu/alpha/mike: creation, awk-hash and sorted order all differ. Text mode, since JSON has only a count.
MULTI="$T_TMP/stale-multi"; repo "$MULTI"
for _n in zulu alpha mike; do note "$MULTI/$_n.md" "$_n"; done
seed "$MULTI" seed 2001-01-01T00:00:00
_m1="$(stalerows "$MULTI")"; _m2="$(stalerows "$MULTI")"
t_eq "all three old notes are reported" 3 "$(printf '%s\n' "$_m1" | grep -c '^STALE ')"
t_eq "the stale order is deterministic" "$_m1" "$_m2"
t_eq "the stale order is the sorted note-list order, not awk hash order" "$(printf '%s\n' "$_m1" | LC_ALL=C sort)" "$_m1"

t_section "harbor#216 defect 1: a store nested below its git root"
# Built here, not the corpus: on the corpus the verdict depends on the tree being a checkout.
NESTED="$T_TMP/nested"; repo "$NESTED"; mkdir -p "$NESTED/sub/store"
for _n in one two three; do note "$NESTED/sub/store/$_n.md" "$_n"; done
seed "$NESTED" seed 2001-01-01T00:00:00
t_eq "a nested store is still git_backed" true "$(stale_n "$NESTED/sub/store" .git_backed)"
t_eq "a nested store still measures staleness" 3 "$(stale_n "$NESTED/sub/store")"

t_section "harbor#216 defects 2-4: quoted names, a trailing slash, a header-shaped filename"
QP="$T_TMP/quotepath"; repo "$QP"
for _n in plain 'with space' 'café' 'naïve note'; do note "$QP/$_n.md" "$_n"; done
seed "$QP" seed 2001-01-01T00:00:00
t_eq "all four notes are measured, non-ASCII included" 4 "$(stale_n "$QP")"
t_eq "a trailing slash on --root changes nothing" 4 "$(stale_n "$QP/")"
printf 'not a note\n' > "$QP/C1700000000"; printf -- '---\ntitle: Fifth\n---\nNothing.\n' > "$QP/fifth.md"
seed "$QP" second 2001-01-02T00:00:00
t_eq "a C<digits> filename does not fabricate any note's age" 5 "$(stale_n "$QP")"

t_section "a note git has never seen has no age"
printf -- '---\ntitle: Uncommitted\n---\nNothing.\n' > "$MULTI/never-committed.md"
_m3="$(stalerows "$MULTI")"
t_eq "a note with no commit changes no stale row" "$_m1" "$_m3"
t_hasnt "a note git has never seen is not reported stale" "$_m3" 'never-committed'

t_section "the engine writes nothing, anywhere"
BEFORE_C="$(fingerprint "$CORPUS")"; BEFORE_H="$(fingerprint "$CLAUDE_CONFIG_DIR")"
sh "$MEM" --root "$CORPUS" $W_QUERY >/dev/null 2>&1
sh "$MEM" --root "$CORPUS" stats >/dev/null 2>&1
sh "$LINT" --root "$CORPUS" >/dev/null 2>&1
t_eq "the corpus is byte-identical after a search" "$BEFORE_C" "$(fingerprint "$CORPUS")"
t_eq "no file appeared under the config dir" "$BEFORE_H" "$(fingerprint "$CLAUDE_CONFIG_DIR")"

t_section "the answer does not depend on the caller's working directory"
# A glob-shaped query must never expand against cwd (it once gave 7 results in one dir, 1 in another).
from() { ( cd "$CORPUS/$1" && shift && "$@" 2>/dev/null ) ; }  # <corpus-subdir> <cmd…>
t_eq "engine rung: a glob-shaped query is not expanded against cwd" \
  "$(from KNOWLEDGE/Ideas sh "$MEM" --root "$CORPUS" --json '*.md')" "$(from assets sh "$MEM" --root "$CORPUS" --json '*.md')"
t_eq "grep rung: a glob-shaped query is not expanded against cwd" \
  "$(from KNOWLEDGE/Ideas env HARBOR_MEMORY_BUN=$NOBUN sh "$MEM" --root "$CORPUS" --json '*.md')" \
  "$(from assets env HARBOR_MEMORY_BUN=$NOBUN sh "$MEM" --root "$CORPUS" --json '*.md')"
t_eq "lint: findings do not depend on cwd" \
  "$(from KNOWLEDGE/Ideas sh "$LINT" --root "$CORPUS" --json)" "$(from assets sh "$LINT" --root "$CORPUS" --json)"

t_section "the same question twice gives the same answer"
t_eq "two identical invocations agree" "$(sh "$MEM" --root "$CORPUS" --json $W_QUERY 2>/dev/null)" \
  "$(sh "$MEM" --root "$CORPUS" --json $W_QUERY 2>/dev/null)"

t_section "D3: retrieval survives a junk derived index"
JUNK="$T_TMP/junk"; cp -R "$CORPUS" "$JUNK"; mkdir -p "$JUNK/indexes"
printf 'not a real index\n' > "$JUNK/indexes/bm25.index"
top2() { sh "$MEM" --root "$1" --json $W_QUERY 2>/dev/null | jq -Sc '.results[0].slug, .count'; }
t_eq "a stray derived index changes nothing" "$(top2 "$CORPUS")" "$(top2 "$JUNK")"

t_section "a query term is a query term, whatever it looks like"
# Before `--` existed, a leading-dash term killed the top rung with exit 2 while grep answered it.
t_exit "a leading-dash term does not abort the top rung" 0 sh "$MEM" --root "$CORPUS" -- '-1'
t_has "a leading-dash term survives as a query term" "$(sh "$MEM" --root "$CORPUS" --json -- '-1' 2>/dev/null)" '"query":"-1"'
t_eq "an argument containing a newline is not split into two terms" "$(printf 'fixture\nparquet')" \
  "$(sh "$MEM" --root "$CORPUS" --json "$(printf 'fixture\nparquet')" 2>/dev/null | jq -r '.query')"

t_section "an operation that could not run does not report success"
t_exit "graph with no runtime" 2 env HARBOR_MEMORY_BUN=$NOBUN sh "$MEM" --root "$CORPUS" graph graph-hub

t_section "flag values are validated by the front door, not the runtime"
t_exit "a non-numeric --limit is a usage error" 2 sh "$MEM" --root "$CORPUS" --limit abc fixture
t_exit "a non-numeric --stale-days is a usage error, not an interpreter crash" 2 sh "$LINT" --root "$CORPUS" --stale-days abc

t_section "an unclosed frontmatter block is body, in both readers"
UNC="$T_TMP/unclosed"; mkdir -p "$UNC"
printf -- '---\ntitle: Unclosed\nrelated:\n  - real-target\n\nBody prose, no closing fence.\n\nrelated:\n  - not-a-real-link\n' > "$UNC/unclosed.md"
printf -- '---\ntitle: Real\n---\nfine\n' > "$UNC/real-target.md"
t_eq "the sh lint fabricates no references from an unclosed block" "[]" \
  "$(sh "$LINT" --root "$UNC" --json 2>/dev/null | jq -c '[.dangling[].target]')"
t_exit "...and --strict does not fail a store over a missing dash" 0 sh "$LINT" --root "$UNC" --strict

t_section "the work-log reconciler backfills a missing record (D1)"
HV="$T_TMP/harvest"
mkdir -p "$HV/projects/-Users-someone" "$HV/projects/-private-tmp-scratch" "$HV/.helm-context"
repo "$HV/MEMORY"; printf 'ambient\n' > "$HV/.helm-context/probe"
for _t in -Users-someone/aaaa-1111 -Users-someone/bbbb-2222 -private-tmp-scratch/cccc-3333; do
  printf '{"type":"x"}\n' > "$HV/projects/$_t.jsonl"
done
harvest() { printf '{"session_id":"probe","cwd":"%s"}' "${1:-/tmp}" | CLAUDE_CONFIG_DIR="$HV" sh "$T_ROOT/hooks/memory-harvest/memory-harvest.sh" 2>/dev/null; }
records() { find "$HV/MEMORY/WORK" -type f -name "${1:-*}" 2>/dev/null | wc -l | tr -d ' '; }
wfp() { find "$HV/MEMORY/WORK" -type f | LC_ALL=C sort | while IFS= read -r p; do printf '%s %s\n' "$(wc -c < "$p" | tr -d ' ')" "$p"; done; }
harvest
t_eq "a session with no record gets one" 2 "$(records)"
t_has "a backfilled record declares its provenance in the frontmatter" \
  "$(cat "$(find "$HV/MEMORY/WORK" -name '*aaaa-1111.md' 2>/dev/null | head -1)" 2>/dev/null)" 'source: reconciled'

t_section "it is idempotent, which is what makes it safe on every Stop"
FP_BEFORE="$(wfp)"; harvest; harvest
t_eq "re-running writes nothing new" "$FP_BEFORE" "$(wfp)"

t_section "a host-token change does not re-harvest what another host recorded"
# The 2026-08-04 flip rewrote 38 records, all duplicates: "recorded anywhere" is the predicate.
HVH="$(find "$HV/MEMORY/WORK/sessions" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort | head -1)"
t_eq "a host partition exists to rename" yes "$([ -n "$HVH" ] && echo yes || echo no)"
mv "$HVH" "$HV/MEMORY/WORK/sessions/A-Previous-Host-Token" 2>/dev/null
HVN="$(records)"; harvest
t_eq "records under a previous host token are not re-harvested" "$HVN" "$(records)"

t_section "harness scratch sessions are not work"
t_eq "a /private/tmp scratch transcript is skipped" 0 "$(records '*cccc-3333*')"

t_section "it stands down only where the repo opts out (harbor#954)"
GOV="$T_TMP/governed"; mkdir -p "$GOV/.agents"; printf 'name: probe\n' > "$GOV/.agents/config.yaml"
OFF="$T_TMP/optout"; mkdir -p "$OFF/.agents"; printf 'name: probe\nworklog: off\n' > "$OFF/.agents/config.yaml"
rm -rf "$HV/MEMORY/WORK"; harvest "$GOV"
t_eq "inside a governed repo without worklog: off it still reconciles" 2 "$(records)"
rm -rf "$HV/MEMORY/WORK"; harvest "$OFF"
t_eq "inside a repo with worklog: off it writes nothing" 0 "$(records)"
rm -rf "$HV/MEMORY/WORK" "$HV/.helm-context"; mkdir -p "$HV/.helm-context"; harvest
t_eq "with no recorded context it still reconciles" 2 "$(records)"

t_section "a shell test in code is not a wikilink"
CODE="$T_TMP/codespans"; mkdir -p "$CODE"
cat > "$CODE/note.md" <<'MD'
---
title: Documents a shell fix
---
Inline first: the guard is `if [[ $? == 1 ]]` and it is wrong.

```sh
if [[ $? == 1 ]]; then echo "also not a wikilink"; fi
```

~~~
[[tilde-fenced-too]]
~~~

But [[a-real-link]] in prose still counts.
MD
t_eq "only the prose link is reported" '["a-real-link"]' "$(sh "$LINT" --root "$CODE" --json 2>/dev/null | jq -c '[.dangling[].target]')"

t_section "no silent caps"
printf 'ambient\n' > "$HV/.helm-context/probe"; rm -rf "$HV/MEMORY/WORK"
t_has "the cap says what it dropped" \
  "$(printf '{"session_id":"probe","cwd":"/tmp"}' | CLAUDE_CONFIG_DIR="$HV" HARBOR_HARVEST_CAP=1 sh "$T_ROOT/hooks/memory-harvest/memory-harvest.sh" 2>&1)" 'still unrecorded'

t_section "one writer, not two"
t_has "worklog-push.sh writes through floor_worklog_record" "$(cat "$T_ROOT/hooks/worklog-push/worklog-push.sh")" floor_worklog_record
t_has "memory-harvest.sh writes through floor_worklog_record" "$(cat "$T_ROOT/hooks/memory-harvest/memory-harvest.sh")" floor_worklog_record
t_eq "the hook never blocks the session" 0 "$(harvest >/dev/null 2>&1; echo $?)"

t_section "usage"
t_exit "--help" 0 sh "$MEM" --help
t_exit "no arguments is a usage error" 2 sh "$MEM"
t_exit "an unknown lint flag is a usage error" 2 sh "$LINT" --root "$CORPUS" --nonsense

t_section "nothing touched the operator's real store"
t_eq "the suite ran against the sandbox config dir" "$T_TMP/cfg" "$CLAUDE_CONFIG_DIR"
t_eq "the config dir is not the live one" no "$([ "$CLAUDE_CONFIG_DIR" = "$LIVE_CFG" ] && echo yes || echo no)"

t_section "the Bun engine assertions (tools/memory/memory-engine.test.ts)"
if [ "$HAVE_BUN" -eq 1 ]; then
  ( cd "$T_ROOT" && HARBOR_MEMORY_FIXTURES="$FIX" "$BUN" tools/memory/memory-engine.test.ts ) > "$T_TMP/bun.log" 2>&1
  _rc=$?; sed 's/^/    /' "$T_TMP/bun.log"
  t_eq "memory-engine.test.ts passes" 0 "$_rc"
else
  t_eq "bun is absent, so HARBOR_REQUIRE_BUN must be off" 0 "$REQ_BUN"
  echo "memory-test: SKIPPED the engine assertions (no bun on PATH)"
fi

t_section "the work-log secret gate, red and green (harbor#81)"
if ! command -v gitleaks >/dev/null 2>&1; then
  t_eq "gitleaks is absent, so HARBOR_REQUIRE_GITLEAKS must be off" 0 "$REQ_GITLEAKS"
  echo "memory-test: SKIPPED the work-log secret gate (no gitleaks on PATH)"
else
  GLT="$T_TMP/gl"; GLR="$GLT/worklog"; REC="$GLR/WORK/sessions/testhost/2026-09-16.md"
  mkdir -p "$GLR/WORK/sessions/testhost" "$GLR/KNOWLEDGE"
  # Assembled, not written: a token-shaped literal here trips secret-to-disk and the repo's scan.
  TOK="ghp_$(printf '%s' 'a1B2c3D4e5F6g7H8i9J0kLmNoPqRsTuVwXyZ')"; _b=BEGIN; _p=PRIVATE; _k=KEY
  printf 'tok %s\n' "$TOK" > "$GLT/bare.md"
  t_exit "the fixture token is detectable out of band (else every row below is inert)" 1 \
    gitleaks dir --no-banner --exit-code 1 "$GLT"
  rm -f "$GLT/bare.md"; repo "$GLR"
  gl_stage() { ( cd "$GLR" && git reset -q
    for g in 'WORK/sessions/*/*.md' 'KNOWLEDGE/*.md' 'LEARNING/*.md' 'WISDOM/*.md' IDEAS.md README.md .gitignore; do
      git add -- "$g" >/dev/null 2>&1 || true; done ) >/dev/null 2>&1; }  # worklog-push.sh's allowlist
  gl_verdict() { if ( . "$T_ROOT/bin/guard-lib.sh" >/dev/null 2>&1; floor_gitleaks_staged "$GLR" >/dev/null 2>&1 ); then
    echo allow; else echo refuse; fi; }  # the shipped decision function, in a subshell
  printf '# session\n\nRan the suite.\n' > "$REC"; gl_stage
  t_eq "a clean work-log record" allow "$(gl_verdict)"
  printf '# session\n\nExported %s for the run.\n' "$TOK" > "$REC"; gl_stage
  t_eq "a provider token in WORK/sessions" refuse "$(gl_verdict)"
  printf '# note\n\n%s\nMIIBOgIBAAJBAKj\n' "-----$_b RSA $_p $_k-----" > "$GLR/KNOWLEDGE/leak.md"; gl_stage
  t_eq "a private-key header in KNOWLEDGE" refuse "$(gl_verdict)"
  printf '# session\n\nRan the suite.\n' > "$REC"; rm -f "$GLR/KNOWLEDGE/leak.md"; gl_stage
  t_eq "the same record once the secrets are gone" allow "$(gl_verdict)"
  printf 'tok %s\n' "$TOK" > "$GLR/notes-outside-the-allowlist.txt"; gl_stage
  _staged="$( ( cd "$GLR" && git diff --cached --name-only ) 2>/dev/null)"
  t_has "the allowlist stages the paths it names" "$_staged" 'WORK/sessions/testhost/2026-09-16.md'
  t_hasnt "the allowlist stages no path it does not name" "$_staged" 'notes-outside-the-allowlist'
  # The second gate: worklog/pre-push scans the whole history, which the staged check cannot see.
  PP="$T_ROOT/worklog/pre-push"; pp() { ( cd "$GLR" && sh "$PP" ) >/dev/null 2>&1; }
  t_eq "worklog/pre-push is in the tree" yes "$([ -f "$PP" ] && echo yes || echo no)"
  rm -f "$GLR/notes-outside-the-allowlist.txt"; ( cd "$GLR" && git add -A && git commit -q -m clean ) >/dev/null 2>&1
  t_exit "pre-push allows a clean history" 0 pp
  printf '# note\n\nExported %s.\n' "$TOK" > "$GLR/KNOWLEDGE/leak.md"
  ( cd "$GLR" && git add -A && git commit -q -m leak ) >/dev/null 2>&1
  t_exit "pre-push refuses a secret already in history" 1 pp
fi

t_section "a symlinked store is read like the tree it points at (harbor#608)"
# memory-route links silos to one store; find without -L walked nothing and said 0 of everything.
LINKDIR="$T_TMP/linked"; mkdir -p "$LINKDIR"; ln -s "$CORPUS" "$LINKDIR/store"; ln -s "$CLEAN" "$LINKDIR/healthy"
SOUT="$(sh "$LINT" --root "$LINKDIR/store" --json 2>/dev/null)"
t_eq "symlinked store: note count" "$W_NOTES" "$(jqr "$SOUT" '.notes // "null"')"
t_eq "symlinked store: dangling count" "$W_DANGLING" "$(jqr "$SOUT" '.dangling | length')"
t_eq "symlinked store: dead-path count" "$W_DEADPATH" "$(jqr "$SOUT" '.dead_paths | length')"
t_eq "symlinked store: collision count" "$W_COLLISION" "$(jqr "$SOUT" '.collisions | length')"
t_eq "symlinked store: the dangling set is the pinned one" "$(jq -Sc "$DSET" "$EXPECT")" "$(printf '%s' "$SOUT" | jq -Sc "$DSET")"
t_exit "symlinked store: --strict exits as on the direct path" 1 sh "$LINT" --root "$LINKDIR/store" --strict
t_exit "symlinked store: --strict is still 0 on a healthy target" 0 sh "$LINT" --root "$LINKDIR/healthy" --strict
t_done
