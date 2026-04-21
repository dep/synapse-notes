export type SplitFrontmatter = {
  frontmatter: string | null
  body: string
}

// Extract a leading YAML-style frontmatter block bounded by lines containing
// only `---`. Supports optional BOM. Returns the frontmatter contents (without
// the fences) and the remaining body. No frontmatter → { frontmatter: null, body: input }.
export function splitFrontmatter(source: string): SplitFrontmatter {
  let input = source
  // Strip a leading BOM.
  if (input.charCodeAt(0) === 0xfeff) input = input.slice(1)

  // Must start with '---' on the first line — nothing before it (not even blanks).
  const firstNewline = input.indexOf('\n')
  if (firstNewline < 0) return { frontmatter: null, body: source }
  const firstLine = input.slice(0, firstNewline).replace(/\r$/, '')
  if (firstLine !== '---') return { frontmatter: null, body: source }

  // Find the closing fence. It must be a line containing only `---`.
  const rest = input.slice(firstNewline + 1)
  const closeMatch = rest.match(/(^|\n)---(\r?\n|$)/)
  if (!closeMatch) return { frontmatter: null, body: source }
  const closeStart = closeMatch.index! + (closeMatch[1] === '\n' ? 1 : 0)
  const frontmatter = rest.slice(0, closeStart).replace(/\r?\n$/, '')
  const afterClose = closeStart + 3 + closeMatch[2].length
  const body = rest.slice(afterClose)
  return { frontmatter, body }
}
