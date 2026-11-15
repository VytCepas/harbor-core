#!/usr/bin/env sh
# audit-stream-export.py (harbor#1181 lane 8): every generation is read, identifiers are re-keyed so they still join, time
# is coarsened, free text is refused or dropped, and a planted name, home path or e-mail stops the release.
. "$(dirname "$0")/../../lib/core.sh"; t_init
R="$(cd "$(dirname "$0")/../../.." && pwd)"; X="$R/bin/audit-stream-export.py"
CF="$T_TMP/cfg"; O="$CF/MEMORY/OBSERVABILITY/box"; mkdir -p "$O/archive" "$O/streams/fleet.snapshots/2026-10-09"
K="$T_TMP/keys/release.key"
row() { printf '{"v":1,"ts":"%sZ","g":"bash","d":"%s","r":"r1","s":"flat","t":"Bash","h":"%s","sk":"%s"}\n' "$1" "$2" "$3" "$4"; }
row 2026-10-08T10:15:00 allow aaaa1111bbbb2222 s1s1s1s1s1s1s1s1 > "$O/guard-decisions.jsonl"
row 2026-10-09T11:20:00 block aaaa1111bbbb2222 s1s1s1s1s1s1s1s1 >> "$O/guard-decisions.jsonl"
row 2026-10-07T09:00:00 allow cccc3333dddd4444 s2s2s2s2s2s2s2s2 > "$O/guard-decisions.jsonl.1"
row 2026-10-06T08:00:00 deny eeee5555ffff6666 s3s3s3s3s3s3s3s3 > "$O/archive/guard-decisions.20261006T000000Z.jsonl"
printf 'not json\n' >> "$O/guard-decisions.jsonl"
ex() { python3 -I "$X" "$@" --cfg "$CF" --key-file "$K" >/dev/null 2>&1; echo $?; }
OUT="$T_TMP/rel"; G="$OUT/guard.decisions.jsonl"

t_section "a digest-only ledger"
t_eq "it exports" 0 "$(ex guard.decisions --out "$OUT")"
t_eq "every generation is read: live, .1 and archive" 4 "$(grep -c . "$G")"
t_eq "the unparseable line is counted, not exported" 1 "$(awk -F'\t' 'NR==2{print $5}' "$OUT/MANIFEST.tsv")"
t_eq "no raw digest survives" 0 "$(grep -c -E 'aaaa1111|s1s1s1' "$G")"
t_eq "the same raw value re-keys to one value, so rows still join" 1 "$(jq -r 'select(.d=="allow" or .d=="block")|select(.ts>="2026-10-08")|.h' "$G" | sort -u | grep -c .)"
t_eq "time is coarsened to the hour" "2026-10-09T11:00:00Z" "$(jq -r 'select(.d=="block").ts' "$G")"
t_eq "the release key is 0600 and outside the release" "-rw-------" "$(ls -l "$K" | cut -c1-10)"
cp "$G" "$T_TMP/first.jsonl"
ex guard.decisions --out "$OUT" >/dev/null
t_eq "the same key re-exports byte-identically" 0 "$(cmp -s "$G" "$T_TMP/first.jsonl"; echo $?)"
t_eq "a day window keeps only its days" 1 "$(ex guard.decisions --out "$T_TMP/win" --from 2026-10-09 --to 2026-10-09 >/dev/null; grep -c . "$T_TMP/win/guard.decisions.jsonl")"
python3 -I "$X" guard.decisions --out "$T_TMP/k2" --cfg "$CF" --key-file "$T_TMP/keys/other.key" >/dev/null 2>&1
jq -r .h "$T_TMP/k2/guard.decisions.jsonl" | sort -u > "$T_TMP/h2"; jq -r .h "$G" | sort -u > "$T_TMP/h1"
t_eq "a different key re-keys differently: no value in common" 0 "$(comm -12 "$T_TMP/h1" "$T_TMP/h2" | grep -c .)"

t_section "policy"
t_eq "a free-text stream is refused" 2 "$(ex events --out "$T_TMP/ev")"
t_eq "a key inside the release dir is refused" 2 "$(python3 -I "$X" guard.decisions --out "$T_TMP/in" --cfg "$CF" --key-file "$T_TMP/in/k" >/dev/null 2>&1; echo $?)"
t_eq "an unregistered stream is refused" 2 "$(ex no.such --out "$T_TMP/x")"

t_section "the scrub gate"
S="$O/streams/fleet.snapshots/2026-10-09/w.jsonl"
printf '{"v":1,"ts":"2026-10-09T10:00:00Z","stream":"fleet.snapshots","sess":"abc","attrs":{"repos":3}}\n' > "$S"
t_eq "a clean envelope stream exports" 0 "$(ex fleet.snapshots --out "$T_TMP/fs")"
t_eq "and its session id is re-keyed" 0 "$(grep -c '"sess":"abc"' "$T_TMP/fs/fleet.snapshots.jsonl")"
for plant in "$(id -un)" "$HOME/x" "/home/someone/y" "ops@example.com"; do
  printf '{"v":1,"ts":"2026-10-09T10:00:00Z","stream":"fleet.snapshots","attrs":{"note":"%s"}}\n' "$plant" >> "$S"
  t_eq "a planted value stops the release ($(printf '%s' "$plant" | sed 's/[A-Za-z]/x/g' | cut -c1-12))" 1 "$(ex fleet.snapshots --out "$T_TMP/pl")"
  t_eq "...and leaves no output" no "$([ -e "$T_TMP/pl/fleet.snapshots.jsonl" ] && echo yes || echo no)"
  sed '$d' "$S" > "$T_TMP/s" && cat "$T_TMP/s" > "$S"
done
t_done
