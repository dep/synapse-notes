import { describe, expect, it, vi } from 'vitest'
import { DEFAULT_MODEL, editSelection } from '../editSelection'

const okBody = {
  id: 'msg_1',
  type: 'message',
  role: 'assistant',
  content: [{ type: 'text', text: 'rewritten' }],
}

function mockFetchOk(responseJson: unknown): typeof fetch {
  return (async () =>
    new Response(JSON.stringify(responseJson), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })) as unknown as typeof fetch
}

function mockFetchErr(status: number, body: string): typeof fetch {
  return (async () =>
    new Response(body, {
      status,
      headers: { 'Content-Type': 'application/json' },
    })) as unknown as typeof fetch
}

describe('editSelection', () => {
  it('rejects missing api key / instruction / selection', async () => {
    const fetchFn = vi.fn(mockFetchOk(okBody))
    expect(
      await editSelection(
        { apiKey: '', instruction: 'x', selection: 'y' },
        fetchFn,
      ),
    ).toEqual({ ok: false, error: 'No Anthropic API key configured.' })
    expect(
      await editSelection(
        { apiKey: 'k', instruction: '  ', selection: 'y' },
        fetchFn,
      ),
    ).toEqual({ ok: false, error: 'Empty instruction.' })
    expect(
      await editSelection(
        { apiKey: 'k', instruction: 'x', selection: '' },
        fetchFn,
      ),
    ).toEqual({ ok: false, error: 'Empty selection.' })
    expect(fetchFn).not.toHaveBeenCalled()
  })

  it('calls Anthropic with the expected body and returns the text', async () => {
    const fetchFn = vi.fn(mockFetchOk(okBody))
    const result = await editSelection(
      { apiKey: 'sk-ant-xx', instruction: 'shorten', selection: 'hello world' },
      fetchFn,
    )
    expect(result).toEqual({ ok: true, text: 'rewritten' })
    expect(fetchFn).toHaveBeenCalledOnce()
    const [url, init] = (fetchFn as unknown as ReturnType<typeof vi.fn>).mock
      .calls[0]
    expect(url).toBe('https://api.anthropic.com/v1/messages')
    const headers = (init as RequestInit).headers as Record<string, string>
    expect(headers['x-api-key']).toBe('sk-ant-xx')
    expect(headers['anthropic-version']).toBe('2023-06-01')
    expect(headers['anthropic-dangerous-direct-browser-access']).toBe('true')
    const payload = JSON.parse((init as RequestInit).body as string)
    expect(payload.model).toBe(DEFAULT_MODEL)
    expect(Array.isArray(payload.messages)).toBe(true)
    expect(payload.messages[0].role).toBe('user')
    expect(String(payload.messages[0].content)).toContain('hello world')
    expect(String(payload.messages[0].content)).toContain('shorten')
  })

  it('includes document context when provided', async () => {
    const fetchFn = vi.fn(mockFetchOk(okBody))
    await editSelection(
      {
        apiKey: 'k',
        instruction: 'x',
        selection: 'y',
        documentContext: 'THE WHOLE FILE',
      },
      fetchFn,
    )
    const payload = JSON.parse(
      (
        (fetchFn as unknown as ReturnType<typeof vi.fn>).mock
          .calls[0][1] as RequestInit
      ).body as string,
    )
    expect(String(payload.messages[0].content)).toContain('THE WHOLE FILE')
  })

  it('surfaces API error messages', async () => {
    const fetchFn = vi.fn(
      mockFetchErr(
        401,
        JSON.stringify({ error: { message: 'invalid x-api-key' } }),
      ),
    )
    const result = await editSelection(
      { apiKey: 'k', instruction: 'x', selection: 'y' },
      fetchFn,
    )
    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.error).toContain('invalid x-api-key')
  })

  it('handles non-JSON error bodies', async () => {
    const fetchFn = vi.fn(mockFetchErr(500, 'internal error'))
    const result = await editSelection(
      { apiKey: 'k', instruction: 'x', selection: 'y' },
      fetchFn,
    )
    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.error).toContain('500')
  })

  it('rejects empty text responses', async () => {
    const fetchFn = vi.fn(
      mockFetchOk({ content: [{ type: 'text', text: '   ' }] }),
    )
    const result = await editSelection(
      { apiKey: 'k', instruction: 'x', selection: 'y' },
      fetchFn,
    )
    expect(result.ok).toBe(false)
  })
})
