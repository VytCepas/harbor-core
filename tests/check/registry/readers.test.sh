#!/usr/bin/env sh
# What reads the composed check registry (harbor#1149): runtime-install installs ONE bin/CHECKS.md, install-drift holds it to
# the composition at the ref, and drift.launchd-plist finds a private check's plist in the layer's jobs/.
# Layers are throwaway directories; the ids are made up and name no real entity.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset CLAUDECODE HARBOR_DEPLOY
T="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"
REG='| `acme-feed` | the Acme feed | hourly | desktop | the feed stopped |'
PLAT='| acme-feed | macOS only | client watcher | `launchctl bootout a` |'
layer() { # <name> -> a private layer holding one made-up check and its plist
  _d="$T/pv-$1"; mkdir -p "$_d/jobs"
  printf '## Register\n\n%s\n\n## Platforms\n\n%s\n\n## Notes\n\nWhy acme-feed exists.\n' "$REG" "$PLAT" > "$_d/checks.md"
  printf '<plist/>\n' > "$_d/jobs/com.harbor.acme-feed.plist"
  printf '%s' "$_d"
}
ri() { env -u CLAUDE_CONFIG_DIR sh "$T_ROOT/bin/runtime-install.sh" "$@"; }

t_section "runtime-install: the installed registry is core when there is no layer, composed when there is"
D="$T/cfg-none"; mkdir -p "$D"; printf '{}' > "$D/settings.json"
HARBOR_SCOPE_PRIVATE="$T/nowhere" ri --apply --dir "$D" >/dev/null 2>&1
t_exit "no layer: bin/CHECKS.md is CHECKS.md, byte for byte" 0 cmp -s "$T_ROOT/CHECKS.md" "$D/bin/CHECKS.md"
PV="$(layer a)"; D="$T/cfg-a"; mkdir -p "$D"; printf '{}' > "$D/settings.json"
_plan="$(HARBOR_SCOPE_PRIVATE="$PV" ri --dir "$D" 2>&1)"
t_has "the dry run says the register is composed" "$_plan" "bin/CHECKS.md is composed: core plus 1 register row(s) from the private layer"
t_eq "...and wrote nothing" no "$([ -e "$D/bin/CHECKS.md" ] && echo yes || echo no)"
HARBOR_SCOPE_PRIVATE="$PV" ri --apply --dir "$D" >/dev/null 2>&1
t_exit "a layer: the installed register holds the private row" 0 grep -q '^| `acme-feed` |' "$D/bin/CHECKS.md"
t_exit "...its platforms row" 0 grep -q '^| acme-feed |' "$D/bin/CHECKS.md"
t_exit "...and still every core row" 0 sh -c "grep '^| \`[a-z]' '$T_ROOT/CHECKS.md' | sort > '$T/core.rows'; grep '^| \`[a-z]' '$D/bin/CHECKS.md' | sort | comm -23 '$T/core.rows' - | grep -q . && exit 1; exit 0"
t_eq "ONE registry: the register ids in the installed file are unique" "" "$(awk -F'|' '/^## / { p = ($0 ~ /^## Register/) } p && /^\| `/ { print $2 }' "$D/bin/CHECKS.md" | sort | uniq -d)"
t_eq "the installed file is the generator's output" "yes" "$(HARBOR_SCOPE_PRIVATE="$PV" sh "$T_ROOT/bin/check-registry-generate.sh" | cmp -s - "$D/bin/CHECKS.md" && echo yes)"
printf '## Register\n\n| `core-never` | not a row |\n' > "$PV/checks.md"
D="$T/cfg-bad"; mkdir -p "$D"; printf '{}' > "$D/settings.json"
HARBOR_SCOPE_PRIVATE="$PV" ri --apply --dir "$D" > "$T/bad.out" 2>&1; _rc=$?
t_eq "a fragment that does not compose refuses the install" 1 "$_rc"
t_has "...and says so" "$(cat "$T/bad.out")" "does not compose into the register"
t_eq "...writing no registry" no "$([ -e "$D/bin/CHECKS.md" ] && echo yes || echo no)"

t_section "install-drift: the installed register is held to the composition at the ref"
R="$T/repo"; CFG="$T/install"; mkdir -p "$R/bin" "$CFG/bin"
cp "$T_ROOT/bin/install-drift.sh" "$T_ROOT/bin/log-lib.sh" "$T_ROOT/bin/install-lib.sh" "$T_ROOT/bin/check-registry-generate.sh" "$R/bin/"
printf 'DATA="CHECKS.md:bin/CHECKS.md"\n' > "$R/bin/runtime-install.sh"
cat > "$R/CHECKS.md" <<'EOF'
## Register

| id | watches | schedule | notifies | red means |
|---|---|---|---|---|
| `core-one` | a core thing | hourly | desktop | broken |
<!-- private:register -->

## Platforms

| id | platforms | why | disable |
|---|---|---|---|
| core-one | macOS only | w | d |
<!-- private:platforms -->
EOF
git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main
git -C "$R" add -A; git -C "$R" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm v1
drift() { HARBOR_SCOPE_PRIVATE="$1" sh "$R/bin/install-drift.sh" --dir "$CFG" --ref main 2>&1; }
PV="$(layer b)"
sh "$R/bin/check-registry-generate.sh" --core "$R/CHECKS.md" --private "$PV" > "$CFG/bin/CHECKS.md"
t_has "the composed register is current when its layer is there" "$(drift "$PV")" "current=1 stale=0 modified=0 unsourced=0"
t_has "...and reads modified when the layer is gone (it is no longer what would be installed)" "$(drift "$T/nowhere")" "FAIL: modified CHECKS.md ("
cp "$R/CHECKS.md" "$CFG/bin/CHECKS.md"
t_has "the bare core register is current when there is no layer" "$(drift "$T/nowhere")" "current=1 stale=0 modified=0 unsourced=0"
t_has "...and reads modified when a layer would add rows to it" "$(drift "$PV")" "FAIL: modified CHECKS.md ("

t_section "drift.launchd-plist: a private check's plist is found in the layer's jobs/"
X9R="$T/x9"; mkdir -p "$X9R/bin" "$X9R/launchd"
cp "$T_ROOT/bin/lint-conventions.sh" "$T_ROOT/bin/check-registry-generate.sh" "$T_ROOT/bin/log-lib.sh" "$X9R/bin/"
cp "$R/CHECKS.md" "$X9R/CHECKS.md"; : > "$X9R/launchd/com.harbor.core-one.plist"
x9() { HARBOR_SCOPE_PRIVATE="$1" HARBOR_ROOT="$X9R" sh "$X9R/bin/lint-conventions.sh" --only X9 2>&1 | grep -E 'ADVISORY \[drift.launchd-plist\]|registered check\(s\)' || true; }
PV="$(layer c)"
t_has "with the layer, the private row is counted" "$(x9 "$PV")" "2 registered check(s)"
t_eq "...and its plist in jobs/ owes nothing" "0" "$(x9 "$PV" | grep -c 'NO COMMIT')"
rm -f "$PV/jobs/com.harbor.acme-feed.plist"
t_has "...with that plist gone it is registered but in no commit" "$(x9 "$PV")" "registered but in NO COMMIT: com.harbor.acme-feed.plist"
t_has "without the layer the register is core's one row" "$(x9 "$T/nowhere")" "1 registered check(s)"
printf '## Register\n\n| `bad` |\n' > "$PV/checks.md"
t_has "a fragment that does not compose is an advisory, and core alone is read" "$(x9 "$PV")" "does not compose into the register"
t_done
