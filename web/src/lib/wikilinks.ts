import type { TreeNode } from '../github/tree'
import { isMarkdownPath } from '../github/tree'

// [[target]] or [[target|display]]. target stops at ] or |. No nested brackets.
export const WIKILINK_REGEX = /\[\[([^\]|\r\n]+?)(?:\|([^\]\r\n]+?))?\]\]/g

export type WikilinkMatch = {
  raw: string
  target: string
  display: string
  index: number
  length: number
}

export function parseWikilinks(text: string): WikilinkMatch[] {
  const out: WikilinkMatch[] = []
  for (const m of text.matchAll(WIKILINK_REGEX)) {
    const target = m[1].trim()
    const display = (m[2] ?? m[1]).trim()
    if (!target) continue
    out.push({
      raw: m[0],
      target,
      display,
      index: m.index ?? 0,
      length: m[0].length,
    })
  }
  return out
}

// Lowercased stem (filename without .md/.mdx/.markdown) → first matching path.
// First-match wins; we walk the tree in a stable order.
export type WikilinkIndex = Map<string, string>

function stemOf(filename: string): string {
  return filename.replace(/\.(md|mdx|markdown)$/i, '')
}

export function buildWikilinkIndex(root: TreeNode): WikilinkIndex {
  const index: WikilinkIndex = new Map()
  const walk = (node: TreeNode) => {
    for (const child of node.children) {
      if (child.type === 'tree') {
        walk(child)
      } else if (isMarkdownPath(child.path)) {
        const key = stemOf(child.name).toLowerCase()
        if (!index.has(key)) index.set(key, child.path)
      }
    }
  }
  walk(root)
  return index
}

// Resolve a wikilink target string against the index. Supports bare stems
// ("foo") and relative paths ("notes/foo"). Case-insensitive.
export function resolveWikilink(
  target: string,
  index: WikilinkIndex,
): string | null {
  const normalized = target.trim()
  if (!normalized) return null
  const stem = stemOf(normalized).toLowerCase()
  const direct = index.get(stem)
  if (direct) return direct

  // Relative-path style: last segment is the stem, everything else is a hint.
  const slash = normalized.lastIndexOf('/')
  if (slash >= 0) {
    const tailStem = stemOf(normalized.slice(slash + 1)).toLowerCase()
    const hit = index.get(tailStem)
    if (hit) return hit
  }
  return null
}
