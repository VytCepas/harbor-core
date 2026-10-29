# STATUS — generated, do not edit

Every number Harbor states about itself lives here and nowhere else.
Regenerate with `sh bin/status-gen.sh --apply`; lint rule **T1** fails if this
file is stale, and **T2** fails if another document states one of these counts
in prose.

This exists because the same fact was found stated three different ways across
three documents on 2026-07-26 — none of them wrong when written, all of them
copies of a fact that lives in the code.

Everything here is **counted from the repo**, so it reads the same on every
machine. What is true of THIS machine — which layers of the floor are actually
installed, whether the live `bin/` lags — is a different kind of fact and is
deliberately not in git: it moved on every deploy and reddened CI until someone
regenerated it. Ask for it when you want it:

```
sh bin/status-gen.sh --observed      # or: harbor status --observed
```

## Counted from the repo

| | |
|---|---|
| lint rules | 105 |
| vendored skills | 28 |
| frozen contracts | 28 |
| floor guards | 9 |
| shared marker fixtures | 38 |
| recorded failures nothing watches | 31 |
| `floor-test` assertions | 1055 |
| `normalize-test` assertions | 198 |
| `marker-test` assertions | 39 |
