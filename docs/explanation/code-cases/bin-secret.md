---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/secret

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/secret, lines 3-5 (before this edit)

```text
SEC-0 · was UNTRACKED in ~/.local/bin until 2026-09-09 and is now here so it
has history, review and a backup. SEC-0 is a classification chosen to satisfy
lint S3 -- there is no issue behind this file, and it is credential-store tooling, which is what SEC-0 covers.
```

## bin/secret, lines 6-37 (before this edit)

```text

WHY IT EXISTS. Measured 2026-09-02: `~/secrets/` held `tracker.txt` (63 bytes)
and `gcp_mcp.json` (534 bytes) in plaintext, mode 0644, readable by any process
running as this user. The tracker one was REDUNDANT — `cu whoami` answers from
the Keychain, so the file was a second copy of a secret already stored properly.
The convention existed only as habit: `cu` and `stape` each read their own key
from the Keychain INSIDE THEIR OWN FILE, and a session that acquires some other
credential has nowhere to put it, so it writes a file. This is the somewhere.

THE SHAPE THE HOUSE PATTERN DID NOT COVER. `cu` and `stape` read a STRING. A
service-account JSON is a FILE — `gcloud --key-file`, an MCP server's config,
anything that wants a PATH cannot take a Keychain item. That gap is the whole
reason `gcp_mcp.json` was on disk, and `withfile` is the answer to it: the bytes
live in the Keychain and are materialised to a 0600 temp path only for the
lifetime of one command.

THERE IS DELIBERATELY NO `get` VERB, AND THAT IS THE MOST IMPORTANT LINE HERE.
The floor's egress guard blocks `security find-generic-password … -w|-g` in a
session Bash call, specifically to keep Keychain secrets out of a transcript
(harbor#310 — it under-matched `-g` for a while and was fixed). A `secret get`
would be a clean bypass of that control under a name the guard does not know:
same disclosure, no rule in the way. So no verb here prints a secret. `run`
injects it as an environment variable and `withfile` as a file; both hand it to
a child process, neither to stdout. CONSTITUTION: never "fix" a failure by
weakening a gate — and never build a new door beside one.

WHAT IT DOES NOT CLAIM. macOS has no tmpfs, so `withfile` writes plaintext to
the per-user TMPDIR for the duration of the command; it is mode 0600 and removed
on every exit path including a trap, but it touches a disk. And on APFS,
overwriting a file does not overwrite its blocks — `adopt` therefore reports
that the ONLY complete remedy for a secret that sat in plaintext is ROTATION,
and does not pretend a delete is one.
```

## bin/secret, lines 51-52 (before this edit)

```text
Ciphertext for anything too large for the Keychain — see THE 128-CHARACTER
CEILING below. Nothing in here is readable without the matching Keychain item.
```

## bin/secret, lines 61-73 (before this edit)

```text
THERE IS NO ALTERNATE-KEYCHAIN OPTION, AND THE REASON IS A MEASURED CONFLICT.
An early version took SECRET_KEYCHAIN so the suite could run against a
throwaway keychain. It cannot work: `security` takes the keychain as a TRAILING
OPERAND, and `-w` takes an OPTIONAL VALUE, so `… -w "$KEYCHAIN"` parses the
keychain path AS THE PASSWORD and writes to the login keychain anyway — measured
2026-09-02, and it silently planted two junk items before the suite caught it.
Operand-first (`security add-generic-password "$KC" … -w`) is rejected outright,
exit 2. So a stdin-fed `-w` and an explicit keychain are mutually exclusive.

Given that choice, the no-argv property wins and the test convenience goes: a
secret in argv is visible to `ps` for every user on the box, which is the whole
thing this tool exists to prevent. The suite therefore runs against the login
keychain under a `zz-selftest-` prefix and deletes what it makes.
```

## bin/secret, lines 77-79 (before this edit)

```text
The name becomes a Keychain service string. Constraining it keeps a caller from
steering the lookup at some OTHER service's item — the namespacing concern
cu.sh records for CU_TOKEN, one layer earlier.
```

## bin/secret, lines 88-93 (before this edit)

```text
THE REGISTER GATE (harbor#1205). A name is a reference into the access register, and a ref the register does
not name is refused: an agent cannot mint a credential nobody recorded, or read one it was never granted.
`access.sh has` is the one reader of the register: 0 is registered, 3 is a ref still served from
contracts/secret-legacy-refs.txt until its consumer is migrated (that list only goes down), else refused.
It fails CLOSED: no access.sh beside this file, or any error from it, is a refusal.
`rm` and `list` are not gated: removing a stale item or listing names grants nothing.
```

## bin/secret, lines 110-122 (before this edit)

```text
Everything is stored BASE64-ENCODED, strings and files alike, for two reasons
that both bit something on this box already:

  · a NEWLINE in a stored value. cu.sh carries the incident: a token containing
    a newline was interpolated into curl's config file, where the newline ended
    the `header =` directive and started a `url =` one — the credential sent to
    a host of the attacker's choosing. Base64 has no newlines, so a value cannot
    carry a line break into whatever consumes it.
  · BINARY BYTES. A .p12 or a DER key is not text; `-w` round-trips it wrong.

One encoding for both shapes means there is no "kind" flag to read back, and
therefore no way for the read side to disagree with the write side about what a
given item is.
```

## bin/secret, lines 127-176 (before this edit)

```text
-T "" removes the default trust that would let the CREATING application read
the item without warning, so EVERY read raises the login-password prompt. Read
from `security add-generic-password -h` on this box.

IT IS NOT THE DEFAULT HERE, AND THAT IS A JUDGEMENT, NOT AN OVERSIGHT. `cu`
reads its token non-interactively on every call; making that prompt turns a
working CLI into one nobody uses, which is CONSTITUTION §2.11 — a guard that
blocks ordinary work gets switched off, and a disabled guard protects nothing.
Locked is right for a credential used a few times a month by a human present at
the keyboard; unlocked is right for a daily driver. The caller says which.
── THE PROMPT IS UNUSABLE, AND THAT DECIDES THE WHOLE DESIGN ────────────────
MEASURED 2026-09-02, twice, and the second measurement overturned the first.

FIRST: a value fed to `security … -w` ON STDIN is truncated at 128 characters —
128 round-trips, 132 does not. That looked like the constraint, and the tool was
built around it: small values inline, larger ones encrypted to a blob.

THEN IT FAILED ON A REAL FILE IN THE OPERATOR'S TERMINAL while passing 25/25
here, and the reason is worse than a size limit. `security … -w` uses
readpassphrase(), WHICH OPENS /dev/tty. With a controlling terminal it ignores
the pipe entirely and reads the terminal — so under a pty the call HANGS
waiting for a human, and whatever sat in the input buffer becomes the stored
password. The operator's Keychain ended up holding 15 characters of unrelated
text where 51 were sent.

EVERY TEST HERE RAN WITHOUT A TTY, so the pipe was read and everything passed.
The suite could not have caught this: it was measuring a different code path
from the one a human uses. That is the endogenous-instrument trap — a check
that reads the tool's own output under the tool's own conditions proves
consistency, never correctness.

SO THE PROMPT IS OUT, and the Keychain write goes through ARGV, which behaves
identically with and without a terminal. Argv is readable via `ps`, so THE RULE
IS THAT A SECRET NEVER GOES THERE: everything is encrypted to a blob under
$BLOBDIR, and the only thing argv ever carries is a freshly generated 44-char
passphrase for a local file. There is no inline mode any more — inline would
mean the secret itself in argv, which is the one thing this must not do.

  v1:enc:<passphrase>    the passphrase; ciphertext at $BLOBDIR/<name>.enc
  v1:b64:<payload>       READ-ONLY legacy, from before the tty finding

-T "" removes the default trust that would let the CREATING application read
the item without warning, so EVERY read raises the login-password prompt. Read
from `security add-generic-password -h` on this box.

IT IS NOT THE DEFAULT, AND THAT IS A JUDGEMENT. `cu` reads its token
non-interactively on every call; making that prompt turns a working CLI into
one nobody uses — §2.11, a guard that blocks ordinary work gets switched off,
and a disabled guard protects nothing. Locked suits a credential a human
reaches for monthly; unlocked suits a daily driver. The caller says which.
```

## bin/secret, lines 180-183 (before this edit)

```text
THE VALUE IS IN ARGV, DELIBERATELY, AND ONLY EVER A GENERATED PASSPHRASE.
See THE PROMPT IS UNUSABLE above: the stdin route silently stores whatever is
in the terminal buffer. Argv is the only spelling that behaves the same with
and without a controlling terminal, so it is the only one that can be tested.
```

## bin/secret, lines 196-209 (before this edit)

```text
CHECK WHAT THE KEYCHAIN ACTUALLY TOOK, here, at the write — not only end to
end in store(). A 2026-09-02 failure on a real file reported "pre-v1 format",
which means this write had stored something that was neither what it was
given nor nothing at all, and the end-to-end check could not say which. It was
not reproducible afterwards because the diagnosis needs the item as written
and the failing run had already been cleaned up.

The mismatch message reports SHAPE ONLY — lengths and the leading marker —
because a secret must not reach a terminal, a scrollback or a bug report. That
is the same reason there is no `get` verb.
RETURNS non-zero rather than calling die, so the CALLER can clean up. When
this exited directly it stranded store()'s half-written `<name>.enc.new.$$`
temp blob — two of them were found on disk after the tty failures, each a
complete ciphertext whose passphrase never reached the Keychain.
```

## bin/secret, lines 231-234 (before this edit)

```text
THE PASSPHRASE REACHES openssl THROUGH A FIFO — not argv, and not a file. A
named pipe satisfies `-pass file:` without the passphrase ever touching a block
device, which matters here precisely because the CIPHERTEXT is on one: a
snapshot that caught both at the same instant would hold everything needed.
```

## bin/secret, lines 266-268 (before this edit)

```text
ONE PATH, ALWAYS. No size branch: a small secret stored inline would be a
secret in argv, and the whole point of the redesign is that argv only ever
carries a generated passphrase.
```

## bin/secret, lines 279-283 (before this edit)

```text
VERIFY END TO END, through the same read path a caller will use. `security`
returning 0 does not mean the item holds what we sent — the truncation above
is exactly that failure — and `adopt` DELETES a plaintext original on the
strength of this. So the check lives with the write, not in one verb that
remembered to do it.
```

## bin/secret, lines 288-290 (before this edit)

```text
The ONE read. Every verb that needs plaintext comes through here, so there is a
single place where a secret enters this process — and it is a function whose
result is never printed, only passed to a child.
```

## bin/secret, lines 293-300 (before this edit)

```text
THE LOOKUP IS CAPTURED BEFORE IT IS DECODED, and that is not style. Written as
a pipeline — `security … | unb64 || die` — the `||` tests the exit status of
the LAST stage, and `base64 -D` on empty input succeeds. So a MISSING secret
decoded to nothing and returned 0: `run` then exec'd the child with the
variable set to the empty string, and a caller that reasonably treats "the
command ran" as "the credential was there" would authenticate as nobody and
read the failure as something else entirely. Caught by the suite's
"a removed secret is gone" case, which is the whole reason it is in there.
```

## bin/secret, lines 307-310 (before this edit)

```text
A blob-backed name whose blob is gone FAILS. It does not fall back to
treating the passphrase as the secret, which is what an inferred mode
would do here — and that would hand a caller 44 characters of random
base64 as though it were their credential.
```

## bin/secret, lines 316-318 (before this edit)

```text
v0: written before the mode marker existed — bare base64, inline only.
Read, but say so, because it cannot have been larger than the ceiling and
the next write of this name will move it to v1 silently.
```

## bin/secret, lines 371-372 (before this edit)

```text
Piped input is taken VERBATIM, trailing newline and all, because a piped
secret is usually a file's contents and trimming it would corrupt a key.
```

## bin/secret, lines 391-394 (before this edit)

```text
The migration verb. Store, then PROVE the stored copy matches the original
byte for byte BEFORE deleting anything — a migration that deletes on the
strength of "the write returned 0" is how a credential is lost, and the
comparison is on hashes so neither copy is printed.
```

## bin/secret, lines 421-426 (before this edit)

```text
The migration for a tool that read its own raw item before it went through `run` (stape,
stape-write, meta: harbor#618). The value moves between two store items inside this process
and never reaches a terminal; the old item is left for the operator to remove. Read as `$(...)`
the old tools did, so a trailing newline is stripped exactly as they stripped it.
It REFUSES to replace a name that already holds a secret: the old raw item is usually the
revoked one, and a rotated key must not be overwritten by it with no way back (harbor#1112).
```

## bin/secret, lines 442-447 (before this edit)

```text
Names only. dump-keychain would print values and is blocked by the egress
floor anyway; this greps the service labels out of the item metadata.
A keychain that cannot be read is exit 1, never an empty list: `harbor access stored|status` would read
an empty list as "nothing stored", and the pipe below ends in `while`, which always exits 0.
macOS only: on libsecret an unreachable Secret Service still lists empty (not yet measured on Linux).
Held in a variable, never a file: attributes only, but they still name every item.
```

## bin/secret, lines 477-479 (before this edit)

```text
The blob goes with it. Left behind it is unreadable ciphertext for a
passphrase that no longer exists — harmless, but it accumulates, and a
later `put` of the same name would find a stale file where it expects none.
```

## bin/secret, lines 486-492 (before this edit)

```text
Replace a value and keep it only if <cmd> passes against it (harbor access rotate, harbor#1205).
The old value is held for the length of one probe, as base64 (newline-safe) in this process, and
put back THROUGH store() - never a raw item through kc_write, whose -w would put a legacy item's
plaintext in argv. A sha256 proves the put-back. The probe gets no stdin and its output is
discarded: a failing CLI may print the credential it was handed. Exit 0 kept, 1 put back
(or removed, when there was nothing readable before), 4 the put-back itself failed, 5 the new value
could not be stored (store() dies after it may have half-written, so the old value is put back too).
```

## bin/secret, lines 585-586 (before this edit)

```text
A private directory, not just a private file: mktemp -d gives 0700, so the
materialised credential is unreachable even for a moment by another user.
```

## bin/secret, lines 588-590 (before this edit)

```text
The trap fires on ordinary exit AND on the signals a Ctrl-C or a killed
parent sends. Without INT/TERM/HUP a interrupted command leaves the
plaintext behind, which is the exact failure this verb exists to avoid.
```
