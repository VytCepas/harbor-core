// The pane's guarantees (harbor#1480, harbor#1485), each shown red once by breaking what it guards:
// a button press appends the row; an id outside the source table is refused, unrun; a failing source renders unavailable;
// open and refresh run no scan; scan-used follows a scan that worked and never a failed one; the write table runs only
// a known action with a held, well-formed id. The two suggestion tools are fixtures here: their JSON shapes are the contract's.
import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

import { ACTIONS, REFRESH_IDS, SOURCES, actionIdOk, knownIds, runAction } from '../hooks/sources'
import type { Where } from '../hooks/sources'
import { SCAN as REAL_SCAN, STATUS_EMPTY, STATUS_ROWS, VOCABULARY } from './fixtures/real-tools'

const HOME = '/home/op'
const PANE = {
  plugin: 'status-pane',
  component: 'Pane',
  requestId: 'status-pane',
  props: { title: 'Harbor', isFocused: true, bodyColumns: 120, placement: 'dock', scroll: { offset: 0, bodyRows: 60 }, view: {} },
} as const

const APPROVE = `${HOME}/.claude/bin/gate-approve.sh merge owner/repo 7 0123456789abcdef0123456789abcdef01234567`
const ROWS = [
  { id: 'approval:merge-owner_repo-7-0123456789ab', kind: 'approval', subject: 'merge-owner_repo-7-0123456789ab', owner: 'operator', title: 'approve merge 7', state: 'open', age_s: 7200 },
  { id: 'intent:handoff-plan', kind: 'intent', subject: 'handoff-plan', owner: 'operator', title: 'decide the plan tier', state: 'overdue', age_s: 200000 },
  { id: 'leftover:stray-files:port/x 1', kind: 'leftover', subject: 'stray-files:port/x 1', owner: 'operator', title: 'stray-files: port/x 1', state: 'open', age_s: 90000 },
  { id: 'pr:owner/repo#9', kind: 'pr', subject: 'owner/repo#9', owner: 'session:abc', title: 'a session PR', state: 'open', age_s: 60 },
]

type Answer = { exitCode: number; stdout: string; stderr?: string } | 'throw'
type Script = Partial<Record<'obligations' | 'approvals' | 'sweep' | 'access' | 'skills' | 'suggest' | 'scan' | 'act', Answer>>
const ok = (v: unknown): Answer => ({ exitCode: 0, stdout: typeof v === 'string' ? v : JSON.stringify(v) })
const STATUS = {
  schema: 1,
  enabled: true,
  stopped: [{ id: 'old-tip', since: '2026-11-01', origin: 'agent', label: 'old tip' }],
  last: { id: 'wait-for-ci', line: 'You could let the box wait for CI.', at: '2026-11-05' },
  rows: [
    { id: 'wait-for-ci', kind: 'verb', line: 'Wait for CI the shared way.', stopped: false },
    { id: 'old-tip', kind: 'skill', line: 'An old tip.', stopped: true },
  ],
  intro_due: false,
}
const SCAN = {
  schema: 1,
  days: 14,
  sessions: 12,
  candidates: [
    { id: 'a1b2c3d4', kind: 'skill', shape: 'connector report, then write document', sessions: 4, count: 9 },
    { id: 'e5f6a7b8', kind: 'mod', shape: 'search the web, then write document', sessions: 3, count: 5 },
  ],
}
const GOOD: Script = {
  suggest: ok(STATUS),
  scan: ok(SCAN),
  act: { exitCode: 0, stdout: '' },
  obligations: ok({ generated_ts: '', sources: {}, obligations: ROWS, proposals: [], read_ts: '' }),
  approvals: ok([{ id: 'merge-owner_repo-7-0123456789ab', command: APPROVE }]),
  sweep: ok(`${JSON.stringify({ class: 'stray-files', subject: 'port/x 1', action: `rm '${HOME}/port/x/1'` })}\n`),
  access: { exitCode: 1, stdout: JSON.stringify({ entries: [{ id: 'gh-pr-read', state: 'expired', problem: 'expired 2026-11-01', since: '2026-11-01' }, { id: 'mail', state: 'ok', problem: null, since: '' }, { id: 'sso-login', state: 'unknown', problem: null, since: '2026-10-26' }, { id: 'slow-api', state: 'unknown', problem: 'the check did not finish in 30s', since: '2026-11-05' }] }) },
  skills: ok({ ts: '', days: 30, skills: [{ name: 'tdd', tier: 'box', hidden: true, description: 'Test first.', uses: 0, last_used: null }] }),
}

// The world beneath the plugin: a box with a checkout, and each source answering from the script.
function world(on: On, script: Script, hold?: { scan?: Promise<void> }) {
  const ran: string[][] = []
  const copied: string[] = []
  const toasts: string[] = []
  mock.env(on, { HOME, PORT_ROOT: `${HOME}/port` })
  mock.clock(on, { now: Date.UTC(2026, 10, 6, 1, 0, 0) })
  on('command.register', () => ({ value: { command: 'status-pane' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('ui.toast', (_, e) => {
    toasts.push(e.text ?? '')
    return { value: undefined }
  })
  on('fs.exists', () => ({ value: true }))
  on('ui.copy', (_, e) => {
    copied.push(e.text)
    return { value: { isCopied: true } }
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('process.run', async (_, e) => {
    const argv = [...e.argv]
    ran.push(argv)
    const line = argv.join(' ')
    const id = line.includes('status-suggest-scan.sh')
      ? 'scan'
      : line.includes('status-suggest.sh')
        ? argv[2] === 'status'
          ? 'suggest'
          : 'act'
        : line.includes('status-obligations.sh')
          ? 'obligations'
      : line.includes('gate-queue.sh')
        ? 'approvals'
        : argv[0] === 'jq'
          ? 'sweep'
          : line.includes('access status')
            ? 'access'
            : line.includes('skill-catalog.sh')
              ? 'skills'
              : undefined
    if (id === 'scan') await hold?.scan
    const a = id ? script[id] : undefined
    if (!a || a === 'throw') throw new Error(`cannot start ${argv[0]}`)
    return { value: { exitCode: a.exitCode, stdout: a.stdout, stderr: a.stderr ?? '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  return { ran, copied, toasts, session: mock.session(on) }
}

// What a person types: Enter at the prompt, in a fullscreen terminal.
const TYPED = { origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 200 } } as const

const texts = async (ui: { findAll: (q: { type: 'Text' }) => Promise<readonly { text?: string }[]> }) =>
  (await ui.findAll({ type: 'Text' })).map(t => t.text ?? '').join('\n')

test('a button press appends the row: use, fix and copy, on every surface that takes input', async ($, on) => {
  const w = world(on, GOOD)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    await ui.press({ key: 'refresh' })
    const before = w.session.appended().length

    await ui.press({ key: 'use:tdd' })
    const use = w.session.appended().slice(before)
    expect(use).toHaveLength(1)
    expect(use[0]?.message.type).toBe('user')
    expect(JSON.stringify(use[0]?.message.content)).toContain('Load the skill tdd')

    await ui.press({ key: 'fix:gh-pr-read' })
    const fix = w.session.appended().slice(before + 1)
    expect(fix).toHaveLength(1)
    expect(JSON.stringify(fix[0]?.message.content)).toContain('gh-pr-read: expired · expired 2026-11-01 · since 2026-11-01')

    await ui.press({ key: 'copy:approval:merge-owner_repo-7-0123456789ab' })
    expect(w.copied.at(-1)).toBe(APPROVE) // the exact command, not the abbreviated one drawn
    await ui.press({ key: 'copy:leftover:stray-files:port/x 1' })
    expect(w.copied.at(-1)).toBe(`rm '${HOME}/port/x/1'`)
    await ui.press({ key: 'copy:intent:handoff-plan' })
    expect(w.copied.at(-1)).toBe('harbor event emit obligation.close handoff-plan')

    const shown = await texts(ui)
    expect(shown).toContain('sh bin/status-obligations.sh show --json · ran ') // every panel names its command and run time
    expect(shown).toContain('sh bin/skill-catalog.sh usage --json --live · ran ')
    expect(shown).toContain('sh bin/harbor access status --json · ran ')
    expect(shown).toContain('Access · 2 need you · 1 ok · 1 no check') // an entry with no check is not a problem
    expect(shown).toContain('slow-api: unknown · since 2026-11-05 · the check did not finish in 30s') // one that failed to answer is
    expect(shown).toContain('1 have no check to run: harbor access status -v')
    expect(shown).not.toContain('sso-login')
    await ui.press({ key: 'fix:slow-api' })
    expect(JSON.stringify(w.session.appended().at(-1)?.message.content)).toContain('slow-api: unknown')
    expect(shown).toContain('<cfg>/bin/gate-approve.sh merge owner/repo 7') // drawn without the config dir's path
    expect(shown).not.toContain(`${HOME}/.claude`)
    expect(shown).not.toContain('a session PR') // a session's row is not the operator's turn
    await ui.unmount()
  }
})

test('an id outside the source table is refused and runs nothing', async ($, on) => {
  const w = world(on, GOOD)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  for (const args of ['rm', '__proto__', 'toString', 'obligations; rm -rf /']) {
    const r = await $.command.run({ ...TYPED, command: 'status-pane', args })
    expect(r.text ?? '').toMatch(/^refused: .* is not in the source table/)
  }
  expect(w.ran).toHaveLength(0)

  const r = await $.command.run({ ...TYPED, command: 'status-pane', args: 'approvals' })
  expect(r.text).toBe('Harbor pane: approvals re-ran: ok.')
  expect(w.ran).toEqual([[`${HOME}/.claude/bin/gate-queue.sh`, 'list', '--json']])
})

test('a source that fails, or cannot start, renders unavailable, never empty or zero', async ($, on) => {
  world(on, {
    ...GOOD,
    obligations: { exitCode: 2, stdout: '', stderr: 'jq: error: ledger unreadable' },
    access: 'throw',
    skills: ok('not json'),
  })
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    await ui.press({ key: 'refresh' })
    const shown = await texts(ui)
    expect(shown).toContain('unavailable: exit 2: jq: error: ledger unreadable')
    expect(shown).toContain('unavailable: did not run: ')
    expect(shown).toContain('unavailable: output is not the skill usage shape')
    expect(shown).not.toContain('nothing of yours is open')
    expect(shown).not.toContain('the register lists no entries')
    expect(await ui.find({ key: 'use:tdd' })).toBeUndefined()
    await ui.unmount()
  }
})

// The status-suggest.sh calls in a run log: the verb and everything after it.
const verbs = (ran: string[][]) => ran.filter(a => a.join(' ').includes('status-suggest.sh')).map(a => a.slice(2).join(' '))
const scans = (ran: string[][]) => ran.filter(a => a.join(' ').includes('status-suggest-scan.sh')).length

test('open and refresh run no scan: it is a row of its own, on demand', async ($, on) => {
  const w = world(on, GOOD)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  expect(REFRESH_IDS).not.toContain('scan')
  expect(SOURCES.scan.onDemand).toBe(true)

  await $.command.run({ ...TYPED, command: 'status-pane', args: '' }) // opens the pane, which refreshes
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    await ui.press({ key: 'refresh' })
    const shown = await texts(ui)
    expect(shown).toContain('Suggestions · on · 1 stopped') // the status row did run
    expect(shown).toContain('not scanned in this session: press scan')
    await ui.unmount()
  }
  expect(verbs(w.ran)).toContain('status --json')
  expect(scans(w.ran)).toBe(0)
  expect(verbs(w.ran).filter(v => v !== 'status --json')).toEqual([]) // and no write ran either
})

test('the Scan press scans, then marks the scan used; a failed scan is not marked used', async ($, on) => {
  const script: Script = { ...GOOD } // read at call time, so a later step may change what a tool answers
  const w = world(on, script)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    await ui.press({ key: 'refresh' })
    w.ran.length = 0
    await ui.press({ key: 'scan' })
    expect(scans(w.ran)).toBe(1)
    expect(verbs(w.ran).filter(v => v.startsWith('scan-used'))).toEqual(['scan-used'])
    const order = w.ran.map(a => (a.join(' ').includes('status-suggest-scan.sh') ? 'scan' : (a[2] ?? '')))
    expect(order.indexOf('scan')).toBeLessThan(order.indexOf('scan-used')) // used only after the scan
    const shown = await texts(ui)
    expect(shown).toContain('12 sessions over 14 days')
    expect(shown).toContain('connector report, then write document · skill · 4 sessions, 9 times')
    expect(shown).toContain('sh bin/status-suggest-scan.sh --json --live · ran ')
    await ui.unmount()
  }

  script.scan = { exitCode: 2, stdout: '', stderr: 'scan: sessions unreadable' }
  w.ran.length = 0
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await ui.press({ key: 'scan' })
  expect(scans(w.ran)).toBe(1)
  expect(verbs(w.ran)).toEqual([]) // not scan-used
  expect(await texts(ui)).toContain('unavailable: exit 2: scan: sessions unreadable')
  await ui.unmount()

  script.scan = GOOD.scan // a typed `/status-pane scan` is a press too
  w.ran.length = 0
  const r = await $.command.run({ ...TYPED, command: 'status-pane', args: 'scan' })
  expect(r.text).toBe('Harbor pane: scan re-ran: ok.')
  expect(verbs(w.ran).filter(v => !v.startsWith('status'))).toEqual(['scan-used'])
})

test('Stop, Start, Off and On run the write table with the panel origin and one held id', async ($, on) => {
  const script: Script = { ...GOOD }
  const w = world(on, script)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    await ui.press({ key: 'refresh' })
    w.ran.length = 0
    await ui.press({ key: 'stop:wait-for-ci' })
    await ui.press({ key: 'start:old-tip' })
    await ui.press({ key: 'suggest-toggle' })
    expect(verbs(w.ran).filter(v => !v.startsWith('status'))).toEqual([
      'stop wait-for-ci --origin panel',
      'start old-tip --origin panel',
      'off --origin panel',
    ])
    expect(verbs(w.ran).filter(v => v.startsWith('status')).length).toBe(3) // each write re-reads the status
    const shown = await texts(ui)
    expect(shown).toContain('verb: Wait for CI the shared way.')
    expect(shown).toContain('since 2026-11-01 · by agent · old tip')
    expect(shown).toContain('last shown 2026-11-05: You could let the box wait for CI.')
    expect(await ui.find({ key: 'stop:old-tip' })).toBeUndefined() // a stopped row is on the stopped list, with Start
    await ui.unmount()
  }

  script.suggest = ok({ ...STATUS, enabled: false })
  w.ran.length = 0
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await ui.press({ key: 'refresh' })
  expect(await texts(ui)).toContain('suggestions are off')
  await ui.press({ key: 'suggest-toggle' })
  expect(verbs(w.ran)).toContain('on --origin panel')
  await ui.unmount()
})

test('a candidate: build it sends the fixed sentence, dismiss stops its id, Start brings it back, a hostile one is not drawn', async ($, on) => {
  const hostile = { id: '0badc0de', kind: 'skill', shape: 'x`;id;`', sessions: 1, count: 1 }
  const script: Script = { ...GOOD, scan: ok({ ...SCAN, candidates: [...SCAN.candidates, hostile] }) }
  const w = world(on, script)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    await ui.press({ key: 'refresh' })
    await ui.press({ key: 'scan' })
    expect(await ui.find({ key: 'build:0badc0de' })).toBeUndefined()
    expect(await texts(ui)).toContain('1 candidate(s) not shown: unexpected shape')

    const before = w.session.appended().length
    await ui.press({ key: 'build:a1b2c3d4' })
    const rows = w.session.appended().slice(before)
    expect(rows).toHaveLength(1)
    expect(rows[0]?.message.type).toBe('user')
    expect(JSON.stringify(rows[0]?.message.content)).toContain(
      "Harbor suggestion a1b2c3d4: a skill for connector report, then write document. Explain it in plain words, and offer to build it the standard way, through default-way-route's homes (asked from the Harbor pane).",
    )
    expect(w.toasts.at(-1)).toContain('send any message') // an idle session does not wake by itself

    w.ran.length = 0
    script.suggest = ok({ ...STATUS, stopped: [...STATUS.stopped, { id: 'a1b2c3d4', since: '2026-11-06', origin: 'panel', label: 'a1b2c3d4' }] })
    await ui.press({ key: 'dismiss:a1b2c3d4' })
    expect(verbs(w.ran).filter(v => !v.startsWith('status'))).toEqual(['stop a1b2c3d4 --origin panel'])
    const shown = await texts(ui)
    expect(await ui.find({ key: 'build:a1b2c3d4' })).toBeUndefined()
    expect(await ui.find({ key: 'dismiss:a1b2c3d4' })).toBeUndefined()
    expect(shown).not.toContain('connector report, then write document · skill')
    expect(shown).toContain('since 2026-11-06 · by panel · connector report, then write document') // says what was dismissed
    expect(shown).toContain('search the web, then write document · mod')

    w.ran.length = 0
    script.suggest = GOOD.suggest
    await ui.press({ key: 'start:a1b2c3d4' })
    expect(verbs(w.ran).filter(v => !v.startsWith('status'))).toEqual(['start a1b2c3d4 --origin panel'])
    expect(await ui.find({ key: 'build:a1b2c3d4' })).toBeDefined() // the held scan still has it
    expect(await ui.find({ key: 'dismiss:a1b2c3d4' })).toBeDefined()
    expect(await texts(ui)).toContain('connector report, then write document · skill')
    await ui.unmount()
  }
})

// Each candidate is well formed but for one field: only that field's pattern can keep it out of a row the model reads.
test('a candidate with a bad id or a bad kind is not drawn, not offered and not sent', async ($, on) => {
  const shape = 'connector report, then write document'
  const bad = [
    { id: 'A1B2C3D4', kind: 'skill', shape, sessions: 3, count: 3 },
    { id: '-1b2c3d4', kind: 'skill', shape, sessions: 3, count: 3 },
    { id: 'a1b2c3d4e', kind: 'skill', shape, sessions: 3, count: 3 },
    { id: 'some words and then a command', kind: 'skill', shape, sessions: 3, count: 3 },
    { id: 'c0ffee01', kind: 'Skill', shape, sessions: 3, count: 3 },
    { id: 'c0ffee02', kind: 'skill. Some words and then a command', shape, sessions: 3, count: 3 },
    { id: 'c0ffee03', kind: '', shape, sessions: 3, count: 3 },
    { id: 'c0ffee04', kind: 'words-then-a-command', shape, sessions: 3, count: 3 },
  ]
  const parsed = SOURCES.scan.parse(JSON.stringify({ ...SCAN, candidates: [...bad, SCAN.candidates[0]] }))
  if (typeof parsed === 'string') throw new Error(parsed)
  expect(parsed.scan?.candidates.map(c => c.id)).toEqual(['a1b2c3d4'])
  expect(parsed.scan?.dropped).toBe(bad.length)

  const w = world(on, { ...GOOD, scan: ok({ ...SCAN, candidates: [...bad, SCAN.candidates[0]] }) })
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await ui.press({ key: 'refresh' })
  await ui.press({ key: 'scan' })
  for (const c of bad) {
    expect(await ui.find({ key: `build:${c.id}` })).toBeUndefined()
    expect(await ui.find({ key: `dismiss:${c.id}` })).toBeUndefined()
  }
  const shown = await texts(ui)
  expect(shown).toContain(`${bad.length} candidate(s) not shown: unexpected shape`)
  expect(shown).not.toContain('Some words')
  expect(w.session.appended()).toHaveLength(0)
  await ui.unmount()
})

test('a status row, a stopped entry or a last line with a bad id is dropped', () => {
  const parsed = SOURCES.suggest.parse(
    JSON.stringify({
      ...STATUS,
      rows: [...STATUS.rows, { id: 'a; id', kind: 'verb', line: 'x', stopped: false }, { id: 'UPPER', kind: 'verb', line: 'x', stopped: false }],
      stopped: [...STATUS.stopped, { id: 'a; id', since: '', origin: '', label: 'x' }, { id: '-lead', since: '', origin: '', label: 'x' }],
      last: { id: 'a; id', line: 'x', at: '' },
    }),
  )
  if (typeof parsed === 'string') throw new Error(parsed)
  expect(parsed.suggest?.rows.map(r => r.id)).toEqual(['wait-for-ci', 'old-tip'])
  expect(parsed.suggest?.stopped.map(r => r.id)).toEqual(['old-tip'])
  expect(parsed.suggest?.last).toBeNull()
})

test('Start works on an id that lives only in the stopped list: a dismissed candidate is no table row', async ($, on) => {
  const w = world(on, { ...GOOD, suggest: ok({ ...STATUS, stopped: [{ id: 'c0ffee42', since: '2026-11-06', origin: 'panel', label: 'c0ffee42' }] }) })
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await ui.press({ key: 'refresh' })
  w.ran.length = 0
  await ui.press({ key: 'start:c0ffee42' })
  expect(verbs(w.ran).filter(v => !v.startsWith('status'))).toEqual(['start c0ffee42 --origin panel'])
  expect(w.toasts.filter(t => t.startsWith('refused'))).toEqual([])
  await ui.unmount()
})

test('a press during a scan runs nothing: one scan, one scan-used, and the pane says it is scanning', async ($, on) => {
  let release = () => {}
  const hold = { scan: new Promise<void>(r => (release = r)) as Promise<void> | undefined }
  const w = world(on, GOOD, hold)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await ui.press({ key: 'refresh' })
  w.ran.length = 0

  const first = ui.press({ key: 'scan' })
  await new Promise(r => setTimeout(r, 20))
  expect(await texts(ui)).toContain('scanning…') // no answer yet, and said so
  await ui.press({ key: 'scan' })
  expect(w.toasts.at(-1)).toBe('a scan is already running')
  release()
  await first
  expect(scans(w.ran)).toBe(1)
  expect(verbs(w.ran).filter(v => v.startsWith('scan-used'))).toEqual(['scan-used'])

  // A later scan keeps the last answer drawn while it runs, and the button works again.
  hold.scan = new Promise<void>(r => (release = r))
  w.ran.length = 0
  const again = ui.press({ key: 'scan' })
  await new Promise(r => setTimeout(r, 20))
  const during = await texts(ui)
  expect(during).toContain('connector report, then write document · skill')
  expect(during).toContain('running now')
  release()
  await again
  expect(scans(w.ran)).toBe(1)
  await ui.unmount()
})

test('the stopped list drawn from the real tool: since and origin survive the clip, at any width', async ($, on) => {
  world(on, { ...GOOD, suggest: ok(STATUS_ROWS) })
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  for (const bodyColumns of [120, 60]) {
    const ui = await $.ui.mount({ ...PANE, surface: 'desktop', props: { ...PANE.props, bodyColumns } })
    await ui.press({ key: 'refresh' })
    const shown = await texts(ui)
    expect(shown).toContain('since 2026-11-06 · by agent · There is a ready')
    expect(shown).toContain('since 2026-11-06 · by panel · a1b2c3d4')
    await ui.unmount()
  }
})

// Every step comes from the real tool (`status-suggest-scan.sh --vocabulary`; tests/status/suggest/e2e.test.sh holds this copy equal to it). Any shape is
// 2 to 4 steps, no two neighbours alike: a pattern that takes each step in each place, and the longest two alternating, takes them all.
test('every shape the closed vocabulary can make is drawn: a hidden candidate is a defect', () => {
  const { steps, kinds, most_steps: most, joiner } = JSON.parse(VOCABULARY) as { steps: string[]; kinds: string[]; most_steps: number; joiner: string }
  const [l1, l2] = [...steps].sort((a, b) => b.length - a.length)
  const fill = (at: number, step: string) => Array.from({ length: most }, (_, i) => (i === at ? step : i % 2 ? l2 : l1)).join(joiner)
  const shapes = steps.flatMap(s => [`${s}${joiner}${l1 === s ? l2 : l1}`, ...Array.from({ length: most }, (_, at) => fill(at, s))])
  const candidates = kinds.flatMap(kind => shapes.map(shape => ({ id: 'a1b2c3d4', kind, shape, sessions: 3, count: 3 })))
  const parsed = SOURCES.scan.parse(JSON.stringify({ schema: 1, days: 14, sessions: 3, candidates }))
  if (typeof parsed === 'string') throw new Error(parsed)
  const hidden = candidates.filter(c => !parsed.scan?.candidates.some(d => d.shape === c.shape && d.kind === c.kind))
  expect(hidden.slice(0, 3)).toEqual([])
  expect(parsed.scan?.dropped).toBe(0)
  expect(parsed.scan?.candidates.length).toBe(kinds.length * steps.length * (most + 1))
  expect(steps).toContain('run python3') // the step that once fell outside the pattern
  expect(steps).toContain('use a connector') // the neutral step: a connector whose name says neither read nor write
})

test('the scan row waits at least twice the slowest real scan measured (75 s, a loaded box)', () => {
  expect(SOURCES.scan.timeoutMs).toBeGreaterThanOrEqual(2 * 75_000)
})

// Output the real tools printed (tests/status/suggest/fixture.sh), through the pane's own parsers.
test('the real tools\' output passes the parsers: nothing is unavailable, nothing is dropped', () => {
  const empty = SOURCES.suggest.parse(STATUS_EMPTY)
  if (typeof empty === 'string') throw new Error(empty)
  expect(empty.suggest).toEqual({ enabled: true, stopped: [], last: null, rows: [], introDue: false })

  const rows = SOURCES.suggest.parse(STATUS_ROWS)
  if (typeof rows === 'string') throw new Error(rows)
  expect(rows.suggest?.rows.map(r => r.id)).toEqual(['fixture-verb', 'fixture-skill', 'fixture-connector', 'fixture-file', 'fixture-mod', 'fixture-intro'])
  expect(rows.suggest?.rows.find(r => r.id === 'fixture-skill')?.stopped).toBe(true)
  expect(rows.suggest?.stopped.map(r => `${r.id} ${r.origin}`)).toEqual(['fixture-skill agent', 'a1b2c3d4 panel'])
  expect(rows.suggest?.last?.id).toBe('fixture-verb')
  expect(rows.suggest?.introDue).toBe(true)

  const scan = SOURCES.scan.parse(REAL_SCAN)
  if (typeof scan === 'string') throw new Error(scan)
  expect(scan.scan?.dropped).toBe(0)
  expect(scan.scan?.candidates.map(c => c.kind).sort()).toEqual(['job', 'mod', 'skill'])
  expect(scan.scan?.candidates.some(c => c.shape.includes('python3'))).toBe(true)
})

test('the write table refuses an unknown action and any id the pane does not hold, unrun', async () => {
  // runAction called directly, on a bare engine whose process.run records what it is asked to start
  const ranArgv: string[][] = []
  const $ = {
    clock: { now: async () => 0 },
    process: { run: async (argv: readonly string[]) => (ranArgv.push([...argv]), { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false }) },
  } as never
  const w = { ran: ranArgv }
  // malformed ids are put IN the held set too: the pattern has to refuse them on its own, not just the held check
  const known = new Set(['wait-for-ci', 'old-tip', 'a1b2c3d4', 'wait-for-ci; id', '--origin', '__proto__', 'WAIT-FOR-CI'])
  const bin: Where = { bin: `${HOME}/port/harbor/bin`, root: `${HOME}/port/harbor`, cfg: `${HOME}/.claude`, home: HOME }

  expect(Object.isFrozen(ACTIONS)).toBe(true)
  expect(Object.keys(ACTIONS).sort()).toEqual(['off', 'on', 'scan-used', 'start', 'stop'])
  for (const id of ['wait-for-ci', 'a1b2c3d4']) expect(actionIdOk(id, known)).toBe(true)
  for (const id of ['x', 'WAIT-FOR-CI', 'wait-for-ci; id', '--origin', '-h', '../old-tip', '__proto__', 'toString', '', 'a1b2c3d4 ', 'e5f6a7b8'])
    expect(actionIdOk(id, known)).toBe(false) // malformed, or well-formed and not held
  expect(actionIdOk(undefined, known)).toBe(false)
  expect(actionIdOk(7, known)).toBe(false)

  for (const [action, id] of [
    ['rm', 'old-tip'],
    ['__proto__', 'old-tip'],
    ['stop', undefined],
    ['stop', 'not-held'],
    ['start', 'wait-for-ci; id'],
    ['start', '--origin'],
    ['off', 'old-tip'], // off, on and scan-used take no id
    ['scan-used', 'old-tip'],
  ] as const) {
    const r = await runAction($, action, id, bin, known)
    expect(r.status).toBe('refused')
  }
  expect(w.ran).toHaveLength(0)

  const r = await runAction($, 'stop', 'old-tip', bin, known)
  expect(r.status).toBe('ok')
  expect(w.ran).toEqual([['sh', `${HOME}/port/harbor/bin/status-suggest.sh`, 'stop', 'old-tip', '--origin', 'panel']])

  const meta = { status: 'ok', reason: '', command: '', ranAt: 0, ms: 0 } as const
  const held = {
    suggest: {
      ...meta,
      suggest: { enabled: true, introDue: false, stopped: [{ id: 's9', since: '', origin: '', label: 's9' }], last: null, rows: [{ id: 'r1', kind: 'verb', line: '', stopped: false }] },
    },
    scan: { ...meta, scan: { days: 1, sessions: 1, dropped: 0, candidates: [{ id: 'a1b2c3d4', kind: 'skill', shape: 'x', sessions: 1, count: 1 }] } },
  }
  expect([...knownIds(held)].sort()).toEqual(['a1b2c3d4', 'r1', 's9'])
})

test('a write is not a source: /status-pane stop is refused and runs nothing', async ($, on) => {
  const w = world(on, GOOD)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  for (const args of ['stop', 'scan-used', 'off']) {
    const r = await $.command.run({ ...TYPED, command: 'status-pane', args })
    expect(r.text ?? '').toMatch(/^refused: .* is not in the source table/)
  }
  expect(w.ran).toHaveLength(0)
})

test('a suggestion source or write that fails says unavailable, never empty', async ($, on) => {
  const script: Script = { ...GOOD, suggest: { exitCode: 2, stdout: '', stderr: 'status-suggest: state folder unreadable' } }
  const f = world(on, script)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    await ui.press({ key: 'refresh' })
    const shown = await texts(ui)
    expect(shown).toContain('unavailable: exit 2: status-suggest: state folder unreadable')
    expect(shown).not.toContain('no suggestion is active')
    expect(await ui.find({ key: 'suggest-toggle' })).toBeUndefined()
    await ui.unmount()
  }

  script.suggest = ok({ ...STATUS, schema: 2 })
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await ui.press({ key: 'refresh' })
  expect(await texts(ui)).toContain('unavailable: output is not the suggestion status shape (schema 1)')
  await ui.unmount()

  script.suggest = ok(STATUS)
  script.act = { exitCode: 2, stdout: '', stderr: 'usage: bad id' }
  const ui2 = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await ui2.press({ key: 'refresh' })
  await ui2.press({ key: 'stop:wait-for-ci' })
  expect(f.toasts.at(-1)).toBe('unavailable: stop: exit 2: usage: bad id')
  await ui2.unmount()
})
