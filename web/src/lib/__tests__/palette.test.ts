import { describe, expect, it } from 'vitest'
import type { TreeNode } from '../../github/tree'
import { collectPaletteItems, filterItems, scoreItem } from '../palette'

const tree: TreeNode = {
  name: '',
  path: '',
  type: 'tree',
  children: [
    {
      name: 'notes',
      path: 'notes',
      type: 'tree',
      children: [
        { name: 'alpha.md', path: 'notes/alpha.md', type: 'blob', children: [] },
        {
          name: 'deep',
          path: 'notes/deep',
          type: 'tree',
          children: [
            {
              name: 'very-long-name.md',
              path: 'notes/deep/very-long-name.md',
              type: 'blob',
              children: [],
            },
          ],
        },
      ],
    },
    { name: 'README.md', path: 'README.md', type: 'blob', children: [] },
  ],
}

describe('collectPaletteItems', () => {
  it('walks every folder and file, including nested', () => {
    const items = collectPaletteItems(tree)
    expect(items.map((i) => `${i.kind}:${i.path}`).sort()).toEqual(
      [
        'file:README.md',
        'file:notes/alpha.md',
        'file:notes/deep/very-long-name.md',
        'folder:notes',
        'folder:notes/deep',
      ].sort(),
    )
  })

  it('captures parent path', () => {
    const items = collectPaletteItems(tree)
    const deepFile = items.find(
      (i) => i.path === 'notes/deep/very-long-name.md',
    )!
    expect(deepFile.parentPath).toBe('notes/deep')
    const readme = items.find((i) => i.path === 'README.md')!
    expect(readme.parentPath).toBe('')
  })
})

describe('scoreItem', () => {
  const item = (path: string, kind: 'file' | 'folder' = 'file') => {
    const slash = path.lastIndexOf('/')
    return {
      kind,
      path,
      name: slash >= 0 ? path.slice(slash + 1) : path,
      parentPath: slash >= 0 ? path.slice(0, slash) : '',
    }
  }

  it('exact name beats prefix beats contains beats subsequence', () => {
    const exact = scoreItem(item('foo.md'), 'foo.md')
    const prefix = scoreItem(item('foobar.md'), 'foo')
    const contains = scoreItem(item('xyzfooabc.md'), 'foo')
    const sub = scoreItem(item('f-o-o.md'), 'foo')
    expect(exact).toBeGreaterThan(prefix)
    expect(prefix).toBeGreaterThan(contains)
    expect(contains).toBeGreaterThan(sub)
  })

  it('returns 0 for no match', () => {
    expect(scoreItem(item('nothing.md'), 'zzzzzz')).toBe(0)
  })

  it('prefers shorter names on close matches', () => {
    const shortS = scoreItem(item('foo.md'), 'foo')
    const longS = scoreItem(item('foo-bar-baz.md'), 'foo')
    expect(shortS).toBeGreaterThan(longS)
  })

  it('prefers files over folders when base scores tie', () => {
    const file = scoreItem(item('foo', 'file'), 'foo')
    const folder = scoreItem(item('foo', 'folder'), 'foo')
    expect(file).toBeGreaterThan(folder)
  })

  it('path match scores below name match', () => {
    const nameContains = scoreItem(item('hello/notes.md'), 'notes')
    const pathOnly = scoreItem(item('notes/zeta.md'), 'not')
    expect(nameContains).toBeGreaterThan(pathOnly)
  })

  it('is case-insensitive', () => {
    const items = item('README.md')
    expect(scoreItem(items, 'readme')).toBeGreaterThan(0)
    expect(scoreItem(items, 'ReAdMe')).toBeGreaterThan(0)
  })
})

describe('filterItems', () => {
  const items = collectPaletteItems(tree)

  it('returns a bounded slice for empty query', () => {
    const out = filterItems(items, '', 2)
    expect(out).toHaveLength(2)
  })

  it('ranks exact-name match first', () => {
    const out = filterItems(items, 'alpha.md')
    expect(out[0].path).toBe('notes/alpha.md')
  })

  it('ranks name prefix above path substring', () => {
    const out = filterItems(items, 'alp')
    expect(out[0].path).toBe('notes/alpha.md')
  })

  it('excludes items with zero score', () => {
    const out = filterItems(items, 'zzzzzzzzz')
    expect(out).toEqual([])
  })

  it('respects limit', () => {
    const out = filterItems(items, 'a', 2)
    expect(out.length).toBeLessThanOrEqual(2)
  })

  it('uses path to tiebreak identical scores', () => {
    const many = [
      { kind: 'file' as const, path: 'z/foo.md', name: 'foo.md', parentPath: 'z' },
      { kind: 'file' as const, path: 'a/foo.md', name: 'foo.md', parentPath: 'a' },
    ]
    const out = filterItems(many, 'foo.md')
    expect(out[0].path).toBe('a/foo.md')
    expect(out[1].path).toBe('z/foo.md')
  })
})
