#!/usr/bin/env sh
# lint.comment-commands: no shell comment quotes a destructive command in backticks.
# Each arm is a throwaway git checkout holding one planted file; the verdict is read from the rule's own output.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
R="VIOLATION [lint.comment-commands]"
mk() { # <name> <file> <body…> → a checkout whose only sh file is <file>
  _d="$T_TMP/cc-$1"; mkdir -p "$_d/bin"; cp "$T_ROOT/bin/lint-comment-commands.awk" "$_d/bin/"
  _f="$2"; shift 2; mkdir -p "$_d/$(dirname "$_f")"; printf "$@" > "$_d/$_f"
  ( cd "$_d" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm x ) >/dev/null 2>&1
  printf '%s' "$_d"
}
run() { lint1 lint.comment-commands "$(mk "$@")"; }

t_section "red: a destructive verb in backticks in a comment"
for v in 'rm -rf /tmp/probe' 'chmod -R 000 /tmp/probe' 'chown -R nobody /tmp/probe' 'srm -r /tmp/probe' \
         'shred -u /tmp/probe' 'truncate -s 0 /tmp/probe' 'rsync -a --delete a/ b/' 'dd if=/dev/zero of=/tmp/probe' \
         'mkfs.ext4 /dev/null' 'newfs_hfs /dev/null' 'sudo rm -rf /tmp/probe' 'env chmod 0 /tmp/probe'; do
  t_has "$v" "$(run red bin/bad.sh '#!/bin/sh\n# measured, `%s` passed\n:\n' "$v")" "$R bin/bad.sh:2 "
done
t_has "an indented comment" "$(run ind bin/i.sh '#!/bin/sh\nf() {\n  # e.g. `rm -rf /tmp/probe`\n}\n')" "$R bin/i.sh:3 "
t_has "the second span on a line" "$(run two bin/t.sh '# `ls` then `rm -rf /tmp/probe`\n')" "$R bin/t.sh:1 "
t_has "an extensionless file with a sh shebang" "$(run noext bin/tool '#!/usr/bin/env bash\n# `rm -rf /tmp/probe`\n')" "$R bin/tool:2 "
t_has "the fix line is there" "$(run fix bin/bad.sh '# `rm -rf /tmp/probe`\n')" "quote it with ' instead"

t_section "green: what is not the hazard"
t_hasnt "single-quoted example" "$(run sq bin/ok.sh "#!/bin/sh\n# measured, 'rm -rf /tmp/probe' passed\n")" "$R"
t_hasnt "a harmless verb in backticks" "$(run harmless bin/ok.sh '#!/bin/sh\n# run `ls -la` or `git status`\n')" "$R"
t_hasnt "a verb as a prefix of a longer word" "$(run prefix bin/ok.sh '# `rmdir x` and `ddx y`\n')" "$R"
t_hasnt "backticks in code, not a comment" "$(run code bin/ok.sh 'x=`echo rm -rf`\n')" "$R"
t_hasnt "a markdown file" "$(run md docs/a.md '# `rm -rf /tmp/probe`\n')" "$R"
t_hasnt "a python file" "$(run py bin/a.py '# `rm -rf /tmp/probe`\n')" "$R"
t_done
