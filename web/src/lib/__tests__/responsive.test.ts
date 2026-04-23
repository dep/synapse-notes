import { describe, expect, it } from 'vitest'
import {
  MOBILE_BREAKPOINT,
  WIDE_BREAKPOINT,
  crossedBreakpoint,
  defaultPreviewVisible,
  defaultSidebarVisible,
  isMobile,
  resolveVisible,
} from '../responsive'

describe('breakpoint constants', () => {
  it('match the spec', () => {
    expect(MOBILE_BREAKPOINT).toBe(900)
    expect(WIDE_BREAKPOINT).toBe(1250)
  })
})

describe('isMobile', () => {
  it('true strictly below MOBILE_BREAKPOINT', () => {
    expect(isMobile(899)).toBe(true)
    expect(isMobile(900)).toBe(false)
    expect(isMobile(1300)).toBe(false)
  })
})

describe('default visibility', () => {
  it('sidebar hides below 900', () => {
    expect(defaultSidebarVisible(899)).toBe(false)
    expect(defaultSidebarVisible(900)).toBe(true)
  })
  it('preview hides below 1250', () => {
    expect(defaultPreviewVisible(1249)).toBe(false)
    expect(defaultPreviewVisible(1250)).toBe(true)
  })
})

describe('crossedBreakpoint', () => {
  it('returns false when both sides are on the same side', () => {
    expect(crossedBreakpoint(1000, 1100, 900)).toBe(false)
    expect(crossedBreakpoint(700, 800, 900)).toBe(false)
  })
  it('returns true when going from above to below', () => {
    expect(crossedBreakpoint(1000, 800, 900)).toBe(true)
  })
  it('returns true when going from below to above', () => {
    expect(crossedBreakpoint(800, 1000, 900)).toBe(true)
  })
  it('treats the exact breakpoint as "above" (inclusive)', () => {
    expect(crossedBreakpoint(899, 900, 900)).toBe(true)
    expect(crossedBreakpoint(900, 901, 900)).toBe(false)
  })
})

describe('resolveVisible', () => {
  it('falls back to default when override is null', () => {
    expect(resolveVisible(1000, 900, null)).toBe(true)
    expect(resolveVisible(800, 900, null)).toBe(false)
  })
  it('respects an explicit override', () => {
    expect(resolveVisible(1000, 900, false)).toBe(false)
    expect(resolveVisible(800, 900, true)).toBe(true)
  })
})
