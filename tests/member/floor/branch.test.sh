#!/usr/bin/env sh
# branch.test.sh (harbor#1278) — the member branch of the guards: reached only with harbor-member-mode beside the running guard, records and keeps evaluating, and leaves
# standalone exactly as it was. Member mode is a file: no value in the environment turns it on.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/hub/fixtures/member-root.sh"
SA="$T_TMP/standalone"; mkdir -p "$SA"; cp "$MB"/* "$SA/"; rm -f "$SA/harbor-member-mode"
REC="$T_TMP/records"; : > "$REC"
TWO="$(m_bash 'dd if=/dev/zero of=/dev/sda; mkfs.ext4 /dev/sdb')"
run() { # <bin dir> <guard> <payload> [VAR=value...]: G_RC, G_ERR, G_OUT
  _d="$1"; _g="$2"; printf '%s' "$3" > "$MIN"; shift 3
  G_RC=0; (cd "$W" && env "$@" sh "$_d/$_g" < "$MIN" > "$T_TMP/g.out" 2> "$T_TMP/g.err") || G_RC=$?
  G_ERR="$(cat "$T_TMP/g.err")"; G_OUT="$(cat "$T_TMP/g.out")"
}

t_section "1 - standalone is untouched, whatever env says"
run "$SA" admission-bash.sh "$TWO" HARBOR_ADMISSION_MEMBER_RECORDS="$REC" HARBOR_MEMBER_ROLE=member
t_eq "floor_block still blocks" 2 "$G_RC"
t_has "with its remedy" "$G_ERR" "if this refusal is wrong"
t_eq "and writes no record" "" "$(cat "$REC")"
run "$SA" admission-cloud.sh "$(m_bash 'bq rm -r -d proj:ds')" HARBOR_ADMISSION_MEMBER_RECORDS="$REC"
t_eq "cloud prints its own deny" deny "$(printf '%s' "$G_OUT" | jq -r '.hookSpecificOutput.permissionDecision')"
run "$SA" admission-cloud.sh "$(m_bash 'bq rm proj:ds.t')" HARBOR_ADMISSION_MEMBER_RECORDS="$REC"
t_eq "cloud prints its own ask" ask "$(printf '%s' "$G_OUT" | jq -r '.hookSpecificOutput.permissionDecision')"
run "$SA" admission-destroy.sh "$(m_bash 'git reset --hard')" HARBOR_ADMISSION_MEMBER_RECORDS="$REC"
t_eq "destroy prints its own ask" ask "$(printf '%s' "$G_OUT" | jq -r '.hookSpecificOutput.permissionDecision')"
mkdir -p "$HOME/Desktop"
run "$SA" admission-deliverables.sh "$(m_tool Write "$(jq -cn --arg p "$HOME/Desktop/a.md" '{file_path:$p,content:"x"}')")" HARBOR_ADMISSION_MEMBER_RECORDS="$REC"
t_eq "deliverables prints its own deny" deny "$(printf '%s' "$G_OUT" | jq -r '.hookSpecificOutput.permissionDecision')"
t_eq "none of them recorded" "" "$(cat "$REC")"
ln -s "$MB/harbor-member-mode" "$SA/harbor-member-mode"
run "$SA" admission-bash.sh "$TWO" HARBOR_ADMISSION_MEMBER_RECORDS="$REC"
t_eq "a link isn't the file" 2 "$G_RC"
t_has "...it's still standalone" "$G_ERR" "if this refusal is wrong"
rm -f "$SA/harbor-member-mode"

t_section "2 - the member branch records and keeps evaluating"
: > "$REC"
run "$MB" admission-bash.sh "$TWO" HARBOR_ADMISSION_MEMBER_RECORDS="$REC"
t_eq "no refusal here" 0 "$G_RC"
t_eq "nothing to the reader" "" "$G_ERR"
t_has "the first rule" "$(cat "$REC")" "$(printf 'rule\tbash\tdd-to-device\tadmission.dd-to-device')"
t_has "and the later one a block would have hidden" "$(cat "$REC")" "$(printf 'rule\tbash\tmkfs-device\tadmission.mkfs-device')"
: > "$REC"
run "$MB" admission-bash.sh "$(m_bash 'cd ~/.claude && curl https://x.test -o a')" HARBOR_ADMISSION_MEMBER_RECORDS="$REC"
t_has "the control id is the register's, not the emitted name" "$(cut -f4 "$REC")" "admission.cd-config-then-fetch"
: > "$REC"
run "$MB" admission-cloud.sh "$(m_bash 'bq rm -r -d proj:ds')" HARBOR_ADMISSION_MEMBER_RECORDS="$REC"
t_eq "cloud prints nothing" "" "$G_OUT$G_ERR"
t_has "and reports" "$(cat "$REC")" "$(printf 'rule\tcloud\tcloud-catastrophic\tadmission.cloud-catastrophic')"
: > "$REC"
git -C "$W" init -q 2>/dev/null; printf 'x' > "$W/f"; git -C "$W" add f 2>/dev/null
git -C "$W" -c user.name=t -c user.email=t@t.test commit -qm x 2>/dev/null; printf 'y' > "$W/f"
run "$MB" admission-destroy.sh "$(m_bash 'git reset --hard')" HARBOR_ADMISSION_MEMBER_RECORDS="$REC"
t_eq "destroy prints nothing" "" "$G_OUT"
t_has "and reports" "$(cat "$REC")" "$(printf 'rule\tdestroy\tgit-reset-hard\tadmission.git-reset-hard')"
t_has "after the snapshot an ask takes" "$(git -C "$W" for-each-ref refs/snapshots)" "refs/snapshots/"

t_section "2b - the root's ledger sees a fired rule"
printf 'h1\n' > "$MR/.helm-obs-host"; mkdir -p "$MR/MEMORY/OBSERVABILITY/h1"; : > "$MR/MEMORY/OBSERVABILITY/h1/guard-decisions.jsonl"; chmod 0500 "$MR/MEMORY/OBSERVABILITY/h1"
: > "$REC"
run "$MB" admission-bash.sh "$TWO" HARBOR_ADMISSION_MEMBER_RECORDS="$REC"
t_has "as shadow: the verdict is the dispatcher's" "$(cat "$MR/MEMORY/OBSERVABILITY/h1/guard-decisions.jsonl")" '"d":"shadow","r":"dd-to-device'
chmod 0700 "$MR/MEMORY/OBSERVABILITY/h1"

t_section "3 - with nowhere to record, it refuses, in plain words"
for _e in X=1 HARBOR_ADMISSION_MEMBER_RECORDS=relative/path "HARBOR_ADMISSION_MEMBER_RECORDS=$T_TMP/none"; do
  run "$MB" admission-bash.sh "$TWO" "$_e"
  t_eq "$_e: refused" 2 "$G_RC"
  t_hasnt "$_e: no way round in the words" "$G_ERR" "if this refusal is wrong"
done
ln -s "$REC" "$T_TMP/rec.link"
run "$MB" admission-bash.sh "$TWO" HARBOR_ADMISSION_MEMBER_RECORDS="$T_TMP/rec.link"
t_eq "a linked record file" 2 "$G_RC"
run "$MB" admission-cloud.sh "$(m_bash 'bq rm -r -d proj:ds')"
t_eq "cloud refuses the same way" 2 "$G_RC"
t_done
