#!/usr/bin/env sh
# A box across W9 (harbor#967): the collector's and the red-team corpus's env names took their reader's family
# (HARBOR_COLLECTOR_SRC became HARBOR_AUDIT_COLLECTOR_SOURCES, HARBOR_REDTEAM_DIR HARBOR_EVAL_REDTEAM_DIR, ...). The collector's
# jobs are LaunchDaemons that SET two of them, and they run a root-owned copy of the code that no deploy refreshes. So a box
# installed before W9 must keep collecting through the deploy; the box half (standard-rename.sh --wave W9 --dir/--live) must not
# rewrite a job whose code does not read the new name yet, and names the installer's sudo command instead; once the code does,
# the box half leaves every job naming the new names only, still collecting, and a second run changes nothing. The pre-W9 box
# is built from HEAD alone (no history in CI's clone), W9 names spelled back as old. Under --dir the config dir's parent stands
# in for / and HOME: <parent>/Library/LaunchDaemons and <parent>/Library/LaunchAgents are the box's.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/standard-rename.sh"
command -v python3 >/dev/null 2>&1 || { t_section "python3 is absent"; t_exit "the box half is unchecked without python3" 3 sh "$TOOL" --plan --wave W9; t_done; }
unset CLAUDECODE CLAUDE_CONFIG_DIR HARBOR_DEPLOY_ACTIVE HARBOR_DEPLOY
EMPTY='{"permissions":{"allow":[],"deny":[],"disableBypassPermissionsMode":"disable","disableAutoMode":"disable"}}'
JOBS="com.harbor.audit.collector com.harbor.audit.collector-checkpoint com.harbor.audit.otlp-receiver"
CODE="audit-collector.sh library-log.sh library-fs.sh audit-otlp-receiver.py"

# The W9 rows, old TAB new, longest new name first so no name is rewritten inside a longer one.
awk -F'\t' '$5 == "W9" && $2 ~ /^env:/ { print length($3) "\t" substr($2, 5) "\t" substr($3, 5) }' "$T_ROOT/standards/naming/renames.tsv" \
  | sort -rn | cut -f2,3 > "$T_TMP/w9"
t_eq "the W9 env rows are readable (15), or every check below is vacuous" 15 "$(grep -c . "$T_TMP/w9")"
awk -F'\t' '{ printf "s/%s\\([^A-Z0-9_]\\)/%s\\1/g\ns/%s$/%s/\n", $2, $1, $2, $1 }' "$T_TMP/w9" > "$T_TMP/back.sed"
back() { sed -f "$T_TMP/back.sed" "$1"; }   # <file> -> as a pre-W9 install holds it
olds() { cut -f1 "$T_TMP/w9" | while read -r _o; do grep -q "$_o" "$1" && printf '%s ' "$_o"; done; :; }   # <file> -> the old names it carries
news() { cut -f2 "$T_TMP/w9" | while read -r _n; do grep -q "$_n" "$1" && printf '%s ' "$_n"; done; :; }

# The fixture box: a config dir, the system and user launchd dirs, and the collector's root-owned tier, spaces and all.
R="$T_TMP/box"; D="$R/.claude"; LD="$R/Library/LaunchDaemons"; LA="$R/Library/LaunchAgents"
BIN="$R/Library/Application Support/Harbor/collector-bin"; STORE="$R/Library/Application Support/Harbor/collector"
OBS="$D/MEMORY/OBSERVABILITY"; SRC="$OBS"
mkdir -p "$D" "$LD" "$LA" "$BIN" "$STORE" "$OBS/h"; printf '%s\n' "$EMPTY" > "$D/settings.json"
# The installer's own render line (it fills @SOURCES@, @BIN@ and @STORE@ from SRC, BIN and STORE).
eval "$(sed -n '/^render() /p' "$T_ROOT/bin/audit-collector-install.sh")"
t_eq "control: the installer's render line was found" yes "$(command -v render >/dev/null 2>&1 && echo yes || echo no)"
code() { for _f in $CODE; do $1 "$T_ROOT/bin/$_f" > "$BIN/$_f"; done; }               # <back|cat> -> the root-owned copy
jobs() { for _j in $JOBS; do $1 "$T_ROOT/launchd/$_j.plist" > "$T_TMP/$_j.tpl"; render "$T_TMP/$_j.tpl" > "$LD/$_j.plist"; done; }
# Run a job as launchd does: its ProgramArguments under only its EnvironmentVariables and launchd's PATH; prints the exit code.
# The comments go first: launchd reads one holding `--` (the templates' `--uninstall`), which strict XML refuses.
job() { python3 -I -c 'import plistlib, re, subprocess, sys
j = plistlib.loads(re.sub(rb"<!--.*?-->", b"", open(sys.argv[1], "rb").read(), flags=re.S)); e = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin"}; e.update(j.get("EnvironmentVariables") or {})
sys.exit(subprocess.run(j["ProgramArguments"], env=e, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode)' "$LD/$1.plist"; echo $?; }
collects() { # <line> -> yes when an ingest run of the collector job copies a freshly written source line into the store
  printf '%s\n' "$1" >> "$OBS/h/stream.jsonl"; _r="$(job com.harbor.audit.collector)"
  [ "$_r" = 0 ] && cat "$STORE"/data/*.jsonl 2>/dev/null | grep -qx "$1" && echo yes || echo "no (job exit $_r)"; }
envkeys() { python3 -I -c 'import plistlib, re, sys; print(" ".join(sorted((plistlib.loads(re.sub(rb"<!--.*?-->", b"", open(sys.argv[1], "rb").read(), flags=re.S)).get("EnvironmentVariables") or {}).keys())))' "$LD/$1.plist"; }
half() { sh "$TOOL" --apply --wave W9 --dir "$D" --report "$T_TMP/report.tsv" 2>&1; }

t_section "the box before W9: the collector's code and jobs as a pre-W9 install left them"
code back; jobs back
back "$T_ROOT/launchd/com.harbor.eval.redteam-corpus.plist" | sed "s|@HOME@|$R|g" > "$LA/com.harbor.eval.redteam-corpus.plist"
t_has "control: its comment holds a -- that strict XML refuses" "$(sed -n '/<!--/,/-->/p' "$LD/com.harbor.audit.collector.plist")" "--uninstall"
t_eq "control: the ingest job sets only old names" "HARBOR_COLLECTOR_SRC HARBOR_COLLECTOR_STORE" "$(envkeys com.harbor.audit.collector)"
t_eq "control: the root-owned code reads no new name" "" "$(news "$BIN/audit-collector.sh")"
t_eq "control: the red-team agent names the old root" "HARBOR_REDTEAM_DIR " "$(olds "$LA/com.harbor.eval.redteam-corpus.plist")"
t_eq "it collects" yes "$(collects before-w9)"

t_section "W9 deploys: the config dir is refreshed, the root-owned tier is not"
_c0="$(cat "$BIN/audit-collector.sh")"
t_exit "the runtime installs onto the box" 0 sh "$T_ROOT/bin/deploy-runtime-install.sh" --dir "$D" --apply
t_eq "control: the deploy reached the config dir" yes "$([ -f "$D/bin/scope-roots.sh" ] && echo yes || echo no)"
t_eq "the collector's code is untouched by it" "$_c0" "$(cat "$BIN/audit-collector.sh")"
t_eq "the box still collects" yes "$(collects after-deploy)"

t_section "the box half before the collector's code is reinstalled: the daemons are held, the agent is rewritten"
for _j in $JOBS; do cp "$LD/$_j.plist" "$T_TMP/$_j.held"; done
OUT="$(half)"; RC=$?
t_eq "the box half exits 1: a job is held" 1 "$RC"
t_has "...it says why" "$OUT" "sets HARBOR_COLLECTOR_SRC, and the program it runs"
t_has "...and names the sudo step that renders it afresh" "$OUT" "sudo sh $T_ROOT/bin/audit-collector-install.sh"
_same=yes; for _j in $JOBS; do cmp -s "$LD/$_j.plist" "$T_TMP/$_j.held" || _same=no; done
t_eq "no daemon was rewritten" yes "$_same"
t_eq "the box still collects" yes "$(collects held)"
t_eq "the agent, which sets no W9 name, took the new one" "" "$(olds "$LA/com.harbor.eval.redteam-corpus.plist")"
t_has "...in the line that named the old" "$(cat "$LA/com.harbor.eval.redteam-corpus.plist")" "HARBOR_EVAL_REDTEAM_DIR (default vendor-src"
t_eq "no deployed copy reads as older than the rename" "" "$(printf '%s\n' "$OUT" | grep 'older than the rename' || :)"

t_section "the installer's code copy lands, the jobs still name the old names: the window"
code cat
t_eq "control: the root-owned code reads the new names now" "HARBOR_AUDIT_COLLECTOR_SOURCES HARBOR_AUDIT_COLLECTOR_STORE " \
  "$(news "$BIN/audit-collector.sh" | tr ' ' '\n' | grep -E '_(SOURCES|STORE)$' | tr '\n' ' ')"
t_eq "the old-name jobs still collect through its dual read" yes "$(collects window)"

t_section "the box half after it: every job names the new names only, and collects"
OUT="$(half)"; RC=$?
t_eq "the box half exits 0" 0 "$RC"
t_eq "...box residual 0" "residual 0" "$(printf '%s\n' "$OUT" | grep '^residual')"
for _j in $JOBS; do t_eq "$_j names no old name" "" "$(olds "$LD/$_j.plist")"; done
t_eq "the ingest job sets the new names" "HARBOR_AUDIT_COLLECTOR_SOURCES HARBOR_AUDIT_COLLECTOR_STORE" "$(envkeys com.harbor.audit.collector)"
t_eq "...and so does the checkpoint job" "HARBOR_AUDIT_COLLECTOR_SOURCES HARBOR_AUDIT_COLLECTOR_STORE" "$(envkeys com.harbor.audit.collector-checkpoint)"
t_eq "it collects, reading only the new names" yes "$(collects after-w9)"
t_eq "each rewritten job was backed up first" 2 "$(find "$D/backups" -name 'com.harbor.audit.collector*.plist' | wc -l | tr -d ' ')"
_bad=''; for _j in $JOBS; do back "$LD/$_j.plist" | cmp -s - "$T_TMP/$_j.held" || _bad="$_bad $_j"; done
t_eq "nothing but the names moved" "" "$_bad"
S1="$(cat "$LD"/*.plist "$LA"/*.plist)"
t_eq "a second run exits 0" 0 "$(half >/dev/null 2>&1; echo $?)"
t_eq "...and changes nothing" "$S1" "$(cat "$LD"/*.plist "$LA"/*.plist)"

t_section "a daemon only root can write is held, and the installer's own render needs no box half"
jobs back; chmod 0444 "$LD"/*.plist; chmod 0555 "$LD"
OUT="$(half)"; RC=$?
t_eq "a root-owned old-name daemon holds the box half" 1 "$RC"
t_has "...naming the sudo step" "$OUT" "a LaunchDaemon only root can rewrite: sudo sh $T_ROOT/bin/audit-collector-install.sh"
t_eq "...and it is not rewritten" "HARBOR_COLLECTOR_SRC HARBOR_COLLECTOR_STORE" "$(envkeys com.harbor.audit.collector)"
chmod 0755 "$LD"; chmod 0644 "$LD"/*.plist
jobs cat   # what the sudo step writes: HEAD's templates, rendered
for _j in $JOBS; do t_eq "the installer renders $_j with no old name" "" "$(olds "$LD/$_j.plist")"; done
t_eq "...and the box half then finds nothing to do" "residual 0" "$(half | grep '^residual')"
t_eq "it collects" yes "$(collects rendered)"
t_done
