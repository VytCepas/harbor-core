#!/usr/bin/env sh
# contracts/reconcile.md (harbor#1031 PR 1): every drift check answers `<check> --status` in the one shape.
# The adopters are DERIVED, never listed here: a controls.tsv check row whose script (bin/<emitted id, each . a ->.sh) answers --status,
# and the other way round, a script that uses the helper (status_init) without such a row is red. Each adopter is put
# in a green, a drifted, a fixed and a blind world and its report read against the contract; a fixture check that
# does not conform goes red, and a conforming one, a lint rule and a check that does not answer --status stay green.
# A driver (d_<id>_<verb>) is how this test reaches one check; an adopter without one is red.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/reference-check-fixture.sh"   # mkfixture, resettings: reference-check's own clean config dir
W="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)/rec"; mkdir -p "$W"; TMP="$W"   # physical: /var is a link, and memory-route keys off the real path
TAB="$(printf '\t')"; CT="$T_ROOT/standards/naming/controls.tsv"
SUT=""   # the script under test, set by audit_row

# ── the contract, as a reader ────────────────────────────────────────────────
conform() { # <check-id> <exit> <report> → one "[category] message" per way the report breaks contracts/reconcile.md
  awk -F'\t' -v id="$1" -v rc="$2" '
    function bad(c, m) { print "[" c "] " m }
    function num(x) { return x ~ /^[0-9]+$/ }
    NR == 1 { if ($0 != "reconcile\t1\t" id) bad("shape", "the first line is not reconcile<TAB>1<TAB>" id); next }
    fin { bad("shape", "a record after the closing one"); next }
    $1 == "new" || $1 == "standing" {
      if (NF != 6) { bad("shape", $1 " has " NF " fields, not 6"); next }
      if ($2 == "") bad("shape", "an empty key")
      if (seen[$2]++) bad("shape", "a key is listed twice")
      if ($1 == "new" && $6 != "0") bad("shape", "a new row with an age")
      if ($1 == "standing" && $6 != "-" && !num($6)) bad("shape", "a standing row whose age is not seconds")
      rows++; next }
    $1 == "cleared" { if (NF != 2) bad("shape", "cleared has " NF " fields, not 2"); cl++; next }
    $1 == "summary" { if (NF != 4 || !num($2) || !num($3) || !num($4)) bad("shape", "summary is not three numbers"); sm = 1; dr = $3 + 0; scl = $4 + 0; fin = 1; next }
    $1 == "unchecked" { if (NF != 2 || $2 == "") bad("shape", "unchecked carries no reason"); un = 1; fin = 1; next }
    { bad("shape", "an unknown record") }
    END {
      if (NR == 0) { bad("shape", "no output"); exit }
      if (!sm && !un) bad("shape", "no closing record, summary or unchecked")
      if (sm && dr != rows + 0) bad("shape", "summary counts " dr " drifted and " rows + 0 " rows are listed")
      if (sm && scl != cl + 0) bad("shape", "summary counts " scl " cleared and " cl + 0 " are listed")
      if (sm && rc != (dr > 0 ? 1 : 0)) bad("exit", "exit " rc " beside " dr " drifted")
      if (un && rc != 3) bad("exit", "unchecked beside exit " rc)
      if (un && rows + cl > 0) bad("shape", "rows before unchecked")
      if (rc !~ /^[013]$/) bad("exit", "exit " rc " is none of 0, 1, 3")
    }' "$3"
}
keys_of() { awk -F'\t' -v t="$2" '$1 == t { print $2 }' "$1" | LC_ALL=C sort; }   # <report> <record type>
snap() { # <dir> → every path and content under it except a cache/ dir, which --status may write
  (cd "$1" && find . -name cache -prune -o -print | LC_ALL=C sort | while IFS= read -r _f; do
     if [ -L "$_f" ]; then printf '%s -> %s\n'  "$_f" "$(readlink "$_f")"
     elif [ -f "$_f" ]; then printf '%s %s\n' "$_f" "$(cksum < "$_f")"
     else printf '%s\n' "$_f"; fi; done)
}

# ── the drivers: how this test puts one check in a state and runs it ─────────
# Verbs: setup <world> (green), break/fix <world>, run <world> <out> [flags] (the report in <out>, the check's exit as ours), plain <world> (the exit of the
# check's own run), blind <world> <out> (a --status run that cannot look), cfg <world> (where the first-seen state lives). The default driver reads CLAUDE_CONFIG_DIR and has no states.
d_default_setup() { mkdir -p "$1"; }
d_default_cfg()   { printf '%s' "$1"; }
d_default_run()   { _w="$1"; _o="$2"; shift 2; CLAUDE_CONFIG_DIR="$_w" sh "$SUT" "$@" > "$_o" 2>/dev/null < /dev/null; }

mr_key()   { printf '%s' "$1" | sed 's|/|-|g'; }
mr_route() { _k="$(mr_key "$1/$2")"; mkdir -p "$1/cfg/projects/$_k"; ln -s "$1/cfg/projects/$(mr_key "$1")/memory" "$1/cfg/projects/$_k/memory"; }   # <world> <repo>
d_memory_route_setup() { # a box whose two governed repos both reach the one store; the registry is the private layer's (harbor#1149)
  mkdir -p "$1/cfg/projects" "$1/repo" "$1/priv/inject.d/box" "$1/zorbcorp" "$1/blorp" "$1/cfg/projects/$(mr_key "$1")/memory"
  printf 'x\n' > "$1/cfg/projects/$(mr_key "$1")/memory/a.md"
  printf '# registry\nzorbcorp\t~/zorbcorp\tw\nblorp\t~/blorp\tw\n' > "$1/priv/inject.d/box/projects.tsv"
  mr_route "$1" zorbcorp; mr_route "$1" blorp
}
d_memory_route_break() { rm -f "$1/cfg/projects/$(mr_key "$1/blorp")/memory"; }
d_memory_route_fix()   { mr_route "$1" blorp; }
d_memory_route_cfg()   { printf '%s' "$1/cfg"; }
d_memory_route_run()   { _w="$1"; _o="$2"; shift 2; HOME="$_w" PORT_ROOT="$_w/port" HARBOR_SCOPE_PRIVATE="$_w/priv" HARBOR_SCOPE_REPO="$_w/repo" sh "$SUT" --dir "$_w/cfg" "$@" > "$_o" 2>/dev/null < /dev/null; }
d_memory_route_plain() { d_memory_route_run "$1" /dev/null; }
d_memory_route_blind() { # no registry: the governed repos are unknown
  mv "$1/priv/inject.d/box/projects.tsv" "$1/projects.tsv.away"
  d_memory_route_run "$1" "$2" --status; _r=$?
  mv "$1/projects.tsv.away" "$1/priv/inject.d/box/projects.tsv"; return $_r
}

d_drift_reference_check_setup() { mkfixture "${1##*/}" > /dev/null; }
d_drift_reference_check_break() { # a missing script wired under three matchers: the same item reported by each wiring, which must still be one row
  resettings "$1" --arg c "/bin/sh $1/bin/GONE.sh" '.hooks.SessionStart += [{matcher: "x", hooks: [{type: "command", command: $c}]}]
    | .hooks.PreToolUse = [{matcher: "Write|Edit", hooks: [{type: "command", command: $c}]}, {matcher: "WebFetch", hooks: [{type: "command", command: $c}]}]'
  printf '[gone](./NOPE.md)\n' >> "$1/CLAUDE.md"
}
d_drift_reference_check_fix() { resettings "$1" 'del(.hooks.SessionStart[1]) | del(.hooks.PreToolUse)'; printf '# c\n[a](./REAL.md) [b](https://example.com/x) [c](#anchor)\n' > "$1/CLAUDE.md"; }
d_drift_reference_check_cfg()   { printf '%s' "$1"; }
d_drift_reference_check_run()   { _w="$1"; _o="$2"; shift 2; sh "$SUT" "$_w" "$@" > "$_o" 2>/dev/null < /dev/null; }
d_drift_reference_check_plain() { d_drift_reference_check_run "$1" /dev/null; }
d_drift_reference_check_blind() { # no jq on PATH: settings.json cannot be read
  mkdir -p "$W/nojq"
  for _b in sh awk sed sort uniq tr basename grep printf; do _p="$(command -v "$_b" 2>/dev/null)" && ln -sf "$_p" "$W/nojq/$_b" 2>/dev/null; done
  PATH="$W/nojq" sh "$SUT" "$1" --status > "$2" 2>/dev/null < /dev/null
}

# ── the audit of one check ───────────────────────────────────────────────────
audit_row() { # <id> <script> <strict> → "[category] id: message" per problem; strict also requires every state's driver
  id="$1"; SUT="$2"; strict="$3"; w="$W/$id"; rm -rf "$w"; p="$(printf '%s' "$id" | tr .- __)"
  _has() { command -v "d_${p}_$1" > /dev/null 2>&1; }
  _d()   { _v="$1"; shift; if _has "$_v"; then "d_${p}_$_v" "$@"; else "d_default_$_v" "$@"; fi; }
  _rep() { sed "s/^\[\([a-z0-9-]*\)\] /[\1] $id: /"; }   # a message names the check it is about
  _d setup "$w"
  snap "$w" > "$w.s0"
  # a green world
  _d run "$w" "$w.r1" --status; _rc=$?
  conform "$id" "$_rc" "$w.r1" | _rep
  snap "$w" > "$w.s0b"
  cmp -s "$w.s0" "$w.s0b" || echo "[read-only] $id: --status changed files outside cache/ in a green world"
  if [ "$strict" = 1 ]; then
    [ "$_rc" = 0 ] || echo "[exit] $id: the green world exits $_rc, not 0"
    grep -Eq "^(new|standing)${TAB}" "$w.r1" && echo "[shape] $id: the green world lists a drifted row"
  fi
  # a flag it does not take
  _d run "$w" "$w.u" --status --no-such-flag; _rc=$?
  [ "$_rc" = 2 ] || echo "[usage] $id: a bad flag beside --status exits $_rc, not 2"
  [ ! -s "$w.u" ] || echo "[usage] $id: a usage error printed on stdout"
  # the same world twice: nothing may flip to new
  _d run "$w" "$w.r1b" --status
  keys_of "$w.r1" new > "$w.k1"; keys_of "$w.r1" standing >> "$w.k1"; keys_of "$w.r1b" new > "$w.k2"
  if [ -s "$w.k1" ] && [ -n "$(LC_ALL=C sort "$w.k1" | comm -12 - "$w.k2")" ]; then
    echo "[second-run] $id: a row the first run listed is new again on the second"
  fi
  if ! _has break || ! _has fix; then
    [ "$strict" = 1 ] && echo "[driver] $id: no d_${p}_break and d_${p}_fix, so its drifted and fixed states are unproved"
    return 0
  fi
  # a drifted world
  _d break "$w"
  snap "$w" > "$w.s1"
  _d run "$w" "$w.r2" --status; _rc=$?
  conform "$id" "$_rc" "$w.r2" | _rep
  [ "$_rc" = 1 ] || echo "[exit] $id: the drifted world exits $_rc, not 1"
  grep -q "^new${TAB}" "$w.r2" || echo "[second-run] $id: a first sighting is not a new row"
  grep -q "^standing${TAB}" "$w.r2" && echo "[second-run] $id: a first sighting is already standing"
  snap "$w" > "$w.s2"
  cmp -s "$w.s1" "$w.s2" || echo "[read-only] $id: --status changed files outside cache/"
  # the same drifted world again: no new row, the same keys, standing
  _d run "$w" "$w.r3" --status; _rc=$?
  conform "$id" "$_rc" "$w.r3" | _rep
  [ "$_rc" = 1 ] || echo "[exit] $id: the second run exits $_rc, not 1"
  keys_of "$w.r3" new | grep -q . && echo "[second-run] $id: a second run with nothing changed prints a new row"
  [ "$(keys_of "$w.r2" new)" = "$(keys_of "$w.r3" standing)" ] || echo "[second-run] $id: the rows the first run listed are not all standing on the second"
  # the verdict is the check's own: --status and the plain run exit alike
  if _has plain; then
    _d plain "$w"; _rc=$?
    [ "$_rc" = 1 ] || echo "[parity] $id: the plain run exits $_rc on the world --status calls drifted"
  fi
  # a standing row shows its age
  _cfg="$(_d cfg "$w")"; _st="$_cfg/cache/reconcile/$id.tsv"
  if [ -f "$_st" ]; then
    _then=$(( $(date +%s) - 7200 ))
    awk -F'\t' -v t="$_then" 'BEGIN { OFS = "\t" } { print $1, t }' "$_st" > "$_st.t" && mv "$_st.t" "$_st"
    _d run "$w" "$w.r3a" --status
    _n="$(grep -c "^standing${TAB}" "$w.r3a")"
    _ok="$(awk -F'\t' '$1 == "standing" && $6 >= 7200 && $6 < 7320 { n++ } END { print n + 0 }' "$w.r3a")"
    { [ "$_n" -gt 0 ] && [ "$_n" = "$_ok" ]; } || echo "[age] $id: a row first seen two hours ago does not show an age of two hours"
  else
    echo "[age] $id: no first-seen state at cache/reconcile/$id.tsv after a drifted run"
  fi
  # a blind run says so, exits 3, and leaves the ages alone
  if _has blind; then
    _d blind "$w" "$w.r4"; _rc=$?
    conform "$id" "$_rc" "$w.r4" | _rep
    [ "$_rc" = 3 ] || echo "[blind] $id: a run that cannot look exits $_rc, not 3"
    grep -q "^unchecked${TAB}" "$w.r4" || echo "[blind] $id: a run that cannot look prints no unchecked record"
    _d run "$w" "$w.r5" --status
    keys_of "$w.r5" new | grep -q . && echo "[blind] $id: the run after a blind one lists a new row, so the blind run reset the ages"
  elif [ "$strict" = 1 ]; then
    echo "[driver] $id: no d_${p}_blind, so its could-not-judge exit is unproved"
  fi
  # fixed: the rows clear once, then the report is quiet
  _d fix "$w"
  _d run "$w" "$w.r6" --status; _rc=$?
  conform "$id" "$_rc" "$w.r6" | _rep
  [ "$_rc" = 0 ] || echo "[fixed] $id: the fixed world exits $_rc, not 0"
  grep -q "^cleared${TAB}" "$w.r6" || echo "[fixed] $id: the rows that converged are not reported cleared"
  _d run "$w" "$w.r7" --status
  grep -Eq "^(cleared|new|standing)${TAB}" "$w.r7" && echo "[fixed] $id: a cleared row is reported again on the next run"
  return 0
}

# What makes a check an adopter is that its script answers --status: it calls the helper, or takes the flag. `--status` on a check is the reconcile interface,
# so a check with another meaning for the flag would be audited as this one and go red. It is not an owner cell: standard-catalog.sh places a file through the
# owner of the controls whose engine it is, and a check row owned by another family unplaces docs/reference/checks.md (engine_owner_splits below). Only a command word counts, never a comment or a string.
uses_helper()    { grep -v '^[[:space:]]*#' "$1" | grep -Eq '(^|[;&|({]|then|do)[[:space:]]*status_init[[:space:]]'; }
answers_status() { uses_helper "$1" || grep -v '^[[:space:]]*#' "$1" | grep -Eq -- '--status\)'; }
check_scripts() { # <controls.tsv> → "<script name><TAB><check id>" for every check row (a row with no emitted id has no derivable script)
  # The check id is <family>.<object> and its script bin/<family>-<object>.sh (harbor#961 W5): the name is the id, each dot a dash.
  awk -F'\t' '/^#/ || $1 == "id" { next } $3 == "check" && $12 != "-" { s = $12; gsub(/\./, "-", s); print s "\t" $12 }' "$1"
}
adopter_rows() { # <controls.tsv> <root> → "<check id><TAB><script name>" for the check rows whose script exists and answers --status
  check_scripts "$1" | while IFS="$TAB" read -r _e _id; do
    [ -f "$2/bin/$_e.sh" ] && answers_status "$2/bin/$_e.sh" && printf '%s\t%s\n' "$_id" "$_e"
  done
}
engine_owner_splits() { # <controls.tsv> → each engine file whose check rows do not share one owner
  awk -F'\t' '/^#/ || $1 == "id" { next } $3 == "check" { if (!($4 in o)) o[$4] = $10; else if (o[$4] != $10) bad[$4] = 1 } END { for (e in bad) print e }' "$1" | LC_ALL=C sort
}
audit_registry() { # <controls.tsv> <root> <strict> → the problems of every adopter the file names
  adopter_rows "$1" "$2" > "$W/adopters"
  [ -s "$W/adopters" ] || echo "[derive] no check row in controls.tsv names a script that answers --status"
  check_scripts "$1" | cut -f1 > "$W/registered"
  for _f in "$2"/bin/*.sh $(sh "$2/bin/deploy-hooks.sh" --engines --root "$2" 2>/dev/null); do   # the other direction: a script on the helper that no row names is an adopter nobody audits
    [ -f "$_f" ] && [ ! -L "$_f" ] || continue   # a rename shim is an old name of a script judged under its own
    _b="${_f##*/}"; _b="${_b%.sh}"
    [ "$_b" = log-lib ] && continue
    uses_helper "$_f" && ! grep -qx "$_b" "$W/registered" && echo "[derive] $_b: bin/$_b.sh calls status_init and no check row in controls.tsv names it"
  done
  while IFS="$TAB" read -r _cid _sc; do
    audit_row "$_cid" "$2/bin/$_sc.sh" "$3"
  done < "$W/adopters"
}
# one category of an audit's output
cat_of() { printf '%s\n' "$1" | grep "^\[$2\]" || :; }   # <audit output> <category>

# ── the real tree ────────────────────────────────────────────────────────────
t_section "the adopters are derived from controls.tsv and the scripts, never listed"
DERIVED="$(adopter_rows "$CT" "$T_ROOT" | cut -f1)"
t_eq "the query finds adopters at all" yes "$([ -n "$DERIVED" ] && echo yes || echo no)"
t_eq "the adopters are memory-route.sh and drift-reference-check.sh, by their check ids" "drift.reference-check memory.route" "$(printf '%s\n' $DERIVED | sort | tr '\n' ' ' | sed 's/ $//')"
t_eq "no script uses the helper without a check row naming it, and no adopter lacks its row (the derivation runs both ways)" "" "$(audit_registry "$CT" "$T_ROOT" 0 | grep '^\[derive\]' || :)"
t_eq "check rows of one engine file share one owner (a marker in the owner cell unplaces docs/reference/checks.md in standard-catalog.sh)" "" "$(engine_owner_splits "$CT")"

REAL="$(audit_registry "$CT" "$T_ROOT" 1)"
t_eq "the audit ran to its last step on every adopter (an empty problem list below is not an audit that never ran)" "" \
  "$(for _e in $DERIVED; do [ -f "$W/$_e.r7" ] || echo "$_e"; done)"
t_section "every adopter's report is in the one shape, and its exit agrees with it"
t_eq "shape" "" "$(cat_of "$REAL" shape)"
t_eq "exit" "" "$(cat_of "$REAL" exit)"
t_eq "driver" "" "$(cat_of "$REAL" driver; cat_of "$REAL" derive)"
t_section "a second run with nothing changed adds no new row, and a standing row shows its age"
t_eq "second run" "" "$(cat_of "$REAL" second-run)"
t_eq "age" "" "$(cat_of "$REAL" age)"
t_section "usage is 2, could not judge is 3 and keeps the ages, and the verdict is the plain run's"
t_eq "usage" "" "$(cat_of "$REAL" usage)"
t_eq "blind" "" "$(cat_of "$REAL" blind)"
t_eq "parity" "" "$(cat_of "$REAL" parity)"
t_section "--status only reports, and a converged row is cleared once"
t_eq "read-only" "" "$(cat_of "$REAL" read-only)"
t_eq "fixed" "" "$(cat_of "$REAL" fixed)"

# ── fixture rows: the contract goes red on the one that does not conform ────
FX="$W/fx"; mkdir -p "$FX/bin"
fxrow() { printf '%s\twarn\t%s\tdocs/reference/checks.md\t-\tschedule\tdetective\texperimental\t-\t%s\t-\t%s\tfixture\n' "$1" "$2" "$3" "$4"; }   # <id> <type> <owner> <emitted>
# a conforming check, on the library: an odd key (a backslash, a quote, a space) must survive the first-seen state
cat > "$FX/bin/fixture-good.sh" <<GOOD
#!/usr/bin/env sh
case "\$*" in --status) ;; *) echo "usage: fixture-good.sh --status" >&2; exit 2 ;; esac
LOG_FD=2; . "$T_ROOT/bin/library-log.sh"; log_init fixture-good
status_init fixture-good "\$CLAUDE_CONFIG_DIR" || exit 3
status_ok 4
status_drift 'rule\\n "q" x' "want" "have" "fix it"
status_end; exit \$?
GOOD
# one that has nothing to report: a green with examined 0 is the check's own verdict
cat > "$FX/bin/fixture-quiet.sh" <<QUIET
#!/usr/bin/env sh
case "\$*" in --status) ;; *) echo "usage: fixture-quiet.sh --status" >&2; exit 2 ;; esac
LOG_FD=2; . "$T_ROOT/bin/library-log.sh"; log_init fixture-quiet
status_init fixture-quiet "\$CLAUDE_CONFIG_DIR" || exit 3
status_end; exit \$?
QUIET
printf '#!/usr/bin/env sh\ncase "$*" in --status) echo "everything is fine"; exit 0 ;; *) exit 2 ;; esac\n' > "$FX/bin/fixture-liar-prose.sh"
printf '#!/usr/bin/env sh\ncase "$*" in --status) ;; *) exit 2 ;; esac\nprintf "reconcile\\t1\\tfixture-liar-exit\\nnew\\tk\\twant\\thave\\tfix\\t0\\nsummary\\t1\\t1\\t0\\n"\nexit 0\n' > "$FX/bin/fixture-liar-exit.sh"
printf '#!/usr/bin/env sh\ncase "$*" in --status) ;; *) exit 2 ;; esac\nprintf "reconcile\\t1\\tfixture-liar-new\\nnew\\tk\\twant\\thave\\tfix\\t0\\nsummary\\t1\\t1\\t0\\n"\nexit 1\n' > "$FX/bin/fixture-liar-new.sh"
printf '#!/usr/bin/env sh\nexit 0\n' > "$FX/bin/fixture-other.sh"
okrows() { fxrow check.fixture-good check check fixture-good; fxrow check.fixture-quiet check check fixture-quiet
  fxrow drift.fixture-lint lint drift -; fxrow check.fixture-other check check fixture-other; }
mkctl() { # <1 to keep the conforming rows | 0> [row]... → the fixture controls.tsv
  { printf '# fixture controls.tsv\nid\tmode\ttype\tengine\tsurfaces\tmoment\tfunction\tstability\tsuccessor\towner\tred_proof\temitted\ttitle\n'
    if [ "$1" = 1 ]; then okrows; fi
    shift; for _r in "$@"; do printf '%s\n' "$_r"; done; } > "$FX/controls.tsv"
}
fxaudit() { audit_registry "$FX/controls.tsv" "$FX" "${1:-0}"; }
liar() { # <label> <id> <fragment>: one nonconforming row beside the conforming ones is named, and only it is
  mkctl 1 "$(fxrow "check.$2" check check "$2")"
  _lo="$(fxaudit)"
  t_has "$1" "$_lo" "$3"
  t_eq "...and nothing but $2 is named" "" "$(printf '%s\n' "$_lo" | grep -v "$2" | grep . || :)"
}

t_section "valid input that looks like a defect stays green"
mkctl 1
OKOUT="$(fxaudit)"
t_eq "a conforming check (odd key, library-written), one with nothing to report, a lint rule and a check that does not answer --status" "" "$OKOUT"
t_eq "...and the audit ran on the conforming check" yes "$(grep -q "^reconcile${TAB}1${TAB}fixture-good" "$W/fixture-good.r1" && echo yes)"
t_eq "...and its odd key (a backslash, a quote, a space) came back standing on the second run" 1 "$(grep -c "^standing${TAB}" "$W/fixture-good.r1b")"

t_section "a check that answers --status and does not conform goes red"
liar "prose where the report is" fixture-liar-prose "[shape] fixture-liar-prose: the first line is not reconcile"
liar "an exit code that disagrees with the report" fixture-liar-exit "[exit] fixture-liar-exit: exit 0 beside 1 drifted"
liar "a row that is new again on the second run" fixture-liar-new "[second-run] fixture-liar-new: a row the first run listed is new again on the second"
t_has "an adopter with no driver is red under the strict audit" "$(fxaudit 1)" "[driver] fixture-good: no d_fixture_good_break"

t_section "the derivation runs both ways, and a marker may not cost a file its owner"
# a script on the helper with no check row naming it is an adopter nobody audits
printf '#!/usr/bin/env sh\nLOG_FD=2; . "%s/bin/library-log.sh"\nstatus_init fixture-unlisted "$CLAUDE_CONFIG_DIR" || exit 3\nstatus_end; exit $?\n' "$T_ROOT" > "$FX/bin/fixture-unlisted.sh"
mkctl 1
_lo="$(fxaudit)"
t_has "a script that calls status_init and no check row names is red" "$_lo" "[derive] fixture-unlisted: bin/fixture-unlisted.sh calls status_init and no check row in controls.tsv names it"
t_eq "...and nothing else is named" "" "$(printf '%s\n' "$_lo" | grep -v fixture-unlisted | grep . || :)"
rm -f "$FX/bin/fixture-unlisted.sh"
# a comment, a string, or a word like it is not a call
printf '#!/usr/bin/env sh\n# status_init is documented in contracts/reconcile.md\necho "see status_init for the helper"\nstatus_initial=1\nexit 0\n' > "$FX/bin/fixture-mentions.sh"
t_eq "valid but unusual: a script that only mentions status_init (a comment, a string, status_initial) is not an adopter" "" "$(fxaudit)"
rm -f "$FX/bin/fixture-mentions.sh"
mkctl 0 "$(fxrow check.fixture-other check check fixture-other)"
t_has "no check that answers --status is itself a finding" "$(fxaudit)" "[derive] no check row in controls.tsv names a script that answers --status"
mkctl 1
t_eq "check rows of one engine file with one owner: no split" "" "$(engine_owner_splits "$FX/controls.tsv")"
mkctl 1 "$(fxrow check.fixture-marked check drift fixture-other)"
t_eq "one check row owned by another family than the rest of its engine file is named (the file is unplaced in standard-catalog.sh)" "docs/reference/checks.md" "$(engine_owner_splits "$FX/controls.tsv")"
mkctl 1; { printf '%s\n' "$(fxrow lint.a lint lint -)" "$(fxrow lint.b lint skill -)"; } >> "$FX/controls.tsv"
t_eq "valid but unusual: lint rows of one engine file with different owners are not a split (a lint engine owns many families)" "" "$(engine_owner_splits "$FX/controls.tsv")"

t_done
