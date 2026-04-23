import type { IncomingMessage, ServerResponse } from 'node:http'
import react from '@vitejs/plugin-react'
import { loadEnv, defineConfig } from 'vite'
import type { Plugin } from 'vite'
import {
  defaultOAuthExchange,
  handleOAuthCallbackGet,
} from './api/lib/oauthCallbackHandler'

function oauthCallbackDevPlugin(mode: string): Plugin {
  return {
    name: 'opus-oauth-callback-dev',
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        const path = req.url ?? ''
        if (!path.startsWith('/api/oauth/callback')) {
          next()
          return
        }
        if (req.method !== 'GET') {
          res.statusCode = 405
          res.setHeader('Allow', 'GET')
          res.end('Method Not Allowed')
          return
        }
        void handleDevOAuth(req, res, mode)
      })
    },
  }
}

async function handleDevOAuth(
  req: IncomingMessage,
  res: ServerResponse,
  mode: string,
) {
  const env = loadEnv(mode, process.cwd(), '')
  if (!env.GITHUB_CLIENT_ID || !env.GITHUB_CLIENT_SECRET) {
    res.statusCode = 500
    res.setHeader('Content-Type', 'text/plain; charset=utf-8')
    res.end(
      'Missing GITHUB_CLIENT_ID or GITHUB_CLIENT_SECRET. Copy .env.example to .env.local and fill in values.',
    )
    return
  }

  const host = req.headers.host ?? 'localhost'
  const appOrigin = `http://${host}`
  const parsed = new URL(req.url ?? '/', `${appOrigin}/`)

  const result = await handleOAuthCallbackGet(parsed.searchParams, {
    clientId: env.GITHUB_CLIENT_ID,
    clientSecret: env.GITHUB_CLIENT_SECRET,
    appOrigin,
    basePath: env.VITE_BASE_PATH ?? '/',
    exchange: defaultOAuthExchange,
  })

  res.statusCode = result.status
  if (result.headers) {
    for (const [key, value] of Object.entries(result.headers)) {
      res.setHeader(key, value)
    }
  }
  res.end(result.body)
}

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const base = env.VITE_BASE_PATH || '/'
  return {
    base,
    plugins: [react(), oauthCallbackDevPlugin(mode)],
    server: {
      port: 5174,
    },
    test: {
      environment: 'jsdom',
      globals: true,
      setupFiles: ['./vitest.setup.ts'],
      css: false,
    },
  }
})
