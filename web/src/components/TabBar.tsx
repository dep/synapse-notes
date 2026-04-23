import { Box, Typography } from '@mui/material'
import CloseIcon from '@mui/icons-material/Close'
import type { MouseEvent } from 'react'
import type { Tab } from '../lib/tabs'

export type TabBarProps = {
  tabs: Tab[]
  activeId: string | null
  dirtyIds: Set<string>
  onActivate: (id: string) => void
  onClose: (id: string) => void
}

function basename(path: string): string {
  const slash = path.lastIndexOf('/')
  return slash >= 0 ? path.slice(slash + 1) : path
}

export function TabBar(props: TabBarProps) {
  const { tabs, activeId, dirtyIds, onActivate, onClose } = props
  if (tabs.length === 0) return null

  return (
    <Box
      sx={{
        display: 'flex',
        flexDirection: 'row',
        overflow: 'auto',
        borderBottom: '1px solid',
        borderColor: 'divider',
        bgcolor: 'background.paper',
        minHeight: 32,
      }}
    >
      {tabs.map((t) => {
        const active = t.id === activeId
        const dirty = dirtyIds.has(t.id)
        const name = basename(t.path)
        return (
          <Box
            key={t.id}
            onClick={() => onActivate(t.id)}
            onAuxClick={(e: MouseEvent) => {
              // Middle-click closes the tab (common browser convention).
              if (e.button === 1) {
                e.preventDefault()
                onClose(t.id)
              }
            }}
            title={t.path}
            sx={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: 0.75,
              px: 1.25,
              py: 0.5,
              borderRight: '1px solid',
              borderColor: 'divider',
              cursor: 'pointer',
              userSelect: 'none',
              bgcolor: active ? 'background.default' : 'transparent',
              borderBottom: active ? '2px solid' : '2px solid transparent',
              borderBottomColor: active ? 'primary.main' : 'transparent',
              minWidth: 0,
              maxWidth: 200,
              '&:hover': { bgcolor: 'action.hover' },
            }}
          >
            <Typography
              variant="body2"
              sx={{
                fontFamily: 'ui-monospace, Menlo, monospace',
                fontSize: 12,
                whiteSpace: 'nowrap',
                overflow: 'hidden',
                textOverflow: 'ellipsis',
                color: active ? 'text.primary' : 'text.secondary',
                fontWeight: active ? 600 : 400,
              }}
            >
              {name}
              {dirty ? ' •' : ''}
            </Typography>
            <Box
              role="button"
              aria-label="close tab"
              onClick={(e: MouseEvent) => {
                e.stopPropagation()
                onClose(t.id)
              }}
              sx={{
                display: 'inline-flex',
                alignItems: 'center',
                justifyContent: 'center',
                width: 16,
                height: 16,
                borderRadius: 0.5,
                color: 'text.disabled',
                '&:hover': { bgcolor: 'action.hover', color: 'text.primary' },
              }}
            >
              <CloseIcon sx={{ fontSize: 12 }} />
            </Box>
          </Box>
        )
      })}
    </Box>
  )
}
