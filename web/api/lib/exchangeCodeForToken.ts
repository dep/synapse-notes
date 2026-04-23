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

  const raw = await res.text()
  let data: {
    access_token?: string
    error?: string
    error_description?: string
  } = {}
  try {
    data = JSON.parse(raw)
  } catch {
    // Non-JSON response — fall through with empty data and surface the body.
  }

  if (data.access_token) {
    return { ok: true, accessToken: data.access_token }
  }

  const message =
    data.error_description ??
    data.error ??
    `GitHub token exchange failed (${res.status}): ${raw.slice(0, 200)}`
  return { ok: false, error: message }
}
