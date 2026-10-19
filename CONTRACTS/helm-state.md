# The `.helm-*` state files — which ones a session may write

Added 2026-09-27 for harbor#779. Every `.helm-*` name in `bin/` is one row of the
table below, and lint **F14** holds the table to the code in both directions: a
name in `bin/` with no row fails, and so does a row no file in `bin/` names. The
same rule checks that the three enforcement layers name every **integrity** row and
nothing else.

## The classes

- **integrity**: a reader on the floor's side trusts the content, so a session must
  not write it. Three layers refuse the write: guard-bash (every write verb the
  `SURFACE` rules model, through `FILES`), guard-selfedit (Write, Edit, MultiEdit)
  and the B1 deny list (`Edit(~/.claude/<name>)`, or `<name>/**` for a directory).
  The writer that owns it is a hook, an installer run from a terminal, or the
  operator. Hooks run outside the Bash tool, so the guards never see their writes.
- **cache**: the reader only displays or reports it, or a session writes it by
  design. It gets no per-file protection. The general harbor#280 rule still refuses
  a shell redirect anywhere in the config dir outside `MEMORY/` and `projects/`.
- **scratch**: the name never lands in a config dir. It is a temp file under
  `$TMPDIR`, a temp sibling renamed over its target, or a test string. It has a row
  only so F14 can tell it apart from an unclassified name.

## The table

Paths are relative to the config dir (`<cfg>`) unless they say otherwise.

| name | where | class | reader that trusts it | writer that owns it | why |
|---|---|---|---|---|---|
| `.helm-apiroute` | `<cfg>/.helm-apiroute/` | integrity | guard-apiroute.sh: the accepted copy a reroute is judged against | guard-apiroute.sh (PostToolUse and SessionStart hook) | A session that writes the accepted copy blesses its own API reroute (guard-apiroute.sh:42). |
| `.helm-apiroute-allow` | `<cfg>/.helm-apiroute-allow` | integrity | guard-apiroute.sh | the operator, by hand | A session that writes it allows the reroute it is about to make (FLOOR.md, guard-apiroute). |
| `.helm-approvals` | `<cfg>/.helm-approvals/` (`ledger.tsv`, `approved/<queue id>`) | integrity | the gate tools: the ledger is the record of every approval and unattended merge; the runner takes `--approved` only while its one-shot token exists (docs/design/approval-gate.md) | gate-approve.sh and gate-merge.sh append the ledger; gate-approve.sh writes and removes the token (harbor#1018) | A session that writes it forges an approval record, erases a refusal, or forges the click's token. |
| `.helm-ship` | `<cfg>/.helm-ship/` | integrity | deploy-fleet.sh (the ship runner, harbor#1128): the last deployed commit per repo, which decides what a deploy's change is, and the rollback record that stops a retry | deploy-fleet.sh, run by the operator or the runner's own schedule (harbor#1018) | A session that writes it moves a repo's deployed sha so a protected change looks already deployed, or erases a rollback so a red plan is applied again. Kept out of deploy's snapshot set on purpose: a restore must not roll back the record of the deploy it undoes. |
| `.helm-baseline` | `<cfg>/.helm-baseline` | integrity | none in `bin/` since baseline-pin was retired (harbor#765) | none | Kept protected, so this table removes no existing protection. The install standard's prune retires the file. |
| `.helm-context` | `<cfg>/.helm-context/<session_id>` | integrity | `floor_engine_stand_down` in guard-lib.sh, for worklog-push.sh and memory-harvest.sh | context-resolve.sh (SessionStart hook) | A session that writes its own verdict decides whether the work-log and harvest engines record it. worklog-push.sh:19-21 treats the same forgery, made with a planted marker, as a defect. |
| `.helm-deny-hashes` | `<cfg>/.helm-deny-hashes` | cache | deny-hash.sh `--scan`, run on demand | deny-hash.sh `--derive` | No guard consults it (deny-hash.sh:31). A forged filter changes only what an on-demand scan prints. |
| `.helm-deny-terms` | `<cfg>/.helm-deny-terms` | cache | deny-hash.sh `--derive` | the operator | The operator's input to that offline scanner. Keeping it secret is a read question, which this table does not cover. |
| `.helm-dispatch` | `<cfg>/.helm-dispatch/` | integrity | event-dispatch.sh: the follower obeys `rules/`, spawns only while `spawn.on` exists, holds the $5 day to `spend/` and dedups on `ledger` | event-dispatch.sh `on` from the operator's terminal, and its follower under launchd; both refuse inside a Claude session | A session that writes it turns the spawner on, writes the rule an agent runs, or resets the day's spend cap (harbor#1044 review r3 #1: six truncations let $6.50 through a $5 cap). |
| `.helm-floor-teeth` | `<cfg>/.helm-floor-teeth` | integrity | guard-integrity.sh (B6) and session-verdicts.sh | floor-deny.sh `--apply` | The hash of the deny list and the locks. Writable, it re-blesses a gutted deny list. |
| `.helm-govern-salt` | `<cfg>/.helm-govern-salt` | integrity | govern-token.sh `--token` and `--announce` (SessionStart and the inject hooks), reference-check.sh REF-7 | govern-token.sh `--init`, once, by hand | The salt is what stops fetched text computing a governance token (govern-token.sh:21-25). A session that writes it knows every later session's token. |
| `.helm-install-stamp` | `<cfg>/.helm-install-stamp` | integrity | install-stamp.sh `--check` in deploy.sh's preflight (deploy.sh:173), renew-check.sh, failure-capture.sh, floor-uninstall.sh, runtime-install.sh | install-stamp.sh `--write`, called by floor-install.sh and runtime-install.sh | A forged sha lets deploy's regression preflight pass a deploy that removes installed work (install-stamp.sh:2-33), or refuse a sound one. |
| `.helm-instructions.sha256` | `<cfg>/.helm-instructions.sha256` | integrity | guard-integrity.sh (B8) and renew-check.sh | pin-instructions.sh `--apply` | Writable, a session injects into CLAUDE.md and then re-pins over its tracks. |
| `.helm-judge` | `<cfg>/.helm-judge` | integrity | session-verdicts.sh (SessionStart context), fleet-glyph.sh, renew-check.sh | judge-run.sh `--apply` (launchd `com.harbor.judge`) | Its `crit` lines go into every new session's context with their repair text (session-verdicts.sh:136-148). Writable, a session hides a crit or plants an instruction for the next session. |
| `.helm-log-token` | `<cfg>/.helm-log-token` | integrity | worklog-push.sh, idea.sh | save-log-token.sh, by the operator | The work-log push credential. |
| `.helm-obs-host` | `<cfg>/.helm-obs-host` | integrity | `floor_log_decision` in guard-lib.sh (every guard), failure-observe.sh | floor-observe.sh (SessionStart hook) | It names the guard-decision ledger's partition. A forged value sends every guard's record to a partition that does not exist, so the ledger is blind until the next SessionStart (guard-lib.sh:663-676). |
| `.helm-obs-salt` | `<cfg>/.helm-obs-salt` | integrity | `floor_obs_digest` in guard-lib.sh (every guard's block path), deny-hash.sh | floor-observe.sh (SessionStart hook) | Rewriting it un-links every recorded digest from its subject (floor-observe.sh:160-163). |
| `.helm-peers` | `<cfg>/.helm-peers/<session_id>` | integrity | fleet-sessions.sh `--peers`, rendered into SessionStart context by context-resolve.sh; fleet-glyph.sh; harbor-clean.sh | context-resolve.sh (SessionStart and PostToolUse hook) | It is rendered into another session's system context (harbor#75). |
| `.helm-pins` | `<cfg>/.helm-pins/` | integrity | guard-integrity.sh (B6) | floor-install.sh and runtime-install.sh | The per-guard content pins that notice a gutted guard. |
| `.helm-props` | `<cfg>/.helm-props` | cache | fleet-glyph.sh and dashboard-gen.sh (statusline) | renew-check.sh, from the fleet-snapshot job | A count on the statusline, rewritten at every refresh. |
| `.helm-renew` | `<cfg>/.helm-renew` | cache | fleet-glyph.sh and dashboard-gen.sh (statusline) | renew-check.sh, from the fleet-snapshot job | A count on the statusline, rewritten at every refresh. |
| `.helm-replay` | `<cfg>/.helm-replay/` | cache | replay.sh, and pass-score.sh, which prints it beside the MAD gate and never in it (pass-score.sh:129) | replay.sh `--baseline` and `--labels`, run by a person or a session | A measurement a session is meant to build. |
| `.helm-sandbox` | `<cfg>/.helm-sandbox`, in a sandbox dir | cache | none in `bin/` | sandbox-make.sh | A marker in a throwaway dir. Nothing trusts it. |
| `.helm-snapshots` | `<cfg>/.helm-snapshots` | integrity | restore.sh (harbor#769) | deploy.sh | Writable, a session records a snapshot it forged. |
| `.helm-stop-gate` | `<cfg>/.helm-stop-gate/<session_id>` | integrity | guard-stop.sh (the Stop gate) | guard-stop.sh (Stop hook) | A key in the file means "already said" (guard-stop.sh:290-293). A session that writes its own key silences SG-1, SG-2 and SG-3 before they fire. |
| `.helm-suite-payloads` | `<cfg>/bin/.helm-suite-payloads` | integrity | failure-capture.sh (the judge's suite manifest) | runtime-install.sh | Anyone who can append to it can delete a finding from the judge (failure-capture.sh:700). It sits under `bin/`, so the `bin/` arm of all three layers covers it. |
| `.helm-sweep` | `<cfg>/.helm-sweep` | cache | fleet-glyph.sh (statusline) and harbor-clean.sh `--if-due` | harbor-clean.sh `--record` | A count on the statusline, rewritten at each record. |
| `.helm-sweep-keep` | `<cfg>/.helm-sweep-keep` | cache | harbor-clean.sh | the housekeeping skill, from a session, on the operator's "keep" (skills/housekeeping/SKILL.md:38) | A session writes it by design. |
| `.helm-sweep.jsonl` | `<cfg>/.helm-sweep.jsonl` | cache | the housekeeping skill | harbor-clean.sh `--record` | Rows for a person, rebuilt at each record. |
| `.helm-sweep.lock` | `<cfg>/.helm-sweep.lock/` | cache | harbor-clean.sh `--record` | harbor-clean.sh `--record` | A lock. One older than 30 minutes is broken. |
| `.helm-watch` | `<cfg>/.helm-watch` | cache | fleet-glyph.sh and dashboard-gen.sh (statusline) | fleet-snapshot-refresh.sh | A count on the statusline, rewritten at every refresh. |
| `.helm-backfill` | `<repo>/.agents/config.yaml.helm-backfill.<pid>` | scratch | marker-backfill.sh | marker-backfill.sh | A temp sibling, renamed over a repo's config. |
| `.helm-cm1` | `$TMPDIR/.helm-cm1.<pid>` | scratch | lint-conventions.sh CM1 | lint-conventions.sh | A lint temp file. |
| `.helm-cm2fm` | `$TMPDIR/.helm-cm2fm.<pid>` | scratch | lint-conventions.sh CM2 | lint-conventions.sh | A lint temp file. |
| `.helm-cm2g` | `$TMPDIR/.helm-cm2g.<pid>` | scratch | lint-conventions.sh CM2 | lint-conventions.sh | A lint temp file. |
| `.helm-cm2i` | `$TMPDIR/.helm-cm2i.<pid>` | scratch | lint-conventions.sh CM2 | lint-conventions.sh | A lint temp file. |
| `.helm-f11` | `$TMPDIR/.helm-f11.<pid>` | scratch | lint-conventions.sh F11 | lint-conventions.sh | A lint temp file. |
| `.helm-harbor-state` | none | scratch | port-paths.sh's self-test | none | A test string, never a file. |
| `.helm-peers-line` | `$TMPDIR/.helm-peers-line.<pid>` | scratch | fleet-sessions.sh | fleet-sessions.sh | A temp file. |
| `.helm-x7-payload` | `$TMPDIR/.helm-x7-payload.<pid>` | scratch | lint-conventions.sh X7 | lint-conventions.sh | A lint temp file. |

## Tools a session runs that write an integrity file

guard-bash reads the command text. A script's own write is not in that text, so
these pass by design, as harbor#114 records for every program the floor runs:

- `judge-run.sh --live --apply` writes `.helm-judge`. The verdict comes from the
  judge's own run.
- `install-stamp.sh --write` writes `.helm-install-stamp`, through the installers.
  It records the checkout's `HEAD`.
- `govern-token.sh --init --live` writes `.helm-govern-salt` only when the file is
  absent, and it writes random bytes.
- `pin-instructions.sh --apply --live` writes `.helm-instructions.sha256`.
- `event-dispatch.sh on` and `dispatch` write `.helm-dispatch`. guard-bash refuses both verbs by argv
  (`event-dispatch-operator`), and the script refuses them itself when `CLAUDECODE` is set, which covers
  a script a session wrote that runs it (harbor#1044).

The residual is harbor#114's: a session can edit the repo copy of one of these
scripts and then run it. None of them was reclassified. Each file keeps its reader's
trust, and the refusal covers every write the guards can see.

## What this table does not decide

- **Reads.** Every class stays readable. `.helm-obs-salt` and `.helm-log-token` also
  carry a B1 `Read()` deny, which predates this table.
- **`touch`.** guard-bash models no `touch` on any surface, `settings.json`
  included, so a `touch` of an integrity file is allowed. That is harbor#794.
- **`backups/`** is a directory of snapshots, not a `.helm-*` file. guard-bash
  refuses writes into it (harbor#772) and guard-selfedit does too (harbor#787).
