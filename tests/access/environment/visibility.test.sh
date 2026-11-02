#!/usr/bin/env sh
# access-environment.sh (harbor#561) against a stubbed gh and a synthetic registry. Every registry row is a
# case: a public repo must render PUBLIC, a private one PRIVATE, and a row the box cannot read must render
# UNKNOWN, never a guessed visibility. The stub answers from a fixture table and fails on any repo it was not
# told about, so no real GitHub call is made. The registry is read through scope-roots.sh --repos (falling back to
# the private layer's inject.d/box/projects.tsv, harbor#1149), and --check holds a fresh render against the live block's visibility lines:
# green when they match, red when a repo's visibility, a line or the whole set differs, never a write.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/access-environment.sh"; FX="$T_TMP/fx"; mkdir -p "$FX"
GH="$FX/gh"; REG="$FX/projects.tsv"; OUT="$FX/out.txt"

# Synthetic checkouts: a public GitHub repo, a private one (scp-style remote), one with no remote, one not on disk,
# and one whose repo the stub does not know (a gh failure).
mkdir -p "$FX/pub" "$FX/priv" "$FX/noremote" "$FX/gone"
git -C "$FX/pub" init -q && git -C "$FX/pub" remote add origin https://github.com/exampleorg/pubrepo.git
git -C "$FX/priv" init -q && git -C "$FX/priv" remote add origin git@github.com:exampleorg/privrepo.git
git -C "$FX/noremote" init -q
git -C "$FX/gone" init -q && git -C "$FX/gone" remote add origin https://github.com/exampleorg/gone.git
printf 'pubrow\t%s\tpublic fixture\nprivrow\t%s\tprivate fixture\nnoremrow\t%s\tno origin\nmissrow\t%s/absent\tnot on disk\ngonerow\t%s\tgh fails\n' \
  "$FX/pub" "$FX/priv" "$FX/noremote" "$FX" "$FX/gone" > "$REG"

# The stub: it answers from a file per repo (`$GH.ans.<repo>`), so a case flips a verdict by rewriting the file
# and fails a repo by removing it; any repo with no file is a gh error (exit 1, no verdict). Every call is logged
# beside the stub itself, so the test can see which repos were asked about.
cat > "$GH" <<'STUB'
#!/bin/sh
echo "$*" >> "$0.calls"
case "$*" in
  "repo view exampleorg/"*" --json visibility --jq .visibility")
    _r="${3#exampleorg/}"
    [ -f "$0.ans.$_r" ] && { cat "$0.ans.$_r"; exit 0; } ;;
esac
echo "gh: could not resolve repository" >&2; exit 1
STUB
chmod +x "$GH"
echo PUBLIC > "$GH.ans.pubrepo"; echo PRIVATE > "$GH.ans.privrepo"

t_section "a public repo renders PUBLIC and a private one PRIVATE"
sh "$TOOL" --registry "$REG" --gh "$GH" > "$OUT" 2>"$FX/err.txt"; RC=$?
t_eq "generator exits 0" 0 "$RC"
t_has "public repo line" "$(cat "$OUT")" "- pubrow (exampleorg/pubrepo): PUBLIC"
t_has "private repo line" "$(cat "$OUT")" "- privrow (exampleorg/privrepo): PRIVATE"
t_hasnt "public repo is not rendered private" "$(cat "$OUT")" "pubrepo): PRIVATE"

t_section "a row the box cannot read is UNKNOWN, never assumed private"
t_has "no origin remote is UNKNOWN" "$(cat "$OUT")" "- noremrow: UNKNOWN (no origin remote"
t_has "a missing checkout is UNKNOWN" "$(cat "$OUT")" "- missrow: UNKNOWN (no checkout"
t_hasnt "no line says assume" "$(cat "$OUT")" "assume private"

t_section "a gh failure is UNKNOWN, not PRIVATE"
t_has "gh failure is UNKNOWN" "$(cat "$OUT")" "- gonerow (exampleorg/gone): UNKNOWN (gh repo view gave no visibility)"
t_hasnt "gh failure is not PRIVATE" "$(cat "$OUT")" "gone): PRIVATE"
t_has "gh was asked about the failing repo" "$(cat "$GH.calls")" "repo view exampleorg/gone"

t_section "an unreadable registry is a usage error, not an empty block"
sh "$TOOL" --registry "$FX/none.tsv" --gh "$GH" >/dev/null 2>&1; RC=$?
t_eq "missing registry exits 2" 2 "$RC"

# ── the registry: scope-roots.sh --repos first, the private layer's projects.tsv when there is none ─────────
# A fixture workspace: PORT_ROOT holds the checkouts, the private layer holds repos.tsv (id path kind remote, the path relative to PORT_ROOT). HARBOR_SCOPE_ROOT is
# a root whose bin/, contracts/ and standards/ are the real ones. A second private layer carries only inject.d/box/projects.tsv (harbor#1149: core ships none), so the fallback names nothing of this box.
WS="$FX/ws"; PRIV="$FX/private"; HR="$FX/hroot"; PROJ="$FX/projonly"
mkdir -p "$WS" "$PRIV" "$HR" "$PROJ/inject.d/box"
cp -R "$FX/pub" "$WS/pubrepo-checkout"; cp -R "$FX/priv" "$WS/privrepo-checkout"
printf 'id\tpath\tkind\tremote\nwspub\tpubrepo-checkout\tworkload\t-\nwspriv\tprivrepo-checkout\tworkload\t-\n' > "$PRIV/repos.tsv"
ln -s "$T_ROOT/bin" "$HR/bin"; ln -s "$T_ROOT/contracts" "$HR/contracts"; ln -s "$T_ROOT/standards" "$HR/standards"
printf 'fallbackrow\t%s\tonly in projects.tsv\n' "$FX/pub" > "$PROJ/inject.d/box/projects.tsv"
mkdir -p "$PRIV/inject.d/box"; cp "$PROJ/inject.d/box/projects.tsv" "$PRIV/inject.d/box/projects.tsv"   # beside repos.tsv: never read
envrun() { # <private dir> [tool args…] → the tool run in the fixture workspace; stdout then stderr in $FX/e.out / e.err
  _p="$1"; shift
  HARBOR_SCOPE_ROOT="$HR" HARBOR_SCOPE_PRIVATE="$_p" PORT_ROOT="$WS" sh "$TOOL" "$@" > "$FX/e.out" 2> "$FX/e.err"; ERC=$?
}

t_section "the repos come from scope-roots.sh --repos when the private layer has a registry"
envrun "$PRIV" --gh "$GH"
t_eq "exits 0" 0 "$ERC"
t_has "a registry row is rendered with its checkout's visibility (public)" "$(cat "$FX/e.out")" "- wspub (exampleorg/pubrepo): PUBLIC"
t_has "...and the private one" "$(cat "$FX/e.out")" "- wspriv (exampleorg/privrepo): PRIVATE"
t_hasnt "projects.tsv is not read while a registry exists" "$(cat "$FX/e.out")" "fallbackrow"
t_has "the log says which registry it read" "$(cat "$FX/e.err")" "registry: scope-roots.sh --repos"

t_section "no repos.tsv: the private layer's inject.d/box/projects.tsv"
envrun "$PROJ" --gh "$GH"
t_eq "exits 0" 0 "$ERC"
t_has "the fallback row is rendered" "$(cat "$FX/e.out")" "- fallbackrow (exampleorg/pubrepo): PUBLIC"
t_hasnt "...and none of the registry's" "$(cat "$FX/e.out")" "wspub"
t_has "the log names the fallback" "$(cat "$FX/e.err")" "registry: inject.d/box/projects.tsv"

t_section "no private layer: no registry, exit 2 and never this box's"
envrun "$FX/no-private-layer" --gh "$GH"
t_eq "exits 2" 2 "$ERC"
t_eq "no block is printed" "" "$(cat "$FX/e.out")"

t_section "a registry that exists and is invalid is refused, never read around"
printf 'id\tpath\tkind\tremote\nbad\t../outside\tworkload\t-\n' > "$PRIV/repos.tsv.bad"
mkdir -p "$FX/privbad"; cp "$PRIV/repos.tsv.bad" "$FX/privbad/repos.tsv"
envrun "$FX/privbad" --gh "$GH"
t_eq "an escaping path exits 2" 2 "$ERC"
t_eq "no block is printed" "" "$(cat "$FX/e.out")"
t_has "the reason is scope-roots.sh's" "$(cat "$FX/e.err")" "scope-roots.sh --repos refused"

t_section "--registry names a file and wins over both"
envrun "$PRIV" --registry "$REG" --gh "$GH"
t_has "the named file's row is rendered" "$(cat "$FX/e.out")" "- pubrow (exampleorg/pubrepo): PUBLIC"
t_hasnt "...and the private layer's is not" "$(cat "$FX/e.out")" "wspub"

# ── --check ───────────────────────────────────────────────────────────────────────────────────────────
# REG2 holds only rows gh can answer or that are UNKNOWN for a stable reason, so every line is judged.
REG2="$FX/projects2.tsv"; head -n 4 "$REG" > "$REG2"
CTL="$T_ROOT/standards/naming/controls.tsv"; ID=drift.repo-visibility
awk -F'\t' -v id="$ID" 'BEGIN { OFS = "\t" } $1 == id { $2 = "block" } { print }' "$CTL" > "$FX/ctl-block.tsv"
BLOCK="$(sh "$TOOL" --registry "$REG2" --gh "$GH" 2>/dev/null)"
live() { # <file> <environment element…> → a settings.json whose autoMode.environment is those strings
  _f="$1"; shift
  jq -n '{autoMode: {environment: $ARGS.positional}, other: "kept"}' --args "$@" > "$_f"
}
chk() { # <settings> [tool args…] → the check's output in $CO, its exit in $CRC
  _s="$1"; shift
  CO="$(sh "$TOOL" --check --registry "$REG2" --gh "$GH" --settings "$_s" --controls "$CTL" "$@" 2>&1)"; CRC=$?
}
TODAY="**Repository visibility**: Not queryable via gh (no remote configured for this repo); assume private per shipped default"

t_section "the control is registered, warn, with this suite as its proof"
t_eq "controls.tsv has the row as warn, type check, owner drift" "warn check drift" "$(awk -F'\t' -v id="$ID" '$1 == id { print $2, $3, $10 }' "$CTL")"
t_eq "...and its red_proof is this suite" "tests/access/environment/visibility.test.sh" "$(awk -F'\t' -v id="$ID" '$1 == id { print $11 }' "$CTL")"

t_section "a live block that matches a fresh render is green"
live "$FX/s-green.json" "### Org-wide" "**Source control**: The trusted repo and its remote(s) only" "$BLOCK"
chk "$FX/s-green.json"
t_eq "exits 0" 0 "$CRC"
t_has "says the lines match" "$CO" "ok: the live block's 4 visibility lines match a fresh render of 4 repos (0 not judged)"
t_hasnt "no finding" "$CO" "WARN"

t_section "the block as it is today (every repo assumed private) is red"
live "$FX/s-today.json" "### Org-wide" "$TODAY" "**Source control**: The trusted repo and its remote(s) only"
RL="$FX/redlog"; : > "$RL"; NC0="$(wc -l < "$GH.calls" | tr -d ' ')"
CO="$(LINT_REDLOG="$RL" sh "$TOOL" --check --registry "$REG2" --gh "$GH" --settings "$FX/s-today.json" --controls "$CTL" 2>&1)"; CRC=$?
t_has "WARN names the control" "$CO" "WARN: drift.repo-visibility:"
t_has "says the block carries no repo-visibility line" "$CO" "carries no repo-visibility line, so 4 governed repos are undescribed"
t_has "quotes what the block says instead" "$CO" "it says: **Repository visibility**: Not queryable via gh"
t_has "...including the assumption" "$CO" "assume private per shipped default"
t_eq "warn mode exits 0 (D-49)" 0 "$CRC"
t_eq "the id is appended to LINT_REDLOG" "$ID" "$(cat "$RL")"
t_eq "it spent no gh call to say so" "$NC0" "$(wc -l < "$GH.calls" | tr -d ' ')"

t_section "the generated lines beside the old assumption are red: two answers for one repo"
live "$FX/s-contra.json" "### Org-wide" "$TODAY" "$BLOCK"
RL2="$FX/redlog2"; : > "$RL2"
CO="$(LINT_REDLOG="$RL2" sh "$TOOL" --check --registry "$REG2" --gh "$GH" --settings "$FX/s-contra.json" --controls "$CTL" 2>&1)"; CRC=$?
t_has "WARN names the control" "$CO" "WARN: drift.repo-visibility: the live block still says \"**Repository visibility**: Not queryable via gh"
t_has "...quotes the assumption and counts the lines it sits beside" "$CO" "assume private per shipped default\" beside its 4 generated visibility lines"
t_hasnt "...and the lines themselves are not the finding" "$CO" "a fresh render says"
t_hasnt "...nor does it say the lines are missing" "$CO" "carries no repo-visibility line"
t_eq "warn mode exits 0 (D-49)" 0 "$CRC"
t_eq "the id is appended to LINT_REDLOG" "$ID" "$(cat "$RL2")"
chk "$FX/s-contra.json" --controls "$FX/ctl-block.tsv"
t_eq "block: exits 1" 1 "$CRC"
live "$FX/s-contra2.json" "$BLOCK" "**Visibility note**: unlisted repos: we assume them private"
chk "$FX/s-contra2.json"
t_has "another spelling of the assumption is read too (assumed/assume them private)" "$CO" "the live block still says \"**Visibility note**: unlisted repos: we assume them private\""
live "$FX/s-contra3.json" "### Repository visibility" "**Unlisted hosts**: assume private" "**Repository visibility**: never assume private; the lines below are generated" "Repository visibility isn't assumed private either." "$BLOCK"
chk "$FX/s-contra3.json"
t_has "valid but unusual: an assumption about hosts, and visibility lines that say they do NOT assume, stay green" "$CO" "ok: the live block's 4 visibility lines match"
t_hasnt "...with no finding" "$CO" "WARN"

t_section "a repo's visibility changing makes a matching block red"
echo PRIVATE > "$GH.ans.pubrepo"
chk "$FX/s-green.json"
t_has "the repo is named" "$CO" "pubrow: the live block says \"- pubrow (exampleorg/pubrepo): PUBLIC\""
t_has "...with the fresh verdict" "$CO" "a fresh render says \"- pubrow (exampleorg/pubrepo): PRIVATE\""
t_eq "exits 0 under warn" 0 "$CRC"
echo PUBLIC > "$GH.ans.pubrepo"
chk "$FX/s-green.json"
t_has "restored, the same block is green again" "$CO" "ok: the live block's 4 visibility lines match"

t_section "a missing line, a stale line and a different slug are each a finding"
live "$FX/s-missing.json" "$(printf '%s\n' "$BLOCK" | grep -v '^- privrow')"
chk "$FX/s-missing.json"
t_has "a repo the block lacks" "$CO" "the live block has no line for privrow"
live "$FX/s-stale.json" "$BLOCK" "- oldrepo (exampleorg/oldrepo): PUBLIC"
chk "$FX/s-stale.json"
t_has "a repo the registry no longer has" "$CO" "the live block names oldrepo"
live "$FX/s-slug.json" "$(printf '%s\n' "$BLOCK" | sed 's#exampleorg/pubrepo#exampleorg/renamed#')"
chk "$FX/s-slug.json"
t_has "a repo whose slug changed" "$CO" "pubrow: the live block says"
live "$FX/s-dup.json" "$BLOCK" "- pubrow (exampleorg/pubrepo): PUBLIC"
chk "$FX/s-dup.json"
t_has "a repo named twice" "$CO" "the live block names pubrow more than once"

t_section "valid but unusual blocks stay green"
live "$FX/s-shuffled.json" "$(printf '%s\n' "$BLOCK" | awk 'NR == 1 { print; next } { a[++n] = $0 } END { for (i = n; i >= 1; i--) print a[i] }')"
chk "$FX/s-shuffled.json"
t_has "the lines in another order" "$CO" "ok: the live block's 4 visibility lines match"
live "$FX/s-split.json" "Repository visibility, as of generation:" "  - pubrow (exampleorg/pubrepo): PUBLIC  " "- privrow (exampleorg/privrepo): PRIVATE" "$(printf '%s\n' "$BLOCK" | sed -n '4,5p')" "- an unrelated bullet: with a colon" "**Source control**: remotes only"
chk "$FX/s-split.json"
t_has "one element per line, indented, trailing spaces, other bullets and prose around them" "$CO" "ok: the live block's 4 visibility lines match"
t_hasnt "...and no finding" "$CO" "WARN"
jq -n '{autoMode: {environment: "single string, no lines"}}' > "$FX/s-str.json"
chk "$FX/s-str.json"
t_has "an environment that is one string is read, and found to carry no line" "$CO" "carries no repo-visibility line"

t_section "a gh failure is not drift"
live "$FX/s-green5.json" "$(sh "$TOOL" --registry "$REG" --gh "$GH" 2>/dev/null)"
rm -f "$GH.ans.privrepo"
CO="$(sh "$TOOL" --check --registry "$REG" --gh "$GH" --settings "$FX/s-green5.json" --controls "$CTL" 2>&1)"; CRC=$?
echo PRIVATE > "$GH.ans.privrepo"
t_has "the repo gh could not answer is NOT JUDGED, said so" "$CO" "not judged: privrow: gh gave no answer now"
t_hasnt "...and is not a finding" "$CO" "WARN"
t_eq "exits 0" 0 "$CRC"
REG3="$FX/projects3.tsv"; head -n 2 "$REG" > "$REG3"
live "$FX/s-green3.json" "$(sh "$TOOL" --registry "$REG3" --gh "$GH" 2>/dev/null)"
rm -f "$GH.ans.privrepo" "$GH.ans.pubrepo"
CO="$(sh "$TOOL" --check --registry "$REG3" --gh "$GH" --settings "$FX/s-green3.json" --controls "$CTL" 2>&1)"; CRC=$?
echo PUBLIC > "$GH.ans.pubrepo"; echo PRIVATE > "$GH.ans.privrepo"
t_eq "gh answering nothing for any repo is unchecked, exit 3" 3 "$CRC"
t_has "...and says why" "$CO" "gh gave no answer for any of the 2 repos"

t_section "the mode is read from controls.tsv, never from here"
echo PRIVATE > "$GH.ans.pubrepo"
chk "$FX/s-green.json" --controls "$FX/ctl-block.tsv"
t_eq "block: a finding exits 1" 1 "$CRC"
t_has "...as a FAIL" "$CO" "FAIL: drift.repo-visibility: pubrow:"
awk -F'\t' -v id="$ID" 'BEGIN { OFS = "\t" } $1 == id { $2 = "shadow" } { print }' "$CTL" > "$FX/ctl-shadow.tsv"
: > "$RL"
CO="$(LINT_REDLOG="$RL" sh "$TOOL" --check --registry "$REG2" --gh "$GH" --settings "$FX/s-green.json" --controls "$FX/ctl-shadow.tsv" 2>&1)"; CRC=$?
t_eq "shadow: exits 0" 0 "$CRC"
t_eq "...prints nothing" "" "$CO"
t_eq "...and still records the id" "$ID" "$(cat "$RL")"
echo PUBLIC > "$GH.ans.pubrepo"
grep -v "^$ID	" "$CTL" > "$FX/ctl-norow.tsv"
chk "$FX/s-green.json" --controls "$FX/ctl-norow.tsv"
t_eq "no row: unchecked, exit 3" 3 "$CRC"
t_has "...naming the row" "$CO" "no controls.tsv row for drift.repo-visibility"

t_section "unchecked and usage exits, and settings.json is only ever read"
chk "$FX/no-such-settings.json"
t_eq "no settings.json is unchecked, exit 3" 3 "$CRC"
printf 'not json' > "$FX/s-bad.json"
chk "$FX/s-bad.json"
t_eq "a settings.json that is not JSON is unchecked, exit 3" 3 "$CRC"
t_has "...and names the file" "$CO" "settings.json is not readable as JSON"
: > "$FX/empty.tsv"
CO="$(sh "$TOOL" --check --registry "$FX/empty.tsv" --gh "$GH" --settings "$FX/s-green.json" --controls "$CTL" 2>&1)"; CRC=$?
t_eq "an empty registry is unchecked, exit 3" 3 "$CRC"
sh "$TOOL" --check --bogus >/dev/null 2>&1; t_eq "an unknown flag exits 2" 2 "$?"
sh "$TOOL" --check --settings >/dev/null 2>&1; t_eq "--settings without a file exits 2" 2 "$?"
BEFORE="$(cksum < "$FX/s-green.json")$(cksum < "$FX/s-today.json")"
chk "$FX/s-green.json"; chk "$FX/s-today.json"
t_eq "settings.json is byte-identical after a green and a red check" "$BEFORE" "$(cksum < "$FX/s-green.json")$(cksum < "$FX/s-today.json")"
t_has "--help shows the usage block, not only the first paragraph" "$(sh "$TOOL" --help)" "sh access-environment.sh --check"

t_done
