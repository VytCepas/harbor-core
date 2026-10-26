#!/bin/sh
# check-routes.sh — assert the access register is a checkable instrument, not a diary.
#
# The access register (the private layer's access/, CONTRACTS/access-card.md) holds the route
# documents describing how to reach each system and as whom. Measured 2026-08-29: not one of them carries a runnable check, and
# nothing anywhere runs them. So the `verified:` claim in a route can only ever
# age, and the first thing a session does with a route is re-derive it by hand —
# which is the drip-fed-ask failure the access-ledger skill exists to end.
#
# This asserts the CARD: every route names the account it authorises as, one
# command that proves reach, what that reaches, what it provably cannot, who can
# grant it, and when that was last true. Those five fields are exactly the cells
# a casefile pack row needs (owner / reach / probe / verified), so a pack stops
# re-deriving per case and starts citing the book.
#
#   check-routes.sh [dir]              gate every route card      exit 0/1
#   check-routes.sh --report [dir]     derive the "what we can do today" table
#   check-routes.sh --accounts [dir]   derive ACCOUNTS.md: which account connects to what
#   check-routes.sh --coverage <corpus> [dir]  systems referenced with no route
#   check-routes.sh --probe <cmd> <expect>  one check, one verdict word (harbor access status|rotate)
#   check-routes.sh --self-test        prove it goes RED before trusting it GREEN
#
# WHICH ACCOUNT, AND WITH WHAT ROLE (2026-09-24). A card used to name its
# identity in one prose line, so "what can tools@ reach, and where is it the
# wrong account?" had no answer short of reading all of them, and the role a
# card claimed was text nothing re-read: a role change in a vendor UI moved a personal
# account from viewer to admin on 2026-09-23 and the card stayed green, because its check proved the
# door opens and never who is standing in it. So a card now carries one
# `account:` line per account that touches the system, and a `role-check:` that
# reads the role held, or says `none - <why not>` so the gap stays visible.
#
# BSD userland: `grep` on this box is ugrep and skips gitignored/binary files, so
# every grep here is /usr/bin/grep. No `timeout`. And every whitespace class is
# `[[:blank:]]`, never `[ \t]` — BSD sed reads that bracket as {space, backslash,
# t}, so `s/[ \t]*$//` silently turns `client` into `clien`. Measured: it broke
# the owner enum on the first valid card this checker ever saw. awk is one-true-awk with no
# mktime, so date staleness is done by stripping the dashes off two ISO dates
# and comparing them as integers — total order preserved, no date arithmetic,
# and unlike `[ a \< b ]` it is defined in POSIX sh (shellcheck SC3012).
set -eu

# THE CARD STORE IS PRIVATE DATA (harbor#1149): a card names accounts, so it lives in the private
# layer and core ships the format only. The ONE resolver is `bin/roots.sh --access` ($ACCESS_DIR
# wins); this file never spells the location. With no register the answer is exit 2 and a line saying
# nothing was checked, never a pass: a gate that found no cards and said "ok" would be the vacuous
# green the old ACCESS_DIR row in roots.tsv warned about. An explicit [dir] needs no register.
ACCESS_DIR_DEFAULT=''
register_dir() {
  case "$0" in */*) _rh="${0%/*}" ;; *) _rh=. ;; esac
  _rr="$_rh/../../../bin/roots.sh"   # run from a checkout; an installed copy asks the checkout
  [ -f "$_rr" ] && [ -f "$_rh/../../../CONTRACTS/roots.tsv" ] || _rr="${HARBOR_REPO:-${PORT_ROOT:-$HOME/port}/harbor}/bin/roots.sh"
  if ACCESS_DIR_DEFAULT="$(sh "$_rr" --access)"; then return 0; fi
  printf 'check-routes: no access register, so NOTHING was checked and this is not a pass.\n' >&2
  printf '              Pass a card directory, or create the private layer (harbor scope install, CONTRACTS/private-layer.md).\n' >&2
  exit 2
}
want_dir() { [ -n "${1:-}" ] || register_dir; }   # <the optional [dir] argument>
STALE_DAYS=${ROUTE_STALE_DAYS:-30}

REQUIRED_FIELDS='identity
account
via
upgrade
use
check
expect
role-check
role-expect
grant
owner
reaches
cannot
verified'

# `account:` IS REPEATED, ONE LINE PER ACCOUNT, FOUR `|`-SEPARATED FIELDS:
#
#     account:  <account> | <use> | <role held> | <how to connect>
#
# `use` is the answer to "should I be using this one here?":
#   primary  — use this first. A reachable system must name at least one.
#   fallback — only when the primary has failed; say so when falling back.
#   avoid    — holds access here, but it is not the account to use.
#   none     — measured: no access. Recorded so nobody re-probes it.
#   never    — must not be used here, whatever it holds (Meta locks a role
#              mailbox's profile and every asset on it).
# The role and connect cells are capped so the generated matrix stays readable;
# detail belongs in the card's prose, where it already lives.
ACCOUNT_USES='primary fallback avoid none never'
ACCOUNT_CELL_MAX=${ACCOUNT_CELL_MAX:-90}

rank_of_use() {
  case "$1" in
    primary) printf '1' ;; fallback) printf '2' ;; avoid) printf '3' ;;
    none) printf '4' ;; never) printf '5' ;; *) printf '0' ;;
  esac
}

# The generated files a card directory carries. The gate regenerates each one
# and compares, because DISPATCH.md sat two weeks behind the meta and mcp cards
# (found 2026-09-24) while nothing noticed: a derived file nothing re-derives is
# a hand-written copy with extra steps.
GENERATED='ACCOUNTS.md:--accounts
DISPATCH.md:--dispatch'

# THE DISPATCH LADDER. The operator's standing order is cli or api first, then
# mcp, then browser — and a priority order written only in prose is a wish. So
# `via:` is an ORDERED `>`-separated list of these tiers and the checker rejects
# any card that lists them out of rank. That makes the ladder mechanically true
# of every route rather than true of whichever routes someone remembered.
#
# Why this rank and not another:
#   cli     — a wrapper on this box. Scoped by construction, no token in argv,
#             and it fails loudly. `stape` cannot write because it has no verb.
#   api     — direct REST with a minted token. Same accuracy, more rope: the
#             scope is whatever the credential carries, so it is second.
#   mcp     — a vendor's hosted connector. Real capability, but the grant is
#             all-or-nothing and opaque from here, so it cannot be least-privilege.
#   browser — a human session. Unscoped, unlogged, unrepeatable, and the one
#             tier an agent cannot drive without the operator watching.
#   none    — measured to be unreachable. Valid, and must stay valid: a book
#             that only accepts working routes loses the negative that stops the
#             next session re-probing a closed door.
VIA_TIERS='cli api mcp browser none'

rank_of_tier() {
  case "$1" in
    cli) printf '1' ;; api) printf '2' ;; mcp) printf '3' ;; browser) printf '4' ;;
    none) printf '9' ;; *) printf '0' ;;
  esac
}

# A route that says "TBD" has recorded the intention to have a route.
PLACEHOLDERS='^(tbd|todo|none|n/?a|unknown|\?+|-+)$'

# The directory label and the account drift silently, and the account is the
# wall. A card whose identity is only a role label has recorded the label.
#
# ACCESS/README.md's own example of this — `gcx tools` authorising as
# analytics@example.invalid, measured 2026-08-01 — was re-run on 2026-08-29 and returns
# account=tools@example.invalid. The canonical illustration of drift had drifted. That is
# the reason this field is checked by a command rather than trusted as prose.
# The generic labels are core's; a register's own role directories are its vocabulary.tsv `role` rows (harbor#1273).
ROLE_LABELS_CORE='tools|prod|default|personal|admin'
ROLE_LABELS="^($ROLE_LABELS_CORE)\$"

# Curated vocabulary for --coverage. Derived from the systems this estate is
# measured to touch, not from parsing prose — a name scraped out of a sentence
# is not evidence a system is in use, and a coverage report built on that would
# manufacture work. Extend it deliberately.
#
# The right-hand side is the FILE that covers the name, which is not always a
# file of the same name: several systems can share one card when they share one
# measured fact, because copies of one claim drift.
#
# IT IS THE REGISTER'S DATA, NOT CORE'S (harbor#1273): `<card dir>/vocabulary.tsv`, one row per name,
#   kind TAB pattern TAB card    kind `system` (pattern an ERE alternation, card a card's basename) or
#                                `role` (a role-directory label, card `-`); `#` lines and the header skipped.
# No file is no system vocabulary: --coverage says NOT CHECKED, and the role check keeps the core labels.
SYSTEMS=''
load_vocab() { # <card dir> — sets SYSTEMS and ROLE_LABELS; a row that cannot be read exits 2
  _vf="$1/vocabulary.tsv"
  [ -f "$_vf" ] || return 0
  _vout=$(awk -F'\t' '
    { sub(/\r$/, "") } /^[ \t]*#/ || /^[ \t]*$/ { next }
    !hdr { hdr = 1; if ($0 != "kind\tpattern\tcard") { printf "E\tline %d: the header is not kind, pattern, card\n", FNR; bad = 1 }; next }
    NF != 3 || $2 !~ /^[a-z0-9 &|._-]+$/ || ($1 == "system" && $3 !~ /^[a-z0-9-]+$/) || ($1 == "role" && $3 != "-") || ($1 != "system" && $1 != "role") {
      printf "E\tline %d: expected system TAB <pattern> TAB <card>, or role TAB <label> TAB -\n", FNR; bad = 1; next }
    { printf "%s\t%s\t%s\n", $1, $2, $3 } END { exit bad }' "$_vf") || {
    printf '%s\n' "$_vout" | sed -n "s|^E.|check-routes: $_vf |p" >&2
    printf 'check-routes: the register vocabulary does not read, so NOTHING was checked\n' >&2
    exit 2; }
  SYSTEMS=$(printf '%s\n' "$_vout" | awk -F'\t' '$1 == "system" { print $2 ":" $3 }')
  _vroles=$(printf '%s\n' "$_vout" | awk -F'\t' '$1 == "role" { printf "|%s", $2 }')
  ROLE_LABELS="^($ROLE_LABELS_CORE$_vroles)\$"
}

# NOT every .md in this directory is a route card. Four loops walk the dir and
# each needs the same answer, so the list lives ONCE — it was duplicated until
# 2026-09-02, at which point --dispatch knew about ROUTING.md and DISPATCH.md and
# the gate did not, and the gate spent its exit code failing two prose documents
# for lacking an `identity:` line.
#
# THIRD OCCURRENCE, 2026-09-15. Consolidating the card store into ~/harbor/ACCESS
# carried ACCOUNT-PRECEDENCE.md and ESCALATION.md in with the cards, and the gate
# went to exit 1 on two standing-policy documents for the same missing `identity:`
# line. A guard that fails ordinary content is one that gets switched off
# (CONSTITUTION No.2.11), and the failure mode is structural: this list is the only
# thing separating a card from a document that happens to live beside one, so
# anything added to the directory that is not a route must be added here too.
not_a_card() {
  case "$(basename "$1")" in
    README.md|INDEX.md|CAPABILITIES.md|ROUTING.md|DISPATCH.md|ACCOUNTS.md) return 0 ;;
    ACCOUNT-PRECEDENCE.md|ESCALATION.md|register.md) return 0 ;;
    *) return 1 ;;
  esac
}

usage() {
  printf 'usage: %s [dir]                     gate every route card\n' "$0" >&2
  printf '       %s --report [dir]            derive the capability table\n' "$0" >&2
  printf '       %s --dispatch [dir]          derive the routing rules book\n' "$0" >&2
  printf '       %s --accounts [dir]          derive which account connects to what\n' "$0" >&2
  printf '       %s --coverage <corpus> [dir] systems referenced with no route\n' "$0" >&2
  printf '       %s --run [dir]               ACTUALLY RUN every check: (opt-in)\n' "$0" >&2
  printf '       %s --probe <cmd> <expect>    run ONE check: one verdict word, never its output\n' "$0" >&2
  printf '       %s --classify <cmd> <expect> what kind of check it is, running nothing\n' "$0" >&2
  printf '       %s --self-test               prove it goes RED first\n' "$0" >&2
  exit 2
}

# Field values live in an indented block under the H1 so the file still reads as
# prose. `^ *field:` and nothing looser — a mention of "verified:" mid-paragraph
# must not satisfy the card, or the checker becomes the rubber stamp it replaces.
field_of() {
  /usr/bin/grep -m1 -iE "^[[:blank:]]*$2:" "$1" 2>/dev/null \
    | sed -e 's/^[^:]*://' -e 's/^[[:blank:]]*//' -e 's/[[:blank:]]*$//' || true
}

# Every `account:` line of a card, one value per line. field_of stops at the
# first match, which is right for every other field and wrong for this one.
accounts_of() {
  /usr/bin/grep -iE '^[[:blank:]]*account:' "$1" 2>/dev/null \
    | sed -e 's/^[^:]*://' -e 's/^[[:blank:]]*//' -e 's/[[:blank:]]*$//' || true
}

# Field <n> of an account line, trimmed. awk, not sed, for the trim: BSD sed
# reads `[ \t]` as {space, backslash, t} (see the header), awk does not.
acct_field() {
  printf '%s\n' "$1" | awk -F'|' -v n="$2" '{ v = $n; gsub(/^[ \t]+|[ \t]+$/, "", v); print v }'
}

# The top tier a card's `via:` names — `none` for a system measured unreachable.
top_tier() {
  _tt=$(field_of "$1" via); _tt=${_tt%%[>,]*}
  printf '%s' "$_tt" | tr -d '[:blank:]'
}

check_accounts() { # <card> — appends to _rbad
  _aseen=' '; _aprim=0
  _alines=$(accounts_of "$1")
  while IFS= read -r _al; do
    [ -n "$_al" ] || continue
    _anf=$(printf '%s\n' "$_al" | awk -F'|' '{ print NF }')
    if [ "$_anf" -ne 4 ]; then
      _rbad="${_rbad}${_rbad:+
}       \`account: $_al\` has $_anf field(s) — the shape is \`<account> | <use> | <role held> | <how to connect>\`"
      continue
    fi
    _aa=$(acct_field "$_al" 1); _au=$(acct_field "$_al" 2 | tr '[:upper:]' '[:lower:]')
    _ar=$(acct_field "$_al" 3); _ac=$(acct_field "$_al" 4)
    if [ -z "$_aa" ] || printf '%s' "$_aa" | /usr/bin/grep -qiE "$ROLE_LABELS|$PLACEHOLDERS"; then
      _rbad="${_rbad}${_rbad:+
}       \`account: $_al\` names \"$_aa\" — a role label or a placeholder, not the account that authorises"
    fi
    case "$_au" in
      primary) _aprim=$((_aprim + 1)) ;;
      fallback|avoid|none|never) ;;
      *) _rbad="${_rbad}${_rbad:+
}       \`account: $_aa\` has use \"$_au\" — must be one of: $ACCOUNT_USES" ;;
    esac
    if [ -z "$_ar" ]; then
      _rbad="${_rbad}${_rbad:+
}       \`account: $_aa\` names no role — say what it holds, or \`none\`"
    elif [ "${#_ar}" -gt "$ACCOUNT_CELL_MAX" ]; then
      _rbad="${_rbad}${_rbad:+
}       \`account: $_aa\` role is ${#_ar} characters, over $ACCOUNT_CELL_MAX — the matrix cell has to be readable; move the detail into the prose"
    fi
    if [ -z "$_ac" ]; then
      _rbad="${_rbad}${_rbad:+
}       \`account: $_aa\` says nothing about how to connect — the command or login, or \`-\` when it holds nothing"
    elif [ "${#_ac}" -gt "$ACCOUNT_CELL_MAX" ]; then
      _rbad="${_rbad}${_rbad:+
}       \`account: $_aa\` connect cell is ${#_ac} characters, over $ACCOUNT_CELL_MAX"
    fi
    case "$_aseen" in
      *" $_aa |"*) _rbad="${_rbad}${_rbad:+
}       \`account: $_aa\` appears twice — one line per account, with its strongest use" ;;
    esac
    _aseen="$_aseen $_aa |"
  done <<EOF
$_alines
EOF
  # A system something can reach must say which account to reach it WITH. That
  # is the question this field exists for; a card of only fallbacks answers it
  # the way a map of only detours does.
  if [ "$(top_tier "$1")" != none ] && [ "$_aprim" -eq 0 ]; then
    _rbad="${_rbad}${_rbad:+
}       no \`account:\` is \`primary\` — a reachable system must name the account to use first"
  fi
}

check_card() {
  _rf=$1
  _rname=$(basename "$_rf" .md)
  _rbad=''

  for _fld in $REQUIRED_FIELDS; do
    _val=$(field_of "$_rf" "$_fld")
    if [ -z "$_val" ]; then
      _rbad="${_rbad}${_rbad:+
}       no \`$_fld:\` line"
      continue
    fi
    case "$_fld" in
      account) check_accounts "$_rf" ;;
      role-check)
        # A role that is only prose is the Flow miss again. So either a READ of
        # the role, whose `role-expect:` names the literal it must print — or
        # `none` with the reason no machine can read it, which keeps the gap on
        # the page instead of letting it look covered.
        if printf '%s' "$_val" | /usr/bin/grep -qiE '^none([[:blank:]]|$)'; then
          if ! printf '%s' "$_val" | /usr/bin/grep -qiE '^none[[:blank:]]*(-|:|—)[[:blank:]]*[^[:blank:]]'; then
            _rbad="${_rbad}${_rbad:+
}       \`role-check: none\` gives no reason — say why the role cannot be read by a machine"
          fi
        elif ! field_of "$_rf" role-expect | /usr/bin/grep -q '`[^`][^`]*`'; then
          _rbad="${_rbad}${_rbad:+
}       \`role-expect:\` carries no backticked literal — a role check with nothing to match can never fail"
        fi ;;
      check)
        if printf '%s' "$_val" | /usr/bin/grep -qiE "$PLACEHOLDERS"; then
          _rbad="${_rbad}${_rbad:+
}       \`check:\` is a placeholder — a route with no runnable check cannot be re-verified"
        fi ;;
      identity)
        if printf '%s' "$_val" | /usr/bin/grep -qiE "$ROLE_LABELS"; then
          _rbad="${_rbad}${_rbad:+
}       \`identity:\` names a role-directory label, not the account it authorises as"
        fi ;;
      via)
        # Ordered, deduplicated, drawn from the enum, and — the point of the
        # field — in ascending rank. `browser > cli` is REJECTED even though
        # both tiers are real, because a card that lists the human session ahead
        # of the wrapper has documented a habit, not a policy.
        _vprev=0
        for _vt in $(printf '%s' "$_val" | tr '>,' '  '); do
          _vr=$(rank_of_tier "$_vt")
          if [ "$_vr" -eq 0 ]; then
            _rbad="${_rbad}${_rbad:+
}       \`via:\` names \"$_vt\" — must be one of: $VIA_TIERS"
            continue
          fi
          if [ "$_vr" -le "$_vprev" ]; then
            _rbad="${_rbad}${_rbad:+
}       \`via:\` is out of priority order at \"$_vt\" — the ladder is cli > api > mcp > browser"
          fi
          if [ "$_vr" -eq 9 ] && [ "$_vprev" -ne 0 ]; then
            _rbad="${_rbad}${_rbad:+
}       \`via: none\` means unreachable and cannot be listed beside a working tier"
          fi
          _vprev=$_vr
        done
        if [ "$_vprev" -eq 0 ]; then
          _rbad="${_rbad}${_rbad:+
}       \`via:\` lists no tier at all"
        fi ;;
      upgrade)
        # `via:` says what works TODAY. On its own that hides the question an
        # operator actually asks — "can we get more of this over CLI or API?" —
        # and the answer was wrong three times when it was left to prose:
        # Shopify has an Admin API (app creation moved to the Dev Dashboard),
        # LinkedIn's app ALREADY holds Advertising API Development Tier, and a CLI
        # was sitting in a project venv the whole time while the book called it absent.
        #
        # So every card names the tier it could reach and the grant that would
        # get it there — or says `none` and why this tier is the ceiling. A row
        # claiming an upgrade to a tier no better than the one it already has is
        # rejected: that is a wish recorded as a plan.
        _uwant=${_val%%:*}
        _uwant=$(printf '%s' "$_uwant" | tr -d '[:blank:]')
        _ur=$(rank_of_tier "$_uwant")
        if [ "$_ur" -ne 0 ] && [ "$_ur" -ne 9 ]; then
          _utop=$(field_of "$_rf" via); _utop=${_utop%%[>,]*}
          _utop=$(printf '%s' "$_utop" | tr -d '[:blank:]')
          _ucur=$(rank_of_tier "$_utop")
          # AT or above, not strictly above. One system is already `cli` and its open
          # item is a publish scope — a real, documented scope this box
          # simply does not hold. That is an upgrade in capability at the same
          # tier, and a rule demanding a strictly better tier would have forced
          # that row to lie with `none`. Only a DOWNGRADE is a wish.
          if [ "$_ucur" -ne 0 ] && [ "$_ur" -gt "$_ucur" ]; then
            _rbad="${_rbad}${_rbad:+
}       \`upgrade: $_uwant\` is BELOW the \`via:\` tier already held — an upgrade never moves the row down the ladder"
          fi
        elif ! printf '%s' "$_val" | /usr/bin/grep -qiE '^none([[:blank:]]|$)'; then
          _rbad="${_rbad}${_rbad:+
}       \`upgrade:\` must start with a tier and a colon (\`api: <the grant>\`) or with \`none\` and the reason this tier is the ceiling"
        fi ;;
      use)
        # The first move, spelled out. A dispatch table whose top row says "cli"
        # and does not say WHICH command sends the reader back into the prose,
        # and the prose is the half that drifts.
        if printf '%s' "$_val" | /usr/bin/grep -qiE "$PLACEHOLDERS"; then
          _rbad="${_rbad}${_rbad:+
}       \`use:\` is a placeholder — name the exact command or URL to reach for first"
        fi ;;
      owner)
        if ! printf '%s' "$_val" | /usr/bin/grep -qiE '^(us|client|vendor|unknown)$'; then
          _rbad="${_rbad}${_rbad:+
}       \`owner:\` is \"$_val\" — must be one of us|client|vendor|unknown"
        fi ;;
      verified)
        if ! printf '%s' "$_val" | /usr/bin/grep -qE '^20[0-9]{2}-[01][0-9]-[0-3][0-9]$'; then
          _rbad="${_rbad}${_rbad:+
}       \`verified:\` is \"$_val\" — must be one ISO date"
        elif [ "$(printf '%s' "$_val" | tr -d -)" -lt "$(printf '%s' "$CUTOFF" | tr -d -)" ]; then
          _rbad="${_rbad}${_rbad:+
}       \`verified: $_val\` is older than $STALE_DAYS days — re-run \`check:\` or say it is carried"
        fi ;;
    esac
  done

  if [ -n "$_rbad" ]; then
    printf 'FAIL %s\n%s\n' "$_rname" "$_rbad"
    rc=1
  else
    printf 'ok   %s\n' "$_rname"
  fi
}

cutoff_date() {
  # BSD -v, else GNU -d: the old today-fallback made every card stale on Linux (harbor#865).
  date -v-"${STALE_DAYS}"d +%Y-%m-%d 2>/dev/null || date -d "-${STALE_DAYS} days" +%Y-%m-%d 2>/dev/null ||
    date +%Y-%m-%d
}

gate_dir() {
  _gdir=$1
  [ -d "$_gdir" ] || { printf 'FAIL %s does not exist — the access register is the deliverable, not an optional extra\n' "$_gdir"; exit 1; }
  load_vocab "$_gdir"
  _gn=0
  for _gf in "$_gdir"/*.md; do
    [ -f "$_gf" ] || continue
    not_a_card "$_gf" && continue
    check_card "$_gf"
    _gn=$((_gn + 1))
  done
  printf '%s route card(s) checked\n' "$_gn"
  [ "$_gn" -gt 0 ] || { printf 'FAIL no route cards found in %s\n' "$_gdir"; exit 1; }
  check_generated "$_gdir"
}

# A generated file that is PRESENT must equal what the cards generate today. The
# `Derived from ... on <date>` line is the one line allowed to differ: a date is
# not drift. An ABSENT file is not failed here — the fixture books in the
# self-test have none — so the repo's own suite asserts presence separately.
check_generated() {
  _cgdir=$1
  # A heredoc, not a pipe: a `| while` loop runs in a subshell and cannot set rc
  # — the trap lint-conventions.sh records three times for CLI1.
  while IFS=: read -r _cgname _cgflag; do
    [ -n "$_cgname" ] || continue
    [ -f "$_cgdir/$_cgname" ] || continue
    _cgnew=$(sh "$0" "$_cgflag" "$_cgdir" 2>/dev/null | /usr/bin/grep -v '^Derived from `' || true)
    _cgold=$(/usr/bin/grep -v '^Derived from `' "$_cgdir/$_cgname" || true)
    if [ "$_cgnew" = "$_cgold" ]; then
      printf 'ok   %s is current\n' "$_cgname"
    else
      printf 'FAIL %s is stale against the cards — regenerate:\n       sh %s %s %s > %s/%s\n' \
        "$_cgname" "$0" "$_cgflag" "$_cgdir" "$_cgdir" "$_cgname"
      rc=1
    fi
  done <<EOF
$GENERATED
EOF
}

# --report: the "what could be done today" view, DERIVED. Doctrine forbids a
# hand-written copy of a fact that lives elsewhere; this regenerates from the
# cards so it cannot drift into disagreeing with them.
report_dir() {
  _pdir=$1
  printf '<!-- generated by check-routes.sh — do not edit; edit the route cards -->\n\n'
  printf '# What we can reach today\n\n'
  printf 'Derived from `%s` on %s. A row is only as true as its `verified:` date.\n\n' "$_pdir" "$(date +%Y-%m-%d)"
  printf '| system | authorises as | owner | can do | provably cannot | verified |\n'
  printf '|---|---|---|---|---|---|\n'
  for _pf in "$_pdir"/*.md; do
    [ -f "$_pf" ] || continue
    not_a_card "$_pf" && continue
    printf '| %s | %s | %s | %s | %s | %s |\n' \
      "$(basename "$_pf" .md)" \
      "$(field_of "$_pf" identity)" \
      "$(field_of "$_pf" owner)" \
      "$(field_of "$_pf" reaches)" \
      "$(field_of "$_pf" cannot)" \
      "$(field_of "$_pf" verified)"
  done
}

# --dispatch: THE RULES BOOK, derived. One row per system, ordered by how good
# its best route is, so the table itself reads as the standing instruction:
# everything above the browser block is something to do without asking, and
# everything in it needs a human.
#
# Hand-writing this table was the alternative and it is the one failure this
# directory has already had twice — ACCESS/README.md's worked example and the
# skill's own card count both drifted while still reading correctly. A copy of a
# fact is a fact with an expiry date nobody wrote down.
dispatch_dir() {
  _ddir=$1
  printf '<!-- generated by check-routes.sh --dispatch — do not edit; edit the route cards -->\n\n'
  printf '# Dispatch — how to reach each system, in priority order\n\n'
  printf 'Derived from `%s` on %s.\n\n' "$_ddir" "$(date +%Y-%m-%d)"
  printf 'The ladder is **cli > api > mcp > browser**. Take the leftmost tier a row\n'
  printf 'offers; drop a tier only when the one above it has actually failed, and say\n'
  printf 'so when you do. `check-routes.sh` rejects any card that lists them out of order.\n\n'
  printf 'The last column is the answer to "can we get more of this over CLI or API?"\n'
  printf 'It is a checked field, not a hope: a card may not claim an upgrade to a tier\n'
  printf 'BELOW the one it already holds.\n\n'
  printf '| system | via | first move | could reach, and what unlocks it | verified |\n'
  printf '|---|---|---|---|---|\n'
  for _df in "$_ddir"/*.md; do
    [ -f "$_df" ] || continue
    not_a_card "$_df" && continue
    _dvia=$(field_of "$_df" via)
    _dtop=${_dvia%%[>,]*}
    _dtop=$(printf '%s' "$_dtop" | tr -d '[:blank:]')
    printf '%s\t| %s | %s | %s | %s | %s |\n' \
      "$(rank_of_tier "$_dtop")" \
      "$(basename "$_df" .md)" \
      "$_dvia" \
      "$(field_of "$_df" use)" \
      "$(field_of "$_df" upgrade)" \
      "$(field_of "$_df" verified)"
  done | LC_ALL=C sort -n | cut -f2-
}

# --accounts: THE SAME FACTS, TURNED ROUND. Every other view here is one row per
# system, and the failure it leaves open is the one an agent actually has: it is
# holding an account and does not know whether that account is the right one,
# the wrong one, or one that already has more than enough. So this is one column
# per account, a cell per system, and then one table per account. DERIVED, like
# --dispatch, and the gate fails a checked-in copy that no longer matches.
use_cell() { # <use> <role> — one matrix cell
  case "$1" in
    primary)  printf '**primary** · %s' "$2" ;;
    fallback) printf 'fallback · %s' "$2" ;;
    avoid)    printf 'avoid · %s' "$2" ;;
    none)     printf '✗ no access' ;;
    never)    printf '⛔ never · %s' "$2" ;;
  esac
}

accounts_dir() {
  _adir=$1
  _atmp=$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")
  for _af in "$_adir"/*.md; do
    [ -f "$_af" ] || continue
    not_a_card "$_af" && continue
    _asys=$(basename "$_af" .md)
    _arc=$(field_of "$_af" role-check)
    case "$_arc" in
      [Nn][Oo][Nn][Ee]*|'') _arc='not read' ;;
      *) if printf '%s' "$_arc" | /usr/bin/grep -qE "$BROWSER_CHECK"; then _arc=browser; else _arc=machine; fi ;;
    esac
    accounts_of "$_af" | while IFS= read -r _al; do
      [ -n "$_al" ] || continue
      # system, account, use, role, connect, role-check kind — tab-separated.
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$_asys" \
        "$(acct_field "$_al" 1)" "$(acct_field "$_al" 2 | tr '[:upper:]' '[:lower:]')" \
        "$(acct_field "$_al" 3 | tr '|' '/')" "$(acct_field "$_al" 4 | tr '|' '/')" "$_arc"
    done
  done > "$_atmp"

  # Every sort here pins C collation: under a UTF-8 locale `Zed` sorts after `alpha`, and the
  # gate then calls a current file stale (harbor#1273).
  # Columns: every account that touches three or more systems, busiest first.
  # The rest are real, just rare, and a column per rare account would push the
  # table off the screen — they share the last column instead.
  _acols=$(cut -f2 "$_atmp" | LC_ALL=C sort | uniq -c | LC_ALL=C sort -k1,1nr -k2 \
    | awk '$1 >= 3 { sub(/^[ \t]*[0-9]+[ \t]/, ""); print }')

  printf '<!-- generated by check-routes.sh --accounts — do not edit; edit the `account:` lines in the route cards -->\n\n'
  printf '# Accounts — which account connects to what\n\n'
  printf 'Derived from `%s` on %s.\n\n' "$_adir" "$(date +%Y-%m-%d)"
  printf 'Before using an account on a system, read its cell. The route card is `<system>.md`\n'
  printf 'beside this file, and it carries the check that proves the row. `check-routes.sh`\n'
  printf 'fails when this file stops matching the cards.\n\n'
  printf '| use | meaning |\n|---|---|\n'
  printf '| **primary** | use this account first |\n'
  printf '| fallback | only when the primary has failed; say so when falling back |\n'
  printf '| avoid | holds access here, but it is not the account to use |\n'
  printf '| ✗ no access | measured: this account reaches nothing here, so do not re-probe it |\n'
  printf '| ⛔ never | must not be used here, whatever it holds |\n'
  printf '| *(blank)* | not recorded on the card: unknown, which is not the same as none |\n\n'
  printf '**Role checked** says how `check-routes.sh --run` reads the role: by `machine`; by an\n'
  printf 'agent in the `browser` (Claude in Chrome), for which the run prints the page and what it must\n'
  printf 'show; or `not read`, where the card says why.\n\n'

  printf '## At a glance\n\n'
  printf '| system'
  printf '%s\n' "$_acols" | while IFS= read -r _c; do if [ -n "$_c" ]; then printf ' | %s' "$_c"; fi; done
  printf ' | other accounts | role checked |\n|---'
  printf '%s\n' "$_acols" | while IFS= read -r _c; do if [ -n "$_c" ]; then printf '|---'; fi; done
  printf '|---|---|\n'
  for _asys in $(cut -f1 "$_atmp" | LC_ALL=C sort -u); do
    printf '| %s' "$_asys"
    printf '%s\n' "$_acols" | while IFS= read -r _c; do
      [ -n "$_c" ] || continue
      _row=$(awk -F'\t' -v s="$_asys" -v a="$_c" '$1 == s && $2 == a' "$_atmp" | head -1)
      if [ -n "$_row" ]; then
        printf ' | %s' "$(use_cell "$(printf '%s' "$_row" | cut -f3)" "$(printf '%s' "$_row" | cut -f4)")"
      else
        printf ' | '
      fi
    done
    _other=$(awk -F'\t' -v s="$_asys" -v cols="$(printf '%s\n' "$_acols" | tr '\n' '\001')" '
      BEGIN { n = split(cols, c, "\001"); for (i = 1; i <= n; i++) if (c[i] != "") iscol[c[i]] = 1 }
      $1 == s && !($2 in iscol) { printf "%s%s (%s)", sep, $2, $3; sep = "; " }' "$_atmp")
    printf ' | %s | %s |\n' "$_other" "$(awk -F'\t' -v s="$_asys" '$1 == s { print $6; exit }' "$_atmp")"
  done

  printf '\n## By account\n\n'
  printf 'Every account any card names, busiest first. Within one, the systems it should\n'
  printf 'be used for come first and the ones it must not be used for come last.\n'
  cut -f2 "$_atmp" | LC_ALL=C sort | uniq -c | LC_ALL=C sort -k1,1nr -k2 | awk '{ sub(/^[ \t]*[0-9]+[ \t]/, ""); print }' \
    | while IFS= read -r _acct; do
      printf '\n### %s\n\n| system | use | role held | connect with |\n|---|---|---|---|\n' "$_acct"
      awk -F'\t' -v a="$_acct" '$2 == a' "$_atmp" | while IFS="$(printf '\t')" read -r _s _a _u _r _c _k; do
        printf '%s\t| %s | %s | %s | %s |\n' "$(rank_of_use "$_u")" "$_s" "$_u" "$_r" "$_c"
      done | LC_ALL=C sort -t"$(printf '\t')" -k1,1n -k2 | cut -f2-
    done
  rm -f "$_atmp"
}

# --coverage: a system this estate demonstrably works on, with no route, is the
# ask nobody has consolidated yet. Reports; never fails the gate, because an
# unwritten route is a backlog item and a guard that fires on backlog gets
# switched off.
coverage_dir() {
  _ccorp=$1
  _cdir=$2
  # AN UNREADABLE CORPUS IS NOT FULL COVERAGE. Every GAP line comes from a grep
  # over $_ccorp; point this at a path that does not exist and grep matches
  # nothing, no GAP is printed, and the caller reads "no system referenced
  # without a card". Measured 2026-09-05: `--coverage /nonexistent` returned
  # exit 0 and zero GAPs, and the data-estate repo's bin/access-status.sh counted those zero
  # GAPs and reported GOOD "coverage". "Never fails the gate" above is about a
  # BACKLOG item, which an absent corpus is not.
  [ -d "$_ccorp" ] || {
    printf "check-routes: corpus %s is not a readable directory — NOT CHECKED, this is not full coverage\n" "$_ccorp" >&2
    return 2
  }
  [ -d "$_cdir" ] || {
    printf "check-routes: card directory %s does not exist — NOT CHECKED\n" "$_cdir" >&2
    return 2
  }
  load_vocab "$_cdir"
  [ -n "$SYSTEMS" ] || {
    printf "check-routes: no system rows in %s/vocabulary.tsv — NOT CHECKED, this is not full coverage\n" "$_cdir" >&2
    return 2
  }
  printf 'coverage of %s against %s\n' "$_cdir" "$_ccorp"
  printf '%s\n' "$SYSTEMS" | while IFS= read -r _crow; do
    [ -n "$_crow" ] || continue
    _cpat=${_crow%%:*}
    _cfile=${_crow##*:}
    [ -f "$_cdir/$_cfile.md" ] && continue
    _cn=$(/usr/bin/grep -rilE "$_cpat" --include='*.md' "$_ccorp" 2>/dev/null | wc -l | tr -d ' ')
    [ "$_cn" -gt 0 ] || continue
    printf '  GAP  %-16s referenced in %3s file(s), no %s.md\n' "${_cpat%%|*}" "$_cn" "$_cfile"
  done
}

# ------------------------------------------------------------------- --run
# The SUBSTANCE half. `gate_dir` asserts a card HAS a check; it never runs one,
# so a route can be dead while its card reads green. Measured 2026-08-29 on
# ACCESS/gcloud.md: `check: gcx tools true` printed the expected account and
# exited 0, while a real warehouse read on the same identity failed with
# `Reauthentication failed`. The probe must exercise the path the caller does
# (Helm No.2.6) and `true` exercises nothing. This is the same structural gap
# check-topology.sh has against headings, and it gets the same answer: a second
# mode, deliberately separate, so neither drifts into a private definition of
# the other.
#
# OPT-IN, NEVER THE DEFAULT GATE. A `check:` line is a shell string living in a
# tracked, agent-editable file, so running one is an execution surface. Three
# controls, all required and none of them optional:
#   1. --run is explicit; no other mode of this script executes anything.
#   2. every command is PRINTED before it runs.
#   3. a check that is not a read is REFUSED unrun.
# There is no `timeout` in this userland, so a check that hangs hangs the run.
# Keep every check to one short read — that is what the deny-list enforces.
WRITE_VERBS='(^|[;&|[:blank:]])(rm|rmdir|mv|cp|dd|kill|shutdown|reboot|tee|touch|mkdir|chmod|chown|ln)[[:blank:]]|-X[[:blank:]]*(POST|PUT|PATCH|DELETE)|--request[[:blank:]]*(POST|PUT|PATCH|DELETE)|curl[^;&|]*[[:blank:]](-d|--data[a-z-]*|-F|--form|-T|--upload-file)[[:blank:]=]|(^|[;&|[:blank:]])git[[:blank:]]+push[[:blank:]]|auth[[:blank:]]+(login|revoke)|(delete|destroy|drop|revoke|truncate|publish|deploy|update|insert|create)[[:blank:]]|>[[:blank:]]*[^|&[:blank:]]'

# A check that needs a human eye is not machine-runnable. `open` puts a window on
# the operator's screen; that is a manual verification and is reported as one,
# never as a pass.
MANUAL_VERBS='(^|[;&|[:blank:]])(open|say|osascript|ssh)[[:blank:]]'

# Except a URL to look at, which is not a person's job. `open <https URL>` is run
# by an AGENT through Claude in Chrome: navigate, compare the page with `expect:`,
# date the card on a match. So it is reported as that agent's work item, with the
# expectation printed beside it, and never as a pass. A login wall is the finding;
# signing in stays the operator's, because an agent never types a password.
# Measured 2026-09-24: all 7 browser-only cards were checked this way in one pass.
BROWSER_CHECK='^[[:blank:]]*open[[:blank:]]+https?://'

# What the output must contain is every BACKTICKED span of `expect:`. That keeps
# `expect:` readable prose for a human and machine-comparable at the same time,
# without a ninth field. A card whose expect carries no backticks is reported
# UNCHECKABLE — not passed. Silence about what cannot be verified is the failure
# this whole file exists to end.
# One probe: print it, refuse it if it writes, and match every backticked
# literal of its expectation. Sets _pv to pass|fail|refused|browser|manual|uncheckable.
# Used for `check:` (reach) and `role-check:` (the role held), so the two can
# never grow different ideas of what a read is.
probe_lits() { printf '%s' "$1" | tr '`' '\n' | awk 'NR % 2 == 0' | /usr/bin/grep -v '^[[:blank:]]*$' || true; }

# What kind of probe a command is, before anything runs: refused | browser | manual | uncheckable | run.
# Sets _plits to the backticked literals of <expect>. The one classifier for run_probe and probe_one
# (`harbor access status` and `rotate`), so a register entry and a card share one idea of what a read is.
probe_class() { # <cmd> <expect>
  # Strip the redirections that are part of ordinary READ hygiene before
  # testing for writes. `>/dev/null` and `2>&1` appear in almost every honest
  # check — a token check that discards its own output most of all — and a
  # guard that refuses ordinary work is a guard that gets switched off
  # (Helm No.2.11). Only a redirection that lands somewhere real survives this.
  _pprobe=$(printf '%s' "$1" \
    | sed -e 's|[0-9]*>&[0-9]*||g' -e 's|[0-9]*>[[:blank:]]*/dev/null||g')
  _plits=$(probe_lits "$2")
  if printf '%s' "$_pprobe" | /usr/bin/grep -qE "$WRITE_VERBS"; then echo refused
  elif printf '%s' "$1" | /usr/bin/grep -qE "$BROWSER_CHECK"; then echo browser
  elif printf '%s' "$1" | /usr/bin/grep -qE "$MANUAL_VERBS"; then echo manual
  elif [ -z "$_plits" ]; then echo uncheckable
  else echo run; fi
}

# The literals of <expect> that <output> does not contain, one per line; empty is a match.
probe_missing() { # <output> <literals>
  while IFS= read -r _pl; do
    [ -n "$_pl" ] || continue
    printf '%s' "$1" | /usr/bin/grep -qF -- "$_pl" || printf '%s\n' "$_pl"
  done <<EOF
$2
EOF
}

run_probe() { # <label> <cmd> <expect>
  _plbl=$1; _pcmd=$2; _pexp=$3
  printf '   %s$ %s\n' "$_plbl" "$_pcmd"
  _pk=$(probe_class "$_pcmd" "$_pexp")
  _plits=$(probe_lits "$_pexp")
  case "$_pk" in
    refused) printf '   %sREFUSED      not a read — a route card documents reach, not a change\n' "$_plbl"; _pv=refused; return 0 ;;
    browser) printf '   %sBROWSER      for an agent in Chrome; the page must show: %s\n' "$_plbl" "$_pexp"; _pv=browser; return 0 ;;
    manual) printf '   %sMANUAL       needs a human eye; run it yourself, then date the card\n' "$_plbl"; _pv=manual; return 0 ;;
    uncheckable) printf '   %sUNCHECKABLE  `expect:` carries no backticked literal to match on\n' "$_plbl"; _pv=uncheckable; return 0 ;;
  esac
  _pout=$(sh -c "$_pcmd" 2>&1 || true)
  _pmiss=$(probe_missing "$_pout" "$_plits")
  [ -z "$_pmiss" ] || _pmiss="$_pmiss
"
  if [ -n "$_pmiss" ]; then
    printf '   %sFAIL         output does not contain:\n' "$_plbl"
    printf '%s' "$_pmiss" | sed 's/^/                  /'
    printf '   ── first 4 lines of what it did print ──\n'
    printf '%s\n' "$_pout" | head -4 | sed 's/^/                  /'
    _pv=fail
  else
    printf '   %spass\n' "$_plbl"
    _pv=pass
  fi
}

# One probe for `harbor access status|rotate`: prints ONE verdict word and never the probe's output, which a
# failing CLI can fill with its own credential. No `timeout` on macOS, so a watchdog: the probe runs in the
# background and is killed (its direct children first) after PROBE_TIMEOUT seconds, default 30.
# Exit 0 pass, 1 fail|timeout|refused, 3 browser|manual|uncheckable (not machine-decidable).
probe_one() { # <cmd> <expect>
  _ok=$(probe_class "$1" "$2")
  case "$_ok" in
    refused) echo refused; return 1 ;;
    browser|manual|uncheckable) echo "$_ok"; return 3 ;;
  esac
  _olits=$(probe_lits "$2")
  _od=$(mktemp -d "${TMPDIR:-/tmp}/harbor.XXXXXX")
  _op=''
  trap 'rm -rf "$_od"' EXIT
  # An interrupt ends the probe too, rather than leaving it running past a caller that has given up.
  # Every call `|| :`: under set -e a pkill that matches no child would end the trap before the kill and the exit.
  trap '[ -z "$_op" ] || { pkill -TERM -P "$_op" 2>/dev/null || :; kill -TERM "$_op" 2>/dev/null || :; }; rm -rf "$_od"; exit 130' INT TERM HUP
  sh -c "$1" > "$_od/out" 2>&1 < /dev/null &
  _op=$!; _ot=0; _olim=${PROBE_TIMEOUT:-30}
  while kill -0 "$_op" 2>/dev/null; do
    if [ "$_ot" -ge "$_olim" ]; then
      pkill -TERM -P "$_op" 2>/dev/null || :
      kill -TERM "$_op" 2>/dev/null || :
      wait "$_op" 2>/dev/null || :
      echo timeout; return 1
    fi
    sleep 1; _ot=$((_ot + 1))
  done
  wait "$_op" 2>/dev/null || :
  if [ -z "$(probe_missing "$(cat "$_od/out")" "$_olits")" ]; then echo pass; return 0; fi
  echo fail; return 1
}

run_dir() {
  _xdir=$1
  [ -d "$_xdir" ] || { printf 'FAIL %s does not exist\n' "$_xdir"; exit 1; }
  _xn=0; _xp=0; _xf=0; _xs=0; _xb=0
  _yn=0; _yp=0; _yf=0; _yh=0; _yb=0
  printf 'running every route check in %s\n' "$_xdir"
  printf 'read-only, each command shown before it runs, writes refused unrun\n\n'
  for _xfile in "$_xdir"/*.md; do
    [ -f "$_xfile" ] || continue
    not_a_card "$_xfile" && continue
    _xname=$(basename "$_xfile" .md)
    _xcmd=$(field_of "$_xfile" check)
    if [ -z "$_xcmd" ]; then
      printf 'skip %-11s no `check:` line — the default gate names this already\n' "$_xname"
      _xs=$((_xs + 1)); continue
    fi
    printf '── %s\n' "$_xname"
    run_probe '' "$_xcmd" "$(field_of "$_xfile" expect)"
    case "$_pv" in
      pass) _xn=$((_xn + 1)); _xp=$((_xp + 1)) ;;
      fail) _xn=$((_xn + 1)); _xf=$((_xf + 1)); rc=1 ;;
      refused) _xf=$((_xf + 1)); rc=1 ;;
      browser) _xb=$((_xb + 1)) ;;
      *) _xs=$((_xs + 1)) ;;
    esac
    # THE ROLE, read separately from the reach. A door that opens says nothing
    # about who is standing in it; this is the half that would have caught the
    # Flow viewer-to-admin change the day it happened.
    _ycmd=$(field_of "$_xfile" role-check)
    case "$_ycmd" in
      '') ;;
      [Nn][Oo][Nn][Ee]*) printf '   role: not read — %s\n' "$_ycmd"; _yh=$((_yh + 1)) ;;
      *)
        run_probe 'role: ' "$_ycmd" "$(field_of "$_xfile" role-expect)"
        case "$_pv" in
          pass) _yn=$((_yn + 1)); _yp=$((_yp + 1)) ;;
          fail) _yn=$((_yn + 1)); _yf=$((_yf + 1)); rc=1 ;;
          refused) _yf=$((_yf + 1)); rc=1 ;;
          browser) _yb=$((_yb + 1)) ;;
          *) _yh=$((_yh + 1)) ;;
        esac ;;
    esac
    printf '\n'
  done
  printf 'route checks: %s run, %s passed, %s failed, %s for an agent in the browser, %s not machine-checkable\n' \
    "$_xn" "$_xp" "$_xf" "$_xb" "$_xs"
  printf 'role checks:  %s run, %s passed, %s failed, %s for an agent in the browser, %s not read (the card says why)\n' \
    "$_yn" "$_yp" "$_yf" "$_yb" "$_yh"
}

# ---------------------------------------------------------------- self-test
VALID_CARD='# meta — Meta business portfolio

    identity: analytics@example.invalid via a named human profile
    account:  analytics@example.invalid | primary | ads_read on business 1234567 | a named human profile in the browser
    account:  tools@example.invalid | none | no asset assigned | -
    via:      api > browser
    upgrade:  none - the connector grant is all-or-nothing and cannot be narrowed
    use:      curl -sS -H "Authorization: Bearer $TOK" https://graph.facebook.com/v21.0/me
    check:    curl -sS -H "Authorization: Bearer $TOK" https://graph.facebook.com/v21.0/me
    expect:   a JSON object carrying an id, not an OAuthException
    role-check: curl -sS -H "Authorization: Bearer $TOK" https://graph.facebook.com/v21.0/me/permissions
    role-expect: lists `ads_read` as granted
    grant:    ads_read on business 1234567
    owner:    client
    reaches:  campaign, ad set and ad reads; catalogue listing
    cannot:   publishing, budget writes, catalogue upload
    verified: @TODAY@

Prose below the card is free-form and the checker does not read it.
'

# Valid but UNUSUAL: a route that is BLOCKED. Everything measured, nothing
# reachable. This must stay GREEN — a book that only accepts working routes
# loses the measured negative, which is the half that stops a second session
# re-probing a closed door.
BLOCKED_CARD='# adplatform — developer portal

    identity: tools@example.invalid, browser multi-login
    account:  tools@example.invalid | none | trial pending, no production token | -
    via:      none
    upgrade:  api: approval of the submitted trial application
    use:      nothing — the trial application must be approved first
    check:    open https://developers.example.invalid/apps/1
    expect:   app status; currently "Trial pending"
    role-check: none - no token exists to read a role with
    role-expect: none
    grant:    none yet — trial application submitted
    owner:    vendor
    reaches:  nothing; the app cannot mint a production token
    cannot:   every v5 endpoint, until the trial is approved
    verified: @TODAY@
'

# Valid and UNUSUAL in the other direction: a system whose ONLY route is the
# human session. `via: browser` alone must stay GREEN. A guard proved only
# against mutations it catches is a guard whose false-positive rate is unmeasured,
# and the first thing an operator does with one that blocks real work is switch
# it off — so the suite carries a legitimate bottom-tier card as a control.
BROWSER_ONLY_CARD='# shopify — three production stores

    identity: tools@example.invalid, collaborator role External Marketer
    account:  tools@example.invalid | primary | collaborator, role External Marketer | admin.shopify.com in a tools@ browser session
    via:      browser
    upgrade:  api: a Dev Dashboard app on the client org, which a collaborator cannot create
    use:      https://admin.shopify.com/store/<handle> in a tools@ session
    check:    open https://admin.shopify.com/
    expect:   the store picker, not a login wall
    role-check: open https://admin.shopify.com/store/fixture/settings/account
    role-expect: the Users table shows `External Marketer`
    grant:    External Marketer collaborator
    owner:    client
    reaches:  orders, products, discounts, the marketing surfaces
    cannot:   Customer events and Themes — both denied by the role
    verified: @TODAY@
'

# Four fixtures for --run, one per verdict it can reach. Single-quoted so the
# backticks in `expect:` stay literal instead of being command-substituted — the
# backtick IS the assertion syntax here, so a double-quoted fixture would run
# the thing it is meant to be matching.
RUN_pass_CARD='# a — the literal really is in the output

    identity: tools@example.invalid
    check:    printf "role=tools account=tools@example.invalid\n"
    expect:   discloses `account=tools@example.invalid`
    grant:    fixture
    owner:    us
    reaches:  nothing, it is a fixture
    cannot:   anything real
    verified: @TODAY@
'
RUN_fail_CARD='# a — the check runs and prints the WRONG thing

    identity: tools@example.invalid
    check:    printf "role=tools account=tools@example.invalid\n"
    expect:   discloses `account=nobody@example.invalid`
    grant:    fixture
    owner:    us
    reaches:  nothing, it is a fixture
    cannot:   anything real
    verified: @TODAY@
'
RUN_refused_CARD='# a — a check that is not a read

    identity: tools@example.invalid
    check:    curl -sS -X POST https://example.invalid/v1/things
    expect:   returns `201`
    grant:    fixture
    owner:    us
    reaches:  nothing, it is a fixture
    cannot:   anything real
    verified: @TODAY@
'
# The FALSE-POSITIVE fixture. A guard that refuses ordinary work gets switched
# off, and a switched-off guard protects nothing (Helm No.2.11), so the deny-list
# has to be proved harmless as well as effective. Every honest check discards
# its own output; this one must PASS, not be REFUSED.
RUN_hygiene_CARD='# a — a read that redirects, as every honest check does

    identity: tools@example.invalid
    check:    command -v sh >/dev/null 2>&1 && printf "sh=present\n"
    expect:   prints `sh=present`
    grant:    fixture
    owner:    us
    reaches:  nothing, it is a fixture
    cannot:   anything real
    verified: @TODAY@
'
RUN_uncheckable_CARD='# a — prose expect, nothing to match on

    identity: tools@example.invalid
    check:    printf "role=tools account=tools@example.invalid\n"
    expect:   the operators own name and numeric id
    grant:    fixture
    owner:    us
    reaches:  nothing, it is a fixture
    cannot:   anything real
    verified: @TODAY@
'
# The ROLE half. Both open the door (`check:` passes); only one holds the role
# its card claims. The Flow miss of 2026-09-23 is exactly the second card: reach
# green, role changed, and nothing reading the role.
RUN_rolepass_CARD='# a — reach and role both as the card says
    identity: tools@example.invalid
    check:    printf "account=tools@example.invalid\n"
    expect:   discloses `account=tools@example.invalid`
    role-check: printf "role=admin\n"
    role-expect: prints `role=admin`
    verified: @TODAY@
'
RUN_rolefail_CARD='# a — the door opens, the role is not the one on the card
    identity: tools@example.invalid
    check:    printf "account=tools@example.invalid\n"
    expect:   discloses `account=tools@example.invalid`
    role-check: printf "role=viewer\n"
    role-expect: prints `role=admin`
    verified: @TODAY@
'
# A URL to look at is an agent's browser item, reported with its expectation —
# never MANUAL (a person's), and never a pass. Reach and role both.
RUN_browser_CARD='# a — a browser-only route
    identity: tools@example.invalid
    check:    open https://example.invalid/
    expect:   the dashboard, not `a login wall`
    verified: @TODAY@
'
RUN_rolebrowser_CARD='# a — the role is read off a settings page
    identity: tools@example.invalid
    check:    printf "account=tools@example.invalid\n"
    expect:   discloses `account=tools@example.invalid`
    role-check: open https://example.invalid/settings/users
    role-expect: shows `Admin`
    verified: @TODAY@
'

self_test() {
  _st=$(mktemp -d "${TMPDIR:-/tmp}/harbor.XXXXXX")
  _today=$(date +%Y-%m-%d)
  printf '%s' "$VALID_CARD" | sed "s/@TODAY@/$_today/" > "$_st/meta.md"
  printf 'kind\tpattern\tcard\nsystem\tfixture-system|fixture sys\tfixture-card\nrole\tfixture-role\t-\n' > "$_st/vocabulary.tsv"
  _pass=0; _fail=0

  printf 'self-test: a good book must be GREEN\n'
  if sh "$0" "$_st" >/dev/null 2>&1; then _pass=$((_pass+1)); else _fail=$((_fail+1)); printf '  FAILED\n'; fi

  printf 'self-test: each mutation must go RED\n'
  # mutation, sed program
  _muts='no identity line|/^ *identity:/d
no check line|/^ *check:/d
check is a placeholder|s|^ *check:.*|    check:    TBD|
owner outside the enum|s|^ *owner:.*|    owner:    partner|
no verified line|/^ *verified:/d
verified is stale|s|^ *verified:.*|    verified: 2020-01-01|
identity is a role label|s|^ *identity:.*|    identity: tools|
identity is a role label from the register vocabulary|s|^ *identity:.*|    identity: fixture-role|
cannot line is empty|s|^ *cannot:.*|    cannot:|
no reaches line|/^ *reaches:/d
no via line|/^ *via:/d
via names a tier outside the enum|s|^ *via:.*|    via:      curl > browser|
via is out of priority order|s|^ *via:.*|    via:      browser > cli|
via repeats a tier|s|^ *via:.*|    via:      api > api|
via mixes none with a working tier|s|^ *via:.*|    via:      api > none|
via lists nothing at all|s|^ *via:.*|    via:|
no use line|/^ *use:/d
use is a placeholder|s|^ *use:.*|    use:      TBD|
no upgrade line|/^ *upgrade:/d
upgrade is a placeholder|s|^ *upgrade:.*|    upgrade:  TBD|
upgrade names a tier no better than the one held|s|^ *upgrade:.*|    upgrade:  browser: log in by hand|
upgrade is free prose with no tier|s|^ *upgrade:.*|    upgrade:  we should probably ask someone|
no account line|/^ *account:/d
account line with the wrong number of fields|s#^ *account:  analytics.*#    account:  analytics@example.invalid primary ads_read#
account use outside the enum|s#| primary |#| main |#
account names a role label|s#^ *account:  analytics@example.invalid#    account:  tools#
account named twice|s#^ *account:  tools@example.invalid#    account:  analytics@example.invalid#
reachable system with no primary account|s#| primary |#| fallback |#
account role empty|s#| ads_read on business 1234567 |#|  |#
account role too long to read in the matrix|s#| ads_read on business 1234567 |#| ads_read, read_insights, business_management, pages_read_engagement and catalog_management on business 1234567 |#
account connect cell empty|s#| a named human profile in the browser#| #
no role-check line|/^ *role-check:/d
no role-expect line|/^ *role-expect:/d
role-check none with no reason|s#^ *role-check:.*#    role-check: none#
role-expect with nothing to match|s#^ *role-expect:.*#    role-expect: lists the permission as granted#'

  printf '%s\n' "$_muts" | while IFS='|' read -r _mname _mprog; do
    [ -n "$_mname" ] || continue
    printf '%s' "$VALID_CARD" | sed "s/@TODAY@/$_today/" | sed "$_mprog" > "$_st/meta.md"
    if sh "$0" "$_st" >/dev/null 2>&1; then
      printf '  NOT CAUGHT: %s\n' "$_mname"; echo x >> "$_st/.f"
    else
      printf '  caught: %s\n' "$_mname"; echo x >> "$_st/.p"
    fi
  done
  if [ -f "$_st/.p" ]; then _pass=$((_pass + $(wc -l < "$_st/.p" | tr -d ' '))); fi
  if [ -f "$_st/.f" ]; then _fail=$((_fail + $(wc -l < "$_st/.f" | tr -d ' '))); fi

  printf 'self-test: a fully BLOCKED route must NOT trip it\n'
  printf '%s' "$VALID_CARD" | sed "s/@TODAY@/$_today/" > "$_st/meta.md"
  printf '%s' "$BLOCKED_CARD" | sed "s/@TODAY@/$_today/" > "$_st/adplatform.md"
  if sh "$0" "$_st" >/dev/null 2>&1; then _pass=$((_pass+1)); else _fail=$((_fail+1)); printf '  FAILED: a blocked-but-measured route was rejected\n'; fi

  printf 'self-test: a browser-ONLY route must NOT trip it\n'
  printf '%s' "$BROWSER_ONLY_CARD" | sed "s/@TODAY@/$_today/" > "$_st/shopify.md"
  if sh "$0" "$_st" >/dev/null 2>&1; then _pass=$((_pass+1)); else _fail=$((_fail+1)); printf '  FAILED: a legitimate bottom-tier route was rejected\n'; fi
  rm -f "$_st/shopify.md"

  printf 'self-test: --dispatch must rank a cli route above a browser-only one\n'
  printf '%s' "$BROWSER_ONLY_CARD" | sed "s/@TODAY@/$_today/" > "$_st/shopify.md"
  printf '%s' "$VALID_CARD" | sed "s/@TODAY@/$_today/" \
    | sed 's|^ *via:.*|    via:      cli|' > "$_st/aaa-cli.md"
  if [ "$(sh "$0" --dispatch "$_st" 2>/dev/null | /usr/bin/grep -nE '^\| (aaa-cli|shopify) ' | head -2 | sed -n '1p' | cut -d: -f2- | cut -d'|' -f2 | tr -d ' ')" = "aaa-cli" ]; then
    _pass=$((_pass+1)); printf '  caught: cli sorts above browser\n'
  else
    _fail=$((_fail+1)); printf '  FAILED: dispatch did not rank cli first\n'
  fi
  rm -f "$_st/shopify.md" "$_st/aaa-cli.md"

  # --coverage BUILT EVERY GAP LINE FROM A GREP OVER THE CORPUS, so an absent
  # corpus produced no GAP lines and read as full coverage. estate's
  # access-status.sh counted those zero GAPs and reported GOOD "coverage".
  _crc=0; sh "$0" --coverage "$_st/no-such-corpus" "$_st" >/dev/null 2>&1 || _crc=$?
  if [ "$_crc" -eq 2 ]; then
    _pass=$((_pass+1)); printf '  caught: an absent corpus is NOT CHECKED, not full coverage\n'
  else
    _fail=$((_fail+1)); printf '  NOT CAUGHT: --coverage on an absent corpus returned %s\n' "$_crc"
  fi
  # CONTROL — a real corpus must still report, and must not be turned into an error.
  printf 'fixture-system is used here\n' > "$_st/corpus-note.md"
  _crc=0; _cout=$(sh "$0" --coverage "$_st" "$_st" 2>/dev/null) || _crc=$?
  if [ "$_crc" -eq 0 ] && printf '%s' "$_cout" | /usr/bin/grep -q 'GAP  fixture-system'; then
    _pass=$((_pass+1)); printf '  caught: CONTROL a readable corpus reports the vocabulary.tsv system it names\n'
  else
    _fail=$((_fail+1)); printf '  NOT CAUGHT: a readable corpus returned %s, or no GAP for the vocabulary system\n' "$_crc"
  fi
  rm -f "$_st/corpus-note.md"
  # The vocabulary is the register's (harbor#1273): with none, nothing is covered, and that is not full coverage.
  mv "$_st/vocabulary.tsv" "$_st/vocabulary.keep"
  _crc=0; sh "$0" --coverage "$_st" "$_st" >/dev/null 2>&1 || _crc=$?
  mv "$_st/vocabulary.keep" "$_st/vocabulary.tsv"
  if [ "$_crc" -eq 2 ]; then
    _pass=$((_pass+1)); printf '  caught: no vocabulary.tsv is NOT CHECKED, not full coverage\n'
  else
    _fail=$((_fail+1)); printf '  NOT CAUGHT: --coverage with no vocabulary returned %s\n' "$_crc"
  fi

  printf 'self-test: --report must name the blocked route as reaching nothing\n'
  if sh "$0" --report "$_st" 2>/dev/null | /usr/bin/grep -q 'nothing; the app cannot mint'; then
    _pass=$((_pass+1)); else _fail=$((_fail+1)); printf '  FAILED\n'; fi

  # --accounts turns the book round: one column per account. tools@ appears on
  # three cards here (meta: none, adplatform: none, shopify: primary), so it earns
  # a column; analytics@ appears on one, so it is filed under "other accounts".
  printf 'self-test: --accounts must allocate every account to every system it touches\n'
  printf '%s' "$BROWSER_ONLY_CARD" | sed "s/@TODAY@/$_today/" > "$_st/shopify.md"
  _acc=$(sh "$0" --accounts "$_st" 2>/dev/null || true)
  for _want in '| system | tools@example.invalid | other accounts | role checked |' \
               '| meta | ✗ no access | analytics@example.invalid (primary) | machine |' \
               '| shopify | **primary** · collaborator, role External Marketer |  | browser |' \
               '| not read |' \
               '### tools@example.invalid' \
               '| shopify | primary | collaborator, role External Marketer |'; do
    if printf '%s' "$_acc" | /usr/bin/grep -qF -- "$_want"; then
      _pass=$((_pass+1)); printf '  caught: --accounts renders %s\n' "$_want"
    else
      _fail=$((_fail+1)); printf '  NOT CAUGHT: --accounts is missing %s\n' "$_want"
    fi
  done
  # Within an account, the systems to USE it for come before the ones it
  # cannot reach — the reader wants the answer, then the negatives.
  if printf '%s' "$_acc" | awk '/^### tools@example.invalid/ { on = 1; next } on && /^### / { exit } on && /^\| [a-z]/ && !/^\| system / { print $4 }' \
      | head -1 | /usr/bin/grep -qx 'primary'; then
    _pass=$((_pass+1)); printf '  caught: an account lists its primary systems first\n'
  else
    _fail=$((_fail+1)); printf '  NOT CAUGHT: --accounts does not put primary first\n'
  fi

  # A CHECKED-IN generated file must match the cards, or the gate goes RED —
  # DISPATCH.md sat two weeks stale because nothing compared it.
  printf 'self-test: a stale ACCOUNTS.md must go RED, a fresh one GREEN\n'
  sh "$0" --accounts "$_st" > "$_st/ACCOUNTS.md" 2>/dev/null
  if sh "$0" "$_st" >/dev/null 2>&1; then
    _pass=$((_pass+1)); printf '  caught: CONTROL a freshly generated ACCOUNTS.md passes\n'
  else
    _fail=$((_fail+1)); printf '  NOT CAUGHT: a fresh ACCOUNTS.md was failed\n'
  fi
  sed 's#| primary | collaborator#| fallback | collaborator#' "$_st/shopify.md" > "$_st/shopify.tmp"
  sed 's#^ *via:.*#    via:      none#' "$_st/shopify.tmp" > "$_st/shopify.md"; rm -f "$_st/shopify.tmp"
  if sh "$0" "$_st" >/dev/null 2>&1; then
    _fail=$((_fail+1)); printf '  NOT CAUGHT: ACCOUNTS.md went stale and the gate stayed green\n'
  else
    _pass=$((_pass+1)); printf '  caught: a card changed under ACCOUNTS.md\n'
  fi
  rm -f "$_st/shopify.md" "$_st/ACCOUNTS.md"

  # --run has to be proved separately: it is the only mode that executes, and a
  # mode that reported `pass` on everything would be worse than not having it.
  printf 'self-test: --run must execute, and discriminate on the output\n'
  for _rcase in pass fail refused uncheckable hygiene rolepass rolefail browser rolebrowser; do
    _rd="$_st/run-$_rcase"; mkdir -p "$_rd"
    eval "_rcard=\$RUN_${_rcase}_CARD" 2>/dev/null || _rcard=''
    printf '%s' "$_rcard" | sed "s/@TODAY@/$_today/" > "$_rd/a.md"
    # `_x=$(cmd)` where cmd exits non-zero ABORTS under set -e, and three of the
    # four fixtures below are meant to exit 1. As the condition of an `if` the
    # assignment is exempt, which is the only portable way to keep both.
    if _rout=$(sh "$0" --run "$_rd" 2>&1); then _rrc=0; else _rrc=$?; fi
    case "$_rcase" in
      pass)        _rwant='   pass';        _rwantrc=0 ;;
      fail)        _rwant='FAIL';           _rwantrc=1 ;;
      refused)     _rwant='REFUSED';        _rwantrc=1 ;;
      uncheckable) _rwant='UNCHECKABLE';    _rwantrc=0 ;;
      hygiene)     _rwant='   pass';        _rwantrc=0 ;;
      rolepass)    _rwant='   role: pass';  _rwantrc=0 ;;
      rolefail)    _rwant='   role: FAIL';  _rwantrc=1 ;;
      browser)     _rwant='   BROWSER      for an agent in Chrome; the page must show: the dashboard'; _rwantrc=0 ;;
      rolebrowser) _rwant='   role: BROWSER '; _rwantrc=0 ;;
    esac
    if printf '%s' "$_rout" | /usr/bin/grep -qF "$_rwant" && [ "$_rrc" -eq "$_rwantrc" ]; then
      printf '  caught: --run %s\n' "$_rcase"; _pass=$((_pass+1))
    else
      printf '  NOT CAUGHT: --run %s (wanted %s + exit %s, got exit %s)\n' \
        "$_rcase" "$_rwant" "$_rwantrc" "$_rrc"; _fail=$((_fail+1))
    fi
  done

  rm -rf "$_st"
  printf '\nself-test: %s passed, %s failed\n' "$_pass" "$_fail"
  [ "$_fail" -eq 0 ] || exit 1
}

CUTOFF=$(cutoff_date)
rc=0

[ $# -ge 1 ] || { register_dir; gate_dir "$ACCESS_DIR_DEFAULT"; exit "$rc"; }
case "$1" in
  --self-test) self_test ;;
  --report)    shift; want_dir "${1:-}"; report_dir "${1:-$ACCESS_DIR_DEFAULT}" ;;
  --dispatch)  shift; want_dir "${1:-}"; dispatch_dir "${1:-$ACCESS_DIR_DEFAULT}" ;;
  --accounts)  shift; want_dir "${1:-}"; accounts_dir "${1:-$ACCESS_DIR_DEFAULT}" ;;
  --run)       shift; want_dir "${1:-}"; run_dir "${1:-$ACCESS_DIR_DEFAULT}" ;;
  --probe)     [ $# -eq 3 ] || usage; probe_one "$2" "$3" && exit 0 || exit $? ;;
  --classify)  [ $# -eq 3 ] || usage; probe_class "$2" "$3" ;;
  --coverage)  shift; [ $# -ge 1 ] || usage
               want_dir "${2:-}"; coverage_dir "$1" "${2:-$ACCESS_DIR_DEFAULT}" ;;
  -h|--help)   usage ;;
  -*)          usage ;;
  *)           gate_dir "$1" ;;
esac
exit "$rc"
