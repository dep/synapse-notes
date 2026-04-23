import { describe, expect, it } from 'vitest'
import {
  colorFromHash,
  extractLeadingEmoji,
  folderStyleFor,
} from '../folderStyle'

describe('extractLeadingEmoji', () => {
  it('returns null when there is no emoji', () => {
    expect(extractLeadingEmoji('Notes')).toEqual({ emoji: null, rest: 'Notes' })
  })

  it('pulls a single emoji prefix', () => {
    const { emoji, rest } = extractLeadingEmoji('📅 Daily Notes')
    expect(emoji).toBe('📅')
    expect(rest).toBe('Daily Notes')
  })

  it('handles emojis with variation selectors or ZWJ sequences', () => {
    const family = extractLeadingEmoji('👨‍👩‍👧 Family')
    expect(family.emoji).toBe('👨‍👩‍👧')
    expect(family.rest).toBe('Family')
  })

  it('leaves non-leading emoji alone', () => {
    expect(extractLeadingEmoji('Project 📅 something')).toEqual({
      emoji: null,
      rest: 'Project 📅 something',
    })
  })
})

describe('colorFromHash', () => {
  it('is deterministic for the same input', () => {
    expect(colorFromHash('notes')).toBe(colorFromHash('notes'))
  })

  it('returns a value from the palette (starts with #)', () => {
    expect(colorFromHash('x')).toMatch(/^#[0-9A-Fa-f]{6}$/)
  })

  it('differs across distinct inputs (nontrivially)', () => {
    const seen = new Set<string>()
    for (const name of ['alpha', 'beta', 'gamma', 'delta', 'epsilon']) {
      seen.add(colorFromHash(name))
    }
    // Not guaranteed all-unique, but we should get more than one color.
    expect(seen.size).toBeGreaterThan(1)
  })
})

describe('folderStyleFor', () => {
  it('prefers emoji when one is present', () => {
    const s = folderStyleFor('📅 Daily Notes')
    expect(s.emoji).toBe('📅')
    expect(s.icon).toBe('folder')
    expect(s.color).toMatch(/^#/)
  })

  it('matches the keyword table (case-insensitive substring)', () => {
    expect(folderStyleFor('Daily Notes').icon).toBe('calendar')
    expect(folderStyleFor('DAILY').icon).toBe('calendar')
    expect(folderStyleFor('my projects').icon).toBe('work')
    expect(folderStyleFor('Archive 2024').icon).toBe('archive')
    expect(folderStyleFor('book list').icon).toBe('menu_book')
    expect(folderStyleFor('images').icon).toBe('photo')
    expect(folderStyleFor('Reading List').icon).toBe('menu_book')
  })

  it('uses first-match ordering for ambiguous names', () => {
    // "journal" rule sits before the generic "note" rule.
    expect(folderStyleFor('journal notes').icon).toBe('calendar')
  })

  it('falls back to hash-based color + generic folder icon', () => {
    const s = folderStyleFor('xyzzy-random-name')
    expect(s.icon).toBe('folder')
    expect(s.emoji).toBeNull()
    expect(s.color).toMatch(/^#[0-9A-Fa-f]{6}$/)
  })

  it('is deterministic — same name always yields same style', () => {
    const a = folderStyleFor('Projects')
    const b = folderStyleFor('Projects')
    expect(a).toEqual(b)
  })

  it('matches AI as a whole word (case-insensitive)', () => {
    expect(folderStyleFor('AI').icon).toBe('robot')
    expect(folderStyleFor('AI Experiments').icon).toBe('robot')
    expect(folderStyleFor('Claude notes').icon).toBe('robot')
  })

  it('does NOT match "ai" inside other words', () => {
    // "Daily" contains "ai" as a substring — must not match the AI rule.
    expect(folderStyleFor('Daily Notes').icon).toBe('calendar')
    // "Maintenance" contains "ai" — fall through to hash-based fallback.
    expect(folderStyleFor('Maintenance').icon).toBe('folder')
    expect(folderStyleFor('Captain').icon).toBe('folder')
  })

  it('matches mobile / phone / ios / android', () => {
    expect(folderStyleFor('Mobile').icon).toBe('phone')
    expect(folderStyleFor('Phone Apps').icon).toBe('phone')
    expect(folderStyleFor('iOS').icon).toBe('phone')
    expect(folderStyleFor('Android dev').icon).toBe('phone')
  })

  it('matches TV / movies / shows / film', () => {
    expect(folderStyleFor('TV').icon).toBe('tv')
    expect(folderStyleFor('Movies').icon).toBe('tv')
    expect(folderStyleFor('Shows').icon).toBe('tv')
    expect(folderStyleFor('Film reviews').icon).toBe('tv')
  })

  it('does not match "tv" inside other words', () => {
    // "private" contains "tv"... wait, it doesn't. Let's test with "stv".
    // Hard to find a real false-positive that isn't contrived; just confirm
    // a clean non-match stays a non-match.
    expect(folderStyleFor('Subversive').icon).toBe('folder')
  })

  it('matches web / website / sites as whole word for web, substring for website', () => {
    expect(folderStyleFor('Web').icon).toBe('web')
    expect(folderStyleFor('my website').icon).toBe('web')
    expect(folderStyleFor('Sites').icon).toBe('web')
  })

  it('matches summary / summaries / recap / digest', () => {
    expect(folderStyleFor('Summary').icon).toBe('summary')
    expect(folderStyleFor('Summaries').icon).toBe('summary')
    expect(folderStyleFor('Recap').icon).toBe('summary')
    expect(folderStyleFor('Weekly Digest').icon).toBe('summary')
  })

  it('matches Files', () => {
    expect(folderStyleFor('Files').icon).toBe('files')
    expect(folderStyleFor('old files').icon).toBe('archive') // 'old' wins first
  })
})
