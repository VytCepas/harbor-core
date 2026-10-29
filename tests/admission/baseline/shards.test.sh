#!/usr/bin/env sh
# The floor suite's CI partition (harbor#727, replacing floor-test SHARD-1 of harbor#679). Every
# floor part — tests/admission/baseline/baseline.test.sh and each tests/admission/baseline/<part>.test.sh — runs as its own
# `--run` step in exactly one floor-shard job, each shard's --sum adds exactly its parts, and the
# `floor` job ("security-floor suite") sums every shard: so the published count is the whole suite.
# THE POOL SHAPE (2026-10-04): every part runs in one bin/test-suite-run.sh pool instead, and the floor job
# relays that pool's `--tally ... floor` verdict and count. The workflow is checked in whichever shape it
# has — shard jobs present means the shard rules — with the same four finding classes either way.
# Checked against governance.yml, and against workflows written here that break each clause.
WF_IN="${HARBOR_STATUS_WORKFLOW:-${HARBOR_WORKFLOW:-}}"  # a proposed workflow, read before t_init clears the caller's HARBOR_* (harbor#773)
. "$(dirname "$0")/../../lib/core.sh"; t_init

wf_table() { # <workflow> -> TAB rows: run <job> <step-id> <path> | sum <job> <step-id> <ref> | out <job> <step-id> | needs <job> <job>
  awk '
    function refs(t, pat, kind,   r) {
      while (match(t, pat)) { r = substr(t, RSTART, RLENGTH); t = substr(t, RSTART + RLENGTH)
        if (kind == "run") { sub(/^--run /, "", r); print "run\t" job "\t" sid "\t" r }
        else { sub(/\.outputs\.count$/, "", r); print "sum\t" job "\t" sid "\t" r } }
    }
    function flush() {
      refs(stext, "--run tests/admission/baseline/[A-Za-z0-9._-]+", "run")
      if (stext ~ /--sum/) refs(stext, "(steps|needs)\\.[A-Za-z0-9_-]+\\.outputs\\.count", "sum")
      sid = ""; stext = ""
    }
    /^[[:space:]]*#/ { next }
    /^jobs:/ { injobs = 1; next }
    !injobs { next }
    /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { flush(); job = $1; sub(/:$/, "", job); inout = 0; insteps = 0; next }
    /^    outputs:/ { inout = 1; next }
    /^    needs:/ { n = $0; sub(/^    needs:[[:space:]]*/, "", n); gsub(/[][ ]/, "", n)
                    k = split(n, a, ","); for (i = 1; i <= k; i++) if (a[i] != "") print "needs\t" job "\t" a[i] }
    /^    steps:/ { flush(); insteps = 1; inout = 0; next }
    /^    [A-Za-z-]+:/ { inout = 0 }
    inout && /^      count:/ && match($0, /steps\.[A-Za-z0-9_-]+\.outputs/) {
      print "out\t" job "\t" substr($0, RSTART + 6, RLENGTH - 14) }
    insteps && /^      - / { flush(); if ($2 == "id:") sid = $3 }
    insteps && /^        id:/ { sid = $2 }
    insteps { stext = stext " " $0 }
    END { flush() }
  ' "$1"
}

shard_findings() { # <workflow> <root> -> one finding per line; empty when the partition holds
  _pf="$T_TMP/parts.$$"
  find "$2/tests/admission/baseline" -name '*.test.sh' 2>/dev/null \
    | sed "s|^$2/||" | sort > "$_pf"
  wf_table "$1" | awk -F '\t' -v root="$2" -v pf="$_pf" '
    BEGIN { while ((getline p < pf) > 0) { part[p] = 1; np++ } }
    function isshard(j) { return j ~ /^floor-shard-[0-9]+$/ }
    function isfloor(p) { return p ~ /^tests\/admission\/baseline\/[A-Za-z0-9_-]+\.test\.sh$/ }
    $1 == "run" { if (isfloor($4)) { runs[$4]++; if (isshard($2)) { srun[$4]++; stepof[$2 SUBSEP $3] = $4 }
                    if (!($4 in part)) print "missing: " $2 " runs " $4 ", which is not on disk"
                    if (isshard($2) && $3 == "") print "summed: " $4 " in " $2 " has no step id to sum" }
                  if (isshard($2)) shardjob[$2] = 1 }
    $1 == "sum" { summed[$2 SUBSEP $4]++; sumstep[$2] = $3 }
    $1 == "out" { outstep[$2] = $3 }
    $1 == "needs" { need[$2 SUBSEP $3] = 1 }
    END {
      if (np == 0) print "runs: no floor part found on disk under " root "/tests/admission/baseline"
      for (p in part) {
        if (runs[p] + 0 != 1) print "runs: " p " is run by " runs[p] + 0 " steps (want exactly 1)"
        else if (srun[p] + 0 != 1) print "runs: " p " is not run by a floor-shard job"
      }
      ns = 0
      for (j in shardjob) { ns++
        for (k in stepof) { split(k, q, SUBSEP)
          if (q[1] == j && q[2] != "" && summed[j SUBSEP "steps." q[2]] + 0 != 1)
            print "summed: " stepof[k] " (step " q[2] ") is summed " summed[j SUBSEP "steps." q[2]] + 0 " times by " j }
        for (k in summed) { split(k, q, SUBSEP); s = q[2]; sub(/^steps\./, "", s)
          if (q[1] == j && !((j SUBSEP s) in stepof)) print "summed: " j " sums " q[2] ", which runs no floor part" }
        if (!(j in sumstep) || outstep[j] != sumstep[j]) print "summed: " j "'"'"'s count output is not its --sum step"
        if (!need["floor" SUBSEP j]) print "floor: the floor job does not need " j
        if (summed["floor" SUBSEP "needs." j] + 0 != 1) print "floor: the floor job sums " j " " summed["floor" SUBSEP "needs." j] + 0 " times (want 1)"
      }
      if (ns == 0) print "runs: no floor-shard job runs a floor part"
      if (!("floor" in sumstep) || outstep["floor"] != sumstep["floor"]) print "floor: the floor job'"'"'s count output is not its --sum step"
      for (k in summed) { split(k, q, SUBSEP)
        if (q[1] == "floor") { j = q[2]; sub(/^needs\./, "", j); if (!(j in shardjob)) print "floor: the floor job sums " q[2] ", which runs no floor part" } }
    }' | sort
}
# POOL SHAPE: one `test-suite-run.sh --tally <results> floor <parts>` covers each part once, none macOS-only
# or missing from suites-quick.txt; the always() relay checks `pass` and republishes floor_count. Or the
# tally loops `for g in … floor …` over contracts/suites-tally.txt's `floor` rows (harbor#961).
pool_table() { # <workflow> -> TAB rows: tally <job> <sid> <words> | out <job> <name> <expr> | needs <job> <job> | always <job> | pass <job> <pool>
  awk '
    /^[[:space:]]*#/ { next }
    /^jobs:/ { injobs = 1; next }
    !injobs { next }
    /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { job = $1; sub(/:$/, "", job); inout = 0; sid = ""; next }
    /^    outputs:/ { inout = 1; next }
    /^    [A-Za-z-]+:/ { inout = 0 }
    /^    if:[[:space:]]*\$\{\{[[:space:]]*always\(\)[[:space:]]*\}\}/ { print "always\t" job }
    /^    needs:/ { n = $0; sub(/^    needs:[[:space:]]*/, "", n); gsub(/[][ ]/, "", n)
                  k = split(n, a, ","); for (i = 1; i <= k; i++) if (a[i] != "") print "needs\t" job "\t" a[i] }
    inout && /^      [A-Za-z0-9_]+:/ { nm = $1; sub(/:$/, "", nm); e = $0; sub(/^[^:]*:[[:space:]]*/, "", e); print "out\t" job "\t" nm "\t" e }
    /^      - / { sid = ""; lv = ""; ll = ""; if ($2 == "id:") sid = $3 }
    /^        id:/ { sid = $2 }
    /^[[:space:]]+for [A-Za-z_][A-Za-z0-9_]* in [^;]*;[[:space:]]*do/ {
      l = $0; sub(/^[[:space:]]+for /, "", l); lv = l; sub(/ .*/, "", lv); sub(/^[^ ]+ in /, "", l); sub(/;.*/, "", l); ll = " " l " " }
    { for (i = 1; i < NF; i++) if ($i == "--tally" && $(i + 2) == "floor") {
        w = ""; for (j = i + 3; j <= NF; j++) w = w (w == "" ? "" : " ") $j; print "tally\t" job "\t" sid "\t" w }
      else if ($i == "--tally" && lv != "" && $(i + 2) == "\"$" lv "\"" && ll ~ / floor / && match($0, /contracts\/[A-Za-z0-9._-]+/))
        print "tally\t" job "\t" sid "\t@" substr($0, RSTART, RLENGTH) }
    match($0, /needs\.[A-Za-z0-9_-]+\.outputs\.floor[^_A-Za-z0-9]/) && /pass/ {
      p = substr($0, RSTART + 6); sub(/\.outputs.*/, "", p); print "pass\t" job "\t" p }
  ' "$1"
}

pool_findings() { # <workflow> <root> -> one finding per line; empty when the pool shape holds
  _pt="$T_TMP/pool.$$"; pool_table "$1" > "$_pt"
  _pp="$T_TMP/pparts.$$"
  find "$2/tests/admission/baseline" -name '*.test.sh' 2>/dev/null | sed "s|^$2/||" | sort > "$_pp"
  [ -s "$_pp" ] || echo "runs: no floor part found on disk under $2/tests/admission/baseline"
  _nt="$(awk -F '\t' '$1 == "tally"' "$_pt" | grep -c . || :)"
  [ "$_nt" -eq 1 ] || echo "runs: the floor tally appears $_nt times (want 1)"
  _pool="$(awk -F '\t' '$1 == "tally" { print $2; exit }' "$_pt")"
  _tsid="$(awk -F '\t' '$1 == "tally" { print $3; exit }' "$_pt")"
  _words="$(awk -F '\t' '$1 == "tally" { print $4; exit }' "$_pt")"
  # Expanded where the pool expands them: a glob in the repo root, a literal as itself, and @<file> as
  # that groups file's `floor` rows, word-split and globbed as the workflow's $(awk ...) is.
  case "$_words" in @*) [ -f "$2/${_words#@}" ] || echo "missing: the floor tally reads ${_words#@}, which is not on disk" ;; esac
  ( cd "$2" && set +f && for _w in $_words; do
      case "$_w" in
        @*) for _f in $(awk '$1 == "floor" { print $2 }' "${_w#@}" 2>/dev/null); do printf '%s\n' "$_f"; done ;;
        *) for _f in $_w; do printf '%s\n' "$_f"; done ;;
      esac
    done ) > "$T_TMP/tallied.$$"
  while IFS= read -r _f; do [ -f "$2/$_f" ] || echo "missing: the floor tally names $_f, which is not on disk"; done < "$T_TMP/tallied.$$"
  while IFS= read -r _p; do
    _c="$(grep -Fxc -- "$_p" "$T_TMP/tallied.$$" || :)"
    [ "$_c" -eq 1 ] || echo "runs: $_p is tallied $_c times (want exactly 1)"
    awk '{ print $1 }' "$2/contracts/suites-quick.txt" 2>/dev/null | grep -Fxq -- "$_p" \
      || echo "runs: $_p is not in contracts/suites-quick.txt, so the quick level cannot tally it"
  done < "$_pp"
  awk -F '\t' -v pool="$_pool" -v sid="$_tsid" '
    $1 == "out" && $2 == pool && $3 == "floor_count" { pc = $4 }
    $1 == "out" && $2 == pool && $3 == "floor" { pv = $4 }
    $1 == "out" && $2 == "floor" && $3 == "count" { fc = $4 }
    $1 == "needs" && $2 == "floor" && $3 == pool { nd = 1 }
    $1 == "always" && $2 == "floor" { al = 1 }
    $1 == "pass" && $2 == "floor" && $3 == pool { ok = 1 }
    END {
      if (sid == "") print "summed: the step running the floor tally has no id to publish from"
      if (pc !~ "steps\\." sid "\\.outputs\\.floor_count") print "summed: the pool job does not publish the tally step'"'"'s floor_count"
      if (pv !~ "steps\\." sid "\\.outputs\\.floor[^_]") print "summed: the pool job does not publish the tally step'"'"'s floor verdict"
      if (fc !~ "needs\\." pool "\\.outputs\\.floor_count") print "summed: the floor job'"'"'s count is not the pool'"'"'s floor_count"
      if (!nd) print "floor: the floor job does not need the pool job " pool
      if (!al) print "floor: the floor job is not always() — a failed pool would SKIP it, and a skipped required check passes"
      if (!ok) print "floor: the floor job does not check the pool'"'"'s floor verdict is pass"
    }' "$_pt"
}

only() { printf '%s\n' "$2" | grep "^$1: " || printf 'none'; }  # <class> <findings>

WF="${WF_IN:-$T_ROOT/.github/workflows/governance.yml}"  # check a proposed workflow before it lands
t_section "the partition in governance.yml"
if grep -qE '^  floor-shard-[0-9]+:' "$WF"; then F="$(shard_findings "$WF" "$T_ROOT")"; else F="$(pool_findings "$WF" "$T_ROOT")"; fi
t_eq "the floor has parts to partition" yes "$([ "$(find "$T_ROOT/tests/admission/baseline" -name '*.test.sh' ! -name baseline.test.sh | grep -c .)" -ge 2 ] && echo yes || echo no)"
t_eq "every floor part runs in exactly one floor-shard job" none "$(only runs "$F")"
t_eq "every floor step names a part on disk" none "$(only missing "$F")"
t_eq "each shard's --sum adds each of its parts once and nothing else" none "$(only summed "$F")"
t_eq "the floor job needs and sums every shard once" none "$(only floor "$F")"

# The workflows below are written here, never copied from governance.yml, one clause broken in each.
FR="$T_TMP/root"; mkdir -p "$FR/tests/admission/baseline" "$FR/tests/admission/equivalence" "$FR/contracts"
for _p in baseline.test a.test b.test c.test; do : > "$FR/tests/admission/baseline/$_p.sh"; done
: > "$FR/tests/admission/baseline/fixture.sh"; : > "$FR/tests/admission/equivalence/equivalence.test.sh"  # neither is a part
shard() { # <n> <step-id:part>... — a floor-shard job
  printf '  floor-shard-%s:\n    needs: [preflight]\n    outputs:\n      count: ${{ steps.suite.outputs.count }}\n    steps:\n      - uses: actions/checkout@v5\n' "$1"
  _n="$1"; shift; _s=""
  for _ip in "$@"; do
    printf '      - name: %s\n        id: %s\n        run: sh bin/test-suite-select.sh --run tests/admission/baseline/%s.sh\n' "${_ip#*:}" "${_ip%%:*}" "${_ip#*:}"
    _s="$_s \"\${{ steps.${_ip%%:*}.outputs.ran }}:\${{ steps.${_ip%%:*}.outputs.count }}\""
  done
  printf '      - name: sum\n        id: suite\n        run: >-\n          sh bin/test-suite-select.sh --sum%s\n' "$_s"
}
floorjob() { # <shard-n>... — the aggregator
  _nd=""; _s=""
  for _k in "$@"; do _nd="$_nd${_nd:+, }floor-shard-$_k"
    _s="$_s \"\${{ needs.floor-shard-$_k.outputs.ran }}:\${{ needs.floor-shard-$_k.outputs.count }}\""; done
  printf '  floor:\n    name: security-floor suite\n    needs: [%s]\n    outputs:\n      count: ${{ steps.sum.outputs.count }}\n    steps:\n      - id: sum\n        run: sh bin/test-suite-select.sh --sum%s\n' "$_nd" "$_s"
}
wf() { printf 'name: g\njobs:\n'; cat; }
findings() { wf > "$T_TMP/wf.yml"; shard_findings "$T_TMP/wf.yml" "$FR"; }

t_section "the check can fail: a workflow written here, one clause broken at a time"
G="$( { shard 0 m:baseline.test a:a.test; shard 1 b:b.test c:c.test; floorjob 0 1; } )"
t_eq "the well-formed control has no finding" none "$(printf '%s\n' "$G" | findings | grep . || printf 'none')"
t_has "a part in two shard jobs" "$( { shard 0 m:baseline.test a:a.test; shard 1 b:b.test c:c.test a2:a.test; floorjob 0 1; } | findings)" \
  'runs: tests/admission/baseline/a.test.sh is run by 2 steps'
t_has "a part in no job" "$( { shard 0 m:baseline.test a:a.test; shard 1 b:b.test; floorjob 0 1; } | findings)" \
  'runs: tests/admission/baseline/c.test.sh is run by 0 steps'
t_has "a part run only outside a shard job" "$( { shard 0 m:baseline.test a:a.test; shard 1 b:b.test; floorjob 0 1
  printf '  fast:\n    steps:\n      - id: x\n        run: sh bin/test-suite-select.sh --run tests/admission/baseline/c.test.sh\n'; } | findings)" \
  'runs: tests/admission/baseline/c.test.sh is not run by a floor-shard job'
t_has "a step naming a part that is not on disk" "$( { shard 0 m:baseline.test a:a.test z:zz.test; shard 1 b:b.test c:c.test; floorjob 0 1; } | findings)" \
  'missing: floor-shard-0 runs tests/admission/baseline/zz.test.sh'
t_has "a part step its shard does not sum" "$(printf '%s\n' "$G" | sed 's/ "${{ steps.c.outputs.ran }}:${{ steps.c.outputs.count }}"//' | findings)" \
  'summed: tests/admission/baseline/c.test.sh (step c) is summed 0 times by floor-shard-1'
t_has "a shard that sums a step running no part" "$(printf '%s\n' "$G" | sed 's/--sum "/--sum "${{ steps.replay.outputs.count }}" "/' | findings)" \
  'summed: floor-shard-0 sums steps.replay, which runs no floor part'
t_has "a shard whose count is not its sum" "$(printf '%s\n' "$G" | awk '!d && sub(/steps\.suite\.outputs\.count/, "steps.m.outputs.count") { d = 1 } 1' | findings)" \
  "count output is not its --sum step"
t_has "a floor job that skips a shard" "$( { shard 0 m:baseline.test a:a.test; shard 1 b:b.test c:c.test; floorjob 0; } | findings)" \
  'floor: the floor job sums floor-shard-1 0 times'
t_has "a floor job that does not need a shard" "$(printf '%s\n' "$G" | sed 's/needs: \[floor-shard-0, floor-shard-1\]/needs: [floor-shard-0]/' | findings)" \
  'floor: the floor job does not need floor-shard-1'
t_has "a comment naming a part is not a run" "$( { printf '  # sh bin/test-suite-select.sh --run tests/admission/baseline/c.test.sh\n'; shard 0 m:baseline.test a:a.test; shard 1 b:b.test; floorjob 0 1; } | findings)" \
  'runs: tests/admission/baseline/c.test.sh is run by 0 steps'

t_section "the pool shape can fail: a workflow written here, one clause broken at a time"
printf 'tests/admission/baseline/baseline.test.sh\ntests/admission/baseline/a.test.sh\ntests/admission/baseline/b.test.sh\ntests/admission/baseline/c.test.sh\n' > "$FR/contracts/suites-quick.txt"
pool() { # [tally words] — a pool job and the floor relay
  printf '  suites:\n    outputs:\n      floor: ${{ steps.tally.outputs.floor }}\n      floor_count: ${{ steps.tally.outputs.floor_count }}\n    steps:\n'
  printf '      - id: run\n        run: sh bin/test-suite-run.sh --results r\n      - id: tally\n        run: |\n          sh bin/test-suite-run.sh --tally r floor %s\n' \
    "${1:-tests/admission/baseline/*.test.sh}"
  printf '  floor:\n    name: security-floor suite\n    needs: [suites]\n    if: ${{ always() }}\n    outputs:\n      count: ${{ needs.suites.outputs.floor_count }}\n'
  printf '    steps:\n      - run: test "${{ needs.suites.outputs.floor }}" = pass\n'
}
pfind() { wf > "$T_TMP/pwf.yml"; pool_findings "$T_TMP/pwf.yml" "$FR"; }
t_eq "the well-formed pool control has no finding" none "$(pool | pfind | grep . || printf 'none')"
t_has "a tally that misses a part" "$(pool 'tests/admission/baseline/baseline.test.sh tests/admission/baseline/a.test.sh tests/admission/baseline/b.test.sh' | pfind)" \
  'runs: tests/admission/baseline/c.test.sh is tallied 0 times'
t_has "a part tallied twice" "$(pool 'tests/admission/baseline/*.test.sh tests/admission/baseline/a.test.sh' | pfind)" \
  'runs: tests/admission/baseline/a.test.sh is tallied 2 times'
t_has "a tally naming a part not on disk" "$(pool 'tests/admission/baseline/*.test.sh tests/admission/baseline/zz.test.sh' | pfind)" \
  'missing: the floor tally names tests/admission/baseline/zz.test.sh'
t_has "a part the quick level leaves out" "$(sed -i.bak '/baseline\/c\.test/d' "$FR/contracts/suites-quick.txt"; pool | pfind; mv "$FR/contracts/suites-quick.txt.bak" "$FR/contracts/suites-quick.txt")" \
  'runs: tests/admission/baseline/c.test.sh is not in contracts/suites-quick.txt'
t_has "no tally at all" "$(pool | sed '/--tally/d' | pfind)" 'runs: the floor tally appears 0 times'
t_has "a floor job that is not always()" "$(pool | sed '/always()/d' | pfind)" 'floor: the floor job is not always()'
t_has "a floor job that never checks pass" "$(pool | sed 's/ = pass/ = success/' | pfind)" 'floor: the floor job does not check'
t_has "a floor job that does not need the pool" "$(pool | sed 's/needs: \[suites\]/needs: [other]/' | pfind)" 'floor: the floor job does not need the pool job suites'
t_has "a count that is not the pool's" "$(pool | sed 's/count: ${{ needs.suites.outputs.floor_count }}/count: 1/' | pfind)" "summed: the floor job's count is not the pool's floor_count"
t_has "a pool that publishes another step's count" "$(pool | sed 's/floor_count: ${{ steps.tally/floor_count: ${{ steps.run/' | pfind)" "summed: the pool job does not publish the tally step's floor_count"

t_section "the groups file can fail too (harbor#961): the tally loops over groups read from CONTRACTS"
GT="$FR/contracts/suites-tally.txt"
printf 'floor tests/admission/baseline/baseline.test.sh\nfloor tests/admission/baseline/?.test.sh   # every part\nlint tests/checks/x-test.sh\n' > "$GT"
cat > "$T_TMP/gloop" <<'LOOP'
          for g in floor lint; do
            sh bin/test-suite-run.sh --tally r "$g" $(awk -v g="$g" '$1 == g { print $2 }' contracts/suites-tally.txt)
          done
LOOP
gpool() { pool | awk -v f="$T_TMP/gloop" '/--tally/ { while ((getline l < f) > 0) print l; next } 1'; }
t_eq "the well-formed groups-file control has no finding" none "$(gpool | pfind | grep . || printf 'none')"
t_has "a floor part dropped from the groups file" "$(sed -i.bak '/?\.test/d' "$GT"; gpool | pfind; mv "$GT.bak" "$GT")" \
  'runs: tests/admission/baseline/a.test.sh is tallied 0 times'
t_has "a loop that tallies no floor group" "$(gpool | sed 's/for g in floor lint/for g in lint/' | pfind)" 'runs: the floor tally appears 0 times'
t_has "a groups file that is not on disk" "$(mv "$GT" "$GT.off"; gpool | pfind; mv "$GT.off" "$GT")" \
  'missing: the floor tally reads contracts/suites-tally.txt'

t_section "every part runs or stands down together (--sum refuses a split)"
_decl() { awk -v k="$1" '$1 == k { $1 = ""; sub(/^ /, ""); print; exit }' "$T_ROOT/contracts/suite-paths.txt"; }
D0="$(_decl tests/admission/baseline/baseline.test.sh)"
t_has "the main part declares the fixture it sources" "$D0" 'tests/admission/baseline/fixture.sh'
_split=""
for _p in $(find "$T_ROOT/tests/admission/baseline" -name '*.test.sh' ! -name baseline.test.sh | sed "s|^$T_ROOT/||" | sort); do
  [ "$(_decl "$_p")" = "$D0" ] || _split="$_split $_p"
done
t_eq "every part's contracts/suite-paths.txt line equals the main part's" "" "$_split"
t_done
