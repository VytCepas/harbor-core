---
name: doc-lithuanian-prose
description: "How a Lithuanian sentence is written for a person: verbs over noun chains, plain words for kanceliarizmai, native connectives, one-word hedges, numbers and punctuation, English jargon with an apostrophe ending, drawn from good publicists and the operator's own edits. USE WHEN writing any Lithuanian text a person reads — mail, DM, ticket or thread comment, report, document, slide, client write-up. NOT FOR mail structure or length (mail-cal Message shape, formerly Draft shape), the five outbound moves (doc-deliverable-contract), or English text."
disable-model-invocation: true
---

# doc-lithuanian-prose

## Ideal state

**A Lithuanian reader takes the text for a colleague's, not a machine's.** The
measured failure is a reader's verdict on a correct ~900-word reply: *„perkrauti,
krūva šnekamojoj kalboj nenaudojamų žodžių ir gana sunku skaitant suprasti
esmę“*. Done looks like:

- the first sentence is the verdict;
- every action has a person and a finite verb;
- no word appears that the writer would not say out loud;
- an identifier the reader pastes is exactly the string they paste.

This file owns **the sentence**. Structure, length and section sets belong to
whichever skill owns the surface (`mail-cal` → Message shape, Draft shape on an older install, for mail, DMs and comments,
`doc-deliverable-contract` for any outbound answer); where they conflict on
length, theirs wins.

**Sources.** Ten opinion columns on LRT and 15min, 2026-10/11 — Lazutka,
Kojala, Valatka, Jakučionis, Skruibis, Bikelis, Bruveris, Leontjeva, Šlekys,
Bitautas — chosen because good columnists explain hard things in plain
Lithuanian without kanceliarinė kalba. Quotes are short exact lines from them
(read through WebFetch, checked by a second reader 2026-11-18); the ✗/✓ pairs
are constructed and are not quotes. The operator's rules in §8 come from his
own edits to drafts.

## 1. First sentence = the verdict

- „Biudžetas vien dėl 3,8 proc. BVP deficito dydžio yra išlaidūniškas.“ — Jakučionis
- „Lietuvoje sujudimas dėl pinigų kaip reta.“ — Lazutka

✗ „Norėčiau trumpai apžvelgti situaciją dėl konversijų sekimo.“
✓ „Purchase event'ai nuo pirmadienio į Meta nebeateina – juos blokuoja naujas consent baneris.“

## 2. Verbs carry the action, a person does it

The columnists put an agent and a finite verb where kanceliarinė kalba puts a
noun chain: „Respublikonai prarado daugumą abiejuose Kongreso rūmuose.“
(Kojala). Nominal phrasing survives only for abstract ideas, never for who did
what.

| ✗ noun chain | ✓ verb |
|---|---|
| Šiuo metu yra vykdomas duomenų perkėlimas. | Duomenis dabar perkeliu. |
| Prašome atlikti pakeitimų įdiegimą. | Prašom įdiegti pakeitimus. |
| Sutrikimas įvyko dėl tag'o konfigūracijos klaidos. | Konversijos nesiregistravo, nes tag'as buvo blogai nustatytas. |
| Bus užtikrintas tinkamas duomenų perdavimas. | Duomenys vėl eis į ataskaitą. |

**Person.** Columnists use *aš* for judgement — „Visgi manau, kad“
(Jakučionis), „Man regis“ (Bitautas), „Tačiau aš tikiu, kad pavyks.“ (Skruibis).
Own work is first person singular (§8). Passive only where the actor truly does
not matter.

## 3. Plain words for kanceliarizmai

| ✗ | ✓ |
|---|---|
| atsižvelgiant į tai, kad | kadangi / todėl |
| šiuo metu | dabar |
| esant poreikiui | jei reikės |
| pateikti informaciją | atsiųsti, parašyti |
| vykdyti, įgyvendinti | the concrete verb: sutvarkyti, įdėti, paleisti |
| užtikrinti, kad X veiktų | kad X veiktų (or: X veiks) |
| norėčiau informuoti, kad | — cut |
| kalbant apie X | start with X, or „O X…“ |

The test for any word not in the table: would the writer say it out loud to a
colleague? If not, use the word they would say.

## 4. Rhythm: one short sentence at every turn

About a fifth to a third of the columnists' sentences are short, and they sit at
the turns — after the setup, at the verdict, at the end:

- „Pradėkime nuo gerų naujienų.“ … „Tačiau tuo geros naujienos ir baigiasi.“ — Lazutka
- „Juokinga? Nebent juodai.“ — Bikelis
- „Ir taip šimtai milijonų švaistomi.“ — Lazutka

Default is short sentences, one idea each. When a sentence must be long, it
carries one subordinate clause at most and a short one follows it.

✓ „Tag'as veikia. Bet tik checkout'e – produkto puslapyje jis net neužsikrauna.“

## 5. A small set of native connectives

A whole column runs on *tačiau, bet, o, todėl, tad, vadinasi, juk, mat, vis
dėlto, be to, beje, kitaip tariant, tai reiškia, kad*. Kojala explains with
„mat“: „…bet Rubio turi potencialo, mat didesnė dalis amerikiečių dėl jo dar
nėra apsisprendę.“

Concession is two sentences, not a clause stack: „Žinoma, kartais teisės aktai
yra būtini problemai spręsti.“ → „Tačiau daugelio socialinių problemų vien teisės
aktais neišspręsi.“ (Skruibis).

✓ „Žinoma, galima palikti kaip yra. Tačiau tada Meta matys tik pusę pirkimų.“

Two or three items inside prose: „Pirma, … Antra, …“ (Bruveris).

## 6. Hedge with one short word

*galbūt, turbūt, gal, vargu ar, kažin ar, atrodo, man regis* — „Vargu ar ramiai
tam pritartume.“ (Leontjeva).

✗ „Galima būtų daryti prielaidą, kad problema gali būti susijusi su…“
✓ „Turbūt kaltas consent baneris.“

*esą / neva* mark someone else's claim and carry distance, often irony („nes tai
neva kenkia Europos saugumui“ — Valatka). **Never about a client or a
colleague**: it reads as a sneer.

## 7. Numbers, punctuation, foreign names

- Decimal comma and abbreviations: „1,7–2 proc.“, „beveik 200 mln. eurų“, „60 tūkst. eurų“; thousands by a space: „iki 300 000 eurų“.
- Small and round quantities in words: „prieš vienuolika metų“.
- Do the arithmetic for the reader: „30 mokinių, 45 minutės – pusantros minutės vienam vaikui.“ (Bitautas). ✓ „Iš 1 200 pirkimų Meta mato 610 – maždaug pusę.“
- Quotes are „…“, never "…".
- A dash stands in for a dropped „yra“: „Sukurti veiksmingas sistemas – ilgas darbas“ (Skruibis).
- Dates: „spalio 5-ąją“, „2022-ųjų vasario 24-oji“.
- A foreign name takes its ending after an apostrophe when the stem does not end in a Lithuanian way — „Vance'as“, „Ratcliffe'o“; established loanwords decline normally („dronų“).

## 8. The operator's own rules (from his edits to drafts)

- **Jargon stays English with a Lithuanian ending after an apostrophe**: `event'as`, `tag'ą`, `pixel'is`, `checkout'o`, `switch'as`, `trigger'intis`, `click ID'as`. Never an invented Lithuanian word for it (*žymė*, *jungiklis*, *iššauti* were all rejected). Words with a normal Lithuanian form keep it: konversija, serveris, naršyklė, slapukas, atribucija.
- **Never decline a literal identifier** — „event_id“, „gclid“, „begin_checkout“ stay byte-exact; a declined one is a different string the reader pastes into a ticket.
- **First person singular for his own work**: `Pažymėjau`, `Radau`, `Nuimsiu`, `pridėčiau aš`. One person owns it; an aside goes in parentheses — „pridėčiau aš pats (kliento IT nereikia)“.
- **No attribution sentence in either direction** — neither defence nor confession („Mūsų techninė klaida.“ was deleted). State what happened.
- **A client's developers are `IT`**, not *programuotojai*.
- **No English filler where Lithuanian exists**: *jūsų sutikimo*, not *jūsų ok*.
- **The shorter noun phrase wins**: *be veikiančių konversijų*, not *be nė vienos veikiančios konversijos*.

## 9. What NOT to borrow from the columnists

They write essays; work text is not one.

- **Long sentences.** Bruveris and Valatka often run 25–40 words. Cap at one subordinate clause.
- **Irony and sarcasm.** Fine in a column, a liability in text someone forwards to a client.
- **Rhetorical questions** to a client or colleague. Ask a real question or state the point.
- **Idioms as decoration.** „lengva ranka“, „laisva pavara“ — at most one, and only one the writer would say.
- **Scare quotes** around official terms.
- **The closing flourish** („Linkiu kovoti pasiūlymais, o ne naratyvais.“). End on the ask or the next step: „Todėl siūlau …“.

## Sources

Opinion columns, read 2026-11-18 (author, title, outlet):

- Romas Lazutka, „Pamesti šimtai milijonų svarstant biudžetą“, LRT
- Linas Kojala, „Rubio dilema: likti ar nelikti su Trumpu“, LRT
- Rimvydas Valatka, „Pagaminta Rusijoje“, LRT
- Saulius Jakučionis, „3,8 proc. biudžeto deficito – kas toliau?“, LRT
- Paulius Skruibis, „Teisės aktas kaip problemos sprendimas“, LRT
- Skirmantas Bikelis, „Meras, ministrė ir tarybos narys užeina į barą „Teisinė valstybė““, LRT
- Vytautas Bruveris, „Kito kelio, nei nukauti priešą, vis tiek nėra“, LRT
- Elena Leontjeva, „Metas sodinti ir rauti, arba vėl tas biudžeto laikas“, LRT
- Deividas Šlekys, „Valia pašaukti“, 15min
- Algis Bitautas, „Mano svajonių mokykloje mokytojui leidžiama būti mokytoju“, LRT
