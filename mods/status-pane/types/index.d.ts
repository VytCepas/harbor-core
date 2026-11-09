// The status-pane state contract (harbor#1480): what the pane draws from, kept in $.state for the session.
// Change the shape tag in hooks/register.tsx when a field here changes: a value an older version stored is then declined.

// `scan` is on demand: sources.ts leaves it out of what open and refresh run (harbor#1485).
export type StatusPaneSourceId = 'obligations' | 'approvals' | 'sweep' | 'access' | 'skills' | 'suggest' | 'scan'

// The write verbs of the suggestion tool, each a row of ACTIONS in hooks/sources.ts and not of SOURCES.
export type StatusPaneActionId = 'stop' | 'start' | 'off' | 'on' | 'scan-used'

export type StatusPaneStatus = 'ok' | 'running' | 'unavailable' | 'refused'

// One operator-owned obligation the "Your turn" panel lists.
export type StatusPaneTurnRow = {
  id: string
  kind: string
  subject: string
  title: string
  state: string
  ageS: number
}

export type StatusPaneSkillRow = {
  name: string
  tier: string
  hidden: boolean
  description: string
  uses: number
  lastUsed: string
}

export type StatusPaneAccessRow = {
  id: string
  state: string
  why: string
  since: string
}

// `bin/status-suggest.sh status --json`, schema 1 (harbor#1485).
export type StatusPaneSuggest = {
  enabled: boolean
  stopped: { id: string; since: string; origin: string; label: string }[]
  last: { id: string; line: string; at: string } | null
  rows: { id: string; kind: string; line: string; stopped: boolean }[]
  introDue: boolean
}

// One candidate of `bin/status-suggest-scan.sh --json`: every field already passed the patterns in hooks/sources.ts.
export type StatusPaneCandidate = { id: string; kind: string; shape: string; sessions: number; count: number }

export type StatusPaneScan = { days: number; sessions: number; candidates: StatusPaneCandidate[]; dropped: number }

// What one run of one source came to. `command` is the argv as shown (home and config dir abbreviated);
// `ranAt` is when it started, in ms since the epoch, and 0 when it never ran.
export type StatusPaneResult = {
  status: StatusPaneStatus
  reason: string
  command: string
  ranAt: number
  ms: number
  turn?: StatusPaneTurnRow[]
  commands?: Record<string, string>
  skills?: StatusPaneSkillRow[]
  access?: StatusPaneAccessRow[]
  suggest?: StatusPaneSuggest
  scan?: StatusPaneScan
}

export type StatusPaneResults = Partial<Record<StatusPaneSourceId, StatusPaneResult>>

declare module 'claude-code' {
  interface PluginState {
    'status-pane': {
      results: Shaped<StatusPaneResults>
      skillQuery: string
    }
  }
}
