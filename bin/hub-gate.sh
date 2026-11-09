#!/usr/bin/env sh
# hub-gate.sh (harbor#1278) — the gate a hub repo's pull requests and pushes must pass. Reads and reports; writes nothing in the hub.
#   sh hub-gate.sh <hub-dir> [--base POLICY] [--signers FILE] [--core DIR]
#     --base      the policy.json the change is made against: a changed policy must carry a higher serial (replay, hub.md)
#     --signers   the allowed_signers file the signature is checked with (default <hub-dir>/hub-signers, the public key)
#     --core      a harbor checkout holding the patterns and registers (default: the one this script sits in)
# Checks (a finding is `[id] text`): layout, leaks, secrets, share, policy, signature, serial, packs. The layout check judges a file with
# no kind, which lint-share skips (R29). Env: HARBOR_HUB_GATE_GITLEAKS (a missing scanner is a finding), HARBOR_HUB_GATE_PRIVATE (the company's names).
# Exit 0 clean, 1 findings, 2 usage or an unreadable hub. Format: contracts/hub.md.
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
LOG_FD=2; export LOG_FD
. "$HERE/library-log.sh"
log_init hub-gate
. "$HERE/library-hub.sh"
usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

HUB=""; BASE=""; SIGNERS=""; CORE="$HERE/.."
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --base) [ "$#" -ge 2 ] || usage; BASE="$2"; shift ;;
    --signers) [ "$#" -ge 2 ] || usage; SIGNERS="$2"; shift ;;
    --core) [ "$#" -ge 2 ] || usage; CORE="$2"; shift ;;
    -*) usage ;;
    *) [ -z "$HUB" ] || usage; HUB="$1" ;;
  esac
  shift
done
[ -n "$HUB" ] || usage
[ -d "$HUB" ] || { log_fail "$HUB is not a folder"; log_nofix "name the hub checkout"; exit 2; }
HUB="$(CDPATH='' cd -- "$HUB" && pwd)"; CORE="$(CDPATH='' cd -- "$CORE" && pwd)"
for _f in "$HERE/lint-leaks.sh" "$HERE/lint-share.sh" "$HERE/hub-format.sh" "$CORE/contracts/leak-patterns.tsv" "$CORE/standards/naming/kinds.tsv"; do
  [ -r "$_f" ] || { log_fail "$_f is missing, so nothing was judged"; log_nofix "use a complete harbor checkout (--core DIR)"; exit 2; }
done
command -v jq >/dev/null 2>&1 || { log_fail "jq is missing, so nothing was judged"; log_fix "$(pkg_hint jq)"; exit 2; }

T="$(mktemp -d "${TMPDIR:-/tmp}/hub-gate.XXXXXX")" || exit 2
trap 'rm -rf "$T"' EXIT INT TERM
: > "$T/findings"
find_() { printf 'hub-gate: [%s] %s\n' "$1" "$2" >> "$T/findings"; }
quote() { sed 's/^/  /' | head -n "${1:-8}"; }   # a tool's own words, bounded

# The scanners judge a staged copy of exactly the files present: git grep sees only the index, so an untracked or ignored
# file would pass unseen, and gitleaks would read a .gitleaksignore the hub ships (harbor#1278, R29).
S="$T/stage"; mkdir -p "$S"
( cd "$HUB" && tar --exclude=.git -cf - . ) | ( cd "$S" && tar -xf - )
( cd "$S" && git init -q . && git add -Af . ) >/dev/null 2>&1 || { log_fail "git could not stage the hub"; log_nofix "git add -A in a copy of the hub shows why"; exit 2; }
( cd "$S" && find . -path ./.git -prune -o -type f -print | sed 's|^\./||' | LC_ALL=C sort ) > "$T/files"

# 1 · layout: a hub holds the policy, its signature and key, packs, and the files that describe it.
while IFS= read -r _p; do
  case "$_p" in
    policy.json|policy.json.sig|hub-signers|README.md|CODEOWNERS|.gitignore|packs/*|.github/*) ;;
    *) find_ layout "$_p is not part of a hub (contracts/hub.md): no policy, key, pack or description" ;;
  esac
done < "$T/files"

# 2 · leaks: the export gate over the staged files. A company's own names come from HARBOR_HUB_GATE_PRIVATE, never from the hub.
PRIV="${HARBOR_HUB_GATE_PRIVATE:-$T/no-private}"
if ! env HARBOR_SCOPE_ROOT="$S" HARBOR_SCOPE_PRIVATE="$PRIV" LEAKS_CORE_PATTERNS="$CORE/contracts/leak-patterns.tsv" \
       LEAKS_BASELINE="$T/none" LEAKS_EXPORT=1 sh "$HERE/lint-leaks.sh" --zero > "$T/leaks.out" 2>&1; then
  find_ leaks "the leak gate is red (names below are pattern ids, never the matched text)"
  env HARBOR_SCOPE_ROOT="$S" HARBOR_SCOPE_PRIVATE="$PRIV" LEAKS_CORE_PATTERNS="$CORE/contracts/leak-patterns.tsv" \
    LEAKS_BASELINE="$T/none" LEAKS_EXPORT=1 sh "$HERE/lint-leaks.sh" --list 2>/dev/null | quote 20 >> "$T/findings" || :
  [ -s "$T/leaks.out" ] && quote 4 < "$T/leaks.out" >> "$T/findings"
fi

# 3 · secrets: gitleaks default rules only. The hub's own config is never read, so a hub cannot allow-list its own secret.
GL="${HARBOR_HUB_GATE_GITLEAKS:-gitleaks}"
if ! command -v "$GL" >/dev/null 2>&1; then
  find_ secrets "gitleaks is not installed, so the hub was not scanned for secrets"
else
  printf '[extend]\nuseDefault = true\n' > "$T/gitleaks.toml"
  if ( cd "$S"
       set -- --no-banner --redact --exit-code 1 --report-format json --report-path "$T/gitleaks.json" --config "$T/gitleaks.toml"
       if "$GL" dir --help >/dev/null 2>&1; then exec "$GL" dir "$@" .; else exec "$GL" detect --no-git "$@" --source .; fi
     ) > "$T/gitleaks.out" 2>&1; then :; else
    _rc=$?
    if [ -s "$T/gitleaks.json" ] && [ "$(jq 'length' "$T/gitleaks.json" 2>/dev/null || echo 0)" -gt 0 ]; then
      jq -r '.[] | "a secret: \(.File):\(.StartLine) rule \(.RuleID)"' "$T/gitleaks.json" | while IFS= read -r _l; do find_ secrets "$_l"; done
    else find_ secrets "gitleaks could not scan the hub (exit $_rc): $(tr -d '\033' < "$T/gitleaks.out" | sed 's/\[[0-9;]*m//g' | tail -n 1)"; fi
  fi
fi

# 4 · share: a file of a kind lives in a share that kind may take. Files with no kind are not judged here; layout above and the
# policy check below judge them, and the test plants one to keep that so.
mkdir -p "$T/empty"
if ! env HARBOR_SCOPE_ROOT="$T/empty" SHARE_KINDS="$CORE/standards/naming/kinds.tsv" HARBOR_SCOPE_PRIVATE="$T/no-private" \
       sh "$HERE/lint-share.sh" --check --strict --tree "$S=hub" > "$T/share.out" 2>&1; then
  find_ share "a file lives in a share its kind does not allow, or the share check could not run"
  grep -E 'WARN|FAIL|lint-share:' "$T/share.out" | quote 10 >> "$T/findings" || :
fi

# 5 · policy: always judged, whatever lint-share thinks of it.
POL="$S/policy.json"
if [ ! -f "$POL" ]; then find_ policy "no policy.json"
elif ! sh "$HERE/hub-format.sh" policy "$POL" > "$T/policy.out" 2>&1; then
  find_ policy "policy.json does not match contracts/hub.md"; quote 12 < "$T/policy.out" >> "$T/findings"
elif jq -e '(.core.commit | test("^0+$")) or ((.approval.approvers // []) | index("your-admin-login")) != null' "$POL" >/dev/null 2>&1; then
  find_ policy "policy.json still holds a value from the starter (the all-zero commit or the your-admin-login approver)"
fi

# 6 · signature: policy.json.sig by the key in the signers file, principal hub, namespace harbor-hub.
SIG="$S/policy.json.sig"; SGN="${SIGNERS:-$S/hub-signers}"
if [ ! -f "$POL" ]; then :
elif [ ! -f "$SIG" ]; then find_ signature "no policy.json.sig: the policy is unsigned and no laptop would take it"
elif [ ! -s "$SGN" ]; then find_ signature "no signers file (hub-signers): the signature cannot be checked"
elif ! command -v ssh-keygen >/dev/null 2>&1; then find_ signature "ssh-keygen is missing, so the signature was not checked"
elif ! ssh-keygen -Y verify -f "$SGN" -I hub -n harbor-hub -s "$SIG" < "$POL" > "$T/sig.out" 2>&1; then
  find_ signature "policy.json.sig does not verify against the signers file"; quote 3 < "$T/sig.out" >> "$T/findings"
fi

# 7 · serial: a changed policy must rise. The same bytes may stand (a change elsewhere in the repo).
if [ -n "$BASE" ]; then
  if [ ! -r "$BASE" ]; then find_ serial "the base policy $BASE cannot be read"
  elif [ -f "$POL" ] && ! cmp -s "$BASE" "$POL"; then
    _b="$(jq -r '.serial // 0' "$BASE" 2>/dev/null || echo 0)"; _n="$(jq -r '.serial // 0' "$POL" 2>/dev/null || echo 0)"
    case "$_b$_n" in *[!0-9]*|'') find_ serial "a serial is not a whole number" ;;
      *) [ "$_n" -gt "$_b" ] || find_ serial "serial $_n does not rise above the base policy's $_b: an old signed file could be replayed" ;;
    esac
  fi
fi

# 8 · packs: the manifests, the hashes they name, and the hooks policy approves.
if [ -f "$POL" ] && jq -e . "$POL" >/dev/null 2>&1; then
  jq -r '(.packs // [])[] | .id' "$POL" | while IFS= read -r _id; do
    [ -d "$S/packs/$_id" ] || find_ packs "policy names pack $_id and packs/$_id does not exist"
  done
  jq -r '(.hooks // [])[] | "\(.pack)\t\(.path)\t\(.sha256)"' "$POL" | while IFS="$(printf '\t')" read -r _pk _hp _hs; do
    # Under harbor-pack/, as contracts/hub.md says and hub.sh delivers them.
    if [ ! -f "$S/packs/$_pk/harbor-pack/$_hp" ]; then find_ packs "policy approves hook packs/$_pk/harbor-pack/$_hp and that file does not exist"
    elif [ "$(hub_sha256 < "$S/packs/$_pk/harbor-pack/$_hp")" != "$_hs" ]; then find_ packs "hook packs/$_pk/harbor-pack/$_hp is not the file policy approved (sha256 differs)"; fi
  done
fi
for _d in "$S"/packs/*/; do
  [ -d "$_d" ] || continue
  _id="${_d%/}"; _id="${_id##*/}"
  [ -f "$_d/extension.json" ] || { find_ packs "packs/$_id has no extension.json"; continue; }
  if ! sh "$HERE/hub-format.sh" manifest "$_d/extension.json" > "$T/man.out" 2>&1; then
    find_ packs "packs/$_id/extension.json does not match contracts/hub.md"; quote 6 < "$T/man.out" >> "$T/findings"; continue
  fi
  jq -r '.files[] | "\(.path)\t\(.sha256)"' "$_d/extension.json" | while IFS="$(printf '\t')" read -r _fp _fs; do
    if [ ! -f "$_d/harbor-pack/$_fp" ]; then find_ packs "packs/$_id lists $_fp and that file does not exist"
    elif [ "$(hub_sha256 < "$_d/harbor-pack/$_fp")" != "$_fs" ]; then find_ packs "packs/$_id/harbor-pack/$_fp differs from the sha256 its manifest lists"; fi
  done
done

n="$(grep -c '^hub-gate: \[' "$T/findings" || :)"
if [ "$n" -gt 0 ]; then
  # a finding and the tool lines under it are one FAIL; the logging contract wants a fix line after each
  _prev=""
  while IFS= read -r _l; do
    case "$_l" in
      "hub-gate: ["*) [ -z "$_prev" ] || { log_fail "$_prev"; log_nofix "docs/how-to/hub-admin.md, the check named in brackets"; }; _prev="${_l#hub-gate: }" ;;
      *) _prev="$_prev |$(printf '%s' "$_l" | sed 's/^ *//')" ;;
    esac
  done < "$T/findings"
  [ -z "$_prev" ] || { log_fail "$_prev"; log_nofix "docs/how-to/hub-admin.md, the check named in brackets"; }
  log_end || :
  exit 1
fi
log_ok "$(wc -l < "$T/files" | tr -d ' ') file(s) judged, no finding"
log_end || :
