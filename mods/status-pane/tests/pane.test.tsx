// The pane's three guarantees (harbor#1480), each shown red once by breaking what it guards:
// a button press appends the row; an id outside the source table is refused, unrun; a failing source renders unavailable.
import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

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
type Script = Partial<Record<'obligations' | 'approvals' | 'sweep' | 'access' | 'skills', Answer>>
const ok = (v: unknown): Answer => ({ exitCode: 0, stdout: typeof v === 'string' ? v : JSON.stringify(v) })
const GOOD: Script = {
  obligations: ok({ generated_ts: '', sources: {}, obligations: ROWS, proposals: [], read_ts: '' }),
  approvals: ok([{ id: 'merge-owner_repo-7-0123456789ab', command: APPROVE }]),
  sweep: ok(`${JSON.stringify({ class: 'stray-files', subject: 'port/x 1', action: `rm '${HOME}/port/x/1'` })}\n`),
  access: { exitCode: 1, stdout: JSON.stringify({ entries: [{ id: 'gh-pr-read', state: 'expired', problem: 'expired 2026-11-01', since: '2026-11-01' }, { id: 'mail', state: 'ok', problem: null, since: '' }, { id: 'sso-login', state: 'unknown', problem: null, since: '2026-10-26' }, { id: 'slow-api', state: 'unknown', problem: 'the check did not finish in 30s', since: '2026-11-05' }] }) },
  skills: ok({ ts: '', days: 30, skills: [{ name: 'tdd', tier: 'box', hidden: true, description: 'Test first.', uses: 0, last_used: null }] }),
}

// The world beneath the plugin: a box with a checkout, and each source answering from the script.
function world(on: On, script: Script) {
  const ran: string[][] = []
  const copied: string[] = []
  mock.env(on, { HOME, PORT_ROOT: `${HOME}/port` })
  mock.clock(on, { now: Date.UTC(2026, 10, 6, 1, 0, 0) })
  on('command.register', () => ({ value: { command: 'status-pane' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('ui.toast', () => ({ value: undefined }))
  on('fs.exists', () => ({ value: true }))
  on('ui.copy', (_, e) => {
    copied.push(e.text)
    return { value: { isCopied: true } }
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('process.run', (_, e) => {
    const argv = [...e.argv]
    ran.push(argv)
    const line = argv.join(' ')
    const id = line.includes('status-obligations.sh')
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
    const a = id ? script[id] : undefined
    if (!a || a === 'throw') throw new Error(`cannot start ${argv[0]}`)
    return { value: { exitCode: a.exitCode, stdout: a.stdout, stderr: a.stderr ?? '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  return { ran, copied, session: mock.session(on) }
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
