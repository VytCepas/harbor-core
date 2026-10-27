#!/usr/bin/env sh
# scope.sh (harbor#966, harbor#1149) - `harbor scope install`: the PORT_ROOT skeleton and an empty
# private layer, idempotent. CONTRACTS/private-layer.md is the shape of what it creates.
#
#   harbor scope install [--dry-run] [--seed-from-projects] [--private-only]
#
#   --dry-run             print what would be created and kept, write nothing
#   --seed-from-projects  also write repos.tsv rows from the private layer's inject.d/box/projects.tsv and the git
#                         checkouts already under PORT_ROOT; only ids not yet in repos.tsv are added
#   --private-only        leave the PORT_ROOT skeleton and the config dir alone and create only harbor-private/
#
# The one file it writes outside PORT_ROOT is the Claude Code config dir's settings.json, as an empty {}, and only when
# it is absent (harbor#457): deploy's preflight refuses a box without one, and a machine where Claude Code never ran has
# none. A present file, a symlink, or a CLAUDE_CONFIG_DIR naming another dir (deploy refuses that too) is left alone.
# Never overwrites a file and never deletes. PORT_ROOT and HARBOR_SCOPE_PRIVATE are read as roots.sh reads them.
set -eu

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
ROOT="${HARBOR_ROOT:-$(CDPATH= cd -- "$SRC/.." && pwd)}"
. "$SRC/log-lib.sh"
log_init scope

DRY=0; SEED=0; PONLY=0
# `harbor scope` hands its words over whole; install is the only scope verb built (D-84).
case "${1:-}" in install) shift ;; -h|--help|help) ;; '') echo "harbor scope: needs a verb (only: install); try --help" >&2; exit 2 ;; *) echo "harbor scope: unknown verb '$1' (only: install)" >&2; exit 2 ;; esac
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --seed-from-projects) SEED=1 ;;
    --private-only) PONLY=1 ;;
    -h|--help|help|'') sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "harbor scope install: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
  shift
done

# roots.sh is the one resolver of both roots (PORT_ROOT, HARBOR_SCOPE_PRIVATE).
PORT="$(sh "$SRC/roots.sh" --port-root)" || { log_fail "no workspace root"; log_fix "export PORT_ROOT=<dir>"; log_end || :; exit 1; }
PRIV="$(sh "$SRC/roots.sh" --private)" || { log_fail "no private layer root"; log_fix "export HARBOR_SCOPE_PRIVATE=<dir>"; log_end || :; exit 1; }

mkdir_p() { # <dir>
  if [ -d "$1" ]; then log_note "kept     $1/"; return 0; fi
  if [ "$DRY" = 1 ]; then log_ok "would create $1/"; return 0; fi
  mkdir -p "$1" && log_ok "created  $1/"
}
put() { # <file> <content> - writes only when the file is absent
  if [ -L "$1" ]; then log_warn "refusing to write through the symlink $1"; return 0; fi
  if [ -e "$1" ]; then log_note "kept     $1"; return 0; fi
  if [ "$DRY" = 1 ]; then log_ok "would create $1"; return 0; fi
  printf '%s' "$2" > "$1" && log_ok "created  $1"
}

TOML='# harbor.toml - this machine'"'"'s Harbor settings. Flat TOML: key = "value" or a one-line array, no tables.
# Read by `sh bin/roots.sh --conf <key>`; CONTRACTS/private-layer.md lists every key.
#
# packs = []                        # workload repos whose harbor-pack/ folder is installed box-wide
components = ["core"]             # core, plus any of: yard, fleet, prod-guard, collector (deploy.sh reads it)
# channel = "main"                  # main | stable
# deliverables_dir = "~/Deliverables"
# worklog_repo = ""                 # the private repo the work log pushes to
'
REPOS_HEAD='id	path	kind	remote
'
REGISTER='# Access register

Every identity an agent may use: an account, role, app, mailbox or token, one `## <id>` entry each. The format is
CONTRACTS/access-register.md in the Harbor checkout. An entry holds a `secret:` reference, never a value, and
`bin/secret` refuses a ref no entry names. Empty until `harbor access add` records one.
'
PERSONAL='# Personal operating rules

Imported by the installed CLAUDE.md. Time zone, ticket tool, habits: yours alone, never core.
'

for d in "$PORT" "$PORT/.worktrees" "$PORT/.scratch" "$PORT/history" "$PRIV" "$PRIV/access" "$PRIV/jobs"; do
  case "$d" in "$PRIV"*) ;; *) [ "$PONLY" = 0 ] || continue ;; esac
  mkdir_p "$d"
done
put "$PRIV/harbor.toml" "$TOML"
put "$PRIV/repos.tsv" "$REPOS_HEAD"
put "$PRIV/checks.md" ""
put "$PRIV/access/register.md" "$REGISTER"
put "$PRIV/CLAUDE.personal.md" "$PERSONAL"

# The config dir's settings.json (harbor#457). Deploy installs into HOME/.claude and refuses a CLAUDE_CONFIG_DIR naming
# another dir, so that case is not seeded. noclobber makes the create exclusive: a file that appears between the test
# and the write is never overwritten.
phys() { CDPATH='' cd -P -- "$1" 2>/dev/null && pwd -P || printf '%s' "${1%/}"; }
seed_settings() {
  # UNVERIFIED (harbor#457, operator's call): that a later first `claude` start keeps a pre-seeded {}. To drop the seed, delete the call below.
  [ -n "${HOME:-}" ] || { log_warn "HOME is unset, so no settings.json was seeded"; return 0; }
  LIVE_DIR="$HOME/.claude"
  __sf="$LIVE_DIR/settings.json"
  if [ -n "${CLAUDE_CONFIG_DIR:-}" ] && [ "$(phys "$CLAUDE_CONFIG_DIR")" != "$(phys "$LIVE_DIR")" ]; then
    log_warn "CLAUDE_CONFIG_DIR is $CLAUDE_CONFIG_DIR, and deploy installs into $LIVE_DIR only: no settings.json was seeded"
    return 0
  fi
  if [ -e "$__sf" ]; then log_note "kept     $__sf"; return 0; fi
  if [ -L "$__sf" ]; then log_warn "refusing to write through the dangling symlink $__sf"; return 0; fi
  if [ "$DRY" = 1 ]; then log_ok "would create $__sf (an empty {}: deploy's preflight needs the file)"; return 0; fi
  if mkdir -p "$LIVE_DIR" 2>/dev/null && ( set -C; printf '{}\n' > "$__sf" ) 2>/dev/null; then
    log_ok "created  $__sf (an empty {}: deploy's preflight needs the file)"
  elif [ -e "$__sf" ]; then log_note "kept     $__sf"
  else
    log_fail "could not create $__sf"
    log_nofix "the error from: mkdir -p '$LIVE_DIR' && : > '$__sf'"
  fi
}
[ "$PONLY" = 1 ] || seed_settings

# kind by the checkout's own `repo-kind:` line in .agents/config.yaml, when it names a kind in
# standards/naming/repo-kinds.tsv; else the three platform repos have one each, everything else is a
# workload. A repo's kind is never listed here (harbor#1273): the registry row is the operator's to correct.
kind_of() { # <id> <checkout>
  __k="$(sed -n 's/^repo-kind:[[:space:]]*\([a-z-]*\).*/\1/p' "$2/.agents/config.yaml" 2>/dev/null | head -1)"
  if [ -n "$__k" ] && awk -F'\t' -v k="$__k" '$1 == k { f = 1 } END { exit !f }' "$ROOT/standards/naming/repo-kinds.tsv" 2>/dev/null; then
    echo "$__k"; return 0
  fi
  case "$1" in
    harbor) echo control-plane ;; project-init) echo scaffolder ;;
    projects-orchestrator) echo fleet-controller ;;
    *) echo workload ;;
  esac
}
# A remote URL with any user:token@ part removed; a checkout with none (or a local path) gets "-".
remote_of() { # <dir>
  __u="$(git -C "$1" remote get-url origin 2>/dev/null || :)"
  case "$__u" in
    https://*|http://*|ssh://*|git@*) printf '%s' "$__u" | sed -E 's#^(https?|ssh)://[^/@]*@#\1://#' ;;
    *) printf '%s' '-' ;;
  esac
}

if [ "$SEED" = 1 ]; then
  REG="$PRIV/repos.tsv"
  # No temp file: --dry-run writes nothing anywhere. Candidates are lines in a variable.
  CAND=""
  PROJ="${HARBOR_SCOPE_PROJECTS_TSV:-$(sh "$SRC/roots.sh" --projects 2>/dev/null || :)}"
  if [ -f "$PROJ" ]; then
    # Rows name ~/port/<dir>; anything else is not under PORT_ROOT and is left for the operator.
    while IFS="$(printf '\t')" read -r __n __p __c; do
      case "$__p" in
        '~/port/'*) CAND="$CAND$__n	${__p#'~/port/'}
" ;;
        *) log_warn "projects.tsv row '$__n' has path $__p, not under ~/port: skipped" ;;
      esac
    done <<EOF
$(grep -vE '^[[:space:]]*(#|$)' "$PROJ" || :)
EOF
  fi
  # Checkouts already on disk: a .git DIRECTORY (a worktree has a .git file) and a real remote.
  for __d in "$PORT"/*; do
    [ -d "$__d/.git" ] || continue
    __b="${__d##*/}"
    case "$__b" in *-wt-*) continue ;; esac
    [ "$(remote_of "$__d")" != "-" ] || continue
    CAND="$CAND$__b	$__b
"
  done
  # The registry as it will be: what is there, plus each accepted row. Every candidate is judged by
  # roots.sh --registry-check, the reader's own rules, before it is added; a registry already invalid
  # is not appended to.
  if [ -f "$REG" ]; then BODY="$(cat "$REG")"; else BODY="$(printf 'id\tpath\tkind\tremote')"; fi
  __e="$(sh "$SRC/roots.sh" --registry-check - 2>&1 >/dev/null <<EOF
$BODY
EOF
)" || {
    log_fail "$REG is already invalid, so nothing is appended: $(printf '%s' "$__e" | tail -1)"
    log_fix "sh $SRC/roots.sh --registry-check"; log_end || :; exit 1; }
  ADDED=0; REJ=0; NEW=""
  while IFS="$(printf '\t')" read -r __id __rel; do
    [ -n "$__id" ] || continue
    __rel="${__rel%/}"
    __row="$(printf '%s\t%s\t%s\t%s' "$__id" "$__rel" "$(kind_of "$__id" "$PORT/$__rel")" "$(remote_of "$PORT/$__rel")")"
    __err="$(sh "$SRC/roots.sh" --registry-check - 2>&1 >/dev/null <<EOF
$BODY
$__row
EOF
)" && __ok=1 || __ok=0
    if [ "$__ok" = 0 ]; then
      case "$__err" in
        *duplicate*) log_note "seed: '$__id' already registered (id or path): skipped" ;;
        *) log_fail "seed row '$__id' would make an invalid registry: $(printf '%s' "$__err" | tail -1 | sed 's/^roots: [^ ]* //')"
           log_fix "fix the source row or checkout name, then re-run"; REJ=$((REJ + 1)) ;;
      esac
      continue
    fi
    BODY="$BODY
$__row"
    NEW="$NEW$__row
"
    ADDED=$((ADDED + 1))
    if [ "$DRY" = 1 ]; then log_ok "would add row: $__row"; else log_ok "added row: $__row"; fi
  done <<EOF
$CAND
EOF
  if [ "$DRY" = 0 ] && [ -n "$NEW" ]; then
    # A file without a final newline would merge its last row with the first appended one.
    if [ -s "$REG" ] && [ -n "$(tail -c1 "$REG")" ]; then printf '\n' >> "$REG"; fi
    printf '%s' "$NEW" >> "$REG"
  fi
  log_note "seed: $ADDED row(s) $( [ "$DRY" = 1 ] && echo 'would be ' )added to $REG"
fi

log_end
