// The pane's allowlist (harbor#1480): every command the pane may run, in ONE table, each an argument array.
// Modelled on tools/ui/sources.ts. A request names a source id and nothing else: no command text, path or
// argument ever comes from the model, the prompt or a drawn row. An id outside the table is refused, unrun.
import type { EngineInterface } from 'claude-code'

import type {
  StatusPaneAccessRow,
  StatusPaneResult,
  StatusPaneSkillRow,
  StatusPaneSourceId,
  StatusPaneTurnRow,
} from '../types'

// Where the sources live, resolved at run time the way bin/harbor resolves its own scripts:
// HARBOR_SCOPE_BIN, else ${PORT_ROOT:-$HOME/port}/harbor/bin, and only where status-generate.sh is there.
export type Where = { bin: string; root: string; cfg: string; home: string }

type Parsed = Partial<Pick<StatusPaneResult, 'turn' | 'commands' | 'skills' | 'access'>>
type Parse = (stdout: string) => Parsed | string // a string is why the output is not the shape: unavailable

export type Source = {
  readonly id: StatusPaneSourceId
  readonly argv: (w: Where) => readonly string[]
  readonly okExits: readonly number[] // exits that are an answer; any other exit is unavailable
  readonly timeoutMs: number
  readonly parse: Parse
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
})

export const SOURCE_IDS = Object.keys(SOURCES) as StatusPaneSourceId[]

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

// The ONE place a process is started. It takes an id, looks it up in the table, and runs that row's argv;
// an id the table does not hold is refused here, before anything runs.
export async function runSource($: EngineInterface, id: string, w: Where | string): Promise<StatusPaneResult> {
  const t0 = await $.clock.now()
  if (!isSourceId(id)) {
    return { status: 'refused', reason: `${scrub(id, undefined, 60)} is not in the source table`, command: '', ranAt: t0, ms: 0 }
  }
  if (typeof w === 'string') return { status: 'unavailable', reason: w, command: '', ranAt: t0, ms: 0 }
  const src = SOURCES[id]
  const argv = src.argv(w)
  const command = shown(argv, w)
  const done = async (r: Omit<StatusPaneResult, 'command' | 'ranAt' | 'ms'>): Promise<StatusPaneResult> => ({
    ...r,
    command,
    ranAt: t0,
    ms: (await $.clock.now()) - t0,
  })
  let ran
  try {
    ran = await $.process.run(argv, { cwd: w.root, env: { NO_COLOR: '1' }, timeoutMs: src.timeoutMs })
  } catch (err) {
    const why = err instanceof Error ? err.message : String(err)
    return done({ status: 'unavailable', reason: `did not run: ${scrub(firstLine(why), w, 160) || 'no reason given'}` })
  }
  if (!src.okExits.includes(ran.exitCode)) {
    const why = scrub(firstLine(ran.stderr) || firstLine(ran.stdout) || 'no output', w, 160)
    return done({ status: 'unavailable', reason: `exit ${ran.exitCode}: ${why}` })
  }
  if (ran.isStdoutTruncated) return done({ status: 'unavailable', reason: 'output is larger than 4 MiB, so it was cut and is not read' })
  if (!ran.stdout.trim() && id !== 'sweep') return done({ status: 'unavailable', reason: 'the command printed nothing' })
  const parsed = src.parse(ran.stdout)
  if (typeof parsed === 'string') return done({ status: 'unavailable', reason: parsed })
  return done({ status: 'ok', reason: '', ...parsed })
}
