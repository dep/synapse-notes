import type { ExchangeCodeResult } from './exchangeCodeForToken'
import { exchangeCodeForToken } from './exchangeCodeForToken'
import {
  GITHUB_TOKEN_SESSION_KEY,
  OAUTH_STATE_SESSION_KEY,
} from '../../src/auth/storageKeys'

export type OAuthCallbackDeps = {
  clientId: string
  clientSecret: string
  appOrigin: string
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

function redirectUriForApp(appOrigin: string): string {
  return `${normalizeOrigin(appOrigin)}/api/oauth/callback`
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

function buildOAuthErrorHtml(message: string): string {
  const safe = JSON.stringify(message)
  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"/><title>Sign-in failed</title></head>
<body>
<p>GitHub sign-in could not be completed.</p>
<script>
(function(){
  var message = ${safe};
  console.error(message);
  setTimeout(function(){ location.replace('/'); }, 2000);
})();
</script>
</body>
</html>`
}

function buildOAuthSuccessHtml(token: string, state: string): string {
  const tokenLiteral = JSON.stringify(token)
  const stateLiteral = JSON.stringify(state)
  const tokenKeyLiteral = JSON.stringify(GITHUB_TOKEN_SESSION_KEY)
  const stateKeyLiteral = JSON.stringify(OAUTH_STATE_SESSION_KEY)

  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"/><title>Signing in…</title></head>
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
    sessionStorage.setItem(tokenKey, token);
  } catch (e) {
    document.body.textContent = 'Could not complete sign-in (storage blocked?).';
    return;
  }
  location.replace('/');
})();
</script>
</body>
</html>`
}

export async function handleOAuthCallbackGet(
  searchParams: URLSearchParams,
  deps: OAuthCallbackDeps,
): Promise<{ status: number; headers?: Record<string, string>; body: string }> {
  const oauthError = searchParams.get('error')
  if (oauthError) {
    const detail = searchParams.get('error_description')
    const description = detail ? `${oauthError} — ${detail}` : oauthError
    return htmlResponse(buildOAuthErrorHtml(description))
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

  const redirectUri = redirectUriForApp(deps.appOrigin)
  const exchanged = await deps.exchange(
    {
      code,
      clientId: deps.clientId,
      clientSecret: deps.clientSecret,
      redirectUri,
    },
    fetch,
  )

  if (!exchanged.ok) {
    return htmlResponse(buildOAuthErrorHtml(exchanged.error))
  }

  return htmlResponse(buildOAuthSuccessHtml(exchanged.accessToken, state))
}

export const defaultOAuthExchange = exchangeCodeForToken
