#!/usr/bin/env sh
# merge-note.sh (harbor#173 · A1) — hand the merge moment to bin/govern-hook.sh.
#
# WHY A WRAPPER AND NOT A STATIC PACK. Everything else in inject.d/ is text,
# because a static rule is the same sentence every time. The merge notes are not:
# the PostToolUse half computes which local branches the merge just retired, which
# of those a worktree is pinning, and how far behind origin this checkout now is.
# That is 160 lines of git with an adversarial suite behind it (tests/hooks/govern-hook-test.sh,
# 33 cases), and copying any of it into a markdown body would be a second copy of
# a tested thing.
#
# `--note` PRINTS THE TEXT WITHOUT THE ENVELOPE, which is inject-hook.sh's `run:`
# contract. The matcher, the conditionals and the silences are unchanged — this
# script decides nothing.
exec sh "bin/govern-hook.sh" --note
