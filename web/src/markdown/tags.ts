const TAG_PATTERN = /(?<![\p{L}\p{N}_#])#([\p{L}\p{N}_][\p{L}\p{N}_-]*)/gu

function blankAtxHeadingPrefix(line: string): string {
  const match = line.match(/^(\s*)(#{1,6})(\s|$)/u)
  if (!match || match[0] === undefined) {
    return line
  }
  const consumed = match[0].length
  return `${' '.repeat(consumed)}${line.slice(consumed)}`
}

export function extractTagsFromMarkdown(markdown: string): string[] {
  const lines = markdown.split('\n')
  const searchable = lines.map(blankAtxHeadingPrefix).join('\n')

  const seen = new Set<string>()
  const ordered: string[] = []

  for (const m of searchable.matchAll(TAG_PATTERN)) {
    const tag = m[1]
    if (tag === undefined) {
      continue
    }
    if (seen.has(tag)) {
      continue
    }
    seen.add(tag)
    ordered.push(tag)
  }

  return ordered
}
