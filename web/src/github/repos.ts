export type GithubRepoListItem = {
  id: number
  full_name: string
  name: string
  private: boolean
  default_branch: string
}

export type FetchUserReposResult =
  | { ok: true; repos: GithubRepoListItem[]; diagnostics: string[] }
  | { ok: false; error: string }

const GH_HEADERS = (token: string) => ({
  Accept: 'application/vnd.github+json',
  Authorization: `Bearer ${token}`,
  'X-GitHub-Api-Version': '2022-11-28',
})

function parseNextLink(linkHeader: string | null): string | null {
  if (!linkHeader) return null
  for (const part of linkHeader.split(',')) {
    const match = part.match(/<([^>]+)>;\s*rel="next"/)
    if (match) return match[1]
  }
  return null
}

function parseRepoRow(row: unknown): GithubRepoListItem | null {
  if (!row || typeof row !== 'object') return null
  const r = row as Record<string, unknown>
  if (
    typeof r.id === 'number' &&
    typeof r.full_name === 'string' &&
    typeof r.name === 'string' &&
    typeof r.private === 'boolean' &&
    typeof r.default_branch === 'string'
  ) {
    return {
      id: r.id,
      full_name: r.full_name,
      name: r.name,
      private: r.private,
      default_branch: r.default_branch,
    }
  }
  return null
}

async function paginate(
  token: string,
  firstUrl: string,
): Promise<
  { ok: true; rows: GithubRepoListItem[] } | { ok: false; error: string }
> {
  const rows: GithubRepoListItem[] = []
  let nextUrl: string | null = firstUrl
  let pages = 0

  while (nextUrl !== null && pages < 30) {
    const currentUrl: string = nextUrl
    const res = await fetch(currentUrl, { headers: GH_HEADERS(token) })
    if (!res.ok) {
      return {
        ok: false,
        error: `Request failed (${res.status}) for ${currentUrl}`,
      }
    }
    const data: unknown = await res.json()
    if (!Array.isArray(data)) {
      return { ok: false, error: 'Unexpected response shape.' }
    }
    for (const row of data) {
      const parsed = parseRepoRow(row)
      if (parsed) rows.push(parsed)
    }
    const linkNext = parseNextLink(res.headers.get('Link'))
    if (linkNext) {
      nextUrl = linkNext
    } else if (data.length >= 100) {
      const parsedUrl = new URL(currentUrl)
      const cur = Number(parsedUrl.searchParams.get('page') ?? '1') || 1
      parsedUrl.searchParams.set('page', String(cur + 1))
      nextUrl = parsedUrl.toString()
    } else {
      nextUrl = null
    }
    pages += 1
  }
  return { ok: true, rows }
}

async function listOrgs(
  token: string,
): Promise<string[]> {
  const res = await fetch(
    'https://api.github.com/user/orgs?per_page=100',
    { headers: GH_HEADERS(token) },
  )
  if (!res.ok) return []
  const data = (await res.json()) as unknown
  if (!Array.isArray(data)) return []
  const names: string[] = []
  for (const row of data) {
    if (row && typeof row === 'object') {
      const login = (row as Record<string, unknown>).login
      if (typeof login === 'string') names.push(login)
    }
  }
  return names
}

export async function fetchUserRepos(
  token: string,
): Promise<FetchUserReposResult> {
  const diagnostics: string[] = []
  const byId = new Map<number, GithubRepoListItem>()

  // 1. /user/repos with explicit per_page=100
  const userRes = await paginate(
    token,
    'https://api.github.com/user/repos?per_page=100&sort=updated&visibility=all&affiliation=owner,collaborator,organization_member',
  )
  if (!userRes.ok) {
    return { ok: false, error: userRes.error }
  }
  for (const r of userRes.rows) byId.set(r.id, r)
  diagnostics.push(`/user/repos → ${userRes.rows.length}`)

  // 2. Each org's repos (private ones the user can access, which /user/repos sometimes misses)
  const orgs = await listOrgs(token)
  diagnostics.push(`orgs: ${orgs.length ? orgs.join(', ') : 'none'}`)
  for (const org of orgs) {
    const orgRes = await paginate(
      token,
      `https://api.github.com/orgs/${encodeURIComponent(org)}/repos?per_page=100&type=all`,
    )
    if (orgRes.ok) {
      let added = 0
      for (const r of orgRes.rows) {
        if (!byId.has(r.id)) {
          byId.set(r.id, r)
          added += 1
        }
      }
      diagnostics.push(`orgs/${org}/repos → +${added} (of ${orgRes.rows.length})`)
    } else {
      diagnostics.push(`orgs/${org}/repos → error: ${orgRes.error}`)
    }
  }

  const repos = Array.from(byId.values()).sort((a, b) =>
    a.full_name.localeCompare(b.full_name),
  )
  return { ok: true, repos, diagnostics }
}

export type FetchRepoByNameResult =
  | { ok: true; repo: GithubRepoListItem }
  | { ok: false; error: string }

export async function fetchRepoByFullName(
  token: string,
  fullName: string,
): Promise<FetchRepoByNameResult> {
  const slash = fullName.indexOf('/')
  if (slash <= 0 || slash === fullName.length - 1) {
    return { ok: false, error: 'Expected "owner/repo".' }
  }
  const res = await fetch(
    `https://api.github.com/repos/${encodeURIComponent(fullName.slice(0, slash))}/${encodeURIComponent(fullName.slice(slash + 1))}`,
    { headers: GH_HEADERS(token) },
  )
  if (!res.ok) {
    if (res.status === 404) {
      return {
        ok: false,
        error:
          'Not found. If this is an org repo with OAuth restrictions, grant access at github.com/settings/applications.',
      }
    }
    return { ok: false, error: `Lookup failed (${res.status})` }
  }
  const parsed = parseRepoRow(await res.json())
  if (!parsed) {
    return { ok: false, error: 'Unexpected repo response shape.' }
  }
  return { ok: true, repo: parsed }
}
