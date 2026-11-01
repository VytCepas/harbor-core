#!/usr/bin/env sh
# admission-cloud.sh (harbor#1149): the non-GCP rules — kubectl delete, terraform destroy, aws destroys.
set -u
. "$(dirname "$0")/../../lib/core.sh"
. "$(dirname "$0")/../../lib/table.sh"
t_init

G="$T_ROOT/bin/admission-cloud.sh"
t_table "$G" "$T_ROOT/tests/admission/cloud/c1-non-gcp.jsonl"
t_section "every rule a row names is an id the guard writes to its ledger"
_cl_ids="$(sed -n 's/.*_crule=\([a-z-]*\).*/\1/p' "$G" | sort -u)"
t_eq "no row names a rule the ledger never records" "" \
  "$(jq -r '.rule // empty' "$T_ROOT/tests/admission/cloud/c1-non-gcp.jsonl" | sort -u | grep -vx none | grep -vxF "$_cl_ids")"
t_done
