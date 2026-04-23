import { describe, expect, it } from 'vitest'
import { applyWikilinks } from '../wikilinksHtml'
import type { WikilinkIndex } from '../wikilinks'

const index: WikilinkIndex = new Map([
  ['alpha', 'notes/Alpha.md'],
  ['readme', 'README.md'],
])

describe('applyWikilinks', () => {
  it('returns input unchanged when no brackets present', () => {
    const out = applyWikilinks('<p>hello world</p>', index)
    expect(out).toBe('<p>hello world</p>')
  })

  it('replaces resolved wikilinks with anchor + data attribute', () => {
    const out = applyWikilinks('<p>see [[Alpha]]</p>', index)
    expect(out).toContain('data-wikilink-path="notes/Alpha.md"')
    expect(out).toContain('class="wikilink wikilink-resolved"')
    expect(out).toContain('>Alpha<')
  })

  it('preserves alias display text', () => {
    const out = applyWikilinks('<p>[[Alpha|go see alpha]]</p>', index)
    expect(out).toContain('data-wikilink-path="notes/Alpha.md"')
    expect(out).toContain('>go see alpha<')
  })

  it('renders unresolved wikilinks as spans with title tooltip', () => {
    const out = applyWikilinks('<p>[[Ghost]]</p>', index)
    expect(out).toContain('class="wikilink wikilink-unresolved"')
    expect(out).toContain('No note found for')
    expect(out).toContain('>Ghost<')
    expect(out).not.toContain('data-wikilink-path')
  })

  it('does NOT rewrite wikilinks inside <code> or <pre>', () => {
    const html = '<p>x <code>[[Alpha]]</code> and <pre>[[Alpha]]</pre></p>'
    const out = applyWikilinks(html, index)
    expect(out).not.toContain('data-wikilink-path')
    expect(out).toContain('[[Alpha]]')
  })

  it('does NOT recurse into existing <a> tags', () => {
    const html = '<p><a href="https://example.com">text [[Alpha]]</a></p>'
    const out = applyWikilinks(html, index)
    expect(out).not.toContain('data-wikilink-path')
    expect(out).toContain('[[Alpha]]')
  })

  it('handles multiple links in one text node', () => {
    const out = applyWikilinks('<p>[[Alpha]] then [[README]]</p>', index)
    expect(out).toContain('data-wikilink-path="notes/Alpha.md"')
    expect(out).toContain('data-wikilink-path="README.md"')
  })

  it('preserves surrounding text', () => {
    const out = applyWikilinks('<p>before [[Alpha]] after</p>', index)
    expect(out).toMatch(/before\s+<a/)
    expect(out).toMatch(/<\/a>\s+after/)
  })
})
