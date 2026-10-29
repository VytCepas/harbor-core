#!/usr/bin/env sh
# lint-secrets.sh (harbor#1205) - the ratchet on credential reads that bypass bin/secret.
#
#   sh lint-secrets.sh --count    the number of hits (occurrences, not files)
#   sh lint-secrets.sh --list     each one as file:line TAB class
#   sh lint-secrets.sh --check    red if the count is above contracts/lint-secrets-baseline.txt;
#                                    green but says to lower the baseline when it is below
#
# A credential reaches code through bin/secret and nowhere else (contracts/access-register.md). Four classes:
#   literal  a value shaped like a credential (contracts/credential-patterns.tsv), anywhere in the tree
#   keychain a direct `security <find|add|delete|dump>-...` or `secret-tool <lookup|store|clear|search>` call in
#            command position; a file whose first 40 lines carry `# secret-seam: <why>` is declared and skipped
#   env      a read of a variable named *TOKEN, *SECRET, *PASSWORD or *API_KEY (code files, not comments)
#   appid    an app's identity written into code (code files, not comments): a GitHub App id, installation id or client id,
#            or a Google OAuth client id. An identity is a register entry in the private layer, never a literal in core
# A line carrying `secret-seam:` is declared, whichever class. Scope: every tracked file plus untracked ones git does
# not ignore, minus tests, fixtures, evals, docs, worklog, vendor, the floor (guard-*, floor-*, docs/explanation/admission-baseline.md), bin/secret
# (the seam), this file and the pattern table. The baseline only goes down: a new read goes through `secret run`.
set -eu

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
ROOT="${HARBOR_ROOT:-$(CDPATH= cd -- "$SRC/.." && pwd)}"
BASE="${SECRETS_BASELINE:-$ROOT/contracts/lint-secrets-baseline.txt}"
PATTERNS="${SECRETS_PATTERNS:-$ROOT/contracts/credential-patterns.tsv}"
. "$SRC/library-log.sh"
log_init lint-secrets
LOG_FD=2

# Command position for a keychain CLI, as tests/access/secret/seam.test.sh derives it.
CALL='(^|[;&|(`{!]|[$][(]|(^|[[:space:]])(then|else|do|if))[[:space:]]*(security[[:space:]]+(find|add|delete|dump)-[a-z-]+|secret-tool[[:space:]]+(lookup|store|clear|search))([[:space:]]|$)'
ENVRE='[$][{]?[A-Z][A-Z0-9_]*(TOKEN|SECRET|PASSWORD|API_KEY|APIKEY)([^A-Za-z0-9_]|$)'
# An app id key followed by a number (app_id: 123456, APP_ID=123456, --app-id 123456, "installationId": 123456), a JWT
# issuer that is a number (a GitHub App id), an installations/<n> path, a GitHub App client id, a Google OAuth client id.
Q="[\"'\\\\]"   # a quote or a backslash: a key or a value may sit in quotes, escaped or not
APPRE="(((app|client|installation)[_-]?(id|Id|ID)|APP_ID|CLIENT_ID|INSTALLATION_ID)$Q*([[:space:]]*[:=][[:space:]]*|[[:space:]]+)$Q*[0-9]{5,}|${Q}iss$Q*[[:space:]]*:[[:space:]]*$Q*[0-9]{5,}|installations/[0-9]{5,}|Iv1[.][0-9a-f]{16}|Iv23[A-Za-z0-9]{16}|[0-9]{6,}-[a-z0-9]{32}[.]apps[.]googleusercontent[.]com)"

# git grep, not grep: grep here is ugrep and skips gitignored files. --untracked adds a new unstaged file.
gg() { # <ERE> [-f file]
  git -C "$ROOT" grep -I --untracked -n -E "$@" -- . \
    ':!tests/**' ':!fixtures/**' ':!evals/**' ':!**/tests/**' ':!**/fixtures/**' ':!docs/**' ':!worklog/**' ':!vendor/**' \
    ':!skills/test-strength/targets/**' ':!skills/*/EVALS/**' ':!bin/guard-*' ':!bin/floor-*' ':!docs/explanation/admission-baseline.md' ':!bin/secret' ':!bin/lint-secrets.sh' \
    ':!contracts/credential-patterns.tsv' ':!contracts/lint-secrets-baseline.txt' 2>/dev/null || :
}
declared() { # <file> - a `# secret-seam:` header in the first 40 lines
  head -40 "$ROOT/$1" 2>/dev/null | /usr/bin/grep -q '^# *secret-seam:'
}
hits() { # file:line TAB class
  # literal: the pattern table, every line
  if [ -f "$PATTERNS" ]; then
    __pf="$(mktemp "${TMPDIR:-/tmp}/lint-secrets.XXXXXX")"
    awk -F'\t' '/^[[:space:]]*(#|$)/ { next } $1 == "id" { next } NF >= 2 { print $2 }' "$PATTERNS" > "$__pf"
    if [ -s "$__pf" ]; then
      git -C "$ROOT" grep -I --untracked -n -E -f "$__pf" -- . \
        ':!tests/**' ':!fixtures/**' ':!evals/**' ':!**/tests/**' ':!**/fixtures/**' ':!docs/**' ':!worklog/**' ':!vendor/**' \
        ':!skills/test-strength/targets/**' ':!skills/*/EVALS/**' ':!bin/guard-*' ':!bin/floor-*' ':!docs/explanation/admission-baseline.md' ':!bin/secret' ':!bin/lint-secrets.sh' \
        ':!contracts/credential-patterns.tsv' ':!contracts/lint-secrets-baseline.txt' 2>/dev/null |
        awk -F: '$0 !~ /secret-seam:/ { printf "%s:%s\tliteral\n", $1, $2 }' || :
    fi
    rm -f "$__pf"
  fi
  # keychain, env and appid: code lines only (a comment is prose), declared files and lines skipped
  { gg "$CALL" | awk '{ print "keychain\t" $0 }'; gg "$ENVRE" | awk '{ print "env\t" $0 }'; gg "$APPRE" | awk '{ print "appid\t" $0 }'; } |
    awk -F'\t' '{ cls = $1; rest = substr($0, length($1) + 2)
                   i = index(rest, ":"); file = substr(rest, 1, i - 1); r2 = substr(rest, i + 1)
                   j = index(r2, ":"); line = substr(r2, 1, j - 1); body = substr(r2, j + 1)
                   if (body ~ /^[[:space:]]*#/ || body ~ /secret-seam:/) next
                   printf "%s:%s\t%s\n", file, line, cls }' |
    while IFS="$(printf '\t')" read -r loc cls; do
      __f="${loc%%:*}"
      case "$__f" in *.md) continue ;; esac
      [ "$cls" = keychain ] && declared "$__f" && continue
      printf '%s\t%s\n' "$loc" "$cls"
    done
}
all_hits() { hits | sort -u; }

case "${1:-}" in
  --count) git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || { echo "lint-secrets: $ROOT is not a git checkout" >&2; exit 2; }
           all_hits | wc -l | tr -d ' ' ;;
  --list)  all_hits ;;
  --check)
    git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || { log_fail "$ROOT is not a git checkout, nothing was inspected"; log_nofix "bin/lint-secrets.sh"; log_end || :; exit 2; }
    WANT="$(grep -vE '^[[:space:]]*(#|$)' "$BASE" 2>/dev/null | head -1 | tr -d ' ')" || WANT=""
    case "$WANT" in ''|*[!0-9]*) log_fail "no numeric baseline in ${BASE#$ROOT/}"; log_fix "write the current count (sh bin/lint-secrets.sh --count) into it"; log_end || :; exit 1 ;; esac
    LIST="$(all_hits)"
    GOT="$(printf '%s' "$LIST" | grep -c . || :)"
    if [ "$GOT" -gt "$WANT" ]; then
      log_fail "$GOT credential read(s) outside bin/secret in the tree, baseline is $WANT"
      log_fix "read a credential through 'secret run <ref> VAR -- <cmd>'; the ref, or an app's id, is a register entry ('harbor access add', contracts/access-register.md)"
      # The delta, not the census: files this branch touched that hold a hit.
      __chg="$(git -C "$ROOT" diff --name-only "$(git -C "$ROOT" merge-base HEAD origin/main 2>/dev/null || echo HEAD)" 2>/dev/null || :)"
      printf '%s\n' "$LIST" | cut -f1 | cut -d: -f1 | sort -u | while IFS= read -r f; do
        case "
$__chg
" in *"
$f
"*) log_note "changed and holds a hit: $f" ;; esac
      done
    elif [ "$GOT" -lt "$WANT" ]; then
      log_ok "$GOT credential read(s), under the baseline of $WANT"
      log_note "lower ${BASE#$ROOT/} to $GOT so the gain is kept"
    else
      log_ok "$GOT credential read(s) outside bin/secret, equal to the baseline"
    fi
    log_end ;;
  -h|--help|help|'') sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) echo "lint-secrets: unknown argument '$1'" >&2; exit 2 ;;
esac
