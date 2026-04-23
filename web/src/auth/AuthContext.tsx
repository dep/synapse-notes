import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import { buildGitHubAuthorizeUrl } from '../github/buildAuthorizeUrl'
import { fetchOAuthScopes } from '../github/gists'
import { getBasePath, withBase } from '../lib/basePath'
import {
  GITHUB_TOKEN_STORAGE_KEY,
  OAUTH_STATE_SESSION_KEY,
  REPO_SELECTION_LOCAL_KEY,
} from './storageKeys'

export type AuthContextValue = {
  token: string | null
  scopes: string[]
  clientConfigured: boolean
  beginGitHubLogin: () => void
  logout: () => void
}

const AuthContext = createContext<AuthContextValue | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const clientId = import.meta.env.VITE_GITHUB_CLIENT_ID ?? ''
  const [token, setToken] = useState<string | null>(() =>
    localStorage.getItem(GITHUB_TOKEN_STORAGE_KEY),
  )
  const [scopes, setScopes] = useState<string[]>([])

  const clearToken = useCallback(() => {
    localStorage.removeItem(GITHUB_TOKEN_STORAGE_KEY)
    setToken(null)
  }, [])

  useEffect(() => {
    if (!token) {
      setScopes([])
      return
    }
    let cancelled = false
    void fetchOAuthScopes(token).then((result) => {
      if (cancelled) return
      if (result.ok) {
        setScopes(result.scopes)
      } else if (/401/.test(result.error)) {
        // Token is no longer valid — drop it so the user can re-auth.
        clearToken()
      }
    })
    return () => {
      cancelled = true
    }
  }, [token, clearToken])

  const beginGitHubLogin = useCallback(() => {
    if (!clientId) {
      return
    }
    const fromEnv = import.meta.env.VITE_PUBLIC_APP_ORIGIN?.replace(/\/$/, '')
    const origin = fromEnv ?? window.location.origin
    const state = crypto.randomUUID()
    sessionStorage.setItem(OAUTH_STATE_SESSION_KEY, state)
    const redirectUri = `${origin}${withBase(getBasePath(), '/api/oauth/callback')}`
    const url = buildGitHubAuthorizeUrl({ clientId, redirectUri, state })
    window.location.assign(url)
  }, [clientId])

  const logout = useCallback(() => {
    localStorage.removeItem(GITHUB_TOKEN_STORAGE_KEY)
    localStorage.removeItem(REPO_SELECTION_LOCAL_KEY)
    setToken(null)
  }, [])

  const value = useMemo<AuthContextValue>(
    () => ({
      token,
      scopes,
      clientConfigured: Boolean(clientId),
      beginGitHubLogin,
      logout,
    }),
    [token, scopes, clientId, beginGitHubLogin, logout],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext)
  if (!ctx) {
    throw new Error('useAuth must be used within AuthProvider')
  }
  return ctx
}
