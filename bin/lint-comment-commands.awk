# lint-comment-commands.awk — a destructive command quoted in backticks inside a shell comment (harbor lint.comment-commands).
# sh reads a script as it runs; a script rewritten in place under a running shell resumes mid-line, and a
# backtick span read from mid-comment is a command substitution. On 2026-10-15 that ran two such examples.
# Prints <file>\t<line>\t<span> per hit. Judged: comment lines of files whose name ends .sh or whose
# first line is a sh-family shebang. Run under LC_ALL=C.
FNR == 1 { sh = (FILENAME ~ /\.sh$/) || ($0 ~ /^#!.*(\/|env[ \t]+)(ba|da|k|z)?sh([ \t]|$)/) }
sh && /^[ \t]*#/ && !(FNR == 1 && /^#!/) {
  s = $0
  while (match(s, /`[^`]*`/)) {
    span = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
    body = substr(span, 2, length(span) - 2)
    sub(/^[ \t]*((sudo|env|command|exec|nohup|xargs)[ \t]+)*/, "", body)
    if (body ~ /^(s?rm|chmod|chown|chgrp|dd|mkfs[.a-z0-9]*|newfs(_[a-z0-9]+)?|shred|truncate|rsync|diskutil)[ \t]/)
      printf "%s\t%d\t%s\n", FILENAME, FNR, span
  }
}
