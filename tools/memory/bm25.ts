// memory · the ranker (harbor#6 — workstream D, D1).
//
// Real BM25, including the IDF term. That qualifier is the whole point of this
// file, because the upstream tool this workstream vendors from does not have
// one: MemoryRetriever.ts:210-219 returns only the tf-saturation factor
//
//     tf * (k1 + 1) / (tf + k1 * (1 - b + b * dl/avgdl))
//
// and there is no document-frequency pass anywhere in that file. Without IDF a
// term carried by EVERY note scores exactly like a term carried by one, so the
// ranking answers "which note repeats the query most" instead of "which note is
// most distinctive for the query". D1's done-when says BM25-ranked, and
// tf-saturation alone would make that label false.
//
// The IDF form is Lucene's, not the textbook's:
//
//     idf(t) = ln(1 + (N - df + 0.5) / (df + 0.5))
//
// The textbook `ln((N - df + 0.5) / (df + 0.5))` goes NEGATIVE once a term is in
// more than half the corpus, which lets a common query term SUBTRACT score and
// can rank a note that contains every query term below one that contains fewer.
// The +1 keeps it positive for every df in [1, N] while preserving the ordering.
import type { Corpus, Note } from "./store.ts";
import { tokenize } from "./store.ts";

export const BM25_K1 = 1.5;
export const BM25_B = 0.75;

// Field weights are applied INSIDE the saturation, as multipliers on tf, not as
// flat additions to the final score. Upstream adds +10 for a title hit and +5
// for a tag hit (MemoryRetriever.ts:65-66) onto a score whose tf term saturates
// at k1+1 = 2.5, so a single title match dominates any amount of body evidence
// and the ranker degenerates into "did the title match". Weighting tf keeps
// every field on one scale and keeps the saturation meaningful.
export const TITLE_WEIGHT = 3;
export const TAG_WEIGHT = 2;

// The cut is RELATIVE to the best hit, never absolute. An absolute floor cannot
// be chosen without knowing the corpus: on the fixture corpus (N=17) a
// corpus-universal term has idf ≈ 0.028, so any fixed threshold near upstream's
// 0.20 returns the empty set for a perfectly good query, while on a large corpus
// the same number admits everything. A fraction of the top score is scale-free.
export const RELATIVE_CUT = 0.2;

export interface Index {
  n: number;
  avgLen: number;
  df: Map<string, number>;
}

export interface Hit {
  slug: string;
  relPath: string;
  title: string;
  score: number;
  excerpt: string;
}

function fieldCounts(note: Note): Map<string, number> {
  const m = new Map<string, number>();
  const add = (toks: string[], weight: number) => {
    for (const t of toks) m.set(t, (m.get(t) ?? 0) + weight);
  };
  add(note.tokens, 1);
  add(note.titleTokens, TITLE_WEIGHT);
  add(note.tagTokens, TAG_WEIGHT);
  return m;
}

// Document frequency counts a term ONCE per note, over the union of body, title
// and tags. Counting body alone would give a title-only term df = 0, and
// idf(0) = ln(1 + (N+0.5)/0.5) — a term that appears nowhere would outrank
// every real term in the corpus.
export function buildIndex(corpus: Corpus): Index {
  const df = new Map<string, number>();
  let total = 0;
  for (const note of corpus.notes) {
    total += note.length;
    const seen = new Set<string>([...note.tokens, ...note.titleTokens, ...note.tagTokens]);
    for (const t of seen) df.set(t, (df.get(t) ?? 0) + 1);
  }
  const n = corpus.notes.length;
  return { n, avgLen: n > 0 ? total / n : 1, df };
}

export function idf(index: Index, term: string): number {
  const df = index.df.get(term) ?? 0;
  return Math.log(1 + (index.n - df + 0.5) / (df + 0.5));
}

function saturate(tf: number, len: number, avgLen: number): number {
  if (tf <= 0) return 0;
  const denom = tf + BM25_K1 * (1 - BM25_B + BM25_B * (avgLen > 0 ? len / avgLen : 1));
  return (tf * (BM25_K1 + 1)) / denom;
}

export function scoreNote(note: Note, terms: string[], index: Index): number {
  const counts = fieldCounts(note);
  let score = 0;
  for (const term of terms) {
    const tf = counts.get(term) ?? 0;
    if (tf === 0) continue;
    score += idf(index, term) * saturate(tf, note.length, index.avgLen);
  }
  return score;
}

// The first body line carrying a query term, so the operator can see WHY a note
// matched without opening it. Deterministic: first match wins, never a "best"
// paragraph chosen by a second heuristic nobody can predict.
function excerptFor(note: Note, terms: string[], max = 160): string {
  const want = new Set(terms);
  for (const line of note.body.split("\n")) {
    const trimmed = line.trim();
    if (trimmed.length === 0) continue;
    for (const tok of tokenize(trimmed)) {
      if (want.has(tok)) {
        return trimmed.length > max ? `${trimmed.slice(0, max - 1)}…` : trimmed;
      }
    }
  }
  const first = note.body.split("\n").map((l) => l.trim()).find((l) => l.length > 0) ?? "";
  return first.length > max ? `${first.slice(0, max - 1)}…` : first;
}

export interface SearchOptions {
  limit?: number;
  cut?: number;
}

export function search(corpus: Corpus, query: string, opts: SearchOptions = {}): Hit[] {
  const terms = tokenize(query);
  if (terms.length === 0) return [];
  const index = buildIndex(corpus);
  const scored: Hit[] = [];
  for (const note of corpus.notes) {
    const score = scoreNote(note, terms, index);
    if (score <= 0) continue;
    scored.push({
      slug: note.slug,
      relPath: note.relPath,
      title: note.title,
      score,
      excerpt: excerptFor(note, terms),
    });
  }
  // Ties break on relPath so the order is stable across runs and machines; a
  // ranking that reorders equal scores makes every pinned expectation flaky.
  scored.sort((a, b) => (b.score - a.score) || (a.relPath < b.relPath ? -1 : a.relPath > b.relPath ? 1 : 0));
  const cut = (opts.cut ?? RELATIVE_CUT) * (scored[0]?.score ?? 0);
  const kept = scored.filter((h) => h.score >= cut);
  return opts.limit && opts.limit > 0 ? kept.slice(0, opts.limit) : kept;
}
