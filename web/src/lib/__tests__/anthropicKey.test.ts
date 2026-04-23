import { beforeEach, describe, expect, it } from 'vitest'
import {
  clearAnthropicKey,
  loadAnthropicKey,
  looksLikeAnthropicKey,
  saveAnthropicKey,
} from '../anthropicKey'

describe('Anthropic key storage', () => {
  beforeEach(() => localStorage.clear?.())

  it('returns null when unset', () => {
    expect(loadAnthropicKey()).toBeNull()
  })

  it('saves and loads a trimmed key', () => {
    saveAnthropicKey('  sk-ant-abc123  ')
    expect(loadAnthropicKey()).toBe('sk-ant-abc123')
  })

  it('treats an empty save as a remove', () => {
    saveAnthropicKey('sk-ant-test123')
    saveAnthropicKey('   ')
    expect(loadAnthropicKey()).toBeNull()
  })

  it('clearAnthropicKey removes the entry', () => {
    saveAnthropicKey('sk-ant-abc')
    clearAnthropicKey()
    expect(loadAnthropicKey()).toBeNull()
  })
})

describe('looksLikeAnthropicKey', () => {
  it('accepts obvious-looking keys', () => {
    expect(looksLikeAnthropicKey('sk-ant-abcdef0123456789ABCDEF')).toBe(true)
  })

  it('rejects empty / short / wrong-prefix', () => {
    expect(looksLikeAnthropicKey('')).toBe(false)
    expect(looksLikeAnthropicKey('   ')).toBe(false)
    expect(looksLikeAnthropicKey('sk-ant-short')).toBe(false)
    expect(looksLikeAnthropicKey('sk-xxx-abcdef0123456789ABCDEF')).toBe(false)
  })
})
