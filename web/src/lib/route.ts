export type RouteQuery = Record<string, string>

export type Route =
  | { kind: 'picker'; query: RouteQuery }
  | { kind: 'repo'; owner: string; repo: string; query: RouteQuery }
  | {
      kind: 'folder'
      owner: string
      repo: string
      folder: string
      query: RouteQuery
    }
  | {
      kind: 'file'
      owner: string
      repo: string
      file: string
      query: RouteQuery
    }
  | { kind: 'today'; owner: string; repo: string; query: RouteQuery }

function stripSlashes(s: string): string {
  return s.replace(/^\/+|\/+$/g, '')
}

function splitSegments(pathname: string): string[] {
  const clean = stripSlashes(pathname)
  if (!clean) return []
  return clean.split('/').map(decodeURIComponent).filter(Boolean)
}

function splitPathAndQuery(input: string): {
  pathname: string
  query: RouteQuery
} {
  const hashIdx = input.indexOf('#')
  const preHash = hashIdx >= 0 ? input.slice(0, hashIdx) : input
  const qIdx = preHash.indexOf('?')
  if (qIdx < 0) return { pathname: preHash, query: {} }
  const pathname = preHash.slice(0, qIdx)
  const qs = preHash.slice(qIdx + 1)
  return { pathname, query: parseQuery(qs) }
}

function parseQuery(qs: string): RouteQuery {
  const out: RouteQuery = {}
  if (!qs) return out
  for (const pair of qs.split('&')) {
    if (!pair) continue
    const eq = pair.indexOf('=')
    const k = eq < 0 ? pair : pair.slice(0, eq)
    const v = eq < 0 ? '' : pair.slice(eq + 1)
    if (!k) continue
    try {
      out[decodeURIComponent(k)] = decodeURIComponent(v)
    } catch {
      out[k] = v
    }
  }
  return out
}

function formatQuery(query: RouteQuery): string {
  const keys = Object.keys(query).sort()
  const parts: string[] = []
  for (const k of keys) {
    const v = query[k]
    if (v == null) continue
    parts.push(`${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
  }
  return parts.length === 0 ? '' : `?${parts.join('&')}`
}

export function parseRoute(input: string): Route {
  const { pathname, query } = splitPathAndQuery(input)
  const parts = splitSegments(pathname)
  if (parts.length < 2) return { kind: 'picker', query }
  const [owner, repo, maybeKind, ...rest] = parts
  if (!owner || !repo) return { kind: 'picker', query }
  if (maybeKind === 'tree') {
    if (rest.length === 0) return { kind: 'repo', owner, repo, query }
    return { kind: 'folder', owner, repo, folder: rest.join('/'), query }
  }
  if (maybeKind === 'blob') {
    if (rest.length === 0) return { kind: 'repo', owner, repo, query }
    return { kind: 'file', owner, repo, file: rest.join('/'), query }
  }
  if (maybeKind === 'today') {
    return { kind: 'today', owner, repo, query }
  }
  return { kind: 'repo', owner, repo, query }
}

function encodeSegments(path: string): string {
  return path.split('/').filter(Boolean).map(encodeURIComponent).join('/')
}

export function formatRoute(route: Route): string {
  const qs = formatQuery(route.query ?? {})
  switch (route.kind) {
    case 'picker':
      return `/${qs}`
    case 'repo':
      return `/${encodeURIComponent(route.owner)}/${encodeURIComponent(route.repo)}${qs}`
    case 'folder': {
      const base = `/${encodeURIComponent(route.owner)}/${encodeURIComponent(route.repo)}`
      if (!route.folder) return `${base}${qs}`
      return `${base}/tree/${encodeSegments(route.folder)}${qs}`
    }
    case 'file':
      return `/${encodeURIComponent(route.owner)}/${encodeURIComponent(route.repo)}/blob/${encodeSegments(route.file)}${qs}`
    case 'today':
      return `/${encodeURIComponent(route.owner)}/${encodeURIComponent(route.repo)}/today${qs}`
  }
}

export function routeRepo(route: Route): { owner: string; repo: string } | null {
  if (route.kind === 'picker') return null
  return { owner: route.owner, repo: route.repo }
}

export function routeFolder(route: Route): string {
  if (route.kind === 'folder') return route.folder
  if (route.kind === 'file') {
    const slash = route.file.lastIndexOf('/')
    return slash >= 0 ? route.file.slice(0, slash) : ''
  }
  if (route.kind === 'today') return 'Daily Notes'
  return ''
}

export function routeFile(route: Route): string | null {
  return route.kind === 'file' ? route.file : null
}

export function routeQuery(route: Route): RouteQuery {
  return route.query ?? {}
}
