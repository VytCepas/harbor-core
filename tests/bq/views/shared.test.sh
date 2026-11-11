#!/usr/bin/env sh
# shared.test.sh (harbor#1278) — templates/bq/shared-views.sql, the only views beyond the operator: run as written in sqlite over
# tables made from contracts/bq-schema.tsv. No view shows a group of fewer than 5 people or any person_id; a group of 5 does show;
# and a copy with its suppression removed is caught by the same check.
. "$(dirname "$0")/../../lib/core.sh"; t_init
command -v sqlite3 >/dev/null 2>&1 || { echo "shared-test: SKIPPED (no sqlite3 to run the views)"; t_section "skipped"; t_pass; t_done; }
V="$T_ROOT/templates/bq/shared-views.sql"; SCHEMA="$T_ROOT/contracts/bq-schema.tsv"; DB="$T_TMP/x.db"
code() { awk -F'\t' -v s="$1" -v v="$2" '$1 == s && $3 == v { print $2 }' "$T_ROOT/contracts/bq-values.tsv"; }
REFUSAL="$(code hub_kind refusal)"; GUARD="$(code hub_kind guard)"

# tables: every schema table as `ds.<table>`, its columns untyped
tables() { awk -F'\t' '/^#/ || NF == 0 || $1 == "table" { next } { c[$1] = c[$1] (c[$1] ? ", " : "") "`" $2 "`" } END { for (t in c) print "CREATE TABLE `ds." t "` (" c[t] ");" }' "$SCHEMA"; }
views() { sed -e 's/@DS@/ds/g' -e 's/@SHARED@/sh/g' -e 's/CREATE OR REPLACE VIEW/CREATE VIEW/' "$1"; }
# rows: <n people> of one group, ids p1..pn
people() { _pn="$1"; shift; _pi=0; while [ "$_pi" -lt "$_pn" ]; do _pi=$((_pi + 1)); printf "$@" "p$_pi"; done; }
fill() {
  {
    printf "INSERT INTO \`ds.dim_enum\` VALUES ('hub_kind', %s, 'refusal'), ('hub_kind', %s, 'guard');\n" "$REFUSAL" "$GUARD"
    # rule 101 hit by 4 people, rule 102 by 5, on one day; and calls from 4 people on day 1, 5 people on day 2
    people 4 "INSERT INTO \`ds.decision\` (person_id, day, rule, kind, count) VALUES ('%s', '2026-11-07', 101, $REFUSAL, 1);\n"
    people 5 "INSERT INTO \`ds.decision\` (person_id, day, rule, kind, count) VALUES ('%s', '2026-11-07', 102, $REFUSAL, 1);\n"
    people 5 "INSERT INTO \`ds.decision\` (person_id, day, rule, kind, count) VALUES ('%s', '2026-11-08', 102, $GUARD, 2);\n"
    people 5 "INSERT INTO \`ds.activity\` (person_id, day, tool, verdict, calls) VALUES ('%s', '2026-11-07', 1, 1, 10);\n"
    people 4 "INSERT INTO \`ds.activity\` (person_id, day, tool, verdict, calls) VALUES ('%s', '2026-11-08', 1, 1, 10);\n"
    people 4 "INSERT INTO \`ds.session\` (person_id, day, started, ended) VALUES ('%s', '2026-11-07', 1, 1);\n"
    people 5 "INSERT INTO \`ds.session\` (person_id, day, started, ended) VALUES ('%s', '2026-11-08', 1, 1);\n"
    printf "INSERT INTO \`ds.agg_approval\` (week, rule, tier, people, requests, approved, expired) VALUES ('2026-11-02', 101, 1, 4, 6, 5, 1), ('2026-11-02', 102, 1, 5, 8, 7, 0);\n"
  } | sqlite3 "$DB"
}
build() { rm -f "$DB"; { echo "ATTACH ':memory:' AS unused;"; tables; views "$1"; } | sqlite3 "$DB" && fill; }
VIEWS="$(sed -n 's/^CREATE OR REPLACE VIEW `@SHARED@\.\([a-z_]*\)`.*/\1/p' "$V")"
cols() { sqlite3 "$DB" "SELECT group_concat(name, ' ') FROM pragma_table_info('sh.$1');"; }
# small <db>: every row of every shared view with fewer than 5 people, or any person_id column; "view n" lines
small() {
  for _v in $VIEWS; do
    _c="$(sqlite3 "$DB" "SELECT COUNT(*) FROM \`sh.$_v\` WHERE people < 5;")"; [ "$_c" = 0 ] || echo "$_v $_c"
    cols "$_v" | grep -qw person_id && echo "$_v person_id"
  done; :
}

t_section "1 - the views run, each carrying its people count"
build "$V"; t_eq "the schema and views load in sqlite" 0 "$?"
t_eq "five shared views" 5 "$(printf '%s\n' "$VIEWS" | grep -c .)"
for _v in $VIEWS; do t_has "$_v has a people column" "$(cols "$_v")" "people"; done

t_section "2 - no group under 5 shows, and no id"
t_eq "no small group and no person_id in any shared view" "" "$(small)"
t_eq "rule 102, 5 people, shows" "102 5" "$(sqlite3 -separator ' ' "$DB" "SELECT rule, people FROM \`sh.v_shared_rule_day\` WHERE day = '2026-11-07';")"
t_eq "rule 101, 4 people, does not" 0 "$(sqlite3 "$DB" "SELECT COUNT(*) FROM \`sh.v_shared_rule_day\` WHERE rule = 101;")"
t_eq "the block rate: 5 people's blocks over 5 people's calls" "2026-11-07 102 5 50" "$(sqlite3 -separator ' ' "$DB" "SELECT day, rule, blocks, calls FROM \`sh.v_shared_block_rate\`;")"
t_eq "a day whose calls come from 4 people gives no rate" 0 "$(sqlite3 "$DB" "SELECT COUNT(*) FROM \`sh.v_shared_block_rate\` WHERE day = '2026-11-08';")"
t_eq "approval weeks: only the 5-person cell" 102 "$(sqlite3 "$DB" "SELECT rule FROM \`sh.v_shared_approval_week\`;")"
t_eq "sessions: only the 5-person day" 2026-11-08 "$(sqlite3 "$DB" "SELECT day FROM \`sh.v_shared_sessions_day\`;")"

t_section "3 - the check sees a view without its suppression"
sed 's/>= 5/>= 1/g' "$V" > "$T_TMP/open.sql"
t_eq "the open copy lost every suppression" 0 "$(grep -c '>= 5' "$T_TMP/open.sql")"
build "$T_TMP/open.sql"
t_has "and the same check names a small group" "$(small)" "v_shared_rule_day"
t_done
