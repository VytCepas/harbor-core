#!/usr/bin/env sh
# SEC-0 (the install standard, harbor#765) — hand-harden Claude Code's config dir.
#   sh deploy-harden.sh (--live | --dir PATH)           DRY RUN: exactly what would change, writes nothing
#   sh deploy-harden.sh --apply (--live | --dir PATH)   write settings.json (backup first) and re-pin both baselines
#
# Safe · idempotent · backup-first · cross-platform (macOS + WSL). Syntax verified
# against code.claude.com/docs/en/settings: deny overrides allow and applies in
# EVERY permission mode. This script touches nothing but settings.json, its backup
# and the two baselines B6 reads (.sec0-baseline.sha256, and .helm-floor-teeth where
# the floor already pinned one). Token rescope and the POSIX shell-injection guard
# are separate (see docs/how-to/harden-the-host.md and workstream B).
#
# Writes the way floor-deny.sh does: temp file, jq-validated, then moved into place
# (this used to be `jq . > settings.json`, a truncate in place), then the teeth and
# baseline re-pinned from the file just written, so B6 is not left drifted. Adding
# `.env` for the first time (harbor#816) adds a top-level key, which the baseline's
# `keys` field already tracks — the re-pin below covers it with no separate step.
# NO .harbor-manifest ROWS (install standard §3): settings.json and the baselines are state, not a
# file installed from the repo, and the baselines are B6's own store.
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/library-log.sh"
. "$HERE/deploy-install-lib.sh"
log_init sec0-harden
il_parse "$@"
il_target
DIR="$IL_TARGET"
S="$DIR/settings.json"

sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{print $1}'; }
if ! command -v jq >/dev/null 2>&1; then
  log_fail "jq is required, and is not on PATH"
  log_fix "$(pkg_hint jq)"
  log_end; exit 1
fi
if [ ! -f "$S" ]; then
  log_fail "no settings.json at $S (Claude Code not configured here?)"
  log_nofix "docs/how-to/harden-the-host.md — start Claude Code once in this config dir, then re-run"
  log_end; exit 1
fi

DENY='[
  "Read(~/.ssh/**)","Read(~/.config/gh/**)","Read(~/.aws/**)","Read(~/.config/gcloud/**)",
  "Read(~/.config/fly/**)","Read(~/.gnupg/**)","Read(~/.password-store/**)",
  "Read(~/.kube/**)","Read(~/.docker/config.json)","Read(~/.netrc)","Read(~/.npmrc)","Read(~/.pypirc)",
  "Read(//**/.env)","Read(//**/.env.*)","Read(//**/secrets/**)","Read(//**/*.pem)","Read(//**/id_rsa)","Read(//**/id_ed25519)",
  "Read(//**/id_dsa)","Read(//**/id_ecdsa)",
  "Read(//**/*.p12)","Read(//**/*.pfx)","Read(//**/*.jks)","Read(//**/*.keystore)",
  "Read(~/.local/share/gcalcli/**)"
]'
# harbor#1313 L6: docs/explanation/admission-baseline.md's key containers and all four id_* key names, wherever they live; ~/.ssh/**
# covers a key only under this HOME. Claude Code merges Read deny into the sandbox's denyRead, so no
# confined process reads these either.
[ -d /mnt/c/Users ] && DENY="$(printf '%s' "$DENY" | jq '. + ["Read(//mnt/c/Users/**)"]')"

# harbor#816 (2026-09-29, operator): keep Remote Control on — it needs usage metrics and feature
# flags, so those and DISABLE_TELEMETRY/DO_NOT_TRACK stay UNSET. Off: error reporting, /feedback,
# the feedback survey, and marketplace autoinstall. Forced to "1"; every other env key is untouched.
ENV_KEYS='["DISABLE_ERROR_REPORTING","DISABLE_FEEDBACK_COMMAND","CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY","CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL"]'

PROG='
  def dangerous:
    test("^Bash\\(\\s*(python3|awk|sed|perl|ruby|node|npx|bunx)( |\\*|\\))")
    or test("(bun add|uv pip install|npm install|npm ci|pip install|cargo add)");
  def permissive: . == "acceptEdits" or . == "bypassPermissions";
  .permissions //= {}
  | .permissions.allow = ((.permissions.allow // []) | map(select(dangerous | not)))
  | (if (.permissions.defaultMode // "" | permissive) then .permissions.defaultMode = "default" else . end)
  | (if (.defaultMode // "" | permissive) then .defaultMode = "default" else . end)
  | .permissions.disableBypassPermissionsMode = "disable"
  | del(.permissions.disableAutoMode)
  | .permissions.deny = (((.permissions.deny // []) + $DENY) | unique)
  | .env = ((.env // {}) + ($ENVK | map({(.): "1"}) | add))
'
NEW="$(jq --argjson DENY "$DENY" --argjson ENVK "$ENV_KEYS" "$PROG" "$S")"

if [ "$IL_APPLY" -eq 1 ]; then log_head "apply to $S"; else log_head "plan for $S (dry run: nothing is written)"; fi
_rm="$(jq -r '(.permissions.allow // [])[]' "$S" \
  | grep -E '^Bash\( *(python3|awk|sed|perl|ruby|node|npx|bunx)|bun add|uv pip install|npm install|npm ci|pip install|cargo add' || :)"
if [ -n "$_rm" ]; then
  while IFS= read -r _a; do log_note "allow to remove (it will prompt instead of auto-run): $_a"; done <<EOF
$_rm
EOF
else
  log_ok "no interpreter or arbitrary-install allow entries"
fi
log_note "defaultMode: $(jq -r '.permissions.defaultMode // .defaultMode // "unset"' "$S") → default when acceptEdits/bypassPermissions (auto is permitted — owner decision 2026-07-24)"
log_note "mode lock: disableBypassPermissionsMode = \"disable\" (un-overridable); disableAutoMode is removed if present"
_add="$(jq -rn --argjson old "$(jq '.permissions.deny // []' "$S")" --argjson add "$DENY" '$add - $old | .[]')"
if [ -n "$_add" ]; then
  while IFS= read -r _d; do log_note "deny to add (a secret read; deny overrides allow in every mode): $_d"; done <<EOF
$_add
EOF
else
  log_ok "every SEC-0 deny entry is present ($(printf '%s' "$DENY" | jq length))"
fi
_add_env="$(jq -rn --argjson old "$(jq '.env // {}' "$S")" --argjson want "$ENV_KEYS" '
  $want[] | select(($old[.] // "") != "1")
')"
if [ -n "$_add_env" ]; then
  while IFS= read -r _e; do log_note "env to add (harbor#816: keep Remote Control — usage metrics + feature flags; off: error reporting, /feedback, surveys, marketplace autoinstall): $_e=1"; done <<EOF
$_add_env
EOF
else
  log_ok "every SEC-0 env key is present ($(printf '%s' "$ENV_KEYS" | jq length))"
fi
if [ "$(jq -S . "$S")" = "$(printf '%s' "$NEW" | jq -S .)" ]; then log_ok "settings.json is already hardened: nothing would change"
else log_note "settings.json would change as listed above"; fi

if [ "$IL_APPLY" -eq 1 ]; then
  il_backup "$S" || { log_end; exit 1; }
  il_write_json "$NEW" "$S" || { log_end; exit 1; }
  jq -S '{perms:.permissions, plugins:(.enabledPlugins // {}), marketplaces:(.extraKnownMarketplaces // {}), keys:((keys) - ["hooks"])}' "$S" | sha >"$DIR/.sec0-baseline.sha256"
  log_ok "wrote $S; backup in $IL_BK"
  log_ok "re-pinned the baseline: $DIR/.sec0-baseline.sha256 (deny + mode locks + plugins + marketplaces)"
  # The teeth pin covers deny and the locks this run just changed; left stale, B6 blocks the next session.
  if [ -f "$DIR/.helm-floor-teeth" ]; then
    il_backup "$DIR/.helm-floor-teeth" || { log_end; exit 1; }
    jq -S '{deny:.permissions.deny, locks:{bypass:.permissions.disableBypassPermissionsMode, auto:.permissions.disableAutoMode}}' "$S" | sha >"$DIR/.helm-floor-teeth"
    log_ok "re-pinned the floor teeth: $DIR/.helm-floor-teeth"
  else
    log_skip "no .helm-floor-teeth here (the floor is not installed), so there are no teeth to re-pin"
  fi
fi

log_head "gh token (two tokens, two roles — corrected 2026-07-23, F2)"
_sc="$(gh auth status 2>&1 | grep -i 'Token scopes' | sed 's/^[[:space:]]*//' || :)"
if [ -n "$_sc" ]; then log_note "$_sc"; else log_note "gh reports no token scopes (not authenticated?)"; fi
log_note "keep the interactive daily-driver login as it is: it must stay able to author CI (.github/workflows pushes)"
log_note "never 'gh auth login --with-token' with a narrow token: it REPLACES the keyring credential for every repo"
log_note "for the work-log sync (G1/G2), mint a separate fine-grained token (Contents: read/write on the memory store's work-log repo only) and feed it via GH_TOKEN or its own git credential"
log_note "split web-fetching (deep-research) into a subagent with no git/gh/write tools"

[ "$IL_APPLY" -eq 1 ] || il_apply_next sec0
log_end; exit $?
