#!/usr/bin/env sh
# permission-request-probe.sh (harbor#1018) — LIVE, by hand, never a suite: can a PermissionRequest hook answer the
# prompt an `ask` rule raises? Control and treatment through a real `claude -p`, each with one --settings file:
#   control    an ask rule on `touch …/approval-probe-*`
#   treatment  the same rule, plus a PermissionRequest hook that answers allow (and leaves a marker when it runs)
# The verdict is the files: the touched target (the call ran), the marker (the hook was consulted). Costs two short
# model calls on the operator's own login. What it cannot prove is in docs/design/approval-gate.md.
#   sh tests/gate/approval/permission-request-probe.sh [--model <id>]
set -u
command -v claude >/dev/null 2>&1 || { echo "probe: no claude on PATH" >&2; exit 2; }
W="$(mktemp -d "${TMPDIR:-/tmp}/pr-probe.XXXXXX")"; W="$(cd -P "$W" && pwd -P)"
MODEL=''; [ "${1:-}" != --model ] || MODEL="--model ${2:-}"
cat > "$W/hook.sh" <<EOF
#!/bin/sh
: > "$W/hook-fired"
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
EOF
jq -n --arg w "$W" '{permissions: {ask: ["Bash(touch \($w)/approval-probe-*)"]}}' > "$W/control.json"
jq -n --arg w "$W" '{permissions: {ask: ["Bash(touch \($w)/approval-probe-*)"]},
  hooks: {PermissionRequest: [{matcher: "Bash", hooks: [{type: "command", command: ("/bin/sh " + $w + "/hook.sh")}]}]}}' > "$W/treatment.json"
arm() { # <name>
  rm -f "$W/hook-fired"
  # shellcheck disable=SC2086
  ( cd "$W" && claude -p $MODEL --permission-mode default --settings "$W/$1.json" \
      "Run exactly this one Bash command, once, and nothing else: touch $W/approval-probe-$1" ) >"$W/$1.out" 2>&1 </dev/null
  printf '%s\tran=%s\thook=%s\n' "$1" "$([ -e "$W/approval-probe-$1" ] && echo yes || echo no)" "$([ -e "$W/hook-fired" ] && echo yes || echo no)"
}
claude --version
arm control
arm treatment
echo "transcripts: $W/control.out $W/treatment.out"
