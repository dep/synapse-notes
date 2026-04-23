export type FolderIconKey =
  | 'folder'
  | 'calendar'
  | 'edit'
  | 'group'
  | 'work'
  | 'archive'
  | 'book'
  | 'menu_book'
  | 'draft'
  | 'idea'
  | 'inbox'
  | 'task'
  | 'star'
  | 'label'
  | 'photo'
  | 'code'
  | 'science'
  | 'build'
  | 'public'
  | 'restaurant'
  | 'flight'
  | 'fitness'
  | 'piggy'
  | 'school'
  | 'description'
  | 'extension'
  | 'person'
  | 'settings'
  | 'history'
  | 'robot'
  | 'phone'
  | 'tv'
  | 'web'
  | 'summary'
  | 'files'

export type FolderStyle = {
  icon: FolderIconKey
  color: string
  // When true, the folder started with an emoji we should use instead of the icon.
  emoji: string | null
}

// Pretty-ish palette. Hand-picked to read well on dark backgrounds.
const PALETTE = [
  '#6EA8FE', // blue
  '#9B8CFF', // violet
  '#FF90B3', // pink
  '#FFB86B', // orange
  '#7DDE92', // green
  '#FFD166', // yellow
  '#5EEAD4', // teal
  '#F0ABFC', // magenta
  '#94A3B8', // slate
  '#F87171', // red
  '#67E8F9', // cyan
  '#C4B5FD', // lavender
]

type KeywordRule = {
  match: string[]
  // If true, match against word boundaries (split on non-alphanumeric). Use for
  // short tokens that would false-positive as substrings (e.g. "AI", "tv").
  wholeWord?: boolean
  icon: FolderIconKey
  color: string
}

// First-match wins. Ordered roughly by specificity so "journal" beats "notes"
// for a "journal notes" folder. Whole-word rules come first so short tokens
// like "AI" / "tv" don't get shadowed by longer substring matches.
const RULES: KeywordRule[] = [
  // Whole-word rules (short tokens that would false-positive as substrings).
  { match: ['ai', 'llm', 'gpt', 'claude'], wholeWord: true, icon: 'robot', color: '#9B8CFF' },
  { match: ['tv', 'shows'], wholeWord: true, icon: 'tv', color: '#FF90B3' },
  { match: ['web', 'sites'], wholeWord: true, icon: 'web', color: '#67E8F9' },

  { match: ['daily', 'journal', 'diary', 'log'], icon: 'calendar', color: '#6EA8FE' },
  { match: ['meeting', '1on1', '1-on-1', 'standup'], icon: 'group', color: '#9B8CFF' },
  { match: ['people', 'team', 'contacts'], icon: 'person', color: '#F0ABFC' },
  { match: ['project'], icon: 'work', color: '#9B8CFF' },
  { match: ['work', 'job'], icon: 'work', color: '#6EA8FE' },
  { match: ['inbox', 'intake'], icon: 'inbox', color: '#5EEAD4' },
  { match: ['draft'], icon: 'draft', color: '#94A3B8' },
  { match: ['archive', 'archived', 'old'], icon: 'archive', color: '#94A3B8' },
  { match: ['idea', 'brainstorm'], icon: 'idea', color: '#FFD166' },
  { match: ['todo', 'task'], icon: 'task', color: '#7DDE92' },
  { match: ['starred', 'favorite', 'fave'], icon: 'star', color: '#FFD166' },
  { match: ['tag'], icon: 'label', color: '#F0ABFC' },
  { match: ['mobile', 'phone', 'ios', 'android'], icon: 'phone', color: '#5EEAD4' },
  { match: ['movie', 'film', 'cinema'], icon: 'tv', color: '#FF90B3' },
  { match: ['website', 'landing'], icon: 'web', color: '#67E8F9' },
  { match: ['summary', 'summaries', 'recap', 'digest', 'tldr'], icon: 'summary', color: '#FFD166' },
  { match: ['image', 'photo', 'media', 'attachment', 'asset'], icon: 'photo', color: '#FF90B3' },
  { match: ['code', 'snippet', 'script'], icon: 'code', color: '#67E8F9' },
  { match: ['research', 'paper'], icon: 'science', color: '#C4B5FD' },
  { match: ['tool', 'setup'], icon: 'build', color: '#FFB86B' },
  { match: ['blog', 'post', 'essay', 'writing'], icon: 'edit', color: '#FF90B3' },
  { match: ['book', 'reading'], icon: 'menu_book', color: '#FFB86B' },
  { match: ['recipe', 'food', 'cooking'], icon: 'restaurant', color: '#F87171' },
  { match: ['travel', 'trip'], icon: 'flight', color: '#6EA8FE' },
  { match: ['health', 'fitness', 'workout'], icon: 'fitness', color: '#7DDE92' },
  { match: ['finance', 'money', 'budget'], icon: 'piggy', color: '#7DDE92' },
  { match: ['learn', 'study', 'course', 'tutorial'], icon: 'school', color: '#C4B5FD' },
  { match: ['reference', 'doc', 'manual'], icon: 'description', color: '#94A3B8' },
  { match: ['wiki', 'knowledge', 'kb'], icon: 'public', color: '#5EEAD4' },
  { match: ['template'], icon: 'extension', color: '#C4B5FD' },
  { match: ['setting', 'config'], icon: 'settings', color: '#94A3B8' },
  { match: ['scratch', 'playground'], icon: 'draft', color: '#94A3B8' },
  { match: ['history', 'past'], icon: 'history', color: '#94A3B8' },
  { match: ['files'], icon: 'files', color: '#94A3B8' },
  { match: ['note'], icon: 'description', color: '#6EA8FE' },
]

function tokensOf(name: string): string[] {
  return name.toLowerCase().split(/[^a-z0-9]+/).filter(Boolean)
}

// Strip a leading emoji (if any) + any trailing whitespace from the name, and
// return both pieces. Matches characters with the Emoji unicode property.
const EMOJI_PREFIX_REGEX = /^\s*(\p{Extended_Pictographic}(?:️|‍\p{Extended_Pictographic})*)\s*/u

export function extractLeadingEmoji(name: string): {
  emoji: string | null
  rest: string
} {
  const match = name.match(EMOJI_PREFIX_REGEX)
  if (!match) return { emoji: null, rest: name }
  return { emoji: match[1], rest: name.slice(match[0].length) }
}

function hashString(s: string): number {
  let h = 0
  for (let i = 0; i < s.length; i++) {
    h = (h << 5) - h + s.charCodeAt(i)
    h |= 0
  }
  return Math.abs(h)
}

export function colorFromHash(s: string): string {
  return PALETTE[hashString(s) % PALETTE.length]
}

export function folderStyleFor(name: string): FolderStyle {
  const { emoji, rest } = extractLeadingEmoji(name)
  if (emoji) {
    // Emoji wins; still pick a palette color deterministically so the label bar
    // of color matches across renders.
    return { icon: 'folder', emoji, color: colorFromHash(rest || name) }
  }
  const lower = name.toLowerCase()
  const tokens = new Set(tokensOf(name))
  for (const rule of RULES) {
    const hit = rule.wholeWord
      ? rule.match.some((kw) => tokens.has(kw))
      : rule.match.some((kw) => lower.includes(kw))
    if (hit) {
      return { icon: rule.icon, color: rule.color, emoji: null }
    }
  }
  return { icon: 'folder', color: colorFromHash(name), emoji: null }
}
