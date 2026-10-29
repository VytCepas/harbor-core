#!/usr/bin/env sh
# drift-reference-check.sh (M8, harbor#44), part 1: REF-0..REF-8, the governance-token order REF-7, and the
# mutants for REF-2, REF-5, the backtick arm and the exit code. Each rule goes RED on its own defect
# and stays GREEN on the valid input that looks like it (§2.11). The skill surface is in part 2.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/reference-check-fixture.sh"

t_section "the clean fixture is clean, and exits 0"
CLEAN="$(mkfixture clean)"
t_eq "the clean fixture reports nothing" "" "$(rules_of "$CLEAN")"
t_exit "the clean fixture exits" 0 sh "$RC" "$CLEAN"


t_section "REF-1: a hook whose script does not exist"
F1="$(mkfixture ref1)"
resettings "$F1" --arg c "/bin/sh $F1/bin/GONE.sh" '.hooks.SessionStart += [{matcher: "x", hooks: [{type: "command", command: $c}]}]'
t_eq "REF-1 fires on a missing hook script" yes "$(fired "$(rules_of "$F1")" REF-1)"
t_exit "a missing hook script exits" 1 sh "$RC" "$F1"

t_section "REF-1: BOTH paths in a wrapper command are checked"
F1B="$(mkfixture ref1b)"
resettings "$F1B" --arg c "/bin/sh $F1B/bin/hook-a.sh $F1B/bin/GONE.sh" '.hooks.PreToolUse = [{matcher: "Bash", hooks: [{type: "command", command: $c}]}]'
t_eq "REF-1 checks the second path of a wrapper" yes "$(fired "$(rules_of "$F1B")" REF-1)"

t_section "REF-2: the same command twice under an equivalent selector"
# The live shape: one bucket with NO matcher key and one with "" — how harbor#95 shipped.
F2="$(mkfixture ref2)"
resettings "$F2" --arg c "/bin/sh $F2/bin/hook-a.sh" '.hooks.SessionStart += [{hooks: [{type: "command", command: $c}]}]'
t_eq "REF-2 fires on absent matcher vs \"\"" yes "$(fired "$(rules_of "$F2")" REF-2)"

t_section "REF-2 STAYS GREEN: same command, two DIFFERENT matchers"
# guard-egress.sh is wired twice at PreToolUse on purpose, so the predicate keys on the matcher.
F2G="$(mkfixture ref2green)"
resettings "$F2G" --arg c "/bin/sh $F2G/bin/hook-b.sh" '
  .hooks.PreToolUse = [{matcher: "Bash|Write", hooks: [{type: "command", command: $c}]},
                       {matcher: "WebFetch|mcp__.*", hooks: [{type: "command", command: $c}]}]'
t_eq "the deliberate two-matcher wiring reports nothing" "" "$(rules_of "$F2G")"

t_section "REF-3: a statusline pointing at nothing"
F3="$(mkfixture ref3)"
resettings "$F3" --arg c "/bin/sh $F3/bin/GONE.sh" '.statusLine.command = $c'
t_eq "REF-3 fires on a missing statusline script" yes "$(fired "$(rules_of "$F3")" REF-3)"

t_section "REF-4: a content pin whose file is gone"
F4="$(mkfixture ref4)"
printf 'deadbeef  bin/vanished.sh\n' > "$F4/.helm-pins/vanished.sh.sha256"
t_eq "REF-4 fires on a pin with no file" yes "$(fired "$(rules_of "$F4")" REF-4)"

t_section "REF-5: a dead citation in the INSTALLED CLAUDE.md"
F5="$(mkfixture ref5)"
printf '# c\n[gone](./NOPE.md)\n' >> "$F5/CLAUDE.md"
t_eq "REF-5 fires on a dead citation" yes "$(fired "$(rules_of "$F5")" REF-5)"

t_section "REF-5 STAYS GREEN: URLs and anchors are not filesystem paths"
F5G="$(mkfixture ref5green)"
printf '[u](https://example.com/a/b.md) [m](mailto:x@y.z) [a](#top)\n' >> "$F5G/CLAUDE.md"
t_eq "a URL, a mailto and an anchor report nothing" "" "$(rules_of "$F5G")"

t_section "REF-5: a manifest row whose installed file is gone is a dangling deploys_to edge (harbor#996 C2)"
F5D="$(mkfixture ref5dangle)"
printf '# .harbor-manifest\nabc 100644 bin/hook-a.sh runtime-install c0\n' > "$F5D/.harbor-manifest"
t_eq "a manifest row whose file is on disk reports nothing" "" "$(rules_of "$F5D")"
printf 'def 100644 bin/GONE-installed.sh runtime-install c0\n' >> "$F5D/.harbor-manifest"
t_eq "REF-5 fires on a manifest row with no file" yes "$(fired "$(rules_of "$F5D")" REF-5)"
t_has "the finding names the missing file" "$(sh "$RC" "$F5D" 2>&1)" "GONE-installed.sh"
t_exit "a dangling installed file exits" 1 sh "$RC" "$F5D"
t_eq "graph-gen --dangling lists the same row" "bin/GONE-installed.sh" "$(CLAUDE_CONFIG_DIR="$F5D" sh "$T_ROOT/bin/doc-graph-generate.sh" --dangling | awk -F'\t' '{ sub(/.*\/bin\//, "bin/", $1); print $1 }')"
t_exit "...and with TMPDIR unwritable still exits" 1 env TMPDIR=/nonexistent-refchk sh "$RC" "$F5D"
t_eq "...still naming the row" yes "$(fired "$(TMPDIR=/nonexistent-refchk sh "$RC" "$F5D" 2>&1)" REF-5)"

t_section "REF-0: a settings.json that does not PARSE is never 'clean'"
F0="$(mkfixture ref0)"
printf '{bad' > "$F0/settings.json"
t_eq "REF-0 fires on a settings.json that does not parse" yes "$(fired "$(rules_of "$F0")" REF-0)"
t_exit "an unreadable settings.json exits" 1 sh "$RC" "$F0"

t_section "REF-5: a fragment is not part of the path"
F5F="$(mkfixture ref5frag)"
printf '[frag](./REAL.md#section)\n' >> "$F5F/CLAUDE.md"
t_eq "a #fragment on a live target reports nothing" "" "$(rules_of "$F5F")"
F5G2="$(mkfixture ref5frag2)"
printf '[frag](./NOPE.md#section)\n' >> "$F5G2/CLAUDE.md"
t_eq "a dead target still fires with a fragment attached" yes "$(fired "$(rules_of "$F5G2")" REF-5)"

t_section "REF-5: a BACKTICKED path, the dialect it was blind to (harbor#462)"
F5B="$(mkfixture ref5backtick)"
printf 'a repo-only doc: `./NOPE.md`\n' >> "$F5B/CLAUDE.md"
t_eq "REF-5 fires on a backticked dead path" yes "$(fired "$(rules_of "$F5B")" REF-5)"
F5BOK="$(mkfixture ref5backtickok)"
printf 'a live one: `./REAL.md`\n' >> "$F5BOK/CLAUDE.md"
t_eq "a backticked path that resolves reports nothing" "" "$(rules_of "$F5BOK")"

t_section "REF-5 + REF-8: a declared **Path root:** is where ./paths resolve"
# ./AWAY.md exists at the declared root and not beside the document; the twin lacks only the line.
F5R="$(mkfixture ref5root)"
mkdir -p "$F5R/elsewhere"; printf 'X\n' > "$F5R/elsewhere/AWAY.md"
printf '# c\n> **Path root:** `%s`\n\ncites `./AWAY.md`\n' "$F5R/elsewhere" > "$F5R/CLAUDE.md"
t_eq "a declared path root is honoured" "" "$(rules_of "$F5R")"
F5RN="$(mkfixture ref5rootless)"
mkdir -p "$F5RN/elsewhere"; printf 'X\n' > "$F5RN/elsewhere/AWAY.md"
printf '# c\n\ncites `./AWAY.md`\n' > "$F5RN/CLAUDE.md"
r="$(rules_of "$F5RN")"
t_eq "without the declaration the citation fires REF-5" yes "$(fired "$r" REF-5)"
t_eq "REF-8 names the missing declaration as the cause" yes "$(fired "$r" REF-8)"
t_eq "REF-8 stays silent where the root is declared" no "$(fired "$(rules_of "$F5R")" REF-8)"

t_section "REF-5: a declared root that does NOT exist is a finding, not a pass"
F5BR="$(mkfixture ref5badroot)"
printf '> **Path root:** `%s/no-such-root`\n' "$TMP" >> "$F5BR/CLAUDE.md"
t_eq "a declared root that does not exist is reported" true \
  "$(sh "$RC" "$F5BR" --json 2>/dev/null | jq '[.findings[] | select(.subject | test("path root"))] | length > 0')"

t_section "REF-5: a MISSING extractor is loud, and never a clean sweep"
NOAWK="$TMP/noawk"; mkdir -p "$NOAWK"; cp "$RC" "$NOAWK/drift-reference-check.sh"; cp "$SRC/library-log.sh" "$SRC/library-fs.sh" "$NOAWK/"
t_eq "a missing doc-cited-paths.awk fires REF-5" yes "$(fired "$(rules_by "$NOAWK/drift-reference-check.sh" "$F5B")" REF-5)"
t_exit "a missing extractor exits" 1 sh "$NOAWK/drift-reference-check.sh" "$F5B"

t_section "REF-6: a CONFIGURED box with no constitution is not 'clean'"
F6="$(mkfixture ref6)"; rm -f "$F6/CLAUDE.md"
t_eq "REF-6 fires on a configured box with no constitution" yes "$(fired "$(rules_of "$F6")" REF-6)"
t_exit "a box with no constitution exits" 1 sh "$RC" "$F6"
mkdir -p "$TMP/bare"
t_eq "an unconfigured directory reports nothing" "" "$(rules_of "$TMP/bare")"

t_section "an absent config dir is an ANSWER, not an error"
t_exit "an absent config dir exits" 0 sh "$RC" "$TMP/nothing-here"
t_eq "an absent config dir reports installed:false" false "$(sh "$RC" "$TMP/nothing-here" --json 2>/dev/null | jq -r '.installed')"

t_section "usage errors exit 2, and are distinguishable from findings"
t_exit "an unknown option" 2 sh "$RC" --nonsense

t_section "B9: a missing jq is LOUD, and never reads as clean"
mkdir -p "$TMP/nojq"
for b in sh awk sed sort uniq tr basename grep printf; do
  p="$(command -v "$b" 2>/dev/null)" && ln -sf "$p" "$TMP/nojq/$b" 2>/dev/null
done
o="$(PATH="$TMP/nojq" sh "$RC" "$CLEAN" 2>&1)"; rc=$?
t_eq "with jq masked the tool exits" 1 "$rc"
t_has "with jq masked the tool says why" "$o" "jq"

t_section "the two renderers report the same findings"
FMIX="$(mkfixture mixed)"
printf '[gone](./NOPE.md)\n' >> "$FMIX/CLAUDE.md"
resettings "$FMIX" --arg c "/bin/sh $FMIX/bin/hook-a.sh" '.hooks.SessionStart += [{hooks: [{type: "command", command: $c}]}]'
NMIX="$(sh "$RC" "$FMIX" --json 2>/dev/null | jq '.findings | length')"
t_eq "the fixture has three findings to count: REF-2, REF-5 and REF-8" 3 "$NMIX"
t_eq "the human report counts what --json counts" "$NMIX" "$(sh "$RC" "$FMIX" 2>/dev/null | awk '/^  FAIL: /{n++} END{print n+0}')"

t_section "the human report is log-lib's line shape (contracts/logging.md, harbor#809)"
sh "$RC" "$FMIX" >"$TMP/mix.out" 2>&1; rc=$?
t_eq "a report with findings exits" 1 "$rc"
t_eq "no check mark, cross, arrow or bullet glyph" 0 "$(grep -cE '✓|✗|↳|^  · ' "$TMP/mix.out")"
t_eq "every line is the header, a TAG line or the summary" 0 \
  "$(grep -cvE '^(── reference-check · |  (ok|FAIL|WARN|note|skip|fix): |reference-check: [0-9]+ ok, [0-9]+ failed, [0-9]+ warnings$)' "$TMP/mix.out")"
t_has "the positive control: a finding is a FAIL line naming its rule and subject" "$(cat "$TMP/mix.out")" "  FAIL: REF-5  CLAUDE.md → ./NOPE.md — "
t_exit "every FAIL is followed by its fix line" 0 awk '/^  FAIL: / { f = 1; next } f && !/^  fix: / { bad = 1 } { f = 0 } END { exit bad }' "$TMP/mix.out"
t_has "a finding with no command names where its repair is written" "$(cat "$TMP/mix.out")" "  fix: none automatic — see bin/drift-reference-check.sh REF-2"
t_eq "the summary counts the findings --json counts, and ends the run" "reference-check: 0 ok, $NMIX failed, 0 warnings" "$(tail -1 "$TMP/mix.out")"
t_has "what it examined is a note line" "$(cat "$TMP/mix.out")" "  note: REF-1  examined "
sh "$RC" "$CLEAN" >"$TMP/clean.out" 2>&1; rc=$?
t_eq "a clean report exits" 0 "$rc"
t_has "a clean report's verdict is an ok line" "$(cat "$TMP/clean.out")" "  ok: every hook, pin and citation on the installed surface resolves"
t_eq "...and its summary agrees" "reference-check: 1 ok, 0 failed, 0 warnings" "$(tail -1 "$TMP/clean.out")"
t_has "an absent config dir is an ok line, not a stderr aside" "$(sh "$RC" "$TMP/nothing-here" 2>/dev/null)" "  ok: no config dir at $TMP/nothing-here"
t_has "a missing jq is a FAIL with its fix line, in this host's package manager" "$(PATH="$TMP/nojq" sh "$RC" "$CLEAN" 2>&1)" "  fix: $(PATH="$TMP/nojq" /bin/sh -c '. "$1"; pkg_hint jq' _ "$T_ROOT/bin/library-log.sh")"
mkdir -p "$TMP/lxjq"; printf '#!/bin/sh\necho Linux\n' > "$TMP/lxjq/uname"; printf '#!/bin/sh\nexit 0\n' > "$TMP/lxjq/apt-get"; chmod +x "$TMP/lxjq/uname" "$TMP/lxjq/apt-get"
t_has "Linux: the fix names apt-get (harbor#618)" "$(PATH="$TMP/lxjq:$TMP/nojq" sh "$RC" "$CLEAN" 2>&1)" "  fix: sudo apt-get install -y jq"
t_eq "...and under --json its log lines stay off stdout, which is data" "" "$(PATH="$TMP/nojq" sh "$RC" "$CLEAN" --json 2>/dev/null)"
NOLIB="$TMP/nolib"; mkdir -p "$NOLIB"; cp "$RC" "$SRC/doc-cited-paths.awk" "$NOLIB/"
t_exit "a copy with no library-log.sh beside it exits" 1 sh "$NOLIB/drift-reference-check.sh" "$CLEAN" --json
t_has "...saying so, never a clean run" "$(sh "$NOLIB/drift-reference-check.sh" "$CLEAN" 2>&1)" "library-log.sh is missing beside $(cd -P "$NOLIB" && pwd -P)"
NOFS="$TMP/nofs"; mkdir -p "$NOFS"; cp "$RC" "$SRC/doc-cited-paths.awk" "$SRC/library-log.sh" "$NOFS/"
t_exit "a copy with no library-fs.sh beside it exits" 1 sh "$NOFS/drift-reference-check.sh" "$CLEAN" --json
t_has "...saying so, never a clean run" "$(sh "$NOFS/drift-reference-check.sh" "$CLEAN" 2>&1)" "library-fs.sh is missing beside $(cd -P "$NOFS" && pwd -P)"
t_eq "--json is byte-for-byte the pre-log-lib shape (the clean fixture)" \
  "$(jq -n --arg d "$CLEAN" '{dir: $d, installed: true, findings: [], examined: [
      {rule: "REF-1", count: 2, what: "absolute path(s) inside wired hook commands"},
      {rule: "REF-3", count: 2, what: "path(s) in the statusline command"},
      {rule: "REF-4", count: 1, what: "content pin(s)"},
      {rule: "REF-5", count: 3, what: "citation(s) extracted from CLAUDE.md"}], clean: true}')" \
  "$(sh "$RC" "$CLEAN" --json 2>&1)"

t_section "REF-7: the governance token's install ORDER (harbor#7, #226)"
t_eq "a box with no governance salt is not REF-7" no "$(fired "$(rules_of "$CLEAN")" REF-7)"
R7A="$(mkfixture ref7-degraded)"   # announce wired, no salt: the honest degrade
printf '#!/usr/bin/env sh\nexit 0\n' > "$R7A/bin/govern-token.sh"
resettings "$R7A" --arg g "/bin/sh $R7A/bin/govern-token.sh --announce" '.hooks.SessionStart[0].hooks += [{type:"command",command:$g}]'
t_eq "a wired-but-unsalted box is not REF-7" no "$(fired "$(rules_of "$R7A")" REF-7)"
R7B="$(mkfixture ref7-correct)"
printf '#!/usr/bin/env sh\nexit 0\n' > "$R7B/bin/govern-token.sh"
resettings "$R7B" --arg g "/bin/sh $R7B/bin/govern-token.sh --announce" '.hooks.SessionStart[0].hooks += [{type:"command",command:$g}]'
printf 'saltbytes\n' > "$R7B/.helm-govern-salt"
# Explicit mtimes months apart: a bare touch lands both in one second, which the rule calls undecidable.
touch -t 202601010000 "$R7B/.helm-govern-salt"; touch -t 202606010000 "$R7B/settings.json"
t_eq "salt older than the wiring is not REF-7" no "$(fired "$(rules_of "$R7B")" REF-7)"
touch -t 202606010000 "$R7B/.helm-govern-salt"; touch -t 202601010000 "$R7B/settings.json"
t_eq "salt minted AFTER the announce was wired fires REF-7" yes "$(fired "$(rules_of "$R7B")" REF-7)"
# Still in the dangerous state: only a session record NEWER than the salt discharges it (harbor#226).
mkdir -p "$R7B/sessions"; touch -t 202603010000 "$R7B/sessions/1111.json"
t_eq "a session OLDER than the salt does not clear REF-7" yes "$(fired "$(rules_of "$R7B")" REF-7)"
touch -t 202607010000 "$R7B/sessions/2222.json"
t_eq "a session started SINCE the salt clears REF-7" no "$(fired "$(rules_of "$R7B")" REF-7)"
rm -rf "$R7B/sessions"

# GNU `stat -f` is --file-system: it prints a report, then fails. The shim reproduces that, and must
# fetch the real epoch without the BSD spelling it simulates, or it is the false positive (#226).
GNUD="$TMP/gnu-stat"; mkdir -p "$GNUD"
cat > "$GNUD/stat" <<'GNUSTAT'
#!/bin/sh
case "$1" in
  -f) shift; _rc=0
      for f in "$@"; do
        if [ -e "$f" ]; then printf '  File: "%s"\n  ID: 0 Namelen: 255 Type: ext2/ext3\n' "$f"
        else printf 'stat: cannot read file system information for %s\n' "$f" >&2; _rc=1; fi
      done
      exit "$_rc" ;;
  -c) shift; [ "$1" = "%Y" ] || exit 1; shift
      for f in "$@"; do
        _v="$(/usr/bin/stat -f %m "$f" 2>/dev/null)"
        case "${_v:-x}" in *[!0-9]*) _v="$(/usr/bin/stat -c %Y "$f" 2>/dev/null)" ;; esac
        case "${_v:-x}" in *[!0-9]*) exit 1 ;; *) printf '%s\n' "$_v" ;; esac
      done ;;
  *) exec /usr/bin/stat "$@" ;;
esac
GNUSTAT
chmod +x "$GNUD/stat"
touch -t 202601010000 "$R7B/.helm-govern-salt"; touch -t 202606010000 "$R7B/settings.json"  # correct order
t_eq "REF-7 stays silent on a correct box under GNU stat" no \
  "$(fired "$(PATH="$GNUD:$PATH" sh "$RC" "$R7B" --json 2>/dev/null | jq -r '[.findings[].rule] | unique | join(" ")')" REF-7)"
# The shim must be able to produce the failure: under the pre-226 helper the same fixture goes red.
oldm='_ref7_m() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || printf ""; }'
MUTRC="$(mkmut mut-pre226)"  # library-log.sh, library-fs.sh and the extractor beside it (#809)
awk -v repl="$oldm" '
  !skip && /^ *_ref7_m\(\) \{/ { print "      " repl; skip=1; next }
  skip == 1 { if ($0 ~ /^ *\}$/) skip=2; next }
  { print }' "$RC" > "$MUTRC"
t_eq "the pre-226 mutant differs from the source" yes "$(differs "$RC" "$MUTRC")"
t_exit "the pre-226 mutant parses" 0 sh -n "$MUTRC"
t_eq "the pre-226 helper fires REF-7 under the GNU shim" yes \
  "$(fired "$(PATH="$GNUD:$PATH" sh "$MUTRC" "$R7B" --json 2>/dev/null | jq -r '[.findings[].rule] | unique | join(" ")')" REF-7)"

R7C="$(mkfixture ref7-unannounced)"   # a salt with nothing announcing it
printf 'saltbytes\n' > "$R7C/.helm-govern-salt"
t_eq "a minted salt with no SessionStart announce fires REF-7" yes "$(fired "$(rules_of "$R7C")" REF-7)"
# Its fix goes through deploy on the live box (install standard §4), and is inject-install on a sandbox (#809).
fixof() { awk -v r="$1" 'f { print; exit } index($0, "  FAIL: " r " ") == 1 { f = 1 }'; }  # <rule>: the line after its FAIL
t_eq "REF-7 off the live box: its fix is inject-install on that dir" \
  "  fix: sh '$(cd -P "$SRC" && pwd -P)/context-injection-install.sh' --apply --dir '$R7C'" "$(sh "$RC" "$R7C" 2>&1 | fixof REF-7)"
LIVE="$HOME/.claude"; cp -R "$R7C" "$LIVE"
_hr="$(sh "$SRC/scope-roots.sh" --get HARBOR_SCOPE_REPO)"
t_eq "REF-7 on the live box (--live): its fix is deploy --only inject" \
  "  fix: sh '$_hr/bin/deploy.sh' --apply --only inject --live" "$(env -u CLAUDE_CONFIG_DIR sh "$RC" --live 2>&1 | fixof REF-7)"
t_eq "...and the same when the live dir is named by its path" \
  "  fix: sh '$_hr/bin/deploy.sh' --apply --only inject --live" "$(env -u CLAUDE_CONFIG_DIR sh "$RC" "$LIVE/" 2>&1 | fixof REF-7)"
t_eq "the fix is its own line: --json's breaks for REF-7 carries no command" 0 \
  "$(sh "$RC" "$R7C" --json 2>/dev/null | jq '[.findings[] | select(.rule == "REF-7") | .breaks | select(test("Fix:|install"))] | length')"
t_eq "REF-6's fix off the live box is constitution-install on that dir" \
  "  fix: sh '$(cd -P "$SRC" && pwd -P)/policy-constitution-install.sh' --apply --dir '$F6'" "$(sh "$RC" "$F6" 2>&1 | fixof REF-6)"
rm -rf "$LIVE"

t_section "mutation: the matcher is load-bearing in REF-2"
MUT="$(mkmut mut-matcher)"
sed 's/| \[\$e, \$m, \.\] | @tsv/| [$e, .] | @tsv/' "$RC" > "$MUT"
t_eq "the matcher mutant differs from the source" yes "$(differs "$RC" "$MUT")"
t_eq "dropping the matcher makes the two-matcher case REF-2" yes "$(fired "$(rules_by "$MUT" "$F2G")" REF-2)"

t_section "mutation: the URL skip is load-bearing in REF-5"
MUT2="$(mkmut mut-urlskip)"  # indent-insensitive: a nesting change once turned it into a copy (#462)
sed -E 's|^[[:space:]]*case "\$ref" in http://.*$|        case "$ref" in mailto:*) continue ;; esac|' "$RC" > "$MUT2"
t_eq "the URL-skip mutant differs from the source" yes "$(differs "$RC" "$MUT2")"
t_eq "removing the URL skip makes the URL fixture REF-5" yes "$(fired "$(rules_by "$MUT2" "$F5G")" REF-5)"

t_section "mutation: the BACKTICK ARM is load-bearing in doc-cited-paths.awk"
MUTA="$(mkmut mut-backtick)"; cp "$RC" "$MUTA"
sed -E 's|match\(t, /`.*`/\)|match(t, /ZZZ_NEVER_MATCHES_ZZZ/)|' "$SRC/doc-cited-paths.awk" > "$TMP/mut-backtick/doc-cited-paths.awk"
t_eq "the backtick mutant differs from the extractor" yes "$(differs "$SRC/doc-cited-paths.awk" "$TMP/mut-backtick/doc-cited-paths.awk")"
t_eq "without the backtick arm the backticked fixture goes green" no "$(fired "$(rules_by "$MUTA" "$F5B")" REF-5)"

t_section "--status: the findings as reconcile rows (contracts/reconcile.md, harbor#1031)"
TB="$(printf '\t')"
rst() { sh "$RC" "$1" --status 2>/dev/null; }   # stdout alone: it is data
t_exit "a clean config dir is exit 0, the plain run's" 0 sh "$RC" "$CLEAN" --status
rst "$CLEAN" > "$TMP/st-clean.out"
t_eq "...the header, then a summary that examined something and drifted nothing" "reconcile${TB}1${TB}drift.reference-check ok" \
  "$(awk -F'\t' 'NR == 1 { printf "%s", $1 FS $2 FS $3 } NR == 2 { printf " %s", ($1 == "summary" && $2 ~ /^[1-9][0-9]*$/ && $3 == 0 && $4 == 0) ? "ok" : "bad" } END { if (NR != 2) printf " lines=%d", NR }' "$TMP/st-clean.out")"
sh "$RC" "$FMIX" --status > "$TMP/st-mix1.out" 2>/dev/null; rc=$?   # the FIRST run on this dir: its rows are the new ones
t_eq "a config dir with findings is exit 1, the plain run's" 1 "$rc"
t_eq "the rows are the findings --json lists, keyed by rule and subject" \
  "$(sh "$RC" "$FMIX" --json 2>/dev/null | jq -r '.findings[] | "\(.rule) \(.subject)"' | LC_ALL=C sort)" \
  "$(awk -F'\t' '$1 == "new" || $1 == "standing" { print $2 }' "$TMP/st-mix1.out" | LC_ALL=C sort)"
t_eq "...each saying what it breaks, in the finding's own words" \
  "$(sh "$RC" "$FMIX" --json 2>/dev/null | jq -r '.findings[] | select(.rule == "REF-5") | .breaks')" \
  "$(awk -F'\t' '$1 == "new" && $2 ~ /^REF-5 / { print $4 }' "$TMP/st-mix1.out")"
t_eq "...and what the rule wants" "every citation in the installed CLAUDE.md resolves" "$(awk -F'\t' '$1 == "new" && $2 ~ /^REF-5 / { print $3 }' "$TMP/st-mix1.out")"
t_eq "the first run: every row is new, with age 0" "$NMIX 0" "$(awk -F'\t' '$1 == "new" && $6 == 0 { n++ } $1 == "standing" { s++ } END { print n + 0 " " s + 0 }' "$TMP/st-mix1.out")"
t_eq "...and the summary counts them drifted" "$NMIX" "$(awk -F'\t' '$1 == "summary" { print $3 }' "$TMP/st-mix1.out")"
rst "$FMIX" > "$TMP/st-mix2.out"
t_eq "a second run with nothing changed prints no new row, and every row stands with an age" "0 $NMIX" \
  "$(awk -F'\t' '$1 == "new" { n++ } $1 == "standing" && $6 ~ /^[0-9]+$/ { s++ } END { print n + 0 " " s + 0 }' "$TMP/st-mix2.out")"
printf '# c\n[a](./REAL.md)\n' > "$FMIX/CLAUDE.md"
rst "$FMIX" > "$TMP/st-mix3.out"
t_eq "findings that are fixed are cleared (the dead citation and the root it lacked), once" 2 "$(grep -c "^cleared${TB}" "$TMP/st-mix3.out")"
t_has "...the dead citation among them" "$(cat "$TMP/st-mix3.out")" "cleared${TB}REF-5 CLAUDE.md → ./NOPE.md"
t_eq "...and the others are still listed" 1 "$(awk -F'\t' '$1 == "standing" && $2 ~ /^REF-2 / { n++ } END { print n + 0 }' "$TMP/st-mix3.out")"
rst "$FMIX" > "$TMP/st-mix4.out"
t_eq "...and not cleared again" 0 "$(grep -c "^cleared${TB}" "$TMP/st-mix4.out")"
# on a dir no --status has touched, so the first run's writes are the ones compared
FRO="$(mkfixture status-ro)"; printf '[gone](./NOPE.md)\n' >> "$FRO/CLAUDE.md"
find "$FRO" -type f -exec cksum {} + | LC_ALL=C sort > "$TMP/st-before.cks"
rst "$FRO" > /dev/null
find "$FRO" -name cache -prune -o -type f -exec cksum {} + | LC_ALL=C sort > "$TMP/st-after.cks"
t_eq "it wrote nothing outside cache/ (the surface it checks is read-only)" "" "$(diff "$TMP/st-before.cks" "$TMP/st-after.cks")"
t_eq "...and the one thing it writes is the first-seen state" "drift.reference-check.tsv" "$(ls "$FRO/cache/reconcile")"

# One script wired under two matchers is two wirings of one item. REF-1 reports each wiring, so the same subject comes twice,
# and a key is unique within a report: --status lists the item once. This box wires guard-egress.sh twice on purpose.
FDUP="$(mkfixture status-dup)"
resettings "$FDUP" --arg g "/bin/sh $FDUP/bin/GONE.sh" --arg h "/bin/sh $FDUP/bin/hook-a.sh" --arg o "/bin/sh $FDUP/bin/GONE2.sh" '
  .hooks.PreToolUse = [{matcher: "Write|Edit", hooks: [{type: "command", command: $g}]},
                       {matcher: "WebFetch",   hooks: [{type: "command", command: $g}]},
                       {matcher: "Read",       hooks: [{type: "command", command: $h}]},
                       {matcher: "Bash",       hooks: [{type: "command", command: $h}]},
                       {matcher: "Glob",       hooks: [{type: "command", command: $o}]}]
  | .hooks.PostToolUse = [{matcher: "", hooks: [{type: "command", command: $g}]}]'
t_eq "plain run: each wiring of the missing script is a finding of its own (unchanged), exit 1" "3 1" \
  "$(sh "$RC" "$FDUP" --json 2>/dev/null | jq -r '[.findings[] | select(.rule == "REF-1" and (.subject | test("GONE.sh$")))] | length') $(sh "$RC" "$FDUP" >/dev/null 2>&1; echo $?)"
sh "$RC" "$FDUP" --status > "$TMP/st-dup1.out" 2>/dev/null; rc=$?
t_eq "--status: a wiring under two matchers in one event is ONE row, and the same script under another event is its own" "PostToolUse PreToolUse" \
  "$(awk -F'\t' '$1 == "new" && $2 ~ /^REF-1 .*\/GONE\.sh$/ { sub(/^REF-1 /, "", $2); sub(/:.*/, "", $2); print $2 }' "$TMP/st-dup1.out" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
t_eq "...a second missing script is another row, and the existing one wired twice is none: 3 rows in all" 3 "$(awk -F'\t' '$1 == "new" || $1 == "standing" { n++ } END { print n + 0 }' "$TMP/st-dup1.out")"
t_eq "...no key twice" "" "$(awk -F'\t' '$1 == "new" || $1 == "standing" { print $2 }' "$TMP/st-dup1.out" | LC_ALL=C sort | uniq -d)"
t_eq "...the summary counts the rows it lists, and the exit is 1" "3 1" "$(awk -F'\t' '$1 == "summary" { print $3 }' "$TMP/st-dup1.out") $rc"
rst "$FDUP" > "$TMP/st-dup2.out"
t_eq "...the second run: the same three, all standing, none new, none twice" "0 3 0" \
  "$(awk -F'\t' '$1 == "new" { n++ } $1 == "standing" { s++; k[$2]++ } END { d = 0; for (x in k) if (k[x] > 1) d++; print n + 0, s + 0, d }' "$TMP/st-dup2.out")"

t_section "--status that cannot judge is exit 3, an unchecked record, and leaves the ages alone"
cp "$FMIX/cache/reconcile/drift.reference-check.tsv" "$TMP/st-state.keep"
PATH="$TMP/nojq" sh "$RC" "$FMIX" --status > "$TMP/st-nojq.out" 2>/dev/null; rc=$?
t_eq "with jq masked: exit" 3 "$rc"
t_eq "...the header and an unchecked record, no summary" "reconcile unchecked" "$(awk -F'\t' '$1 == "reconcile" { a = $1 } $1 == "unchecked" { b = $1 } $1 == "summary" { b = "SUMMARY" } END { print a " " b }' "$TMP/st-nojq.out")"
t_eq "...and the plain run keeps its own code for it (B9: 1, which a caller cannot filter as a typo)" 1 "$(PATH="$TMP/nojq" sh "$RC" "$FMIX" >/dev/null 2>&1; echo $?)"
t_eq "...and the first-seen state is untouched" yes "$(cmp -s "$FMIX/cache/reconcile/drift.reference-check.tsv" "$TMP/st-state.keep" && echo yes || echo no)"
NOLIBS="$(sh "$NOLIB/drift-reference-check.sh" "$CLEAN" --status 2>/dev/null)"; rc=$?
t_eq "a copy with no library-log.sh beside it: exit" 3 "$rc"
t_has "...it says unchecked on stdout, in the contract's shape" "$NOLIBS" "unchecked${TB}library-log.sh is missing beside this copy"

t_section "--status takes --live or one config dir; anything else is a usage error (2) with nothing on stdout"
t_eq "--status --json: exit" 2 "$(sh "$RC" "$CLEAN" --status --json >/dev/null 2>&1; echo $?)"
t_eq "--status --nonsense: exit" 2 "$(sh "$RC" "$CLEAN" --status --nonsense >/dev/null 2>&1; echo $?)"
t_eq "two config dirs: exit" 2 "$(sh "$RC" "$CLEAN" "$FMIX" --status >/dev/null 2>&1; echo $?)"
t_eq "...with nothing on stdout" "" "$(sh "$RC" "$CLEAN" --status --nonsense 2>/dev/null)"
t_eq "valid but unusual: the flags in the other order, and --live, are accepted" "0 0" \
  "$(sh "$RC" --status "$CLEAN" >/dev/null 2>&1; printf '%s ' $?; sh "$RC" --status --live >/dev/null 2>&1; echo $?)"
rm -rf "$TMP/status-nodir"
t_eq "a config dir that does not exist: nothing is installed, a summary of zeros, exit 0" "summary${TB}0${TB}0${TB}0 0" \
  "$(sh "$RC" "$TMP/status-nodir" --status 2>/dev/null | grep '^summary') $(sh "$RC" "$TMP/status-nodir" --status >/dev/null 2>&1; echo $?)"
t_eq "...and the dir is not made for the state" absent "$([ -e "$TMP/status-nodir" ] && echo present || echo absent)"

t_section "mutation: the exit code is wired to the findings"
MUT3="$(mkmut mut-exit)"
sed 's/^  FAIL=\$((FAIL+1))$/  FAIL=$((FAIL+0))/' "$RC" > "$MUT3"
t_eq "the exit-code mutant differs from the source" yes "$(differs "$RC" "$MUT3")"
t_exit "with the counter unwired a dead citation exits" 0 sh "$MUT3" "$F5"
t_done
