import type { ReactNode } from 'react'
import { Menu, MenuItem, Divider, ListItemText } from '@mui/material'

export type ContextMenuItem =
  | {
      kind: 'item'
      label: string
      onClick: () => void
      disabled?: boolean
      danger?: boolean
    }
  | { kind: 'divider' }

export function ContextMenu({
  anchor,
  items,
  onClose,
}: {
  anchor: { mouseX: number; mouseY: number } | null
  items: ContextMenuItem[]
  onClose: () => void
}): ReactNode {
  return (
    <Menu
      open={anchor !== null}
      onClose={onClose}
      anchorReference="anchorPosition"
      anchorPosition={
        anchor ? { top: anchor.mouseY, left: anchor.mouseX } : undefined
      }
    >
      {items.map((item, idx) => {
        if (item.kind === 'divider') {
          return <Divider key={`d-${idx}`} />
        }
        return (
          <MenuItem
            key={item.label}
            disabled={item.disabled}
            onClick={() => {
              item.onClick()
              onClose()
            }}
          >
            <ListItemText
              primary={item.label}
              primaryTypographyProps={{
                color: item.danger ? 'error' : undefined,
                fontSize: 14,
              }}
            />
          </MenuItem>
        )
      })}
    </Menu>
  )
}
