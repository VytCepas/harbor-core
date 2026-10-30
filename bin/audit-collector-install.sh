#!/usr/bin/env sh
# audit-collector-install.sh (harbor#1181 lanes 5, 5b) — installs the second-uid collector. Run from your own Terminal.
#   sh audit-collector-install.sh --dry-run        print every step, change nothing
#   sudo sh audit-collector-install.sh             a hidden system user (_harborlog on macOS, harborlog on Linux), a root-owned
#                                          copy of the code, its store and signing key, read access to the sources,
#                                          and three jobs: ingest every 300 s, checkpoint daily at 04:00, and the
#                                          OTLP receiver on 127.0.0.1:4318, kept alive
#   sudo sh audit-collector-install.sh --uninstall stop and remove the jobs and the read access; the store and the user stay,
#                                          because deleting recorded history is never part of an uninstall
# macOS: launchd system daemons, read through an ACL (chmod leaves ACLs alone there). Linux: systemd system units; the
# ingest unit reads with CAP_DAC_READ_SEARCH, because a POSIX ACL's mask is reset by the floor's own chmod 0600/0500.
# A session cannot run this: every step needs root. Jobs: docs/reference/checks.md rows collector and otlp-receiver.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
case "${1:-}" in -h|--help) awk 'NR<2{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;; esac
. "$HERE/library-log.sh"
log_init collector-setup
MODE=install
for a in "$@"; do case "$a" in
  --dry-run) MODE=dry ;; --uninstall) MODE=uninstall ;;
  *) log_fail "unknown argument $a"; log_nofix "sh bin/audit-collector-install.sh --help"; exit 2 ;;
esac; done
# The test knobs (HARBOR_COLLECTOR_OS, _HOME, _SRC, _USER) let a dry run plan another OS, home, source list or user; under root each
# is refused: an install never takes a caller-chosen ACL target, path or platform.
for v in HARBOR_COLLECTOR_OS HARBOR_COLLECTOR_HOME HARBOR_COLLECTOR_SRC HARBOR_COLLECTOR_USER; do
  eval "_v=\${$v:-}"
  [ -z "$_v" ] || [ "$(id -u)" -ne 0 ] || { log_fail "$v is set under root: refusing"; log_fix "sudo env -u $v sh $0"; exit 1; }
done
OS="${HARBOR_COLLECTOR_OS:-$(uname -s)}"
OP="${SUDO_USER:-$(id -un)}"
[ "$OP" != root ] || { log_fail "run it with sudo from your own account, so it wires YOUR config dir"; log_nofix "sudo sh $0"; exit 1; }
case "$OS" in
  Darwin) U="${HARBOR_COLLECTOR_USER:-_harborlog}"; BIN='/Library/Application Support/Harbor/collector-bin'; STORE='/Library/Application Support/Harbor/collector'
          GRP=wheel; OPHOME="$(dscl . -read "/Users/$OP" NFSHomeDirectory 2>/dev/null | awk '{print $2}')" ;;
  Linux)  U="${HARBOR_COLLECTOR_USER:-harborlog}"; BIN=/opt/harbor/collector-bin; STORE=/var/lib/harbor/collector
          GRP=root; OPHOME="$(getent passwd "$OP" 2>/dev/null | cut -d: -f6)" ;;
  *) log_fail "$OS: macOS and Linux only (harbor#831: Windows only through WSL2, which is Linux here)"; log_nofix "run it on the box"; exit 1 ;;
esac
OPHOME="${HARBOR_COLLECTOR_HOME:-$OPHOME}"
[ -n "$OPHOME" ] || { log_fail "no home dir for $OP"; log_nofix "check the account"; exit 1; }
# Every source the collector copies (lane 4), wherever its writer keeps it; only those that exist now are wired.
CAND="${HARBOR_COLLECTOR_SRC:-$OPHOME/.claude/MEMORY/OBSERVABILITY:$OPHOME/.claude/MEMORY/USAGE:$OPHOME/.local/state/harbor/events:$OPHOME/.local/state/harbor/obligations:$OPHOME/.claude/.helm-approvals:$OPHOME/.claude/cache/checks.log}"
SRC=""; _ifs="$IFS"; IFS=:
for _c in $CAND; do IFS="$_ifs"; if [ -e "$_c" ]; then SRC="${SRC:+$SRC:}$_c"; else log_note "not wired, absent today: $_c"; fi; done; IFS="$_ifs"
case ":$SRC:" in *"/MEMORY/OBSERVABILITY:"*) ;; *) [ -n "${HARBOR_COLLECTOR_SRC:-}" ] || { log_fail "no $OPHOME/.claude/MEMORY/OBSERVABILITY: start one session with the floor installed first"; log_nofix "harbor deploy"; exit 1; } ;; esac
[ -n "$SRC" ] || { log_fail "no source exists"; log_nofix "start a Claude Code session first"; exit 1; }

step() { log_note "$*"; [ "$MODE" = dry ] || "$@"; }
# macOS read access: an ACL on every source, and search ONCE on each dir between a source and the home.
DIRACE="user:$U allow list,search,readattr,readextattr,file_inherit,directory_inherit"
FILEACE="user:$U allow read,readattr,readextattr"
acl() { # <+|->
  _ifs="$IFS"; IFS=:; _par=""
  for _s in $SRC; do IFS="$_ifs"
    if [ -d "$_s" ]; then
      step find "$_s" -type d -exec chmod "$1a" "$DIRACE" {} +
      step find "$_s" -type f -exec chmod "$1a" "$FILEACE" {} +
    else step chmod "$1a" "$FILEACE" "$_s"; fi
    _p="$(dirname "$_s")"
    while case "$_p" in "$OPHOME"|"$OPHOME"/*) true ;; *) false ;; esac; do _par="$_par$_p
"; [ "$_p" != "$OPHOME" ] || break; _p="$(dirname "$_p")"; done
  done; IFS="$_ifs"
  printf "%s" "$_par" | LC_ALL=C sort -u | while IFS= read -r _d; do
    [ -z "$_d" ] || step chmod "$1a" "user:$U allow search" "$_d"
  done
}
# The jobs are the committed templates (launchd/, systemd/; lint X9 and schedules-test hold docs/reference/checks.md to them).
render() { sed -e "s|@SOURCES@|$SRC|g" -e "s|@BIN@|$BIN|g" -e "s|@STORE@|$STORE|g" "$1"; }   # <template>
case "$OS" in
  Darwin) TPL="$HERE/../launchd"; JOBS="com.harbor.audit.collector com.harbor.audit.collector-checkpoint com.harbor.audit.otlp-receiver" ;;
  Linux)  TPL="$HERE/../systemd"; JOBS="harbor-audit-collector.service harbor-audit-collector.timer harbor-audit-collector-checkpoint.service harbor-audit-collector-checkpoint.timer harbor-audit-otlp-receiver.service" ;;
esac
for j in $JOBS; do
  case "$OS" in Darwin) _t="$TPL/$j.plist" ;; *) _t="$TPL/$j" ;; esac
  [ -f "$_t" ] || { log_fail "no template $_t"; log_fix "run it from the harbor checkout: sh ~/port/harbor/bin/audit-collector-install.sh"; exit 1; }
done

if [ "$MODE" != dry ] && [ "$(id -u)" -ne 0 ]; then log_fail "not root"; log_fix "sudo sh $0 ${1:-}"; exit 1; fi

if [ "$MODE" = uninstall ]; then
  case "$OS" in
    Darwin) for j in $JOBS; do launchctl bootout "system/$j" 2>/dev/null || :; rm -f "/Library/LaunchDaemons/$j.plist"; done
            acl - 2>/dev/null || : ;;
    Linux)  systemctl disable --now harbor-audit-collector.timer harbor-audit-collector-checkpoint.timer harbor-audit-otlp-receiver.service 2>/dev/null || :
            for j in $JOBS; do rm -f "/etc/systemd/system/$j"; done; systemctl daemon-reload 2>/dev/null || : ;;
  esac
  log_ok "jobs and read access removed; $STORE and the $U user are kept (sudo cat \"$STORE/events.jsonl\")"; log_end; exit 0
fi

# 1. the user: a hidden system account with no shell and no home, so nothing can log in as it
case "$OS" in
  Darwin)
    if ! dscl . -read "/Users/$U" >/dev/null 2>&1; then
      ID=""; for i in $(seq 400 499); do
        dscl . -list /Users UniqueID | awk -v i="$i" '$2 == i { f = 1 } END { exit f }' \
          && dscl . -list /Groups PrimaryGroupID | awk -v i="$i" '$2 == i { f = 1 } END { exit f }' && { ID="$i"; break; }
      done
      [ -n "$ID" ] || { log_fail "no free system id in 400-499"; log_nofix "pick one by hand"; exit 1; }
      step dscl . -create "/Groups/$U" PrimaryGroupID "$ID"
      step dscl . -create "/Users/$U" UniqueID "$ID"
      step dscl . -create "/Users/$U" PrimaryGroupID "$ID"
      step dscl . -create "/Users/$U" UserShell /usr/bin/false
      step dscl . -create "/Users/$U" NFSHomeDirectory /var/empty
      step dscl . -create "/Users/$U" IsHidden 1
      step dscl . -create "/Users/$U" RealName "Harbor log collector"
    else log_note "user $U exists"; fi ;;
  Linux)
    if ! getent passwd "$U" >/dev/null 2>&1; then
      step useradd --system --user-group --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin --comment "Harbor log collector" "$U"
    else log_note "user $U exists"; fi ;;
esac
# the receiver runs on the system python3, not one a user can replace
[ "$MODE" = dry ] || /usr/bin/python3 -I -c pass 2>/dev/null || { log_fail "/usr/bin/python3 does not run: the OTLP receiver needs it"; log_fix "macOS: xcode-select --install; Linux: install python3"; exit 1; }
# 2. the code runs from a ROOT-owned copy: a copy under ~/.claude could be edited by the uid it watches
step mkdir -p "$BIN"
step cp "$HERE/audit-collector.sh" "$HERE/library-log.sh" "$HERE/library-fs.sh" "$HERE/audit-otlp-receiver.py" "$BIN/"
step chown -R "root:$GRP" "$BIN"
step chmod 0755 "$BIN" "$BIN/audit-collector.sh" "$BIN/library-log.sh" "$BIN/library-fs.sh" "$BIN/audit-otlp-receiver.py"
# 3. the store and the signing key belong to the collector alone
step mkdir -p "$STORE/key"
# Only what the collector does not own yet: its sealed data files are append-only (uappnd), which refuses
# chown even to root, so a recursive chown made every reinstall onto a used store exit here (harbor#949).
step find "$STORE" ! -user "$U" -exec chown "$U:$U" {} +
step chmod 0755 "$STORE"
step chmod 0700 "$STORE/key"
if [ ! -f "$STORE/key/collector" ]; then
  step sudo -u "$U" ssh-keygen -q -t ed25519 -N '' -C harbor-collector -f "$STORE/key/collector"
fi
# 4. read access (macOS only: on Linux the ingest unit holds CAP_DAC_READ_SEARCH instead)
[ "$OS" != Darwin ] || acl +
# 5. the jobs
case "$OS" in
  Darwin)
    for j in $JOBS; do
      if [ "$MODE" = dry ]; then log_note "would write /Library/LaunchDaemons/$j.plist and bootstrap it"; continue; fi
      launchctl bootout "system/$j" 2>/dev/null || :
      render "$TPL/$j.plist" > "/Library/LaunchDaemons/$j.plist"; chown "root:$GRP" "/Library/LaunchDaemons/$j.plist"
      chmod 0644 "/Library/LaunchDaemons/$j.plist"; launchctl bootstrap system "/Library/LaunchDaemons/$j.plist"
    done ;;
  Linux)
    for j in $JOBS; do
      if [ "$MODE" = dry ]; then log_note "would write /etc/systemd/system/$j"; continue; fi
      render "$TPL/$j" > "/etc/systemd/system/$j"; chown "root:$GRP" "/etc/systemd/system/$j"; chmod 0644 "/etc/systemd/system/$j"
    done
    step systemctl daemon-reload
    step systemctl enable --now harbor-audit-collector.timer harbor-audit-collector-checkpoint.timer harbor-audit-otlp-receiver.service ;;
esac
[ "$MODE" = dry ] && { log_note "dry run: nothing changed"; log_end; exit 0; }
# 6. see it work rather than assume it
case "$OS" in
  Darwin) launchctl kickstart -k system/com.harbor.audit.collector 2>/dev/null || : ;;
  Linux)  systemctl start harbor-audit-collector.service 2>/dev/null || : ;;
esac
sleep 3
[ -s "$STORE/status.json" ] || { log_fail "the first ingest wrote no $STORE/status.json"; log_nofix "macOS: sudo cat \"$STORE/com.harbor.audit.collector.log\"; Linux: journalctl -u harbor-audit-collector"; exit 1; }
_rc="$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" --data "{}" http://127.0.0.1:4318/v1/logs 2>/dev/null || true)"
[ "$_rc" = 200 ] || { log_fail "the OTLP receiver does not answer on 127.0.0.1:4318 (got ${_rc:-nothing})"; log_nofix "macOS: sudo cat \"$STORE/com.harbor.audit.otlp-receiver.log\"; Linux: journalctl -u harbor-audit-otlp-receiver"; exit 1; }
log_ok "collector running as $U: $(cat "$STORE/status.json")"
log_end
