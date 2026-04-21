import type { TreeNode } from '../github/tree'

export type PaletteItemKind = 'file' | 'folder'

export type PaletteItem = {
  kind: PaletteItemKind
  path: string
  name: string
  parentPath: string
}

export function collectPaletteItems(root: TreeNode): PaletteItem[] {
  const out: PaletteItem[] = []
  const walk = (node: TreeNode) => {
    for (const child of node.children) {
      const parentPath = node.path
      if (child.type === 'tree') {
        out.push({
          kind: 'folder',
          path: child.path,
          name: child.name,
          parentPath,
        })
        walk(child)
      } else {
        out.push({
          kind: 'file',
          path: child.path,
          name: child.name,
          parentPath,
        })
      }
    }
  }
  walk(root)
  return out
}

// Scoring rules (higher is better; 0 means no match):
//   name exact match        1000
//   name starts with query   500
//   name contains query      300
//   path contains query      200
//   subsequence in name      120
//   subsequence in path       80
// Tiebreakers:
//   + bonus for shorter names (so "foo.md" beats "foo-bar-baz.md")
//   + files ranked above folders for identical base scores
export function scoreItem(item: PaletteItem, rawQuery: string): number {
  const query = rawQuery.trim().toLowerCase()
  if (!query) return 1 // any non-match gets a trivial baseline so ordering is stable
  const name = item.name.toLowerCase()
  const path = item.path.toLowerCase()

  let score = 0
  if (name === query) {
    score = 1000
  } else if (name.startsWith(query)) {
    score = 500
  } else if (name.includes(query)) {
    score = 300
  } else if (path.includes(query)) {
    score = 200
  } else if (isSubsequence(query, name)) {
    score = 120
  } else if (isSubsequence(query, path)) {
    score = 80
  } else {
    return 0
  }

  // Shorter-name bonus (max 20 pts for 1-char names).
  score += Math.max(0, 20 - item.name.length)

  // Prefer files over folders on ties.
  if (item.kind === 'file') score += 1

  return score
}

function isSubsequence(needle: string, haystack: string): boolean {
  if (!needle) return true
  let i = 0
  for (let j = 0; j < haystack.length && i < needle.length; j++) {
    if (needle[i] === haystack[j]) i++
  }
  return i === needle.length
}

export function filterItems(
  items: PaletteItem[],
  query: string,
  limit = 50,
): PaletteItem[] {
  const trimmed = query.trim()
  if (!trimmed) {
    // Empty query: show a stable slice so the UI isn't blank.
    return items.slice(0, limit)
  }
  const scored: Array<{ item: PaletteItem; score: number }> = []
  for (const item of items) {
    const score = scoreItem(item, trimmed)
    if (score > 0) scored.push({ item, score })
  }
  scored.sort((a, b) => {
    if (b.score !== a.score) return b.score - a.score
    return a.item.path.localeCompare(b.item.path)
  })
  return scored.slice(0, limit).map((s) => s.item)
}
