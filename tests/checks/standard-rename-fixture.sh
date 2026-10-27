#!/usr/bin/env sh
# Shared fixture for the standard-rename suites (harbor#996): an empty fixture repo per scenario, and the codemod run on it.
# Sourced after t_init and after TOOL is set; mkfix sets CR, the repo the other two act on.
mkfix() { # <dir> — an empty fixture repo: the registries, no rows, no exemptions, build/ ignored
  CR="$1"; mkdir -p "$CR/standards/naming" "$CR/docs" "$CR/bin"
  for f in terms aliases controls surfaces kinds registers repo-kinds dialects frozen label-axes; do cp "$T_ROOT/standards/naming/$f.tsv" "$CR/standards/naming/"; done
  sed -n '1,/^id	old	new/p' "$T_ROOT/standards/naming/renames.tsv" > "$CR/standards/naming/renames.tsv"
  sed -n '1,/^id	rule	subject/p' "$T_ROOT/standards/naming/exemptions.tsv" > "$CR/standards/naming/exemptions.tsv"
  printf 'build/\n' > "$CR/.gitignore"
}
cc() { git -C "$CR" add -A; git -C "$CR" -c user.email=t@t -c user.name=t commit -qm "$1"; }
crun() { sh "$TOOL" --root "$CR" "$@"; }
