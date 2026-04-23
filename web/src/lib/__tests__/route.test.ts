import { describe, expect, it } from 'vitest'
import {
  formatRoute,
  parseRoute,
  routeFile,
  routeFolder,
  routeQuery,
  routeRepo,
} from '../route'

describe('parseRoute', () => {
  it('treats empty path as picker with empty query', () => {
    expect(parseRoute('/')).toEqual({ kind: 'picker', query: {} })
    expect(parseRoute('')).toEqual({ kind: 'picker', query: {} })
  })
  it('treats single segment as picker', () => {
    expect(parseRoute('/owner')).toEqual({ kind: 'picker', query: {} })
  })
  it('recognizes repo root without mode', () => {
    expect(parseRoute('/o/r')).toEqual({
      kind: 'repo',
      owner: 'o',
      repo: 'r',
      query: {},
    })
  })
  it('recognizes tree with nested folder', () => {
    expect(parseRoute('/o/r/tree/notes/deep')).toEqual({
      kind: 'folder',
      owner: 'o',
      repo: 'r',
      folder: 'notes/deep',
      query: {},
    })
  })
  it('falls back to repo root for /tree with no folder', () => {
    expect(parseRoute('/o/r/tree')).toEqual({
      kind: 'repo',
      owner: 'o',
      repo: 'r',
      query: {},
    })
  })
  it('recognizes blob with nested file', () => {
    expect(parseRoute('/o/r/blob/notes/deep/x.md')).toEqual({
      kind: 'file',
      owner: 'o',
      repo: 'r',
      file: 'notes/deep/x.md',
      query: {},
    })
  })
  it('decodes percent-encoded segments', () => {
    expect(parseRoute('/o/r/blob/a%20b/c.md')).toEqual({
      kind: 'file',
      owner: 'o',
      repo: 'r',
      file: 'a b/c.md',
      query: {},
    })
  })
  it('ignores trailing slashes', () => {
    expect(parseRoute('/o/r/tree/notes/')).toEqual({
      kind: 'folder',
      owner: 'o',
      repo: 'r',
      folder: 'notes',
      query: {},
    })
  })
  it('parses query string', () => {
    expect(parseRoute('/o/r?sort=date-desc')).toEqual({
      kind: 'repo',
      owner: 'o',
      repo: 'r',
      query: { sort: 'date-desc' },
    })
  })
  it('parses multi-key query string', () => {
    const r = parseRoute('/o/r?sort=name-asc&x=1')
    if (r.kind !== 'repo') throw new Error('expected repo')
    expect(r.query).toEqual({ sort: 'name-asc', x: '1' })
  })
  it('recognizes /today', () => {
    expect(parseRoute('/o/r/today')).toEqual({
      kind: 'today',
      owner: 'o',
      repo: 'r',
      query: {},
    })
  })

  it('/today ignores trailing segments', () => {
    // Any extra segments after /today are dropped; it's a magic path.
    expect(parseRoute('/o/r/today/whatever')).toEqual({
      kind: 'today',
      owner: 'o',
      repo: 'r',
      query: {},
    })
  })

  it('strips hash fragments', () => {
    expect(parseRoute('/o/r?sort=name-asc#deep')).toEqual({
      kind: 'repo',
      owner: 'o',
      repo: 'r',
      query: { sort: 'name-asc' },
    })
  })
})

describe('formatRoute', () => {
  it('encodes slashes as path separators, not %2F', () => {
    expect(
      formatRoute({
        kind: 'file',
        owner: 'o',
        repo: 'r',
        file: 'a/b c.md',
        query: {},
      }),
    ).toBe('/o/r/blob/a/b%20c.md')
  })
  it('picker is /', () => {
    expect(formatRoute({ kind: 'picker', query: {} })).toBe('/')
  })
  it('repo root has no trailing tree', () => {
    expect(
      formatRoute({ kind: 'repo', owner: 'o', repo: 'r', query: {} }),
    ).toBe('/o/r')
  })
  it('folder route uses tree', () => {
    expect(
      formatRoute({
        kind: 'folder',
        owner: 'o',
        repo: 'r',
        folder: 'notes',
        query: {},
      }),
    ).toBe('/o/r/tree/notes')
  })
  it('folder with empty string collapses to repo root', () => {
    expect(
      formatRoute({
        kind: 'folder',
        owner: 'o',
        repo: 'r',
        folder: '',
        query: {},
      }),
    ).toBe('/o/r')
  })
  it('today route formats as /o/r/today', () => {
    expect(
      formatRoute({ kind: 'today', owner: 'o', repo: 'r', query: {} }),
    ).toBe('/o/r/today')
  })

  it('serializes query string, stable key order', () => {
    expect(
      formatRoute({
        kind: 'repo',
        owner: 'o',
        repo: 'r',
        query: { sort: 'date-desc', a: '1' },
      }),
    ).toBe('/o/r?a=1&sort=date-desc')
  })
  it('preserves empty string query values (they carry semantic meaning)', () => {
    expect(
      formatRoute({
        kind: 'repo',
        owner: 'o',
        repo: 'r',
        query: { folder: '' },
      }),
    ).toBe('/o/r?folder=')
  })
})

describe('parse/format round trip', () => {
  it('folder route', () => {
    const r = parseRoute('/o/r/tree/a/b')
    expect(parseRoute(formatRoute(r))).toEqual(r)
  })
  it('file route with spaces', () => {
    const r = parseRoute('/o/r/blob/a%20b/c.md')
    expect(parseRoute(formatRoute(r))).toEqual(r)
  })
  it('query preserved', () => {
    const r = parseRoute('/o/r/blob/a.md?sort=date-asc')
    expect(parseRoute(formatRoute(r))).toEqual(r)
  })
})

describe('derived helpers', () => {
  it('routeRepo returns null for picker', () => {
    expect(routeRepo({ kind: 'picker', query: {} })).toBeNull()
  })
  it('routeFolder strips filename from a file route', () => {
    expect(
      routeFolder({
        kind: 'file',
        owner: 'o',
        repo: 'r',
        file: 'notes/a.md',
        query: {},
      }),
    ).toBe('notes')
    expect(
      routeFolder({
        kind: 'file',
        owner: 'o',
        repo: 'r',
        file: 'a.md',
        query: {},
      }),
    ).toBe('')
  })
  it('routeFile is only set for file kind', () => {
    expect(
      routeFile({
        kind: 'folder',
        owner: 'o',
        repo: 'r',
        folder: 'a',
        query: {},
      }),
    ).toBeNull()
    expect(
      routeFile({
        kind: 'file',
        owner: 'o',
        repo: 'r',
        file: 'a.md',
        query: {},
      }),
    ).toBe('a.md')
  })
  it('routeQuery returns the query record', () => {
    const r = parseRoute('/o/r?sort=date-asc')
    expect(routeQuery(r)).toEqual({ sort: 'date-asc' })
  })
})
