# Minting a credential from an OAuth code

**Seam:** core ships the exchange (`harbor access mint`, `bin/access-mint.sh`) and these two formats; the rows are private
data in the access register's folder (`sh bin/scope-roots.sh --access`), because which vendors a company uses and which apps
it owns are workload and company knowledge, never core (harbor#1273, `lint.domain`). harbor#978.

`harbor access mint <provider> <code>` (or `-` to read the code from stdin) posts the one-time code to the vendor's token
endpoint and stores the credential that comes back through the [access register](./access-register.md): `harbor access add`
for a new entry, `harbor access rotate` for one that exists (which keeps the new value only when the entry's `check:` passes).

## What it never does

- Put the app secret, the code or the credential on an argv or in a URL. The secret comes from `bin/secret withfile` as a
  0600 file; curl reads its header and its body from 0600 files in a 0700 folder; the credential reaches the register on a pipe.
- Print the credential, or the response body. It prints the row's `report` line and `list` lines, and refuses either when it
  holds the stored value.
- Run against a vendor it has no row for, or a token URL that is not `https`.

## `mint-vendors.tsv`: the vendor's protocol

Tab-separated, a header row first, one row per vendor.

| Column | Meaning |
|---|---|
| `id` | the provider, as `harbor access mint <id>` names it |
| `token_url` | the token endpoint, `https` only |
| `client_auth` | `basic`: the app id and secret go as `Authorization: Basic`; `body`: they go in the body under `id_field` and `secret_field` |
| `body` | `json`, or `form` (url-encoded) |
| `id_field`, `secret_field` | the body keys of the app id and secret when `client_auth` is `body`, else `-` |
| `code_field` | the body key of the one-time code |
| `fields` | fixed body fields, `key=value` joined by `&`; `{redirect}` stands for the app row's redirect URI; `-` for none |
| `store` | the jq path of the response value that is stored |
| `ok` | a jq test, true when the exchange worked |
| `report` | a jq string printed after the exchange: counts, scopes and expiries |
| `list` | a jq expression whose lines are printed as what the credential reaches, or `-` |
| `note` | the vendor's documentation of the exchange |

## `mint.tsv`: the company's app

Tab-separated, a header row first, one row per provider.

| Column | Meaning |
|---|---|
| `provider` | a row of `mint-vendors.tsv` |
| `client_id` | the app id on the vendor, `[A-Za-z0-9._-]` (not a secret) |
| `secret_ref` | the `bin/secret` ref holding the app secret; its entry is in the register like any other |
| `redirect` | the redirect URI registered on the app (`https`, or loopback `http`), or `-` |
| `entry` | the register entry the credential becomes |
| `kind`, `secret`, `vendor_name` | that entry's fields (`vendor_name` `-` for none) |
| `what`, `use_when`, `reaches`, `cannot`, `grant` | that entry's fields, used when the entry is new |

## Example

A vendor whose endpoint takes a JSON body with the app's credentials in it:

```
id	token_url	client_auth	body	id_field	secret_field	code_field	fields	store	ok	report	list	note
acme	https://api.example.com/oauth/token	body	json	app_id	secret	auth_code	-	.data.access_token	.code == 0	"code=\(.code)"	-	the vendor's docs
```
