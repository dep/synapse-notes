import { describe, expect, it } from 'vitest'
import { buildMentionContext, parseMentions } from '../mentions'

describe('parseMentions', () => {
  it('returns empty array when no mentions', () => {
    expect(parseMentions('make this more concise')).toEqual([])
  })

  it('parses a single mention', () => {
    expect(parseMentions('rewrite using style from @templates/style.md')).toEqual([
      'templates/style.md',
    ])
  })

  it('parses multiple mentions', () => {
    expect(
      parseMentions('see @docs/a.md and @notes/b.md for reference'),
    ).toEqual(['docs/a.md', 'notes/b.md'])
  })

  it('deduplicates repeated mentions', () => {
    expect(parseMentions('@foo.md and @foo.md again')).toEqual(['foo.md'])
  })

  it('handles @ at start of string', () => {
    expect(parseMentions('@README.md summarize this')).toEqual(['README.md'])
  })

  it('does not include spaces in bare paths', () => {
    expect(parseMentions('@file.md and some text')).toEqual(['file.md'])
  })

  it('parses backtick-quoted paths with spaces', () => {
    expect(
      parseMentions('summarize @`Daily Notes/2026-04-21.md` please'),
    ).toEqual(['Daily Notes/2026-04-21.md'])
  })

  it('handles backtick-quoted path at start of string', () => {
    expect(parseMentions('@`My Notes/foo.md` summary')).toEqual([
      'My Notes/foo.md',
    ])
  })

  it('mixes bare and quoted mentions', () => {
    expect(
      parseMentions('see @`Daily Notes/today.md` and @templates/style.md'),
    ).toEqual(['Daily Notes/today.md', 'templates/style.md'])
  })
})

describe('buildMentionContext', () => {
  it('returns empty string with no files', () => {
    expect(buildMentionContext({})).toBe('')
  })

  it('formats a single file block', () => {
    const ctx = buildMentionContext({ 'notes/a.md': 'hello' })
    expect(ctx).toBe('@notes/a.md:\n---\nhello\n---')
  })

  it('separates multiple files with a blank line', () => {
    const ctx = buildMentionContext({ 'a.md': 'aaa', 'b.md': 'bbb' })
    expect(ctx).toContain('@a.md:\n---\naaa\n---')
    expect(ctx).toContain('@b.md:\n---\nbbb\n---')
    expect(ctx.indexOf('---\n\n@')).toBeGreaterThan(-1)
  })
})
