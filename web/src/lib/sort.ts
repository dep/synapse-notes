import type { TreeNode } from '../github/tree'

export type SortCriterion = 'name' | 'date'
export type SortDirection = 'asc' | 'desc'

export type SortSettings = {
  criterion: SortCriterion
  direction: SortDirection
}

export const DEFAULT_SORT: SortSettings = { criterion: 'name', direction: 'asc' }

export function sortSettingsStorageKey(repoFullName: string): string {
  return `synapse_sort:${repoFullName}`
}

export function parseSortSettings(raw: string | null): SortSettings {
  if (!raw) return DEFAULT_SORT
  try {
    const parsed = JSON.parse(raw) as Partial<SortSettings>
    const criterion: SortCriterion =
      parsed.criterion === 'date' ? 'date' : 'name'
    const direction: SortDirection =
      parsed.direction === 'desc' ? 'desc' : 'asc'
    return { criterion, direction }
  } catch {
    return DEFAULT_SORT
  }
}

type Storage = Pick<globalThis.Storage, 'getItem' | 'setItem'>

export function loadSortSettings(
  repoFullName: string,
  storage: Storage = localStorage,
): SortSettings {
  return parseSortSettings(storage.getItem(sortSettingsStorageKey(repoFullName)))
}

export function saveSortSettings(
  repoFullName: string,
  settings: SortSettings,
  storage: Storage = localStorage,
): void {
  storage.setItem(sortSettingsStorageKey(repoFullName), JSON.stringify(settings))
}

// "name-asc" | "name-desc" | "date-asc" | "date-desc"
export function formatSortToken(settings: SortSettings): string {
  return `${settings.criterion}-${settings.direction}`
}

export function parseSortToken(raw: string | null | undefined): SortSettings | null {
  if (!raw) return null
  const [criterion, direction] = raw.split('-')
  if ((criterion !== 'name' && criterion !== 'date')) return null
  if (direction !== 'asc' && direction !== 'desc') return null
  return { criterion, direction }
}

export type SortableEntry = {
  name: string
  path: string
  type: 'tree' | 'blob'
  modifiedAt?: number | null
}

export function compareEntries(
  a: SortableEntry,
  b: SortableEntry,
  settings: SortSettings,
): number {
  if (a.type !== b.type) return a.type === 'tree' ? -1 : 1

  let cmp = 0
  if (settings.criterion === 'date') {
    const aTime = typeof a.modifiedAt === 'number' ? a.modifiedAt : null
    const bTime = typeof b.modifiedAt === 'number' ? b.modifiedAt : null
    if (aTime === null && bTime === null) cmp = 0
    else if (aTime === null) cmp = 1
    else if (bTime === null) cmp = -1
    else cmp = aTime - bTime
    if (cmp === 0) cmp = a.name.localeCompare(b.name, undefined, { sensitivity: 'base' })
  } else {
    cmp = a.name.localeCompare(b.name, undefined, { sensitivity: 'base' })
  }

  return settings.direction === 'asc' ? cmp : -cmp
}

export function sortTreeChildren(
  node: TreeNode,
  settings: SortSettings,
): TreeNode {
  const sortedChildren = [...node.children]
    .map((child) => sortTreeChildren(child, settings))
    .sort((a, b) => compareEntries(a, b, settings))
  return { ...node, children: sortedChildren }
}
