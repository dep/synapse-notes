import type { ExchangeCodeResult } from './exchangeCodeForToken.js'
import { exchangeCodeForToken } from './exchangeCodeForToken.js'

// Must stay in sync with src/auth/storageKeys.ts. Duplicated here so this
// Vercel function doesn't import from the Vite app source tree at build time.
const GITHUB_TOKEN_STORAGE_KEY = 'synapse_github_token'
const OAUTH_STATE_SESSION_KEY = 'synapse_oauth_state'

export type OAuthCallbackDeps = {
  clientId: string
  clientSecret: string
  appOrigin: string
  basePath?: string
  exchange: (
    input: {
      code: string
      clientId: string
      clientSecret: string
      redirectUri: string
    },
    fetchFn: typeof fetch,
  ) => Promise<ExchangeCodeResult>
}

function normalizeOrigin(origin: string): string {
  return origin.replace(/\/$/, '')
}

function normalizeBase(base: string | undefined): string {
  if (!base) return '/'
  let out = base
  if (!out.startsWith('/')) out = `/${out}`
  if (!out.endsWith('/')) out = `${out}/`
  return out
}

function redirectUriForApp(appOrigin: string, basePath: string): string {
  const suffix = basePath === '/' ? '/api/oauth/callback' : `${basePath.slice(0, -1)}/api/oauth/callback`
  return `${normalizeOrigin(appOrigin)}${suffix}`
}

function htmlResponse(
  body: string,
): { status: number; headers: Record<string, string>; body: string } {
  return {
    status: 200,
    headers: { 'Content-Type': 'text/html; charset=utf-8' },
    body,
  }
}

function buildOAuthErrorHtml(message: string, basePath: string): string {
  const safe = JSON.stringify(message)
  const home = JSON.stringify(basePath)
  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"/><title>Synapse Web · Sign-in failed</title></head>
<body>
<p>GitHub sign-in could not be completed.</p>
<script>
(function(){
  var message = ${safe};
  console.error(message);
  setTimeout(function(){ location.replace(${home}); }, 2000);
})();
</script>
</body>
</html>`
}

function buildOAuthSuccessHtml(
  token: string,
  state: string,
  basePath: string,
): string {
  const tokenLiteral = JSON.stringify(token)
  const stateLiteral = JSON.stringify(state)
  const tokenKeyLiteral = JSON.stringify(GITHUB_TOKEN_STORAGE_KEY)
  const stateKeyLiteral = JSON.stringify(OAUTH_STATE_SESSION_KEY)
  const home = JSON.stringify(basePath)

  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"/><title>Synapse Web · Signing in…</title></head>
<body>
<script>
(function(){
  var tokenKey = ${tokenKeyLiteral};
  var stateKey = ${stateKeyLiteral};
  var expectedState = ${stateLiteral};
  var token = ${tokenLiteral};
  try {
    var stored = sessionStorage.getItem(stateKey);
    if (!stored || stored !== expectedState) {
      document.body.textContent = 'OAuth state mismatch. Close this tab and try again.';
      return;
    }
    sessionStorage.removeItem(stateKey);
    localStorage.setItem(tokenKey, token);
  } catch (e) {
    document.body.textContent = 'Could not complete sign-in (storage blocked?).';
    return;
  }
  location.replace(${home});
})();
</script>
</body>
</html>`
}

export async function handleOAuthCallbackGet(
  searchParams: URLSearchParams,
  deps: OAuthCallbackDeps,
): Promise<{ status: number; headers?: Record<string, string>; body: string }> {
  const basePath = normalizeBase(deps.basePath)
  const oauthError = searchParams.get('error')
  if (oauthError) {
    const detail = searchParams.get('error_description')
    const description = detail ? `${oauthError} — ${detail}` : oauthError
    return htmlResponse(buildOAuthErrorHtml(description, basePath))
  }

  const code = searchParams.get('code')
  const state = searchParams.get('state')
  if (!code || !state) {
    return {
      status: 400,
      headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      body: 'Missing OAuth code or state.',
    }
  }

  const redirectUri = redirectUriForApp(deps.appOrigin, basePath)
  const exchanged = await deps.exchange(
    {
      code,
      clientId: deps.clientId,
      clientSecret: deps.clientSecret,
      redirectUri,
    },
    fetch,
  )

  if (exchanged.ok === true) {
    return htmlResponse(buildOAuthSuccessHtml(exchanged.accessToken, state, basePath))
  }
  return htmlResponse(buildOAuthErrorHtml(exchanged.error, basePath))
}

export const defaultOAuthExchange = exchangeCodeForToken
