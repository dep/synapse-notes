import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import {
  canPublishGist,
  createGist,
  fetchOAuthScopes,
  parseScopesHeader,
} from '../gists'

describe('parseScopesHeader', () => {
  it('handles null/empty', () => {
    expect(parseScopesHeader(null)).toEqual([])
    expect(parseScopesHeader('')).toEqual([])
  })
  it('splits comma-separated scopes', () => {
    expect(parseScopesHeader('repo, gist, read:user')).toEqual([
      'repo',
      'gist',
      'read:user',
    ])
  })
  it('drops empty entries', () => {
    expect(parseScopesHeader('repo, , gist')).toEqual(['repo', 'gist'])
  })
})

describe('canPublishGist', () => {
  it('is true only when gist is present', () => {
    expect(canPublishGist(['repo'])).toBe(false)
    expect(canPublishGist(['repo', 'gist'])).toBe(true)
  })
})

describe('fetchOAuthScopes', () => {
  const originalFetch = globalThis.fetch
  afterEach(() => {
    globalThis.fetch = originalFetch
  })

  it('returns scopes from X-OAuth-Scopes header', async () => {
    globalThis.fetch = vi.fn(async () =>
      new Response('{}', {
        status: 200,
        headers: { 'X-OAuth-Scopes': 'repo, gist' },
      }),
    ) as unknown as typeof fetch
    const result = await fetchOAuthScopes('t')
    expect(result).toEqual({ ok: true, scopes: ['repo', 'gist'] })
  })

  it('returns empty scopes when header is missing', async () => {
    globalThis.fetch = vi.fn(async () =>
      new Response('{}', { status: 200 }),
    ) as unknown as typeof fetch
    const result = await fetchOAuthScopes('t')
    expect(result).toEqual({ ok: true, scopes: [] })
  })

  it('propagates non-2xx as error', async () => {
    globalThis.fetch = vi.fn(async () =>
      new Response('nope', { status: 401 }),
    ) as unknown as typeof fetch
    const result = await fetchOAuthScopes('t')
    expect(result.ok).toBe(false)
  })
})

describe('createGist', () => {
  const originalFetch = globalThis.fetch
  beforeEach(() => {
    globalThis.fetch = vi.fn(async () =>
      new Response(
        JSON.stringify({ html_url: 'https://gist.github.com/abc', id: 'abc' }),
        { status: 201 },
      ),
    ) as unknown as typeof fetch
  })
  afterEach(() => {
    globalThis.fetch = originalFetch
  })

  it('calls the gists endpoint with the expected body', async () => {
    const result = await createGist('t', {
      filename: 'README.md',
      content: '# hi',
      description: 'desc',
      isPublic: false,
    })
    expect(result).toEqual({
      ok: true,
      htmlUrl: 'https://gist.github.com/abc',
      id: 'abc',
    })
    const mockFetch = globalThis.fetch as unknown as ReturnType<typeof vi.fn>
    const [url, init] = mockFetch.mock.calls[0]
    expect(url).toBe('https://api.github.com/gists')
    expect(init.method).toBe('POST')
    const payload = JSON.parse(init.body as string)
    expect(payload).toEqual({
      description: 'desc',
      public: false,
      files: { 'README.md': { content: '# hi' } },
    })
  })

  it('returns the scope hint on 404', async () => {
    globalThis.fetch = vi.fn(async () =>
      new Response('{}', { status: 404 }),
    ) as unknown as typeof fetch
    const result = await createGist('t', {
      filename: 'x.md',
      content: 'hi',
      isPublic: false,
    })
    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.error).toMatch(/gist/)
  })

  it('returns raw server text on other errors', async () => {
    globalThis.fetch = vi.fn(async () =>
      new Response('boom', { status: 500 }),
    ) as unknown as typeof fetch
    const result = await createGist('t', {
      filename: 'x.md',
      content: 'hi',
      isPublic: false,
    })
    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.error).toContain('500')
  })
})
