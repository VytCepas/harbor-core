# tests/audit/triage/fixture.sh — what the failure-capture suites share (harbor#44). Source after
# t_init. mkfixture builds a config dir that is clean by construction; each red case adds one defect.
# Today is pinned (harbor#211) one day after the fixtures, so they sit inside the default 7d window.
SRC="$T_ROOT/bin"; FC="$SRC/audit-triage.sh"; FCT="$FC"; TMP="$T_TMP/fc"; mkdir -p "$TMP"
cp "$SRC/floor-verify.sh" "$SRC/guard-lib.sh" "$TMP/"  # a mutant in $TMP derives the probes from these
HOST=testhost
SALT=0123456789abcdef0123456789abcdef  # 32 hex, the length floor_obs_digest requires
HARBOR_AUDIT_TRIAGE_NOW=2026-08-03; export HARBOR_AUDIT_TRIAGE_NOW
mkfixture() { # <name> → the dir: floor wired, guard-lib present, sealed host dir, empty sink
  _d="$TMP/$1"; mkdir -p "$_d/bin" "$_d/MEMORY/OBSERVABILITY/$HOST"
  cp "$SRC/guard-lib.sh" "$_d/bin/guard-lib.sh"
  printf '#!/usr/bin/env sh\nexit 0\n' > "$_d/bin/floor-hook.sh"
  printf '#!/usr/bin/env sh\nexit 0\n' > "$_d/bin/guard-bash.sh"
  printf '%s\n' "$SALT" > "$_d/.helm-obs-salt"
  chmod 0600 "$_d/.helm-obs-salt"
  jq -n --arg c "/bin/sh $_d/bin/floor-hook.sh $_d/bin/guard-bash.sh" '
    {hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: $c}]}]}}' \
    > "$_d/settings.json"
  : > "$_d/MEMORY/OBSERVABILITY/$HOST/guard-decisions.jsonl"
  printf '%s' "$_d"
}
SINK_OF() { printf '%s' "$1/MEMORY/OBSERVABILITY/$HOST/guard-decisions.jsonl"; }
# floor-observe.sh holds the host dir at 0500 and FC-7 checks it: seal to be clean, unseal to append.
unseal() { chmod 0700 "$1/MEMORY/OBSERVABILITY/$HOST" 2>/dev/null || :; }
seal()   { chmod 0500 "$1/MEMORY/OBSERVABILITY/$HOST" 2>/dev/null || :; }
rec() { # <dir> <g> <d> <r> <ts> [digest] [file-suffix]
  printf '{"v":1,"ts":"%s","g":"%s","d":"%s","r":"%s","s":"meta","t":"none","h":"%s"}\n' \
    "$5" "$2" "$3" "$4" "${6:--}" >> "$(SINK_OF "$1")${7:-}"
}
recn() { _n="$1"; shift; _i=0; while [ "$_i" -lt "$_n" ]; do rec "$@"; _i=$((_i+1)); done; }  # <n> <rec args>
census() { # <dir> <n> — equal session and integrity records, which satisfies FC-1
  _i=0; while [ "$_i" -lt "$2" ]; do
    rec "$1" session armed floor-armed "2026-08-02T10:0$_i:00Z"
    rec "$1" integrity allow integrity-clean "2026-08-02T10:0$_i:01Z"
    _i=$((_i+1))
  done
}
# Session records for a fixture that adds integrity records of its own, so FC-1 cannot mask the rule.
sessions() { _i=0; while [ "$_i" -lt "$2" ]; do rec "$1" session armed floor-armed "2026-08-02T11:1$_i:00Z"; _i=$((_i+1)); done; }
json_of() { sh "$FCT" "$@" --json 2>/dev/null; }  # <dir> [flags…]; FCT is the real tool unless a mutant is set
q() { _q="$1"; shift; json_of "$@" | jq -r "$_q" 2>/dev/null; }  # <filter> <dir> [flags…]
rules_of() { # <dir> [flags…] → the unique rules, or NO-REPORT when the tool printed no report
  _j="$(json_of "$@")"
  printf '%s' "${_j:-null}" | jq -r 'if type == "object" and has("findings")
    then [.findings[].rule] | unique | join(" ") else "NO-REPORT" end' 2>/dev/null || echo NO-REPORT
}
has_rule() { # <dir> <rule> [flags…] → yes | no | NO-REPORT
  _hd="$1"; _hr="$2"; shift 2; _hl="$(rules_of "$_hd" "$@")"
  case " $_hl " in " NO-REPORT ") echo NO-REPORT ;; *" $_hr "*) echo yes ;; *) echo no ;; esac
}
of_rule() { q "[.findings[]|select(.rule==\"$3\")|.$1]|$4" "$2"; }  # <field> <dir> <rule> <reducer>
sev_of()    { of_rule severity "$1" "$2" 'unique|join(" ")'; }
subj_of()   { of_rule subject "$1" "$2" 'join(" ")'; }
repair_of() { of_rule repair "$1" "$2" 'join(" ")'; }
breaks_of() { of_rule breaks "$1" "$2" 'join(" ")'; }
count_of()  { of_rule rule "$1" "$2" 'length'; }
worst_of()  { q '.worst' "$1"; }
# The independent digest oracle: `<salt>:<subject>`, no newline, first 16 hex, recomputed with a plain
# pipeline rather than the function the tool calls, so a shared bug cannot pass both sides.
digest_of() {
  if command -v sha256sum >/dev/null 2>&1; then printf '%s:%s' "$SALT" "$1" | sha256sum | cut -c1-16
  else printf '%s:%s' "$SALT" "$1" | shasum -a 256 | cut -c1-16; fi
}
# One probe subject, read out of floor-verify.sh as the tool reads it and never copied here: one of
# the six carries a provider-token shape, which guard-egress refuses to write to disk.
PROBE_SUBJ="$(awk '/^probe[[:space:]]/ {
      s = $0; i = index(s, "{"); if (i == 0) next
      s = substr(s, i)
      j = 0; for (k = length(s); k > 0; k--) if (substr(s, k, 1) == "}") { j = k; break }
      if (j == 0) next
      print substr(s, 1, j) }' "$SRC/floor-verify.sh" 2>/dev/null \
  | sed 's/\\"/"/g' | jq -r '.tool_input.command // empty' 2>/dev/null | head -1)"
D_PROBE_T="$(digest_of "${PROBE_SUBJ:-fallback-subject}")"  # stands in for one `harbor verify` run
D_REAL="$(digest_of 'some operator command that is not a probe')"
