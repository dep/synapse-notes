import { describe, expect, it, vi } from 'vitest'
import {
  CURSOR_SENTINEL,
  buildDocumentWithSentinel,
  generateAtCursor,
} from '../generateAtCursor'

function mockFetchOk(text: string): typeof fetch {
  return (async () =>
    new Response(
      JSON.stringify({ content: [{ type: 'text', text }] }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    )) as unknown as typeof fetch
}

describe('buildDocumentWithSentinel', () => {
  it('inserts the sentinel at the given offset', () => {
    expect(buildDocumentWithSentinel('hello world', 5)).toBe(
      `hello${CURSOR_SENTINEL} world`,
    )
  })

  it('clamps to the document length', () => {
    expect(buildDocumentWithSentinel('abc', -5).startsWith(CURSOR_SENTINEL)).toBe(
      true,
    )
    expect(buildDocumentWithSentinel('abc', 999).endsWith(CURSOR_SENTINEL)).toBe(
      true,
    )
  })
})

describe('generateAtCursor', () => {
  it('rejects missing api key / empty instruction', async () => {
    const fetchFn = vi.fn(mockFetchOk('ignored'))
    expect(
      await generateAtCursor(
        { apiKey: '', instruction: 'hi', document: 'x', cursorOffset: 0 },
        fetchFn,
      ),
    ).toEqual({ ok: false, error: 'No Anthropic API key configured.' })
    expect(
      await generateAtCursor(
        { apiKey: 'k', instruction: '  ', document: 'x', cursorOffset: 0 },
        fetchFn,
      ),
    ).toEqual({ ok: false, error: 'Empty instruction.' })
    expect(fetchFn).not.toHaveBeenCalled()
  })

  it('sends a prompt containing the sentinel-marked document', async () => {
    const fetchFn = vi.fn(mockFetchOk('inserted'))
    const result = await generateAtCursor(
      {
        apiKey: 'k',
        instruction: 'continue the paragraph',
        document: 'The quick brown fox',
        cursorOffset: 15,
      },
      fetchFn,
    )
    expect(result).toEqual({ ok: true, text: 'inserted' })
    const payload = JSON.parse(
      (
        (fetchFn as unknown as ReturnType<typeof vi.fn>).mock
          .calls[0][1] as RequestInit
      ).body as string,
    )
    const content = String(payload.messages[0].content)
    expect(content).toContain(CURSOR_SENTINEL)
    expect(content).toContain('continue the paragraph')
    expect(content).toContain('The quick brown')
  })

  it('strips echoed sentinels from the output', async () => {
    const fetchFn = vi.fn(mockFetchOk(`pre${CURSOR_SENTINEL}post`))
    const result = await generateAtCursor(
      { apiKey: 'k', instruction: 'x', document: 'x', cursorOffset: 0 },
      fetchFn,
    )
    expect(result).toEqual({ ok: true, text: 'prepost' })
  })
})
