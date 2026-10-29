#!/usr/bin/env sh
# memory-log-token-save.sh (harbor#431, #1205): the token goes into the store as worklog-token, the legacy
# plaintext file is removed, nothing is printed, and the clipboard is cleared. pbpaste/pbcopy and the
# store are stubs, so no real clipboard or keychain is touched. The fixtures are assembled at runtime:
# guard-egress refuses a token-shaped literal on disk.
. "$(dirname "$0")/../../lib/core.sh"; t_init
SUBJ="$T_ROOT/bin/memory-log-token-save.sh"; T="$T_TMP/slt"; mkdir -p "$T/cfg"
cat > "$T_BIN/pbpaste" <<'STUB'
#!/bin/sh
cat "$FAKE_CLIP" 2>/dev/null || true
STUB
cat > "$T_BIN/pbcopy" <<'STUB'
#!/bin/sh
cat > /dev/null
: > "$FAKE_CLIP"
STUB
chmod +x "$T_BIN/pbpaste" "$T_BIN/pbcopy"
# The store stub: `put worklog-token` keeps stdin, a .refuse marker makes it refuse, `run` serves it.
cat > "$T/secret" <<'STUB'
#!/bin/sh
case "$1" in
  put) if [ ! -e "$FAKE_STORE.refuse" ] && [ "$2" = worklog-token ]; then cat > "$FAKE_STORE"
       else cat > /dev/null; echo "secret: STUBERR-no-register-entry names 'worklog-token' in its secret: field" >&2; exit 1; fi ;;
  run) [ -f "$FAKE_STORE" ] || { echo "no secret named '$2'" >&2; exit 1; }; v="$(cat "$FAKE_STORE")"; export "$3=$v"; shift 4; exec "$@" ;;
  *) exit 2 ;;
esac
STUB
export HARBOR_SECRET_BIN="$T/secret" FAKE_STORE="$T/store"
_gh='git''hub'
GOOD="${_gh}_pat_11ABCDEFG0$(printf 'x%.0s' 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0)NOTAREAL"
NEARMISS="${_gh}_patx_11ABCDEFG"
CANARY="${_gh}_LEAKCANARY_shouldnotbeprinted"
export FAKE_CLIP="$T/clip"
TOK="$T/cfg/.helm-log-token"
# The default destination when CLAUDE_CONFIG_DIR is unset, seeded so a write there shows.
DEFAULT="$HOME/.claude/.helm-log-token"; mkdir -p "$HOME/.claude"; printf 'sentinel\n' > "$DEFAULT"
runit() { # <clipboard> → OUT, RC
  printf '%s' "$1" > "$FAKE_CLIP"
  OUT="$(CLAUDE_CONFIG_DIR="$T/cfg" sh "$SUBJ" 2>&1)"; RC=$?
}

t_section "SLT-1 a token-shaped clipboard is stored as worklog-token"
printf '%s' "$GOOD" > "$FAKE_CLIP"
t_has "the clipboard stub serves the token the subject reads" "$(pbpaste)" "$GOOD"
printf 'old\n' > "$TOK"
runit "$GOOD"
t_eq "exit" 0 "$RC"
t_eq "the bytes stored are the bytes pasted" "$GOOD" "$(cat "$FAKE_STORE" 2>/dev/null)"

t_section "SLT-2 no plaintext copy is left"
t_eq "the legacy token file is removed" no "$([ -f "$TOK" ] && echo yes || echo no)"
t_has "...and it says so" "$OUT" "plaintext file removed"

t_section "SLT-3 the token never appears in the output"
t_hasnt "the token is absent from the output" "$OUT" "$GOOD"
t_has "the length is reported instead" "$OUT" "${#GOOD} chars"

t_section "SLT-4 the clipboard is cleared"
t_eq "bytes left on the clipboard" 0 "$(wc -c < "$FAKE_CLIP" | tr -d ' ')"

t_section "SLT-5 a non-token clipboard is refused"
rm -f "$TOK" "$FAKE_STORE"
runit 'hello world, not a credential'
t_eq "exit" 1 "$RC"
t_eq "nothing was stored" no "$([ -f "$FAKE_STORE" ] && echo yes || echo no)"
t_eq "nothing was written" no "$([ -f "$TOK" ] && echo yes || echo no)"
t_has "it says NOT SAVED" "$OUT" "NOT SAVED"

t_section "SLT-6 a near miss is still a miss (SLT-1's control)"
runit "$NEARMISS"; t_eq "a lookalike prefix exits" 1 "$RC"
runit 'ghp'; t_eq "a bare prefix with no body exits" 1 "$RC"

t_section "SLT-7 the refusal does not leak the clipboard it refused"
runit "$CANARY"
t_has "the refusal quotes the clipboard's first 4 characters" "$OUT" "starts: gith..."
t_hasnt "and never the value" "$OUT" "LEAKCANARY"

t_section "SLT-8 --help and argument handling"
t_exit "--help" 0 sh "$SUBJ" --help
t_has "--help names the tool" "$(sh "$SUBJ" --help 2>&1)" "memory-log-token-save"
t_exit "an unknown argument" 2 sh "$SUBJ" --nonsense

t_section "SLT-9 Linux: wl-clipboard, xclip or xsel stand in for pbpaste/pbcopy (harbor#618)"
. "$T_ROOT/tests/lib/linux-sim.sh"
LX="$T/lx"; linux_path "$LX" pbpaste pbcopy wl-paste wl-copy xclip xsel powershell.exe clip.exe
lxrun() { printf '%s' "$1" > "$FAKE_CLIP"; OUT="$(PATH="$LX" CLAUDE_CONFIG_DIR="$T/cfg" sh "$SUBJ" 2>&1)"; RC=$?; }
t_eq "control: the Linux PATH has no pbpaste" "" "$(PATH="$LX" command -v pbpaste)"
lxrun "$GOOD"; t_eq "with no clipboard tool at all it exits 2" 2 "$RC"
t_has "...naming the tools it looked for" "$OUT" "wl-paste"
printf '#!/bin/sh\ncase " $* " in *" -o "*) cat "$FAKE_CLIP" ;; *) cat > /dev/null; : > "$FAKE_CLIP" ;; esac\n' > "$LX/xclip"
chmod +x "$LX/xclip"; rm -f "$FAKE_STORE"; lxrun "$GOOD"
t_eq "xclip: exit" 0 "$RC"
t_eq "xclip: the bytes stored are the bytes pasted" "$GOOD" "$(cat "$FAKE_STORE" 2>/dev/null)"
t_eq "xclip: the clipboard is cleared" 0 "$(wc -c < "$FAKE_CLIP" | tr -d ' ')"
printf '#!/bin/sh\ncat "$FAKE_CLIP"\n' > "$LX/wl-paste"; printf '#!/bin/sh\n[ "$1" = --clear ] && : > "$FAKE_CLIP"\n' > "$LX/wl-copy"
chmod +x "$LX/wl-paste" "$LX/wl-copy"; rm -f "$FAKE_STORE" "$LX/xclip"; lxrun "$GOOD"
t_eq "wl-clipboard: the token is stored" "$GOOD" "$(cat "$FAKE_STORE" 2>/dev/null)"
t_eq "wl-clipboard: the clipboard is cleared" 0 "$(wc -c < "$FAKE_CLIP" | tr -d ' ')"

t_section "SLT-10 a refused store is a FAIL, never a fall back to the plaintext file"
rm -f "$TOK" "$FAKE_STORE"; : > "$FAKE_STORE.refuse"
runit "$GOOD"
t_eq "exit" 1 "$RC"
t_has "it says NOT SAVED" "$OUT" "NOT SAVED"
t_eq "no plaintext file was written instead" no "$([ -f "$TOK" ] && echo yes || echo no)"
t_eq "the clipboard is still cleared" 0 "$(wc -c < "$FAKE_CLIP" | tr -d ' ')"
t_hasnt "the token is absent from the output" "$OUT" "$GOOD"
t_has "the store's own error text reaches the operator (harbor#431)" "$OUT" "STUBERR-no-register-entry"
t_hasnt "...and the token is still not in what is printed" "$OUT" "$GOOD"
rm -f "$FAKE_STORE.refuse"

t_section "SLT-0 the default destination is untouched"
t_eq "\$HOME/.claude/.helm-log-token" sentinel "$(cat "$DEFAULT")"
t_done
