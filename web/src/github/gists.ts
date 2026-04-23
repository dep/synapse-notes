const GH_HEADERS = (token: string) => ({
  Accept: 'application/vnd.github+json',
  Authorization: `Bearer ${token}`,
  'X-GitHub-Api-Version': '2022-11-28',
})

export function parseScopesHeader(raw: string | null): string[] {
  if (!raw) return []
  return raw
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean)
}

export function canPublishGist(scopes: string[]): boolean {
  return scopes.includes('gist')
}

export type FetchScopesResult =
  | { ok: true; scopes: string[] }
  | { ok: false; error: string }

export async function fetchOAuthScopes(
  token: string,
): Promise<FetchScopesResult> {
  const res = await fetch('https://api.github.com/user', {
    headers: GH_HEADERS(token),
  })
  if (!res.ok) {
    return { ok: false, error: `User lookup failed (${res.status})` }
  }
  return { ok: true, scopes: parseScopesHeader(res.headers.get('X-OAuth-Scopes')) }
}

export type CreateGistBody = {
  filename: string
  content: string
  description?: string
  isPublic: boolean
}

export type CreateGistResult =
  | { ok: true; htmlUrl: string; id: string }
  | { ok: false; error: string }

export async function createGist(
  token: string,
  body: CreateGistBody,
): Promise<CreateGistResult> {
  const res = await fetch('https://api.github.com/gists', {
    method: 'POST',
    headers: {
      ...GH_HEADERS(token),
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      description: body.description ?? '',
      public: body.isPublic,
      files: {
        [body.filename]: { content: body.content },
      },
    }),
  })
  if (!res.ok) {
    if (res.status === 404 || res.status === 403) {
      return {
        ok: false,
        error:
          'Gist creation was rejected — your token likely lacks the "gist" scope. Sign out and sign back in to grant it.',
      }
    }
    const text = await res.text()
    return { ok: false, error: `Gist create failed (${res.status}): ${text}` }
  }
  const data = (await res.json()) as { html_url?: string; id?: string }
  if (!data.html_url || !data.id) {
    return { ok: false, error: 'Gist response missing html_url or id.' }
  }
  return { ok: true, htmlUrl: data.html_url, id: data.id }
}
