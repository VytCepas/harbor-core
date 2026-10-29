#!/usr/bin/env sh
# admission-mutation-tier.sh, the four-tier path classifier (M10, harbor#44, PR #126/#128). It fires the REAL
# guard-selfedit.sh at every fixture path and rebuilds the deny array from the repo's own writers
# (sec0-harden + floor-deny) into a sandbox config dir, so the table and the enforced surface agree.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/admission-mutation-tier.sh"; FIX="$T_ROOT/fixtures/mutation-tier/cases.json"; B="$T_TMP"
tier() { CLAUDE_CONFIG_DIR="${2:-$CFG}" sh "$TOOL" "$1" 2>/dev/null | awk '{print $2}'; }   # <path> [cfg]
scope() { CLAUDE_CONFIG_DIR="${2:-$CFG}" sh "$TOOL" "$1" 2>/dev/null | awk '{print $1}'; }  # <path> [cfg]
jtrue() { CLAUDE_CONFIG_DIR="$CFG" sh "$TOOL" --json "$1" 2>/dev/null | jq -e "$2" >/dev/null 2>&1 && echo true || echo false; }
manifest() { find "$1" -type f -exec ls -ld -- {} + 2>/dev/null | awk '{print $5, $NF}' | sort; }  # <dir>

CFG="$B/mt"; mkdir -p "$CFG/bin"
for g in guard-lib.sh guard-selfedit.sh guard-integrity.sh; do [ -f "$T_ROOT/bin/$g" ] && cp "$T_ROOT/bin/$g" "$CFG/bin/$g"; done
printf '{"permissions":{"allow":[],"deny":[]}}\n' > "$CFG/settings.json"
CLAUDE_CONFIG_DIR="$CFG" sh "$T_ROOT/bin/deploy-harden.sh" --apply --dir "$CFG" >/dev/null 2>&1
CLAUDE_CONFIG_DIR="$CFG" sh "$T_ROOT/bin/floor-deny.sh" --apply --dir "$CFG" >/dev/null 2>&1

t_section "MT-1: every fixture path classifies as the table says"
while IFS='	' read -r p want; do
  [ -n "$p" ] || continue
  t_eq "MT-1 tier of $p" "$want" "$(tier "$CFG/$p")"
done <<CASES
$(jq -r '.cases[] | [.path, (.tier|tostring)] | @tsv' "$FIX")
CASES

t_section "MT-2: the REAL guard agrees with the table, path by path"
# The parent is created first: guard-selfedit resolves the target physically, and an unresolvable
# path keeps a spelling its globs miss (a false "UNPROTECTED" found while building this, §2.11).
while IFS='	' read -r p want; do
  [ -n "$p" ] || continue
  mkdir -p "$(dirname -- "$CFG/$p")"
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$CFG/$p" \
    | CLAUDE_CONFIG_DIR="$CFG" sh "$CFG/bin/guard-selfedit.sh" >/dev/null 2>&1
  rc=$?; got=no; [ "$rc" = 2 ] && got=yes
  t_eq "MT-2 guard-selfedit blocks $p" "$want" "$got"
done <<CASES
$(jq -r '.cases[] | [.path, (if .guard_blocks then "yes" else "no" end)] | @tsv' "$FIX")
CASES

t_section "MT-3: the deny array agrees with the table, rebuilt from the repo's writers"
REP="$B/report.txt"; sh "$TOOL" --report "$CFG" > "$REP" 2>/dev/null  # one run: it probes every path
while IFS='	' read -r p want; do
  [ -n "$p" ] || continue
  got="$(awk -v p="$p" '$1 == p {print $4}' "$REP")"
  t_eq "MT-3 deny coverage for $p" "$want" "${got:-(absent)}"
done <<CASES
$(jq -r '.cases[] | [.path, (if .deny then "yes" else "no" end)] | @tsv' "$FIX")
CASES

t_section "MT-4: the table cannot drift silently — a wrong tier goes RED"
bogus="$(jq -r '(.cases[] | select(.path == "settings.json") | .tier) = 3 | .cases[] | select(.path == "settings.json") | .tier' "$FIX")"
t_eq "MT-4 a tier edited to disagree diverges from the classifier" yes \
  "$(if [ "$(tier "$CFG/settings.json")" != "$bogus" ]; then echo yes; else echo no; fi)"

t_section "MT-5: the report names the single-layer paths, and counts them"
rep="$(sh "$TOOL" --report "$CFG" 2>/dev/null)"
t_has "MT-5a the report flags a guard-only tier-1 path" "$rep" 'NO DENY BACKSTOP'
# MT-5b's subject was .helm-obs-salt, deny-only until harbor#779. The guard now covers it, so the
# report is asked about a copy of the guard with that arm cut: the same gap, planted.
MR="$B/mroot"; mkdir -p "$MR/bin" "$MR/fixtures/mutation-tier"
cp "$FIX" "$MR/fixtures/mutation-tier/"; cp "$T_ROOT/bin/guard-lib.sh" "$MR/bin/"
sed '/"\$root\/\.helm-obs-salt"/d' "$T_ROOT/bin/guard-selfedit.sh" > "$MR/bin/guard-selfedit.sh"
_mt5() { printf '%s\n' "$1" | awk '$1 == ".helm-obs-salt"'; }  # <report> → the salt's row
t_has "MT-5b the report flags a deny-only tier-0 path (the salt's guard arm cut)" \
  "$(_mt5 "$(HARBOR_ROOT="$MR" sh "$TOOL" --report "$CFG" 2>/dev/null)")" 'guard does not cover it'
t_hasnt "MT-5d the real guard covers the salt, so the report does not flag it (harbor#779)" "$(_mt5 "$rep")" 'guard does not cover it'
t_has "MT-5d ...and the row it read is the salt's" "$(_mt5 "$rep")" '.helm-obs-salt'
n="$(printf '%s' "$rep" | sed -n 's/^  note: single-layer or unprotected tier-0\/1 paths: //p')"
t_eq "MT-5c the gap count is a number of at least 1" yes \
  "$(case "${n:-x}" in (''|*[!0-9]*) echo "not a number: '$n'" ;; (*) [ "$n" -ge 1 ] && echo yes || echo 0 ;; esac)"

t_section "MT-12: the report's own lines are log lines, its table stays data (harbor#771)"
rep_rc=0; sh "$TOOL" --report "$CFG" > "$B/rep12.out" 2> "$B/rep12.err" || rep_rc=$?
rep12="$(cat "$B/rep12.out")"
t_eq "MT-12a the report exits 0: a gap is a WARN, never a failure" 0 "$rep_rc"
t_eq "MT-12b ...and nothing goes to stderr" "" "$(cat "$B/rep12.err")"
t_eq "MT-12c the first line is the header" "── mutation-tier · report on $CFG" "$(head -1 "$B/rep12.out")"
t_eq "MT-12d one WARN per single-layer path, as many as the count says" "${n:-x}" "$(grep -c '^  WARN: ' "$B/rep12.out")"
t_eq "MT-12e every WARN is followed by its fix line" "$(grep -c '^  WARN: ' "$B/rep12.out")" \
  "$(awk '/^  WARN: /{w=1; next} w && /^  fix: /{n++} {w=0} END{print n+0}' "$B/rep12.out")"
t_has "MT-12f a WARN names the path, its tier and the finding" "$rep12" '  WARN: hooks/h.sh (tier 1): NO DENY BACKSTOP'
t_eq "MT-12g the summary counts those warnings, and it is the last line" \
  "mutation-tier: 0 ok, 0 failed, ${n:-x} warnings" "$(tail -1 "$B/rep12.out")"
t_has "MT-12h the table header is still a data line" "$rep12" "$(printf '%-46s %-5s %-7s %-6s %s' PATH TIER GUARD DENY NOTE)"
t_eq "MT-12i the old unshaped lines are gone" 0 "$(grep -c -e '^mutation-tier --report' -e '^fixture: ' -e '^It reports' "$B/rep12.out")"
cls="$(CLAUDE_CONFIG_DIR="$CFG" sh "$TOOL" "$CFG/settings.json" "$CFG/bin/x.sh" 2>&1)"
t_eq "MT-12j the classifier prints data only: one line per path, no summary" \
  "$(printf 'tier 0  settings.json\ntier 1  bin/x.sh')" "$cls"
NOFX="$B/nofix"; mkdir -p "$NOFX/bin"; cp "$TOOL" "$T_ROOT/bin/library-log.sh" "$NOFX/bin/"
nf_rc=0; HARBOR_ROOT="$NOFX" sh "$NOFX/bin/admission-mutation-tier.sh" --report "$CFG" > "$B/nf.out" 2>&1 || nf_rc=$?
t_eq "MT-12k a missing fixture fails the report, exit 1 (a failed run, not a usage error)" 1 "$nf_rc"
t_has "MT-12l ...with a FAIL naming the path" "$(cat "$B/nf.out")" "  FAIL: no fixture at $NOFX/fixtures/mutation-tier/cases.json"
t_has "MT-12m ...its fix line" "$(cat "$B/nf.out")" '  fix: none automatic — see fixtures/mutation-tier/cases.json'
t_eq "MT-12n ...and the summary last" 'mutation-tier: 0 ok, 1 failed, 0 warnings' "$(tail -1 "$B/nf.out")"

t_section "MT-6: case-folding, because APFS is case-insensitive"
t_eq "MT-6a Settings.json is tier 0" 0 "$(tier "$CFG/Settings.json")"
t_eq "MT-6b BIN/guard-bash.sh is tier 1" 1 "$(tier "$CFG/BIN/guard-bash.sh")"

t_section "MT-7: a path that does not exist still has a tier"
t_eq "MT-7a an absent path classifies" 3 "$(tier "$CFG/settings.json.new")"
t_eq "MT-7b an absent path under bin/ is tier 1" 1 "$(tier "$CFG/bin/not-yet-written.sh")"

t_section "MT-8: usage errors, and --json"
t_exit "MT-8a no paths given" 2 sh "$TOOL"
t_exit "MT-8b an unknown option" 2 sh "$TOOL" --nonsuch
t_eq "MT-8c --json emits a parseable tier" true "$(jtrue "$CFG/settings.json" '.[0].tier == 0')"

t_section "MT-9: it writes nothing into the tree it inspects"
before="$(manifest "$CFG")"
sh "$TOOL" --report "$CFG" >/dev/null 2>&1; CLAUDE_CONFIG_DIR="$CFG" sh "$TOOL" "$CFG/settings.json" >/dev/null 2>&1
t_eq "MT-9a the inspected dir is unchanged" "$before" "$(manifest "$CFG")"
t_eq "MT-9b the manifest compared is not empty" yes "$(if [ -n "$before" ]; then echo yes; else echo no; fi)"

t_section "MT-10: a path OUTSIDE the config dir is unjudged, not tier 3"
for out in /etc/passwd "$B/elsewhere/settings.json"; do
  t_eq "MT-10 $out is reported outside" outside "$(scope "$out")"
done
t_eq "MT-10c --json marks an outside path unjudged" true "$(jtrue /etc/passwd '.[0].scope == "outside" and .[0].tier == null')"
t_eq "MT-10d --json still judges an inside path" true "$(jtrue "$CFG/settings.json" '.[0].scope == "inside" and .[0].tier == 0')"

t_section "MT-11: every config-dir spelling a caller can produce (PR #126/#128)"
# #126: a trailing slash made every child `outside`; #128: then `$CFG/x` fell to tier 3. Both
# sides must normalise, so the shell-built and the CLEAN target forms are both asserted.
sp="$B/spell"; mkdir -p "$sp/bin"
for c in "$sp" "$sp/" "$sp///"; do
  t_eq "MT-11 settings.json under '$c'" 0 "$(tier "$c/settings.json" "$c")"
  t_eq "MT-11 bin/guard-bash.sh under '$c'" 1 "$(tier "$c/bin/guard-bash.sh" "$c")"
  t_eq "MT-11 cache/x under '$c' stays tier 3" 3 "$(tier "$c/cache/x" "$c")"
  t_eq "MT-11 /etc/passwd under '$c' stays outside" outside "$(scope /etc/passwd "$c")"
  t_eq "MT-11 a CLEAN settings.json under '$c'" 0 "$(tier "$sp/settings.json" "$c")"
  t_eq "MT-11 a CLEAN bin/guard-bash.sh under '$c'" 1 "$(tier "$sp/bin/guard-bash.sh" "$c")"
done
t_done
