import { describe, expect, it } from 'vitest'
import { extractTagsFromMarkdown } from './tags'

describe('extractTagsFromMarkdown', () => {
  it('collects hashtags written as #tag in prose', () => {
    expect(extractTagsFromMarkdown('Meeting about #synapse and #web')).toEqual([
      'synapse',
      'web',
    ])
  })

  it('deduplicates tags while preserving first-seen order', () => {
    expect(extractTagsFromMarkdown('#a #b #a')).toEqual(['a', 'b'])
  })

  it('returns an empty list when no tags are present', () => {
    expect(extractTagsFromMarkdown('No hashtags here.')).toEqual([])
  })

  it('does not treat ATX headings as tags', () => {
    expect(extractTagsFromMarkdown('# Heading\n\nBody')).toEqual([])
  })

  it('does not treat mid-word hash fragments as tags', () => {
    expect(extractTagsFromMarkdown('issue#231 is tricky')).toEqual([])
  })

  it('supports unicode letters in tags', () => {
    expect(extractTagsFromMarkdown('Note #café #日本語')).toEqual(['café', '日本語'])
  })
})
