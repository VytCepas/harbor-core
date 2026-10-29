#!/usr/bin/env sh
# deny-hash.sh, the salted-hash leak filter (M7, harbor#44, PR #127). Hermetic: a fixture salt and
# fixture terms in a throwaway dir, never the operator's corpus. The two properties that matter are
# no plaintext in the filter (DH-3) and a scan that goes RED on a term but not a near miss (DH-5/6).
REAL_LIVE="$HOME/.claude"  # read before t_init sandboxes HOME; DH-12 compares it, nothing touches it
. "$(dirname "$0")/../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/deny-hash.sh"; B="$T_TMP"
yn() { if "$@"; then echo yes; else echo no; fi; }
manifest() { find "$1" -type f -exec ls -ld -- {} + 2>/dev/null | awk '{print $5, $NF}' | sort; }  # <dir>
lines() { wc -l < "$1" | tr -d ' '; }

CFG="$B/dh"; mkdir -p "$CFG"
printf '0123456789abcdef0123456789abcdef\n' > "$CFG/.helm-obs-salt"  # 32 hex, as floor_obs_digest needs
T1=acme-corp-internal; T2=vytautas@example-client.lt; T3=sk-CUSTOMPREFIX-9382
printf '# comment ignored\n%s\n%s\n%s\nmulti word term\n' "$T1" "$T2" "$T3" > "$CFG/.helm-deny-terms"
FILTER="$CFG/.helm-deny-hashes"

t_section "DH-1: --derive turns declared terms into a digest filter"
t_exit "DH-1a --derive on a good fixture" 0 sh "$TOOL" --derive "$CFG"
t_eq "DH-1b a filter was written" yes "$(yn [ -f "$FILTER" ])"
t_eq "DH-1c three digests, the multi-word term refused" 3 "$(lines "$FILTER")"
t_eq "DH-1d every line is a 16-hex digest" 0 "$(grep -cvE '^[0-9a-f]{16}$' "$FILTER")"

t_section "DH-2: a multi-word term is REFUSED, not silently stored"
t_has "DH-2 the refusal is printed" "$(sh "$TOOL" --derive "$CFG" 2>&1)" 'refusing multi-word term'

t_section "DH-3: THE FILTER CONTAINS NO PLAINTEXT"
for t in "$T1" "$T2" "$T3"; do t_hasnt "DH-3 no plaintext $t in the filter" "$(cat "$FILTER")" "$t"; done
t_hasnt "DH-3 no term fragment in the filter" "$(cat "$FILTER")" 'acme'

t_section "DH-4: the filter is not world-readable"
t_eq "DH-4 filter mode" -rw------- "$(ls -l "$FILTER" | cut -c1-10)"

t_section "DH-5: a scan GOES RED on a declared term, and names no value"
printf 'notes: reach %s for the handover\n' "$T2" > "$B/hit.txt"
t_exit "DH-5a a scan over a declared term" 1 sh "$TOOL" --scan "$CFG" "$B/hit.txt"
o="$(sh "$TOOL" --scan "$CFG" "$B/hit.txt" 2>&1)"
t_hasnt "DH-5b the scan does not print the matched term" "$o" "$T2"
t_has "DH-5c the scan reports a hit" "$o" 'HIT'

t_section "DH-6: a NEAR MISS stays green"
printf '%sX %s more-text\n' "$T1" "$(printf '%s' "$T1" | cut -c1-10)" > "$B/near.txt"
t_exit "DH-6a a near-miss token" 0 sh "$TOOL" --scan "$CFG" "$B/near.txt"
printf 'ordinary content, support@example.com, nothing private\n' > "$B/clean.txt"
t_exit "DH-6b benign content" 0 sh "$TOOL" --scan "$CFG" "$B/clean.txt"

t_section "DH-7: an unhashable box REFUSES, and never reports clean"
NOSALT="$B/nosalt"; mkdir -p "$NOSALT"; cp "$FILTER" "$NOSALT/"
t_exit "DH-7a a scan without a salt" 2 sh "$TOOL" --scan "$NOSALT" "$B/hit.txt"
t_has "DH-7b the refusal says why" "$(sh "$TOOL" --scan "$NOSALT" "$B/hit.txt" 2>&1)" 'report CLEAN'
NOSALT2="$B/nosalt2"; mkdir -p "$NOSALT2"; cp "$CFG/.helm-deny-terms" "$NOSALT2/"
t_exit "DH-7c --derive without a salt" 2 sh "$TOOL" --derive "$NOSALT2"
t_eq "DH-7d --derive wrote no filter without a salt" no "$(yn [ -f "$NOSALT2/.helm-deny-hashes" ])"

t_section "DH-8: a scan with no filter refuses rather than passing"
NOFILT="$B/nofilter"; mkdir -p "$NOFILT"; cp "$CFG/.helm-obs-salt" "$NOFILT/"
t_exit "DH-8 a scan with no filter" 2 sh "$TOOL" --scan "$NOFILT" "$B/hit.txt"

t_section "DH-9: --propose writes NOTHING, in any circumstance"
PROP="$B/prop"; mkdir -p "$PROP/MEMORY/TELOS"
printf 'goal: work with %s and reach %s\n' "$T1" "$T2" > "$PROP/MEMORY/IDENTITY.md"
cp "$CFG/.helm-obs-salt" "$PROP/"
before="$(manifest "$PROP")"; sh "$TOOL" --propose "$PROP" >/dev/null 2>&1; after="$(manifest "$PROP")"
t_eq "DH-9a --propose left the tree it read unchanged" "$before" "$after"
t_eq "DH-9b the manifest compared is not empty" yes "$(yn [ -n "$before" ])"
t_eq "DH-9c --propose wrote no terms file" no "$(yn [ -f "$PROP/.helm-deny-terms" ])"
t_eq "DH-9d --propose wrote no filter" no "$(yn [ -f "$PROP/.helm-deny-hashes" ])"
t_has "DH-9e --propose surfaces a corpus term" "$(sh "$TOOL" --propose "$PROP" 2>/dev/null)" "$T2"

t_section "DH-10: --derive refuses the live dir without an explicit --live (lint D2)"
# The live dir is the sandbox's, created first: absent, --derive falls back to the config dir.
LIVE_DIR="$HOME/.claude"; mkdir -p "$LIVE_DIR"; ln -s "$LIVE_DIR" "$B/live-link"
o="$(sh "$TOOL" --derive "$LIVE_DIR" 2>&1)"; rc=$?
t_eq "DH-10a --derive on the live dir with no --live exits" 1 "$rc"
t_has "DH-10b that refusal is the --live gate" "$o" 'refusing to write the LIVE filter'
o="$(sh "$TOOL" --derive "$B/live-link" 2>&1)"; rc=$?
t_eq "DH-10c a symlinked spelling of the live dir exits" 1 "$rc"
t_has "DH-10d that refusal is the --live gate" "$o" 'refusing to write the LIVE filter'

t_section "DH-11: usage errors, and --json"
t_exit "DH-11a no mode" 2 sh "$TOOL"
t_exit "DH-11b an unknown option" 2 sh "$TOOL" --nonsuch
j="$(sh "$TOOL" --scan --json "$CFG" "$B/hit.txt" 2>/dev/null)"
t_eq "DH-11c --json reports the hit count" 1 "$(printf '%s' "$j" | jq -r '.hit_count' 2>/dev/null)"
t_eq "DH-11d --json carries a 16-hex digest" true "$(printf '%s' "$j" | jq '.hits[0].digest | test("^[0-9a-f]{16}$")' 2>/dev/null)"
t_eq "DH-11e --json carries no term" 0 "$(printf '%s' "$j" | jq --arg t "$T2" '[..|strings] | map(select(. == $t)) | length' 2>/dev/null)"

t_section "DH-12: the suite is nowhere near the operator's own corpus or filter"
t_eq "DH-12a the fixture is outside the real live dir" no "$(case "$CFG" in ("$REAL_LIVE"|"$REAL_LIVE"/*) echo yes ;; (*) echo no ;; esac)"
t_eq "DH-12b the salt under test is the fixture salt" 0123456789abcdef0123456789abcdef "$(cat "$CFG/.helm-obs-salt")"

t_section "DH-13: a term the scanner cannot reproduce is REFUSED (PR #127)"
RT="$B/rt"; mkdir -p "$RT"; cp "$CFG/.helm-obs-salt" "$RT/"
printf 'client:api/key\nZm9vYmFyYmF6cXV1eA==\nplain-ok-token\n' > "$RT/.helm-deny-terms"; chmod 600 "$RT/.helm-deny-terms"
o="$(sh "$TOOL" --derive "$RT" 2>&1)"
t_eq "DH-13a only the round-tripping term is stored" 1 "$(lines "$RT/.helm-deny-hashes")"
t_has "DH-13b the refusal is printed" "$o" 'cannot reproduce as one token'
printf 'plain-ok-token\n' > "$RT/.helm-deny-terms"; chmod 600 "$RT/.helm-deny-terms"
sh "$TOOL" --derive "$RT" >/dev/null 2>&1
t_eq "DH-13c an ordinary single-token term is still accepted" 1 "$(lines "$RT/.helm-deny-hashes")"

t_section "DH-14: an unreadable input REFUSES, and never reports clean (PR #127)"
t_exit "DH-14a a missing input" 2 sh "$TOOL" --scan "$CFG" "$B/does-not-exist"
t_exit "DH-14b a directory input" 2 sh "$TOOL" --scan "$CFG" "$B"
ur="$B/unreadable.txt"; : > "$ur"; chmod 000 "$ur"
if [ ! -r "$ur" ]; then t_exit "DH-14c an unreadable input" 2 sh "$TOOL" --scan "$CFG" "$ur"
else echo "  SKIP DH-14c: this user reads a mode-000 file (root), so there is no unreadable input to give"; fi
chmod 644 "$ur"
printf 'notes: reach %s for the handover\n' "$T2" > "$B/a file with spaces.txt"
t_exit "DH-14d a filename with spaces is scanned and hits" 1 sh "$TOOL" --scan "$CFG" "$B/a file with spaces.txt"
t_done
