#!/usr/bin/env sh
# `harbor pack` (bin/pack.sh, harbor#1149): the five refusals, the client-free gate, an exact remove, an idempotent install.
# Every case runs on a throwaway PORT_ROOT and a throwaway target dir (--dir); the real ~/.claude is never named.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/fixture.sh"
# refused <label> <id> <reason fragment>: install is skipped by name, exits 1 and leaves the target untouched.
refused() {
  TG="$T_TMP/tg-$1"; rm -rf "$TG"; mkdir -p "$TG/bin" "$TG/skills"; printf 'core\n' > "$TG/bin/core-file"
  _b="$(snap "$TG")"; listed "\"$2\""
  _o="$(pk install "$2" --apply --dir "$TG" 2>&1)"; _rc=$?
  t_eq "$1: exits 1" 1 "$_rc"
  t_has "$1: skipped by name" "$_o" "skipped $2:"
  t_has "$1: says why" "$_o" "$3"
  t_eq "$1: the target is byte-identical" "$_b" "$(snap "$TG")"
}

t_section "a clean pack installs, idempotently, and remove undoes it exactly"
mkpack ok; listed '"ok"'
TG="$T_TMP/tg-ok"; mkdir -p "$TG/bin" "$TG/skills"; printf 'core\n' > "$TG/bin/core-file"
B0="$(snap "$TG")"
pk install ok --dir "$TG" >/dev/null 2>&1
t_eq "a dry run writes nothing" "$B0" "$(snap "$TG")"
t_exit "install --apply exits 0" 0 pk install ok --apply --dir "$TG"
t_eq "skill lands" "A demo skill." "$(tail -n 1 "$TG/skills/demo/SKILL.md")"
t_eq "bin lands, executable" "yes" "$([ -x "$TG/bin/demo-tool" ] && echo yes || echo no)"
t_eq "inject pack lands under a pack-owned name" "yes" "$([ -f "$TG/context-rules/user/pack-demo-ok--demo.md" ] && echo yes || echo no)"
t_has "check rows land in a per-pack fragment" "$(cat "$TG/checks.d/ok.md")" '| `demo-ok` |'
t_has "the pack's shims land in a per-pack fragment, which shim-install reads" "$(cat "$TG/shims.d/ok.tsv")" "demo-tool	bin/demo-tool"
t_has "...and its control rows beside it" "$(cat "$TG/checks.d/ok.controls.tsv")" 'check.demo-ok	warn'
t_eq "tests/ and pack.toml are not installed" "0" "$(find "$TG" -name pack.toml | wc -l | tr -d ' ')"
B1="$(snap "$TG")"
pk install ok --apply --dir "$TG" >/dev/null 2>&1
t_eq "a second install changes nothing" "$B1" "$(snap "$TG")"
t_has "list names the installed pack" "$(pk list --dir "$TG" 2>/dev/null)" "demo-ok"
t_exit "remove exits 0" 0 pk remove ok --apply --dir "$TG"
t_eq "install then remove leaves the target byte-identical" "$B0" "$(snap "$TG")"
t_eq "...the core file included" "core" "$(cat "$TG/bin/core-file")"

t_section "remove takes back only what install wrote"
pk install ok --apply --dir "$TG" >/dev/null 2>&1
printf 'mine\n' > "$TG/skills/demo/extra.md"; printf 'mine\n' > "$TG/bin/mine"
pk remove ok --apply --dir "$TG" >/dev/null 2>&1
t_eq "a file the operator added in the pack's dir survives" "mine" "$(cat "$TG/skills/demo/extra.md")"
t_eq "a sibling file survives" "mine" "$(cat "$TG/bin/mine")"
t_exit "removing what is not installed exits 1" 1 pk remove ok --apply --dir "$TG"

t_section "refusal 1: hooks/ and guard-* files"
mkpack hk; mkdir -p "$PW/hk/harbor-pack/hooks"; printf 'x\n' > "$PW/hk/harbor-pack/hooks/h.sh"; G "$PW/hk" add -A; G "$PW/hk" commit -q -m h
refused hooks hk "hooks/"
mkpack gd; printf 'x\n' > "$PW/gd/harbor-pack/bin/guard-thing.sh"; G "$PW/gd" add -A; G "$PW/gd" commit -q -m g
refused guard gd "guard-*"

t_section "harbor#1010: a pack's rules in the new layout, context-rules/user/, land in the same installed tier"
mkpack nl; mkdir -p "$PW/nl/harbor-pack/context-rules/user"; G "$PW/nl" mv harbor-pack/inject.d/demo.md harbor-pack/context-rules/user/demo.md
G "$PW/nl" commit -q -m layout; listed '"nl"'
t_eq "the fixture pack carries no inject.d/" "harbor-pack/context-rules/user/demo.md" "$(G "$PW/nl" ls-files | grep 'demo\.md$')"
TGN="$T_TMP/tg-nl"; mkdir -p "$TGN/bin" "$TGN/skills"
t_exit "install --apply exits 0" 0 pk install nl --apply --dir "$TGN"
t_eq "the new-layout rule lands under a pack-owned name" "yes" "$([ -f "$TGN/context-rules/user/pack-demo-nl--demo.md" ] && echo yes || echo no)"
mkpack ns; mkdir -p "$PW/ns/harbor-pack/context-rules/demo"; G "$PW/ns" mv harbor-pack/inject.d/demo.md harbor-pack/context-rules/demo/demo.md
G "$PW/ns" commit -q -m scope
refused scope ns "a repo scope is that repo's own"

t_section "refusal 2: an inject pack with run:"
mkpack rn; printf -- '---\nid: r\nevent: PreToolUse\nwhen: always\nrun: check.sh\n---\nn\n' > "$PW/rn/harbor-pack/inject.d/r.md"; G "$PW/rn" add -A; G "$PW/rn" commit -q -m r
refused run rn "run:"

t_section "refusal 3: a bin/ name that shadows a core command"
mkpack sh1; printf '#!/bin/sh\n' > "$PW/sh1/harbor-pack/bin/idea"; G "$PW/sh1" add -A; G "$PW/sh1" commit -q -m s
refused shadow-script sh1 "shadows the core command"
mkpack sh2; printf '#!/bin/sh\n' > "$PW/sh2/harbor-pack/bin/uninstall"; G "$PW/sh2" add -A; G "$PW/sh2" commit -q -m s
refused shadow-verb sh2 "shadows"
mkpack sh3; mkdir -p "$PW/sh3/harbor-pack/skills/access-ledger"; printf 'x\n' > "$PW/sh3/harbor-pack/skills/access-ledger/SKILL.md"; G "$PW/sh3" add -A; G "$PW/sh3" commit -q -m s
refused shadow-skill sh3 "shadows a core skill"

t_section "refusal 3b: a shims.tsv that links nothing the pack installs, or a name core owns (harbor#1149)"
mkpack sm1; printf 'name\trel\nno-such\tbin/no-such\n' > "$PW/sm1/harbor-pack/shims.tsv"; G "$PW/sm1" add -A; G "$PW/sm1" commit -q -m s
refused shim-no-file sm1 "bin/no-such is not a bin/ file this pack installs"
mkpack sm2; printf 'name\trel\nsecret\tbin/demo-tool\n' > "$PW/sm2/harbor-pack/shims.tsv"; G "$PW/sm2" add -A; G "$PW/sm2" commit -q -m s
refused shim-core-name sm2 "secret is a command core's contracts/shims.tsv owns"
mkpack sm3; printf 'demo-tool\tbin/demo-tool\n' > "$PW/sm3/harbor-pack/shims.tsv"; G "$PW/sm3" add -A; G "$PW/sm3" commit -q -m s
refused shim-no-header sm3 "its header is not name, rel"
mkpack sm4; printf 'name\trel\ndemo-tool\tbin/demo-tool\ndemo-tool\tbin/demo-tool\n' > "$PW/sm4/harbor-pack/shims.tsv"; G "$PW/sm4" add -A; G "$PW/sm4" commit -q -m s
refused shim-twice sm4 "demo-tool is listed twice"
mkpack sm5; printf 'name\trel\nhello\tskills/demo/SKILL.md\n' > "$PW/sm5/harbor-pack/shims.tsv"; G "$PW/sm5" add -A; G "$PW/sm5" commit -q -m s
refused shim-not-bin sm5 "is not a bin/ file this pack installs"
mkpack sm6; printf 'name\trel\nbad name\tbin/demo-tool\n' > "$PW/sm6/harbor-pack/shims.tsv"; G "$PW/sm6" add -A; G "$PW/sm6" commit -q -m s
refused shim-bad-name sm6 "is not a command name"
mkpack sm7; printf 'name\trel\ndemo-tool\tbin/demo-tool\textra\n' > "$PW/sm7/harbor-pack/shims.tsv"; G "$PW/sm7" add -A; G "$PW/sm7" commit -q -m s
refused shim-columns sm7 "has 3 columns, not 2"
# RED-PROOF: the same pack with a valid row installs, so the refusals above are the shims.tsv check and nothing else.
mkpack sm8; listed '"sm8"'; mkdir -p "$T_TMP/tg-sm8"
t_exit "control: a pack with a valid shims.tsv installs" 0 pk install sm8 --apply --dir "$T_TMP/tg-sm8"

t_section "refusal 4: a dirty or unpinned checkout"
mkpack dt; printf 'changed\n' >> "$PW/dt/harbor-pack/skills/demo/SKILL.md"
refused dirty-edit dt "dirty"
mkpack du; printf 'new\n' > "$PW/du/harbor-pack/skills/demo/new.md"
refused dirty-untracked du "dirty"
mkpack up; rm -rf "$PW/up/.git"
refused unpinned-nogit up "unpinned"
mkpack uc; rm -rf "$PW/uc/.git"; G "$PW/uc" init -q
refused unpinned-nocommit uc "unpinned"

t_section "refusal 5: a harbor_version core does not satisfy"
mkpack vm '>=99.0'
refused version vm "needs harbor >=99.0"
mkpack vb 'soon'
refused version-malformed vb "is not a constraint"
mkpack vo '>=1.0,<2'; listed '"vo"'
mkdir -p "$T_TMP/tg-vo"
t_exit "a satisfied range installs" 0 pk install vo --apply --dir "$T_TMP/tg-vo"

t_section "client-free: the leak gate runs over the pack"
mkpack lk; printf 'see %s/jdoe/work\n' /Users > "$PW/lk/harbor-pack/skills/demo/SKILL.md"; G "$PW/lk" add -A; G "$PW/lk" commit -q -m l
refused leak lk "client-free"

t_section "the gate scans exactly what installs (harbor#1149)"
LEAK='see /Users'"/jdoe/work"
mkpack gt; mkdir -p "$PW/gt/harbor-pack/skills/demo/tests" "$PW/gt/harbor-pack/skills/demo/fixtures"
printf '%s\n' "$LEAK" > "$PW/gt/harbor-pack/skills/demo/tests/t.md"; G "$PW/gt" add -A; G "$PW/gt" commit -q -m t
refused leak-in-skill-tests gt "client-free"
mkpack gf; mkdir -p "$PW/gf/harbor-pack/skills/demo/fixtures"
printf '%s\n' "$LEAK" > "$PW/gf/harbor-pack/skills/demo/fixtures/f.md"; G "$PW/gf" add -A; G "$PW/gf" commit -q -m f
refused leak-in-skill-fixtures gf "client-free"
mkpack gl; mkdir -p "$PW/gl/contracts"; printf 'path\tlayer\tnote\nharbor-pack/\tdev\tn\n' > "$PW/gl/contracts/layers.tsv"
printf '%s\n' "$LEAK" > "$PW/gl/harbor-pack/skills/demo/SKILL.md"; G "$PW/gl" add -A; G "$PW/gl" commit -q -m l
refused leak-with-own-layers-tsv gl "client-free"
mkpack gn; printf '%s\n\0\n' "$LEAK" > "$PW/gn/harbor-pack/skills/demo/data.md"; G "$PW/gn" add -A; G "$PW/gn" commit -q -m n
refused leak-in-nul-file gn "client-free"
mkpack ga; printf '*.md binary\n' > "$PW/ga/.gitattributes"; printf '%s\n' "$LEAK" > "$PW/ga/harbor-pack/skills/demo/SKILL.md"; G "$PW/ga" add -A; G "$PW/ga" commit -q -m a
refused leak-in-binary-attribute ga "client-free"

mkpack gi; printf '*\n' > "$PW/gi/harbor-pack/skills/demo/.gitignore"; printf '%s\n' "$LEAK" > "$PW/gi/harbor-pack/skills/demo/SKILL.md"; G "$PW/gi" add -f -A; G "$PW/gi" commit -q -m i
refused leak-under-own-gitignore gi "client-free"

t_section "secrets: gitleaks scans the same stage, by its default rules, and a missing scanner refuses (harbor#1274)"
# A GitHub-token shape, joined at run time so this file holds none: tests/ is exported and gitleaks scans it too.
SEC="$(printf '%s%s%s' ghp_ Zq8LmN2pR7tY4wXc9Vb K3jHs6DfG1aQe5UoI)"
mkpack sk; printf 'pat %s\n' "$SEC" > "$PW/sk/harbor-pack/skills/demo/tok.md"; G "$PW/sk" add -A; G "$PW/sk" commit -q -m s
refused secret sk "carries a secret"
OUT="$(pk install sk --apply --dir "$T_TMP/tg-secret" 2>&1)"
t_has "secret: named as file:rule:line" "$OUT" "tok.md:github-pat:1"
t_hasnt "secret: never by its text" "$OUT" "Zq8LmN2pR7tY4wXc9Vb"
printf '[extend]\nuseDefault = true\n[allowlist]\npaths = [%s]\n' "'''.*'''" > "$T_TMP/loose.toml"
mkdir -p "$T_TMP/tg-loose"
t_has "an inherited GITLEAKS_CONFIG does not loosen it" "$(GITLEAKS_CONFIG="$T_TMP/loose.toml" pk install sk --apply --dir "$T_TMP/tg-loose" 2>&1)" "carries a secret"
# The real PATH as one directory of links minus gitleaks, as tests/deploy/push/push.test.sh does.
FARM="$T_TMP/farm"; mkdir -p "$FARM"
for _d in $(printf '%s' "$PATH" | tr ':' ' '); do
  [ -d "$_d" ] || continue
  for _b in "$_d"/*; do
    _n="${_b##*/}"; [ "$_n" != gitleaks ] || continue
    [ -x "$_b" ] && [ ! -e "$FARM/$_n" ] && ln -s "$_b" "$FARM/$_n"
  done
done
t_eq "positive control: gitleaks is gone from the farm" no "$(env PATH="$FARM" sh -c 'command -v gitleaks' >/dev/null 2>&1 && echo yes || echo no)"
mkdir -p "$T_TMP/tg-nogl"; listed '"ok"'
OUT="$(PATH="$FARM" pk install ok --apply --dir "$T_TMP/tg-nogl" 2>&1)"; RC=$?
t_eq "no gitleaks refuses a clean pack rather than skipping the scan" 1 "$RC"
t_has "...and says so" "$OUT" "gitleaks is missing, so the pack was not scanned"
t_eq "...nothing installed" "" "$(find "$T_TMP/tg-nogl" -type f)"

t_section "refusal: a case-folded guard or core-command name, and a hooks: key"
mkpack cg; printf 'x\n' > "$PW/cg/harbor-pack/bin/Guard-bash.sh"; G "$PW/cg" add -A; G "$PW/cg" commit -q -m g
refused guard-case cg "guard-*"
mkpack cs; printf '#!/bin/sh\n' > "$PW/cs/harbor-pack/bin/IDEA"; G "$PW/cs" add -A; G "$PW/cs" commit -q -m s
refused shadow-case cs "shadows the core command"
mkpack ch; printf -- '---\nname: demo\nhooks:\n  PreToolUse: x\n---\nA demo skill.\n' > "$PW/ch/harbor-pack/skills/demo/SKILL.md"; G "$PW/ch" add -A; G "$PW/ch" commit -q -m h
refused hooks-front-matter ch "it has a hooks: key"

t_section "front matter is an allowlist with a canonical form (harbor#1149)"
# fm <label> <printf-format>: a pack whose SKILL.md is exactly that text; refused with the stated reason.
fm() { mkpack "$1"; printf -- "$2" > "$PW/$1/harbor-pack/skills/demo/SKILL.md"; G "$PW/$1" add -A; G "$PW/$1" commit -q -m f; refused "fm-$1" "$1" "$3"; }
fm bom '\357\273\277---\nname: demo\nhooks:\n  PreToolUse: x\n---\nA demo skill.\n' "UTF-8 BOM"
fm sp '--- \nname: demo\nhooks:\n  PreToolUse: x\n---\nA demo skill.\n' "not exactly ---"
fm flow '---\n{name: demo, hooks: {PreToolUse: x}}\n---\nA demo skill.\n' "not key: value"
fm esc '---\nname: demo\n"hoo\\x6bs":\n  PreToolUse: x\n---\nA demo skill.\n' "not key: value"
fm cplx '---\nname: demo\n? hooks\n: x\n---\nA demo skill.\n' "not key: value"
fm noclose '---\nname: demo\ndescription: x\n' "no closing ---"
fm unk '---\nname: demo\nsurprise: x\n---\nA demo skill.\n' "key surprise is not in"
mkpack nest; printf -- '---\nname: demo\nallowed-tools:\n  hooks: x\n---\nA demo skill.\n' > "$PW/nest/harbor-pack/skills/demo/SKILL.md"; G "$PW/nest" add -A; G "$PW/nest" commit -q -m n
listed '"nest"'; t_exit "a hooks: nested under allowed-tools: is accepted" 0 pk install nest --apply --dir "$(mkdir -p "$T_TMP/tg-nest"; echo "$T_TMP/tg-nest")"

t_section "never overwrites what the pack did not write"
mkpack ow; listed '"ow"'
TG="$T_TMP/tg-ow"; mkdir -p "$TG/bin"; printf 'core\n' > "$TG/bin/demo-tool"
B="$(snap "$TG")"
t_exit "a core-owned file in the way refuses" 1 pk install ow --apply --dir "$TG"
t_eq "...and is untouched, nothing else written" "$B" "$(snap "$TG")"
mkpack ok2; listed '"ow"'
TG="$T_TMP/tg-unl"; mkdir -p "$TG"
UO="$(pk install ok2 --apply --dir "$TG" 2>&1)"; URC=$?
t_eq "a repo not in harbor.toml packs is refused" 1 "$URC"
t_has "...and says so" "$UO" "not listed in harbor.toml packs"
t_eq "...and writes nothing" 0 "$(find "$TG" | wc -l | tr -d ' ' | awk '{ print $1 - 1 }')"

t_section "an incompatible pack is skipped by name; the others install; the run exits non-zero"
mkpack good1; mkpack bad1 '>=99.0'; listed '"bad1", "good1"'
TG="$T_TMP/tg-mix"; mkdir -p "$TG"
O="$(pk install --apply --dir "$TG" 2>&1)"; RC=$?
t_eq "exit 1" 1 "$RC"
t_has "the skip names the pack" "$O" "skipped bad1:"
t_eq "the compatible pack still installed" "yes" "$([ -f "$TG/.harbor-packs/good1.tsv" ] && echo yes || echo no)"
t_eq "the skipped one left no manifest" "no" "$([ -e "$TG/.harbor-packs/bad1.tsv" ] && echo yes || echo no)"

t_section "the pack move: a skill core installed and no longer ships is taken over, an edited one is not (harbor#1149)"
# coremf <target> <bytes>: core installed skills/demo/SKILL.md with these bytes, and a second file it still owns.
coremf() {
  rm -rf "$1"; mkdir -p "$1/skills/demo" "$1/bin"; printf '%s\n' "$2" > "$1/skills/demo/SKILL.md"; printf 'core\n' > "$1/bin/core-file"
  { printf '# .harbor-manifest\n'
    printf '%s 100644 skills/demo/SKILL.md skills-install abc\n' "$(git hash-object --no-filters "$1/skills/demo/SKILL.md")"
    printf '%s 100644 bin/core-file runtime-install abc\n' "$(git hash-object --no-filters "$1/bin/core-file")"; } > "$1/.harbor-manifest"
}
mkpack mv; listed '"mv"'
TG="$T_TMP/tg-mv"; coremf "$TG" 'core wrote this'
B="$(snap "$TG")"
t_has "a dry run names the takeover" "$(pk install mv --dir "$TG" 2>&1)" "taking over 1 file(s) core no longer ships"
t_eq "...and writes nothing" "$B" "$(snap "$TG")"
t_exit "install --apply exits 0" 0 pk install mv --apply --dir "$TG"
t_eq "the pack's copy is installed" "A demo skill." "$(tail -n 1 "$TG/skills/demo/SKILL.md")"
t_eq "core's manifest no longer names it" "0" "$(grep -c ' skills/demo/SKILL.md ' "$TG/.harbor-manifest")"
t_eq "...and keeps every other row" "1" "$(grep -c ' bin/core-file ' "$TG/.harbor-manifest")"
t_has "the pack's manifest names it" "$(cat "$TG/.harbor-packs/mv.tsv")" "F	skills/demo/SKILL.md"
TG="$T_TMP/tg-mv2"; coremf "$TG" 'core wrote this'; printf 'the operator edited it\n' >> "$TG/skills/demo/SKILL.md"
B="$(snap "$TG")"
t_exit "a core skill edited since core wrote it refuses" 1 pk install mv --apply --dir "$TG"
t_eq "...and the target is byte-identical" "$B" "$(snap "$TG")"
TG="$T_TMP/tg-mv3"; coremf "$TG" 'core wrote this'; : > "$TG/.harbor-manifest"
t_exit "a skill no manifest names is the operator's, and refuses" 1 pk install mv --apply --dir "$TG"

t_section "the private layer's own pack: id harbor-private is the layer scope-roots.sh --private resolves, not a repos.tsv row (harbor#1273)"
# A layer that is a git checkout with a harbor-pack/, a registry that does NOT name it, and a decoy checkout at PORT_ROOT/harbor-private.
PL="$T_TMP/elsewhere/layer"; mkdir -p "$T_TMP/elsewhere"; mkpack lyr; mv "$PW/lyr" "$PL"
printf 'packs = ["harbor-private"]\n' > "$PL/harbor.toml"; printf 'id\tpath\tkind\tremote\n' > "$PL/repos.tsv"
TG="$T_TMP/tg-priv"; mkdir -p "$TG/bin" "$TG/skills"
pkl() { env -u CLAUDE_CONFIG_DIR PORT_ROOT="$PW" HARBOR_SCOPE_PRIVATE="$PL" sh "$T_ROOT/bin/pack.sh" "$@"; }
t_exit "install --apply exits 0" 0 pkl install harbor-private --apply --dir "$TG"
t_eq "...from the layer HARBOR_SCOPE_PRIVATE names" "A demo skill." "$(tail -n 1 "$TG/skills/demo/SKILL.md")"
t_has "...its manifest under the reserved id" "$(pkl list --dir "$TG" 2>/dev/null)" "harbor-private	demo-lyr"
t_exit "remove exits 0" 0 pkl remove harbor-private --apply --dir "$TG"
# RED-PROOF: another id with no registry row is still refused, so the pass above is the reserved id and nothing else.
printf 'packs = ["lyr"]\n' > "$PL/harbor.toml"
t_has "an unregistered id is refused" "$(pkl install lyr --dir "$TG" 2>&1)" "skipped lyr: no checkout registered"
printf 'packs = ["harbor-private"]\n' > "$PL/harbor.toml"

t_section "usage"
t_exit "no verb is a usage error" 2 pk --dir "$T_TMP/x"
t_section "conf-keys.txt: a pack declares the harbor.toml keys its tools read, so core names none (#949)"
mkpack ck; printf '# keys\nck_project\n' > "$PW/ck/harbor-pack/conf-keys.txt"; G "$PW/ck" add -A; G "$PW/ck" commit -q -m k
listed '"ck"'
TG="$T_TMP/tg-ck"; mkdir -p "$TG/bin" "$TG/skills"; B0="$(snap "$TG")"
t_exit "a pack with conf-keys.txt installs" 0 pk install ck --apply --dir "$TG"
t_eq "...its keys land at conf-keys.d/<repo-id>.txt" "ck_project" "$(grep -v '^#' "$TG/conf-keys.d/ck.txt")"
PVK="$T_TMP/pv-ck"; mkdir -p "$PVK"; printf 'ck_project = "p1"\n' > "$PVK/harbor.toml"
t_eq "scope-roots.sh reads a key an installed pack declares" "p1" \
  "$(CLAUDE_CONFIG_DIR="$TG" HARBOR_SCOPE_PRIVATE="$PVK" sh "$T_ROOT/bin/scope-roots.sh" --conf ck_project 2>&1)"
t_exit "remove exits 0" 0 pk remove ck --apply --dir "$TG"
t_eq "...and takes the keys back, the target byte-identical" "$B0" "$(snap "$TG")"
t_exit "with the pack gone the key is unknown again (exit 2)" 2 \
  env CLAUDE_CONFIG_DIR="$TG" HARBOR_SCOPE_PRIVATE="$PVK" sh "$T_ROOT/bin/scope-roots.sh" --conf ck_project
mkpack kc; printf 'channel\n' > "$PW/kc/harbor-pack/conf-keys.txt"; G "$PW/kc" add -A; G "$PW/kc" commit -q -m k
refused conf-key-core kc "is a core harbor.toml key"
mkpack lg; printf 'gads_secret_project\n' > "$PW/lg/harbor-pack/conf-keys.txt"; G "$PW/lg" add -A; G "$PW/lg" commit -q -m k
listed '"lg"'; TGL="$T_TMP/tg-lg"; mkdir -p "$TGL/bin" "$TGL/skills"
t_exit "a legacy core key is the pack's to declare, and installs" 0 pk install lg --apply --dir "$TGL"
mkpack kb; printf 'Bad-Key\n' > "$PW/kb/harbor-pack/conf-keys.txt"; G "$PW/kb" add -A; G "$PW/kb" commit -q -m k
refused conf-key-shape kb "is not a key"
TG2="$T_TMP/tg-ck2"; mkdir -p "$TG2/bin" "$TG2/skills"; listed '"ck"'; pk install ck --apply --dir "$TG2" >/dev/null 2>&1
mkpack k2; printf 'ck_project\n' > "$PW/k2/harbor-pack/conf-keys.txt"; G "$PW/k2" add -A; G "$PW/k2" commit -q -m k
listed '"k2"'
_o2="$(pk install k2 --apply --dir "$TG2" 2>&1)"
t_has "a key another installed pack declares is refused, naming it" "$_o2" "declared by the installed pack ck.txt"

t_section "terms.tsv: a pack registers its workload's system terms, so core's registry names none (harbor#950)"
THDR="$(grep -v '^#' "$T_ROOT/standards/naming/terms.tsv" | awk 'NF { print; exit }')"
trow() { printf '%s\t%s\t%s\t-\t-\texperimental\t-\ttest\t-\t-\ta fixture system\n' "$1" "$2" "$1"; }
# tp <id> <"term class">...: a committed pack whose terms.tsv is core's header and these rows
tp() { _i="$1"; shift; mkpack "$_i"; { printf '%s\n' "$THDR"; for _r; do trow $_r; done; } > "$PW/$_i/harbor-pack/terms.tsv"
  G "$PW/$_i" add -A; G "$PW/$_i" commit -q -m t; }
lnc() { env CLAUDE_CONFIG_DIR="$1" HARBOR_SCOPE_PRIVATE="$PRIV" sh "$T_ROOT/bin/lint-name.sh" --check env WIDGETSYS_LINT_X 2>&1; }
tp tm "widgetsys system"; listed '"tm"'
TG="$T_TMP/tg-tm"; mkdir -p "$TG/bin" "$TG/skills"; B0="$(snap "$TG")"
t_has "positive control: before install the workload's prefix is unregistered" "$(lnc "$TG")" "not a registered system"
t_exit "a pack with terms.tsv installs" 0 pk install tm --apply --dir "$TG"
t_eq "...its rows land at terms.d/<repo-id>.tsv" "$(cat "$PW/tm/harbor-pack/terms.tsv")" "$(cat "$TG/terms.d/tm.tsv")"
t_has "...and bin/lint-name.sh reads them: the prefix is registered" "$(lnc "$TG")" "no finding"
t_exit "remove exits 0" 0 pk remove tm --apply --dir "$TG"
t_eq "...and takes the terms back, the target byte-identical" "$B0" "$(snap "$TG")"
tp tc "widget client"; refused terms-class tc "has class client: a pack registers system terms only"
tp tf "family system"; refused terms-core tf "family is a core term"
tp tk "WidgetSys system"; refused terms-kebab tk "is not a lowercase kebab term"
tp tw "widgetsys system" "widgetsys system"; refused terms-twice tw "widgetsys is listed twice"
mkpack th; printf 'id\tclass\nwidgetsys\tsystem\n' > "$PW/th/harbor-pack/terms.tsv"; G "$PW/th" add -A; G "$PW/th" commit -q -m t
refused terms-header th "its header is not the core terms.tsv header"
mkpack tn; { printf '%s\n' "$THDR"; printf 'widgetsys\tsystem\twidgetsys\n'; } > "$PW/tn/harbor-pack/terms.tsv"; G "$PW/tn" add -A; G "$PW/tn" commit -q -m t
refused terms-columns tn "has 3 columns, the header has 11"
{ printf '%s\n' "$THDR"; trow widgetsys system; } > "$PRIV/terms.tsv"; tp tv "widgetsys system"
refused terms-private tv "names a client or account"   # the private overlay's rows are leak patterns (D-85)
rm -f "$PRIV/terms.tsv"
TG2="$T_TMP/tg-tm2"; mkdir -p "$TG2/bin" "$TG2/skills"; listed '"tm"'; pk install tm --apply --dir "$TG2" >/dev/null 2>&1
tp t2 "widgetsys system"; listed '"t2"'
t_has "a term another installed pack declares is refused, naming it" "$(pk install t2 --apply --dir "$TG2" 2>&1)" "declared by the installed pack tm.tsv"

t_exit "no target is a usage error" 2 pk list
t_exit "the real dispatcher routes harbor pack" 2 env HARBOR_SCOPE_BIN="$T_ROOT/bin" sh "$T_ROOT/bin/harbor" pack
t_done
