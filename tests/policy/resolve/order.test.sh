#!/usr/bin/env sh
# bin/policy-resolve.sh (harbor#957, #1001): flag > env > repo > user > default, and each step falls through when empty.
. "$(dirname "$0")/../../lib/core.sh"; t_init
PR="$T_ROOT/bin/policy-resolve.sh"
printf 'k=repo\n' > "$T_TMP/repo"; printf 'k=user\n' > "$T_TMP/user"
r() { env POLICY_K="$2" sh "$PR" k --flag "$1" --env POLICY_K --repo "$T_TMP/repo" --user "$T_TMP/user" --default dflt 2>&1; }
t_section "each source wins over the ones below it"
t_has "flag beats all" "$(r f e)" "source: flag"
t_has "env beats repo, user and default" "$(r "" e)" "source: env"
t_has "repo beats user and default" "$(r "" "")" "source: repo"
t_eq "…and prints the repo value" "repo" "$(sh "$PR" k --repo "$T_TMP/repo" --user "$T_TMP/user" 2>/dev/null | head -1)"
rm "$T_TMP/repo"
t_has "user beats default" "$(r "" "")" "source: user"
rm "$T_TMP/user"
t_has "default is last" "$(r "" "")" "source: default"
t_section "usage and no source"
t_exit "no source and no default exits 1" 1 sh "$PR" k --repo "$T_TMP/none"
t_exit "no key exits 2" 2 sh "$PR"
t_exit "an unknown option exits 2" 2 sh "$PR" k --bogus x
t_done
