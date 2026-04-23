import { useCallback, useEffect, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import { Box } from '@mui/material'
import { MAX_PANE_RATIO, MIN_PANE_RATIO, clampRatio } from '../lib/previewRatio'

export function SplitPane({
  left,
  right,
  ratio,
  onRatioChange,
}: {
  left: ReactNode
  right: ReactNode
  ratio: number
  onRatioChange: (next: number) => void
}) {
  const containerRef = useRef<HTMLDivElement>(null)
  const [dragging, setDragging] = useState(false)

  const onMouseDown = useCallback((e: React.MouseEvent) => {
    e.preventDefault()
    setDragging(true)
  }, [])

  useEffect(() => {
    if (!dragging) return
    const onMove = (e: MouseEvent) => {
      const el = containerRef.current
      if (!el) return
      const rect = el.getBoundingClientRect()
      if (rect.width === 0) return
      const next = clampRatio((e.clientX - rect.left) / rect.width)
      onRatioChange(next)
    }
    const onUp = () => setDragging(false)
    window.addEventListener('mousemove', onMove)
    window.addEventListener('mouseup', onUp)
    const prevUserSelect = document.body.style.userSelect
    const prevCursor = document.body.style.cursor
    document.body.style.userSelect = 'none'
    document.body.style.cursor = 'col-resize'
    return () => {
      window.removeEventListener('mousemove', onMove)
      window.removeEventListener('mouseup', onUp)
      document.body.style.userSelect = prevUserSelect
      document.body.style.cursor = prevCursor
    }
  }, [dragging, onRatioChange])

  const leftPct = `${clampRatio(ratio) * 100}%`

  return (
    <Box
      ref={containerRef}
      sx={{
        display: 'flex',
        flexDirection: 'row',
        height: '100%',
        width: '100%',
        overflow: 'hidden',
        position: 'relative',
      }}
    >
      <Box sx={{ width: leftPct, minWidth: `${MIN_PANE_RATIO * 100}%`, overflow: 'hidden' }}>
        {left}
      </Box>
      <Box
        role="separator"
        aria-orientation="vertical"
        aria-label="resize preview"
        onMouseDown={onMouseDown}
        sx={{
          flex: '0 0 6px',
          cursor: 'col-resize',
          bgcolor: dragging ? 'primary.main' : 'divider',
          transition: dragging ? 'none' : 'background-color 120ms',
          '&:hover': { bgcolor: 'primary.main' },
          userSelect: 'none',
        }}
      />
      <Box sx={{ flex: 1, minWidth: `${(1 - MAX_PANE_RATIO) * 100}%`, overflow: 'hidden' }}>
        {right}
      </Box>
    </Box>
  )
}
