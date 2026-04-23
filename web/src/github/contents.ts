export type GitTreeEntry = {
  path: string
  type: 'blob' | 'tree'
  sha: string
  size?: number
}

export type FetchTreeResult =
  | { ok: true; entries: GitTreeEntry[]; truncated: boolean; sha: string }
  | { ok: false; error: string }

const GH_HEADERS = (token: string) => ({
  Accept: 'application/vnd.github+json',
  Authorization: `Bearer ${token}`,
  'X-GitHub-Api-Version': '2022-11-28',
})

async function fetchBranchSha(
  token: string,
  owner: string,
  repo: string,
  branch: string,
): Promise<{ ok: true; sha: string } | { ok: false; error: string }> {
  const res = await fetch(
    `https://api.github.com/repos/${owner}/${repo}/branches/${encodeURIComponent(branch)}`,
    { headers: GH_HEADERS(token) },
  )
  if (!res.ok) {
    return { ok: false, error: `Branch lookup failed (${res.status})` }
  }
  const data = (await res.json()) as { commit?: { sha?: string } }
  if (!data.commit?.sha) {
    return { ok: false, error: 'Branch response missing commit.sha' }
  }
  return { ok: true, sha: data.commit.sha }
}

export async function fetchRepoTree(
  token: string,
  owner: string,
  repo: string,
  branch: string,
): Promise<FetchTreeResult> {
  const shaResult = await fetchBranchSha(token, owner, repo, branch)
  if (!shaResult.ok) return shaResult

  const res = await fetch(
    `https://api.github.com/repos/${owner}/${repo}/git/trees/${shaResult.sha}?recursive=1`,
    { headers: GH_HEADERS(token) },
  )
  if (!res.ok) {
    return { ok: false, error: `Tree request failed (${res.status})` }
  }
  const data = (await res.json()) as {
    tree?: Array<{
      path?: string
      type?: string
      sha?: string
      size?: number
    }>
    truncated?: boolean
  }
  const entries: GitTreeEntry[] = []
  for (const row of data.tree ?? []) {
    if (
      typeof row.path === 'string' &&
      (row.type === 'blob' || row.type === 'tree') &&
      typeof row.sha === 'string'
    ) {
      entries.push({
        path: row.path,
        type: row.type,
        sha: row.sha,
        size: typeof row.size === 'number' ? row.size : undefined,
      })
    }
  }
  return {
    ok: true,
    entries,
    truncated: Boolean(data.truncated),
    sha: shaResult.sha,
  }
}

export type FetchFileResult =
  | { ok: true; content: string; sha: string; encoding: 'utf-8' | 'binary' }
  | { ok: false; error: string }

function decodeBase64Utf8(b64: string): string {
  const clean = b64.replace(/\s+/g, '')
  const binary = atob(clean)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return new TextDecoder('utf-8').decode(bytes)
}

function encodeBase64Utf8(str: string): string {
  const bytes = new TextEncoder().encode(str)
  let binary = ''
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i])
  return btoa(binary)
}

export async function fetchFileContent(
  token: string,
  owner: string,
  repo: string,
  path: string,
  branch: string,
): Promise<FetchFileResult> {
  const res = await fetch(
    `https://api.github.com/repos/${owner}/${repo}/contents/${encodePath(path)}?ref=${encodeURIComponent(branch)}`,
    { headers: GH_HEADERS(token) },
  )
  if (!res.ok) {
    return { ok: false, error: `File request failed (${res.status})` }
  }
  const data = (await res.json()) as {
    content?: string
    encoding?: string
    sha?: string
    size?: number
    type?: string
  }
  if (data.type && data.type !== 'file') {
    return { ok: false, error: `Not a regular file: ${data.type}` }
  }
  if (!data.sha) {
    return { ok: false, error: 'File response missing sha.' }
  }
  if (data.content == null || data.encoding !== 'base64') {
    return { ok: false, error: 'Unsupported file encoding.' }
  }
  try {
    const text = decodeBase64Utf8(data.content)
    if (text.includes('\u0000')) {
      return { ok: true, content: '', sha: data.sha, encoding: 'binary' }
    }
    return { ok: true, content: text, sha: data.sha, encoding: 'utf-8' }
  } catch {
    return { ok: true, content: '', sha: data.sha, encoding: 'binary' }
  }
}

export type PutFileResult =
  | { ok: true; newSha: string; commitSha: string }
  | { ok: false; error: string }

export async function putFileContent(
  token: string,
  owner: string,
  repo: string,
  path: string,
  body: {
    content: string
    message: string
    branch: string
    sha?: string
  },
): Promise<PutFileResult> {
  const payload: Record<string, unknown> = {
    message: body.message,
    content: encodeBase64Utf8(body.content),
    branch: body.branch,
  }
  if (body.sha) payload.sha = body.sha

  const res = await fetch(
    `https://api.github.com/repos/${owner}/${repo}/contents/${encodePath(path)}`,
    {
      method: 'PUT',
      headers: {
        ...GH_HEADERS(token),
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    },
  )
  if (!res.ok) {
    const text = await res.text()
    return { ok: false, error: `Save failed (${res.status}): ${text}` }
  }
  const data = (await res.json()) as {
    content?: { sha?: string }
    commit?: { sha?: string }
  }
  if (!data.content?.sha || !data.commit?.sha) {
    return { ok: false, error: 'Save response missing sha.' }
  }
  return { ok: true, newSha: data.content.sha, commitSha: data.commit.sha }
}

export type DeleteFileResult =
  | { ok: true; commitSha: string }
  | { ok: false; error: string }

export async function deleteFileContent(
  token: string,
  owner: string,
  repo: string,
  path: string,
  body: {
    message: string
    branch: string
    sha: string
  },
): Promise<DeleteFileResult> {
  const res = await fetch(
    `https://api.github.com/repos/${owner}/${repo}/contents/${encodePath(path)}`,
    {
      method: 'DELETE',
      headers: {
        ...GH_HEADERS(token),
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: body.message,
        branch: body.branch,
        sha: body.sha,
      }),
    },
  )
  if (!res.ok) {
    const text = await res.text()
    return { ok: false, error: `Delete failed (${res.status}): ${text}` }
  }
  const data = (await res.json()) as { commit?: { sha?: string } }
  if (!data.commit?.sha) {
    return { ok: false, error: 'Delete response missing commit sha.' }
  }
  return { ok: true, commitSha: data.commit.sha }
}

function encodePath(path: string): string {
  return path.split('/').map(encodeURIComponent).join('/')
}

export type FileCommit = {
  sha: string
  message: string
  date: string
  author: string
}

export type FetchFileCommitsResult =
  | { ok: true; commits: FileCommit[] }
  | { ok: false; error: string }

export async function fetchFileCommits(
  token: string,
  owner: string,
  repo: string,
  path: string,
  branch: string,
): Promise<FetchFileCommitsResult> {
  const res = await fetch(
    `https://api.github.com/repos/${owner}/${repo}/commits?path=${encodePath(path)}&sha=${encodeURIComponent(branch)}&per_page=30`,
    { headers: GH_HEADERS(token) },
  )
  if (!res.ok) {
    return { ok: false, error: `Commits request failed (${res.status})` }
  }
  const data = (await res.json()) as Array<{
    sha?: string
    commit?: {
      message?: string
      author?: { date?: string; name?: string }
    }
  }>
  const commits: FileCommit[] = data
    .filter((c) => c.sha && c.commit)
    .map((c) => ({
      sha: c.sha!,
      message: c.commit!.message?.split('\n')[0] ?? '',
      date: c.commit!.author?.date ?? '',
      author: c.commit!.author?.name ?? '',
    }))
  return { ok: true, commits }
}

export async function fetchFileAtCommit(
  token: string,
  owner: string,
  repo: string,
  path: string,
  commitSha: string,
): Promise<FetchFileResult> {
  const res = await fetch(
    `https://api.github.com/repos/${owner}/${repo}/contents/${encodePath(path)}?ref=${encodeURIComponent(commitSha)}`,
    { headers: GH_HEADERS(token) },
  )
  if (!res.ok) {
    return { ok: false, error: `File at commit request failed (${res.status})` }
  }
  const data = (await res.json()) as {
    content?: string
    encoding?: string
    sha?: string
    type?: string
  }
  if (!data.sha) return { ok: false, error: 'File response missing sha.' }
  if (data.content == null || data.encoding !== 'base64') {
    return { ok: false, error: 'Unsupported file encoding.' }
  }
  try {
    const text = decodeBase64Utf8(data.content)
    if (text.includes(' ')) {
      return { ok: true, content: '', sha: data.sha, encoding: 'binary' }
    }
    return { ok: true, content: text, sha: data.sha, encoding: 'utf-8' }
  } catch {
    return { ok: true, content: '', sha: data.sha, encoding: 'binary' }
  }
}
