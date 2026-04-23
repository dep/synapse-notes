export type PinKind = 'file' | 'folder'

export type PinnedItem = {
  path: string
  kind: PinKind
}

export type PinsStore = {
  list: () => PinnedItem[]
  isPinned: (path: string) => boolean
  pin: (item: PinnedItem) => PinnedItem[]
  unpin: (path: string) => PinnedItem[]
  rename: (oldPath: string, newPath: string) => PinnedItem[]
  remove: (path: string) => PinnedItem[]
  clear: () => void
}

type Storage = Pick<globalThis.Storage, 'getItem' | 'setItem' | 'removeItem'>

export function pinsStorageKey(repoFullName: string): string {
  return `synapse_pins:${repoFullName}`
}

export function parsePins(raw: string | null): PinnedItem[] {
  if (!raw) return []
  try {
    const parsed = JSON.parse(raw) as unknown
    if (!Array.isArray(parsed)) return []
    const out: PinnedItem[] = []
    const seen = new Set<string>()
    for (const entry of parsed) {
      if (!entry || typeof entry !== 'object') continue
      const path = (entry as { path?: unknown }).path
      const kind = (entry as { kind?: unknown }).kind
      if (typeof path !== 'string' || !path) continue
      if (kind !== 'file' && kind !== 'folder') continue
      if (seen.has(path)) continue
      seen.add(path)
      out.push({ path, kind })
    }
    return out
  } catch {
    return []
  }
}

export function createPinsStore(
  repoFullName: string,
  storage: Storage = localStorage,
): PinsStore {
  const key = pinsStorageKey(repoFullName)

  const read = (): PinnedItem[] => parsePins(storage.getItem(key))
  const write = (items: PinnedItem[]): void => {
    if (items.length === 0) {
      storage.removeItem(key)
    } else {
      storage.setItem(key, JSON.stringify(items))
    }
  }

  return {
    list: read,
    isPinned: (path) => read().some((p) => p.path === path),
    pin: (item) => {
      const current = read()
      if (current.some((p) => p.path === item.path)) return current
      const next = [...current, item]
      write(next)
      return next
    },
    unpin: (path) => {
      const next = read().filter((p) => p.path !== path)
      write(next)
      return next
    },
    rename: (oldPath, newPath) => {
      const current = read()
      const next = current.map((p) =>
        p.path === oldPath ? { ...p, path: newPath } : p,
      )
      if (next.some((p, i) => p.path !== current[i].path)) write(next)
      return next
    },
    remove: (path) => {
      const next = read().filter((p) => p.path !== path)
      write(next)
      return next
    },
    clear: () => storage.removeItem(key),
  }
}
