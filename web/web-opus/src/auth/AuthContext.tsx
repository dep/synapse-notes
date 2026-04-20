import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import { buildGitHubAuthorizeUrl } from '../github/buildAuthorizeUrl'
import {
  GITHUB_TOKEN_SESSION_KEY,
  OAUTH_STATE_SESSION_KEY,
  REPO_SELECTION_LOCAL_KEY,
} from './storageKeys'

export type AuthContextValue = {
  token: string | null
  clientConfigured: boolean
  beginGitHubLogin: () => void
  logout: () => void
}

const AuthContext = createContext<AuthContextValue | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const clientId = import.meta.env.VITE_GITHUB_CLIENT_ID ?? ''
  const [token, setToken] = useState<string | null>(() =>
    sessionStorage.getItem(GITHUB_TOKEN_SESSION_KEY),
  )

  const beginGitHubLogin = useCallback(() => {
    if (!clientId) {
      return
    }
    const fromEnv = import.meta.env.VITE_PUBLIC_APP_ORIGIN?.replace(/\/$/, '')
    const origin = fromEnv ?? window.location.origin
    const state = crypto.randomUUID()
    sessionStorage.setItem(OAUTH_STATE_SESSION_KEY, state)
    const redirectUri = `${origin}/api/oauth/callback`
    const url = buildGitHubAuthorizeUrl({ clientId, redirectUri, state })
    window.location.assign(url)
  }, [clientId])

  const logout = useCallback(() => {
    sessionStorage.removeItem(GITHUB_TOKEN_SESSION_KEY)
    localStorage.removeItem(REPO_SELECTION_LOCAL_KEY)
    setToken(null)
  }, [])

  const value = useMemo<AuthContextValue>(
    () => ({
      token,
      clientConfigured: Boolean(clientId),
      beginGitHubLogin,
      logout,
    }),
    [token, clientId, beginGitHubLogin, logout],
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
