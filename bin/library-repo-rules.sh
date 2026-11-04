#!/usr/bin/env sh
# library-repo-rules.sh (harbor#1418) — how a repo's GitHub rules are declared in ship.conf and read from GitHub, one
# spelling for the two callers that compare them: gate-pr-plan.sh (a PR's plan) and gate-repo-drift.sh (the whole repo).
# Source it; it defines functions only and needs jq.
#
#   rr_conf <key>                  ship.conf text on stdin -> the key's first value ('#' comments stripped, as gate_conf does)
#   rr_method_decl <value>         ship.conf `method` -> squash | merge | rebase (merge-commit is merge), else the value as given
#   rr_review_decl <value>         ship.conf `review` -> "<n>" or "<n> code-owner"; `none` is "0"; anything else "invalid"
#   rr_deletebranch_decl <value>   ship.conf `delete-branch` -> true | false, else "invalid"
#   rr_methods <repo-json> <rules-json>   the merge methods a PR can use now: the repo's allow_* AND the rules' allowed_merge_methods
#   rr_review_live <rules-json>    the strictest pull_request rule on the branch, as rr_review_decl spells it; empty when none is readable

# lint S1/S4/LOG1 judge every bin/*.sh alike: the strict mode both callers already run under, the --help arm that answers
# only when this file is run itself ($0), and the log library the callers have sourced.
set -u
case "${0##*/}:${1:-}" in library-repo-rules.sh:-h|library-repo-rules.sh:--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); print; next } {exit}' "$0"; exit 0 ;; esac
[ -n "${_LOG_LIB:-}" ] || . "$(dirname -- "$0")/library-log.sh"

rr_conf() { # <key>
  awk -v k="$1" '{ sub(/(^|[ \t])#.*/, "") } $1 == k { $1 = ""; sub(/^[ \t]+/, ""); sub(/[ \t]+$/, ""); print; exit }'
}

rr_method_decl() { # <value>
  case "$1" in merge-commit) printf 'merge\n' ;; *) printf '%s\n' "$1" ;; esac
}

rr_review_decl() { # <value>
  printf '%s\n' "$1" | awk '
    NF == 1 && $1 == "none" { print "0"; exit }
    $1 !~ /^[0-9]+$/ || NF > 2 || (NF == 2 && $2 != "code-owner") { print "invalid"; exit }
    { print $1 (NF == 2 ? " code-owner" : ""); exit }'
}

rr_deletebranch_decl() { # <value>
  case "$1" in yes|true) printf 'true\n' ;; no|false) printf 'false\n' ;; *) printf 'invalid\n' ;; esac
}

rr_methods() { # <repo-json> <rules-json>
  jq -rn --argjson r "$1" --argjson u "$2" '
    [if $r.allow_squash_merge == false then empty else "squash" end,
     if $r.allow_merge_commit == false then empty else "merge" end,
     if $r.allow_rebase_merge == false then empty else "rebase" end] as $repo
    | ([$u[]? | select(.type == "pull_request") | .parameters.allowed_merge_methods // empty] | if length == 0 then $repo else (.[0]) end) as $rule
    | [$repo[] | select(. as $m | $rule | index($m))] | join(" ")'
}

rr_review_live() { # <rules-json>
  jq -rn --argjson u "$1" '
    [$u[]? | select(.type == "pull_request") | .parameters] as $p
    | if ($p | length) == 0 then empty
      else "\([$p[].required_approving_review_count // 0] | max)" + (if any($p[]; .require_code_owner_review == true) then " code-owner" else "" end) end'
}
