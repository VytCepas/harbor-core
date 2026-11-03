#!/usr/bin/env sh
# drift.launchd-wall (harbor#1442): drift-launchd-wall.sh fails on a com.harbor.* job whose executable or script sits inside the
# confinement's write list, unless an exemption row with a reason covers it. Fixture plists in HARBOR_DRIFT_LAUNCHD_DIR;
# the write list is the real compose over a fixture PORT_ROOT, so the check is proven against the writer's own output.
. "$(dirname "$0")/../../lib/core.sh"; t_init
DL="$T_ROOT/bin/drift-launchd-wall.sh"
PORT_ROOT="$T_TMP/port"; PRIV="$PORT_ROOT/harbor-private"; mkdir -p "$PRIV" "$PORT_ROOT/work" "$T_TMP/installed/bin"
PORT_ROOT="$(cd -P "$PORT_ROOT" && pwd)"; PRIV="$PORT_ROOT/harbor-private"
export PORT_ROOT HARBOR_CONFINEMENT_PRIVATE="$PRIV" HARBOR_CONFINEMENT_OS=Darwin HARBOR_CHECK_RECEIPTS="$T_TMP/receipts"
LA="$T_TMP/LaunchAgents"; mkdir -p "$LA"; export HARBOR_DRIFT_LAUNCHD_DIR="$LA"
dl() { sh "$DL" "$@" 2>&1; }
rc() { sh "$DL" >/dev/null 2>&1; echo $?; }
state() { sh "$DL" --state 2>/dev/null; }
receipt() { jq -r .status "$HARBOR_CHECK_RECEIPTS/drift.launchd-wall.json" 2>/dev/null; }

command -v plutil >/dev/null 2>&1 || {
  t_section "no plutil: a host without launchd stands down"
  t_eq "not-applicable, never a green" not-applicable "$(state)"
  t_done
}

# job <label> [<wd>] <arg>... writes LA/<label>.plist
job() {
  _l="$1"; _w="$2"; shift 2
  { printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>Label</key><string>%s</string>\n<key>ProgramArguments</key><array>\n' "$_l"
    for _a in "$@"; do printf '<string>%s</string>\n' "$_a"; done
    printf '</array>\n'
    [ -z "$_w" ] || printf '<key>WorkingDirectory</key><string>%s</string>\n' "$_w"
    printf '</dict></plist>\n'; } > "$LA/$_l.plist"
}

t_section "no job, no verdict"
t_eq "an empty folder stands down" not-applicable "$(state)"
t_eq "...with exit 0" 0 "$(rc)"

t_section "a job running an installed copy is clear"
job com.harbor.alpha "" /bin/sh "$T_TMP/installed/bin/alpha.sh"
OUT="$(dl)"
t_eq "outside the write list: exit 0" 0 "$(rc)"
t_has "...an ok line stamped with the check id" "$OUT" "ok: [check:drift.launchd-wall] 1 com.harbor.* job(s): none runs code from the write list"
t_eq "...state match" match "$(state)"
t_eq "...the receipt is green" green "$(receipt)"

t_section "a job running code from the write list is red, and restoring it is green"
job com.harbor.beta "$PORT_ROOT/work" /opt/homebrew/bin/python3 "$PORT_ROOT/work/job.py"
OUT="$(dl)"
t_eq "script inside the write list: exit 1" 1 "$(rc)"
t_eq "...state drift" drift "$(state)"
t_has "...naming the job and the path" "$OUT" "com.harbor.beta runs $PORT_ROOT/work/job.py, inside the write list ($PORT_ROOT)"
t_hasnt "...and not the clear job" "$OUT" "com.harbor.alpha runs"
t_has "...with the fix: an installed copy" "$OUT" "install a copy of each script outside the write list"
t_has "...the receipt names the subject" "$(jq -r '.subjects[]' "$HARBOR_CHECK_RECEIPTS/drift.launchd-wall.json")" "com.harbor.beta:$PORT_ROOT/work/job.py"
t_has "a working directory in the write list is a note, not a finding" "$OUT" "working directory $PORT_ROOT/work is inside the write list"
job com.harbor.beta "$PORT_ROOT/work" /opt/homebrew/bin/python3 "$T_TMP/installed/bin/job.py"
t_eq "CONTROL: pointed at the installed copy, green again" "0 match" "$(rc) $(state)"
t_eq "...a working directory in the zone alone is not red" 0 "$(rc)"

t_section "each way to reach the zone"
rm -f "$LA/com.harbor.beta.plist"
job com.harbor.rel "$PORT_ROOT/work" /bin/sh run.sh
t_eq "a relative script resolved against the working directory" drift "$(state)"
t_has "...names the resolved path" "$(dl)" "com.harbor.rel runs $PORT_ROOT/work/run.sh"
rm -f "$LA/com.harbor.rel.plist"
ln -s "$PORT_ROOT/work/real.sh" "$T_TMP/installed/bin/link.sh"; : > "$PORT_ROOT/work/real.sh"
job com.harbor.link "" /bin/sh "$T_TMP/installed/bin/link.sh"
t_eq "an installed path that is a symlink into the zone" drift "$(state)"
rm -f "$LA/com.harbor.link.plist"
job com.harbor.tilde "" /bin/sh "~/.cache/uv/x.sh"
t_eq "a ~ path into another write-list row (~/.cache/uv)" drift "$(state)"
rm -f "$LA/com.harbor.tilde.plist"
job com.harbor.flag "" /bin/sh "$T_TMP/installed/bin/alpha.sh" --out="$PORT_ROOT/work/x"
t_eq "an argument that merely contains a path is not an executable" match "$(state)"
rm -f "$LA/com.harbor.flag.plist"
cat > "$LA/other.plist" <<'PLISTEND'
<plist version="1.0"><dict><key>Label</key><string>other</string><key>ProgramArguments</key><array><string>/bin/sh</string></array></dict></plist>
PLISTEND
t_eq "a plist that is not com.harbor.* is not judged" match "$(state)"
rm -f "$LA/other.plist"

t_section "an exemption row with a reason covers the job; one without a reason refuses to judge"
job com.harbor.gamma "" /bin/sh "$PORT_ROOT/work/g.sh"
t_eq "CONTROL: red before the row" drift "$(state)"
printf '# header\ncom.harbor.gamma\t%s/work\tmoved into an installed copy by the next deploy\n' "$PORT_ROOT" > "$PRIV/launchd-wall-exempt.tsv"
OUT="$(dl)"
t_eq "the private layer's row: green" "0 match" "$(rc) $(state)"
t_has "...the note carries the reason" "$OUT" "exempt: moved into an installed copy by the next deploy"
printf 'com.harbor.other\t%s/work\ta different job\n' "$PORT_ROOT" > "$PRIV/launchd-wall-exempt.tsv"
t_eq "a row for another job does not cover this one" drift "$(state)"
printf 'com.harbor.gamma\t%s/work\t\n' "$PORT_ROOT" > "$PRIV/launchd-wall-exempt.tsv"
t_eq "a row with no reason: unchecked (3), never green" "3 unchecked" "$(rc) $(state)"
rm -f "$PRIV/launchd-wall-exempt.tsv"
t_eq "the row removed: red again" drift "$(state)"
rm -f "$LA/com.harbor.gamma.plist"

t_section "could not judge is unchecked (3), never green"
printf 'not a host!\n' > "$PRIV/confinement-hosts.txt"
job com.harbor.alpha "" /bin/sh "$T_TMP/installed/bin/alpha.sh"
t_eq "a write list that does not compose: exit 3" 3 "$(rc)"
t_eq "...state unchecked" unchecked "$(state)"
rm -f "$PRIV/confinement-hosts.txt"
t_eq "CONTROL: restored" match "$(state)"
rm -f "$HARBOR_CHECK_RECEIPTS/drift.launchd-wall.json"; state >/dev/null
t_eq "--state writes no receipt: a verifier writes nothing" absent "$([ -e "$HARBOR_CHECK_RECEIPTS/drift.launchd-wall.json" ] && echo present || echo absent)"
t_exit "an unknown argument is a usage error" 2 sh "$DL" --nope
t_done
