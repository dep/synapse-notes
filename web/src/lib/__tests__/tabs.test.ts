import { beforeEach, describe, expect, it } from 'vitest'
import {
  EMPTY_TABS,
  activateByIndex,
  activateTab,
  activeTab,
  closeTab,
  findTabByPath,
  loadTabs,
  openInActive,
  openInNewTab,
  parseTabs,
  renamePath,
  saveTabs,
  tabsStorageKey,
} from '../tabs'

describe('openInActive', () => {
  it('creates a first tab when empty', () => {
    const s = openInActive(EMPTY_TABS, 'a.md')
    expect(s.tabs).toHaveLength(1)
    expect(s.tabs[0].path).toBe('a.md')
    expect(s.activeId).toBe(s.tabs[0].id)
  })

  it('replaces the active tab path when path is new', () => {
    let s = openInActive(EMPTY_TABS, 'a.md')
    s = openInActive(s, 'b.md')
    expect(s.tabs).toHaveLength(1)
    expect(s.tabs[0].path).toBe('b.md')
  })

  it('activates existing tab if the path is already open', () => {
    let s = openInActive(EMPTY_TABS, 'a.md')
    s = openInNewTab(s, 'b.md')
    const firstId = s.tabs[0].id
    s = openInActive(s, 'a.md')
    expect(s.tabs).toHaveLength(2)
    expect(s.activeId).toBe(firstId)
  })
})

describe('openInNewTab', () => {
  it('inserts a new tab after the active one', () => {
    let s = openInActive(EMPTY_TABS, 'a.md')
    s = openInNewTab(s, 'b.md')
    expect(s.tabs.map((t) => t.path)).toEqual(['a.md', 'b.md'])
    expect(s.activeId).toBe(s.tabs[1].id)
  })

  it('does not duplicate when path is already in a tab', () => {
    let s = openInActive(EMPTY_TABS, 'a.md')
    s = openInNewTab(s, 'b.md')
    s = openInNewTab(s, 'a.md')
    expect(s.tabs.map((t) => t.path)).toEqual(['a.md', 'b.md'])
    expect(s.activeId).toBe(s.tabs[0].id)
  })

  it('works on empty state', () => {
    const s = openInNewTab(EMPTY_TABS, 'a.md')
    expect(s.tabs).toHaveLength(1)
    expect(s.activeId).toBe(s.tabs[0].id)
  })
})

describe('activateTab', () => {
  it('switches active id', () => {
    let s = openInActive(EMPTY_TABS, 'a.md')
    s = openInNewTab(s, 'b.md')
    const firstId = s.tabs[0].id
    s = activateTab(s, firstId)
    expect(s.activeId).toBe(firstId)
  })

  it('is a no-op for unknown id', () => {
    const s = openInActive(EMPTY_TABS, 'a.md')
    const after = activateTab(s, 'nope')
    expect(after).toBe(s)
  })
})

describe('activateByIndex', () => {
  it('activates by 1-based index', () => {
    let s = openInActive(EMPTY_TABS, 'a.md')
    s = openInNewTab(s, 'b.md')
    s = openInNewTab(s, 'c.md')
    s = activateByIndex(s, 2)
    expect(activeTab(s)?.path).toBe('b.md')
  })

  it('is a no-op for out-of-range index', () => {
    const s = openInActive(EMPTY_TABS, 'a.md')
    expect(activateByIndex(s, 0)).toBe(s)
    expect(activateByIndex(s, 99)).toBe(s)
  })
})

describe('closeTab', () => {
  it('removes the tab and picks a neighbor when active', () => {
    let s = openInActive(EMPTY_TABS, 'a.md')
    s = openInNewTab(s, 'b.md')
    s = openInNewTab(s, 'c.md') // active = c
    const cId = s.tabs[2].id
    s = closeTab(s, cId)
    expect(s.tabs.map((t) => t.path)).toEqual(['a.md', 'b.md'])
    // c was last, so we fall back to the new last tab = b
    expect(activeTab(s)?.path).toBe('b.md')
  })

  it('activates the right-side neighbor when a middle tab closes', () => {
    let s = openInActive(EMPTY_TABS, 'a.md')
    s = openInNewTab(s, 'b.md')
    s = openInNewTab(s, 'c.md')
    // active = c; switch to b
    s = activateTab(s, s.tabs[1].id)
    // close b -> active should become c (next right)
    s = closeTab(s, s.tabs[1].id)
    expect(s.tabs.map((t) => t.path)).toEqual(['a.md', 'c.md'])
    expect(activeTab(s)?.path).toBe('c.md')
  })

  it('sets activeId null when last tab closes', () => {
    let s = openInActive(EMPTY_TABS, 'a.md')
    s = closeTab(s, s.tabs[0].id)
    expect(s.tabs).toEqual([])
    expect(s.activeId).toBeNull()
  })

  it('is a no-op for unknown id', () => {
    const s = openInActive(EMPTY_TABS, 'a.md')
    expect(closeTab(s, 'nope')).toBe(s)
  })
})

describe('renamePath', () => {
  it('updates every tab with the old path', () => {
    let s = openInActive(EMPTY_TABS, 'old.md')
    s = openInNewTab(s, 'b.md')
    s = renamePath(s, 'old.md', 'new.md')
    expect(s.tabs.map((t) => t.path)).toEqual(['new.md', 'b.md'])
  })

  it('is a no-op when no tab matches', () => {
    const s = openInActive(EMPTY_TABS, 'a.md')
    expect(renamePath(s, 'x.md', 'y.md')).toBe(s)
  })
})

describe('findTabByPath / activeTab', () => {
  it('finds by path', () => {
    let s = openInActive(EMPTY_TABS, 'a.md')
    s = openInNewTab(s, 'b.md')
    expect(findTabByPath(s, 'b.md')?.path).toBe('b.md')
    expect(findTabByPath(s, 'z.md')).toBeNull()
  })

  it('activeTab returns null on empty state', () => {
    expect(activeTab(EMPTY_TABS)).toBeNull()
  })
})

describe('persistence', () => {
  beforeEach(() => localStorage.clear?.())

  it('roundtrips', () => {
    let s = openInActive(EMPTY_TABS, 'a.md')
    s = openInNewTab(s, 'b.md')
    saveTabs('o/r', s)
    const loaded = loadTabs('o/r')
    expect(loaded.tabs.map((t) => t.path)).toEqual(['a.md', 'b.md'])
    expect(loaded.activeId).toBe(s.activeId)
  })

  it('removes the key when empty', () => {
    saveTabs('o/r', openInActive(EMPTY_TABS, 'a.md'))
    saveTabs('o/r', EMPTY_TABS)
    expect(localStorage.getItem(tabsStorageKey('o/r'))).toBeNull()
  })

  it('scopes by repo', () => {
    saveTabs('o/a', openInActive(EMPTY_TABS, 'a.md'))
    expect(loadTabs('o/b')).toEqual(EMPTY_TABS)
  })
})

describe('parseTabs', () => {
  it('returns empty for null / invalid JSON / wrong shape', () => {
    expect(parseTabs(null)).toEqual(EMPTY_TABS)
    expect(parseTabs('not json')).toEqual(EMPTY_TABS)
    expect(parseTabs('123')).toEqual(EMPTY_TABS)
    expect(parseTabs('{"tabs": "not an array"}')).toEqual(EMPTY_TABS)
  })

  it('drops malformed tab entries', () => {
    const raw = JSON.stringify({
      tabs: [
        { id: 'a', path: 'a.md' },
        { id: '', path: 'b.md' },
        { id: 'c', path: '' },
        null,
        { path: 'no-id.md' },
      ],
      activeId: 'a',
    })
    const out = parseTabs(raw)
    expect(out.tabs.map((t) => t.id)).toEqual(['a'])
  })

  it('picks a fallback activeId when saved id is gone', () => {
    const raw = JSON.stringify({
      tabs: [{ id: 'a', path: 'a.md' }],
      activeId: 'gone',
    })
    expect(parseTabs(raw).activeId).toBe('a')
  })
})
