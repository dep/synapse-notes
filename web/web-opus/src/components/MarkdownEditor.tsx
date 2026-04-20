import { useEffect, useRef } from 'react'
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

export function MarkdownEditor({
  value,
  onChange,
  readOnly,
  markdownMode,
}: {
  value: string
  onChange: (next: string) => void
  readOnly?: boolean
  markdownMode: boolean
}) {
  const hostRef = useRef<HTMLDivElement>(null)
  const viewRef = useRef<EditorView | null>(null)
  const onChangeRef = useRef(onChange)
  onChangeRef.current = onChange

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

  return <div ref={hostRef} style={{ height: '100%', overflow: 'auto' }} />
}
