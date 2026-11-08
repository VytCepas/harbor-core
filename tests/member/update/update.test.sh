#!/bin/sh
# update.test.sh (harbor#1278) — bin/member-update.sh over a fixture core repo and a fixture managed root, no network and no root: it moves
# every row of contracts/member-files.txt to the pinned commit, keeps the marker, checks member-integrity.sh, and puts the old floor back when anything fails.
# Not covered here: the root-only branch (overrides refused, chown), the OS defaults of the managed root, and a real GitHub remote.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/hub/fixtures/make-hub.sh"
U="$T_ROOT/bin/member-update.sh"; C="$T_TMP/core"; R="$T_TMP/root"; POL="$T_TMP/pol"; MS="$T_TMP/managed-settings.json"
G() { git -C "$C" -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false "$@"; }
sha() { G rev-parse "$1"; }

# the stub floor: hash covers bin and core.commit, check compares it with floor.pin
GOOD_INTEGRITY='#!/bin/sh
R="$(cd "$(dirname "$0")/.." && pwd)"
h() { (cd "$R" && find bin -type f | LC_ALL=C sort | xargs cksum; cat core.commit 2>/dev/null) | cksum | awk "{printf \"%016x\\n\", \$1}"; }
case "$1" in hash) h ;; check) [ "$(h)" = "$(cat "$R/floor.pin" 2>/dev/null)" ] ;; esac'
list() { { printf '# the floor
bin/harbor
bin/member-integrity.sh
bin/tool.sh
contracts/tiers.tsv tiers.tsv
'; printf '%s
' "$@"; } > "$C/contracts/member-files.txt"; }
mkcore() {
  rm -rf "$C"; mkdir -p "$C/bin" "$C/contracts"; git -C "$C" init -q . ; git -C "$C" config uploadpack.allowAnySHA1InWant true
  printf 'CONTRACT_VERSION=1\n' > "$C/bin/harbor"; printf '%s\n' "$GOOD_INTEGRITY" > "$C/bin/member-integrity.sh"
  printf 'echo A\n' > "$C/bin/tool.sh"; printf 'echo old\n' > "$C/bin/old.sh"; printf 'row\tA\n' > "$C/contracts/tiers.tsv"
  printf 'echo unlisted\n' > "$C/bin/unlisted.sh"
  # The commit's composer: the settings it prints are the arguments it was given, so a case reads what reached it.
  cat > "$C/bin/member-managed.sh" <<'STUB'
#!/bin/sh
m='[]'; p=''; for a in "$@"; do [ "$p" != --mcp-allow ] || m="$(cat "$a")"; p="$a"; done
jq -n --argjson m "$m" --arg c "${0%/bin/*}" '{composed: $ARGS.positional, mcp: $m, by: ($c | split("/") | last)}' --args -- "$@"
STUB
  list bin/old.sh
  G add -A && G commit -q -m A && G tag A
  printf 'echo B\n' > "$C/bin/tool.sh"; git -C "$C" rm -q bin/old.sh; printf 'echo new\n' > "$C/bin/new.sh"; printf 'row\tB\n' > "$C/contracts/tiers.tsv"
  list bin/new.sh
  G add -A && G commit -q -m B && G tag B
  # C: a floor whose check always fails after the swap
  { printf '%s\n' "$GOOD_INTEGRITY" | sed 's/check) \[ .*$/check) exit 1 ;; esac/'; } > "$C/bin/member-integrity.sh"
  printf 'echo C\n' > "$C/bin/tool.sh"; G add -A && G commit -q -m C && G tag C
  # D: a link in bin
  G checkout -q B && ln -s /etc/hosts "$C/bin/link" && list bin/new.sh bin/link && G add -A && G commit -q -m D && G tag D && G checkout -q B
  # E: a file git archive rewrites (export-subst), so the unpacked bytes are not the blob the commit names
  printf 'id $Format:%%H$\n' > "$C/bin/stamp"; printf 'bin/stamp export-subst\n' > "$C/.gitattributes"; list bin/new.sh bin/stamp; G add -A && G commit -q -m E && G tag E && G checkout -q B
  # F: a list naming a file the commit lacks. H: no list at all. I: a row that would land outside bin.
  list bin/new.sh bin/gone.sh; G add -A && G commit -q -m F && G tag F && G checkout -q B
  git -C "$C" rm -q contracts/member-files.txt; G commit -q -m H && G tag H && G checkout -q B
  printf 'bin/harbor\nbin/member-integrity.sh\nbin/tool.sh ../evil\n' > "$C/contracts/member-files.txt"; G add -A && G commit -q -m I && G tag I && G checkout -q B
  # J: a commit whose composer fails. K: one with no composer. L: one that lists upterm itself.
  printf '#!/bin/sh\necho "a composer that cannot" >&2; exit 1\n' > "$C/bin/member-managed.sh"; G add -A && G commit -q -m J && G tag J && G checkout -q B
  git -C "$C" rm -q bin/member-managed.sh; G commit -q -m K && G tag K && G checkout -q B
  printf 'up\n' > "$C/bin/upterm"; list bin/new.sh bin/upterm; G add -A && G commit -q -m L && G tag L && G checkout -q B
}
mkroot() { # install commit A in a fresh managed root, as the install would
  rm -rf "$R" "$R".update.*; mkdir -p "$R/bin"; G archive A bin contracts/tiers.tsv | tar -x -C "$R"
  mv "$R/contracts/tiers.tsv" "$R/bin/"; rmdir "$R/contracts"; rm -f "$R/bin/unlisted.sh"
  : > "$R/bin/harbor-member-mode"
  printf 'hub namespaces="harbor-hub" %s\n' "$(cut -d' ' -f1,2 "$HUBKEY.pub")" > "$R/hub-signers"
  sha A > "$R/core.commit"; printf '1\n' > "$R/pin.serial"
  # What the install places beside the list, named in floor.extra; the facts it writes; the settings it landed, with a proxy IT set.
  printf 'upterm v1\n' > "$R/bin/upterm"; printf 'harbor-member-mode\nupterm\n' > "$R/floor.extra"
  mkdir -p "$T_TMP/home"; printf 'hub=fixture-org/fixture-hub\nlogin=alice\nhome=%s\n' "$T_TMP/home" > "$R/member.conf"
  jq -n '{env: {HARBOR_MEMBER_ROLE: "member", HTTPS_PROXY: "http://proxy.corp.example:3128"}, allowedMcpServers: [{serverName: "fixture-mcp"}]}' > "$MS"
  sh "$R/bin/member-integrity.sh" hash > "$R/floor.pin"
}
mkpol() { # <serial> <commit> [contract]: with one host and the hub's relay, which the settings must come to carry
  mkdir -p "$POL"; jq --argjson s "$1" --arg c "$2" --argjson k "${3:-1}" '.serial = $s | .core.commit = $c | .core.contract = $k
    | .hosts = ["pkg.example.com", "*.corp.example"] | .support = {relay: "wss://relay.example:8443"}' "$T_ROOT/tests/hub/fixtures/policy.json" > "$POL/policy.json"
  rm -f "$POL/policy.json.sig"; ssh-keygen -q -Y sign -f "$HUBKEY" -n harbor-hub "$POL/policy.json"
}
upd() { _o="$(HARBOR_MEMBER_ROOT="$R" HARBOR_MEMBER_CORE_SOURCE="file://$C" sh "$U" "$@" 2>&1)" && RC=0 || RC=$?; OUT="$_o"; }
state() { printf '%s|%s|%s|%s|%s' "$(cat "$R/core.commit")" "$(cat "$R/floor.pin")" "$(cat "$R/pin.serial")" "$(cd "$R/bin" && find . -type f | LC_ALL=C sort | xargs cksum | cksum)" "$(cksum < "$MS")"; }
check_ok() { sh "$R/bin/member-integrity.sh" check; }
mkcore; A="$(sha A)"; B="$(sha B)"; Cc="$(sha C)"; D="$(sha D)"; E="$(sha E)"; F="$(sha F)"; H="$(sha H)"; I="$(sha I)"; J="$(sha J)"; K="$(sha K)"; L="$(sha L)"

t_section "1 - a dry run says what it would do and changes nothing"
mkroot; mkpol 2 "$B"; before="$(state)"
upd --dry-run --policy "$POL/policy.json"
t_eq "exit 0" 0 "$RC"; t_has "it names the move" "$OUT" "would move the floor from $A to $B"
t_eq "and the floor is as it was" "$before" "$(state)"

t_section "2 - the update: new files, removed files, kept files, a new pin"
mkroot; mkpol 2 "$B"
upd --policy "$POL/policy.json"
t_eq "exit 0" 0 "$RC"; t_has "it says updated" "$OUT" "updated: $A -> $B"
t_eq "tool.sh is commit B's" "echo B" "$(cat "$R/bin/tool.sh")"
t_eq "new.sh arrived" "echo new" "$(cat "$R/bin/new.sh")"
t_eq "a data file moved with the code, flat" "$(printf 'row\tB')" "$(cat "$R/bin/tiers.tsv")"
t_eq "a file the list doesn't name stays out" "no" "$([ -e "$R/bin/unlisted.sh" ] && echo yes || echo no)"
t_eq "the floor is runnable, as an install lands it" "" "$(find "$R/bin" -type f ! -perm -100 ! -name harbor-member-mode | head -n 1)"
t_eq "old.sh, which core dropped, is gone" "no" "$([ -e "$R/bin/old.sh" ] && echo yes || echo no)"
t_eq "harbor-member-mode, which core never shipped, stayed" "yes" "$([ -e "$R/bin/harbor-member-mode" ] && echo yes || echo no)"
t_eq "core.commit records B" "$B" "$(cat "$R/core.commit")"
t_eq "pin.serial records the policy's serial" "2" "$(cat "$R/pin.serial")"
if check_ok; then t_pass; else t_fail "member-integrity.sh check fails after the update"; fi
t_eq "no work folder or lock left behind" "0" "$(find "$T_TMP" -maxdepth 1 -name 'root.update*' | grep -c . || true)"
t_eq "bin is not writable by group or others" "" "$(find "$R/bin" -perm -020 -o -perm -002 | head -n 1)"
upd --policy "$POL/policy.json"
t_eq "a second run is a no-op" 0 "$RC"; t_has "and says unchanged" "$OUT" "unchanged"

t_section "3 - a failing check puts the old floor back"
mkroot; mkpol 3 "$Cc"; before="$(state)"
upd --policy "$POL/policy.json"
t_eq "exit 1" 1 "$RC"; t_has "the reason is the check" "$OUT" "member-integrity.sh check fails on the new floor"
t_has "it says the old floor checks again" "$OUT" "the old floor checks again"
t_eq "bin, pin, commit and serial are exactly as before" "$before" "$(state)"
t_eq "the new commit's tool did not stay" "echo A" "$(cat "$R/bin/tool.sh")"
t_eq "and no work folder is left" "0" "$(find "$T_TMP" -maxdepth 1 -name 'root.update*' | grep -c . || true)"

t_section "4 - the policy is verified by the updater itself"
mkroot; mkpol 2 "$B"; before="$(state)"
printf ' ' >> "$POL/policy.json"; upd --policy "$POL/policy.json"
t_eq "a policy edited after signing: exit 1" 1 "$RC"; t_has "and refused for its signature" "$OUT" "signature does not verify"
t_eq "the floor is untouched" "$before" "$(state)"
mkpol 2 "$B"; ssh-keygen -q -t ed25519 -N '' -f "$T_TMP/other" 2>/dev/null
printf 'hub namespaces="harbor-hub" %s\n' "$(cut -d' ' -f1,2 "$T_TMP/other.pub")" > "$R/hub-signers"; before="$(state)"
upd --policy "$POL/policy.json"; t_eq "signed by a key the box does not trust: exit 1" 1 "$RC"
t_eq "the floor is untouched" "$before" "$(state)"
mkroot; mkpol 2 "$B"; rm "$POL/policy.json.sig"; upd --policy "$POL/policy.json"
t_eq "no signature file: exit 1" 1 "$RC"
mkroot; mkpol 1 "$B"; printf '5\n' > "$R/pin.serial"; before="$(state)"
upd --policy "$POL/policy.json"
t_eq "a serial below the last applied: exit 1" 1 "$RC"; t_has "named as an old signed file" "$OUT" "below the 5 already applied"
t_eq "the floor is untouched" "$before" "$(state)"

t_section "5 - what is refused before anything moves"
mkroot; mkpol 2 "$B" 2; before="$(state)"
upd --policy "$POL/policy.json"; t_eq "a pin of contract 2 over a floor of contract 1: exit 1" 1 "$RC"
t_has "named" "$OUT" "pins contract 2"
t_eq "the floor is untouched" "$before" "$(state)"
mkroot; mkpol 2 "$D"; before="$(state)"
upd --policy "$POL/policy.json"; t_eq "a commit with a link in bin: exit 1" 1 "$RC"; t_has "named" "$OUT" "link or submodule"
t_eq "the floor is untouched" "$before" "$(state)"
mkroot; mkpol 2 "$E"; before="$(state)"
upd --policy "$POL/policy.json"; t_eq "a file that differs from the commit's blob: exit 1" 1 "$RC"; t_has "named" "$OUT" "differs from the blob"
t_eq "the floor is untouched" "$before" "$(state)"
mkroot; mkpol 2 "$F"; before="$(state)"
upd --policy "$POL/policy.json"; t_eq "a listed file the commit lacks: exit 1" 1 "$RC"; t_has "named: no half floor" "$OUT" "bin/gone.sh"
t_eq "the floor is untouched" "$before" "$(state)"
mkroot; mkpol 2 "$H"; before="$(state)"
upd --policy "$POL/policy.json"; t_eq "a commit with no list: exit 1" 1 "$RC"; t_has "named" "$OUT" "no contracts/member-files.txt"
t_eq "the floor is untouched" "$before" "$(state)"
mkroot; mkpol 2 "$I"; before="$(state)"
upd --policy "$POL/policy.json"; t_eq "a row landing outside bin: exit 1" 1 "$RC"; t_has "named" "$OUT" "not a plain name"
t_eq "the floor is untouched" "$before" "$(state)"
mkroot; mkpol 2 "$B"; printf 'tampered\n' >> "$R/bin/tool.sh"; before="$(state)"
upd --policy "$POL/policy.json"; t_eq "a floor that already fails its check: exit 1" 1 "$RC"; t_has "it will not re-pin over it" "$OUT" "re-pinning would hide that"
t_eq "the floor is untouched" "$before" "$(state)"
mkroot; rm "$R/bin/harbor-member-mode"; sh "$R/bin/member-integrity.sh" hash > "$R/floor.pin"; mkpol 2 "$B"; before="$(state)"
upd --policy "$POL/policy.json"; t_eq "a box without the member-mode file: exit 1" 1 "$RC"; t_has "it is not a member box" "$OUT" "not a member box"
t_eq "and is not touched" "$before" "$(state)"
mkroot; mkpol 2 "$(printf '1%.0s' $(seq 1 40))"; before="$(state)"
upd --policy "$POL/policy.json"; t_eq "a pinned commit that is not in core: exit 3" 3 "$RC"
t_eq "the floor is untouched" "$before" "$(state)"
mkpol 2 "$B"; HARBOR_MEMBER_ROOT="$R" HARBOR_MEMBER_CORE_SOURCE="file://$T_TMP/nowhere" sh "$U" --policy "$POL/policy.json" >/dev/null 2>&1; RC=$?
t_eq "a core that is not there: exit 3" 3 "$RC"

t_section "7 - what the install placed beside the list moves with the floor (N3)"
mkroot; mkpol 2 "$B"; upd --policy "$POL/policy.json"
t_eq "an update exits 0" 0 "$RC"
t_eq "upterm, which no list names, is still there" 'upterm v1' "$(cat "$R/bin/upterm" 2>/dev/null)"
t_eq "...runnable" yes "$([ -x "$R/bin/upterm" ] && echo yes || echo no)"
t_eq "and floor.extra still names it" "$(printf 'harbor-member-mode\nupterm')" "$(cat "$R/floor.extra")"
mkroot; rm "$R/bin/upterm"; sh "$R/bin/member-integrity.sh" hash > "$R/floor.pin"; mkpol 2 "$B"; before="$(state)"
upd --policy "$POL/policy.json"; t_eq "floor.extra names a file bin lacks: refused" 1 "$RC"; t_has "named" "$OUT" 'bin holds no such file'
t_eq "the floor is untouched" "$before" "$(state)"
mkroot; mkpol 2 "$L"; before="$(state)"
upd --policy "$POL/policy.json"; t_eq "a commit that lists a file floor.extra names: refused" 1 "$RC"; t_has "named" "$OUT" 'one owner only'
t_eq "the floor is untouched" "$before" "$(state)"

t_section "8 - the managed settings are composed again from the verified policy (N7)"
mkroot; mkpol 2 "$B"; upd --policy "$POL/policy.json"
t_eq "an update exits 0" 0 "$RC"
t_eq "the commit's own composer wrote them" core "$(jq -r .by "$MS")"
args() { jq -r '.composed | join(" ")' "$MS"; }
t_has "for the hub and login of member.conf" "$(args)" '--hub fixture-org/fixture-hub --login alice'
t_has "for the member who owns the home" "$(args)" "--user $(ls -ld "$T_TMP/home" | awk '{ print $3 }')"
t_has "naming this managed root in the hooks" "$(args)" "--root $R"
t_has "with the policy's relay denied" "$(args)" '--deny-host relay.example'
t_has "and its hosts allowed, a *. row as one word" "$(args)" '--allow-host pkg.example.com --allow-host *.corp.example'
t_eq "keeping the MCP list the install landed" '[{"serverName":"fixture-mcp"}]' "$(jq -c .mcp "$MS")"
t_eq "a proxy IT set in managed env carries over" 'http://proxy.corp.example:3128' "$(jq -r '.env.HTTPS_PROXY // empty' "$MS")"
mkroot; mkpol 3 "$Cc"; before="$(state)"
upd --policy "$POL/policy.json"; t_eq "a floor that fails its check after the swap: exit 1" 1 "$RC"
t_eq "and the settings go back with the rest" "$before" "$(state)"
mkroot; mkpol 2 "$J"; before="$(state)"
upd --policy "$POL/policy.json"; t_eq "a commit whose settings don't compose: exit 1" 1 "$RC"; t_has "named" "$OUT" 'do not compose'
t_eq "the floor is untouched" "$before" "$(state)"
mkroot; mkpol 2 "$K"; before="$(state)"
upd --policy "$POL/policy.json"; t_eq "a commit with no composer: exit 1" 1 "$RC"; t_has "named" "$OUT" 'no bin/member-managed.sh'
t_eq "the floor is untouched" "$before" "$(state)"
mkroot; rm "$MS"; mkpol 2 "$B"; upd --policy "$POL/policy.json"
t_eq "no settings beside the root: refused" 1 "$RC"; t_has "named" "$OUT" 'never landed whole'
if command -v chflags >/dev/null 2>&1 && mkroot && chflags uchg "$MS" 2>/dev/null; then
  mkpol 2 "$B"; _ms="$(cat "$MS")"; upd --policy "$POL/policy.json"
  t_eq "settings this run can't write (W4, as /mnt/c may be): the floor still moves" 0 "$RC"
  t_has "...and it says the old settings stay" "$OUT" 'the old settings stay'
  t_eq "...whole" "$_ms" "$(cat "$MS")"
  chflags nouchg "$MS"
else echo "update-test: SKIPPED the unwritable-settings case (no chflags uchg here)"; fi

t_section "9 - root's PATH is system directories, and a tool must be root's (N8)"
t_eq "PATH is the system directories alone" /usr/bin:/bin:/usr/sbin:/sbin "$(MEMBER_UPDATE_LIB=1 PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin sh -c '. "$0"; printf %s "$PATH"' "$U")"
ro() { MEMBER_UPDATE_LIB=1 sh -c '. "$0"; root_owned "$1"' "$U" "$1" && echo yes || echo no; }
t_eq "CONTROL: a system tool is root's" yes "$(ro "$(PATH=/usr/bin:/bin command -v tar)")"
printf '#!/bin/sh\n' > "$T_TMP/jq"; chmod 755 "$T_TMP/jq"
t_eq "a tool the user owns is not" no "$(ro "$T_TMP/jq")"
ln -s "$T_TMP/jq" "$T_TMP/jq-link"; t_eq "nor a link to one" no "$(ro "$T_TMP/jq-link")"
mkdir -p "$T_TMP/linkdir"; ln -s "$(PATH=/usr/bin:/bin command -v tar)" "$T_TMP/linkdir/tar"
t_eq "a link the user owns to a root tool is judged where it leads" yes "$(ro "$T_TMP/linkdir/tar")"

t_section "6 - one run at a time, and usage"
mkroot; mkpol 2 "$B"; mkdir "$R.update.lock"; printf '%s\n' "$$" > "$R.update.lock/pid"
upd --policy "$POL/policy.json"; t_eq "a live lock: exit 3" 3 "$RC"; t_has "named" "$OUT" "another update is running"
printf '999999\n' > "$R.update.lock/pid"; upd --policy "$POL/policy.json"
t_eq "a stale lock is cleared and the run goes on" 0 "$RC"
t_exit "an argument it does not know" 2 sh "$U" --nonsense
t_exit "--help" 0 sh "$U" --help
t_done
