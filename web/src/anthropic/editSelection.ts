export const DEFAULT_MODEL = 'claude-sonnet-4-6'

export type EditSelectionResult =
  | { ok: true; text: string }
  | { ok: false; error: string }

export type EditSelectionInput = {
  apiKey: string
  model?: string
  instruction: string
  selection: string
  // Optional: whole-file context so Claude can match voice/style.
  documentContext?: string
  maxTokens?: number
}

const SYSTEM_PROMPT = [
  'You are an inline editor working on a single passage from the user\'s markdown note.',
  'You will receive the passage and a brief instruction describing how to change it.',
  'Rewrite the passage following the instruction.',
  'Return ONLY the rewritten passage. Do not add explanation, preface, apology, quotation marks, or code fences.',
  'Preserve markdown structure (links, bold, lists, etc.) unless the instruction explicitly asks otherwise.',
  'Match the user\'s existing tone and voice.',
].join(' ')

export async function editSelection(
  input: EditSelectionInput,
  fetchFn: typeof fetch = fetch,
): Promise<EditSelectionResult> {
  const {
    apiKey,
    model = DEFAULT_MODEL,
    instruction,
    selection,
    documentContext,
    maxTokens = 2048,
  } = input

  if (!apiKey) return { ok: false, error: 'No Anthropic API key configured.' }
  if (!instruction.trim()) return { ok: false, error: 'Empty instruction.' }
  if (!selection) return { ok: false, error: 'Empty selection.' }

  const userText = [
    documentContext
      ? `Context — the full note, for reference only. Do NOT rewrite anything outside the passage.\n---\n${documentContext}\n---\n`
      : '',
    `Passage to rewrite:\n---\n${selection}\n---`,
    `\nInstruction: ${instruction.trim()}`,
  ]
    .filter(Boolean)
    .join('\n')

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
      detail =
        parsed?.error?.message ??
        parsed?.message ??
        rawBody.slice(0, 300)
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
  const text = pieces.join('').trim()
  if (!text) return { ok: false, error: 'Empty response from Anthropic.' }
  return { ok: true, text }
}
