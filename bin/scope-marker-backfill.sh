#!/usr/bin/env sh
# H3 (harbor#4) — declare the detect-and-defer boundary across the installed base.
#
#   sh bin/scope-marker-backfill.sh            # DRY RUN — prints what it would write
#   sh bin/scope-marker-backfill.sh --apply    # writes
#   sh bin/scope-marker-backfill.sh --apply --include-dirty
#
# WHAT IT WRITES, AND WHAT IT DOES NOT. One line — `context: repo` at the top of
# a governed repo's `.agents/config.yaml` — and only where no `context:` key
# exists in ANY spelling the contract allows. It never rewrites an existing
# value: `context: ambient` is the owner's opt-out, and a back-fill that
# overwrote it would silently re-govern a repo whose owner opted out.
#
# WHY THE VALUE MATTERS WHEN ABSENCE ALREADY RESOLVES `repo`. It does not change
# the verdict — M21 says absence falls back to marker presence, so these repos
# already resolve `repo`. It changes whether the verdict is DECLARED or INFERRED.
# An inferred one is silent about the owner's intent, so the day someone wants a
# repo ambient there is no field to change, only a marker to delete.
#
# THE TARGET SET IS THE FLEET, NOT A DIRECTORY SCAN. `.agents/` present is the
# predicate M12 settled AGAINST, and the difference is not academic on this
# machine: `~/port/<repo>` carries a tracked, already-pushed `.agents/` tree and
# belongs to the employer's org, not the operator. It has no `config.yaml`, so
# the fleet does not list it and this tool never sees it. Widening the predicate
# would commit into someone else's repository.
#
# THE CWD TRAP. `fleet` reads `fleet.yaml` from the CURRENT
# directory and otherwise falls back to scanning `cwd.parent` with no excludes,
# so the same command returns 7 projects from the checkout and 0 from $HOME.
# This tool always runs the CLI from the orchestrator checkout for that reason;
# an empty fleet is treated as an error, never as "nothing to do".
set -eu

. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/library-log.sh"
log_init marker-backfill

APPLY=0
INCLUDE_DIRTY=0
for arg in "$@"; do
  case "$arg" in
    --apply)         APPLY=1 ;;
    --include-dirty) INCLUDE_DIRTY=1 ;;
    -h|--help)       sed -n '2,32p' "$0"; exit 0 ;;
    *) log_fail "unknown argument: $arg"; log_fix "sh $0 --help"; log_end || :; exit 2 ;;
  esac
done

PO_DIR="$(sh "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/scope-roots.sh" --get HARBOR_SCOPE_FLEET_CONTROLLER)" || exit 2   # harbor#966
CLI="$(command -v projects-orchestrator 2>/dev/null || true)"
[ -n "$CLI" ] || { log_fail "the fleet CLI is not installed (not on PATH)"
  log_nofix "contracts/marker.md (install fleet from its checkout, then rerun)"; log_end || :; exit 1; }
[ -d "$PO_DIR" ] || { log_fail "no orchestrator checkout at $PO_DIR"
  log_fix "git clone <the fleet repo> $PO_DIR  # or set HARBOR_SCOPE_FLEET_CONTROLLER"; log_end || :; exit 1; }
command -v jq >/dev/null 2>&1 || { log_fail "jq is required and is not on PATH"; log_fix "$(pkg_hint jq)"; log_end || :; exit 1; }

FLEET="$(cd "$PO_DIR" && "$CLI" snapshot --json 2>/dev/null || true)"
COUNT="$(printf '%s' "$FLEET" | jq 'length' 2>/dev/null || echo 0)"
if [ "$COUNT" -eq 0 ]; then
  log_fail "the fleet is EMPTY as read from $PO_DIR: refusing to report 'nothing to do' (an empty answer is a tooling failure, not a clean estate)"
  log_fix "cd $PO_DIR && $CLI snapshot --json  # check fleet.yaml and that the CLI runs there"
  log_end || :; exit 1
fi

# The contract's permissive spellings (contracts/marker.md): `context : repo`,
# `"context": repo`, `context: "repo"`. Anchored at column 0 — a `context:`
# indented under another block is a different key that shares a name. Matching
# the KEY, not a value, because any declared value means "already declared".
KEY_RE='^[[:space:]]*["'"'"']?context["'"'"']?[[:space:]]*:'
KEY_RE_TOP='^["'"'"']?context["'"'"']?[[:space:]]*:'

log_head "fleet: $COUNT governed repos (read from $PO_DIR)"
[ "$APPLY" -eq 1 ] || log_note "DRY RUN — nothing is written; to write: sh $0 --apply"

# The rows go through a file, not a pipe, so the loop runs in this shell and its counts reach the summary.
ROWS="$(mktemp "${TMPDIR:-/tmp}/marker-backfill.XXXXXX")"
trap 'rm -f "$ROWS"' EXIT INT TERM HUP
printf '%s' "$FLEET" | jq -r '.[] | "\(.descriptor.name)\t\(.descriptor.path)\t\(.descriptor.config_root)"' > "$ROWS"
while IFS="$(printf '\t')" read -r name path root; do
  cfg="$path/$root/config.yaml"
  if [ ! -f "$cfg" ] || [ -L "$cfg" ]; then
    log_warn "$name: no readable non-symlink config at $cfg"
    continue
  fi
  if /usr/bin/grep -Eq "$KEY_RE_TOP" "$cfg"; then
    log_ok "$name: already declares context: $(/usr/bin/grep -Em1 "$KEY_RE_TOP" "$cfg" | sed 's/.*:[[:space:]]*//' | tr -d '"'"'")"
    continue
  fi
  # An indented `context:` is a DIFFERENT key, but writing a top-level one
  # beside it produces a file with two keys a reader could confuse. Report and
  # leave it: this tool does not resolve ambiguity it did not create.
  if /usr/bin/grep -Eq "$KEY_RE" "$cfg"; then
    log_warn "$name: has an INDENTED context: key; resolve by hand"
    log_fix "vi $cfg  # make the key top-level, or remove it"
    continue
  fi
  dirty=""
  if git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
    [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ] && dirty="dirty"
  fi
  if [ -n "$dirty" ] && [ "$INCLUDE_DIRTY" -eq 0 ]; then
    log_warn "$name: WOULD WRITE, but the tree is dirty"
    log_fix "git -C $path status --short  # commit or stash, then rerun (or pass --include-dirty)"
    continue
  fi
  # This tool must never be able to rewrite the LIVE config. It is not a
  # settings.json mutator and carries no `--live` gate (lint D2 exempts it for
  # that reason), so the refusal below is what makes the exemption true rather
  # than a claim: resolved with `cd -P`, because `~/.claude/../.claude` and a
  # symlinked route name the same directory a string compare would miss.
  _cfgdir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  _cfgdir_phys="$(CDPATH= cd -P -- "$_cfgdir" 2>/dev/null && pwd -P || printf '%s' "$_cfgdir")"
  _target_phys="$(CDPATH= cd -P -- "$(dirname "$cfg")" 2>/dev/null && pwd -P || printf '%s' "$path")"
  case "$_target_phys/" in
    "$_cfgdir_phys"/*)
      log_warn "$name: REFUSED — resolves inside the config dir ($_cfgdir_phys)"
      continue ;;
  esac
  if [ "$APPLY" -eq 0 ]; then
    log_note "$name: would prepend \"context: repo\" to ${cfg#"$HOME"/}"
    continue
  fi
  # PREPENDING IS NOT ALWAYS THE TOP (PR #96 review). A descriptor may open with
  # `%YAML`/`%TAG` directives and/or a `---` document-start marker. Writing above
  # those makes `context: repo` a SEPARATE first document — a single-document
  # loader then reads `{context: repo}` and loses the whole descriptor — or puts
  # a key illegally before a directive. So find the document start and insert
  # after it. Comments and blank lines may precede the marker and are skipped;
  # the first line that is real content ends the search, because a `---` after
  # content is a second document and not this one's header.
  _ins=0; _n=0
  while IFS= read -r _l; do
    _n=$((_n + 1))
    case "$_l" in
      ---|"--- "*|"---	"*) _ins=$_n; break ;;
      "%"*|"#"*|"") continue ;;
      *) break ;;
    esac
  done < "$cfg"
  tmp="$cfg.helm-backfill.$$"
  if [ "$_ins" -gt 0 ]; then
    { head -n "$_ins" "$cfg"; printf 'context: repo\n'; tail -n "+$((_ins + 1))" "$cfg"; } > "$tmp"
  else
    { printf 'context: repo\n'; cat "$cfg"; } > "$tmp"
  fi
  mv "$tmp" "$cfg"
  log_ok "$name: wrote context: repo"
done < "$ROWS"

log_note "yard specifically: its .claude/config.yaml is a byte-hashed committed mirror, so a splice there needs 'just sync-claude' in the same change or tests/contracts/test_claude_dir_sync.py goes red"
log_end; exit $?
