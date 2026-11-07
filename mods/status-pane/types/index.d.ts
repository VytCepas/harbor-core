// The status-pane state contract (harbor#1480): what the pane draws from, kept in $.state for the session.
// Change the shape tag in hooks/register.tsx when a field here changes: a value an older version stored is then declined.

export type StatusPaneSourceId = 'obligations' | 'approvals' | 'sweep' | 'access' | 'skills'

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
