export type WikiLinkMatch = {
  target: string
  start: number
  end: number
}

const WIKI_LINK_PATTERN = /\[\[([^\]]+?)\]\]/g

function parseWikiTarget(inner: string): string {
  const pipeIndex = inner.indexOf('|')
  const targetPart = pipeIndex === -1 ? inner : inner.slice(0, pipeIndex)
  return targetPart.trim()
}

export function findWikiLinks(markdown: string): WikiLinkMatch[] {
  const matches: WikiLinkMatch[] = []

  for (const m of markdown.matchAll(WIKI_LINK_PATTERN)) {
    const inner = m[1]
    if (inner === undefined || m.index === undefined) {
      continue
    }

    matches.push({
      target: parseWikiTarget(inner),
      start: m.index,
      end: m.index + m[0].length,
    })
  }

  return matches
}
