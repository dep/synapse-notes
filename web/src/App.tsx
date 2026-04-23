import { useCallback, useEffect, useMemo, useState } from 'react'
import { Alert, Box, CircularProgress } from '@mui/material'
import { useAuth } from './auth/AuthContext'
import { SignIn } from './components/SignIn'
import { RepoPicker } from './components/RepoPicker'
import { RepoEditor } from './components/RepoEditor'
import { useLocation } from './lib/useLocation'
import { formatRoute, parseRoute, routeRepo } from './lib/route'
import { fetchRepoByFullName } from './github/repos'

export type SelectedRepo = {
  fullName: string
  defaultBranch: string
}

export function App() {
  const { token } = useAuth()
  const { path, navigate } = useLocation()
  const route = useMemo(() => parseRoute(path), [path])
  const repoInRoute = routeRepo(route)
  const repoKey = repoInRoute ? `${repoInRoute.owner}/${repoInRoute.repo}` : null

  const [resolvedRepo, setResolvedRepo] = useState<SelectedRepo | null>(null)
  const [repoLookupError, setRepoLookupError] = useState<string | null>(null)
  const [repoLoading, setRepoLoading] = useState(false)

  useEffect(() => {
    if (!token || !repoKey) {
      setResolvedRepo(null)
      setRepoLookupError(null)
      return
    }
    if (resolvedRepo?.fullName === repoKey) return
    let cancelled = false
    setRepoLoading(true)
    setRepoLookupError(null)
    void fetchRepoByFullName(token, repoKey).then((result) => {
      if (cancelled) return
      setRepoLoading(false)
      if (result.ok) {
        setResolvedRepo({
          fullName: result.repo.full_name,
          defaultBranch: result.repo.default_branch,
        })
      } else {
        setResolvedRepo(null)
        setRepoLookupError(result.error)
      }
    })
    return () => {
      cancelled = true
    }
    // resolvedRepo intentionally excluded — we re-resolve only when the URL changes
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token, repoKey])

  const handlePickRepo = useCallback(
    (repo: SelectedRepo) => {
      setResolvedRepo(repo)
      const [owner, name] = repo.fullName.split('/')
      navigate(formatRoute({ kind: 'repo', owner, repo: name, query: {} }))
    },
    [navigate],
  )

  const handleChangeRepo = useCallback(() => {
    setResolvedRepo(null)
    navigate('/')
  }, [navigate])

  if (!token) {
    return (
      <Box sx={{ minHeight: '100vh', display: 'grid', placeItems: 'center' }}>
        <SignIn />
      </Box>
    )
  }

  if (!repoInRoute) {
    return (
      <Box sx={{ minHeight: '100vh' }}>
        <RepoPicker onSelect={handlePickRepo} />
      </Box>
    )
  }

  if (repoLookupError) {
    return (
      <Box sx={{ p: 4 }}>
        <Alert severity="error">
          Couldn't load <code>{repoKey}</code>: {repoLookupError}
        </Alert>
      </Box>
    )
  }

  if (!resolvedRepo || repoLoading) {
    return (
      <Box sx={{ minHeight: '100vh', display: 'grid', placeItems: 'center' }}>
        <CircularProgress />
      </Box>
    )
  }

  return (
    <RepoEditor
      repo={resolvedRepo}
      route={route}
      navigate={navigate}
      onChangeRepo={handleChangeRepo}
    />
  )
}
