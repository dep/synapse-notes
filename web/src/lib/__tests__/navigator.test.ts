import { describe, expect, it } from 'vitest'
import type { TreeNode } from '../../github/tree'
import {
  breadcrumbSegments,
  findFolderNode,
  parentFolder,
} from '../navigator'

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
        {
          name: 'deep',
          path: 'notes/deep',
          type: 'tree',
          children: [
            { name: 'x.md', path: 'notes/deep/x.md', type: 'blob', children: [] },
          ],
        },
      ],
    },
    { name: 'README.md', path: 'README.md', type: 'blob', children: [] },
  ],
}

describe('parentFolder', () => {
  it('returns empty for root or top-level', () => {
    expect(parentFolder('')).toBe('')
    expect(parentFolder('README.md')).toBe('')
  })
  it('strips last segment', () => {
    expect(parentFolder('a/b/c.md')).toBe('a/b')
    expect(parentFolder('a/b')).toBe('a')
  })
})

describe('breadcrumbSegments', () => {
  it('has just Root for empty folder', () => {
    expect(breadcrumbSegments('')).toEqual([{ label: 'Root', path: '' }])
  })
  it('accumulates paths', () => {
    expect(breadcrumbSegments('a/b/c')).toEqual([
      { label: 'Root', path: '' },
      { label: 'a', path: 'a' },
      { label: 'b', path: 'a/b' },
      { label: 'c', path: 'a/b/c' },
    ])
  })
})

describe('findFolderNode', () => {
  it('returns root for empty', () => {
    expect(findFolderNode(tree, '')).toBe(tree)
  })
  it('walks nested folders', () => {
    const notes = findFolderNode(tree, 'notes')!
    expect(notes.path).toBe('notes')
    const deep = findFolderNode(tree, 'notes/deep')!
    expect(deep.path).toBe('notes/deep')
  })
  it('returns null for non-existent or non-folder path', () => {
    expect(findFolderNode(tree, 'nope')).toBeNull()
    expect(findFolderNode(tree, 'README.md')).toBeNull()
  })
})
