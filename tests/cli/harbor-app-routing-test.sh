#!/usr/bin/env sh
# harbor-app: the in-session gh shim and git helper route each repo owner to its App installation, and
# harbor-app-install.sh copies them (never links) and refuses --apply inside a Claude session. harbor#1225.
# Against stubs only: a minter that echoes the account it was asked for, a gh that echoes GH_TOKEN.
# A mutant that never routes must fail exactly the org cases, or this suite tests nothing.
. "$(dirname "$0")/../lib/core.sh"; t_init
export HARBOR_SCOPE_PRIVATE="$T_TMP/no-layer"
APP="$T_ROOT/bin/harbor-app"; INST="$T_ROOT/bin/harbor-app-install.sh"
mkdir -p "$HOME/.config/harbor-app" "$T_TMP/org" "$T_TMP/me" "$T_TMP/none"
printf '#!/bin/sh\necho "tok:${1:-DEFAULT}"\n' > "$HOME/.config/harbor-app/mint-token.sh"
printf '#!/bin/sh\necho "$GH_TOKEN"\n' > "$T_BIN/realgh"; chmod +x "$T_BIN/realgh"
git -C "$T_TMP/org" init -q && git -C "$T_TMP/org" remote add origin https://github.com/Acme-Org/widgets.git
git -C "$T_TMP/me" init -q && git -C "$T_TMP/me" remote add origin git@github.com:VytCepas/harbor.git
git -C "$T_TMP/none" init -q
printf 'acme-org\tAcme-Org\n' > "$HOME/.config/harbor-app/orgs.tsv"   # the table core ships none of
O=tok:Acme-Org; V=tok:DEFAULT

# One routing case: <want> <cwd> <gh args…> through $GH, or a helper request through $HELPER.
g() { _w="$1"; _c="$2"; shift 2; ( cd "$T_TMP/$_c" && CLAUDECODE=1 sh "$GH" "$@" 2>/dev/null ); }
h() { ( cd "$T_TMP/$1" && printf "$2" | CLAUDECODE=1 sh "$HELPER" get 2>/dev/null | sed -n 's/^password=//p' ); }
routes() { # prints one "<want> <got> <label>" line per case
  for _row in \
    "$O|none|issue view 164 -R Acme-Org/widgets" \
    "$O|none|issue view 164 --repo acme-org/widgets" \
    "$O|none|pr view --repo=Acme-Org/x 1" \
    "$O|none|api repos/Acme-Org/widgets" \
    "$O|none|api /orgs/Acme-Org/repos" \
    "$O|none|pr view https://github.com/Acme-Org/widgets/pull/218" \
    "$O|org|issue list" \
    "$O|me|repo view Acme-Org/widgets" \
    "$O|me|repo clone https://github.com/Acme-Org/widgets" \
    "$O|org|pr view feature/x" \
    "$V|me|issue list" \
    "$V|none|issue view 1 -R VytCepas/harbor" \
    "$V|none|api repos/cli/cli" \
    "$V|none|api user" \
    "$V|org|issue view 1 -R VytCepas/harbor" \
    "$V|org|repo view VytCepas/harbor" ; do
    _w="${_row%%|*}"; _r="${_row#*|}"; _c="${_r%%|*}"; _a="${_r#*|}"
    # shellcheck disable=SC2086 # the args are words on purpose
    printf '%s %s gh[%s] %s\n' "$_w" "$(g "$_w" "$_c" $_a)" "$_c" "$_a"
  done
  # A URL in a comment body never outranks the target, whichever side of -R it sits.
  printf '%s %s gh[none] body URL before -R\n' "$V" "$(g "$V" none issue comment 5 -b 'see https://github.com/Acme-Org/x/issues/1' -R VytCepas/harbor)"
  printf '%s %s gh[me] body URL, no -R\n' "$V" "$(g "$V" me issue comment 5 -b 'see https://github.com/Acme-Org/x/issues/1')"
  printf '%s %s helper[org] cwd origin\n' "$O" "$(h org 'protocol=https\nhost=github.com\n\n')"
  printf '%s %s helper[me] cwd origin\n' "$V" "$(h me 'protocol=https\nhost=github.com\n\n')"
  printf '%s %s helper[none] path=\n' "$O" "$(h none 'protocol=https\nhost=github.com\npath=Acme-Org/widgets.git\n\n')"
  printf '%s %s helper[none] no path\n' "$V" "$(h none 'protocol=https\nhost=github.com\n\n')"
}

t_section "each owner reaches its own installation"
sed "s#^REAL=.*#REAL=$T_BIN/realgh#" "$APP/gh" > "$T_TMP/gh"; GH="$T_TMP/gh"; HELPER="$APP/git-credential.sh"
routes > "$T_TMP/real"
while read -r _w _g _l; do t_eq "$_l" "$_w" "$_g"; done < "$T_TMP/real"

t_section "control: a shim that never routes fails exactly the org cases"
sed "s#^REAL=.*#REAL=$T_BIN/realgh#; s#orgs.tsv#never.tsv#g" "$APP/gh" > "$T_TMP/gh-mut"
sed "s#orgs.tsv#never.tsv#g" "$APP/git-credential.sh" > "$T_TMP/helper-mut"
GH="$T_TMP/gh-mut"; HELPER="$T_TMP/helper-mut"
routes > "$T_TMP/mut"
t_eq "the mutant's wrong answers are the org cases" "$(grep -c "^$O " "$T_TMP/real")" "$(awk '$1 != $2' "$T_TMP/mut" | grep -c "^$O ")"
t_eq "the mutant gets every default case right" "0" "$(awk '$1 != $2' "$T_TMP/mut" | grep -vc "^$O ")"

t_section "no table, no routing"
mv "$HOME/.config/harbor-app/orgs.tsv" "$T_TMP/orgs.keep"
GH="$T_TMP/gh"; HELPER="$APP/git-credential.sh"; routes > "$T_TMP/notable"
t_eq "without orgs.tsv every owner gets the default" "0" "$(awk '{print $2}' "$T_TMP/notable" | grep -vc "^$V\$")"
mv "$T_TMP/orgs.keep" "$HOME/.config/harbor-app/orgs.tsv"

t_section "the installer"
R="$T_TMP/root"; mkdir -p "$R/.config/harbor-app" "$R/.local/bin"
printf 'KEY\n' > "$R/.config/harbor-app/app.pem"; printf '123\n' > "$R/.config/harbor-app/app-id"
t_exit "a dry run on an empty root exits 0" 0 env -u CLAUDECODE sh "$INST" --dir "$R"
t_eq "the dry run wrote nothing" "" "$(find "$R/.local/bin" -type f)"
t_exit "--apply inside a Claude session is refused (1)" 1 env CLAUDECODE=1 sh "$INST" --apply --dir "$R"
t_eq "the refused apply wrote nothing" "" "$(find "$R/.local/bin" -type f)"
# A symlink into a checkout at the gh destination: replaced by a copy, its target left alone.
printf 'checkout copy\n' > "$T_TMP/checkout-gh"; ln -s "$T_TMP/checkout-gh" "$R/.local/bin/gh"
t_exit "--apply from a terminal installs" 0 env -u CLAUDECODE sh "$INST" --apply --dir "$R"
t_eq "gh is a regular file, not a link" "file" "$(if [ -L "$R/.local/bin/gh" ]; then echo link; elif [ -f "$R/.local/bin/gh" ]; then echo file; fi)"
t_eq "the link's target was not written through" "checkout copy" "$(cat "$T_TMP/checkout-gh")"
for _f in gh:.local/bin/gh git-credential.sh:.config/harbor-app/git-credential.sh mint-token.sh:.config/harbor-app/mint-token.sh git-credential.sh:.local/bin/git-credential-harbor; do
  t_exit "${_f%%:*} is byte-identical to the repo" 0 cmp "$APP/${_f%%:*}" "$R/${_f#*:}"
done
t_eq "app.pem untouched" "KEY" "$(cat "$R/.config/harbor-app/app.pem")"
t_eq "app-id untouched" "123" "$(cat "$R/.config/harbor-app/app-id")"
_out="$(env -u CLAUDECODE sh "$INST" --dir "$R" 2>&1)"
t_eq "after the apply, a dry run reports all four same" "4" "$(printf '%s\n' "$_out" | grep -c ': same (')"
printf '# drifted\n' >> "$R/.config/harbor-app/git-credential.sh"
_out="$(env -u CLAUDECODE sh "$INST" --dir "$R" 2>&1)"
t_has "a drifted copy is reported" "$_out" "git-credential.sh: differs"
# The table comes from the private layer, never from core.
P="$T_TMP/priv"; mkdir -p "$P/harbor-app"; printf 'acme-org\tAcme-Org\n' > "$P/harbor-app/orgs.tsv"
t_exit "--apply installs the private layer's orgs.tsv" 0 env -u CLAUDECODE HARBOR_SCOPE_PRIVATE="$P" sh "$INST" --apply --dir "$R"
t_exit "orgs.tsv is byte-identical to the layer's" 0 cmp "$P/harbor-app/orgs.tsv" "$R/.config/harbor-app/orgs.tsv"
rm -f "$R/.config/harbor-app/orgs.tsv"
t_exit "with no layer table, --apply writes no orgs.tsv" 0 env -u CLAUDECODE HARBOR_SCOPE_PRIVATE="$T_TMP/nolayer" sh "$INST" --apply --dir "$R"
t_eq "and none exists" "" "$(find "$R/.config/harbor-app" -name orgs.tsv)"

t_section "the gitconfig helper entry is repointed out of the denied dir (harbor#1298)"
G="$R/.gitconfig"; rm -f "$G"
git config --file "$G" --add credential.https://github.com.helper ''
git config --file "$G" --add credential.https://github.com.helper "!$R/.config/harbor-app/git-credential.sh"
git config --file "$G" --add credential.https://github.com.helper osxkeychain
t_has "a dry run says it would repoint" "$(env -u CLAUDECODE sh "$INST" --dir "$R" 2>&1)" "would repoint it to harbor"
t_eq "...and leaves the entry as it was" "!$R/.config/harbor-app/git-credential.sh" "$(git config --file "$G" --get-all credential.https://github.com.helper | sed -n 2p)"
env -u CLAUDECODE sh "$INST" --apply --dir "$R" >/dev/null 2>&1
t_eq "--apply repoints it in place: reset, harbor, osxkeychain" "|harbor|osxkeychain" "$(git config --file "$G" --get-all credential.https://github.com.helper | paste -sd'|' -)"
t_hasnt "a second dry run has nothing to repoint" "$(env -u CLAUDECODE sh "$INST" --dir "$R" 2>&1)" "would repoint"

t_section "confined: the hook's cache answers when ~/.config/harbor-app cannot be opened (harbor#1298)"
C="$T_TMP/cache"; mkdir -p "$C"; export HARBOR_CONFINEMENT_CACHE="$C"
_later=$(($(date +%s) + 3000)); _past=$(($(date +%s) - 10))
printf '%s\ncache:Acme-Org\n' "$_later" > "$C/gh-Acme-Org"; printf '%s\ncache:DEFAULT\n' "$_later" > "$C/gh-VytCepas"
cp "$HOME/.config/harbor-app/orgs.tsv" "$C/orgs.tsv"
printf '#!/bin/sh\necho "$GH_TOKEN|${GH_CONFIG_DIR:-unset}"\n' > "$T_BIN/realgh2"; chmod +x "$T_BIN/realgh2"
sed "s#^REAL=.*#REAL=$T_BIN/realgh2#" "$APP/gh" > "$T_TMP/gh2"
gh2() { _d="$1"; shift; ( cd "$T_TMP/$_d" && CLAUDECODE=1 sh "$T_TMP/gh2" "$@" 2>/dev/null ); }
helper() { ( cd "$T_TMP/$1" && printf "$2" | CLAUDECODE=1 sh "$APP/git-credential.sh" get 2>/dev/null ); }
t_eq "a fresh cached token wins over a mint" "cache:DEFAULT" "$(gh2 none issue list -R VytCepas/harbor | cut -d'|' -f1)"
chmod 000 "$HOME/.config/harbor-app/orgs.tsv"
t_eq "the operator's table unopenable: the cache's copy routes the org" "cache:Acme-Org" "$(gh2 none issue view 1 -R Acme-Org/widgets | cut -d'|' -f1)"
t_eq "the helper routes through the cache too" "password=cache:Acme-Org" "$(helper none 'protocol=https\nhost=github.com\npath=Acme-Org/widgets.git\n\n' | grep '^password=')"
chmod 600 "$HOME/.config/harbor-app/orgs.tsv"
printf '%s\ncache:STALE\n' "$_past" > "$C/gh-VytCepas"
t_eq "a stale cached token is never used: the mint answers" "tok:DEFAULT" "$(gh2 none issue list -R VytCepas/harbor | cut -d'|' -f1)"
t_has "no operator gh config to open: gh gets its own writable dir" "$(gh2 none issue list -R VytCepas/harbor | cut -d'|' -f2)" "harbor-gh-config"
mkdir -p "$HOME/.config/gh"; printf 'git_protocol: https\n' > "$HOME/.config/gh/config.yml"
t_eq "CONTROL: an openable operator config keeps gh on it" "unset" "$(gh2 none issue list -R VytCepas/harbor | cut -d'|' -f2)"
printf '#!/bin/sh\nexit 1\n' > "$HOME/.config/harbor-app/mint-token.sh"
t_eq "stale cache and a failed mint: the helper answers quit=1, never a fall-through" "quit=1" "$(helper me 'protocol=https\nhost=github.com\n\n')"
t_done
