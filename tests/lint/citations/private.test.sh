#!/usr/bin/env sh
# Lint rule T7 (doc.urls-cited) reads the private layer's citations.md beside CITATIONS.md (harbor#1149): the
# rows for hosts core does not name. Each arm points the rule at a throwaway root and a throwaway layer.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
FIX="$TMP/cit"; mkdir -p "$FIX" "$TMP/pv-empty"
printf '# ledger\n\n| URL | HTTP |\n|---|---|\n| `https://github.com/VytCepas/harbor` | 200 |\n' > "$FIX/CITATIONS.md"
printf 'The tool is documented at `https://docs.example-vendor.io/guide` and on help.example-vendor.io today.\n' > "$FIX/DOC.md"
PV="$TMP/pv"; mkdir -p "$PV"
t7() { env HARBOR_SCOPE_PRIVATE="$1" HARBOR_ROOT="$FIX" sh "$LINT" --only T7 2>&1 | grep -F 'VIOLATION [doc.urls-cited]'; }

t_section "a host in neither ledger is a violation"
t_has "the URL is reported" "$(t7 "$PV")" 'docs.example-vendor.io/guide'
t_has "the bare host is reported" "$(t7 "$PV")" 'help.example-vendor.io'

t_section "a row in the private citations.md satisfies it"
printf '| `https://docs.example-vendor.io/guide` | 200 | curl | 2026-10-01 | fixture |\n| `help.example-vendor.io` | - | prose | 2026-10-01 | fixture |\n' > "$PV/citations.md"
t_eq "both are listed: silent" "" "$(t7 "$PV")"

t_section "the private ledger adds, it never replaces"
printf '| `https://docs.example-vendor.io/guide` | 200 |\n' > "$PV/citations.md"
t_has "the host the private file lacks is still reported" "$(t7 "$PV")" 'help.example-vendor.io'
t_hasnt "and the one it holds is not" "$(t7 "$PV")" 'docs.example-vendor.io/guide'
printf 'See `https://github.com/VytCepas/harbor` for the repo.\n' > "$FIX/DOC.md"
t_eq "a row only the core ledger holds still counts" "" "$(t7 "$TMP/pv-empty")"

t_section "no private layer is the core ledger alone, not an error"
printf 'The tool is documented at `https://docs.example-vendor.io/guide`.\n' > "$FIX/DOC.md"
t_has "an unlisted URL is a violation, as before" "$(t7 "$TMP/no-such-layer")" 'docs.example-vendor.io/guide'
t_done
