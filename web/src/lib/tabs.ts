export type Tab = {
  id: string
  path: string
}

export type TabsState = {
  tabs: Tab[]
  activeId: string | null
}

export const EMPTY_TABS: TabsState = { tabs: [], activeId: null }

export function tabsStorageKey(repoFullName: string): string {
  return `synapse_tabs:${repoFullName}`
}

function makeId(): string {
  // Good-enough unique id for a session-scoped tab list.
  return `t_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`
}

export function findTabByPath(state: TabsState, path: string): Tab | null {
  return state.tabs.find((t) => t.path === path) ?? null
}

export function activeTab(state: TabsState): Tab | null {
  if (!state.activeId) return null
  return state.tabs.find((t) => t.id === state.activeId) ?? null
}

// Open a file in the active tab: if the path is already in a tab, activate
// that tab; otherwise replace the active tab's path (or create a first tab
// when the list is empty).
export function openInActive(state: TabsState, path: string): TabsState {
  const existing = findTabByPath(state, path)
  if (existing) return { ...state, activeId: existing.id }
  if (state.tabs.length === 0 || state.activeId === null) {
    const tab: Tab = { id: makeId(), path }
    return { tabs: [...state.tabs, tab], activeId: tab.id }
  }
  const tabs = state.tabs.map((t) =>
    t.id === state.activeId ? { ...t, path } : t,
  )
  return { ...state, tabs }
}

// Open a file in a NEW tab inserted after the active one. If the path is
// already open, just activate that tab instead of duplicating.
export function openInNewTab(state: TabsState, path: string): TabsState {
  const existing = findTabByPath(state, path)
  if (existing) return { ...state, activeId: existing.id }
  const tab: Tab = { id: makeId(), path }
  if (state.activeId === null) {
    return { tabs: [...state.tabs, tab], activeId: tab.id }
  }
  const idx = state.tabs.findIndex((t) => t.id === state.activeId)
  const insertAt = idx < 0 ? state.tabs.length : idx + 1
  const tabs = [
    ...state.tabs.slice(0, insertAt),
    tab,
    ...state.tabs.slice(insertAt),
  ]
  return { tabs, activeId: tab.id }
}

export function activateTab(state: TabsState, id: string): TabsState {
  if (!state.tabs.some((t) => t.id === id)) return state
  return { ...state, activeId: id }
}

export function activateByIndex(
  state: TabsState,
  oneBasedIndex: number,
): TabsState {
  if (oneBasedIndex < 1 || oneBasedIndex > state.tabs.length) return state
  return { ...state, activeId: state.tabs[oneBasedIndex - 1].id }
}

// Close a tab. If the closed tab was active, activate the neighbor on the
// right, or the left if it was last. Returns activeId=null when list is empty.
export function closeTab(state: TabsState, id: string): TabsState {
  const idx = state.tabs.findIndex((t) => t.id === id)
  if (idx < 0) return state
  const nextTabs = state.tabs.filter((t) => t.id !== id)
  let nextActiveId = state.activeId
  if (state.activeId === id) {
    if (nextTabs.length === 0) nextActiveId = null
    else if (idx < nextTabs.length) nextActiveId = nextTabs[idx].id
    else nextActiveId = nextTabs[nextTabs.length - 1].id
  }
  return { tabs: nextTabs, activeId: nextActiveId }
}

// Rename a path inside the tab list (in place; does not reorder).
export function renamePath(
  state: TabsState,
  oldPath: string,
  newPath: string,
): TabsState {
  let changed = false
  const tabs = state.tabs.map((t) => {
    if (t.path === oldPath) {
      changed = true
      return { ...t, path: newPath }
    }
    return t
  })
  return changed ? { ...state, tabs } : state
}

type Storage = Pick<globalThis.Storage, 'getItem' | 'setItem' | 'removeItem'>

export function parseTabs(raw: string | null): TabsState {
  if (!raw) return EMPTY_TABS
  try {
    const parsed = JSON.parse(raw) as unknown
    if (!parsed || typeof parsed !== 'object') return EMPTY_TABS
    const tabsIn = (parsed as { tabs?: unknown }).tabs
    const activeIn = (parsed as { activeId?: unknown }).activeId
    if (!Array.isArray(tabsIn)) return EMPTY_TABS
    const tabs: Tab[] = []
    const seen = new Set<string>()
    for (const row of tabsIn) {
      if (!row || typeof row !== 'object') continue
      const id = (row as { id?: unknown }).id
      const path = (row as { path?: unknown }).path
      if (typeof id !== 'string' || !id) continue
      if (typeof path !== 'string' || !path) continue
      if (seen.has(id)) continue
      seen.add(id)
      tabs.push({ id, path })
    }
    const activeId =
      typeof activeIn === 'string' && tabs.some((t) => t.id === activeIn)
        ? activeIn
        : tabs.length > 0
          ? tabs[0].id
          : null
    return { tabs, activeId }
  } catch {
    return EMPTY_TABS
  }
}

export function loadTabs(
  repoFullName: string,
  storage: Storage = localStorage,
): TabsState {
  return parseTabs(storage.getItem(tabsStorageKey(repoFullName)))
}

export function saveTabs(
  repoFullName: string,
  state: TabsState,
  storage: Storage = localStorage,
): void {
  if (state.tabs.length === 0) {
    storage.removeItem(tabsStorageKey(repoFullName))
  } else {
    storage.setItem(tabsStorageKey(repoFullName), JSON.stringify(state))
  }
}
