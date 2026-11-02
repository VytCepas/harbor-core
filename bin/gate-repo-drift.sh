#!/usr/bin/env sh
# gate-repo-drift.sh (harbor#1418) — each governed repo's GitHub rules, declared in .agents/ship.conf, against live.
#
#   sh gate-repo-drift.sh [--print | --commands] [--repo OWNER/NAME]... [--registry FILE] [--declared FILE]
#
# DECLARED  .agents/ship.conf on the default branch: `method`, `review <n> [code-owner]` (or `none`), `delete-branch
#           yes|no` (docs/design/deploy-fleet.md). --declared FILE adds `slug TAB key TAB value` rows for a repo or a key
#           that has no ship.conf (the private layer's declaration). A key declared nowhere is UNDECLARED.
# LIVE      `gh api repos/<r>` (allow_*_merge, delete_branch_on_merge) and `repos/<r>/rules/branches/<base>` (the
#           pull_request rule, strictest wins). Method is judged as the set a PR can use now; one the declaration does not
#           name is drift. A branch with no readable review rule is probed for classic protection, which answers 403 to
#           the App: that is UNREADABLE, never clean. A classic rule beside a readable ruleset is not seen.
# THE REPOS --repo (repeatable), else the governed-repo registry (`scope-roots.sh --repos`, or --registry FILE of
#           name TAB checkout rows), each checkout's origin naming the GitHub repo. A repo it cannot map or read is
#           UNREAD, never skipped.
# OUTPUT    every line carries [check:gate.repo-drift] (docs/reference/checks.md). Default: the DELTA — new findings in
#           full, standing ones as one line with their age, from ${HARBOR_GATE_REPO_DRIFT_STATE:-<state dir>/harbor/
#           repo-drift/seen.tsv}. --print: the census (undeclared, drift, unreadable, clean) with the exact operator
#           command per drift, and writes nothing. --commands: only the runnable fix commands on stdout, in run order,
#           the census on stderr. It applies nothing: every command is the operator's (an admin write).
# EXIT      0 clean · 1 drift or undeclared · 2 usage · 3 something could not be read (wins over 1)
# ENV       HARBOR_TEST_GH a fake gh
set -u
case "$0" in */*) _SRC="${0%/*}" ;; *) _SRC=. ;; esac
HERE="$(CDPATH= cd -- "$_SRC" && pwd)"
. "$HERE/library-log.sh"
. "$HERE/library-repo-rules.sh"
ID="gate.repo-drift"
GH="${HARBOR_TEST_GH:-gh}"
STATE="${HARBOR_GATE_REPO_DRIFT_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/harbor/repo-drift/seen.tsv}"
MODE=delta; REPOS=""; REG=""; DECLF=""

usage() { printf '[check:%s] %s\nusage: sh %s [--print | --commands] [--repo OWNER/NAME]... [--registry FILE] [--declared FILE]\n' "$ID" "$1" "$0" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); print; next } {exit}' "$0"; exit 0 ;;
    --print) MODE=print; shift ;;
    --commands) MODE=commands; shift ;;
    --repo) [ $# -ge 2 ] || usage "--repo takes OWNER/NAME"; slug_valid "$2" || usage "--repo takes OWNER/NAME, not: $2"; REPOS="$REPOS$2
"; shift 2 ;;
    --registry) [ $# -ge 2 ] || usage "--registry takes a file"; REG="$2"; shift 2 ;;
    --declared) [ $# -ge 2 ] || usage "--declared takes a file"; DECLF="$2"; shift 2 ;;
    *) usage "unknown argument: $1" ;;
  esac
done
command -v jq >/dev/null 2>&1 || { printf '[check:%s] jq is required (%s)\n' "$ID" "$(pkg_hint jq)" >&2; exit 3; }
[ -z "$DECLF" ] || [ -r "$DECLF" ] || usage "--declared file not readable: $DECLF"
W="$(mktemp -d "${TMPDIR:-/tmp}/gate-repo-drift.XXXXXX")" || exit 3
trap 'rm -rf "$W"' EXIT INT TERM HUP
: > "$W/findings"; : > "$W/fixes"; : > "$W/clean"

# ── the repo list: one slug per line in $W/targets, or an unread row in $W/findings ──
: > "$W/targets"
if [ -n "$REPOS" ]; then
  printf '%s' "$REPOS" | awk 'NF { print $1 }' > "$W/targets"
else
  if [ -n "$REG" ]; then
    [ -r "$REG" ] || usage "registry not readable: $REG"
    cp "$REG" "$W/reg"
  else
    sh "$HERE/scope-roots.sh" --repos > "$W/reg" 2>/dev/null && [ -s "$W/reg" ] \
      || { printf '[check:%s] no registry of governed repos (scope-roots.sh --repos): nothing to read; name one with --repo OWNER/NAME\n' "$ID" >&2; exit 3; }
  fi
  while IFS="$(printf '\t')" read -r _name _path _rest; do
    case "$_name" in ''|'#'*) continue ;; esac
    case "$_path" in "~/"*) _path="$HOME/${_path#\~/}" ;; esac
    if [ ! -d "$_path" ]; then printf '%s\t%s\t%s\t%s\n' "$_name" unread registry "no checkout at its registry path" >> "$W/findings"; continue; fi
    _slug="$(slug_of_url "$(git -C "$_path" remote get-url origin 2>/dev/null)")"
    if [ -n "$_slug" ]; then printf '%s\n' "$_slug" >> "$W/targets"; continue; fi
    # No origin: a parent folder of repos (and their worktrees) — judge each child's GitHub repo once.
    _kids=0
    for _c in "$_path"/*/; do
      [ -e "$_c.git" ] || continue
      _s="$(slug_of_url "$(git -C "$_c" remote get-url origin 2>/dev/null)")"
      [ -n "$_s" ] && { printf '%s\n' "$_s" >> "$W/targets"; _kids=1; }
    done
    [ "$_kids" = 1 ] || printf '%s\t%s\t%s\t%s\n' "$_name" unread registry "no GitHub origin" >> "$W/findings"
  done < "$W/reg"
fi
[ -s "$W/targets" ] || [ -s "$W/findings" ] || { printf '[check:%s] the registry names no repo\n' "$ID" >&2; exit 3; }

sq() { sed "s/'/'\\\\''/g"; }                       # a JSON body inside single quotes
find_() { printf '%s\t%s\t%s\t%s\n' "$R" "$1" "$2" "$3" >> "$W/findings"; }   # <kind> <key> <detail>
fix_() { printf '%s\t%s\t%s\t%s\n' "$R" "$1" "$2" "$3" >> "$W/fixes"; }       # <key> <run|do> <text>
decl_() { # <key> -> the declared value: ship.conf first, then the --declared row
  _v="$(printf '%s\n' "$SHIP" | rr_conf "$1")"
  if [ -z "$_v" ] && [ -n "$DECLF" ]; then _v="$(awk -F'\t' -v r="$R" -v k="$1" '$1 == r && $2 == k { print $3; exit }' "$DECLF")"; fi
  printf '%s\n' "$_v"
}
declmethod_() { # the declared method as the API spells it, empty when undeclared or not one
  _m="$(decl_ method)"; _m="$(rr_method_decl "${_m%% *}")"; case "$_m" in squash|merge|rebase) printf '%s\n' "$_m" ;; esac
}
mflag() { case "$1" in squash) echo allow_squash_merge ;; merge) echo allow_merge_commit ;; rebase) echo allow_rebase_merge ;; esac; }

# the ruleset that makes the declared review readable: one POST, then the classic rule (403 to the App) goes
migrate_() { # <key> <review "<n> [code-owner]"> <method-or-empty>
  _n="${2%% *}"; _co=false; case "$2" in *code-owner*) _co=true ;; esac
  _body="$(jq -cn --argjson n "$_n" --argjson co "$_co" --arg m "$3" '{name: "declared review", target: "branch", enforcement: "active",
    conditions: {ref_name: {include: ["~DEFAULT_BRANCH"], exclude: []}},
    rules: [{type: "pull_request", parameters: {required_approving_review_count: $n, dismiss_stale_reviews_on_push: true,
      require_code_owner_review: $co, require_last_push_approval: false, required_review_thread_resolution: false,
      allowed_merge_methods: (if $m == "" then ["merge", "squash", "rebase"] else [$m] end)}}]}')"
  fix_ "$1" run "printf '%s' '$(printf '%s' "$_body" | sq)' | gh api -X POST repos/$R/rulesets --input -"
  fix_ "$1" run "gh api -X DELETE repos/$R/branches/$BASE/protection"
}

judge() { # <slug>
  R="$1"; NF_BEFORE="$(grep -c . "$W/findings" | tr -d ' ')"
  RJ="$("$GH" api "repos/$R" 2>"$W/err")" || { find_ unread repo "could not read the repo: $(head -n 1 "$W/err" | cut -c1-160)"; return; }
  BASE="$(printf '%s' "$RJ" | jq -r '.default_branch // "main"')"
  RUL="$("$GH" api "repos/$R/rules/branches/$BASE" 2>"$W/err")" || { find_ unread rules "could not read $BASE's rules: $(head -n 1 "$W/err" | cut -c1-160)"; return; }
  SHIP="$("$GH" api "repos/$R/contents/.agents/ship.conf?ref=$BASE" -H "Accept: application/vnd.github.raw" 2>"$W/err")" || {
    grep -q 'HTTP 404' "$W/err" || { find_ unread ship.conf "could not read ship.conf: $(head -n 1 "$W/err" | cut -c1-160)"; return; }
    SHIP=""; }
  UNDECL=""

  # method: the set a PR can use now against the one declared
  d="$(decl_ method)"; d="$(rr_method_decl "${d%% *}")"; live="$(rr_methods "$RJ" "$RUL")"
  if [ -z "$d" ]; then UNDECL="$UNDECL method"
  else
    case "$d" in squash|merge|rebase) ;; *) find_ drift method "method $d is not squash, merge-commit or rebase" ;; esac
    case "$d" in squash|merge|rebase)
      extra=""; for m in $live; do [ "$m" = "$d" ] || extra="$extra $m"; done
      case " $live " in *" $d "*) has=1 ;; *) has=0 ;; esac
      if [ -n "$extra" ] || [ "$has" = 0 ]; then
        find_ drift method "declared $d, live allows: ${live:-nothing}"
        args=""; for m in $extra; do args="$args -F $(mflag "$m")=false"; done
        if [ "$has" = 0 ]; then
          if [ "$(printf '%s' "$RJ" | jq -r --arg k "$(mflag "$d")" '.[$k]')" = false ]; then args="$args -F $(mflag "$d")=true"
          else fix_ method do "a ruleset's allowed_merge_methods excludes $d: $(printf '%s' "$RUL" | jq -r '[.[] | select(.type == "pull_request") | .ruleset_id] | unique | map("repos/'"$R"'/rulesets/\(.)") | join(" ")')"; fi
        fi
        [ -z "$args" ] || fix_ method run "gh api -X PATCH repos/$R$args"
      fi ;;
    esac
  fi

  # delete-branch
  d="$(decl_ delete-branch)"
  if [ -z "$d" ]; then UNDECL="$UNDECL delete-branch"
  else
    dn="$(rr_deletebranch_decl "$d")"; live="$(printf '%s' "$RJ" | jq -r '.delete_branch_on_merge // false')"
    if [ "$dn" = invalid ]; then find_ drift delete-branch "delete-branch $d is not yes or no"
    elif [ "$dn" != "$live" ]; then
      find_ drift delete-branch "declared $d, live delete_branch_on_merge is $live"
      fix_ delete-branch run "gh api -X PATCH repos/$R -F delete_branch_on_merge=$dn"
    fi
  fi

  # review: the ruleset's pull_request rule; none readable means classic protection may hold it
  d="$(decl_ review)"; dn=""
  if [ -z "$d" ]; then UNDECL="$UNDECL review"
  else dn="$(rr_review_decl "$d")"; [ "$dn" != invalid ] || { find_ drift review "review $d is not '<n> [code-owner]' or 'none'"; dn=""; }; fi
  live="$(rr_review_live "$RUL")"; classic=""
  if [ -z "$live" ]; then
    if "$GH" api "repos/$R/branches/$BASE/protection" > "$W/prot" 2>"$W/err"; then
      classic=1
      live="$(jq -r '.required_pull_request_reviews // {} | "\(.required_approving_review_count // 0)" + (if .require_code_owner_reviews == true then " code-owner" else "" end)' "$W/prot")"
    elif grep -q 'HTTP 403' "$W/err"; then
      find_ unreadable review "classic branch protection answers 403 to the App, so $BASE's review rule cannot be read; a ruleset can"
      [ -z "$dn" ] || migrate_ review "$dn" "$(declmethod_)"
      live="?"
    elif grep -q 'HTTP 404' "$W/err"; then live="0"
    else find_ unread review "could not read $BASE's protection: $(head -n 1 "$W/err" | cut -c1-160)"; live="?"; fi
  fi
  if [ -n "$dn" ] && [ "$live" != "?" ] && [ "$live" != "$dn" ]; then
    find_ drift review "declared $dn, live requires $live"
    mm="$(declmethod_)"
    if [ -n "$classic" ]; then migrate_ review "$dn" "$mm"
    elif [ -z "$(rr_review_live "$RUL")" ]; then migrate_ review "$dn" "$mm"
    else
      _n="${dn%% *}"; _co=false; case "$dn" in *code-owner*) _co=true ;; esac
      for _id in $(printf '%s' "$RUL" | jq -r --argjson n "$_n" --argjson co "$_co" '[.[] | select(.type == "pull_request" and .ruleset_source_type == "Repository"
          and ((.parameters.required_approving_review_count // 0) != $n or (.parameters.require_code_owner_review // false) != $co)) | .ruleset_id] | unique | .[]'); do
        if "$GH" api "repos/$R/rulesets/$_id" > "$W/rs" 2>"$W/err"; then
          _body="$(jq -c --argjson n "$_n" --argjson co "$_co" '{name, target, enforcement, conditions, bypass_actors,
            rules: [.rules[] | if .type == "pull_request" then .parameters += {required_approving_review_count: $n, require_code_owner_review: $co} else . end]}
            | with_entries(select(.value != null))' "$W/rs")"
          fix_ review run "printf '%s' '$(printf '%s' "$_body" | sq)' | gh api -X PUT repos/$R/rulesets/$_id --input -"
        else fix_ review do "set ruleset $_id's pull_request rule to $dn (gh api repos/$R/rulesets/$_id could not be read: $(head -n 1 "$W/err" | cut -c1-100))"; fi
      done
      printf '%s' "$RUL" | jq -e '[.[] | select(.type == "pull_request" and .ruleset_source_type != "Repository")] | length > 0' >/dev/null 2>&1 \
        && fix_ review do "an organisation ruleset also holds a pull_request rule: its owner changes it"
    fi
  fi

  [ -z "$UNDECL" ] || find_ undeclared declaration "no ship.conf or --declared row for:$(printf '%s' "$UNDECL" | sed 's/ /, /g; s/^,//')"
  [ "$(grep -c . "$W/findings" | tr -d ' ')" != "$NF_BEFORE" ] || printf '%s\n' "$R" >> "$W/clean"
}

awk '!seen[$0]++' "$W/targets" > "$W/targets.u"     # a repo two checkouts carry is judged once
while IFS= read -r _t; do judge "$_t"; done < "$W/targets.u"

# ── the report ──────────────────────────────────────────────────────────────
NOW="$(date +%s)"
keyof() { printf '%s|%s|%s' "$1" "$2" "$3"; }
: > "$W/seen.new"
if [ "$MODE" = delta ] && [ -r "$STATE" ]; then cp "$STATE" "$W/seen.old"; else : > "$W/seen.old"; fi
out() { # <line>: every line names its check
  if [ "$MODE" = commands ]; then printf '[check:%s] %s\n' "$ID" "$1" >&2; else printf '[check:%s] %s\n' "$ID" "$1"; fi
}
show_fixes() { # <repo> <key>
  awk -F'\t' -v r="$1" -v k="$2" '$1 == r && $2 == k { print $3 "\t" $4 }' "$W/fixes" | while IFS="$(printf '\t')" read -r _k _c; do
    case "$_k" in run) out "    fix: $_c" ;; *) out "    do (not a command): $_c" ;; esac
  done
}
NNEW=0; NSTAND=0
while IFS="$(printf '\t')" read -r _r _kind _key _detail; do
  _k="$(keyof "$_r" "$_kind" "$_key")"
  _seen="$(awk -F'\t' -v k="$_k" '$1 == k { print $2; exit }' "$W/seen.old")"
  printf '%s\t%s\n' "$_k" "${_seen:-$NOW}" >> "$W/seen.new"
  if [ "$MODE" = delta ] && [ -n "$_seen" ]; then
    NSTAND=$((NSTAND + 1)); out "$_r $_kind $_key: standing $(( (NOW - _seen) / 86400 ))d"
  else
    NNEW=$((NNEW + 1)); out "$_r $_kind $_key: $_detail"; show_fixes "$_r" "$_key"
  fi
done < "$W/findings"
if [ "$MODE" != delta ]; then while IFS= read -r _c; do out "$_c clean"; done < "$W/clean"; fi
NCLEAN="$(grep -c . "$W/clean" | tr -d ' ')"
NUNREAD="$(awk -F'\t' '$2 == "unread" || $2 == "unreadable"' "$W/findings" | grep -c . | tr -d ' ')"
NDRIFT="$(awk -F'\t' '$2 == "drift" || $2 == "undeclared"' "$W/findings" | grep -c . | tr -d ' ')"
out "$NCLEAN clean, $NDRIFT drift or undeclared, $NUNREAD unreadable or unread; $NNEW shown, $NSTAND standing${MODE:+ ($MODE)}"
if [ "$MODE" = commands ]; then awk -F'\t' '$3 == "run" { print $4 }' "$W/fixes"; fi
# delta mode remembers when each finding was first seen; a fixed one drops out
if [ "$MODE" = delta ]; then
  mkdir -p "$(dirname -- "$STATE")" 2>/dev/null && cp "$W/seen.new" "$STATE" 2>/dev/null \
    || printf '[check:%s] could not write %s: every finding will read as new next run\n' "$ID" "$STATE" >&2
fi
[ "$NUNREAD" -eq 0 ] || exit 3
[ "$NDRIFT" -eq 0 ] || exit 1
exit 0
