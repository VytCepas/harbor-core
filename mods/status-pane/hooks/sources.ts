// The pane's allowlist (harbor#1480): every command the pane may run, in TWO frozen tables, each row an argument array.
// Modelled on tools/ui/sources.ts. SOURCES are reads: a request names a source id and nothing else, no command text,
// path or argument. ACTIONS (harbor#1485) are the five suggestion writes: a request names an action, and for stop and
// start one id that must match a strict pattern AND be one this pane already holds (a status row, the stopped list,
// a candidate of the last scan). No command text, path or option ever comes from the model, the prompt or a drawn row.
// An id outside either table is refused, unrun.
import type { EngineInterface } from 'claude-code'

import type {
  StatusPaneAccessRow,
  StatusPaneActionId,
  StatusPaneCandidate,
  StatusPaneResult,
  StatusPaneResults,
  StatusPaneScan,
  StatusPaneSkillRow,
  StatusPaneSourceId,
  StatusPaneSuggest,
  StatusPaneTurnRow,
} from '../types'

// Where the sources live, resolved at run time the way bin/harbor resolves its own scripts:
// HARBOR_SCOPE_BIN, else ${PORT_ROOT:-$HOME/port}/harbor/bin, and only where status-generate.sh is there.
export type Where = { bin: string; root: string; cfg: string; home: string }

type Parsed = Partial<Pick<StatusPaneResult, 'turn' | 'commands' | 'skills' | 'access' | 'suggest' | 'scan'>>
type Parse = (stdout: string) => Parsed | string // a string is why the output is not the shape: unavailable

export type Source = {
  readonly id: StatusPaneSourceId
  readonly argv: (w: Where) => readonly string[]
  readonly okExits: readonly number[] // exits that are an answer; any other exit is unavailable
  readonly timeoutMs: number
  readonly parse: Parse
  readonly onDemand?: boolean // never run by open or refresh: only a person's press (or a typed id) starts it
}

const isObj = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)
const str = (v: unknown) => (typeof v === 'string' ? v : '')
const json = (text: string): unknown => {
  try {
    return JSON.parse(text)
  } catch {
    return undefined
  }
}

// The obligation kinds the operator acts on: approvals, hand-offs (intent) and leftovers (contracts/obligation-kinds.tsv).
export const TURN_KINDS = ['approval', 'intent', 'leftover'] as const
const LIVE = new Set(['open', 'overdue'])

const parseObligations: Parse = out => {
  const j = json(out)
  if (!isObj(j)) return 'output is not a JSON object'
  if (!Array.isArray(j.obligations)) return 'output has no obligations list' // the frozen shape, contracts/cli.md
  const turn: StatusPaneTurnRow[] = j.obligations
    .filter(isObj)
    .filter(r => r.owner === 'operator' && LIVE.has(str(r.state)) && (TURN_KINDS as readonly string[]).includes(str(r.kind)))
    .map(r => ({
      id: str(r.id),
      kind: str(r.kind),
      subject: str(r.subject),
      title: str(r.title) || str(r.subject) || 'untitled',
      state: str(r.state),
      ageS: typeof r.age_s === 'number' && Number.isFinite(r.age_s) ? r.age_s : -1,
    }))
  return { turn }
}

// gate-queue.sh list --json: each open approval with its exact approve command, keyed by the queue id (the obligation subject).
const parseApprovals: Parse = out => {
  const j = json(out)
  if (!Array.isArray(j)) return 'output is not a JSON list'
  const commands: Record<string, string> = {}
  for (const r of j.filter(isObj)) if (str(r.id) && str(r.command)) commands[str(r.id)] = str(r.command)
  return { commands }
}

// The sweep record's RISK and DECIDE rows: each leftover's `action`, keyed <class>:<subject> as the obligation subject is.
const parseSweep: Parse = out => {
  const commands: Record<string, string> = {}
  for (const line of out.split('\n')) {
    if (!line.trim()) continue
    const r = json(line)
    if (!isObj(r)) return 'a sweep row is not a JSON object'
    if (str(r.action)) commands[`${str(r.class)}:${str(r.subject)}`] = str(r.action)
  }
  return { commands }
}

// `harbor access status --json` (harbor#1480): { entries: [{ id, state, problem, since, ... }] }; the reason is `problem`.
const parseAccess: Parse = out => {
  const j = json(out)
  const list = Array.isArray(j) ? j : isObj(j) && Array.isArray(j.entries) ? j.entries : undefined
  if (!list) return 'output is not the access status shape ({ entries: [...] })'
  const access: StatusPaneAccessRow[] = list
    .filter(isObj)
    .filter(r => str(r.id))
    .map(r => ({ id: str(r.id), state: str(r.state) || 'unknown', why: str(r.problem), since: str(r.since) }))
  return { access }
}

// `skill-catalog.sh usage --json` (harbor#1480, lane B): { ts, days, skills: [{ name, tier, hidden, description, uses, last_used }] }.
const parseSkills: Parse = out => {
  const j = json(out)
  if (!isObj(j) || !Array.isArray(j.skills)) return 'output is not the skill usage shape ({ skills: [...] })'
  const skills: StatusPaneSkillRow[] = j.skills
    .filter(isObj)
    .filter(r => str(r.name))
    .map(r => ({
      name: str(r.name),
      tier: str(r.tier),
      hidden: r.hidden === true,
      description: str(r.description),
      uses: typeof r.uses === 'number' ? r.uses : 0,
      lastUsed: str(r.last_used),
    }))
  return { skills }
}

// The patterns every suggestion id and word passes before it is drawn or sent anywhere (contract: lane-contract.md, Panel).
export const ROW_ID = /^[a-z0-9][a-z0-9-]{0,26}$/
export const CANDIDATE_ID = /^[0-9a-f]{8}$/
const KIND = /^(mod|skill|hook|job)$/ // the scan's four, as --vocabulary prints them
const SHAPE = /^[a-z][a-z0-9 ,-]{0,119}$/ // the scan's closed vocabulary, every step of it (a test enumerates them); nothing else is let through
const num = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) && v >= 0 ? v : 0)

// `status-suggest.sh status --json` (harbor#1485): schema 1.
const parseSuggest: Parse = out => {
  const j = json(out)
  if (!isObj(j) || j.schema !== 1) return 'output is not the suggestion status shape (schema 1)'
  if (typeof j.enabled !== 'boolean' || !Array.isArray(j.stopped) || !Array.isArray(j.rows))
    return 'output is not the suggestion status shape (enabled, stopped, rows)'
  const last = isObj(j.last) && ROW_ID.test(str(j.last.id)) ? { id: str(j.last.id), line: str(j.last.line), at: str(j.last.at) } : null
  const suggest: StatusPaneSuggest = {
    enabled: j.enabled,
    stopped: j.stopped
      .filter(isObj)
      .filter(r => ROW_ID.test(str(r.id)))
      .map(r => ({ id: str(r.id), since: str(r.since), origin: str(r.origin), label: str(r.label) || str(r.id) })),
    last,
    rows: j.rows
      .filter(isObj)
      .filter(r => ROW_ID.test(str(r.id)))
      .map(r => ({ id: str(r.id), kind: str(r.kind), line: str(r.line), stopped: r.stopped === true })),
    introDue: j.intro_due === true,
  }
  return { suggest }
}

// `status-suggest-scan.sh --json --live` (harbor#1485): schema 1. A candidate that fails a pattern is counted and not drawn.
const parseScan: Parse = out => {
  const j = json(out)
  if (!isObj(j) || j.schema !== 1 || !Array.isArray(j.candidates)) return 'output is not the suggestion scan shape (schema 1)'
  const all = j.candidates.filter(isObj)
  const candidates: StatusPaneCandidate[] = all
    .filter(r => CANDIDATE_ID.test(str(r.id)) && KIND.test(str(r.kind)) && SHAPE.test(str(r.shape)))
    .map(r => ({ id: str(r.id), kind: str(r.kind), shape: str(r.shape), sessions: num(r.sessions), count: num(r.count) }))
  const scan: StatusPaneScan = { days: num(j.days), sessions: num(j.sessions), candidates, dropped: j.candidates.length - candidates.length }
  return { scan }
}

// THE TABLE. Nothing else in the mod names a command.
export const SOURCES: Readonly<Record<StatusPaneSourceId, Source>> = Object.freeze({
  obligations: {
    id: 'obligations',
    argv: w => ['sh', `${w.bin}/status-obligations.sh`, 'show', '--json'],
    okExits: [0],
    timeoutMs: 60_000,
    parse: parseObligations,
  },
  approvals: {
    id: 'approvals',
    argv: w => [`${w.cfg}/bin/gate-queue.sh`, 'list', '--json'], // runs only as the installed copy, by its own rule
    okExits: [0],
    timeoutMs: 30_000,
    parse: parseApprovals,
  },
  sweep: {
    id: 'sweep',
    argv: w => ['jq', '-c', 'select(.verdict == "RISK" or .verdict == "DECIDE") | {class, subject, action}', `${w.cfg}/.helm-sweep.jsonl`],
    okExits: [0],
    timeoutMs: 10_000,
    parse: parseSweep,
  },
  access: {
    id: 'access',
    argv: w => ['sh', `${w.bin}/harbor`, 'access', 'status', '--json'],
    okExits: [0, 1], // 1 is "something is red", an answer
    timeoutMs: 180_000,
    parse: parseAccess,
  },
  skills: {
    id: 'skills',
    argv: w => ['sh', `${w.bin}/skill-catalog.sh`, 'usage', '--json', '--live'],
    okExits: [0],
    timeoutMs: 120_000,
    parse: parseSkills,
  },
  suggest: {
    id: 'suggest',
    argv: w => ['sh', `${w.bin}/status-suggest.sh`, 'status', '--json'],
    okExits: [0],
    timeoutMs: 30_000,
    parse: parseSuggest,
  },
  // Reads every session's tool calls, so it runs on a press and never on open or refresh (harbor#1485, decision 7).
  // `time sh bin/status-suggest-scan.sh --json --live`, 1.7 GB of transcripts: 9 s at load 7, 75 s at load 65. The timeout keeps 2x the worst.
  scan: {
    id: 'scan',
    argv: w => ['sh', `${w.bin}/status-suggest-scan.sh`, '--json', '--live'],
    okExits: [0],
    timeoutMs: 180_000,
    parse: parseScan,
    onDemand: true,
  },
})

export const SOURCE_IDS = Object.keys(SOURCES) as StatusPaneSourceId[]
// What open and refresh run: every row but the on-demand ones.
export const REFRESH_IDS = SOURCE_IDS.filter(id => !SOURCES[id].onDemand)

// Is this id a row of the table? The one check every run passes through.
export const isSourceId = (id: string): id is StatusPaneSourceId => Object.prototype.hasOwnProperty.call(SOURCES, id)

// The argv as a person reads it: the checkout's bin as bin/, the config dir as <cfg>, $HOME as ~ (no absolute paths on a panel).
export const shown = (argv: readonly string[], w: Where) =>
  argv
    .map(a =>
      a.startsWith(`${w.root}/`)
        ? a.slice(w.root.length + 1)
        : w.cfg && a.startsWith(`${w.cfg}/`)
          ? `<cfg>/${a.slice(w.cfg.length + 1)}`
          : w.home && a.startsWith(`${w.home}/`)
            ? `~/${a.slice(w.home.length + 1)}`
            : a,
    )
    .map(a => (/[\s"'|]/.test(a) ? `'${a}'` : a))
    .join(' ')

// Any text bound for a panel: $HOME and the config dir abbreviated, control characters dropped, clipped.
export const scrub = (text: string, w: Where | undefined, max = 200) => {
  let t = text.replace(/[\u0000-\u001f\u007f]/g, ' ')
  if (w?.cfg) t = t.split(w.cfg).join('<cfg>')
  if (w?.home) t = t.split(w.home).join('~')
  t = t.replace(/~\/\.claude\b/g, '<cfg>')
  return t.length > max ? `${t.slice(0, max - 1)}…` : t
}

export async function where($: EngineInterface): Promise<Where | string> {
  const home = (await $.env.get('HOME')) ?? ''
  const scoped = await $.env.get('HARBOR_SCOPE_BIN')
  const port = (await $.env.get('PORT_ROOT')) || (home ? `${home}/port` : '')
  const bin = scoped || (port ? `${port}/harbor/bin` : '')
  if (!bin) return 'no HOME, PORT_ROOT or HARBOR_SCOPE_BIN, so no harbor checkout can be found'
  if (!(await $.fs.exists(`${bin}/status-generate.sh`)))
    return `no harbor checkout at ${scrub(bin, { bin, root: '', cfg: '', home })} (set HARBOR_SCOPE_BIN or PORT_ROOT)`
  const cfg = (await $.env.get('CLAUDE_CONFIG_DIR')) || (home ? `${home}/.claude` : '')
  return { bin, root: bin.replace(/\/bin$/, ''), cfg, home }
}

const firstLine = (s: string) => (s.split('\n').map(l => l.trim()).find(Boolean) ?? '').slice(0, 160)

// The ONE place a process is started, for a source and for an action alike: an argv built from a table row, nothing else.
type Spec = { okExits: readonly number[]; timeoutMs: number; emptyOk: boolean; parse: Parse }
async function execute($: EngineInterface, w: Where, argv: readonly string[], spec: Spec, t0: number): Promise<StatusPaneResult> {
  const command = shown(argv, w)
  const done = async (r: Omit<StatusPaneResult, 'command' | 'ranAt' | 'ms'>): Promise<StatusPaneResult> => ({
    ...r,
    command,
    ranAt: t0,
    ms: (await $.clock.now()) - t0,
  })
  let ran
  try {
    ran = await $.process.run(argv, { cwd: w.root, env: { NO_COLOR: '1' }, timeoutMs: spec.timeoutMs })
  } catch (err) {
    const why = err instanceof Error ? err.message : String(err)
    return done({ status: 'unavailable', reason: `did not run: ${scrub(firstLine(why), w, 160) || 'no reason given'}` })
  }
  if (!spec.okExits.includes(ran.exitCode)) {
    const why = scrub(firstLine(ran.stderr) || firstLine(ran.stdout) || 'no output', w, 160)
    return done({ status: 'unavailable', reason: `exit ${ran.exitCode}: ${why}` })
  }
  if (ran.isStdoutTruncated) return done({ status: 'unavailable', reason: 'output is larger than 4 MiB, so it was cut and is not read' })
  if (!ran.stdout.trim() && !spec.emptyOk) return done({ status: 'unavailable', reason: 'the command printed nothing' })
  const parsed = spec.parse(ran.stdout)
  if (typeof parsed === 'string') return done({ status: 'unavailable', reason: parsed })
  return done({ status: 'ok', reason: '', ...parsed })
}

// It takes an id, looks it up in SOURCES, and runs that row's argv; an id the table does not hold is refused here, before anything runs.
export async function runSource($: EngineInterface, id: string, w: Where | string): Promise<StatusPaneResult> {
  const t0 = await $.clock.now()
  if (!isSourceId(id)) {
    return { status: 'refused', reason: `${scrub(id, undefined, 60)} is not in the source table`, command: '', ranAt: t0, ms: 0 }
  }
  if (typeof w === 'string') return { status: 'unavailable', reason: w, command: '', ranAt: t0, ms: 0 }
  const src = SOURCES[id]
  return execute($, w, src.argv(w), { okExits: src.okExits, timeoutMs: src.timeoutMs, emptyOk: id === 'sweep', parse: src.parse }, t0)
}

// THE WRITE TABLE (harbor#1485). The only commands the pane runs that change anything, every one scoped to the suggestion
// state folder by the tool itself. `takesId` rows get the id from the caller and nothing else; the origin is fixed here.
export type Action = {
  readonly id: StatusPaneActionId
  readonly takesId: boolean
  readonly argv: (w: Where, id: string) => readonly string[]
  readonly okExits: readonly number[]
  readonly timeoutMs: number
}
const tool = (w: Where, ...rest: string[]) => ['sh', `${w.bin}/status-suggest.sh`, ...rest]
export const ACTIONS: Readonly<Record<StatusPaneActionId, Action>> = Object.freeze({
  stop: { id: 'stop', takesId: true, argv: (w, id) => tool(w, 'stop', id, '--origin', 'panel'), okExits: [0], timeoutMs: 30_000 },
  start: { id: 'start', takesId: true, argv: (w, id) => tool(w, 'start', id, '--origin', 'panel'), okExits: [0], timeoutMs: 30_000 },
  off: { id: 'off', takesId: false, argv: w => tool(w, 'off', '--origin', 'panel'), okExits: [0], timeoutMs: 30_000 },
  on: { id: 'on', takesId: false, argv: w => tool(w, 'on', '--origin', 'panel'), okExits: [0], timeoutMs: 30_000 },
  'scan-used': { id: 'scan-used', takesId: false, argv: w => tool(w, 'scan-used'), okExits: [0], timeoutMs: 30_000 },
})

export const isActionId = (id: string): id is StatusPaneActionId => Object.prototype.hasOwnProperty.call(ACTIONS, id)

// The ids this pane holds right now: the status rows, the stopped list and the candidates of the last scan.
export function knownIds(all: StatusPaneResults): Set<string> {
  const ids = new Set<string>()
  for (const r of all.suggest?.suggest?.rows ?? []) ids.add(r.id)
  for (const r of all.suggest?.suggest?.stopped ?? []) ids.add(r.id)
  for (const c of all.scan?.scan?.candidates ?? []) ids.add(c.id)
  return ids
}

// The one check an id passes before it reaches an argv: a string, the row-id or the candidate-id pattern, and one of `known`.
export const actionIdOk = (id: unknown, known: ReadonlySet<string>): id is string =>
  typeof id === 'string' && (ROW_ID.test(id) || CANDIDATE_ID.test(id)) && known.has(id)

// Run one action. The name must be a row of ACTIONS; stop and start need an id that passes actionIdOk, the other three take none.
export async function runAction(
  $: EngineInterface,
  action: string,
  id: string | undefined,
  w: Where | string,
  known: ReadonlySet<string>,
): Promise<StatusPaneResult> {
  const t0 = await $.clock.now()
  const refuse = (reason: string): StatusPaneResult => ({ status: 'refused', reason, command: '', ranAt: t0, ms: 0 })
  if (!isActionId(action)) return refuse(`${scrub(action, undefined, 60)} is not in the action table`)
  const row = ACTIONS[action]
  if (!row.takesId && id !== undefined) return refuse(`${action} takes no id`)
  if (row.takesId && !actionIdOk(id, known)) return refuse(`${scrub(String(id), undefined, 60)} is not an id this pane holds`)
  if (typeof w === 'string') return { status: 'unavailable', reason: w, command: '', ranAt: t0, ms: 0 }
  return execute($, w, row.argv(w, id ?? ''), { okExits: row.okExits, timeoutMs: row.timeoutMs, emptyOk: true, parse: () => ({}) }, t0)
}
