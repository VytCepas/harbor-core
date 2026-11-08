#!/usr/bin/env sh
# Stub of hub-sync.sh (harbor#1278): `path` prints the file named in stub-policy beside it, or nothing. The dispatcher clears env, so a sibling file is the only channel.
# `check` exits stub-check, else 0 with a policy and 2 without. `hook` is the real verb's rule: the delivered file, if its sha256 is the policy's.
_d="${0%/*}"
case "${1:-}" in
  path) [ -f "$_d/stub-policy" ] && cat "$_d/stub-policy"; exit 0 ;;
  check) [ -f "$_d/stub-check" ] && exit "$(cat "$_d/stub-check")"; [ -f "$_d/stub-policy" ] && exit 0; exit 2 ;;
  hook)
    _want="$(jq -r --arg p "$2" --arg r "$3" '[.hooks[]? | select(.pack == $p and .path == $r) | .sha256][0] // empty' "$(cat "$_d/stub-policy")")"
    _hf="$HOME/.local/state/harbor/hub/hooks/$2/$3"
    { [ -n "$_want" ] && [ -f "$_hf" ] && [ ! -L "$_hf" ]; } || exit 1
    if command -v sha256sum >/dev/null 2>&1; then _got="$(sha256sum < "$_hf")"; else _got="$(shasum -a 256 < "$_hf")"; fi
    [ "${_got%% *}" = "$_want" ] || exit 1
    printf '%s\n' "$_hf"; exit 0 ;;
  state) echo joined ;;
esac
exit 0
