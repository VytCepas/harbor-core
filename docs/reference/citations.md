# CITATIONS — every external URL Harbor's own documents cite

Hand-maintained and machine-checked — **not** generated like
`docs/generated/status.md`, because the last column cannot be derived by a fetcher.
Check it with `sh bin/doc-cite-verify.sh` (needs network); lint rule **T7** does the
offline half and fails if a document cites an external URL that is not listed
here.

*This paragraph said "refresh with `sh bin/doc-cite-verify.sh --apply`" until
2026-07-30. That flag has never existed — the script reports and exits. A file
whose entire subject is citation honesty was citing a flag that was not there,
which is the failure it was written to prevent, one level up.*

Method taken from upstream `Research`'s `UrlVerificationProtocol`
([docs/reference/provenance.md](./provenance.md)). Its point is not link-rot — it is that
**agents hallucinate plausible URLs**, and that a URL returning 200 is not the
same fact as its content supporting the claim it was cited for. Both columns
below are therefore required, and the second one cannot be filled in by `curl`.

Fixture URLs (`evil.com`, `example.com`, `localhost`, `https://x`) are attack
payloads and template placeholders, not citations. T7 skips them by pattern.

**Hosts of clients, partners and the company itself are not listed here.** Their
rows live in the private layer's `citations.md` (same row shape,
[contracts/private-layer.md](../../contracts/private-layer.md)), which T7 reads
beside this file. With no private layer (the public export, a runner that
mounts none) T7 reads only this file, so a tracked file that still names one of
those hosts is red there: take the host out of the file first, then move its row.

**The verifier is part of the fact.** `harbor` is a **private** repo, so an
anonymous `curl` returns **404** for its own issue URLs while `gh` returns them
fine. The first run of `doc-cite-verify.sh` reported three live citations as broken
for exactly that reason. *"404 to an anonymous fetcher"* and *"does not exist"*
are different facts, and the `via` column records which one was answered.

| URL | HTTP | via | Verified | Cited for — and whether the content supports it |
|---|---|---|---|---|
| `https://raw.githubusercontent.com/danielmiessler/fabric/main/LICENSE` | 200 | curl | 2026-10-15 | The upstream Fabric licence. Supports: MIT, with the copyright line as upstream carries it, copied to `vendor/skills/fabric/LICENSE-fabric`; GitHub's licence API also reports MIT. |
| `https://github.com/VytCepas/project-init/pull/902` | 200 | gh | 2026-07-26 | PI-901 — the `context: repo` emitter. Supports: the PR exists and carries the marker work described in `docs/reports/handover-archive.md` § Workstream H. |
| `https://github.com/gitleaks/gitleaks/releases/download/v8.18.4/gitleaks_8.18.4_linux_x64.tar.gz` | 206 (range request, after 1 redirect) | curl | 2026-09-24 | The gitleaks v8.18.4 Linux release that the floor jobs' hosted-runner step downloads. Cited only because `patches/admission-shard.patch.md` quotes that workflow step verbatim. Supports: the release asset exists at this URL. No Harbor claim depends on its content. |
| `https://github.com/VytCepas/project-init/pull/904` | 200 | gh | 2026-07-26 | PI-903 — symlinked-marker refusal (M13). Supports: the PR exists and carries the `_find_config` change. |
| `https://github.com/VytCepas/harbor/issues/41` | 200 | gh | 2026-07-26 | OBSERVE-1, guard-decision telemetry. Supports: the issue exists and specifies the redaction-by-construction and fail-open requirements cited in workstream L. |
| `https://github.com/VytCepas/harbor/issues/42` | 200 | gh | 2026-07-26 | CLI-1, the `harbor` command. Supports: the issue exists and carries the verb table and the not-a-launcher finding. |
| `https://github.com/VytCepas/harbor/issues/43` | 200 | gh | 2026-07-26 | C1a, TELOS + identity. Supports: the issue exists and records that `vendor/skills/telos` reads three paths that do not exist. |
| `https://github.com/VytCepas/harbor/issues/44` | 200 | gh | 2026-07-26 | Workstream M, the UPSTREAM/TOOLS takes. Supports: the issue exists and carries the dependency order and the skip accounting. |
| `https://github.com/VytCepas/harbor/issues/57` | 200 | gh | 2026-07-31 | The credential boundary. Supports: the issue exists and carries the operator decision (no agent changes an IAM binding or a tag-container publish permission), the shared-identity reasoning, the three measured `prod_guard` gaps, and the four human checklist items that `docs/explanation/credential-boundary.md` records rather than restates. |
| `https://mcp.facebook.com/ads` | 405 | curl | 2026-08-13 | Meta's hosted Ads MCP server, cited by `skills/reporting-apis` for the derivation rule and the all-or-nothing grant. **405 is the verification**: the endpoint exists and refuses `GET`; a `POST` carrying an MCP `initialize` returns `401 Authentication Required`, and `GET /.well-known/oauth-protected-resource/ads` returns `200` with the seven-scope list the skill quotes. The 100× defect and the panel behaviour are measured against a live account, not fetched from this URL. |
| `https://developers.facebook.com/support/bugs` | 200 | curl | 2026-08-13 | Meta's Platform Bug Report tool, cited by `skills/reporting-apis` as the only destination for a defect in the hosted connector — there is no repository to file against. Supports ONLY that the tool exists and is reachable; whether Marketing API is a selectable category, and whether a report stays private, is **unverified from outside the login** and the skill says so. |

## Hosts named without a scheme — added 2026-08-02 (harbor#82)

T7 read only `https?://`, so a source written as a bare hostname was invisible
to it and nothing ever asked whether it had been read. The rule now extracts
bare hosts too, and these are the eight it found on its first run. Every one was
fetched on 2026-08-02.

**Several of these are not sources.** They are hosts a document *names* — a
tracking endpoint a skill describes, the mail domain an identity belongs
to. The row says so rather than implying a reading that never happened, which is
the distinction the last column exists for. Recording them is what makes the
next unlisted hostname visible.

| URL | HTTP | via | Verified | Cited for — and whether the content supports it |
|---|---|---|---|---|
| `https://code.claude.com/docs/en/memory.md` | 200 | curl | 2026-08-02 | Claude Code's memory documentation, named in `trio-decoupling-epic.md`. Supports: the page exists. It is cited as background for the memory-layout discussion, and no claim in that document rests on its contents. |
| `https://code.claude.com/docs/en/hooks` | 200 | curl | 2026-10-10 | Claude Code's hooks reference. Supports: the SubagentStart and SubagentStop input fields and outputs quoted in `contracts/subagent.md` (read in full for those two sections: SubagentStart has `agent_id` and `agent_type` only; SubagentStop adds `stop_hook_active`, `agent_transcript_path`, `last_assistant_message`, `background_tasks`, `session_crons`, and `background_tasks` is parent-scoped). |
| `https://admin.shopify.com` | 403 | curl | 2026-08-06 | The Shopify admin console, named in a measurement skill as the surface **nothing on this box reaches**. **403 to an anonymous fetcher is the verification**, not a failure: the host routed the request and refused it without a session, which is exactly the fact being cited. The stronger claim in the skill — that it lands on the login page — was checked in the paired Chrome on 2026-08-05 and does **not** rest on this fetch. |
| `https://docs.cloud.google.com/iam/docs/downscoping-short-lived-credentials` | 200 | curl | 2026-08-16 | Google's IAM reference for Credential Access Boundaries, cited in [docs/explanation/credential-boundary.md](../explanation/credential-boundary.md) as the reason the downscoped-token route (harbor#194 item 5) is **closed for the warehouse**. Supports the claim directly and categorically — the page states *"Credential Access Boundaries are only available for Cloud Storage. Other Google Cloud services don't support this feature."* **Read for this claim, not merely reachable**, and the paragraph citing it says plainly that it was read rather than probed: minting credentials to measure a limitation the vendor states outright is cost without an answer. `cloud.google.com/iam/docs/...` 301s here, so the redirect target is what is cited. |
| `https://claude.ai/code/artifact/859e73aa-fb35-4fb4-95cd-21c38de65f23` | — | not fetched | 2026-08-21 | The de-identified enforcement diagram produced alongside the Meta MCP review, linked from `skills/reporting-apis/references/meta-ads-mcp.md`. **Deliberately not fetched.** It is the operator's own private artifact behind an account session, so a status code from here would say only that an auth wall answered — which is not evidence about the artifact and would read in this column as if it were. The claim it is cited for is that the diagram exists and is shareable, and that rests on it having been produced, not on a probe. |
| `Windsor.ai` | — | bare hostname in prose | 2026-08-21 | A vendor **named** in `skills/reporting-apis/references/meta-ads-mcp.md` when recording that its connector is not read-only and therefore not a way around the write surface. No URL is cited and no claim rests on the site's contents — the finding came from the connector's own tool list. Recorded because T7 sees the hostname; **a product name, not a source.** |
| `business.facebook.com` | — | bare hostname in prose | 2026-08-21 | Meta's Business Manager console, named in the same file as the **UI path** where the MCP server's business binding is read (`/latest/settings/ads_mcp_server`). Reached in a browser session by the operator, never by a fetcher. **A surface, not a source.** |
| `claude.ai` | — | bare hostname in prose | 2026-08-21 | Named in `skills/reporting-apis` when distinguishing the claude.ai-managed connector from the CLI-managed one — the distinction that matters because a claude.ai-managed connector cannot be removed with `claude mcp remove`. That fact was measured on this box, not read from the site. **A surface, not a source.** |
| `mail.google.com` | 200 / 404 | **Chrome, signed in** | 2026-08-25 | The Gmail web UI, cited by `cu`'s contract (now in the private layer's pack, harbor#1273) for the permalink form `cu tpl --mail` renders. **Both outcomes are the citation**, and the plausible spelling is the broken one: `/mail/u/<email>/#all/<id>` returned *Temporary Error (404)*, while `/mail/?authuser=<email>#all/<id>` opened the intended thread and Gmail rewrote the address bar to its own `u/<n>/#all/FMfcgz…` permalink. Verified **in a signed-in browser against a real thread**, which is the only verifier that can answer this — an anonymous fetcher gets a login page for both forms and would have reported the broken form as fine. Supports the claim directly; the `u/0` warning rests on `authuser` being an ordinal, measured separately on this box. |

**Not verifiable by status code, and therefore not claimed:** that either PR is
merged, or that its diff still reads as described. Those are `gh pr view`
questions, and the GitHub issues plus `docs/reports/platform-build-tickets.md` are where they
are tracked — `docs/how-to/handover.md` was named here until 2026-08-03, when it was rotated
into a start-here brief that deliberately tracks nothing.
| `https://github.com/affaan-m/ecc` | 200 | gh | 2026-09-15 | "Everything Claude Code", the external harness surveyed by epic #481. Supports: the repo exists, is MIT, and is the source of every ECC citation under `EVALS-DATA/ecc-2026-09-07/`. It does NOT support any single quoted line — those were verified by reading the clone at `v2.2.1`, and the repo has since moved (pushed 2026-09-14), which is why children B and J carry a re-read instruction rather than a pinned quote. |
| `https://api.app.stape.io` | 404 | curl | 2026-09-15 | Stape's **global** API base, pinned in the operator's `~/.config/stape/config` and named in `harbor-private/access/stape.md` when recording that the EU endpoint is a separate account answering 401 to a valid key. **An endpoint, not a source** — a bare API base has nothing to serve, which is what the 404 says; no claim rests on its body. |
| `https://api.app.stape.io/api/doc` | 200 | curl | 2026-09-15 | The vendor's API documentation page, cited in `harbor-private/access/stape.md` for exactly one fact: the auth header is `X-AUTH-TOKEN`, which is absent from the prose docs. The card stamps that reading `[M] 2026-08-19`. **This row attests reachability today, not a re-read** — the content claim rests on the 08-19 reading recorded in the card. |
| `https://stape.io/helpdesk/knowledgebase/what-happens-if-the-container-reaches-the-monthly-request-limit-and-when-does-it-reset` | 200 | curl | 2026-09-15 | The vendor knowledge-base article cited in `harbor-private/access/stape.md` for the overlimit wording and the one-time 30-day grace on Business and Enterprise tiers. Read `[M] 2026-08-19` per the card's own stamp; **this row attests reachability, not a re-read of the thresholds.** |
| `https://stape.io/price` | 200 | curl | 2026-09-15 | The vendor's public pricing page, cited in `harbor-private/access/stape.md` for Enterprise at USD 167/month billed yearly, 20% off, 20M requests. Same `[M] 2026-08-19` provenance and the same limit: reachability here, content there. |
| `stape.io` | — | bare hostname in prose | 2026-09-15 | The vendor's apex, named throughout `harbor-private/access/stape.md`. The two pages actually cited from it have their own rows above. **A vendor name, not a source.** |
| `app.stape.io` | — | bare hostname in prose | 2026-09-15 | Stape's console host, named in `harbor-private/access/stape.md` as the browser surface beside the CLI. **A surface, not a source.** |
| `secretmanager.googleapis.com` | — | bare hostname in prose | 2026-09-15 | Named in `harbor-private/access/meta.md` as the audit-log service whose `DATA_READ` entries answer "who read this secret". **An API name, not a source.** |
| `myaccount.google.com` | — | bare hostname in prose | 2026-09-15 | Google's account console, named in `harbor-private/access/meta.md` as the UI path checked directly on 2026-08-01 for linked apps. **A surface, not a source** — it was read in a browser by the operator, never by a fetcher. |
| `gmail.com` | — | bare hostname in prose | 2026-09-15 | A mail domain appearing in account names across `harbor-private/access/ACCOUNT-PRECEDENCE.md`, `harbor-private/access/<tool>.md`, `harbor-private/access/meta.md` and `skills/mail-cal`. **An identity, not a source.** |
| `appspot.com` | — | bare hostname in prose | 2026-09-15 | Named in `harbor-private/access/stape.md` in the hosting-fingerprint table, as the default App Engine domain one container's endpoint resolves to. **A hosting fingerprint, not a source** — read from DNS and response headers. |
| `run.app` | — | bare hostname in prose | 2026-09-15 | Google Cloud Run's domain, named in `harbor-private/access/stape.md` inside a quoted list of CNAME target shapes a server-side container may point at. **A domain shape, not a source.** |
| `googleusercontent.com` | — | bare hostname in prose | 2026-09-15 | Named in `harbor-private/access/stape.md` as the PTR suffix the Stape-hosted addresses reverse to. **A reverse-DNS observation, not a source.** |
| `your-server.de` | — | bare hostname in prose | 2026-09-15 | Hetzner's reverse-DNS domain, named in `harbor-private/access/stape.md`'s hosting-fingerprint table. **A reverse-DNS observation, not a source.** |
| `ads.reddit.com` | — | **Chrome, signed in, via `harbor chrome`** | 2026-09-30 | Reddit Ads, cited in [contracts/browser-routing.md](../../contracts/browser-routing.md) row 4 and `harbor-private/access/reddit.md`. **Supports the claim:** the claude-in-chrome extension refused it ("not allowed due to safety restrictions") and the pinned CLI through the Playwright Extension opened Events Manager and read the pixel id. A surface, not a source. |
| `docs.google.com` | — | **Chrome, both routes** | 2026-10-06 | Google Sheets, cited in row 4 for the `EDITORS` exception. **Supports the claim:** claude-in-chrome wrote a client report tab with a Name-Box focus check (2026-09-29); `harbor chrome` on 2026-10-06 typed range text into A2/A3, and its Delete and paste went into the Name Box, so 0 cells changed (verified by export). A surface, not a source. |
