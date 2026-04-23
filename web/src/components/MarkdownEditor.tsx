import {
  forwardRef,
  useEffect,
  useImperativeHandle,
  useRef,
} from 'react'
import { EditorState, type Extension } from '@codemirror/state'
import { EditorView, keymap, lineNumbers, highlightActiveLine } from '@codemirror/view'
import { defaultKeymap, history, historyKeymap } from '@codemirror/commands'
import {
  bracketMatching,
  defaultHighlightStyle,
  indentOnInput,
  syntaxHighlighting,
} from '@codemirror/language'
import { markdown } from '@codemirror/lang-markdown'
import { languages } from '@codemirror/language-data'
import { oneDark } from '@codemirror/theme-one-dark'

export type EditorSelectionInfo = {
  text: string
  from: number
  to: number
  // Viewport-relative rect at the end of the selection, for pill positioning.
  rect: { left: number; top: number; bottom: number } | null
}

export type CursorInfo = {
  offset: number
  beforeContext: string
  afterContext: string
}

export type MarkdownEditorHandle = {
  getSelection: () => EditorSelectionInfo | null
  getCursor: () => CursorInfo | null
  replaceRange: (from: number, to: number, text: string) => void
  insertAt: (offset: number, text: string) => void
}

export type MarkdownEditorProps = {
  value: string
  onChange: (next: string) => void
  readOnly?: boolean
  markdownMode: boolean
  onSelectionChange?: (info: EditorSelectionInfo | null) => void
}

export const MarkdownEditor = forwardRef<
  MarkdownEditorHandle,
  MarkdownEditorProps
>(function MarkdownEditor(
  { value, onChange, readOnly, markdownMode, onSelectionChange },
  ref,
) {
  const hostRef = useRef<HTMLDivElement>(null)
  const viewRef = useRef<EditorView | null>(null)
  const onChangeRef = useRef(onChange)
  onChangeRef.current = onChange
  const onSelectionChangeRef = useRef(onSelectionChange)
  onSelectionChangeRef.current = onSelectionChange

  useEffect(() => {
    if (!hostRef.current) return

    const extensions: Extension[] = [
      lineNumbers(),
      history(),
      indentOnInput(),
      bracketMatching(),
      highlightActiveLine(),
      syntaxHighlighting(defaultHighlightStyle, { fallback: true }),
      keymap.of([...defaultKeymap, ...historyKeymap]),
      oneDark,
      EditorView.lineWrapping,
      EditorView.theme({
        '&': { height: '100%', fontSize: '14px' },
        '.cm-scroller': {
          fontFamily:
            'ui-monospace, SFMono-Regular, "SF Mono", Menlo, monospace',
        },
        '.cm-content': { padding: '12px 4px' },
      }),
      EditorState.readOnly.of(Boolean(readOnly)),
      EditorView.updateListener.of((v) => {
        if (v.docChanged) {
          onChangeRef.current(v.state.doc.toString())
        }
        if (v.selectionSet || v.docChanged || v.focusChanged) {
          const info = readSelectionInfo(v.view)
          onSelectionChangeRef.current?.(info)
        }
      }),
    ]

    if (markdownMode) {
      extensions.push(markdown({ codeLanguages: languages }))
    }

    const state = EditorState.create({ doc: value, extensions })
    const view = new EditorView({ state, parent: hostRef.current })
    viewRef.current = view

    return () => {
      view.destroy()
      viewRef.current = null
    }
    // Recreate editor when mode / readOnly flips; value changes handled below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [markdownMode, readOnly])

  useEffect(() => {
    const view = viewRef.current
    if (!view) return
    const current = view.state.doc.toString()
    if (current !== value) {
      view.dispatch({
        changes: { from: 0, to: current.length, insert: value },
      })
    }
  }, [value])

  useImperativeHandle(
    ref,
    () => ({
      getSelection: () => {
        const view = viewRef.current
        if (!view) return null
        return readSelectionInfo(view)
      },
      getCursor: () => {
        const view = viewRef.current
        if (!view) return null
        const pos = view.state.selection.main.head
        const doc = view.state.doc.toString()
        const beforeStart = Math.max(0, pos - 80)
        const afterEnd = Math.min(doc.length, pos + 80)
        return {
          offset: pos,
          beforeContext: doc.slice(beforeStart, pos),
          afterContext: doc.slice(pos, afterEnd),
        }
      },
      replaceRange: (from, to, text) => {
        const view = viewRef.current
        if (!view) return
        view.dispatch({
          changes: { from, to, insert: text },
          selection: { anchor: from + text.length },
        })
        view.focus()
      },
      insertAt: (offset, text) => {
        const view = viewRef.current
        if (!view) return
        view.dispatch({
          changes: { from: offset, to: offset, insert: text },
          selection: { anchor: offset + text.length },
        })
        view.focus()
      },
    }),
    [],
  )

  return (
    <div
      ref={hostRef}
      style={{
        height: '100%',
        width: '100%',
        maxWidth: '100%',
        overflow: 'auto',
      }}
    />
  )
})

function readSelectionInfo(view: EditorView): EditorSelectionInfo | null {
  const { from, to } = view.state.selection.main
  if (from === to) return null
  const text = view.state.sliceDoc(from, to)
  const coords = view.coordsAtPos(to)
  const rect = coords
    ? { left: coords.left, top: coords.top, bottom: coords.bottom }
    : null
  return { text, from, to, rect }
}
