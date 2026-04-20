import { useMemo } from 'react'
import { Box } from '@mui/material'
import { marked } from 'marked'

marked.setOptions({ gfm: true, breaks: false })

export function MarkdownPreview({ source }: { source: string }) {
  const html = useMemo(() => marked.parse(source) as string, [source])

  return (
    <Box
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
      }}
      // eslint-disable-next-line react/no-danger
      dangerouslySetInnerHTML={{ __html: html }}
    />
  )
}
