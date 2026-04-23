import { describe, expect, it } from 'vitest'
import type { TreeNode } from '../../github/tree'
import {
  buildWikilinkIndex,
  parseWikilinks,
  resolveWikilink,
} from '../wikilinks'

const tree: TreeNode = {
  name: '',
  path: '',
  type: 'tree',
  children: [
    { name: 'README.md', path: 'README.md', type: 'blob', children: [] },
    {
      name: 'notes',
      path: 'notes',
      type: 'tree',
      children: [
        { name: 'Alpha.md', path: 'notes/Alpha.md', type: 'blob', children: [] },
        { name: 'Beta.mdx', path: 'notes/Beta.mdx', type: 'blob', children: [] },
        { name: 'logo.png', path: 'notes/logo.png', type: 'blob', children: [] },
      ],
    },
    {
      name: 'more',
      path: 'more',
      type: 'tree',
      children: [
        // Intentional duplicate stem to test "first match wins".
        { name: 'Alpha.md', path: 'more/Alpha.md', type: 'blob', children: [] },
      ],
    },
  ],
}

describe('parseWikilinks', () => {
  it('returns [] when nothing matches', () => {
    expect(parseWikilinks('plain text')).toEqual([])
  })

  it('extracts a simple link', () => {
    const [m] = parseWikilinks('see [[Alpha]] for details')
    expect(m.target).toBe('Alpha')
    expect(m.display).toBe('Alpha')
    expect(m.raw).toBe('[[Alpha]]')
    expect(m.index).toBe(4)
    expect(m.length).toBe(9)
  })

  it('extracts alias form', () => {
    const [m] = parseWikilinks('[[Alpha|my alpha]]')
    expect(m.target).toBe('Alpha')
    expect(m.display).toBe('my alpha')
  })

  it('ignores empty targets', () => {
    expect(parseWikilinks('[[ ]] [[|x]]')).toEqual([])
  })

  it('does not cross newlines', () => {
    expect(parseWikilinks('[[Alpha\nBeta]]')).toEqual([])
  })

  it('extracts multiple matches', () => {
    const out = parseWikilinks('[[one]] and [[two|2]] and [[three]]')
    expect(out.map((m) => m.target)).toEqual(['one', 'two', 'three'])
  })
})

describe('buildWikilinkIndex', () => {
  it('indexes every markdown file by lowercased stem', () => {
    const index = buildWikilinkIndex(tree)
    expect(index.get('readme')).toBe('README.md')
    expect(index.get('alpha')).toBe('notes/Alpha.md') // first match wins
    expect(index.get('beta')).toBe('notes/Beta.mdx')
  })

  it('skips non-markdown files', () => {
    const index = buildWikilinkIndex(tree)
    expect(index.has('logo')).toBe(false)
  })
})

describe('resolveWikilink', () => {
  const index = buildWikilinkIndex(tree)

  it('resolves a bare stem, case-insensitive', () => {
    expect(resolveWikilink('Alpha', index)).toBe('notes/Alpha.md')
    expect(resolveWikilink('alpha', index)).toBe('notes/Alpha.md')
    expect(resolveWikilink('ALPHA', index)).toBe('notes/Alpha.md')
  })

  it('resolves with explicit extension', () => {
    expect(resolveWikilink('Alpha.md', index)).toBe('notes/Alpha.md')
  })

  it('resolves relative-path hint using the tail stem', () => {
    expect(resolveWikilink('notes/Alpha', index)).toBe('notes/Alpha.md')
  })

  it('returns null for unknown targets', () => {
    expect(resolveWikilink('nope', index)).toBeNull()
    expect(resolveWikilink('', index)).toBeNull()
    expect(resolveWikilink('   ', index)).toBeNull()
  })
})
