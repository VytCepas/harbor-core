# access-get — one read-only GET to a vendor API

`harbor access get <vendor> <path> [--query k=v ...]` (`bin/access-get.sh`, harbor#1617) issues one HTTPS GET to a
vendor API with the one credential the vendor table binds to that vendor, and prints the JSON body, redacted. It
replaces the hand-copied per-vendor read wrapper: a new vendor is a table row, not a file.

## What it cannot do

- **No method, header, body or URL argument.** After `<vendor> <path>` only `--query k=v` is accepted; anything else
  (`-X`, `--header`, `--data`, a second path, a URL) is refused before any request. curl runs under `env -i` with
  `-q` (no curlrc, `CURL_HOME`, proxy, CA bundle or key-log file from the caller), `--noproxy '*'`, the system CA
  store, no `-X`, no data, `--proto =https`, `--max-redirs 0` and `--path-as-is`. The token-endpoint leg is the same.
- **No environment variable moves it.** The search path is `/usr/bin:/bin`, the home is the account's passwd home (not
  `$HOME`), and `ACCESS_DIR`, `HARBOR_SCOPE_ROOT`, `HARBOR_SCOPE_PRIVATE`, `PORT_ROOT`, `HARBOR_ACCESS_REDACT_EGRESS`,
  the `XDG_*` homes, `PS4`, `ENV`, `BASH_ENV` and every curl, proxy and CA variable are dropped first. `harbor access
  get` starts it as `/bin/sh` by absolute path with that PATH, and every child shell starts without `SHELLOPTS`, `PS4`,
  `ENV` or `BASH_ENV`. Tests drive a copy with the two seam lines rewritten.
- **No trace prints a credential.** `set +xv` is the first command of `access.sh`, `access-get.sh` and
  `access-oauth.sh`, so `sh -x` and `SHELLOPTS=xtrace` trace nothing past it.
- **The base URL comes only from the table.** The path is appended to the row's base URL.
- **Paths are default-deny.** A path must start with one of the row's allowed prefixes and match none of its denied
  globs. Refused anywhere in it: `..`, a `.` segment, whitespace, quotes, a backtick, `$ ; | < > &`, `#`, `?`, `//`,
  and any byte outside `[A-Za-z0-9._~/:@=+,-]` (so `%` too). A query goes only through `--query`: the key is
  `[A-Za-z0-9_.-]`, never one that names a credential (`access_token`, `key`, `secret` …), and the value is printable
  ASCII with no space, at most 1024 characters, percent-encoded by the tool.
- **The credential is never in argv, a URL, an environment, stdout, stderr or any file.** It always comes from
  `bin/secret run`, whose child (`access-get.sh --emit`) unsets it and writes it to its stdout, which is the parent's
  command substitution: a pipe. From there it is an unexported shell variable, and reaches curl only as a config line
  on stdin (`-K -`). A refresh-token row is exchanged first by `access-oauth.sh --exchange` (`OA_GRANT=refresh_token`,
  `OA_RESP=-`), the token-endpoint client the OAuth intake already uses: the client secret and refresh token go in on
  its stdin and the token response comes back on its stdout. The vendor's unredacted answer is a shell variable too,
  never a file, and no temp dir is made at all.
- **The output is redacted.** A key is compared lower case with `- _ .` and space removed: one containing `token`,
  `secret`, `password`, `passwd`, `privatekey`, `apikey`, `accesskey`, `secretkey`, `authorization`, `cookie`,
  `session`, `credential` or `signature`, one that is exactly `key`, `pass`, `pwd`, `pin`, `sig`, `auth`, `bearer`,
  `otp` or `code`, or one the row's redact regex names has its value replaced by `[withheld N chars]` (a number by
  `[withheld number]`). So is the `value`, `val` or `content` (any case) of an object whose `name`, `key`, `field`,
  `type`, `label`, `param`, `parameter` or `header` (any case) is such a key, the second element of a two-element array
  whose first is one, any JWT-shaped string and any string that starts `Bearer `, `Basic `, `Digest ` or `Token `. One
  number is kept: one directly under a key that normalises to exactly `code`, so a vendor's numeric status
  `"code": 0` prints. The result then passes `access-redact.sh` (provider token shapes). A body that is not JSON is
  not printed; a 401 or 403 is named by its status first, JSON body or not.
- **A rotated refresh token is not stored.** On a refresh row the token response's new `refresh_token`, if the
  vendor sends one, is dropped: this tool reads and has no write path to the store. A vendor that rotates refresh
  tokens on every use needs `harbor access` re-intake when the stored one stops working.
- **A `--query` key that names a credential is refused**, normalised as above: `access-token`, `x-api-key` and
  `accessToken` are refused as `access_token` is. The names are exact, so a pagination key such as `pageToken`
  passes.

Exit: 0 a 2xx; 1 the request failed or was not 2xx (the redacted body is still printed); 2 refused before any
request; 3 the redactor withheld the output.

## The table

Private data, read from one place only: `~/.claude/access/get.tsv` under the account's passwd home, a path in the
config dir that no confined command can write (the write zone is `contracts/confinement-paths.txt`). It is deployed from
the private layer's own pack: commit it as `harbor-private/harbor-pack/access/get.tsv`, then run, from a terminal,
`sh bin/deploy.sh --only packs --apply --live` (`bin/pack.sh` installs `access/get.tsv` from that pack only, and refuses
it in any other). The private checkout itself is never read, since an agent can write it and a changed row there could
send a ref to another host. Core ships the reader
and a fixture (`tests/access/get/get.tsv`), never real rows. One row per vendor, tab-separated, ten columns; `#`
lines, blank lines and a header row starting `vendor` are skipped. `-` means none.

| # | Column | Holds |
|---|---|---|
| 1 | `vendor` | `[a-z0-9-]`, unique in the table |
| 2 | `secret` | the one registered secret ref this vendor uses: the API token, or the refresh token when column 8 is set. Every ref, in this column or column 10, is named once in the whole table |
| 3 | `base` | `https://<host>/<path>/`, ending in `/`; no port, no userinfo |
| 4 | `auth` | `bearer` (`Authorization: Bearer <token>`) or `header:<Name>` (`<Name>: <token>`) |
| 5 | `allow` | comma-separated literal path prefixes, relative to `base`; at least one |
| 6 | `deny` | comma-separated shell globs a path may not match (a GET that returns a credential, a transfer code, personal data) |
| 7 | `redact` | a jq regex of JSON keys to withhold, on top of the floor |
| 8 | `token_url` | for a refresh-token row: the https token endpoint; else `-` |
| 9 | `client_id` | the app's public client id (refresh rows); else `-` |
| 10 | `client_ref` | the registered ref of the app's client secret (refresh rows); else `-`. Client authentication is HTTP basic |

A refresh-token row reads two refs, the token's and the client secret's, both named in the row and nowhere else; the
caller can name neither.

**Not a boundary against `secret run` itself, nor for the register.** A process that can run `secret run <ref> VAR --
<anything>` holds the value without this tool; what stops that reaching a foreign host is the egress guard and the
sandbox's network list. The register `bin/secret` checks (`harbor-private/access/register.md`) is in the agent-writable
private checkout, and protecting it is `secret run`'s own pre-existing boundary, not this tool's. This tool's job is
that its own path never launders a credential to a host the deployed table does not name.

A vendor whose token is minted by a POST other than a refresh-token grant (client
credentials, say) cannot be a row today.

## Example

```
vendor	secret	base	auth	allow	deny	redact	token_url	client_id	client_ref
example	example-api-read	https://api.example.com/v1/	header:Access-Token	user/,report/	*/token*	email|phone	-	-	-
```
