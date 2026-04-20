import type { VercelRequest, VercelResponse } from '@vercel/node'
import {
  defaultOAuthExchange,
  handleOAuthCallbackGet,
} from '../lib/oauthCallbackHandler'

function resolveAppOrigin(req: VercelRequest): string {
  const configured = process.env.PUBLIC_APP_ORIGIN?.replace(/\/$/, '')
  if (configured) {
    return configured
  }
  const rawProto = req.headers['x-forwarded-proto']
  const proto =
    typeof rawProto === 'string'
      ? rawProto.split(',')[0]?.trim() ?? 'https'
      : 'https'
  const rawHost = req.headers['x-forwarded-host'] ?? req.headers.host
  const host =
    typeof rawHost === 'string' ? rawHost.split(',')[0]?.trim() : undefined
  if (!host) {
    return 'http://localhost:5174'
  }
  return `${proto}://${host}`
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'GET') {
    res.status(405).setHeader('Allow', 'GET').send('Method Not Allowed')
    return
  }

  const clientId = process.env.GITHUB_CLIENT_ID ?? ''
  const clientSecret = process.env.GITHUB_CLIENT_SECRET ?? ''
  if (!clientId || !clientSecret) {
    res
      .status(500)
      .setHeader('Content-Type', 'text/plain; charset=utf-8')
      .send('Server is missing GITHUB_CLIENT_ID or GITHUB_CLIENT_SECRET.')
    return
  }

  const appOrigin = resolveAppOrigin(req)
  const base = appOrigin.endsWith('/') ? appOrigin.slice(0, -1) : appOrigin
  const url = new URL(typeof req.url === 'string' ? req.url : '/', `${base}/`)
  const result = await handleOAuthCallbackGet(url.searchParams, {
    clientId,
    clientSecret,
    appOrigin: base,
    exchange: defaultOAuthExchange,
  })

  res.status(result.status)
  if (result.headers) {
    for (const [key, value] of Object.entries(result.headers)) {
      res.setHeader(key, value)
    }
  }
  res.send(result.body)
}
