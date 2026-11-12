#!/usr/bin/env sh
# repo-not-adopted.sh (harbor#1278) - at session start, each repo under PORT_ROOT harbor does not govern, with its adopt command.
# The list is bin/scope-repo-sources.sh --not-adopted's; this only words it. Silent on an empty list and on any failure.
case "$0" in */*) _H="${0%/*}" ;; *) _H=. ;; esac
# Run from a checkout the scripts are beside this file; installed, they are in the harbor checkout.
_B="$_H/../../bin"
[ -f "$_B/scope-repo-sources.sh" ] && [ -f "$_H/../../contracts/roots.tsv" ] || _B="${HARBOR_SCOPE_REPO:-${PORT_ROOT:-$HOME/port}/harbor}/bin"
[ -f "$_B/scope-repo-sources.sh" ] || exit 0
LIST="$(sh "$_B/scope-repo-sources.sh" --not-adopted 2>/dev/null)" || exit 0
[ -n "$LIST" ] || exit 0
PR="$(sh "$_B/scope-roots.sh" --port-root 2>/dev/null)" || PR=''
case "$PR" in "$HOME"/*) PR="~/${PR#"$HOME"/}" ;; '') PR='the workspace root' ;; esac
KINDS="$(awk -F'\t' '/^#/ || $0 == "" { next } !h { h = 1; next } { print $1 }' "$_B/../standards/naming/repo-kinds.tsv" 2>/dev/null | sort -u | tr '\n' ' ')"
printf '%s\n' "$LIST" | awk -F'\t' -v pr="$PR" -v kinds="${KINDS% }" '
  NF < 3 { next }
  $3 == "unregistered" { u++; l = l sprintf("\n  - %s (no registry row): harbor repo adopt %s --kind <repo-kind>", $1, $1) }
  $3 == "ungoverned"   { g++; l = l sprintf("\n  - %s (registered, governed=no): harbor repo adopt %s --kind %s", $1, $1, $2) }
  END { if (l == "") exit
    printf "Repos under %s that harbor does not govern yet (harbor#1278, advisory): every repo starts with yard and is integrated into fleet, and `harbor repo adopt` scaffolds what is missing, registers it and audits it. Adopting writes into the repo and the registry, so name these to the operator and leave the run to them:%s\n", pr, l
    if (u) printf "<repo-kind> is one of: %s.\n", kinds
    if (g) printf "For a governed=no row, adopt keeps the existing registry row as it is: its governed cell stays no until the operator sets it to yes in repos.tsv.\n" }'
exit 0
