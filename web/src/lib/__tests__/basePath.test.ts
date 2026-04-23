import { describe, expect, it } from 'vitest'
import { normalizeBasePath, stripBase, withBase } from '../basePath'

describe('normalizeBasePath', () => {
  it('adds leading and trailing slash', () => {
    expect(normalizeBasePath('web')).toBe('/web/')
    expect(normalizeBasePath('/web')).toBe('/web/')
    expect(normalizeBasePath('web/')).toBe('/web/')
  })
  it('treats empty as /', () => {
    expect(normalizeBasePath('')).toBe('/')
  })
  it('passes / through', () => {
    expect(normalizeBasePath('/')).toBe('/')
  })
})

describe('withBase', () => {
  it('returns path unchanged under /', () => {
    expect(withBase('/', '/o/r')).toBe('/o/r')
    expect(withBase('/', 'o/r')).toBe('/o/r')
  })
  it('prepends a non-root base', () => {
    expect(withBase('/web/', '/o/r')).toBe('/web/o/r')
    expect(withBase('/web/', 'o/r')).toBe('/web/o/r')
  })
  it('handles bare root path', () => {
    expect(withBase('/web/', '/')).toBe('/web/')
  })
})

describe('stripBase', () => {
  it('returns / for bare-prefix URLs', () => {
    expect(stripBase('/web/', '/web')).toBe('/')
    expect(stripBase('/web/', '/web/')).toBe('/')
  })
  it('strips the base from a nested path', () => {
    expect(stripBase('/web/', '/web/o/r/tree/x')).toBe('/o/r/tree/x')
  })
  it('leaves / and unrelated paths untouched', () => {
    expect(stripBase('/', '/o/r')).toBe('/o/r')
    expect(stripBase('/web/', '/other/path')).toBe('/other/path')
  })
})
