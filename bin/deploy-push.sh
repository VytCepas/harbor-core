#!/usr/bin/env sh
# deploy-push.sh (harbor#1149, DESIGN.md v2.1) - `harbor deploy push`: share core. One snapshot commit of the core set, no history.
#
#   deploy-push.sh [--dry-run] <target>   target: a LOCAL git checkout (its top level), clean, not on `stable`
#
# The gate scans every staged file, tests and fixtures included (LEAKS_EXPORT=1), then gitleaks scans the same set.
# Core = the paths of CONTRACTS/layers.tsv at HEAD. They are staged, gated by `lint-leaks.sh --zero` and gitleaks on exactly that set,
# and only on green written into <target> as one commit naming the source sha. It never pushes, never touches a tag or
# `stable`, and refuses a URL, a dirty target, an unclassified path or a red gate. --dry-run lists the set and the gate.
# The staged CONTRACTS/repo-slug.txt is rewritten to the target's GitHub origin; no origin, or the source's own, refuses.
# The gate also reads the target's published history (a dry run too, when it names a target), the domain ratchet at zero
# and pass-score; it prints every release gate row on stderr, the two it does not run included (harbor#1274).
set -eu

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
ROOT="${HARBOR_ROOT:-$(CDPATH= cd -- "$SRC/.." && pwd)}"
. "$SRC/log-lib.sh"
log_init deploy-push
LOG_FD=2

DRY=0; TARGET=''
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "deploy-push: unknown option '$a'" >&2; exit 2 ;;
    *) [ -z "$TARGET" ] || { echo "deploy-push: one target only" >&2; exit 2; }; TARGET="$a" ;;
  esac
done
[ "$DRY" = 1 ] || [ -n "$TARGET" ] || { echo "usage: deploy-push.sh [--dry-run] <local git checkout>" >&2; exit 2; }

refuse() { log_fail "$1"; [ -z "${2:-}" ] || log_fix "$2"; log_end || :; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/deploy-push.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT INT TERM

# The target first: nothing is built for a destination that would be refused anyway.
if [ -n "$TARGET" ]; then
  case "$TARGET" in
    *://*|*@*:*|[A-Za-z0-9._-]*:*) refuse "the target '$TARGET' looks like a network remote" "name a local checkout path; this command never pushes" ;;
  esac
  [ -d "$TARGET" ] || refuse "the target '$TARGET' is not a directory" "create and git init the export checkout first"
  TDIR="$(CDPATH= cd -- "$TARGET" && pwd -P)"
  [ "$(git -C "$TDIR" rev-parse --show-toplevel 2>/dev/null || :)" = "$TDIR" ] || refuse "the target is not the top level of a git checkout" "git init $TARGET"
  [ "$TDIR" != "$(CDPATH= cd -- "$ROOT" && pwd -P)" ] || refuse "the target is the source checkout" "name the export checkout"
  [ -z "$(git -C "$TDIR" status --porcelain 2>/dev/null)" ] || refuse "the target has uncommitted or untracked changes" "commit or clean the target first"
  [ "$(git -C "$TDIR" symbolic-ref -q --short HEAD 2>/dev/null || :)" != stable ] || refuse "the target has stable checked out" "stable moves only by the operator's choice; switch the target to another branch"
  [ -n "$(git -C "$TDIR" symbolic-ref -q HEAD 2>/dev/null || :)" ] || refuse "the target HEAD is detached" "check out a branch in the target"
fi

SHA="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)" || refuse "$ROOT is not a git checkout with a commit" ""
RAW="$TMP/raw"; STAGE="$TMP/stage"; mkdir -p "$RAW" "$STAGE"
git -C "$ROOT" archive HEAD | tar -xf - -C "$RAW"
[ -f "$RAW/CONTRACTS/layers.tsv" ] || refuse "no CONTRACTS/layers.tsv at HEAD, so no core set" "commit CONTRACTS/layers.tsv"
git -C "$ROOT" ls-tree -r --name-only HEAD > "$TMP/all.files"
LAYERS_FILE="$RAW/CONTRACTS/layers.tsv" sh "$SRC/layers.sh" --classify < "$TMP/all.files" > "$TMP/classes" ||
  refuse "CONTRACTS/layers.tsv is malformed" "sh bin/layers.sh --check"
BAD="$(awk -F'\t' '$NF == "none" || $NF == "multi"' "$TMP/classes" | wc -l | tr -d ' ')"
[ "$BAD" = 0 ] || refuse "$BAD path(s) at HEAD match no layers.tsv row or two" "sh bin/layers.sh --check names them"
awk -F'\t' '$NF == "core" { sub(/\t[^\t]*$/, ""); print }' "$TMP/classes" > "$TMP/core.files"
NCORE="$(wc -l < "$TMP/core.files" | tr -d ' ')"
[ "$NCORE" -gt 0 ] || refuse "the core set is empty" "check CONTRACTS/layers.tsv"
tar -cf - -C "$RAW" -T "$TMP/core.files" | tar -xf - -C "$STAGE"

# The export names itself, never the dev repo: findings-run.sh fetches and runs what repo-slug.txt names (harbor#1149).
# The slug is the target's GitHub origin, the answer repo_slug gives inside a clone; none, or the source's own, refuses.
SLUGF="$STAGE/CONTRACTS/repo-slug.txt"; XSLUG=''; SLUGERR=''
if [ -f "$SLUGF" ]; then
  SSLUG="$(slug_of_url "$(git -C "$ROOT" config --get remote.origin.url 2>/dev/null || :)")"
  [ -n "$SSLUG" ] || SSLUG="$(_rs_pin "$SLUGF")"
  if [ -z "$TARGET" ]; then SLUGERR="no target, so the export's own slug is unknown"
  else
    XSLUG="$(slug_of_url "$(git -C "$TDIR" config --get remote.origin.url 2>/dev/null || :)")"
    if ! slug_valid "$XSLUG"; then XSLUG=''; SLUGERR="the target has no GitHub origin, so the export would name $SSLUG as its own repo"
    elif [ "$XSLUG" = "$SSLUG" ]; then SLUGERR="the target's origin is the source repo $SSLUG"; XSLUG=''
    else awk -v s="$XSLUG" '!d && $0 !~ /^[ \t]*(#|$)/ { print s; d = 1; next } { print }' "$SLUGF" > "$TMP/slug" && cat "$TMP/slug" > "$SLUGF"
    fi
  fi
fi
FIXSLUG="git -C <target> remote add origin https://github.com/<owner>/<export repo>.git"

# docs/index.html is built, not committed (harbor#1197), so HEAD has none and the core clone would open with a README that
# says `open docs/index.html` and no page. The stage's own builder makes it, before the gate so the gate scans it, and
# `git add -f` below carries it past the .gitignore. It is a build, not a source: it is not in core.files or the count.
if [ -f "$STAGE/bin/docs-gen.sh" ]; then
  sh "$STAGE/bin/docs-gen.sh" --apply > "$TMP/docs-gen.out" 2>&1 ||
    { sed 's/^/    /' "$TMP/docs-gen.out" >&2; refuse "docs-gen could not build docs/index.html in the staged core set" "sh bin/docs-gen.sh --check names the failure"; }
fi

# The gate runs on the staged set alone: it is a throwaway checkout whose every file is tracked, ignored or not.
git -C "$STAGE" init -q .
git -C "$STAGE" add -f -A
# docs/context-map.md is a census of the tracked tree, and the export drops the dev layer, so the copy from HEAD is
# stale in every core clone and its fresh-check refuses the run (harbor-core's first CI). The stage's own builder recounts it.
if [ -f "$STAGE/bin/standard-catalog.sh" ]; then
  ( cd "$STAGE" && sh bin/standard-catalog.sh --map ) > "$TMP/map.out" 2>&1 && git -C "$STAGE" add -f docs/context-map.md ||
    { sed 's/^/    /' "$TMP/map.out" >&2; refuse "standard-catalog could not rebuild docs/context-map.md in the staged core set" "sh bin/standard-catalog.sh --check names the failure"; }
fi
PRIV="${HARBOR_SCOPE_PRIVATE:-${PORT_ROOT:-$HOME/port}/harbor-private}"
[ -d "${PRIV%/}" ] || refuse "no private layer, so the private terms cannot be checked" "set HARBOR_SCOPE_PRIVATE; the export gate is core patterns plus those terms"
GATE=0
LEAKS_EXPORT=1 HARBOR_ROOT="$STAGE" LEAKS_CORE_PATTERNS="$ROOT/CONTRACTS/leak-patterns.tsv" sh "$SRC/lint-leaks.sh" --zero || GATE=$?

# gitleaks over the same stage (harbor#1149): the token shapes no leak pattern names. Missing is a refusal, never a skip.
# The staged .gitleaks.toml decides, never an inherited GITLEAKS_CONFIG. 8.19+ says `dir`, 8.18 `detect --no-git`.
SECRETS=0
if ! command -v gitleaks >/dev/null 2>&1; then
  SECRETS=1; log_fail "gitleaks is missing, so the stage was not scanned for secrets"; log_fix "$(pkg_hint gitleaks)"
else
  set -- --no-banner --redact --exit-code 1 --report-format json --report-path "$TMP/gitleaks.json"
  [ ! -f "$STAGE/.gitleaks.toml" ] || set -- "$@" --config "$STAGE/.gitleaks.toml"
  if ( cd "$STAGE" || exit 2; unset GITLEAKS_CONFIG GITLEAKS_CONFIG_TOML
       if gitleaks dir --help >/dev/null 2>&1; then exec gitleaks dir "$@" .; else exec gitleaks detect --no-git "$@" --source .; fi
     ) > "$TMP/gitleaks.out" 2>&1; then
    log_ok "gitleaks: no secret in the $NCORE staged file(s)"
  else
    SECRETS=1
    # The report's fingerprints are file:rule:line, the secret itself redacted; no finding means gitleaks itself failed.
    sed -n 's/^ *"Fingerprint": "\(.*\)",\{0,1\}$/\1/p' "$TMP/gitleaks.json" 2>/dev/null > "$TMP/gitleaks.hits" || :
    if [ -s "$TMP/gitleaks.hits" ]; then
      while IFS= read -r _h; do log_note "gitleaks: $_h"; done < "$TMP/gitleaks.hits"
      log_fail "gitleaks: $(wc -l < "$TMP/gitleaks.hits" | tr -d ' ') secret(s) in the staged set"
      log_fix "take each one out of its tracked file; the notes above name it as file:rule:line"
    else
      log_fail "gitleaks could not scan the stage: $(tr -d '\033' < "$TMP/gitleaks.out" | sed 's/\[[0-9;]*m//g' | tail -n 1)"
      log_fix "gitleaks dir --redact . in a checkout of HEAD shows its error"
    fi
  fi
fi
FIXL="sh bin/lint-leaks.sh --list names each file:line and pattern id"
FIXS="clear the gitleaks finding or install gitleaks, as the fix above says"

# hist_scan <target>: its published history (harbor#1274) under the stage's leak patterns and gitleaks. A leak pushed
# once stays published, so one in any earlier export refuses the next. Notes name commit, path:line and pattern id only.
HIST=0; HISTN=0; HISTB=0
hist_note() { # <hits file> <label>: at most 20 notes, then a count
  awk -v l="$2" 'NR <= 20 { print l ": " $0 } END { if (NR > 20) print l ": and " NR - 20 " more" }' "$1" |
    while IFS= read -r _l; do log_note "$_l"; done
}
hist_err() { log_fail "history: $1 failed, so the published history was not scanned"; log_fix "git fsck in the target names a broken object or ref"; return 1; }
hist_scan() {
  git -C "$1" rev-parse -q --verify HEAD >/dev/null || return 0  # no commit yet: nothing is published
  [ "$(git -C "$1" rev-parse --is-shallow-repository)" = false ] ||
    { log_fail "history: the target is a shallow clone, so its published history cannot all be read"; log_fix "git -C $1 fetch --unshallow"; return 1; }
  # Every commit HEAD, the tags and the remote branches reach: what a push publishes and what is already published.
  set -- "$1" HEAD --tags --remotes
  HISTN="$(git -C "$1" rev-list --count "$2" "$3" "$4")" || { hist_err "listing the commits"; return 1; }
  _h="$TMP/hist"; mkdir -p "$_h"; git -C "$_h" init -q . || { hist_err "the scan checkout"; return 1; }
  git -C "$1" rev-parse --path-format=absolute --git-path objects > "$_h/.git/objects/info/alternates" || { hist_err "reaching the objects"; return 1; }
  # Each blob once, at <commit12>-<blob12>/<path> of the oldest commit holding it: one directory per blob, so paths that
  # differ only in case cannot overwrite each other on macOS. A symlink's target is read as text.
  git -C "$1" -c core.quotePath=false log --reverse --root -m --raw --no-abbrev --no-renames --format='C %H' "$2" "$3" "$4" \
    > "$TMP/hist.raw" || { hist_err "reading the commits"; return 1; }
  awk '/^C [0-9a-f]+$/ { c = substr($0, 3, 12); next }
       /^:/ { t = index($0, "\t"); split(substr($0, 1, t - 1), M, " ")
              if (M[5] ~ /^D/ || M[2] == "160000" || M[4] ~ /^0+$/ || (M[4] in S)) next
              S[M[4]] = 1; printf "100644 %s\t%s-%s/%s\n", M[4], c, substr(M[4], 1, 12), substr($0, t + 1) }' "$TMP/hist.raw" > "$TMP/hist.index" ||
    { hist_err "listing the file versions"; return 1; }
  HISTB="$(wc -l < "$TMP/hist.index" | tr -d ' ')"
  { git -C "$_h" update-index --add --index-info < "$TMP/hist.index" && git -C "$_h" checkout-index -a -f; } || { hist_err "writing the file versions"; return 1; }
  # Commit messages are published too: each one as <commit12>.msg.
  git -C "$1" log --format='%H%x01%B%x02' "$2" "$3" "$4" > "$TMP/hist.msgs" || { hist_err "reading the messages"; return 1; }
  awk -v d="$_h" 'BEGIN { RS = "\002" } { sub(/^\n/, ""); i = index($0, "\001"); if (!i) next
                  f = d "/" substr($0, 1, 12) ".msg"; printf "%s", substr($0, i + 1) > f; close(f) }' "$TMP/hist.msgs" ||
    { hist_err "writing the messages"; return 1; }
  git -C "$_h" add -f -A || { hist_err "indexing the messages"; return 1; }
  _r=0
  LEAKS_EXPORT=1 HARBOR_ROOT="$_h" LEAKS_CORE_PATTERNS="$ROOT/CONTRACTS/leak-patterns.tsv" sh "$SRC/lint-leaks.sh" --list \
    > "$TMP/hist.hits" 2> "$TMP/hist.err" || { _r=1; log_fail "history: the leak scan did not complete: $(grep -E 'FAIL' "$TMP/hist.err" | head -1 | sed 's/^ *//')"; log_fix "$FIXL"; }
  if [ -s "$TMP/hist.hits" ]; then
    _r=1; sed -e 's/^\([0-9a-f]\{12\}\)-[0-9a-f]\{12\}\/\(.*\):\([^:]*\)$/commit \1 \2 pattern \3/' \
      -e 's/^\([0-9a-f]\{12\}\)\.\(msg:.*\):\([^:]*\)$/commit \1 \2 pattern \3/' "$TMP/hist.hits" > "$TMP/hist.named"
    hist_note "$TMP/hist.named" "history leak"
    log_fail "history: $(wc -l < "$TMP/hist.hits" | tr -d ' ') leak occurrence(s) in the target's published commits"; log_fix "$FIXH"
  fi
  command -v gitleaks >/dev/null 2>&1 || { log_fail "history: gitleaks is missing, so the published commits were not scanned for secrets"; log_fix "$(pkg_hint gitleaks)"; return 1; }
  # The stage's config decides, as for the stage; without one the defaults, never the target's own copy.
  _cfg="$STAGE/.gitleaks.toml"; [ -f "$_cfg" ] || { _cfg="$TMP/default.toml"; printf '[extend]\nuseDefault = true\n' > "$_cfg"; }
  if ( cd "$1" || exit 2; unset GITLEAKS_CONFIG GITLEAKS_CONFIG_TOML
       set -- --no-banner --redact --exit-code 1 --report-format json --report-path "$TMP/hist-gl.json" --config "$_cfg" --log-opts="$2 $3 $4"
       if gitleaks git --help >/dev/null 2>&1; then exec gitleaks git "$@" .; else exec gitleaks detect "$@" --source .; fi
     ) > "$TMP/hist-gl.out" 2>&1; then :
  else
    _r=1
    sed -n 's/^ *"Fingerprint": "\(.*\)",\{0,1\}$/\1/p' "$TMP/hist-gl.json" 2>/dev/null > "$TMP/hist-gl.hits" || :
    if [ -s "$TMP/hist-gl.hits" ]; then
      hist_note "$TMP/hist-gl.hits" "history gitleaks (commit:file:rule:line)"
      log_fail "history: gitleaks: $(wc -l < "$TMP/hist-gl.hits" | tr -d ' ') secret(s) in the target's published commits"; log_fix "$FIXH"
    else log_fail "history: gitleaks could not scan the target: $(tr -d '\033' < "$TMP/hist-gl.out" | sed 's/\[[0-9;]*m//g' | tail -n 1)"; log_fix "gitleaks git --redact in the target shows its error"; fi
  fi
  return "$_r"
}
FIXH="a leak already published is not removed by a new commit: before the announcement, recreate the export repo from a clean snapshot; after it, rotate the leaked value (harbor#1149)"
if [ -n "$TARGET" ]; then
  hist_scan "$TDIR" || HIST=1
  [ "$HIST" = 1 ] || log_ok "history: $HISTN published commit(s), $HISTB distinct file version(s), no leak and no secret"
fi

# Domain ratchet at zero over the stage (harbor#1274): core carries no workload tool's name.
DOMAIN=0
HARBOR_ROOT="$STAGE" sh "$SRC/lint-domain.sh" --zero >&2 || DOMAIN=1
# and no workload repo's name (harbor#1273): the ids come from the private registry, so none is named here
HARBOR_ROOT="$STAGE" sh "$SRC/lint-domain.sh" --repos --zero >&2 || DOMAIN=1
# pass-score (decision 17 on harbor#1149): HEAD's FLOOR.md, so its pass table, not the working tree's.
PASSS=0
if [ -f "$RAW/bin/pass-score.sh" ]; then
  sh "$RAW/bin/pass-score.sh" > "$TMP/pass.out" 2>&1 || PASSS=1
  PASSV="$(grep -E '(ok|FAIL): VERDICT' "$TMP/pass.out" | head -1 | sed 's/^ *[A-Za-z]*: //')"
else PASSS=1; PASSV="no bin/pass-score.sh at HEAD"; fi
# redteam-corpus (decision 23 on harbor#1149): the last run of the external corpora, read against HEAD's guards, pins and
# baseline. Red while a finding is unaccepted, a corpus was skipped, or HEAD's guards or pins differ from what was run.
# The overrides are dropped so no environment can point the gate at another baseline.
RTS=0
if [ -f "$RAW/bin/redteam-corpus.sh" ]; then
  env -u HARBOR_REDTEAM_BASELINE -u HARBOR_REDTEAM_SOURCES -u HARBOR_CACHE_DIR sh "$RAW/bin/redteam-corpus.sh" --print \
    > "$TMP/redteam.out" 2>&1 || RTS=1
  RTV="$(grep -cE '^  ok: ' "$TMP/redteam.out" | tr -d ' ') corpus line(s) ok, $(grep -cE '^  FAIL: ' "$TMP/redteam.out" | tr -d ' ') red"
else RTS=1; RTV="no bin/redteam-corpus.sh at HEAD"; fi
FIXR="sh bin/redteam-corpus.sh --print names each red corpus; adjudicate each finding on harbor#1313"
FIXD="sh bin/lint-domain.sh --list (and --repos --list) names each file and term (harbor#1273)"
FIXP="sh bin/pass-score.sh shows the pass table; an adjudicated pass must leave zero criticals open (decision 23, harbor#1149)"

# The release gate (harbor#1274, decisions 17-18 on harbor#1149): every row named, none a silent pass. The rows run here
# refuse a push when red; the two too costly for a push are named with the command that settles them.
gate_row() { # <name> <0 green | 1 red> <detail> <fix>
  if [ "$2" = 0 ]; then log_ok "release gate · $1: green - $3"; else log_fail "release gate · $1: red - $3"; log_fix "$4"; fi
}
log_head "release gate"
gate_row "leak gate 0" "$GATE" "the staged set" "$FIXL"
gate_row "secrets 0" "$SECRETS" "gitleaks over the staged set" "$FIXS"
if [ -n "$TARGET" ]; then gate_row "export history" "$HIST" "$HISTN published commit(s) of the target" "$FIXH"
else log_skip "release gate · export history: not run - name the target: harbor deploy push --dry-run <target>"; fi
gate_row "domain ratchet 0" "$DOMAIN" "sh bin/lint-domain.sh --zero and --repos --zero over the staged set" "$FIXD"
gate_row "pass-score" "$PASSS" "${PASSV:-no verdict}" "$FIXP"
gate_row "redteam-corpus" "$RTS" "$RTV" "$FIXR"
log_skip "release gate · stranger install: not run here - its verdict for this sha: gh run list -w stranger-install.yml -c $SHA; to run it: gh workflow run stranger-install.yml"
log_skip "release gate · export suite: not run here (serial seconds: the sum of tests/suite-durations.tsv, harbor#1275) - in a clean clone of the target: sh bin/suite-run.sh"
RED=$((GATE + SECRETS + HIST + DOMAIN + PASSS + RTS))

if [ "$DRY" = 1 ]; then
  cat "$TMP/core.files"
  log_note "dry run: $NCORE core file(s) from ${SHA}$([ -z "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ] || echo ', uncommitted changes are not in HEAD')"
  if [ -n "$XSLUG" ]; then log_note "repo-slug.txt exports as $XSLUG"; elif [ -n "$SLUGERR" ]; then log_note "repo-slug.txt: $SLUGERR; a push refuses until $FIXSLUG"; fi
  if [ "$RED" = 0 ]; then log_ok "gate: every row run here is green, a push would proceed"
  else log_fail "gate: red, a push would refuse"; log_fix "each red release gate row above names its fix"; RED=1; fi
  log_end || :; exit "$RED"
fi
[ "$GATE" = 0 ] || refuse "the leak gate is red; nothing was written to the target" "$FIXL"
[ "$SECRETS" = 0 ] || refuse "the secret scan is red or did not run; nothing was written to the target" "$FIXS"
[ "$HIST" = 0 ] || refuse "the target's published history carries a leak or could not be scanned; nothing was written to the target" "$FIXH"
[ "$DOMAIN" = 0 ] || refuse "the domain ratchet is above zero; nothing was written to the target" "$FIXD"
[ "$PASSS" = 0 ] || refuse "pass-score is not green; nothing was written to the target" "$FIXP"
[ "$RTS" = 0 ] || refuse "redteam-corpus is not green; nothing was written to the target" "$FIXR"
[ -z "$SLUGERR" ] || refuse "$SLUGERR; nothing was written to the target" "$FIXSLUG"

# Replace the target's tree with the staged set: one commit, parent = the target's own last export, no source history.
if [ -n "$(git -C "$TDIR" ls-files)" ]; then git -C "$TDIR" rm -rq --ignore-unmatch -- . ; fi
tar -cf - --exclude ./.git -C "$STAGE" . | tar -xf - -C "$TDIR"
git -C "$TDIR" add -f -A
if git -C "$TDIR" rev-parse -q --verify HEAD >/dev/null && git -C "$TDIR" diff --cached --quiet; then
  log_ok "the target already holds this core set; no commit"; log_end || :; exit 0
fi
if git -C "$TDIR" commit -q -m "export: core snapshot of $(printf '%s' "$SHA" | cut -c1-12)" -m "Source commit: $SHA ($NCORE files)

Refs: harbor#1149"; then
  log_ok "one snapshot commit in the target: $(git -C "$TDIR" rev-parse --short HEAD), $NCORE file(s) from $(printf '%s' "$SHA" | cut -c1-12); not pushed, tags and stable untouched"
  log_end || :; exit 0
fi
# Restore: the target was clean when we began, so HEAD is the state to return to.
if git -C "$TDIR" rev-parse -q --verify HEAD >/dev/null; then git -C "$TDIR" reset -q --hard HEAD; else git -C "$TDIR" rm -rqf --cached --ignore-unmatch -- . ; fi
git -C "$TDIR" clean -fdq
refuse "the commit in the target failed (identity or a hook); the target was restored" "set user.name and user.email in the target"
