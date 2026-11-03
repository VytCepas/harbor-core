#!/usr/bin/env sh
# bin/gate-merge-stack-resolve.py (harbor#1060): conflict blocks (git's diff3 style: ours, base, theirs) where both sides
# only ADD to the base are resolved by keeping both; deletions, edits and every other shape are refused with the file
# untouched. No line is taken for a comment (r4 #3); a declared line list (--lines) is resolved line by line.
# One mutant per shape, one for the refusal and one for the base check must go red.
. "$(dirname "$0")/../../lib/core.sh"; t_init
RS="$T_ROOT/bin/gate-merge-stack-resolve.py"; D="$T_TMP/r"; mkdir -p "$D"
blk() { [ -z "$1" ] || printf '%s\n' "$1"; }
# mk <name> <base> <ours> <theirs>: a diff3-style conflicted file with a line before and after
mk() { { echo before; echo '<<<<<<< HEAD'; blk "$3"; echo '||||||| base'; blk "$2"; echo '======='; blk "$4"; echo '>>>>>>> pr'; echo after; } > "$D/$1"; }
res() { python3 -I "${3:-$RS}" $4 "$D/$1" >/dev/null 2>&1; echo $?; }
want() { printf 'before\n%s\nafter\n' "$1"; }
mutate() { # <label> <old> <new> → $D/mut.py
  python3 - "$RS" "$D/mut.py" "$2" "$3" <<'PY'
import sys
s = open(sys.argv[1]).read()
assert sys.argv[3] in s, "mutation anchor not found"
open(sys.argv[2], "w").write(s.replace(sys.argv[3], sys.argv[4]))
PY
  t_eq "$1: the mutation applies" 0 "$?"
}
F_B='FILES="a b"'; F_O='FILES="a b c"'; F_T='FILES="a b d"'
CS_B='  case "$b" in library-admission.sh) continue ;; esac'; CS_O='  case "$b" in library-admission.sh|library-log.sh) continue ;; esac'; CS_T='  case "$b" in library-admission.sh|library-fs.sh) continue ;; esac'
CL_B='c"'; CL_O='c d"'; CL_T='c e f"'
shapes() { # <resolver> <expected-exit>
  mk files.sh "$F_B" "$F_O" "$F_T"; t_eq "FILES word list: exit" "$2" "$(res files.sh x "$1")"
  mk cs.sh "$CS_B" "$CS_O" "$CS_T"; t_eq "case alternatives: exit" "$2" "$(res cs.sh x "$1")"
  mk cl.sh "$CL_B" "$CL_O" "$CL_T"; t_eq "closing word list: exit" "$2" "$(res cl.sh x "$1")"
}

t_section "every shape, with both sides only adding to the base, keeps both"
shapes "$RS" 0
t_eq "FILES: the union, ours first, with the lines around it kept" "$(want 'FILES="a b c d"')" "$(cat "$D/files.sh")"
t_eq "case: the alternatives unioned" "$(want '  case "$b" in library-admission.sh|library-log.sh|library-fs.sh) continue ;; esac')" "$(cat "$D/cs.sh")"
t_eq "closing list: the new words join the last line" "$(want 'c d e f"')" "$(cat "$D/cl.sh")"
mk same.sh "$F_B" "$F_O" "$F_O"; res same.sh x >/dev/null; t_eq "identical sides resolve to one" "$(want "$F_O")" "$(cat "$D/same.sh")"
mk sub.sh "$CL_B" 'c d"' 'c"'; res sub.sh x >/dev/null; t_eq "a closing list whose other side adds nothing keeps ours" "$(want 'c d"')" "$(cat "$D/sub.sh")"
printf 'x\n' > "$D/none.sh"; t_eq "a file with no conflict block is not resolved: exit 1 (a delete/modify leaves none, r5 #1)" 1 "$(res none.sh x)"; t_eq "...left byte for byte" x "$(cat "$D/none.sh")"
printf 'v\000\001' > "$D/blob.sh"; t_eq "...nor is a binary file, which git leaves with no marker" 1 "$(res blob.sh x)"
printf 'a\n' > "$D/none.txt"; t_eq "...in --lines mode too" 1 "$(res none.txt x "$RS" --lines)"
mutate "M55 a file with no block passes (r5 #1 reverted)" "blocks == 0 or " ""
python3 - "$D/mut.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read(); a = "if '<<<<<<<' not in s or not hash_syntax(p, s)"
assert a in s; open(p, "w").write(s.replace(a, "if '<<<<<<<' in s and not hash_syntax(p, s)"))
PY
t_eq "M55: the marker-free file is resolved, exit 0" 0 "$(res none.sh x "$D/mut.py")"

t_section "a deletion or an edit relative to the base is refused, not brought back (the reviewer's two examples)"
refuse() { # <label> <base> <ours> <theirs>
  mk r.sh "$2" "$3" "$4"; cp "$D/r.sh" "$D/r.sh.orig"
  t_eq "$1: exit 1" 1 "$(res r.sh x)"; t_eq "$1: file untouched" "" "$(cmp "$D/r.sh" "$D/r.sh.orig" 2>&1)"
}
refuse 'FILES: a side deleted b (FILES="a b c" against "a c d")' 'FILES="a b c"' 'FILES="a b c e"' 'FILES="a c d"'
refuse 'closing list: a side replaced build/ (rm -rf build/" against rm -rf /")' 'rm -rf build/"' 'rm -rf build/ x"' 'rm -rf /"'
refuse "FILES: an edit is a deletion plus an addition" 'FILES="a b"' 'FILES="a b c"' 'FILES="a x"'
refuse "case: a deleted alternative" '  case "$b" in a|b) continue ;; esac' '  case "$b" in a|b|c) continue ;; esac' '  case "$b" in a|d) continue ;; esac'
refuse "comments: a deleted comment" '# keep me' '# keep me
# ours' '# theirs'
refuse "comments: two added from an empty base (a # line may be data, so it is never a comment)" '' '# ours' '# theirs'
refuse "a FILES line with a comment added above it" 'FILES="a b"' '# why c
FILES="a b c"' 'FILES="a b d"'
printf 'before\n<<<<<<< HEAD\nFILES="a b c"\n=======\nFILES="a b d"\n>>>>>>> pr\nafter\n' > "$D/nobase.sh"; cp "$D/nobase.sh" "$D/nobase.sh.orig"
t_eq "a block with no base section (merge style) is refused: exit 1" 1 "$(res nobase.sh x)"
t_eq "...file untouched" "" "$(cmp "$D/nobase.sh" "$D/nobase.sh.orig" 2>&1)"

t_section "every other shape is refused and the file is left untouched"
refuse "code lines" 'echo base' 'echo one' 'echo two'
refuse "one side empty" 'FILES="a b"' 'FILES="a b"' ''
refuse "a different word-list variable" 'PATHS="a"' 'PATHS="a b"' 'PATHS="a c"'
refuse "a case on another variable" '  case "$x" in a) continue ;; esac' '  case "$x" in a|b) continue ;; esac' '  case "$x" in a|c) continue ;; esac'
refuse "a case with another body" '  case "$b" in a) break ;; esac' '  case "$b" in a|b) break ;; esac' '  case "$b" in a|c) break ;; esac'
refuse "a closing list with a comment in it" 'c"' 'c d" # why' 'c e"'
refuse "a list line with a command in it" 'c"' 'c $(rm x)"' 'c e"'
refuse "an indented closing list (the shape starts at a word)" '  c"' '  c d"' '  c e"'
refuse "a FILES line both sides added, with no base" '' 'FILES="a"' 'FILES="b"'
printf 'ok\n<<<<<<< HEAD\nFILES="a b c"\n||||||| base\nFILES="a b"\n=======\nFILES="a b d"\n>>>>>>> pr\nmid\n<<<<<<< HEAD\necho one\n||||||| base\necho\n=======\necho two\n>>>>>>> pr\n' > "$D/mixed.sh"; cp "$D/mixed.sh" "$D/mixed.sh.orig"
t_eq "a file with a resolvable and a refused block: exit 1" 1 "$(res mixed.sh x)"
t_eq "...and not even the resolvable one is written" "" "$(cmp "$D/mixed.sh" "$D/mixed.sh.orig" 2>&1)"
t_exit "no argument is a usage error" 2 python3 -I "$RS"

t_section "a # line is never a comment: inside an sh here-doc it is data (r4 #3) (red-proof)"
# the reviewer's case: a .sh whose here-doc writes C, each side adding a different #define (probes-1126-r4/base.sh, theirs.sh)
printf '#!/bin/sh\ncat > config.h <<EOF\nEOF\n' > "$D/hb.sh"; printf '#!/bin/sh\ncat > config.h <<EOF\n#define LIMIT 10\nEOF\n' > "$D/ho.sh"
printf '#!/bin/sh\ncat > config.h <<EOF\n#define LIMIT 99999\nEOF\n' > "$D/ht.sh"
git merge-file -p --diff3 "$D/ho.sh" "$D/hb.sh" "$D/ht.sh" > "$D/gen.sh"; t_eq "git leaves a conflict in gen.sh" 1 "$?"
cp "$D/gen.sh" "$D/gen.sh.orig"
t_eq "two #defines in a here-doc of a .sh are refused: exit 1" 1 "$(res gen.sh)"
t_eq "...file untouched" "" "$(cmp "$D/gen.sh" "$D/gen.sh.orig" 2>&1)"
printf 'x = 1\n<<<<<<< HEAD\n# ours\n||||||| base\n=======\n# theirs\n>>>>>>> pr\n' > "$D/doc.py"
t_eq "a .py comment block is refused too (a # line may sit in a triple-quoted string)" 1 "$(res doc.py)"

t_section "known syntax only: C, Markdown and unknown files are refused whole (red-proof)"
# the reviewer's case: two conflicting #defines from an empty base, as git merge-file --diff3 writes them
printf '#include <stdio.h>\n' > "$D/base.h"; cp "$D/base.h" "$D/ours.h"; cp "$D/base.h" "$D/theirs.h"
printf '#define LIMIT 10\n' >> "$D/ours.h"; printf '#define LIMIT 99999\n' >> "$D/theirs.h"
git merge-file -p --diff3 "$D/ours.h" "$D/base.h" "$D/theirs.h" > "$D/limits.h"; t_eq "git leaves a conflict in limits.h" 1 "$?"
cp "$D/limits.h" "$D/limits.h.orig"
t_eq "C: two conflicting #defines are refused: exit 1" 1 "$(res limits.h)"
t_eq "...file untouched" "" "$(cmp "$D/limits.h" "$D/limits.h.orig" 2>&1)"
mk doc.md '' '# ours' '# theirs'; cp "$D/doc.md" "$D/doc.md.orig"
t_eq "Markdown: two headings are not comments: exit 1" 1 "$(res doc.md)"; t_eq "...file untouched" "" "$(cmp "$D/doc.md" "$D/doc.md.orig" 2>&1)"
mk plain "$F_B" "$F_O" "$F_T"; t_eq "an extensionless file with no shebang is refused, even a FILES list: exit 1" 1 "$(res plain)"
sheb() { { echo "$2"; echo '<<<<<<< HEAD'; echo "$F_O"; echo '||||||| base'; echo "$F_B"; echo '======='; echo "$F_T"; echo '>>>>>>> pr'; } > "$D/$1"; }
sheb tool '#!/bin/sh'; t_eq "an extensionless #!/bin/sh script: its FILES list resolved, exit 0" 0 "$(res tool)"
t_eq "...both kept" "#!/bin/sh
FILES=\"a b c d\"" "$(cat "$D/tool")"
sheb tool.py3 '#!/usr/bin/env python3'; t_eq "an env python3 script: resolved, exit 0" 0 "$(res tool.py3)"
sheb tool.js '#!/usr/bin/env node'; t_eq "an env node script: refused, exit 1" 1 "$(res tool.js)"
mk shebang.sh '' '#!/bin/sh' '#!/bin/bash'; t_eq "two shebang lines are not comments: exit 1" 1 "$(res shebang.sh)"
mutate "M34 every file is taken to use # comments" "or not hash_syntax(p, s)" "or False"
mk plain "$F_B" "$F_O" "$F_T"; t_eq "M34: the extensionless file's FILES list is resolved (exit 0)" 0 "$(res plain x "$D/mut.py")"

t_section "red-proof: each shape, the refusal and the base check, removed from a copy, goes red"
mutate "M10 the FILES shape" 'FILES="' 'FILEX="'
mk files.sh "$F_B" "$F_O" "$F_T"; t_eq "M10: FILES is no longer resolved" 1 "$(res files.sh x "$D/mut.py")"
mutate "M12 the case shape" ') continue ;; esac' ') continue ;; esaX'
mk cs.sh "$CS_B" "$CS_O" "$CS_T"; t_eq "M12: case is no longer resolved" 1 "$(res cs.sh x "$D/mut.py")"
mutate "M13 the closing-list shape" ".endswith('\"') and t[-1]" ".endswith('@') and t[-1]"
mk cl.sh "$CL_B" "$CL_O" "$CL_T"; t_eq "M13: the closing list is no longer resolved" 1 "$(res cl.sh x "$D/mut.py")"
mutate "M14 the refusal: an unknown shape takes ours" 'raise SystemExit(1)' "return ''.join(o)"
mk r.sh 'echo base' 'echo one' 'echo two'; t_eq "M14: a refused shape is now resolved (exit 0, so the refusal test goes red)" 0 "$(res r.sh x "$D/mut.py")"
mutate "M29 the base is not consulted: deletions are unioned back" 'if not only_adds(' 'if False and not only_adds('
mk r.sh 'FILES="a b c"' 'FILES="a b c e"' 'FILES="a c d"'; t_eq "M29: the FILES deletion is brought back (exit 0)" 0 "$(res r.sh x "$D/mut.py")"
mk r.sh 'rm -rf build/"' 'rm -rf build/ x"' 'rm -rf /"'; t_eq "M29: so is the rm -rf one" 0 "$(res r.sh x "$D/mut.py")"

t_section "a declared line list (--lines): whole lines both sides added are kept, a lost line is refused (r4 #2)"
mk list.txt 'tests/a.test.sh' 'tests/a.test.sh
tests/m.test.sh' 'tests/a.test.sh
tests/p.test.sh'
t_eq "--lines: both sides added a line: exit 0" 0 "$(res list.txt x "$RS" --lines)"
t_eq "...ours, then theirs' new line" "$(want 'tests/a.test.sh
tests/m.test.sh
tests/p.test.sh')" "$(cat "$D/list.txt")"
mk dup.tsv '' 'x	1
y	2' 'y	2
z	3'
res dup.tsv x "$RS" --lines >/dev/null; t_eq "--lines: a line both added is kept once" "$(want 'x	1
y	2
z	3')" "$(cat "$D/dup.tsv")"
mk cm.txt '# header' '# header
# a' '# header
#define B'; t_eq "--lines: # lines are data like any other line" 0 "$(res cm.txt x "$RS" --lines)"
lrefuse() { mk "$2" "$3" "$4" "$5"; cp "$D/$2" "$D/$2.orig"
  t_eq "$1: exit 1" 1 "$(res "$2" x "$RS" --lines)"; t_eq "$1: file untouched" "" "$(cmp "$D/$2" "$D/$2.orig" 2>&1)"; }
lrefuse "--lines: main deleted a line the PR kept" del.txt 'old
keep' 'keep
m' 'old
keep
p'
lrefuse "--lines: an edited line (the reviewer's ALLOW= case)" ed.txt 'ALLOW="status deploy"' 'ALLOW="status"' 'ALLOW="status deploy doctor"'
lrefuse "--lines on code (.sh) is refused: a line list is data" code.sh '' 'a=1' 'b=2'
lrefuse "--lines on a document (.md) is refused" cli.md '' '| x |' '| y |'
t_eq "without --lines, a .txt line block is no shape: refused" 1 "$(mk l2.txt 'a' 'a
m' 'a
p'; res l2.txt)"
mutate "M35 --lines ignores the base" 'if not only_adds(b, o, t)' 'if False'
mk del.txt 'old
keep' 'keep
m' 'old
keep
p'; t_eq "M35: the deleted line comes back (exit 0)" 0 "$(res del.txt x "$D/mut.py" --lines)"
t_eq "M35: ...it is in the file again" 1 "$(grep -c '^old$' "$D/del.txt")"
t_done
