# tests/checks/reference-check-fixture.sh — what the reference-check suites share (M8, harbor#44).
# Source after t_init. mkfixture builds a config dir that is clean by construction; each red case
# adds exactly one defect, so a finding can only come from the thing the case is named after.
SRC="$T_ROOT/bin"; RC="$SRC/reference-check.sh"; TMP="$T_TMP/rc"; mkdir -p "$TMP"
# A mutant needs the extractor, log-lib.sh and fs-lib.sh beside it: the checker resolves both from its OWN dir,
# and without the extractor REF-5 fires and every mutant assertion tests the copy (#462, #809).
mkmut() { # <name> → the path the mutant script goes to, extractor and log-lib in place
  _m="$TMP/$1"; mkdir -p "$_m"; cp "$SRC/cited-paths.awk" "$SRC/log-lib.sh" "$SRC/fs-lib.sh" "$_m/"
  printf '%s' "$_m/reference-check.sh"
}
mkfixture() { # <name> → the dir: one wired hook, a statusline, a pin, and citations that resolve
  _d="$TMP/$1"; mkdir -p "$_d/bin" "$_d/.helm-pins"
  printf '#!/usr/bin/env sh\nexit 0\n' > "$_d/bin/hook-a.sh"
  printf '#!/usr/bin/env sh\nexit 0\n' > "$_d/bin/hook-b.sh"
  printf '#!/usr/bin/env sh\nexit 0\n' > "$_d/bin/line.sh"
  printf 'abc  bin/hook-a.sh\n' > "$_d/.helm-pins/hook-a.sh.sha256"
  printf 'REAL\n' > "$_d/REAL.md"
  # One citation of every shape: a resolving link, a URL, an anchor. Broken skip logic makes it red.
  printf '# c\n[a](./REAL.md) [b](https://example.com/x) [c](#anchor)\n' > "$_d/CLAUDE.md"
  jq -n --arg a "/bin/sh $_d/bin/hook-a.sh" --arg l "/bin/sh $_d/bin/line.sh" '
    {hooks: {SessionStart: [{matcher: "", hooks: [{type: "command", command: $a}]}]},
     statusLine: {type: "command", command: $l}}' > "$_d/settings.json"
  printf '%s' "$_d"
}
resettings() { _f="$1"; shift; jq "$@" "$_f/settings.json" > "$_f/s.tmp" && mv "$_f/s.tmp" "$_f/settings.json"; }  # <dir> <jq args…>
rules_by() { sh "$1" "$2" --json 2>/dev/null | jq -r '[.findings[].rule] | unique | join(" ")'; }  # <script> <dir> → sorted rules
rules_of() { rules_by "$RC" "$1"; }  # <dir>
fired() { case " $1 " in *" $2 "*) echo yes ;; *) echo no ;; esac; }  # <rules> <rule>, space-anchored: REF-1 is not REF-10
differs() { cmp -s "$1" "$2" && echo no || echo yes; }  # <source> <mutant> — a no-op mutant proves nothing
mkskill() { # <fixture-dir> <skill> <body> → an installed-shaped skill
  _sd="$1/skills/$2"; mkdir -p "$_sd"
  printf -- '---\nname: %s\n---\n\n%s\n' "$2" "$3" > "$_sd/SKILL.md"
}
