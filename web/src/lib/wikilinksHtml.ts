import type { WikilinkIndex } from './wikilinks'
import { WIKILINK_REGEX, resolveWikilink } from './wikilinks'

// Walks text nodes in the given HTML string, skipping <code>, <pre>, and <a>
// content, replacing [[links]] with resolved or unresolved spans/anchors.
// Uses DOMParser, which requires a browser/jsdom environment.
//
// Anchors use data-wikilink-path="..." and href="#wikilink:<path>" so they
// behave like normal links visually while also being distinguishable by a
// click handler.
export function applyWikilinks(
  html: string,
  index: WikilinkIndex,
): string {
  if (typeof DOMParser === 'undefined') return html
  const parser = new DOMParser()
  // marked returns a fragment; wrap so we parse as a full document.
  const doc = parser.parseFromString(`<div id="__root">${html}</div>`, 'text/html')
  const root = doc.getElementById('__root')
  if (!root) return html
  walk(root, doc, index)
  return root.innerHTML
}

const SKIP_TAGS = new Set(['CODE', 'PRE', 'A', 'SCRIPT', 'STYLE'])

function walk(node: Node, doc: Document, index: WikilinkIndex): void {
  if (node.nodeType === Node.TEXT_NODE) {
    const text = node.textContent ?? ''
    if (!text.includes('[[')) return
    const frag = buildFragment(text, doc, index)
    if (frag) node.parentNode?.replaceChild(frag, node)
    return
  }
  if (node.nodeType !== Node.ELEMENT_NODE) return
  if (SKIP_TAGS.has((node as Element).tagName)) return
  // Copy children first so replacement doesn't invalidate iteration.
  const children = Array.from(node.childNodes)
  for (const child of children) walk(child, doc, index)
}

function buildFragment(
  text: string,
  doc: Document,
  index: WikilinkIndex,
): DocumentFragment | null {
  WIKILINK_REGEX.lastIndex = 0
  let lastEnd = 0
  let matched = false
  const frag = doc.createDocumentFragment()
  for (const m of text.matchAll(WIKILINK_REGEX)) {
    const start = m.index ?? 0
    const target = m[1].trim()
    const display = (m[2] ?? m[1]).trim()
    if (!target) continue
    matched = true
    if (start > lastEnd) {
      frag.appendChild(doc.createTextNode(text.slice(lastEnd, start)))
    }
    const resolved = resolveWikilink(target, index)
    if (resolved) {
      const a = doc.createElement('a')
      a.setAttribute('href', `#wikilink:${encodeURIComponent(resolved)}`)
      a.setAttribute('data-wikilink-path', resolved)
      a.className = 'wikilink wikilink-resolved'
      a.textContent = display
      frag.appendChild(a)
    } else {
      const span = doc.createElement('span')
      span.className = 'wikilink wikilink-unresolved'
      span.setAttribute('title', `No note found for "${target}"`)
      span.textContent = display
      frag.appendChild(span)
    }
    lastEnd = start + m[0].length
  }
  if (!matched) return null
  if (lastEnd < text.length) {
    frag.appendChild(doc.createTextNode(text.slice(lastEnd)))
  }
  return frag
}
