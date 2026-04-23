const KEY = 'synapse_hidden_paths'

type Storage = Pick<globalThis.Storage, 'getItem' | 'setItem' | 'removeItem'>

/** Returns the raw comma-separated string, e.g. ".obsidian, templates" */
export function loadHiddenPaths(storage: Storage = localStorage): string {
  return storage.getItem(KEY) ?? ''
}

export function saveHiddenPaths(value: string, storage: Storage = localStorage): void {
  const trimmed = value.trim()
  if (!trimmed) {
    storage.removeItem(KEY)
  } else {
    storage.setItem(KEY, trimmed)
  }
}

/**
 * Parses the comma-separated string into a list of lowercased patterns.
 * Each pattern matches any path segment (file or folder name) exactly,
 * or the full path prefix for folder-style entries like "Daily Notes".
 */
export function parseHiddenPatterns(raw: string): string[] {
  return raw
    .split(',')
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean)
}

/** Returns true if the given path should be hidden. */
export function isHidden(path: string, patterns: string[]): boolean {
  if (patterns.length === 0) return false
  const lower = path.toLowerCase()
  return patterns.some((pat) => {
    // Match any path segment or the full path / a prefix segment boundary.
    const segments = lower.split('/')
    return segments.some((seg) => seg === pat) || lower === pat || lower.startsWith(pat + '/')
  })
}
