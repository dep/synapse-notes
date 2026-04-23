export function parseRepoFullName(fullName: string): {
  owner: string
  repo: string
} | null {
  const slash = fullName.indexOf('/')
  if (slash <= 0 || slash === fullName.length - 1) {
    return null
  }
  return { owner: fullName.slice(0, slash), repo: fullName.slice(slash + 1) }
}
