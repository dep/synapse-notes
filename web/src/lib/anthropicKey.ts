export const ANTHROPIC_KEY_STORAGE_KEY = 'synapse_anthropic_api_key'

type Storage = Pick<globalThis.Storage, 'getItem' | 'setItem' | 'removeItem'>

export function loadAnthropicKey(
  storage: Storage = localStorage,
): string | null {
  const raw = storage.getItem(ANTHROPIC_KEY_STORAGE_KEY)
  if (!raw) return null
  const trimmed = raw.trim()
  return trimmed || null
}

export function saveAnthropicKey(
  key: string,
  storage: Storage = localStorage,
): void {
  const trimmed = key.trim()
  if (!trimmed) {
    storage.removeItem(ANTHROPIC_KEY_STORAGE_KEY)
    return
  }
  storage.setItem(ANTHROPIC_KEY_STORAGE_KEY, trimmed)
}

export function clearAnthropicKey(storage: Storage = localStorage): void {
  storage.removeItem(ANTHROPIC_KEY_STORAGE_KEY)
}

// Sanity-check: Anthropic keys start with `sk-ant-`. Returns true for the
// common shape; not a cryptographic check.
export function looksLikeAnthropicKey(key: string): boolean {
  return /^sk-ant-[A-Za-z0-9_-]{20,}$/.test(key.trim())
}
