#!/usr/bin/env sh
# failure-capture.sh (M5, harbor#44), part 3: the ledger itself. Host partitions and FC-9 (harbor#119),
# the rotated generation, a torn tail, usage and a missing jq (B9), the two renderers, and the
# tool-failure ledger rules FC-10 and FC-11 (harbor#465).
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$T_ROOT/tests/hooks/failure-capture-fixture.sh"
CLEAN="$(mkfixture clean)"; unseal "$CLEAN"; census "$CLEAN" 3; seal "$CLEAN"

t_section "multi-host: one machine's records do not mask another's failure"
# A census is a per-machine fact: before the partition, healthy host B diluted host A's 67% drop.
mh_rec() { # <dir> <host> <g> <d> <r> <ts>
  printf '{"v":1,"ts":"%s","g":"%s","d":"%s","r":"%s","s":"meta","t":"none","h":"-"}\n' \
    "$6" "$3" "$4" "$5" >> "$1/MEMORY/OBSERVABILITY/$2/guard-decisions.jsonl"
}
mkmulti() { # <name> → a fixture with hostA and hostB partitions
  _d="$(mkfixture "$1")"
  mkdir -p "$_d/MEMORY/OBSERVABILITY/hostA" "$_d/MEMORY/OBSERVABILITY/hostB"
  : > "$_d/MEMORY/OBSERVABILITY/hostA/guard-decisions.jsonl"
  : > "$_d/MEMORY/OBSERVABILITY/hostB/guard-decisions.jsonl"
  rm -rf "$_d/MEMORY/OBSERVABILITY/$HOST"
  printf '%s' "$_d"
}
MH="$(mkmulti multihost-green)"
for _i in 1 2 3; do
  mh_rec "$MH" hostA session   armed floor-armed     "2026-08-02T10:0$_i:00Z"
  mh_rec "$MH" hostA integrity allow integrity-clean "2026-08-02T10:0$_i:01Z"
  mh_rec "$MH" hostB session   armed floor-armed     "2026-08-02T11:0$_i:00Z"
done
chmod 0500 "$MH/MEMORY/OBSERVABILITY/hostA" "$MH/MEMORY/OBSERVABILITY/hostB"
t_eq "two healthy hosts, one without B6: FC-1" no "$(has_rule "$MH" FC-1)"  # FC-9 is expected here
MH2="$(mkmulti multihost-red)"
for _i in 1 2 3; do
  mh_rec "$MH2" hostA session armed floor-armed "2026-08-02T10:0$_i:00Z"
  mh_rec "$MH2" hostB session armed floor-armed "2026-08-02T11:0$_i:00Z"
  mh_rec "$MH2" hostB session armed floor-armed "2026-08-02T12:0$_i:00Z"
done
for _i in 1 2 3 4 5 6 7 8 9; do mh_rec "$MH2" hostA integrity allow integrity-clean "2026-08-02T13:0$_i:01Z"; done
printf '{"v":1,"ts":"2026-08-02T13:20:00Z","g":"bash","d":"block","r":"floor-surface","s":"meta","t":"none","h":"%s"}\n' \
  "$D_PROBE_T" >> "$MH2/MEMORY/OBSERVABILITY/hostA/guard-decisions.jsonl"  # one verify run on hostA
chmod 0500 "$MH2/MEMORY/OBSERVABILITY/hostA" "$MH2/MEMORY/OBSERVABILITY/hostB"
t_eq "hostA's 3-vs-9 surplus, beside hostB's 6 sessions" warn "$(sev_of "$MH2" FC-1)"
t_has "the FC-1 finding names its host" "$(subj_of "$MH2" FC-1)" "hostA"

t_section "FC-9: a ledger sharded under two host keys is reported as forked"
t_eq "FC-9 fires on two partitions" yes "$(has_rule "$MH" FC-9)"
t_eq "hostA/hostB match no canonical key: an ongoing fork" crit "$(sev_of "$MH" FC-9)"
case "$(subj_of "$MH" FC-9)" in *hostA*hostB*|*hostB*hostA*) _s=both ;; *) _s="$(subj_of "$MH" FC-9)" ;; esac
t_eq "it names both partitions" both "$_s"

t_section "FC-9 separates an ongoing fork from orphaned history (harbor#119)"
# The canonical name comes from floor_host_token, which owns it; what is asserted is which partition
# holds the newest record.
CANON="$(sh -c '. "$1/guard-lib.sh" 2>/dev/null; floor_host_token 2>/dev/null' _ "$SRC")"
t_eq "the canonical host token is derived" yes "$([ -n "$CANON" ] && echo yes || echo no)"
mkforked() { # <name> <newest-in> → a two-partition fixture
  _d="$(mkfixture "$1")"
  mkdir -p "$_d/MEMORY/OBSERVABILITY/$CANON" "$_d/MEMORY/OBSERVABILITY/oldkey"
  rm -rf "$_d/MEMORY/OBSERVABILITY/$HOST"
  for _h in "$CANON" oldkey; do
    printf '{"v":1,"ts":"2026-08-02T10:00:00Z","g":"session","d":"armed","r":"floor-armed","s":"meta","t":"none","h":"-"}\n' \
      > "$_d/MEMORY/OBSERVABILITY/$_h/guard-decisions.jsonl"
  done
  printf '{"v":1,"ts":"2026-08-04T23:00:00Z","g":"session","d":"armed","r":"floor-armed","s":"meta","t":"none","h":"-"}\n' \
    >> "$_d/MEMORY/OBSERVABILITY/$2/guard-decisions.jsonl"
  chmod 0500 "$_d/MEMORY/OBSERVABILITY/$CANON" "$_d/MEMORY/OBSERVABILITY/oldkey"
  printf '%s' "$_d"
}
FK_ON="$(mkforked forked-ongoing oldkey)"
t_eq "still receiving under the old key" crit "$(sev_of "$FK_ON" FC-9)"
t_has "it says which key is still written" "$(subj_of "$FK_ON" FC-9)" "still writing under"
FK_HIST="$(mkforked forked-historical "$CANON")"
t_eq "orphaned history" warn "$(sev_of "$FK_HIST" FC-9)"

t_section "FC-9 degrades honestly when the canonical key cannot be read"
mkdir -p "$TMP/bare-copy"; cp "$FC" "$TMP/bare-copy/failure-capture.sh"  # no sibling guard-lib.sh
FCT="$TMP/bare-copy/failure-capture.sh"
t_has "it admits the canonical key is unknown" "$(subj_of "$MH" FC-9)" "UNKNOWN"
FCT="$FC"

t_section "FC-9 stays silent on a single-partition ledger"
t_eq "FC-9 on the clean fixture" no "$(has_rule "$CLEAN" FC-9)"

t_section "the rotated generation is read, not skipped"
FR="$(mkfixture rotated)"; unseal "$FR"; census "$FR" 2
recn 3 "$FR" bash block jq-rewrites-surface "2026-08-01T09:00:00Z" "$(digest_of 'older generation command')" .1
seal "$FR"
t_eq "records in guard-decisions.jsonl.1 fire FC-5" yes "$(has_rule "$FR" FC-5)"
t_eq "records counted across both generations" 7 "$(q '.records' "$FR")"

t_section "a torn tail is dropped, and the rest of the file still counts"
FT="$(mkfixture torn)"; unseal "$FT"; census "$FT" 2
printf '{"v":1,"ts":"2026-08-02T12:00:00Z","g":"bash","d":"bl\n' >> "$(SINK_OF "$FT")"; seal "$FT"
t_eq "records" 4 "$(q '.records' "$FT")"
t_eq "no findings" "" "$(rules_of "$FT")"

t_section "an absent config dir is an answer, not an error"
t_exit "exit" 0 sh "$FC" "$TMP/nothing-here"
t_eq "installed" false "$(q '.installed' "$TMP/nothing-here")"

t_section "usage errors exit 2, distinguishably from findings"
t_exit "an unknown option" 2 sh "$FC" --nonsense
t_exit "two config dirs" 2 sh "$FC" "$CLEAN" "$CLEAN"
t_exit "--help" 0 sh "$FC" --help

t_section "B9: a missing jq is loud, and never reads as clean"
mkdir -p "$TMP/nojq"
for _b in sh awk sed sort uniq tr basename cat find wc printf cut chmod; do
  _p="$(command -v "$_b" 2>/dev/null)" && ln -sf "$_p" "$TMP/nojq/$_b" 2>/dev/null
done
_out="$(PATH="$TMP/nojq" sh "$FC" "$CLEAN" 2>&1)"; _st=$?
t_eq "exit" 1 "$_st"
t_has "it says why" "$_out" "jq"

t_section "the two renderers report the same findings"
FMIX="$(mkfixture mixed)"; unseal "$FMIX"
recn 2 "$FMIX" session armed floor-armed "2026-08-02T10:00:00Z"
recn 9 "$FMIX" integrity allow integrity-clean "2026-08-02T10:00:01Z"
rec "$FMIX" wrapper deny wrapper-no-verdict "2026-08-02T11:00:00Z"
recn 3 "$FMIX" bash block rm-rf-root "2026-08-02T12:00:00Z" "$D_REAL"; seal "$FMIX"
t_eq "human rows equal --json findings" "$(q '.findings | length' "$FMIX")" \
  "$(sh "$FC" "$FMIX" 2>/dev/null | awk '/^  (FAIL|WARN): /{n++} END{print n+0}')"
t_eq "worst with a wrapper deny present" crit "$(worst_of "$FMIX")"

t_section "mutation: the per-host partition is load-bearing"
MUT5="$TMP/mut-host.sh"
sed 's#select(._host==\\\$h)|select(#select(#g' "$FC" > "$MUT5"  # `#`: the pattern holds jq's `|`
t_eq "the mutation applies" no "$(cmp -s "$FC" "$MUT5" && echo yes || echo no)"
# Aggregated, hostA's 3-vs-9 and hostB's 6 sessions net to 9-vs-9: the mutant must go silent.
t_eq "the real tool: FC-1 rows on the two-host fixture" 1 "$(count_of "$MH2" FC-1)"
FCT="$MUT5"; t_eq "the mutant: FC-1 rows" 0 "$(count_of "$MH2" FC-1)"; FCT="$FC"

# FC-10's falsifier, both halves: the same failure in three sessions is ONE finding naming the tool
# and input, and a tool that fails once raises nothing (harbor#465).
tf_write() { # <dir> <n> <session-prefix> <error-class> [digest] [same] [key] [day]; `same` = one session
  _d="$1"; _n="$2"; _p="$3"; _e="$4"; _h="${5:-aaaabbbbccccdddd}"; _m="${6:-}"; _k="${7:-~/x/gone.md}"; _day="${8:-2026-08-02}"
  _i=1
  while [ "$_i" -le "$_n" ]; do
    _sid="$_p$_i"; [ "$_m" = same ] && _sid="$_p"
    printf '{"v":1,"ts":"%sT10:00:00Z","t":"Read","e":"%s","k":"%s","h":"%s","s":"%s","ms":4}\n' \
      "$_day" "$_e" "$_k" "$_h" "$_sid" >> "$_d/MEMORY/OBSERVABILITY/$HOST/tool-failures.jsonl"
    _i=$((_i + 1))
  done
}
tf_fixture() { # <name> → a clean fixture with a tool-failure sink and the hook wired
  _f="$(mkfixture "$1")"
  : > "$_f/MEMORY/OBSERVABILITY/$HOST/tool-failures.jsonl"
  jq --arg c "/bin/sh $_f/bin/failure-observe.sh" '
    .hooks.PostToolUseFailure = [{matcher: ".*", hooks: [{type: "command", command: $c}]}]' \
    "$_f/settings.json" > "$_f/s.tmp" && mv "$_f/s.tmp" "$_f/settings.json"
  printf '%s' "$_f"
}
t_section "FC-10: the same failure across sessions is one finding"
FT1="$(tf_fixture tf-recur)"; tf_write "$FT1" 3 s not-found
t_eq "FC-10 fires on three sessions" yes "$(has_rule "$FT1" FC-10)"
t_eq "as one finding, not three" 1 "$(count_of "$FT1" FC-10)"
case "$(subj_of "$FT1" FC-10)" in *Read*gone.md*) _s=named ;; *) _s="$(subj_of "$FT1" FC-10)" ;; esac
t_eq "it names the tool, then the input" named "$_s"
t_section "FC-10 stays silent on a retry loop, a single failure, and a floor block"
FT2="$(tf_fixture tf-oneshot)"; tf_write "$FT2" 5 one not-found aaaabbbbccccdddd same
t_eq "five failures inside one session" no "$(has_rule "$FT2" FC-10)"
FT3="$(tf_fixture tf-single)"; tf_write "$FT3" 1 s not-found
t_eq "one failure, once" no "$(has_rule "$FT3" FC-10)"
FT4="$(tf_fixture tf-blocked)"; tf_write "$FT4" 4 s blocked  # the guard ledger's record, not this one
t_eq "a repeated floor block" no "$(has_rule "$FT4" FC-10)"

# A not-found pointer that resolves now is repaired (the judge's crit on ~/port/harbor/CLAUDE.md outlived its own fix).
t_section "FC-10: a not-found path that exists now is repaired, and one that does not still fires"
mkdir -p "$HOME/x"; : > "$HOME/x/present.md"
FT8="$(tf_fixture tf-repaired)"; tf_write "$FT8" 3 s not-found aaaabbbbccccdddd "" '~/x/present.md'
t_eq "a ~/ path that now exists" no "$(has_rule "$FT8" FC-10)"
FT9="$(tf_fixture tf-abs)"; tf_write "$FT9" 3 s not-found aaaabbbbccccdddd "" "$HOME/x/present.md"
t_eq "an absolute path that now exists" no "$(has_rule "$FT9" FC-10)"
FT10="$(tf_fixture tf-stilldead)"; tf_write "$FT10" 3 s not-found aaaabbbbccccdddd "" '~/x/absent.md'
t_eq "a path that still does not exist" yes "$(has_rule "$FT10" FC-10)"
rm -f "$HOME/x/present.md"
t_eq "the repaired one returns the day it is gone again" yes "$(has_rule "$FT8" FC-10)"
FT11="$(tf_fixture tf-notapath)"; tf_write "$FT11" 3 s not-found aaaabbbbccccdddd "" 'gone-command'
t_eq "a key that is not a path cannot be probed, so it stays" yes "$(has_rule "$FT11" FC-10)"
FT12="$(tf_fixture tf-othererr)"; : > "$HOME/x/present.md"; tf_write "$FT12" 3 s timeout aaaabbbbccccdddd "" '~/x/present.md'
t_eq "an existing path under another error class still fires" yes "$(has_rule "$FT12" FC-10)"
rm -f "$HOME/x/present.md"

t_section "FC-10 is horizoned on last occurrence: a failure last seen weeks ago is history"
FT13="$(tf_fixture tf-old)"; tf_write "$FT13" 4 s timeout aaaabbbbccccdddd "" 'old-command' 2026-07-01
t_eq "four sessions, all a month before today" no "$(has_rule "$FT13" FC-10)"
FT14="$(tf_fixture tf-oldnew)"; tf_write "$FT14" 3 s timeout aaaabbbbccccdddd "" 'old-command' 2026-07-01
tf_write "$FT14" 1 t timeout aaaabbbbccccdddd "" 'old-command' 2026-08-02
t_eq "the same failure again yesterday: it fires, counted over all history" yes "$(has_rule "$FT14" FC-10)"
MUT7="$TMP/mut-fc10-horizon.sh"
sed 's/map(select($c == "" or .last >= $c))/map(.)/' "$FC" > "$MUT7"
t_eq "the horizon mutation applies" no "$(cmp -s "$FC" "$MUT7" && echo yes || echo no)"
FCT="$MUT7"; t_eq "without the horizon the month-old failure fires" yes "$(has_rule "$FT13" FC-10)"; FCT="$FC"

t_section "FC-11: the recorder is wired and has nowhere to write"
FT5="$(tf_fixture tf-nosink)"
chmod 0700 "$FT5/MEMORY/OBSERVABILITY/$HOST"; rm -f "$FT5/MEMORY/OBSERVABILITY/$HOST/tool-failures.jsonl"
chmod 0500 "$FT5/MEMORY/OBSERVABILITY/$HOST"
t_eq "FC-11 fires" yes "$(has_rule "$FT5" FC-11)"
FT6="$(mkfixture tf-unwired)"  # never wired is not broken
t_eq "FC-11 on a dir that never wired the recorder" no "$(has_rule "$FT6" FC-11)"

t_section "both denominators are reported, never summed (harbor#467)"
FT7="$(tf_fixture tf-denom)"; tf_write "$FT7" 2 s other
t_eq "--json tool_failures" 2 "$(q '.tool_failures' "$FT7")"
t_has "the human report states it" "$(sh "$FC" "$FT7" 2>/dev/null)" "2 tool failure(s) read"

t_section "mutation: the session threshold is load-bearing in FC-10"
MUT6="$TMP/mut-sessions.sh"
sed 's/select(\.n >= 3 and \.s >= 2)/select(.n >= 3)/' "$FC" > "$MUT6"
t_eq "the mutation applies" no "$(cmp -s "$FC" "$MUT6" && echo yes || echo no)"
FCT="$MUT6"; t_eq "without it the retry loop fires" yes "$(has_rule "$FT2" FC-10)"; FCT="$FC"
t_done
