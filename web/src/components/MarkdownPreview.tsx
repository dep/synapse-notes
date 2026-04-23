import { useCallback, useMemo } from 'react'
import type { MouseEvent } from 'react'
import { Box } from '@mui/material'
import { marked } from 'marked'
import type { WikilinkIndex } from '../lib/wikilinks'
import { applyWikilinks } from '../lib/wikilinksHtml'
import { splitFrontmatter } from '../lib/frontmatter'

marked.setOptions({ gfm: true, breaks: false })

export function MarkdownPreview({
  source,
  wikilinkIndex,
  onWikilinkClick,
}: {
  source: string
  wikilinkIndex?: WikilinkIndex
  onWikilinkClick?: (path: string) => void
}) {
  const { frontmatter, body } = useMemo(() => splitFrontmatter(source), [source])
  const html = useMemo(() => {
    const raw = marked.parse(body) as string
    return wikilinkIndex ? applyWikilinks(raw, wikilinkIndex) : raw
  }, [body, wikilinkIndex])

  const handleClick = useCallback(
    (e: MouseEvent<HTMLDivElement>) => {
      if (!onWikilinkClick) return
      const target = e.target as HTMLElement | null
      if (!target) return
      const anchor = target.closest('a[data-wikilink-path]') as HTMLElement | null
      if (!anchor) return
      const path = anchor.getAttribute('data-wikilink-path')
      if (!path) return
      e.preventDefault()
      onWikilinkClick(path)
    },
    [onWikilinkClick],
  )

  return (
    <Box
      onClick={handleClick}
      sx={{
        p: 3,
        height: '100%',
        overflow: 'auto',
        color: 'text.primary',
        fontSize: 15,
        lineHeight: 1.6,
        '& h1, & h2, & h3, & h4': {
          mt: 3,
          mb: 1.5,
          fontWeight: 600,
        },
        '& h1': { fontSize: '2rem', borderBottom: '1px solid', borderColor: 'divider', pb: 1 },
        '& h2': { fontSize: '1.5rem', borderBottom: '1px solid', borderColor: 'divider', pb: 1 },
        '& h3': { fontSize: '1.2rem' },
        '& p': { my: 1.5 },
        '& a': { color: 'primary.main' },
        '& code': {
          fontFamily: 'ui-monospace, Menlo, monospace',
          fontSize: '0.9em',
          background: 'rgba(255,255,255,0.08)',
          px: 0.75,
          py: 0.25,
          borderRadius: 0.5,
        },
        '& pre': {
          background: 'rgba(0,0,0,0.3)',
          p: 2,
          borderRadius: 1,
          overflow: 'auto',
        },
        '& pre code': { background: 'transparent', p: 0, fontSize: '0.85em' },
        '& blockquote': {
          borderLeft: '3px solid',
          borderColor: 'divider',
          pl: 2,
          color: 'text.secondary',
          my: 2,
        },
        '& ul, & ol': { pl: 3, my: 1.5 },
        '& li': { my: 0.5 },
        '& table': { borderCollapse: 'collapse', my: 2 },
        '& th, & td': {
          border: '1px solid',
          borderColor: 'divider',
          px: 1.5,
          py: 1,
        },
        '& img': { maxWidth: '100%' },
        '& hr': { border: 0, borderTop: '1px solid', borderColor: 'divider', my: 3 },
        '& .wikilink': {
          cursor: 'pointer',
          textDecoration: 'none',
          borderBottom: '1px dashed',
        },
        '& .wikilink-resolved': {
          color: 'primary.main',
          borderBottomColor: 'primary.main',
          '&:hover': { backgroundColor: 'action.hover' },
        },
        '& .wikilink-unresolved': {
          color: 'text.disabled',
          borderBottomColor: 'text.disabled',
          fontStyle: 'italic',
          cursor: 'help',
        },
      }}
    >
      {frontmatter !== null && (
        <Box
          component="pre"
          sx={{
            m: 0,
            mb: 2,
            px: 1.5,
            py: 1,
            borderLeft: '2px solid',
            borderColor: 'divider',
            bgcolor: 'rgba(255,255,255,0.03)',
            color: 'text.secondary',
            fontFamily: 'ui-monospace, Menlo, monospace',
            fontSize: 11,
            lineHeight: 1.45,
            whiteSpace: 'pre-wrap',
            wordBreak: 'break-word',
            borderRadius: 0.5,
          }}
        >
          {frontmatter}
        </Box>
      )}
      <Box
        // eslint-disable-next-line react/no-danger
        dangerouslySetInnerHTML={{ __html: html }}
      />
    </Box>
  )
}
