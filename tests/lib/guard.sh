# tests/lib/guard.sh — fire a floor guard on one hook payload and name the verdict.
# Source after core.sh. Guards answer on three channels; t_decide folds them into
# one token so every guard suite asserts the same way:
#   allow (exit 0, no output) · ask|deny (permissionDecision) · block (exit 2) · exit-N

t_bash_json() { # <command> [extra top-level fields, each ending in a comma]
  printf '{"tool_name":"Bash",%s"tool_input":{"command":%s}}' "${2:-}" "$(printf '%s' "$1" | jq -Rs .)"
}
t_file_json() { # <path> [tool, default Write]
  printf '{"tool_name":"%s","tool_input":{"file_path":%s}}' "${2:-Write}" "$(printf '%s' "$1" | jq -Rs .)"
}

t_fold() { # <exit code> <stdout> — the one place a guard's answer becomes a token
  case "$1" in
    0) if [ -z "$2" ]; then echo allow
       else printf '%s' "$2" | jq -rs 'if length == 1 then .[0].hookSpecificOutput.permissionDecision // "PARSE_ERR"
                                         else "PARSE_ERR" end' 2>/dev/null || echo PARSE_ERR  # one decision, never two
       fi ;;
    2) echo block ;;
    *) echo "exit-$1" ;;
  esac
}

t_decide() { # <guard> <payload> [VAR=value …]
  _gg="$1"; _gp="$2"; shift 2
  _go="$(printf '%s' "$_gp" | env "$@" sh "$_gg" 2>/dev/null)"; _gr=$?
  t_fold "$_gr" "$_go"
}

t_reason() { # <guard> <payload> [VAR=value …] — the text the operator reads
  _gg="$1"; _gp="$2"; shift 2
  printf '%s' "$_gp" | env "$@" sh "$_gg" 2>/dev/null \
    | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null
}

t_guard() { # <want> <label> <guard> <payload> [VAR=value …]
  _gw="$1"; _gl="$2"; shift 2
  t_eq "$_gl" "$_gw" "$(t_decide "$@")"
}

t_pad() { # <n> — n bytes of 'x', for over-cap payloads; doubled, not sprintf: mawk caps sprintf at 8192 bytes (harbor#1149)
  awk -v n="$1" 'BEGIN { s = "x"; while (length(s) < n) s = s s; printf "%s", substr(s, 1, n) }'
}
