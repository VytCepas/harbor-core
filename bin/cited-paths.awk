# cited-paths.awk (harbor#462) — THE ONE EXTRACTOR for paths cited in prose.
#
#   awk -f cited-paths.awk <file>      one cited path per line, in file order
#
# WHY THIS FILE EXISTS, AND IT IS NOT TIDINESS. Two rules ask the same question
# of the same document and each carried its own extractor:
#
#   lint K1   "every repo path cited by CONSTITUTION.md resolves"   -> the REPO
#   REF-5     "the installed CLAUDE.md's citations resolve"         -> the BOX
#
# Both were born in commit 8b50867 on 2026-08-03. That single commit ALSO
# migrated CONSTITUTION.md from 16 markdown links to 13 backticked paths, on the
# reasoning written into K1's own comment: "a BACKTICKED `./path` — plain text,
# which cannot dangle anywhere". K1 was given a second arm to read the new form.
# REF-5 was not, and its extractor has not changed since.
#
# THE PREMISE WAS FALSE. A backticked `./DOCTRINE/grilling.md` dangles exactly as
# hard as a markdown link to it — the reader follows it and gets nothing either
# way. What the migration actually changed is that the only instrument aimed at
# the installed surface stopped being able to SEE the citations. Measured
# 2026-09-06: REF-5 extracted 0 paths from a 21,552-byte CLAUDE.md carrying 10,
# all 10 dead, and reported "every hook, pin and citation on the installed
# surface resolves" with exit 0 — for its entire existence, on its own headline
# subject. CONSTITUTION §2.10, a test that cannot fail is worse than no test.
#
# So the extractor is ONE FILE that both rules run, because the defect was never
# the parsing. It was that a document dialect could change under a checker
# without the checker changing with it, and two copies is what made that
# possible. floor-normalize.awk is the precedent for a shared awk program here.
#
# WHAT IT EMITS, AND WHY THE TWO FORMS ARE NOT TREATED ALIKE:
#
#   [text](target)   every target, VERBATIM, including URLs and #anchors.
#                    Callers filter — REF-5 skips URLs, K1 wants ./ only — and a
#                    filter belongs at the caller because the two want different
#                    sets. Emitting the raw target keeps this file free of any
#                    policy it would then hold a second copy of.
#
#   `./path`         backticked, and ONLY when ./-prefixed. K1's comment argues
#                    this and it is right: a bare `FLOOR.md` in backticks is
#                    indistinguishable from prose, and widening to "any backticked
#                    token with a dot" would have to decide about `permissions.deny`
#                    and `harbor#44`. A rule that guesses is a rule that gets muted
#                    (§2.11). The `./` is what keeps this exhaustive, not heuristic.
#
# FRAGMENTS ARE LEFT ON. `./A.md#section` is emitted whole so a caller can print
# what the document actually says; stripping for the filesystem test is the
# caller's job. REF-5 shipped once treating `A.md#section` as a filename.
#
# awk AND NOT grep, and this is the same note reference-check.sh and K1 both
# carry: on this box `grep` is a ugrep wrapper with -I --ignore-files, so a line
# it silently skips produces FEWER findings. Every consumer of this file rests a
# NEGATIVE on it ("nothing dangles"), which is the one direction where a missed
# line reads as success.
#
# -v WITHFILE=1 PREFIXES EACH ROW WITH `FILENAME<TAB>`, and it exists for cost,
# not taste. REF-9 asks this question of a whole corpus, and one awk process per
# file over the installed skills measured 687 ms against 135 ms for a single pass
# — on a check whose entire budget is 0.22 s. Provenance is the only thing a
# multi-file pass loses, so it is the only thing this flag adds. Default off, so
# every existing caller reads byte-identical output.

function emit(p) { print (WITHFILE ? FILENAME "\t" p : p) }

{
  # A link inside a code span is shown, not followed: cu.md's `[id](…/t/id)` example was REF-9's one
  # live red (harbor#1018). Spans are dropped from the link arm only; the `./path` arm below needs them.
  s = $0
  gsub(/`[^`]*`/, "", s)
  while (match(s, /\]\([^)]*\)/)) {
    emit(substr(s, RSTART + 2, RLENGTH - 3))
    s = substr(s, RSTART + RLENGTH)
  }
  t = $0
  while (match(t, /`\.\/[^`]+`/)) {
    emit(substr(t, RSTART + 1, RLENGTH - 2))
    t = substr(t, RSTART + RLENGTH)
  }
}
