import { useEffect, useMemo, useRef, useState } from 'react'
import type { KeyboardEvent as ReactKeyboardEvent } from 'react'
import {
  Box,
  Dialog,
  InputBase,
  Stack,
  Typography,
} from '@mui/material'
import FolderIcon from '@mui/icons-material/Folder'
import ArticleIcon from '@mui/icons-material/Article'
import { filterItems, type PaletteItem } from '../lib/palette'

export function CommandPalette({
  open,
  items,
  onSelect,
  onClose,
}: {
  open: boolean
  items: PaletteItem[]
  onSelect: (item: PaletteItem) => void
  onClose: () => void
}) {
  const [query, setQuery] = useState('')
  const [highlight, setHighlight] = useState(0)
  const listRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    if (open) {
      setQuery('')
      setHighlight(0)
    }
  }, [open])

  const results = useMemo(() => filterItems(items, query, 50), [items, query])

  useEffect(() => {
    if (highlight >= results.length) setHighlight(0)
  }, [results.length, highlight])

  useEffect(() => {
    const el = listRef.current?.querySelector(
      `[data-palette-index="${highlight}"]`,
    )
    if (el && 'scrollIntoView' in el) {
      ;(el as HTMLElement).scrollIntoView({ block: 'nearest' })
    }
  }, [highlight])

  const handleKeyDown = (e: ReactKeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      setHighlight((h) => (results.length === 0 ? 0 : (h + 1) % results.length))
    } else if (e.key === 'ArrowUp') {
      e.preventDefault()
      setHighlight((h) =>
        results.length === 0 ? 0 : (h - 1 + results.length) % results.length,
      )
    } else if (e.key === 'Enter') {
      e.preventDefault()
      const chosen = results[highlight]
      if (chosen) onSelect(chosen)
    }
    // Escape handled by Dialog's onClose.
  }

  return (
    <Dialog
      open={open}
      onClose={onClose}
      maxWidth="sm"
      fullWidth
      // Focus the query input once the dialog has finished mounting its focus
      // trap; autoFocus on InputBase alone races with MUI's trap.
      TransitionProps={{
        onEntered: () => inputRef.current?.focus(),
      }}
      PaperProps={{ sx: { position: 'absolute', top: '12vh', m: 0 } }}
    >
      <Box sx={{ p: 1.5, borderBottom: '1px solid', borderColor: 'divider' }}>
        <InputBase
          autoFocus
          placeholder="Jump to file or folder…"
          value={query}
          onChange={(e) => {
            setQuery(e.target.value)
            setHighlight(0)
          }}
          onKeyDown={handleKeyDown}
          fullWidth
          sx={{ fontSize: 16, fontFamily: 'ui-monospace, Menlo, monospace' }}
          inputProps={{
            'aria-label': 'command palette query',
            ref: inputRef,
          }}
        />
      </Box>
      <Box
        ref={listRef}
        sx={{ maxHeight: '50vh', overflow: 'auto', py: 0.5 }}
      >
        {results.length === 0 ? (
          <Box sx={{ p: 2 }}>
            <Typography variant="caption" color="text.secondary">
              No matches.
            </Typography>
          </Box>
        ) : (
          results.map((item, idx) => (
            <Row
              key={`${item.kind}:${item.path}`}
              index={idx}
              item={item}
              active={idx === highlight}
              onMouseEnter={() => setHighlight(idx)}
              onClick={() => onSelect(item)}
            />
          ))
        )}
      </Box>
    </Dialog>
  )
}

function Row({
  index,
  item,
  active,
  onMouseEnter,
  onClick,
}: {
  index: number
  item: PaletteItem
  active: boolean
  onMouseEnter: () => void
  onClick: () => void
}) {
  return (
    <Stack
      data-palette-index={index}
      data-testid="palette-row"
      direction="row"
      alignItems="center"
      spacing={1.25}
      onMouseEnter={onMouseEnter}
      onClick={onClick}
      sx={{
        px: 1.5,
        py: 0.75,
        cursor: 'pointer',
        userSelect: 'none',
        bgcolor: active ? 'action.selected' : 'transparent',
      }}
    >
      {item.kind === 'folder' ? (
        <FolderIcon fontSize="small" />
      ) : (
        <ArticleIcon fontSize="small" color="primary" />
      )}
      <Box sx={{ minWidth: 0, flex: 1 }}>
        <Typography
          variant="body2"
          sx={{
            fontFamily: 'ui-monospace, Menlo, monospace',
            fontSize: 13,
            whiteSpace: 'nowrap',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
          }}
        >
          {item.name}
        </Typography>
        {item.parentPath && (
          <Typography
            variant="caption"
            color="text.secondary"
            sx={{
              fontFamily: 'ui-monospace, Menlo, monospace',
              fontSize: 11,
              whiteSpace: 'nowrap',
              overflow: 'hidden',
              textOverflow: 'ellipsis',
              display: 'block',
            }}
          >
            {item.parentPath}
          </Typography>
        )}
      </Box>
      <Typography
        variant="caption"
        color="text.secondary"
        sx={{ fontSize: 11, flexShrink: 0 }}
      >
        {item.kind === 'folder' ? 'folder' : 'file'}
      </Typography>
    </Stack>
  )
}
