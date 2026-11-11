#!/usr/bin/env sh
# hub.sh (harbor#1278; `harbor hub`) — the member's and the admin's door to the hub. Format: contracts/hub.md.
#   harbor hub init                          member: what this laptop still needs, the state dir, a first sync
#   harbor hub sync [--no-fetch] [--live | --dir PATH]    fetch the policy, install the hub packs it pins, deliver its hooks, report the pin
#   harbor hub status                        role, hub, policy serial and mode, last sync, pin against the installed core, packs
#   harbor hub sign <policy.json> --key <private-key> [--signers FILE]   admin: validate, then ssh-keygen -Y sign (ns harbor-hub)
#   harbor hub check [DIR] [--signers FILE]  admin or the hub's gate: policy, signature, packs, hooks and the pin agree
#   harbor hub pin-check <contract> [DIR]    refuse a pin while an extension's harbor_version does not accept that contract
#   harbor hub leave [--apply] [--live | --dir PATH]   after a VERIFIED revocation: drop hub packs and policy; names IT's root step
#   harbor hub project register <name> [--covers TEXT] [--kind K]   register a checkout with `harbor repo adopt --core-only`
#   harbor hub support list|accept <id>|connect <id>   admin: answer a member's request for remote help (hub-support.sh)
#   harbor hub tools create <login>|admit <tool>   admin: a colleague's private tools repo, and a proposed skill into a hub pack (hub-tools.sh)
#   harbor hub id                            member: this laptop account's random id for Harbor's logs, read only, and whether the
#                                            notice receipt is recorded. Give the id to ask for your data or its deletion (legal/dpia.md R12)
# Exit 0 done, 1 refused or a check is red, 2 usage, 3 the hub could not be reached (the last good policy stays).
set -eu
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH= cd -- "$HERE" && pwd -P)"
. "$HERE/library-log.sh"
. "$HERE/library-hub.sh"
. "$HERE/library-pack-version.sh"
log_init hub
TAB="$(printf '\t')"
STATE="$(hub_state_dir)"

usage() { awk 'NR < 2 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$HERE/hub.sh"; }
die() { log_fail "$1"; log_fix "${2:-sh $HERE/hub.sh --help}"; log_end || :; exit "${3:-2}"; }
hs() { sh "$HERE/hub-sync.sh" "$@"; }
ev() { if [ -f "$HERE/hub-events.sh" ]; then sh "$HERE/hub-events.sh" record "$@" > /dev/null 2>&1 || :; fi; }
is_member() { hub_is_member; }

# ── target: the config dir the hub packs land in, spelled as every installer does ─────────────────────────
TGT_KIND=live; TGT_DIR=''; TGT_SET=0; APPLY=0; QUIET=0; NOFETCH=0; REST=''
tgt_parse() {
  REST=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --live) TGT_KIND=live; TGT_SET=1 ;;
      --dir) [ $# -ge 2 ] || die "--dir needs a path"; TGT_KIND=dir; TGT_DIR="$2"; TGT_SET=1; shift ;;
      --apply) APPLY=1 ;;
      --quiet) QUIET=1 ;;
      --no-fetch) NOFETCH=1 ;;
      *) REST="${REST:+$REST }$1" ;;
    esac
    shift
  done
}
cfgdir() { if [ "$TGT_KIND" = dir ]; then printf '%s' "$TGT_DIR"; else printf '%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; fi; }
# A write into a config dir names its target: the live one only with an explicit --live, as every installer does.
need_target() { [ "$TGT_SET" -eq 1 ] || die "refusing to write the config dir without an explicit --live (or --dir PATH)" "harbor hub $1 --live"; }
pk() { if [ "$TGT_KIND" = dir ]; then sh "$HERE/pack.sh" "$@" --dir "$TGT_DIR"; else sh "$HERE/pack.sh" "$@" --live; fi; }

# The packs installed from the hub: their manifests carry `# source hub`.
hub_manifests() { for _m in "$(cfgdir)"/.harbor-packs/hub-*.tsv; do
  [ -f "$_m" ] && awk -F'\t' '$1 == "# source" && $2 == "hub" { f = 1 } END { exit !f }' "$_m" && printf '%s\n' "$_m"
done; return 0; }
manifest_commit() { awk -F'\t' '$1 == "# commit" { print $2; exit }' "$1"; }

# ── the pin: read at sync, reported in status. Acting on it is IT's until the updater exists (F26, R4) ────
installed_commit() { awk '$1 == "floor-install" { print $2; exit }' "$(cfgdir)/.helm-install-stamp" 2>/dev/null || :; }
installed_contract() { sed -n 's/^CONTRACT_VERSION=\([0-9][0-9]*\)$/\1/p' "$HERE/harbor" 2>/dev/null | head -n 1; }
pin_report() { # <policy>
  _pc="$(jq -r '.core.commit' "$1")"; _pk="$(jq -r '.core.contract' "$1")"
  _ic="$(installed_commit)"; _ik="$(installed_contract)"; _bad=''
  [ -z "$_ic" ] || [ "$_ic" = "$_pc" ] || _bad="core $(printf %s "$_ic" | cut -c1-12) is installed, the policy pins $(printf %s "$_pc" | cut -c1-12)"
  [ -z "$_ik" ] || [ "$_ik" = "$_pk" ] || _bad="${_bad:+$_bad; }contract $_ik is installed, the policy pins $_pk"
  if [ -n "$_bad" ]; then
    printf 'pin: MISMATCH - %s. Acting on it stays with IT until the updater exists.\n' "$_bad"
  else
    printf 'pin: ok - core %s, contract %s%s\n' "$(printf %s "$_pc" | cut -c1-12)" "$_pk" "$([ -n "$_ic" ] || echo ' (installed commit unknown: no install stamp)')"
  fi
}

# ── hub packs and hooks ───────────────────────────────────────────────────────────────────────────────────
# A landed pack is the pin's, not the manifest's (harbor#1278): every file the manifest names is there, and each one extension.json lists at the pinned
# commit has that sha256. A file a member edited or deleted fails it, and sync installs the pack again; a file the member added beside them is not looked at.
pack_intact() { # <id> <commit> <manifest>
  _hdir="$(sh "$HERE/scope-roots.sh" --hub 2>/dev/null)" || return 1
  git -C "$_hdir" show "$2:packs/$1/extension.json" 2>/dev/null | jq -r '.files[]? | [.path, .sha256] | @tsv' > "$STATE/ext.files" 2>/dev/null || return 1
  awk -F'\t' 'NR == FNR { h[$1] = $2; next } $1 == "F" { print $2 "\t" (($2 in h) ? h[$2] : "") }' "$STATE/ext.files" "$3" > "$STATE/ext.rows"
  while IFS="$TAB" read -r _rp _rh; do
    [ -f "$(cfgdir)/$_rp" ] || return 1
    [ -z "$_rh" ] || [ "$(hub_sha256 < "$(cfgdir)/$_rp")" = "$_rh" ] || return 1
  done < "$STATE/ext.rows"
  return 0
}
sync_packs() { # <policy>: install what the policy pins, remove what it no longer lists
  _fails=0
  jq -r '.packs[]? | [.id, .commit] | @tsv' "$1" > "$STATE/packs.want"
  while IFS="$TAB" read -r _id _co; do
    [ -n "$_id" ] || continue
    _mf="$(cfgdir)/.harbor-packs/hub-$_id.tsv"
    if [ -f "$_mf" ] && [ "$(manifest_commit "$_mf")" = "$_co" ]; then
      pack_intact "$_id" "$_co" "$_mf" && continue
      log_warn "hub pack $_id: a file landed on this laptop is not the pinned one; installing it again"
    fi
    if pk install "$_id" --hub --apply > "$STATE/pack.out" 2>&1; then log_ok "hub pack $_id at $(printf %s "$_co" | cut -c1-12)"
    else
      _fails=$((_fails + 1)); log_fail "hub pack $_id was not installed: $(grep -m1 'skipped' "$STATE/pack.out" | cut -c1-200)"
      log_fix "the admin repairs the pack and its pin, then harbor hub sync"; ev check check=hub-pack outcome=failed
    fi
  done < "$STATE/packs.want"
  for _m in $(hub_manifests); do
    _hid="${_m##*/hub-}"; _hid="${_hid%.tsv}"
    awk -F'\t' -v i="$_hid" '$1 == i { f = 1 } END { exit !f }' "$STATE/packs.want" && continue
    if pk remove "hub-$_hid" --apply > "$STATE/pack.out" 2>&1; then log_ok "removed hub pack $_hid: the policy no longer lists it"
    else _fails=$((_fails + 1)); log_fail "could not remove hub pack $_hid"; log_fix "harbor pack remove hub-$_hid --apply --live"; fi
  done
  [ "$_fails" -eq 0 ]
}

# Hooks go to HUB_STATE/hooks/<pack>/<path>, which the agent cannot write; the dispatcher asks `hub-sync.sh hook` and runs a hook
# only if its bytes still match the sha256 in the signed policy. A mismatch at delivery is dropped, never run (R21, #1285).
sync_hooks() { # <policy>
  _hf=0; _hd="$STATE/hooks"; mkdir -p "$_hd"
  jq -r '.hooks[]? | [.pack, .path, .sha256] | @tsv' "$1" > "$STATE/hooks.want"
  : > "$STATE/hooks.keep"
  while IFS="$TAB" read -r _hp _hpath _hsha; do
    [ -n "$_hp" ] || continue
    _co="$(jq -r --arg p "$_hp" '[.packs[]? | select(.id == $p) | .commit][0] // empty' "$1")"
    _hdir="$(sh "$HERE/scope-roots.sh" --hub 2>/dev/null)" || _hdir=''
    _tmp="$_hd/.new.$$"
    if [ -n "$_co" ] && [ -n "$_hdir" ] && git -C "$_hdir" show "$_co:packs/$_hp/harbor-pack/$_hpath" > "$_tmp" 2>/dev/null &&
       [ "$(hub_sha256 < "$_tmp")" = "$_hsha" ]; then
      mkdir -p "$_hd/$_hp/${_hpath%/*}"; chmod 755 "$_tmp"; mv -f "$_tmp" "$_hd/$_hp/$_hpath"
      printf '%s\n' "$_hp/$_hpath" >> "$STATE/hooks.keep"; log_ok "hub hook $_hp/$_hpath delivered"
    else
      rm -f "$_tmp"; _hf=$((_hf + 1))
      log_fail "hub hook $_hp/$_hpath does not match the signed hash, or its pack is not pinned: not delivered"
      log_fix "the admin pins the pack and signs the hash of the committed file"; ev check check=hub-hook outcome=failed
    fi
  done < "$STATE/hooks.want"
  # A delivered file the policy no longer lists goes.
  ( cd "$_hd" && find . -type f ! -name '.new.*' | sed 's|^\./||' ) | while IFS= read -r _f; do
    grep -qxF "$_f" "$STATE/hooks.keep" || rm -f "$_hd/$_f"
  done
  [ "$_hf" -eq 0 ]
}

# Hub context rules: a pack's context-rules/user/<f>.md notes, delivered to HUB_STATE/rules/<pack>/<f>.md, the folder the member engine reads (injection-rule.sh --member-root).
# Live means: the pack is in the signed policy, its file is listed in the manifest extension.json at the pinned commit, the bytes carry that sha256, and the file is a pure
# note (no run:, no spoke:). Anything else is not delivered, and a delivered file the policy no longer vouches for goes. HUB_STATE is protected by the sandbox and the Edit deny
# rows (member_protected), not by ownership: the worst a hand-written note there does is fire as a note, since the engine never loads a rule with run: or spoke:.
sync_rules() { # <policy>
  _rf=0; _rd="$STATE/rules"; mkdir -p "$_rd"; : > "$STATE/rules.keep"
  jq -r '.packs[]? | [.id, .commit] | @tsv' "$1" > "$STATE/rules.want"
  _hdir="$(sh "$HERE/scope-roots.sh" --hub 2>/dev/null)" || _hdir=''
  while IFS="$TAB" read -r _id _co; do
    [ -n "$_id" ] && [ -n "$_hdir" ] || continue
    # Only a pack the laptop installed, at the pin: one pack.sh refused (what the hub gate would refuse) delivers no rule either.
    _mf="$(cfgdir)/.harbor-packs/hub-$_id.tsv"
    [ -f "$_mf" ] && [ "$(manifest_commit "$_mf")" = "$_co" ] || continue
    git -C "$_hdir" show "$_co:packs/$_id/extension.json" 2>/dev/null | jq -r '.files[]? | [.path, .sha256] | @tsv' 2>/dev/null > "$STATE/rules.ext" || : > "$STATE/rules.ext"
    while IFS="$TAB" read -r _rp _rh; do
      case "$_rp" in context-rules/user/*.md) ;; *) continue ;; esac
      case "$_rp" in */*/*/*|*..*) continue ;; esac
      _tmp="$_rd/.new.$$"
      if git -C "$_hdir" show "$_co:packs/$_id/harbor-pack/$_rp" > "$_tmp" 2>/dev/null && [ "$(hub_sha256 < "$_tmp")" = "$_rh" ] &&
         ! tr -d '\r' < "$_tmp" | awk '/^[ \t]*(run|spoke)[ \t]*:/ { f = 1 } END { exit !f }'; then
        mkdir -p "$_rd/$_id"; chmod 644 "$_tmp"; mv -f "$_tmp" "$_rd/$_id/${_rp##*/}"
        printf '%s\n' "$_id/${_rp##*/}" >> "$STATE/rules.keep"; log_ok "hub rule $_id/${_rp##*/} delivered"
      else
        rm -f "$_tmp"; _rf=$((_rf + 1))
        log_fail "hub rule $_id/${_rp##*/} is not delivered: its hash differs from the manifest's, or it has run: or spoke:"
        log_fix "the admin repairs the rule, regenerates extension.json and signs the new pin"; ev check check=hub-rule outcome=failed
      fi
    done < "$STATE/rules.ext"
  done < "$STATE/rules.want"
  ( cd "$_rd" && find . -type f ! -name '.new.*' | sed 's|^\./||' ) | while IFS= read -r _f; do
    grep -qxF "$_f" "$STATE/rules.keep" || rm -f "$_rd/$_f"
  done
  find "$_rd" -mindepth 1 -type d -empty -exec rmdir {} + 2>/dev/null || :
  [ "$_rf" -eq 0 ]
}

# ── sync ──────────────────────────────────────────────────────────────────────────────────────────────────
cmd_sync() {
  tgt_parse "$@"
  need_target sync
  is_member || { log_note "not a member box (HARBOR_MEMBER_ROLE is not member): nothing to sync"; log_end || :; return 0; }
  mkdir -p "$STATE"
  _frc=0; if [ "$NOFETCH" -eq 0 ]; then hs fetch || _frc=$?; fi
  case "$(hs state)" in
    revoked)
      log_warn "the verified policy lists you as revoked"
      if [ "$TGT_KIND" = dir ]; then cmd_leave --apply --dir "$TGT_DIR"; else cmd_leave --apply --live; fi; return $? ;;
    none) log_end || :; return "$_frc" ;;
  esac
  _pol="$(hs path)"
  _src=0
  sync_packs "$_pol" || _src=1
  sync_hooks "$_pol" || _src=1
  sync_rules "$_pol" || _src=1
  pin_report "$_pol"
  log_end || :
  [ "$_frc" -ne 0 ] && return "$_frc"
  return "$_src"
}

# ── status ────────────────────────────────────────────────────────────────────────────────────────────────
# cmd_id: the id member-install.sh made, beside the managed root: read, never written or made here. Stdout is the id alone, so a
# person can copy it; the rest goes to stderr. The board never shows it (hub-events.sh seals it), so this is the only place to read it.
cmd_id() {
  LOG_FD=2
  [ $# -eq 0 ] || die "id takes no argument"
  hub_marker || die "this is not a member laptop: it has no Harbor logs id" "docs/how-to/member-install.md" 1
  _idf="$HERE/../../harbor-ids/$(id -un).id"
  _id="$(cat "$_idf" 2>/dev/null)" || _id=''
  case "$_id" in *[!0123456789abcdef]*) _id='' ;; esac
  [ "${#_id}" -eq 32 ] || die "no valid id at $_idf: IT runs the install again, which makes one" "docs/how-to/member-install.md" 1
  printf '%s\n' "$_id"
  if [ -f "$HERE/../notice-received" ]; then log_note "the notice receipt is recorded: this laptop sends its counts, under this id only"
  else log_note "no notice receipt is recorded: this laptop sends no counts to Harbor's logs"; fi
  log_end || :
}

cmd_status() {
  tgt_parse "$@"
  printf 'role: %s\n' "$(hub_role)"
  is_member || { echo "no hub on this box"; return 0; }
  printf 'hub: %s\nmember: %s\n' "${HARBOR_HUB_REPO:-unset}" "${HARBOR_MEMBER_LOGIN:-unset}"
  _mr="$(hs root)"; printf 'managed root: %s (hub-signers %s)\n' "$_mr" "$([ -s "$_mr/hub-signers" ] && echo present || echo MISSING)"
  _st="$(hs state)"; _crc=0; hs check || _crc=$?
  case "$_crc" in 1) echo "policy: TAMPERED - policy files exist and none verifies; on a member laptop every call is refused until a fetch verifies one (contracts/hub.md)" ;; esac
  printf 'state: %s\n' "$_st"
  if [ "$_st" != none ]; then
    _pol="$(hs path)"
    printf 'policy: serial %s, mode %s, issued %s, silent after %s days\n' "$(jq -r .serial "$_pol")" "$(jq -r .rollout.mode "$_pol")" "$(jq -r .issued "$_pol")" "$(jq -r .silent_days "$_pol")"
    pin_report "$_pol"
    printf 'packs listed: %s\n' "$(jq -r '[.packs[]?.id] | if length == 0 then "none" else join(", ") end' "$_pol")"
    printf 'packs installed: %s\n' "$(for _m in $(hub_manifests); do _x="${_m##*/hub-}"; printf '%s@%s ' "${_x%.tsv}" "$(manifest_commit "$_m" | cut -c1-12)"; done | sed 's/ $//')"
    _hl="$(jq -r '[.hooks[]?] | length' "$_pol")"; _ho=0
    for _h in $(jq -r '.hooks[]? | .pack + ":" + .path' "$_pol"); do hs hook "${_h%%:*}" "${_h#*:}" > /dev/null 2>&1 && _ho=$((_ho + 1)); done
    printf 'hooks: %s listed, %s delivered and matching\n' "$_hl" "$_ho"
  fi
  if [ -f "$STATE/last-sync" ]; then
    _ls="$(cut -f1 "$STATE/last-sync")"
    printf 'last sync: %s, %s\n' "$(date -u -r "$_ls" +%Y-%m-%dT%H:%MZ 2>/dev/null || date -u -d "@$_ls" +%Y-%m-%dT%H:%MZ 2>/dev/null || echo "$_ls")" "$(cut -f2 "$STATE/last-sync")"
  else echo "last sync: never"; fi
  [ "$_st" != revoked ] || echo "revoked: run harbor hub leave --apply; the root half is IT's step"
  return 0
}

# ── init ──────────────────────────────────────────────────────────────────────────────────────────────────
cmd_init() {
  tgt_parse "$@"
  need_target init
  _miss=0
  need() { # <ok 0|1> <what> <who fixes>
    if [ "$1" -eq 0 ]; then log_ok "$2"; else _miss=$((_miss + 1)); log_fail "$2 is missing"; log_fix "$3"; fi
  }
  need "$(is_member && echo 0 || echo 1)" "HARBOR_MEMBER_ROLE=member in the managed settings" "IT: the member install sets it (docs/how-to/member-install.md)"
  [ "$_miss" -eq 0 ] || { log_end || :; return 1; }
  need "$([ -n "${HARBOR_HUB_REPO:-}" ] && echo 0 || echo 1)" "HARBOR_HUB_REPO in the managed settings" "IT: set it to owner/name of the hub repo"
  need "$([ -n "${HARBOR_MEMBER_LOGIN:-}" ] && echo 0 || echo 1)" "HARBOR_MEMBER_LOGIN in the managed settings" "IT: set it to your GitHub login"
  need "$([ -s "$(hs root)/hub-signers" ] && echo 0 || echo 1)" "the admin's key at $(hs root)/hub-signers" "IT: install the admin's public key as 'hub <key>' (contracts/hub.md)"
  for _t in git jq ssh-keygen; do need "$(command -v "$_t" > /dev/null 2>&1 && echo 0 || echo 1)" "$_t on PATH" "$(pkg_hint "$_t")"; done
  if hs token; then log_ok "a hub token is in the secret store (hub-token)"; else log_warn "no hub-token in the secret store: the hub is private, so a fetch will say unreachable until the sign-in step is done with IT"; fi
  [ "$_miss" -eq 0 ] || { log_end || :; return 1; }
  (umask 077; mkdir -p "$STATE") && log_ok "state dir $STATE"
  log_end || :
  cmd_sync "$@"
}

# ── leave ─────────────────────────────────────────────────────────────────────────────────────────────────
cmd_leave() {
  tgt_parse "$@"
  need_target leave
  _st="$(hs state)"
  if [ "$_st" != revoked ]; then
    if [ "$_st" = none ] && [ -z "$(hub_manifests)" ]; then log_note "this box holds no hub policy and no hub packs: nothing to leave"; log_end || :; return 0; fi
    die "not revoked: only a verified policy that lists $(printf %s "${HARBOR_MEMBER_LOGIN:-this login}") in revoked removes anything, and a failed fetch, an expired token or an outage never does" \
        "the admin lists the login in revoked and signs; or IT removes the managed files (the root half)" 1
  fi
  log_head "leaving the hub (verified revocation)"
  _lf=0
  for _m in $(hub_manifests); do
    _hid="${_m##*/hub-}"; _hid="${_hid%.tsv}"
    if [ "$APPLY" -eq 1 ]; then pk remove "hub-$_hid" --apply > /dev/null 2>&1 && log_ok "removed hub pack $_hid" || { _lf=1; log_fail "could not remove hub pack $_hid"; log_fix "harbor pack remove hub-$_hid --apply --live"; }
    else log_note "would remove hub pack $_hid"; fi
  done
  # A pack left behind keeps the policy too: revoked is derived from it, so dropping it would stop the next session trying again.
  [ "$_lf" -eq 0 ] || { log_end || :; return 1; }
  case "$STATE" in
    */harbor/hub)
      if [ "$APPLY" -eq 1 ]; then
        rm -rf "$STATE" && log_ok "dropped the hub policy, clone and hooks under $STATE" || { log_fail "could not drop $STATE"; log_fix "rm -rf '$STATE'"; log_end || :; return 1; }
      else log_note "would drop the hub policy, clone and hooks under $STATE"; fi ;;
    *) die "refusing to remove $STATE: it is not a harbor/hub state dir" ;;
  esac
  printf 'The root half is IT'"'"'s step, and nothing here can do it:\n'
  printf '  - remove %s (bin/, hub-signers, floor.pin, harbor-member-mode)\n' "$(sh "$HERE/hub-sync.sh" root 2>/dev/null || echo '<managed root>')"
  printf '  - remove the Harbor managed settings (hooks, HARBOR_MEMBER_ROLE, HARBOR_MEMBER_LOGIN, HARBOR_MEMBER_ROOT and HARBOR_HUB_REPO env, allowManagedHooksOnly)\n'
  printf '  - delete the stored hub-token (bin/secret) and revoke the member'"'"'s access to the hub repo\n'
  [ "$APPLY" -eq 1 ] || log_note "dry run: nothing was changed; add --apply"
  log_end || :
}

# ── pin-check, check, sign ────────────────────────────────────────────────────────────────────────────────
pin_check_dir() { # <contract> <dir>: print one line per extension that rejects the contract; return 1 if any
  _bad=0; _any=0
  for _e in "$2"/packs/*/extension.json; do
    [ -f "$_e" ] || continue
    _any=1
    _hv="$(jq -r '.harbor_version // empty' "$_e" 2>/dev/null)"; _eid="$(jq -r '.id // "?"' "$_e" 2>/dev/null)"
    _prc=0; pack_ver_ok "$_hv" "$1.0" || _prc=$?
    case "$_prc" in
      0) ;;
      1) _bad=1; printf 'pin: contract %s is refused: extension %s needs harbor %s\n' "$1" "$_eid" "$_hv" ;;
      *) _bad=1; printf 'pin: extension %s has a harbor_version the pack grammar cannot read: %s\n' "$_eid" "$_hv" ;;
    esac
  done
  [ "$_any" -eq 1 ] || printf 'pin: no extension in %s\n' "$2" >&2
  [ "$_bad" -eq 0 ]
}
cmd_pin_check() {
  [ $# -ge 1 ] || die "pin-check needs a contract number"
  case "$1" in ''|*[!0-9]*) die "the contract is a whole number, not '$1'" ;; esac
  _d="${2:-.}"
  if pin_check_dir "$1" "$_d"; then log_ok "contract $1 is accepted by every extension in $_d"; log_end || :; return 0; fi
  log_fail "the pin may not move to contract $1 while an extension rejects it"; log_fix "update or remove the extension named above, then raise the pin"
  log_end || :; return 1
}

SIGNERS=''
W="${TMPDIR:-/tmp}/hub.$$"; mkdir -p "$W"; trap 'rm -rf "$W"' EXIT INT TERM

# check_dir <dir> <sig|nosig>: one finding per line on stdout; return 1 when there is any. The hub's gate and `sign` both call it.
check_dir() {
  _cd="$1"; _o="$W/findings"; : > "$_o"
  say() { printf '%s\n' "$1" >> "$_o"; }
  [ -f "$_cd/policy.json" ] || { say "no policy.json in $_cd"; cat "$_o"; return 1; }
  sh "$HERE/hub-format.sh" policy "$_cd/policy.json" > /dev/null 2> "$W/fmt" || sed 's/^/policy: /' "$W/fmt" >> "$_o"
  if [ "$2" = sig ]; then
    _sg="${SIGNERS:-$(hs root)/hub-signers}"
    if [ ! -f "$_cd/policy.json.sig" ]; then say "policy.json.sig is missing: the policy is unsigned"
    elif [ ! -s "$_sg" ]; then printf 'check: signature not verified, no signers file at %s (give --signers)\n' "$_sg" >&2
    elif ! ssh-keygen -Y verify -f "$_sg" -I hub -n harbor-hub -s "$_cd/policy.json.sig" < "$_cd/policy.json" > /dev/null 2>&1; then
      say "policy.json.sig does not verify against the signers file"
    fi
  fi
  # A hub may re-tier a default row and nothing else: a fixed row in tiers is refused at read time, so it is refused here too.
  _rt="$HERE/../contracts/risk-tiers.tsv"; [ -f "$_rt" ] || _rt="$HERE/risk-tiers.tsv"
  if [ -f "$_rt" ]; then
    for _k in $(jq -r '.tiers // {} | keys[]' "$_cd/policy.json" 2>/dev/null); do
      awk -F'\t' -v k="$_k" '$1 == k && $3 == "fixed" { f = 1 } END { exit !f }' "$_rt" && say "tiers.$_k: a fixed row cannot be re-tiered"
    done
  fi
  _ct="$(jq -r '.core.contract // 0' "$_cd/policy.json" 2>/dev/null)"
  jq -r '.packs[]? | [.id, .commit] | @tsv' "$_cd/policy.json" > "$W/packs" 2>/dev/null || : > "$W/packs"
  jq -r '.hooks[]? | [.pack, .path, .sha256] | @tsv' "$_cd/policy.json" > "$W/hooks" 2>/dev/null || : > "$W/hooks"
  if [ -s "$W/packs" ] || [ -s "$W/hooks" ]; then
    git -C "$_cd" rev-parse --git-dir > /dev/null 2>&1 || say "packs and hooks are pinned by commit, and $_cd is not a git checkout"
  fi
  if git -C "$_cd" rev-parse --git-dir > /dev/null 2>&1; then
    while IFS="$TAB" read -r _id _co; do
      [ -n "$_id" ] || continue
      git -C "$_cd" cat-file -e "$_co^{commit}" 2>/dev/null || { say "pack $_id: commit $_co is not in this repository"; continue; }
      git -C "$_cd" show "$_co:packs/$_id/harbor-pack/pack.toml" > /dev/null 2>&1 || say "pack $_id: no packs/$_id/harbor-pack/pack.toml at $_co"
      if ! git -C "$_cd" show "$_co:packs/$_id/extension.json" > "$W/ext" 2>/dev/null; then say "pack $_id: no packs/$_id/extension.json at $_co"; continue; fi
      sh "$HERE/hub-format.sh" manifest "$W/ext" > /dev/null 2> "$W/extf" || say "pack $_id: extension.json: $(head -n 1 "$W/extf")"
      [ "$(jq -r .id "$W/ext" 2>/dev/null)" = "$_id" ] || say "pack $_id: extension.json names another pack"
      _prc=0; pack_ver_ok "$(jq -r '.harbor_version // empty' "$W/ext")" "$_ct.0" || _prc=$?
      [ "$_prc" -eq 0 ] || say "pack $_id: harbor_version $(jq -r '.harbor_version // empty' "$W/ext") rejects the pinned contract $_ct"
      jq -r '.files[]? | [.path, .sha256] | @tsv' "$W/ext" > "$W/extfiles" 2>/dev/null || : > "$W/extfiles"
      while IFS="$TAB" read -r _ep _eh; do
        [ "$(git -C "$_cd" show "$_co:packs/$_id/harbor-pack/$_ep" 2>/dev/null | hub_sha256)" = "$_eh" ] || say "pack $_id: $_ep differs from the hash in extension.json"
      done < "$W/extfiles"
    done < "$W/packs"
    while IFS="$TAB" read -r _hp _hpath _hsha; do
      [ -n "$_hp" ] || continue
      _co="$(awk -F'\t' -v p="$_hp" '$1 == p { print $2; exit }' "$W/packs")"
      [ -n "$_co" ] || { say "hook $_hp/$_hpath: pack $_hp is not in packs"; continue; }
      [ "$(git -C "$_cd" show "$_co:packs/$_hp/harbor-pack/$_hpath" 2>/dev/null | hub_sha256)" = "$_hsha" ] || say "hook $_hp/$_hpath: the committed file does not match sha256 in the policy"
    done < "$W/hooks"
  fi
  [ ! -d "$_cd/packs" ] || pin_check_dir "$_ct" "$_cd" >> "$_o" 2>/dev/null || :
  cat "$_o"
  [ ! -s "$_o" ]
}

cmd_check() {
  _dir=.; SIGNERS=''
  while [ $# -gt 0 ]; do
    case "$1" in --signers) [ $# -ge 2 ] || die "--signers needs a file"; SIGNERS="$2"; shift ;; -*) die "unknown flag: $1" ;; *) _dir="$1" ;; esac
    shift
  done
  if check_dir "$_dir" sig > "$W/out"; then log_ok "$_dir: policy, signature, packs, hooks and pin agree"; log_end || :; return 0; fi
  cat "$W/out"; log_fail "$(wc -l < "$W/out" | tr -d ' ') finding(s) in $_dir"; log_fix "fix what is listed above, then harbor hub sign"; log_end || :; return 1
}

cmd_sign() {
  _file=''; _key=''; SIGNERS=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --key) [ $# -ge 2 ] || die "--key needs a private key file"; _key="$2"; shift ;;
      --signers) [ $# -ge 2 ] || die "--signers needs a file"; SIGNERS="$2"; shift ;;
      -*) die "unknown flag: $1" ;;
      *) _file="$1" ;;
    esac
    shift
  done
  [ -f "$_file" ] || die "sign needs the policy.json to sign"
  [ "${_file##*/}" = policy.json ] || die "the file to sign is named policy.json"
  [ -r "$_key" ] || die "sign needs --key <private key file>"
  _dir="${_file%/*}"; [ "$_dir" != "$_file" ] || _dir=.
  rm -f "$_file.sig"
  if ! check_dir "$_dir" nosig > "$W/out"; then
    cat "$W/out"; die "not signing: the policy fails its checks" "fix what is listed above" 1
  fi
  # A policy replaces the committed one only with a higher serial, so a signed file cannot be walked backwards.
  _old="$(git -C "$_dir" show HEAD:policy.json 2>/dev/null | jq -r '.serial // empty' 2>/dev/null)" || _old=''
  if [ -n "$_old" ] && ! git -C "$_dir" show HEAD:policy.json 2>/dev/null | cmp -s - "$_file"; then
    [ "$(jq -r .serial "$_file")" -gt "$_old" ] || die "not signing: serial $(jq -r .serial "$_file") is not above the committed serial $_old" "raise serial in policy.json" 1
  fi
  ssh-keygen -Y sign -f "$_key" -n harbor-hub "$_file" || die "ssh-keygen could not sign" "check the key file and its passphrase" 1
  # Prove the file just written: against the signers file given, else the key's own public half.
  _sg="$SIGNERS"
  if [ -z "$_sg" ] && [ -r "$_key.pub" ]; then _sg="$W/signers"; printf 'hub %s\n' "$(cat "$_key.pub")" > "$_sg"; fi
  if [ -z "$_sg" ]; then log_warn "signed, but not verified: no --signers and no $_key.pub"
  elif ssh-keygen -Y verify -f "$_sg" -I hub -n harbor-hub -s "$_file.sig" < "$_file" > /dev/null 2>&1; then log_ok "signed serial $(jq -r .serial "$_file"): $_file.sig verifies"
  else rm -f "$_file.sig"; die "the signature just made does not verify against the signers file: removed" "use the key whose public half is in hub-signers" 1; fi
  log_end || :
}

# ── member projects: harbor repo adopt, without the plugin and the lifecycle workflow ─────────────────────
cmd_project() {
  [ "${1:-}" = register ] || die "project takes: register <name> [--covers TEXT] [--kind K]"
  shift
  _name=''; _covers='member project'; _kind=workload
  while [ $# -gt 0 ]; do
    case "$1" in
      --covers) [ $# -ge 2 ] || die "--covers needs text"; _covers="$2"; shift ;;
      --kind) [ $# -ge 2 ] || die "--kind needs a repo kind"; _kind="$2"; shift ;;
      -*) die "unknown flag: $1" ;;
      *) _name="$1" ;;
    esac
    shift
  done
  case "$_name" in ''|*[!A-Za-z0-9._-]*|[!A-Za-z0-9]*) die "'$_name' is not a project name ([A-Za-z0-9][A-Za-z0-9._-]*)" ;; esac
  _pr="$(sh "$HERE/scope-roots.sh" --port-root)" || die "no workspace root" "sh $HERE/scope-roots.sh --port-root"
  [ -d "$_pr/$_name" ] || die "no checkout at $_pr/$_name" "clone it there, then harbor hub project register $_name"
  rm -rf "$W"
  # R28: a core install has no yard, uv or just. Say it, then do the part core can do: register, list and route the checkout,
  # then lay down the project standard yard would (member-standard.sh, control member.standard).
  log_note "this install has no yard, uv or just: the scaffold, label, versions and fleet steps are not run; the project is registered, listed and routed, and gets the member project standard (AGENTS.md, CLAUDE.md, tests/) without a governance marker"
  _rc=0
  sh "$HERE/scope-repo.sh" adopt "$_pr/$_name" --kind "$_kind" --covers "$_covers" --core-only || _rc=$?   # set -e: 3 (a check could not look) is an answer, not an abort
  case "$_rc" in 0|3) ;; *) exit "$_rc" ;; esac
  sh "$HERE/member-standard.sh" "$_pr/$_name" --name "$_name" --kind "$_kind" --covers "$_covers" || exit $?
  exit "$_rc"
}

verb="${1:-}"; [ $# -eq 0 ] || shift
case "$verb" in
  -h|--help|help) usage ;;
  init) cmd_init "$@" ;;
  sync) cmd_sync "$@" ;;
  status) cmd_status "$@" ;;
  sign) cmd_sign "$@" ;;
  check) cmd_check "$@" ;;
  pin-check) cmd_pin_check "$@" ;;
  leave) cmd_leave "$@" ;;
  project) cmd_project "$@" ;;
  support) rm -rf "$W"; exec sh "$HERE/hub-support.sh" "$@" ;;
  tools) rm -rf "$W"; exec sh "$HERE/hub-tools.sh" "$@" ;;
  id) cmd_id "$@" ;;
  '') usage >&2; exit 2 ;;
  *) die "unknown verb '$verb' (init, sync, status, sign, check, pin-check, leave, project, support, tools)" ;;
esac
