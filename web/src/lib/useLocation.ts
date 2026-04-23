import { useCallback, useEffect, useState } from 'react'
import { getBasePath, stripBase, withBase } from './basePath'

function rawPath(): string {
  if (typeof window === 'undefined') return '/'
  return window.location.pathname + window.location.search + window.location.hash
}

function appPath(base: string): string {
  if (typeof window === 'undefined') return '/'
  const stripped = stripBase(base, window.location.pathname)
  return stripped + window.location.search + window.location.hash
}

export function useLocation(): {
  path: string
  navigate: (to: string, options?: { replace?: boolean }) => void
} {
  const base = getBasePath()
  const [path, setPath] = useState<string>(() => appPath(base))

  useEffect(() => {
    const onPop = () => setPath(appPath(base))
    window.addEventListener('popstate', onPop)
    return () => window.removeEventListener('popstate', onPop)
  }, [base])

  const navigate = useCallback(
    (to: string, options?: { replace?: boolean }) => {
      const target = withBase(base, to)
      if (target === rawPath()) return
      if (options?.replace) {
        window.history.replaceState(null, '', target)
      } else {
        window.history.pushState(null, '', target)
      }
      setPath(appPath(base))
    },
    [base],
  )

  return { path, navigate }
}
