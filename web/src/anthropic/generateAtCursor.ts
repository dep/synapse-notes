import { DEFAULT_MODEL } from './editSelection'

export type GenerateAtCursorResult =
  | { ok: true; text: string }
  | { ok: false; error: string }

export type GenerateAtCursorInput = {
  apiKey: string
  model?: string
  instruction: string
  // Full document content; we'll inject a sentinel at `cursorOffset` so the
  // model knows where to insert.
  document: string
  cursorOffset: number
  maxTokens?: number
}

export const CURSOR_SENTINEL = '<<<INSERT HERE>>>'

const SYSTEM_PROMPT = [
  `You help the user extend a markdown note.`,
  `The user's note contains the marker ${CURSOR_SENTINEL} exactly where they want new content inserted.`,
  `Produce ONLY the text that should replace the marker. Do not repeat surrounding content. Do not echo the marker. No quotation, no code fences, no prose about what you did.`,
  `Match the surrounding tone and markdown style (links, bold, lists, etc.).`,
  `Pay attention to indentation and whether the surrounding text is mid-paragraph, a new line, a list item, etc. — your insertion should fit naturally in place.`,
].join(' ')

export function buildDocumentWithSentinel(
  document: string,
  cursorOffset: number,
): string {
  const clamped = Math.max(0, Math.min(cursorOffset, document.length))
  return document.slice(0, clamped) + CURSOR_SENTINEL + document.slice(clamped)
}

export async function generateAtCursor(
  input: GenerateAtCursorInput,
  fetchFn: typeof fetch = fetch,
): Promise<GenerateAtCursorResult> {
  const {
    apiKey,
    model = DEFAULT_MODEL,
    instruction,
    document,
    cursorOffset,
    maxTokens = 2048,
  } = input

  if (!apiKey) return { ok: false, error: 'No Anthropic API key configured.' }
  if (!instruction.trim()) return { ok: false, error: 'Empty instruction.' }

  const withMarker = buildDocumentWithSentinel(document, cursorOffset)
  const userText = [
    `The note, with ${CURSOR_SENTINEL} marking the insertion point:`,
    '---',
    withMarker,
    '---',
    '',
    `Instruction: ${instruction.trim()}`,
  ].join('\n')

  let res: Response
  try {
    res = await fetchFn('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'anthropic-dangerous-direct-browser-access': 'true',
      },
      body: JSON.stringify({
        model,
        max_tokens: maxTokens,
        system: SYSTEM_PROMPT,
        messages: [{ role: 'user', content: userText }],
      }),
    })
  } catch (err) {
    return {
      ok: false,
      error: err instanceof Error ? err.message : 'Network error.',
    }
  }

  const rawBody = await res.text()
  if (!res.ok) {
    let detail = rawBody
    try {
      const parsed = JSON.parse(rawBody)
      detail = parsed?.error?.message ?? parsed?.message ?? rawBody.slice(0, 300)
    } catch {
      detail = rawBody.slice(0, 300)
    }
    return { ok: false, error: `Anthropic API error (${res.status}): ${detail}` }
  }

  let data: unknown
  try {
    data = JSON.parse(rawBody)
  } catch {
    return { ok: false, error: 'Unexpected non-JSON response from Anthropic.' }
  }
  const content = (data as { content?: unknown })?.content
  if (!Array.isArray(content)) {
    return { ok: false, error: 'Malformed response (no content array).' }
  }
  const pieces: string[] = []
  for (const block of content) {
    if (
      block &&
      typeof block === 'object' &&
      (block as { type?: unknown }).type === 'text' &&
      typeof (block as { text?: unknown }).text === 'string'
    ) {
      pieces.push((block as { text: string }).text)
    }
  }
  // Safety net: if the model echoed the sentinel back, strip it out.
  const text = pieces.join('').split(CURSOR_SENTINEL).join('')
  const trimmed = text.trim()
  if (!trimmed) return { ok: false, error: 'Empty response from Anthropic.' }
  // Intentionally return `text` (not trimmed) so surrounding whitespace from
  // the model is preserved — Claude typically emits clean output already.
  return { ok: true, text }
}
