/**
 * Parses @path mentions from an instruction string.
 * Two forms are supported:
 *   @`path with spaces/file.md`  — backtick-quoted (used when path contains spaces)
 *   @path/no-spaces.md           — bare (no spaces in path)
 * Returns deduplicated paths in order of first appearance.
 */
export function parseMentions(instruction: string): string[] {
  const seen = new Set<string>()
  const results: string[] = []
  // Match backtick-quoted first, then bare (order matters for the alternation).
  for (const match of instruction.matchAll(/@`([^`]+)`|@(\S+)/g)) {
    const path = match[1] ?? match[2]
    if (!seen.has(path)) {
      seen.add(path)
      results.push(path)
    }
  }
  return results
}

/**
 * Given a raw instruction and a map of resolved file contents,
 * returns the instruction with @mentions replaced by their paths
 * (unchanged) plus a preamble block for each file.
 *
 * The extra context is returned separately so callers can inject
 * it as an additional context block into the API prompt.
 */
export function buildMentionContext(
  resolvedFiles: Record<string, string>,
): string {
  const entries = Object.entries(resolvedFiles)
  if (entries.length === 0) return ''
  return entries
    .map(([path, content]) => `@${path}:\n---\n${content}\n---`)
    .join('\n\n')
}
