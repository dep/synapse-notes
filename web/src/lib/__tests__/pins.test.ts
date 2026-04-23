import { beforeEach, describe, expect, it } from 'vitest'
import {
  createPinsStore,
  parsePins,
  pinsStorageKey,
} from '../pins'

const REPO = 'owner/repo'

describe('pinsStorageKey', () => {
  it('scopes by repo full name', () => {
    expect(pinsStorageKey('a/b')).toBe('synapse_pins:a/b')
    expect(pinsStorageKey('x/y')).not.toBe(pinsStorageKey('a/b'))
  })
})

describe('parsePins', () => {
  it('returns [] for null, invalid JSON, or non-array', () => {
    expect(parsePins(null)).toEqual([])
    expect(parsePins('not json')).toEqual([])
    expect(parsePins('{"foo":1}')).toEqual([])
  })

  it('filters out entries without valid path/kind', () => {
    const raw = JSON.stringify([
      { path: 'a.md', kind: 'file' },
      { path: '', kind: 'file' },
      { path: 'b', kind: 'mystery' },
      { kind: 'file' },
      null,
      { path: 'c/', kind: 'folder' },
    ])
    expect(parsePins(raw)).toEqual([
      { path: 'a.md', kind: 'file' },
      { path: 'c/', kind: 'folder' },
    ])
  })

  it('dedupes entries with the same path', () => {
    const raw = JSON.stringify([
      { path: 'a.md', kind: 'file' },
      { path: 'a.md', kind: 'folder' },
    ])
    expect(parsePins(raw)).toEqual([{ path: 'a.md', kind: 'file' }])
  })
})

describe('createPinsStore', () => {
  beforeEach(() => localStorage.clear?.())

  it('starts empty', () => {
    expect(createPinsStore(REPO).list()).toEqual([])
  })

  it('pins and unpins a file', () => {
    const store = createPinsStore(REPO)
    store.pin({ path: 'notes/a.md', kind: 'file' })
    expect(store.isPinned('notes/a.md')).toBe(true)
    store.unpin('notes/a.md')
    expect(store.isPinned('notes/a.md')).toBe(false)
    expect(localStorage.getItem(pinsStorageKey(REPO))).toBeNull()
  })

  it('does not duplicate when pinning the same path twice', () => {
    const store = createPinsStore(REPO)
    store.pin({ path: 'a.md', kind: 'file' })
    store.pin({ path: 'a.md', kind: 'file' })
    expect(store.list()).toHaveLength(1)
  })

  it('preserves insertion order', () => {
    const store = createPinsStore(REPO)
    store.pin({ path: 'c', kind: 'folder' })
    store.pin({ path: 'a.md', kind: 'file' })
    store.pin({ path: 'b.md', kind: 'file' })
    expect(store.list().map((p) => p.path)).toEqual(['c', 'a.md', 'b.md'])
  })

  it('scopes pins by repo', () => {
    const a = createPinsStore('owner/a')
    const b = createPinsStore('owner/b')
    a.pin({ path: 'x.md', kind: 'file' })
    expect(b.list()).toEqual([])
    expect(a.list()).toHaveLength(1)
  })

  it('renames a pinned path in place', () => {
    const store = createPinsStore(REPO)
    store.pin({ path: 'old.md', kind: 'file' })
    store.rename('old.md', 'new.md')
    expect(store.list()).toEqual([{ path: 'new.md', kind: 'file' }])
  })

  it('remove and unpin behave the same for a pinned path', () => {
    const store = createPinsStore(REPO)
    store.pin({ path: 'a.md', kind: 'file' })
    expect(store.remove('a.md')).toEqual([])
    expect(store.list()).toEqual([])
  })

  it('persists through a fresh store instance', () => {
    createPinsStore(REPO).pin({ path: 'a.md', kind: 'file' })
    const fresh = createPinsStore(REPO)
    expect(fresh.list()).toEqual([{ path: 'a.md', kind: 'file' }])
  })
})
