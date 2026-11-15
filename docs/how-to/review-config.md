---
kind: how-to
owner: @VytCepas
status: unreviewed
---

# Configure the PR review bot per repo

The `review:` block of `.agents/config.yaml` sets how the in-house reviewer treats this repo (harbor#1497). Every key is optional; an absent file or block means the defaults.

```yaml
review:
  tier: standard            # default tier: quick | standard | deep
  quick-under-lines: 30     # a diff under this many lines goes quick
  max-inline: 10            # inline comments per review, 0..50 (0 = summary only)
  verify: on                # only on is valid
  quick-lenses: 1           # lens subagents per tier, 1..6
  standard-lenses: 4
  deep-lenses: 6
  exclude-authors:          # explicit logins, brackets allowed; no wildcards
    - dependabot[bot]
    - renovate[bot]
  docs-paths:               # all files match: quick
    - docs/*
    - "*.md"
  generated-paths:          # all files match: no review
    - "*.lock"
  deep-paths:               # any file matches: deep
    - .agents/*
```

- **Lists** are block items (`- item`) or `[]`. A list you set replaces its defaults, so `exclude-authors: []` excludes nobody.
- **Globs** are `case` patterns where `*` crosses `/`. A glob that matches every path, starts with `/`, holds `..` or has an unbalanced `[` is refused.
- **No tier is a single agent.** Every tier keeps at least one lens and a separate verifier: `verify: off` and a lens count of 0 are refused.
- **Bots are excluded by name**, never by "is a bot": most PRs here come from the harbor App, and that is reviewed.

## Where it is read from

The reader takes the config from the PR's **base** commit (`git show <base>:.agents/config.yaml`), never the working tree or the PR head, so a PR cannot exclude itself or its files from review. A config change takes effect once it is merged.

```sh
sh bin/audit-review-config.sh read --base origin/main          # effective config, key=value
sh bin/audit-review-config.sh decide --base origin/main --author alice --lines 40   # changed paths on stdin
sh bin/audit-review-config.sh check .agents/config.yaml        # the shape check
```

`decide` order: excluded author, then no files, then all files generated (skip); otherwise any deep path (deep), all docs (quick), a small diff (quick), else the default tier.

The shape is held by lint rule `lint.review-config-shape` (`sh bin/lint-conventions.sh --only lint.review-config-shape`), which runs the same parser the reader uses. Tests: `tests/audit/review-config/reader.test.sh`, `tests/lint/conventions/review-config.test.sh`.
