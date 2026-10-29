#!/usr/bin/env sh
# bin/lint-comment.sh (harbor#978): header line 2 and the comment rule, on added lines only.
. "$(dirname "$0")/../../lib/core.sh"; t_init
LC="$T_ROOT/bin/lint-comment.sh"
G="$T_TMP/repo"; mkdir -p "$G/bin" "$G/standards/naming"
git -C "$G" init -q -b main
printf '#!/usr/bin/env sh\n# legacy.sh (harbor#1) — old\n# a\n# b\n# c\n# d\n# e\nx=1\n' > "$G/bin/legacy.sh"
printf 'id\tmode\n' > "$G/standards/naming/controls.tsv"
git -C "$G" add -A && git -C "$G" -c user.email=t@e.invalid -c user.name=t commit -q -m base
git -C "$G" checkout -q -b feature
printf '#!/usr/bin/env sh\n# good.sh (harbor#2) — fine\nx=1\n' > "$G/bin/good.sh"
printf '#!/usr/bin/env sh\n# whatever it does\nx=1\n' > "$G/bin/nohead.sh"
printf '#!/usr/bin/env sh\n# other.sh (harbor#2) — wrong name\nx=1\n' > "$G/bin/wrongname.sh"
printf '// good.ts (harbor#3) — ts header\nexport const x = 1\n' > "$G/bin/good.ts"
printf '#!/usr/bin/env sh\n# hdrblock.sh (harbor#2) — ok\n# h3\n# h4\n# h5\n# h6\nx=1\n' > "$G/bin/hdrblock.sh"
{ printf '#!/usr/bin/env sh\n# late.sh (harbor#2) — ok\n'; i=0; while [ $i -lt 8 ]; do echo x=1; i=$((i+1)); done; printf '# a\n# b\n# c\n# d\n'; } > "$G/bin/late.sh"
{ cat "$G/bin/legacy.sh"; printf 'y=1\n# one\n# two\n# three\n# four\nz=2\n# ok1\n# ok2\nw=3\n'; } > "$G/bin/legacy.new"; mv "$G/bin/legacy.new" "$G/bin/legacy.sh"
git -C "$G" add -A && git -C "$G" -c user.email=t@e.invalid -c user.name=t commit -q -m branch
out="$(sh "$LC" --root "$G" --base main 2>&1)"
t_has "an added 4-line comment block is flagged" "$out" "[lint.comment-added] bin/legacy.sh:10"
t_hasnt "a 2-line added block is not" "$out" "legacy.sh:15"
t_hasnt "the untouched legacy 5-line block is not" "$out" "legacy.sh:3"
t_has "an added file without the line-2 header is flagged" "$out" "[lint.file-header] bin/nohead.sh:2"
t_has "a header naming another file is flagged" "$out" "[lint.file-header] bin/wrongname.sh:2"
t_hasnt "a compliant sh header passes" "$out" "bin/good.sh"
t_hasnt "a compliant ts header passes" "$out" "bin/good.ts"
t_has "a 4-line block in a new file below its header is flagged" "$out" "[lint.comment-added] bin/late.sh:11"
t_hasnt "a new file's own header block is exempt from the run rule" "$out" "hdrblock.sh"
t_exit "warn findings exit 0" 0 sh "$LC" --root "$G" --base main
t_exit "no base is unchecked, never clean" 3 sh "$LC" --root "$G" --base no-such-ref
printf 'id\tmode\nlint.comment-added\tblock\n' > "$G/standards/naming/controls.tsv"
t_exit "a block row makes the run fail" 1 sh "$LC" --root "$G" --base main
printf 'id\tmode\nlint.comment-added\tshadow\nlint.file-header\tshadow\n' > "$G/standards/naming/controls.tsv"
t_eq "shadow prints nothing" "" "$(sh "$LC" --root "$G" --base main 2>&1 | grep -c 'WARN\|FAIL' | grep -v '^0$')"
t_done
