import { beforeEach, describe, expect, it } from 'vitest'
import {
  DEFAULT_PREVIEW_RATIO,
  MAX_PANE_RATIO,
  MIN_PANE_RATIO,
  clampRatio,
  loadPreviewRatio,
  parseRatio,
  previewRatioStorageKey,
  savePreviewRatio,
} from '../previewRatio'

describe('clampRatio', () => {
  it('clamps to min/max', () => {
    expect(clampRatio(0.05)).toBe(MIN_PANE_RATIO)
    expect(clampRatio(0.99)).toBe(MAX_PANE_RATIO)
  })
  it('passes through valid values', () => {
    expect(clampRatio(0.5)).toBe(0.5)
  })
  it('returns default for non-finite inputs', () => {
    expect(clampRatio(Number.NaN)).toBe(DEFAULT_PREVIEW_RATIO)
    expect(clampRatio(Number.POSITIVE_INFINITY)).toBe(DEFAULT_PREVIEW_RATIO)
  })
})

describe('parseRatio', () => {
  it('returns default for null / non-numeric', () => {
    expect(parseRatio(null)).toBe(DEFAULT_PREVIEW_RATIO)
    expect(parseRatio('abc')).toBe(DEFAULT_PREVIEW_RATIO)
  })
  it('clamps values from storage', () => {
    expect(parseRatio('0.05')).toBe(MIN_PANE_RATIO)
    expect(parseRatio('0.99')).toBe(MAX_PANE_RATIO)
    expect(parseRatio('0.4')).toBe(0.4)
  })
})

describe('persistence', () => {
  beforeEach(() => localStorage.clear?.())

  it('roundtrips', () => {
    savePreviewRatio('o/r', 0.4)
    expect(loadPreviewRatio('o/r')).toBe(0.4)
  })

  it('clamps on save', () => {
    savePreviewRatio('o/r', 0.01)
    expect(loadPreviewRatio('o/r')).toBe(MIN_PANE_RATIO)
  })

  it('scopes by repo', () => {
    savePreviewRatio('o/a', 0.3)
    expect(loadPreviewRatio('o/b')).toBe(DEFAULT_PREVIEW_RATIO)
  })

  it('uses predictable key', () => {
    expect(previewRatioStorageKey('o/r')).toBe('synapse_preview_ratio:o/r')
  })
})
