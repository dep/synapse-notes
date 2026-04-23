import { describe, expect, it } from 'vitest'
import { splitFrontmatter } from '../frontmatter'

describe('splitFrontmatter', () => {
  it('returns no frontmatter for plain markdown', () => {
    const out = splitFrontmatter('# Hello\n\nbody')
    expect(out.frontmatter).toBeNull()
    expect(out.body).toBe('# Hello\n\nbody')
  })

  it('extracts a basic block', () => {
    const src = '---\ntitle: Hi\ntags: [a, b]\n---\n# Heading\n'
    const out = splitFrontmatter(src)
    expect(out.frontmatter).toBe('title: Hi\ntags: [a, b]')
    expect(out.body).toBe('# Heading\n')
  })

  it('does not match when --- is not on the very first line', () => {
    const src = '\n---\ntitle: Hi\n---\nbody'
    const out = splitFrontmatter(src)
    expect(out.frontmatter).toBeNull()
    expect(out.body).toBe(src)
  })

  it('requires a closing fence', () => {
    const src = '---\ntitle: Hi\n# Heading'
    const out = splitFrontmatter(src)
    expect(out.frontmatter).toBeNull()
    expect(out.body).toBe(src)
  })

  it('handles an empty frontmatter block', () => {
    const src = '---\n---\n# Heading'
    const out = splitFrontmatter(src)
    expect(out.frontmatter).toBe('')
    expect(out.body).toBe('# Heading')
  })

  it('strips a leading BOM', () => {
    const src = '﻿---\ntitle: X\n---\ncontent'
    const out = splitFrontmatter(src)
    expect(out.frontmatter).toBe('title: X')
    expect(out.body).toBe('content')
  })

  it('does not consume content past the closing fence', () => {
    const src = '---\na: 1\n---\n\n---\nb: 2\n---\nrest'
    const out = splitFrontmatter(src)
    expect(out.frontmatter).toBe('a: 1')
    expect(out.body).toBe('\n---\nb: 2\n---\nrest')
  })

  it('handles CRLF line endings on the fence lines', () => {
    const src = '---\r\ntitle: X\r\n---\r\nbody'
    const out = splitFrontmatter(src)
    expect(out.frontmatter).toBe('title: X')
    expect(out.body).toBe('body')
  })
})
