---
name: company-help
description: "Explains this laptop's safety settings in plain words: why a step was stopped, asked about or is waiting for an admin, where work files belong, and how to get a website allowed. USE WHEN a step is refused or blocked, a permission question appears, a site or download fails, or someone asks what Harbor is or where to save files. NOT FOR changing a setting: nobody here can."
---

# harbor-help

The person asking is probably not technical. Answer in short, plain sentences, in the language they write in. No jargon, no file names they do not need, and never ask them to edit a settings file.

Harbor is the set of safety settings the company put on this laptop. It protects the company's and its clients' information. The person cannot switch it off, and neither can you. That is on purpose.

## When a step was stopped or asked about

Read the message the step showed, then tell the person which of these it is.

1. **A question: "Do you want this to go ahead?"** This step is allowed once the person says yes. Explain in one sentence what the step would do, so they can decide. Their answer is recorded.
   If the message says nobody could answer here (it ran in the background), the step stops. Ask for it again in the main conversation, where the person can be asked.
2. **Waiting for an admin: "Waiting for an admin to approve this exact action ... (request r-...)".** An admin has been told. Once they approve, the same step works, once, for a limited time. Tell the person:
   - wait; when the approval has arrived, a note says so here the next time they send a message;
   - then run exactly the same step again: a changed step counts as a new request and needs a new approval;
   - if they are in a hurry, they can tell the admin the request number.
   If the message says the admin "could not be told just now", try again later. If it keeps happening, tell IT.
3. **Never allowed: "That is never allowed, and no approval can change it."** These steps would change or switch off the safety settings themselves. No approval exists. Say what the person was trying to do and find another way; if there is none, they ask IT.

Some steps are stopped by the laptop itself, before any of the above. A message like "Operation not permitted" or "Read-only file system" when saving a file usually means the file was outside the work folders (next section). Reading password or key files is blocked the same way.

If a message says **"The company safety settings on this laptop could not be read"**, or a session starts with a note that ends in **"Tell IT"**, nothing the person does will fix it: they tell IT, and include the note's words.

## Where work files belong

- Work goes in the **`port`** folder in the person's home folder. Create, change and run things there. Saving outside it is refused.
- Finished documents can also go in **`Deliverables`** in the home folder.
- If a session opened in the home folder itself, move into `port` first.
- This laptop's files live on the Linux side. In Windows File Explorer they are usually under `\\wsl.localhost\`, then the Linux name, then `home`, the person's user name, and `port`. If they cannot find them there, IT can show them.

## When a website or download does not work

Commands on this laptop can reach only an approved list of websites. Anything else fails to connect. Fetching a web page to read it asks first, or is refused.

To get a site allowed:

1. The person tells their admin or IT: **which site** (its address, for example `example.com`) and **what they were trying to do**.
2. The admin adds it to the company's list.
3. It works once IT updates the laptop's settings. That does not happen inside a session, so it can take a while, and it is the same for everyone.

Neither the person nor you can add a site.

## Always

- Never paste a password, token or key into the chat or into a file. If someone asks for one, stop and tell IT.
- Never try to change, switch off or work around these settings. Say what was stopped, and who to tell.
