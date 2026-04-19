import { describe, expect, it } from 'vitest'
import { findWikiLinks } from './wikiLinks'

describe('findWikiLinks', () => {
  it('finds basic [[note]] wiki links', () => {
    expect(findWikiLinks('See [[My Note]] for details.')).toEqual([
      { target: 'My Note', start: 4, end: 15 },
    ])
  })

  it('finds multiple wiki links in order', () => {
    expect(findWikiLinks('[[a]] then [[b]]')).toEqual([
      { target: 'a', start: 0, end: 5 },
      { target: 'b', start: 11, end: 16 },
    ])
  })

  it('supports display alias syntax [[target|alias]]', () => {
    expect(findWikiLinks('[[real page|shown text]]')).toEqual([
      { target: 'real page', start: 0, end: 24 },
    ])
  })

  it('trims whitespace around targets and aliases', () => {
    expect(findWikiLinks('[[  spaced  ]]')).toEqual([
      { target: 'spaced', start: 0, end: 14 },
    ])
  })

  it('returns an empty list when no wiki links exist', () => {
    expect(findWikiLinks('plain markdown')).toEqual([])
  })
})
