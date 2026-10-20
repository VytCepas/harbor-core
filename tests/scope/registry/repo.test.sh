#!/usr/bin/env sh
# The repo registry and harbor.toml readers in roots.sh, `harbor scope install` (harbor#966, #1149), and
# the notes/ pointer a core skill prints through `roots.sh --private`.
# Every case runs on a throwaway PORT_ROOT; HARBOR_SCOPE_PRIVATE is unset unless a case sets it.
. "$(dirname "$0")/../../lib/core.sh"; t_init
R() { env -u HARBOR_SCOPE_PRIVATE PORT_ROOT="$PW" "$@"; }   # a command with PW as the workspace
roots() { R sh "$T_ROOT/bin/roots.sh" "$@"; }
mkpriv() { PW="$T_TMP/$1"; mkdir -p "$PW/harbor-private"; printf '%s' "$2" > "$PW/harbor-private/repos.tsv"; }
H='id	path	kind	remote
'

t_section "--repo answers from the registry"
mkpriv a "$H"'zorbcorp	zorbcorp	workload	https://example.test/zorbcorp.git
yard	tools/yard	scaffolder	-
'
t_eq "a known id is its resolved checkout" "$PW/zorbcorp" "$(roots --repo zorbcorp)"
t_eq "a nested relative path is kept" "$PW/tools/yard" "$(roots --repo yard)"
t_eq "--repos lists id and checkout from the registry" "zorbcorp	$PW/zorbcorp
yard	$PW/tools/yard" "$(roots --repos)"
t_exit "an unknown id exits 1" 1 roots --repo nope
t_eq "...and prints nothing on stdout" "" "$(roots --repo nope 2>/dev/null)"
t_exit "no id is a usage error" 2 roots --repo

t_section "--remote answers with the registry's remote column (harbor#966)"
mkpriv r "$H"'zorbcorp	zorbcorp	workload	https://example.test/o/zorbcorp.git
yard	tools/yard	scaffolder	-
blank	blank	workload	
'
t_eq "a known id prints its remote, and only the remote" "https://example.test/o/zorbcorp.git" "$(roots --remote zorbcorp)"
t_exit "a row whose remote is - exits 1" 1 roots --remote yard
t_eq "...and prints nothing on stdout" "" "$(roots --remote yard 2>/dev/null)"
t_has "...and says why" "$(roots --remote yard 2>&1)" "has no remote in the registry"
t_exit "a row with an empty remote exits 1" 1 roots --remote blank
t_eq "...and prints nothing on stdout" "" "$(roots --remote blank 2>/dev/null)"
t_exit "an unknown id exits 1" 1 roots --remote nope
t_eq "...and prints nothing on stdout" "" "$(roots --remote nope 2>/dev/null)"
t_has "...and says not registered" "$(roots --remote nope 2>&1)" "no repo 'nope' in the registry"
t_exit "no id is a usage error" 2 roots --remote
t_exit "an id that is not a repo name is a usage error" 2 roots --remote 'a/b'
mkpriv rbad "$H"'evil	../outside	workload	https://example.test/o/evil.git
good	good	workload	https://example.test/o/good.git
'
t_exit "a registry --repo refuses is refused here too" 2 roots --remote good
t_eq "...and no remote reaches stdout" "" "$(roots --remote good 2>/dev/null)"
PW="$T_TMP/rnone"; mkdir -p "$PW"
t_exit "no registry exits 1" 1 roots --remote zorbcorp
t_eq "...and prints nothing on stdout" "" "$(roots --remote zorbcorp 2>/dev/null)"
t_has "...and names the missing registry" "$(roots --remote zorbcorp 2>&1)" "no registry at"
PW="$T_TMP/rcrlf"; mkdir -p "$PW/harbor-private"
printf 'id\tpath\tkind\tremote\r\nok\tok\tworkload\thttps://example.test/o/ok.git\r\n' > "$PW/harbor-private/repos.tsv"
t_eq "CRLF is stripped from the remote" "https://example.test/o/ok.git" "$(roots --remote ok 2>/dev/null)"

t_section "a row that escapes PORT_ROOT is refused"
for bad in '../outside' '/etc' 'a/../../b' '~/x' '$HOME/x' 'a//b' '.' 'a/./b'; do
  mkpriv esc "$H""evil	$bad	workload	-
"
  t_exit "path '$bad' is refused by --repo" 2 roots --repo evil
  t_exit "path '$bad' is refused by --repos" 2 roots --repos
done
mkpriv esc2 "$H"'evil	../outside	workload	-
good	good	workload	-
'
t_eq "a bad row does not leak its path to stdout" "" "$(roots --repo good 2>/dev/null)"
t_has "...and the refusal names the file and line" "$(roots --repo good 2>&1)" "repos.tsv:2"
mkpriv dup "$H"'a	a	workload	-
a	b	workload	-
'
t_exit "a duplicate id is refused" 2 roots --repo a

t_section "no registry: today's behaviour"
PW="$T_TMP/none"; mkdir -p "$PW"
t_has "--repos falls back to the roots table" "$(roots --repos)" "harbor	"
t_eq "--repo harbor falls back to PORT_ROOT/harbor, not the home default (harbor#630)" "$PW/harbor" "$(roots --repo harbor)"
t_eq "...and any id is PORT_ROOT/<id> with no registry, whether or not it exists (the old literal)" "$PW/nope" "$(roots --repo nope)"
t_exit "...but an id that is not a repo name is a usage error" 2 roots --repo 'a/b'
mkdir -p "$T_TMP/emptypriv"
t_eq "an empty private dir is no registry: PORT_ROOT/<id>" "$PW/mailcal" "$(env PORT_ROOT="$PW" HARBOR_SCOPE_PRIVATE="$T_TMP/emptypriv" sh "$T_ROOT/bin/roots.sh" --repo mailcal)"
mkdir -p "$T_TMP/regpriv"; printf 'harbor\tharbor\tcontrol-plane\t-\n' > "$T_TMP/regpriv/repos.tsv"
t_exit "a registry that lacks the row says not registered" 1 env PORT_ROOT="$PW" HARBOR_SCOPE_PRIVATE="$T_TMP/regpriv" sh "$T_ROOT/bin/roots.sh" --repo mailcal

t_section "a PORT_ROOT with a control character is refused"
TABROOT="$T_TMP/ta	b"
t_exit "--repo with a TAB in PORT_ROOT is refused" 2 env PORT_ROOT="$TABROOT" sh "$T_ROOT/bin/roots.sh" --repo zorbcorp
t_exit "--port-root with a TAB in PORT_ROOT is refused" 2 env PORT_ROOT="$TABROOT" sh "$T_ROOT/bin/roots.sh" --port-root

t_section "a bare harbor scope is a usage error that writes nothing"
BP="$T_TMP/bare"
t_exit "no verb exits 2" 2 env PORT_ROOT="$BP" sh "$T_ROOT/bin/harbor" scope
t_eq "and created nothing" no "$([ -e "$BP" ] && echo yes || echo no)"

t_section "HARBOR_SCOPE_PRIVATE moves the private layer"
mkdir -p "$T_TMP/elsewhere"; printf '%s' "${H}z	z	workload	-
" > "$T_TMP/elsewhere/repos.tsv"
t_eq "the registry is read from HARBOR_SCOPE_PRIVATE" "$PW/z" "$(env PORT_ROOT="$PW" HARBOR_SCOPE_PRIVATE="$T_TMP/elsewhere" sh "$T_ROOT/bin/roots.sh" --repo z)"

t_section "--registry-check judges the kind column"
mkpriv k "$H"'harbor	harbor	control-plane	-
'
t_exit "a known kind is green" 0 roots --registry-check
mkpriv k2 "$H"'harbor	harbor	nonsense	-
'
t_exit "an unknown kind is refused" 2 roots --registry-check
t_exit "...though the lookup still answers" 0 roots --repo harbor

t_section "--conf reads harbor.toml"
mkpriv c "$H"
cf() { printf '%s\n' "$1" > "$PW/harbor-private/harbor.toml"; }
cf '# comment
packs = ["zorbcorp", "plumb"]   # trailing
channel = "stable"
deliverables_dir = "~/Deliverables"'
t_eq "an array prints one element per line" "zorbcorp
plumb" "$(roots --conf packs)"
t_eq "a string prints raw" "stable" "$(roots --conf channel)"
t_eq "a value with a slash and tilde survives" "~/Deliverables" "$(roots --conf deliverables_dir)"
t_exit "an unset key without a default exits 1" 1 roots --conf worklog_repo
t_eq "components prints one element per line" "core
yard" "$(cf 'components = ["core", "yard"]'; roots --conf components)"
cf 'components = []'
t_exit "an empty array is unset: exits 1 like packs" 1 roots --conf components
t_eq "...and prints nothing on stdout" "" "$(roots --conf components 2>/dev/null)"
PW="$T_TMP/noconf"; mkdir -p "$PW"
t_exit "no file: components is unset, exits 1" 1 roots --conf components
t_eq "...and prints nothing on stdout" "" "$(roots --conf components 2>/dev/null)"
t_eq "no file: channel is main" "main" "$(roots --conf channel)"
mkpriv c2 "$H"
for body in '[tool]' 'packs = zorbcorp' 'packs = ["a"' 'typo_key = "x"' 'channel = "nightly"' 'channel = "main" junk' 'packs = ["a"]
packs = ["b"]'; do
  cf "$body"
  t_exit "bad config '$(printf '%s' "$body" | tr '\n' ' ')' is refused" 2 roots --conf packs
done
t_exit "an unknown key name is a usage error" 2 roots --conf nope

t_section "harbor scope install"
PW="$T_TMP/init"
t_exit "--dry-run succeeds" 0 env PORT_ROOT="$PW" sh "$T_ROOT/bin/scope.sh" install --dry-run
t_exit "...and writes nothing" 1 test -e "$PW"
env PORT_ROOT="$PW" sh "$T_ROOT/bin/scope.sh" install >"$T_TMP/init1" 2>&1
for p in .worktrees .scratch history harbor-private/access harbor-private/jobs; do
  t_exit "creates $p/" 0 test -d "$PW/$p"
done
for p in harbor.toml repos.tsv checks.md CLAUDE.personal.md; do
  t_exit "creates harbor-private/$p" 0 test -f "$PW/harbor-private/$p"
done
t_has "reports what it created" "$(cat "$T_TMP/init1")" "created"
t_eq "repos.tsv is the header alone" "id	path	kind	remote" "$(cat "$PW/harbor-private/repos.tsv")"
t_exit "the new registry is valid" 0 roots --registry-check
t_has "the template seeds a live components = [core] line" "$(grep -E '^components = ' "$PW/harbor-private/harbor.toml")" 'components = ["core"]'
t_has "...and its comment names every optional component" "$(cat "$PW/harbor-private/harbor.toml")" "yard, fleet, prod-guard, collector"
t_eq "the seeded harbor.toml reads components as core" "core" "$(roots --conf components)"
printf 'mine\n' > "$PW/harbor-private/CLAUDE.personal.md"
env PORT_ROOT="$PW" sh "$T_ROOT/bin/scope.sh" install >"$T_TMP/init2" 2>&1
t_eq "a second run keeps an edited file" "mine" "$(cat "$PW/harbor-private/CLAUDE.personal.md")"
t_has "...and says kept" "$(cat "$T_TMP/init2")" "kept"
t_hasnt "...and creates nothing" "$(cat "$T_TMP/init2")" "created"
t_exit "an unknown flag is a usage error" 2 env PORT_ROOT="$PW" sh "$T_ROOT/bin/scope.sh" install --bogus
t_exit "harbor scope install is a dispatcher verb" 0 env PORT_ROOT="$PW" sh "$T_ROOT/bin/harbor" scope install --dry-run

t_section "registry rows: shape, aliases, symlinks, text encodings"
mkpriv sl "$H"'real	real/	workload	-
'
mkdir -p "$PW/real"
t_eq "one trailing slash is normalised, not fatal" "$PW/real" "$(roots --repo real)"
mkpriv five "$H"'a	a	workload	-	extra
'
t_exit "a row with five fields is refused" 2 roots --repo a
mkpriv alias "$H"'REAL	REAL	workload	-
real	real	workload	-
'
t_exit "a case alias of another row's path is refused" 2 roots --repo real
t_has "...saying duplicate path" "$(roots --repo real 2>&1)" "duplicate path"
mkpriv samep "$H"'a	same	workload	-
b	same	workload	-
'
t_exit "two ids on one path are refused" 2 roots --repo a
mkpriv lnk "$H"'link	link	workload	-
'
mkdir -p "$T_TMP/outside"; ln -s "$T_TMP/outside" "$PW/link"
t_exit "a symlink resolving outside PORT_ROOT is refused by --repo" 2 roots --repo link
t_exit "...and by --registry-check" 2 roots --registry-check
t_eq "...with nothing on stdout" "" "$(roots --repo link 2>/dev/null)"
mkpriv lnk2 "$H"'in	in	workload	-
twin	twin	workload	-
'
mkdir -p "$PW/target"; ln -s "$PW/target" "$PW/in"; ln -s "$PW/target" "$PW/twin"
t_exit "two rows resolving to one checkout are refused" 2 roots --repo in
mkpriv crlf "$H"'ok	ok	workload	-
'
printf 'id\tpath\tkind\tremote\r\nok\tok\tworkload\t-\r\n\r\n' > "$PW/harbor-private/repos.tsv"
t_eq "CRLF in repos.tsv is read" "$PW/ok" "$(roots --repo ok 2>/dev/null)"
t_has "...with a note" "$(roots --repo ok 2>&1)" "CRLF"
printf '\357\273\277id\tpath\tkind\tremote\nok\tok\tworkload\t-\n' > "$PW/harbor-private/repos.tsv"
t_eq "a BOM in repos.tsv is read" "$PW/ok" "$(roots --repo ok 2>/dev/null)"
PW="$T_TMP/esc\\tb"; mkdir -p "$PW/harbor-private"; printf '%s' "$H"'real	real	workload	-
' > "$PW/harbor-private/repos.tsv"
t_eq "a backslash in PORT_ROOT is not expanded as an escape" "$PW/real" "$(roots --repo real)"

t_section "harbor.toml: escapes, empties, encodings"
mkpriv t "$H"
cf() { printf '%s\n' "$1" > "$PW/harbor-private/harbor.toml"; }
cf 'worklog_repo = "a\" # x"'
t_exit "an escaped quote is refused, not misread" 2 roots --conf worklog_repo
cf 'packs = ["", "b"]'
t_exit "an empty array element is refused" 2 roots --conf packs
cf 'packs = ["a"]'
printf 'packs = ["a"]\r\nchannel = "stable"\r\n' > "$PW/harbor-private/harbor.toml"
t_eq "CRLF in harbor.toml is read" "stable" "$(roots --conf channel 2>/dev/null)"
t_has "...with a note" "$(roots --conf channel 2>&1)" "CRLF"
printf '\357\273\277channel = "stable"\n' > "$PW/harbor-private/harbor.toml"
t_eq "a BOM in harbor.toml is read" "stable" "$(roots --conf channel 2>/dev/null)"

t_section "harbor scope install: symlinks and the temp dir"
PW="$T_TMP/ln"; mkdir -p "$PW/harbor-private" "$T_TMP/elsewhere2"
ln -s "$T_TMP/elsewhere2/planted.toml" "$PW/harbor-private/harbor.toml"
env PORT_ROOT="$PW" sh "$T_ROOT/bin/scope.sh" install >/dev/null 2>&1
t_exit "init does not write through a dangling symlink" 1 test -e "$T_TMP/elsewhere2/planted.toml"
mkdir -p "$T_TMP/emptytmp"; PW="$T_TMP/dryt"
env PORT_ROOT="$PW" TMPDIR="$T_TMP/emptytmp" HARBOR_SCOPE_PROJECTS_TSV="$T_TMP/projects.tsv" sh "$T_ROOT/bin/scope.sh" install --dry-run --seed-from-projects >/dev/null 2>&1
t_eq "--dry-run --seed writes nothing, TMPDIR included" "" "$(ls -A "$T_TMP/emptytmp")"

t_section "harbor scope install --private-only"
PW="$T_TMP/ponly"; mkdir -p "$PW"
env PORT_ROOT="$PW" sh "$T_ROOT/bin/scope.sh" install --private-only >/dev/null 2>&1
t_exit "creates the private layer" 0 test -f "$PW/harbor-private/repos.tsv"
t_exit "...and not the workspace skeleton" 1 test -e "$PW/.worktrees"

t_section "harbor scope install: the config dir's settings.json (harbor#457)"
# Each case is its own HOME with no CLAUDE_CONFIG_DIR: the stranger's box. deploy installs into HOME/.claude only.
SH_="$T_TMP/sh0"; mkdir -p "$SH_"
scope() { # <home> [args…] → output in $T_TMP/sout, exit in $SRC_RC
  _sh="$1"; shift
  env -u CLAUDE_CONFIG_DIR HOME="$_sh" PORT_ROOT="$_sh/port" sh "$T_ROOT/bin/scope.sh" install "$@" >"$T_TMP/sout" 2>&1; SRC_RC=$?
}
sout() { cat "$T_TMP/sout"; }
mkdir -p "$SH_/a"; scope "$SH_/a" --dry-run
t_has "--dry-run says it would create it" "$(sout)" "would create $SH_/a/.claude/settings.json"
t_exit "...and writes nothing" 1 test -e "$SH_/a/.claude"
scope "$SH_/a"
t_eq "a box with no config dir: exit 0" 0 "$SRC_RC"
t_has "it creates settings.json and says so" "$(sout)" "created  $SH_/a/.claude/settings.json"
t_eq "...as an empty object" "{}" "$(cat "$SH_/a/.claude/settings.json")"
t_exit "...that is valid JSON" 0 jq -e 'type == "object"' "$SH_/a/.claude/settings.json"
printf '{"model":"mine"}\n' > "$SH_/a/.claude/settings.json"
scope "$SH_/a"
t_has "a second run says kept" "$(sout)" "kept     $SH_/a/.claude/settings.json"
t_eq "...and the operator's file is byte for byte what it was" '{"model":"mine"}' "$(cat "$SH_/a/.claude/settings.json")"
mkdir -p "$SH_/b/.claude"; scope "$SH_/b"
t_eq "a config dir with no settings.json gets one, nothing else in it touched" "{}" "$(cat "$SH_/b/.claude/settings.json")"
mkdir -p "$SH_/c/.claude" "$SH_/c/dots"; printf '{"x":1}\n' > "$SH_/c/dots/settings.json"; ln -s "$SH_/c/dots/settings.json" "$SH_/c/.claude/settings.json"
scope "$SH_/c"
t_has "a symlink to a real file is kept, not refused" "$(sout)" "kept     $SH_/c/.claude/settings.json"
t_eq "...and its target is untouched" '{"x":1}' "$(cat "$SH_/c/dots/settings.json")"
mkdir -p "$SH_/d/.claude"; ln -s "$SH_/d/nowhere.json" "$SH_/d/.claude/settings.json"
scope "$SH_/d"
t_has "a dangling symlink is not written through" "$(sout)" "refusing to write through the dangling symlink"
t_exit "...so its target is not created" 1 test -e "$SH_/d/nowhere.json"
mkdir -p "$SH_/e"; scope "$SH_/e" --private-only
t_exit "--private-only leaves the config dir alone" 1 test -e "$SH_/e/.claude"
mkdir -p "$SH_/f"; env HOME="$SH_/f" PORT_ROOT="$SH_/f/port" CLAUDE_CONFIG_DIR="$SH_/elsewhere" sh "$T_ROOT/bin/scope.sh" install >"$T_TMP/sout" 2>&1
t_has "a CLAUDE_CONFIG_DIR naming another dir is named, not seeded" "$(sout)" "WARN: CLAUDE_CONFIG_DIR is $SH_/elsewhere, and deploy installs into $SH_/f/.claude only"
t_exit "...so neither dir is created" 1 test -e "$SH_/f/.claude"
mkdir -p "$SH_/g/.claude"; env HOME="$SH_/g" PORT_ROOT="$SH_/g/port" CLAUDE_CONFIG_DIR="$SH_/g/.claude/" sh "$T_ROOT/bin/scope.sh" install >"$T_TMP/sout" 2>&1
t_eq "a CLAUDE_CONFIG_DIR naming the same dir (trailing slash) is seeded" "{}" "$(cat "$SH_/g/.claude/settings.json")"
mkdir -p "$SH_/h"; : > "$SH_/h/.claude"
scope "$SH_/h"
t_eq "a config dir that cannot be made is a FAIL, exit 1" 1 "$SRC_RC"
t_has "...naming the file" "$(sout)" "FAIL: could not create $SH_/h/.claude/settings.json"
t_has "...with a fix line under it" "$(grep -A1 'could not create' "$T_TMP/sout")" "  fix: "

t_section "harbor scope install --seed-from-projects"
PW="$T_TMP/seed"; mkdir -p "$PW/zorbcorp" "$PW/tool" "$PW/loose"
git -C "$PW/zorbcorp" init -q; git -C "$PW/zorbcorp" remote add origin https://user:secret@example.test/o/zorbcorp.git
git -C "$PW/tool" init -q; git -C "$PW/tool" remote add origin https://example.test/o/tool.git
git -C "$PW/loose" init -q
printf '# c\nzorbcorp\t~/port/zorbcorp\tx\nplumb\t~/port/plumb\ty\nodd\t/srv/odd\tz\n' > "$T_TMP/projects.tsv"
env PORT_ROOT="$PW" HARBOR_SCOPE_PROJECTS_TSV="$T_TMP/projects.tsv" sh "$T_ROOT/bin/scope.sh" install --seed-from-projects >/dev/null 2>&1
DRYOUT="$(env PORT_ROOT="$T_TMP/seed" HARBOR_SCOPE_PRIVATE="$T_TMP/seed-dry" HARBOR_SCOPE_PROJECTS_TSV="$T_TMP/projects.tsv" sh "$T_ROOT/bin/scope.sh" install --private-only --seed-from-projects --dry-run 2>&1)"
t_eq "--dry-run names a row seeded from both sources once" "1" "$(printf '%s\n' "$DRYOUT" | grep -c 'would add row: zorbcorp')"
REG="$PW/harbor-private/repos.tsv"
t_eq "a projects.tsv row becomes a row, token stripped from its remote" "zorbcorp	zorbcorp	workload	https://example.test/o/zorbcorp.git" "$(grep '^zorbcorp	' "$REG")"
t_eq "a row with no checkout gets remote -" "plumb	plumb	workload	-" "$(grep '^plumb	' "$REG")"
t_eq "a checkout with a remote that projects.tsv lacks is added" "tool	tool	workload	https://example.test/o/tool.git" "$(grep '^tool	' "$REG")"
t_hasnt "a checkout with no remote is left out" "$(cat "$REG")" "loose"
t_hasnt "a path outside ~/port is skipped" "$(cat "$REG")" "odd"
t_exit "the seeded registry is valid" 0 roots --registry-check
env PORT_ROOT="$PW" HARBOR_SCOPE_PROJECTS_TSV="$T_TMP/projects.tsv" sh "$T_ROOT/bin/scope.sh" install --seed-from-projects >/dev/null 2>&1
t_eq "seeding twice adds no row" "4" "$(wc -l < "$REG" | tr -d ' ')"

t_section "a seeded kind is the checkout's own repo-kind line, never a name core lists (harbor#1273)"
PW="$T_TMP/seedk"; mkdir -p "$PW/models/.agents" "$PW/oddkind/.agents"
for _r in models oddkind; do git -C "$PW/$_r" init -q; git -C "$PW/$_r" remote add origin "https://example.test/o/$_r.git"; done
printf 'scope: project\nrepo-kind: data  # standards/naming/repo-kinds.tsv\n' > "$PW/models/.agents/config.yaml"
printf 'repo-kind: nonsense\n' > "$PW/oddkind/.agents/config.yaml"
: > "$T_TMP/pk.tsv"
env PORT_ROOT="$PW" HARBOR_SCOPE_PROJECTS_TSV="$T_TMP/pk.tsv" sh "$T_ROOT/bin/scope.sh" install --seed-from-projects >/dev/null 2>&1
t_eq "a declared kind is seeded" "data" "$(awk -F'\t' '$1 == "models" { print $3 }' "$PW/harbor-private/repos.tsv")"
t_eq "a kind the vocabulary lacks falls back to workload" "workload" "$(awk -F'\t' '$1 == "oddkind" { print $3 }' "$PW/harbor-private/repos.tsv")"

t_section "seeding refuses rows the reader would refuse (M1) and fixes a missing newline (M2)"
PW="$T_TMP/seed2"; mkdir -p "$PW/slashy" "$PW/my repo" "$PW/zorbcorp"
git -C "$PW/my repo" init -q; git -C "$PW/my repo" remote add origin https://example.test/o/m.git
git -C "$PW/zorbcorp" init -q; git -C "$PW/zorbcorp" remote add origin https://example.test/o/zorbcorp.git
printf 'slash\t~/port/slashy/\naz\t~/port/zorbcorp\n' > "$T_TMP/p2.tsv"
env PORT_ROOT="$PW" HARBOR_SCOPE_PROJECTS_TSV="$T_TMP/p2.tsv" sh "$T_ROOT/bin/scope.sh" install --seed-from-projects >"$T_TMP/s2.out" 2>&1; RC=$?
REG="$PW/harbor-private/repos.tsv"
t_eq "an unnameable checkout makes the seed exit 1" "1" "$RC"
t_has "...loudly" "$(cat "$T_TMP/s2.out")" "my repo"
t_exit "...yet the registry it leaves is valid" 0 roots --registry-check
t_eq "a trailing slash is normalised into the row" "slashy" "$(awk -F'\t' '$1 == "slash" { print $2 }' "$REG")"
t_eq "an id on an already-registered path is not added" "0" "$(grep -c '^zorbcorp	' "$REG")"
PW="$T_TMP/seed3"; mkdir -p "$PW/flowy" "$PW/harbor-private"
printf 'id\tpath\tkind\tremote\nmine\tmine\tworkload\t-' > "$PW/harbor-private/repos.tsv"
printf 'plumb\t~/port/flowy\n' > "$T_TMP/p3.tsv"
env PORT_ROOT="$PW" HARBOR_SCOPE_PROJECTS_TSV="$T_TMP/p3.tsv" sh "$T_ROOT/bin/scope.sh" install --seed-from-projects >/dev/null 2>&1
t_eq "a registry with no final newline keeps both rows" "2" "$(grep -c '	workload	' "$PW/harbor-private/repos.tsv")"
t_eq "...and the new row is whole" "plumb	flowy	workload	-" "$(grep '^plumb	' "$PW/harbor-private/repos.tsv")"
printf 'id\tpath\tkind\tremote\nbad\t../x\tworkload\t-\n' > "$PW/harbor-private/repos.tsv"
t_exit "a registry already invalid is not appended to" 1 env PORT_ROOT="$PW" HARBOR_SCOPE_PROJECTS_TSV="$T_TMP/p3.tsv" sh "$T_ROOT/bin/scope.sh" install --seed-from-projects

t_section "a skill's notes/ pointer finds its file through roots.sh --private (harbor#1149)"
# dev-tracking, the skill that carried one, left core for the private layer's pack (harbor#1273), whose suite checks it;
# a fixture skill keeps the shape and the resolver tested here, beside any core skill that still prints one.
NP="$T_TMP/notes-priv"; mkdir -p "$NP/notes" "$T_TMP/fx-skills/fx"
NOTE_ROW="$(grep '^| `notes/`' "$T_ROOT/CONTRACTS/private-layer.md")"
printf -- '---\nname: fx\n---\ncat "$(sh ~/port/harbor/bin/roots.sh --private)/notes/fixture-note.md"\n' > "$T_TMP/fx-skills/fx/SKILL.md"
find "$T_ROOT/skills" "$T_TMP/fx-skills" -name SKILL.md -exec sed -n '/^cat "\$(sh ~\/port\/harbor\/bin\/roots\.sh --private)\/notes\/[a-z0-9-]*\.md"$/p' {} + > "$T_TMP/pointers"
t_has "a pointer of the exact shape is found" "$(cat "$T_TMP/pointers")" "notes/fixture-note.md"
t_has "private-layer.md documents notes/" "$NOTE_ROW" "notes/"
while IFS= read -r ptr; do
  n="${ptr##*/}"; n="${n%\"}"
  printf 'marker-%s\n' "$n" > "$NP/notes/$n"
  t_eq "the pointer for $n prints the file in the private layer" "marker-$n" "$(env HARBOR_SCOPE_PRIVATE="$NP" sh -c "$(printf '%s' "$ptr" | sed "s|~/port/harbor/bin/roots.sh|$T_ROOT/bin/roots.sh|")")"
done < "$T_TMP/pointers"
t_done
