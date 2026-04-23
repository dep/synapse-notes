import { describe, expect, it } from 'vitest'
import { defaultCommitMessage } from '../commit'

describe('defaultCommitMessage', () => {
  it('formats update/create/delete', () => {
    expect(defaultCommitMessage('update', 'a/b.md')).toBe('Update a/b.md')
    expect(defaultCommitMessage('create', 'new.md')).toBe('Create new.md')
    expect(defaultCommitMessage('delete', 'old.md')).toBe('Delete old.md')
  })

  it('formats rename with target', () => {
    expect(defaultCommitMessage('rename', 'a.md', 'b.md')).toBe('Rename a.md to b.md')
  })
})
