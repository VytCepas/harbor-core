#!/usr/bin/env sh
# guard-cloud.sh (harbor#193, #194): its rule table, its messages, and the shared shapes.
set -u
. "$(dirname "$0")/../lib/core.sh"
. "$(dirname "$0")/../lib/table.sh"
t_init

G="$T_ROOT/bin/guard-cloud.sh"
# The IDENTITY message reads the active account from gcloud; the stub answers $STUB_ACCOUNT.
printf '#!/bin/sh\n[ "$*" = "config get-value account" ] && printf "%%s\\n" "${STUB_ACCOUNT:-(unset)}"\nexit 0\n' > "$T_BIN/gcloud"
chmod +x "$T_BIN/gcloud"

t_table  "$G" "$T_ROOT/tests/guards/cloud.jsonl"
t_msgs   "$G" "$T_ROOT/tests/guards/cloud.msg.jsonl"
t_shared "$G" cloud
# One id per rule (harbor#957): a row's rule is the ledger id guard-cloud writes, never the tier word
# (the rows said SOFT while the ledger said cloud-soft). `none` marks a row no rule may decide.
t_section "every rule a row names is an id the guard writes to its ledger"
_cl_ids="$(sed -n 's/.*_crule=\([a-z-]*\).*/\1/p' "$G" | sort -u)"
t_eq "the guard's ledger ids were read" yes "$([ -n "$_cl_ids" ] && echo yes || echo no)"
t_eq "no row names a rule the ledger never records" "" \
  "$(jq -r '.rule // empty' "$T_ROOT/tests/guards/cloud.jsonl" | sort -u | grep -vx none | grep -vxF "$_cl_ids")"
t_done
