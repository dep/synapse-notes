export function getBasePath(): string {
  const raw = import.meta.env.BASE_URL ?? '/'
  return normalizeBasePath(raw)
}

export function normalizeBasePath(raw: string): string {
  if (!raw) return '/'
  let out = raw
  if (!out.startsWith('/')) out = `/${out}`
  if (!out.endsWith('/')) out = `${out}/`
  return out
}

export function withBase(base: string, path: string): string {
  const normBase = normalizeBasePath(base)
  if (normBase === '/') return path.startsWith('/') ? path : `/${path}`
  const trimmed = path.startsWith('/') ? path.slice(1) : path
  return `${normBase}${trimmed}`
}

export function stripBase(base: string, pathname: string): string {
  const normBase = normalizeBasePath(base)
  if (normBase === '/') return pathname || '/'
  const prefix = normBase.slice(0, -1)
  if (pathname === prefix) return '/'
  if (pathname.startsWith(normBase)) {
    return `/${pathname.slice(normBase.length)}`
  }
  return pathname || '/'
}
