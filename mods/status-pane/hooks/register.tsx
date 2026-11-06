// The Harbor pane (harbor#1480): the console's panels 1-3 docked beside the conversation, read-only.
// It draws what the fixed source table (sources.ts) answers; every rule about the data lives in the Harbor
// command it calls. A button copies a command, or appends one user row the model reads; nothing else writes.
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { StatusPaneResult, StatusPaneResults, StatusPaneSourceId, StatusPaneTurnRow } from '../types'
import { SOURCE_IDS, runSource, scrub, where } from './sources'

const PANE = 'status-pane'

// Change the tag when StatusPaneResult changes: it declines what an earlier version stored, which outlives a reload.
const results = atom({ plugin: 'status-pane', key: 'results' } as const, {} as StatusPaneResults, { shape: 'results-1' })
const skillQuery = atom({ plugin: 'status-pane', key: 'skillQuery' } as const, '')

const SKILL_NAME = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,79}$/
const ACCESS_ID = /^[a-z0-9][a-z0-9._-]{0,79}$/
const PLAIN_ID = /^[A-Za-z0-9][A-Za-z0-9._:#/-]{0,199}$/
const MAX_TURN = 15
const MAX_SKILLS = 12

export const ageText = (s: number) =>
  s < 0 ? 'age ?' : s < 90 ? `${Math.round(s)}s` : s < 5400 ? `${Math.floor(s / 60)}m` : s < 172800 ? `${Math.floor(s / 3600)}h` : `${Math.floor(s / 86400)}d`

const clock = (ms: number) => {
  try {
    return new Date(ms).toLocaleTimeString('en-GB', { timeZone: 'Europe/Vilnius', hour12: false })
  } catch {
    return `${new Date(ms).toISOString().slice(11, 19)} UTC`
  }
}

// Run these sources, each writing its own result as it lands. The previous answer stays drawn, marked running.
async function refresh($: EngineInterface, ids: readonly StatusPaneSourceId[]) {
  const w = await where($)
  const now = await $.clock.now()
  await update($, results, r => {
    const next: StatusPaneResults = { ...(r ?? {}) }
    for (const id of ids) next[id] = { ...(next[id] ?? { reason: '', command: '', ms: 0 }), status: 'running', ranAt: next[id]?.ranAt ?? now }
    return next
  })
  await Promise.all(
    ids.map(async id => {
      const res = await runSource($, id, w)
      await update($, results, r => ({ ...(r ?? {}), [id]: res }))
    }),
  )
}

// The exact command a "Your turn" row asks for, or why it has none.
function turnCommand(row: StatusPaneTurnRow, all: StatusPaneResults): { command: string } | { why: string } {
  const from = (id: 'approvals' | 'sweep', missing: string) => {
    const src = all[id]
    if (!src || src.status !== 'ok') return { why: `${id} unavailable: ${src?.reason || 'not run yet'}` }
    const c = src.commands?.[row.subject]
    return c ? { command: c } : { why: missing }
  }
  if (row.kind === 'approval') return from('approvals', 'not in the approvals queue')
  if (row.kind === 'leftover') return from('sweep', 'the sweep record names no action for it')
  if (row.kind === 'intent')
    return PLAIN_ID.test(row.subject) ? { command: `harbor event emit obligation.close ${row.subject}` } : { why: 'its subject is not a plain id' }
  return { why: `no command for kind ${row.kind}` }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'status-pane',
      description: 'Open the Harbor pane: your turn, skills, access. `/status-pane <source>` re-runs one source.',
      argumentHint: `[${SOURCE_IDS.join('|')}]`,
    })
    return next(e)
  })

  on('command.run', { command: 'status-pane' }, async ($, e) => {
    const arg = e.args.trim()
    if (arg) {
      // A typed id goes through the table's own check in runSource, and nowhere else: one it does not hold runs nothing.
      await $.ui.open({ id: PANE, title: 'Harbor' })
      const r = await runSource($, arg, await where($))
      if (r.status === 'refused') return { text: `refused: ${r.reason} (the sources: ${SOURCE_IDS.join(', ')})` }
      await update($, results, all => ({ ...(all ?? {}), [arg as StatusPaneSourceId]: r }))
      return { text: `Harbor pane: ${arg} re-ran: ${r.status === 'ok' ? 'ok' : `unavailable: ${r.reason}`}.` }
    }
    await $.ui.open({ id: PANE, title: 'Harbor' })
    void refresh($, SOURCE_IDS)
    return { text: 'Harbor pane opened.' }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button, Input } = $.ui.resolve(e)
    const all = await read($, results)
    const query = await read($, skillQuery)
    const w = await where($)
    const cols = Math.max(30, e.props.bodyColumns)
    const clip = (t: string, n = cols - 2) => scrub(t, typeof w === 'string' ? undefined : w, Math.max(10, n))

    const ran = (r: StatusPaneResult | undefined, id: StatusPaneSourceId) => {
      if (!r) return <Text dimColor>{clip(`${id}: not run in this session yet`)}</Text>
      const when = r.status === 'running' ? 'running now' : `ran ${clock(r.ranAt)} (${(r.ms / 1000).toFixed(1)}s)`
      return <Text dimColor>{clip(`${r.command || id} · ${when}`)}</Text>
    }
    // Unavailable is said, never drawn as an empty list or a zero.
    const down = (r: StatusPaneResult | undefined) =>
      !r ? (
        <Text color="warning">unavailable: not run yet (/status-pane runs it)</Text>
      ) : r.status === 'unavailable' || r.status === 'refused' ? (
        <Text color="warning">{clip(`unavailable: ${r.reason}`)}</Text>
      ) : r.status === 'running' && !r.turn && !r.skills && !r.access ? (
        <Text dimColor>running…</Text>
      ) : undefined

    // 1 · Your turn
    const ob = all.obligations
    const turnRows = [...(ob?.turn ?? [])].sort(
      (a, b) => Number(b.state === 'overdue') - Number(a.state === 'overdue') || b.ageS - a.ageS,
    )
    const turn = (
      <Box flexDirection="column" marginBottom={1}>
        <Text bold>
          Your turn{ob?.turn ? ` · ${turnRows.length} listed, ${turnRows.filter(r => r.state === 'overdue').length} overdue` : ''}
        </Text>
        {ran(ob, 'obligations')}
        {ran(all.approvals, 'approvals')}
        {ran(all.sweep, 'sweep')}
        {down(ob) ??
          (turnRows.length === 0 ? (
            <Text>nothing of yours is open</Text>
          ) : (
            turnRows.slice(0, MAX_TURN).map(row => {
              const c = turnCommand(row, all)
              return (
                <Box flexDirection="column">
                  <Box flexDirection="row">
                    <Text color={row.state === 'overdue' ? 'warning' : undefined}>
                      {clip(`${ageText(row.ageS)} ${row.state === 'overdue' ? 'overdue ' : ''}${row.kind}: ${row.title}`, cols - 9)}
                    </Text>
                    {'command' in c && (
                      <Button
                        key={`copy:${row.id}`}
                        label="copy"
                        onPress={async pe => {
                          const r = await $.ui.copy({ text: c.command, surface: pe.surface })
                          $.ui.toast(r.isCopied ? 'Copied the command.' : `Not copied: ${r.reason}`)
                        }}
                      />
                    )}
                  </Box>
                  <Text dimColor>{clip(`  ${'command' in c ? c.command : `no command: ${c.why}`}`)}</Text>
                </Box>
              )
            })
          ))}
        {turnRows.length > MAX_TURN && <Text dimColor>{`${turnRows.length - MAX_TURN} more not shown`}</Text>}
      </Box>
    )

    // 2 · Skills library
    const sk = all.skills
    const q = query.trim().toLowerCase()
    const skillRows = [...(sk?.skills ?? [])]
      .filter(s => !q || s.name.toLowerCase().includes(q) || s.description.toLowerCase().includes(q))
      .sort((a, b) => b.lastUsed.localeCompare(a.lastUsed) || b.uses - a.uses || a.name.localeCompare(b.name))
    const skills = (
      <Box flexDirection="column" marginBottom={1}>
        <Text bold>
          Skills{sk?.skills ? ` · ${sk.skills.length} installed, ${sk.skills.filter(s => s.uses === 0).length} unused 30d` : ''}
        </Text>
        {ran(sk, 'skills')}
        {down(sk) ?? (
          <Box flexDirection="column">
            <Input
              key="skill-search"
              placeholder="search skills"
              value={query}
              onInput={v => void update($, skillQuery, () => v)}
              onSubmit={v => void update($, skillQuery, () => v)}
            />
            {skillRows.length === 0 && <Text>{q ? 'no skill matches the search' : 'the feed lists no skills'}</Text>}
            {skillRows.slice(0, MAX_SKILLS).map(s => (
              <Box flexDirection="row">
                <Text>
                  {clip(
                    `${s.name}${s.hidden ? ' [hidden]' : ''}${s.uses === 0 ? ' [unused 30d]' : ''} · ${s.tier || 'tier ?'} · ${s.uses} uses${s.lastUsed ? `, last ${s.lastUsed.slice(0, 10)}` : ''}`,
                    cols - 8,
                  )}
                </Text>
                {SKILL_NAME.test(s.name) && (
                  <Button
                    key={`use:${s.name}`}
                    label="use"
                    onPress={async () => {
                      await $.session.append({
                        message: { type: 'user', content: [{ type: 'text', text: `Load the skill ${s.name} (asked from the Harbor pane).` }] },
                      })
                      $.ui.toast(`Asked the model to load ${s.name}.`)
                    }}
                  />
                )}
              </Box>
            ))}
            {skillRows.length > MAX_SKILLS && <Text dimColor>{`${skillRows.length - MAX_SKILLS} more; search to narrow`}</Text>}
          </Box>
        )}
      </Box>
    )

    // 3 · Access
    const ac = all.access
    const accessRows = [...(ac?.access ?? [])].sort((a, b) => Number(a.state === 'ok') - Number(b.state === 'ok') || a.id.localeCompare(b.id))
    const access = (
      <Box flexDirection="column">
        <Text bold>Access{ac?.access ? ` · ${accessRows.filter(a => a.state !== 'ok').length} not ok of ${accessRows.length}` : ''}</Text>
        {ran(ac, 'access')}
        {down(ac) ??
          (accessRows.length === 0 ? (
            <Text>the register lists no entries</Text>
          ) : (
            accessRows.map(a => {
              const line = `${a.id}: ${a.state}${a.why ? ` · ${a.why}` : ''}${a.since ? ` · since ${a.since}` : ''}`
              return (
                <Box flexDirection="row">
                  <Text color={a.state === 'ok' ? undefined : 'warning'}>{clip(line, cols - 8)}</Text>
                  {a.state !== 'ok' && ACCESS_ID.test(a.id) && (
                    <Button
                      key={`fix:${a.id}`}
                      label="fix"
                      onPress={async () => {
                        await $.session.append({
                          message: {
                            type: 'user',
                            content: [{ type: 'text', text: `Harbor access entry ${scrub(line, undefined, 300)}. Help me fix it (asked from the Harbor pane).` }],
                          },
                        })
                        $.ui.toast(`Asked the model about ${a.id}.`)
                      }}
                    />
                  )}
                </Box>
              )
            })
          ))}
      </Box>
    )

    return (
      <Box flexDirection="column">
        <Box flexDirection="row">
          <Text dimColor>{clip(typeof w === 'string' ? `unavailable: ${w}` : 'read-only · buttons copy or append one row')}</Text>
          <Button key="refresh" label="refresh" onPress={() => refresh($, SOURCE_IDS)} />
        </Box>
        {turn}
        {skills}
        {access}
      </Box>
    )
  })
}
