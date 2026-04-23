export function buildGitHubAuthorizeUrl(options: {
  clientId: string
  redirectUri: string
  state: string
  scope?: string
}): string {
  const url = new URL('https://github.com/login/oauth/authorize')
  url.searchParams.set('client_id', options.clientId)
  url.searchParams.set('redirect_uri', options.redirectUri)
  url.searchParams.set('state', options.state)
  url.searchParams.set('allow_signup', 'true')
  url.searchParams.set('scope', options.scope ?? 'repo read:user gist')
  return url.toString()
}
