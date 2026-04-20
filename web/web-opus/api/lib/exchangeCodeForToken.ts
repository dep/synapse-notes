export type ExchangeCodeResult =
  | { ok: true; accessToken: string }
  | { ok: false; error: string }

export async function exchangeCodeForToken(
  input: {
    code: string
    clientId: string
    clientSecret: string
    redirectUri: string
  },
  fetchFn: typeof fetch,
): Promise<ExchangeCodeResult> {
  const body = new URLSearchParams({
    client_id: input.clientId,
    client_secret: input.clientSecret,
    code: input.code,
    redirect_uri: input.redirectUri,
  })

  const res = await fetchFn('https://github.com/login/oauth/access_token', {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body,
  })

  const data = (await res.json()) as {
    access_token?: string
    error?: string
    error_description?: string
  }

  if (data.access_token) {
    return { ok: true, accessToken: data.access_token }
  }

  const message =
    data.error_description ??
    data.error ??
    `GitHub token exchange failed (${res.status})`
  return { ok: false, error: message }
}
