#!/usr/bin/env sh
# bin/library-fs.sh (harbor#618): a file's mtime, size, mode and owner read the same on BSD and GNU stat.
# GNU is simulated on a Mac by tests/lib/linux-sim.sh (its `stat -f` prints filesystem text and fails);
# a Linux runner exercises its own stat directly. Every bare `stat -f` left in bin/ is named here.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/lib/linux-sim.sh"
. "$T_ROOT/bin/library-fs.sh"
W="$T_TMP/w"; mkdir -p "$W"
F="$W/f"; printf 'hello' > "$F"; chmod 640 "$F"; TZ=UTC touch -t 200001020304.05 "$F"
GN="$T_TMP/gnu"; gnu_stat_stub "$GN"
all() { printf '%s|%s|%s|%s' "$(fs_mtime "$1")" "$(fs_size "$1")" "$(fs_mode "$1")" "$(fs_uid "$1")"; }
want="946782245|5|640|$(id -u)"   # 2000-01-02 03:04:05 UTC

t_section "the helper reads the values the file was given"
t_eq "mtime|size|mode|uid on this userland" "$want" "$(all "$F")"
chmod 600 "$F"; t_eq "mode follows chmod 600" 600 "$(fs_mode "$F")"
chmod 755 "$F"; t_eq "mode follows chmod 755" 755 "$(fs_mode "$F")"
chmod 4755 "$F" 2>/dev/null; t_eq "a setuid file reads its permission bits, as BSD does" 755 "$(fs_mode "$F")"
chmod 640 "$F"

t_section "the same values on a GNU userland"
PATH="$GN:$PATH"
t_eq "stat resolves to the GNU stub" "$GN/stat" "$(command -v stat)"
t_has "control: the stub's stat -f prints filesystem text, as GNU does" "$(stat -f %m "$F" 2>/dev/null || true)" "Type: ext2"
t_eq "mtime|size|mode|uid under GNU stat" "$want" "$(all "$F")"
t_eq "an unreadable file is empty under GNU stat" "" "$(fs_mtime "$W/nope")"
chmod 755 "$F"; t_eq "mode 755 under GNU stat" 755 "$(fs_mode "$F")"
chmod 4755 "$F"
t_eq "control: the GNU stub prints 4755 for a setuid file, as GNU %a does" 4755 "$(stat -c %a "$F")"
t_eq "a setuid file reads its permission bits under GNU stat" 755 "$(fs_mode "$F")"
# red-proof: the same helper without its trim line returns 4755 here, so the case above can fail.
grep -v '7:????\*' "$T_ROOT/bin/library-fs.sh" > "$T_TMP/fs-lib-notrim.sh"
t_eq "red-proof: without the trim, fs_mode returns the setuid digit" 4755 "$(. "$T_TMP/fs-lib-notrim.sh"; fs_mode "$F")"
chmod 640 "$F"

t_section "red-proof: the BSD-first chain this replaces is garbage on that userland"
# Spelled in two strings: lint posix.stat-fallback refuses the one-expression chain, as it should.
nv1='stat -f %m "$F" 2>/dev/null'
nv2='stat -c %Y "$F"'
naive="$(eval "$nv1 || $nv2")"
case "$naive" in *[!0-9]*) t_pass ;; *) t_fail "the naive chain returned digits ($naive): the stub no longer reproduces the GNU trap" ;; esac
t_hasnt "while the helper's answer carries no filesystem text" "$(all "$F")" "Type:"

t_section "unknown means empty and exit 0, so a set -e caller survives"
t_eq "missing file: empty" "" "$(fs_size "$W/nope")"
t_eq "set -eu caller gets empty and carries on" "ok:" "$(sh -c 'set -eu; . "$1"; x="$(fs_mtime "$2")"; echo "ok:$x"' _ "$T_ROOT/bin/library-fs.sh" "$W/nope")"
t_exit "exit code on a missing file" 0 sh -c '. "$1"; fs_mtime "$2"' _ "$T_ROOT/bin/library-fs.sh" "$W/nope"

t_section "no bare stat -f in bin/ outside the helper and the named files"
# Comment lines stripped first, as harbor#618's own derivation does, so prose cannot count.
bare() { # <dir> -> the *.sh files whose code holds `stat -f`
  for _f in "$1"/*.sh; do
    [ -f "$_f" ] && [ ! -L "$_f" ] || continue   # a rename shim (symlink) is its target, counted once
    sed -e 's/^[[:space:]]*#.*//' "$_f" | grep -qE 'stat[[:space:]]+-f' && printf '%s\n' "${_f##*/}"
  done
}
# status-fleet-glyph.sh stays self-contained (the statusline sources nothing) and is
# proved below. freshness, skill-usage and wf-progress keep a correct local copy: touching them trips lint LOG1's
# ratchet until they move onto log-lib. lint-conventions.sh is copied alone into the lint suites' fixtures, so it cannot source a sibling. A new name here is a decision.
t_eq "the bare stat -f files are exactly the named ones" "doc-freshness.sh library-fs.sh lint-conventions.sh session-workflow-progress.sh skill-usage.sh status-fleet-glyph.sh" "$(bare "$T_ROOT/bin" | tr '\n' ' ' | sed 's/ $//')"
mkdir -p "$T_TMP/plant"
printf '#!/usr/bin/env sh\nm="$(stat -f %%m "$1")"\n' > "$T_TMP/plant/new-tool.sh"
printf '#!/usr/bin/env sh\n# stat -f in a comment is not a call\n' > "$T_TMP/plant/prose.sh"
t_eq "red-proof: a planted bare call is found, a comment is not" "new-tool.sh" "$(bare "$T_TMP/plant")"

t_section "the five scripts that keep their own stat answer correctly on both userlands"
# Their own code, lifted from the source: a rewrite that no longer matches fails here, loudly.
lift() { awk -v n="$2" '$0 ~ "^" n "\\(\\) \\{" {p=1} p{print} p&&/^\}/{exit}' "$T_ROOT/bin/$1"; }  # <script> <function>
fr_fn="$(lift doc-freshness.sh mtime_days)"; su_fn="$(lift skill-usage.sh _su_mtime)"; wf_fn="$(lift session-workflow-progress.sh mtime)"; lc_fn="$(lift lint-conventions.sh _x8_mtime)"
fg_ex="$(grep -m1 'if mt="$(stat -f %m "$CACHE"' "$T_ROOT/bin/status-fleet-glyph.sh" | sed -e 's/^[[:space:]]*if //' -e 's/; then$//')"
t_has "found status-fleet-glyph.sh's cache-age expression" "$fg_ex" 'stat -c %Y'
t_has "found doc-freshness.sh's mtime_days" "$fr_fn" 'mtime_days()'
t_has "found skill-usage.sh's _su_mtime" "$su_fn" '_su_mtime()'
t_has "found session-workflow-progress.sh's mtime" "$wf_fn" 'mtime()'
t_has "found lint-conventions.sh's _x8_mtime" "$lc_fn" '_x8_mtime()'
both() { # <label> — run the lifted code under this PATH
  CFG="$F"; CACHE="$F"; mt=""
  NOW=$((946782245 + 3 * 86400)); eval "$fr_fn"; eval "$su_fn"; eval "$wf_fn"; eval "$lc_fn"; eval "$fg_ex" || mt="none"
  t_eq "$1: fleet-glyph cache mtime" 946782245 "$mt"
  t_eq "$1: freshness mtime_days" 3 "$(mtime_days "$F")"
  t_eq "$1: skill-usage _su_mtime" 946782245 "$(_su_mtime "$F")"
  t_eq "$1: wf-progress mtime" 946782245 "$(mtime "$F")"
  t_eq "$1: lint-conventions _x8_mtime" 946782245 "$(_x8_mtime "$F")"
}
both "GNU stub"
PATH="${PATH#"$GN":}"
both "native"

t_done
