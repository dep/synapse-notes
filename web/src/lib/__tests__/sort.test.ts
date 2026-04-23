import { beforeEach, describe, expect, it } from 'vitest'
import type { TreeNode } from '../../github/tree'
import {
  DEFAULT_SORT,
  compareEntries,
  formatSortToken,
  loadSortSettings,
  parseSortSettings,
  parseSortToken,
  saveSortSettings,
  sortSettingsStorageKey,
  sortTreeChildren,
  type SortableEntry,
  type SortSettings,
} from '../sort'

const REPO = 'owner/repo'

const entry = (
  name: string,
  type: 'tree' | 'blob',
  modifiedAt?: number | null,
): SortableEntry => ({ name, path: name, type, modifiedAt })

describe('parseSortSettings', () => {
  it('returns default for null/invalid', () => {
    expect(parseSortSettings(null)).toEqual(DEFAULT_SORT)
    expect(parseSortSettings('not json')).toEqual(DEFAULT_SORT)
  })

  it('coerces unknown values to defaults', () => {
    expect(parseSortSettings('{"criterion":"weird","direction":"sideways"}')).toEqual(
      DEFAULT_SORT,
    )
  })

  it('parses valid values', () => {
    expect(parseSortSettings('{"criterion":"date","direction":"desc"}')).toEqual({
      criterion: 'date',
      direction: 'desc',
    })
  })
})

describe('sort settings persistence', () => {
  beforeEach(() => localStorage.clear?.())

  it('returns defaults for an unknown repo', () => {
    expect(loadSortSettings(REPO)).toEqual(DEFAULT_SORT)
  })

  it('persists and reads back', () => {
    const settings: SortSettings = { criterion: 'date', direction: 'desc' }
    saveSortSettings(REPO, settings)
    expect(loadSortSettings(REPO)).toEqual(settings)
  })

  it('scopes by repo', () => {
    saveSortSettings('owner/a', { criterion: 'date', direction: 'desc' })
    expect(loadSortSettings('owner/b')).toEqual(DEFAULT_SORT)
  })

  it('uses a predictable key', () => {
    expect(sortSettingsStorageKey(REPO)).toBe(`synapse_sort:${REPO}`)
  })
})

describe('sort token', () => {
  it('formats as criterion-direction', () => {
    expect(formatSortToken({ criterion: 'name', direction: 'asc' })).toBe('name-asc')
    expect(formatSortToken({ criterion: 'date', direction: 'desc' })).toBe('date-desc')
  })

  it('parses valid tokens', () => {
    expect(parseSortToken('name-asc')).toEqual({ criterion: 'name', direction: 'asc' })
    expect(parseSortToken('date-desc')).toEqual({ criterion: 'date', direction: 'desc' })
  })

  it('returns null for invalid or missing', () => {
    expect(parseSortToken(null)).toBeNull()
    expect(parseSortToken('')).toBeNull()
    expect(parseSortToken('bogus')).toBeNull()
    expect(parseSortToken('name')).toBeNull()
    expect(parseSortToken('name-sideways')).toBeNull()
    expect(parseSortToken('weird-asc')).toBeNull()
  })

  it('roundtrips for every combination', () => {
    const all: SortSettings[] = [
      { criterion: 'name', direction: 'asc' },
      { criterion: 'name', direction: 'desc' },
      { criterion: 'date', direction: 'asc' },
      { criterion: 'date', direction: 'desc' },
    ]
    for (const s of all) {
      expect(parseSortToken(formatSortToken(s))).toEqual(s)
    }
  })
})

describe('compareEntries', () => {
  it('always groups folders before files', () => {
    const folder = entry('z-folder', 'tree')
    const file = entry('a-file.md', 'blob')
    expect(compareEntries(folder, file, { criterion: 'name', direction: 'asc' })).toBeLessThan(0)
    expect(compareEntries(folder, file, { criterion: 'name', direction: 'desc' })).toBeLessThan(0)
    expect(compareEntries(folder, file, { criterion: 'date', direction: 'asc' })).toBeLessThan(0)
  })

  it('sorts by name case-insensitively', () => {
    const a = entry('Apple.md', 'blob')
    const b = entry('banana.md', 'blob')
    expect(compareEntries(a, b, { criterion: 'name', direction: 'asc' })).toBeLessThan(0)
    expect(compareEntries(a, b, { criterion: 'name', direction: 'desc' })).toBeGreaterThan(0)
  })

  it('sorts by date asc = oldest first', () => {
    const older = entry('old.md', 'blob', 1000)
    const newer = entry('new.md', 'blob', 2000)
    expect(compareEntries(older, newer, { criterion: 'date', direction: 'asc' })).toBeLessThan(0)
    expect(compareEntries(older, newer, { criterion: 'date', direction: 'desc' })).toBeGreaterThan(0)
  })

  it('falls back to name when dates tie', () => {
    const a = entry('a.md', 'blob', 100)
    const b = entry('b.md', 'blob', 100)
    expect(compareEntries(a, b, { criterion: 'date', direction: 'asc' })).toBeLessThan(0)
  })

  it('sorts undated entries last when sorting by date', () => {
    const dated = entry('dated.md', 'blob', 100)
    const undated = entry('undated.md', 'blob', null)
    expect(compareEntries(dated, undated, { criterion: 'date', direction: 'asc' })).toBeLessThan(0)
    // direction still flips when both missing? That's degenerate — tested above via tie-break to name.
  })
})

describe('sortTreeChildren', () => {
  const tree: TreeNode = {
    name: '',
    path: '',
    type: 'tree',
    children: [
      { name: 'z.md', path: 'z.md', type: 'blob', children: [] },
      {
        name: 'notes',
        path: 'notes',
        type: 'tree',
        children: [
          { name: 'b.md', path: 'notes/b.md', type: 'blob', children: [] },
          { name: 'a.md', path: 'notes/a.md', type: 'blob', children: [] },
        ],
      },
      { name: 'a.md', path: 'a.md', type: 'blob', children: [] },
    ],
  }

  it('sorts by name asc by default, folders first', () => {
    const sorted = sortTreeChildren(tree, DEFAULT_SORT)
    expect(sorted.children.map((c) => c.name)).toEqual(['notes', 'a.md', 'z.md'])
    expect(sorted.children[0].children.map((c) => c.name)).toEqual(['a.md', 'b.md'])
  })

  it('reverses when direction is desc', () => {
    const sorted = sortTreeChildren(tree, { criterion: 'name', direction: 'desc' })
    expect(sorted.children.map((c) => c.name)).toEqual(['notes', 'z.md', 'a.md'])
  })
})
