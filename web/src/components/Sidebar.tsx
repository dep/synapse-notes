import { useMemo, useState } from 'react'
import type { MouseEvent } from 'react'
import { Box, Collapse, Stack, Tooltip, Typography } from '@mui/material'
import FolderIcon from '@mui/icons-material/Folder'
import DescriptionIcon from '@mui/icons-material/Description'
import ArticleIcon from '@mui/icons-material/Article'
import PushPinIcon from '@mui/icons-material/PushPin'
import ArrowDropDownIcon from '@mui/icons-material/ArrowDropDown'
import ArrowRightIcon from '@mui/icons-material/ArrowRight'
import ArrowUpwardIcon from '@mui/icons-material/ArrowUpward'
import ArrowDownwardIcon from '@mui/icons-material/ArrowDownward'
import ChevronLeftIcon from '@mui/icons-material/ChevronLeft'
import CalendarMonthIcon from '@mui/icons-material/CalendarMonth'
import type { TreeNode } from '../github/tree'
import { isMarkdownPath } from '../github/tree'
import type { PinnedItem } from '../lib/pins'
import type { SortSettings, SortCriterion, SortableEntry } from '../lib/sort'
import { compareEntries } from '../lib/sort'
import {
  breadcrumbSegments,
  findFolderNode,
  parentFolder,
} from '../lib/navigator'
import { folderStyleFor } from '../lib/folderStyle'
import { StyledFolderIcon } from './FolderIcon'

export type SidebarContextTarget =
  | { kind: 'file'; path: string; name: string }
  | { kind: 'folder'; path: string; name: string }

export type SidebarProps = {
  root: TreeNode
  activePath: string | null
  pinnedItems: PinnedItem[]
  sort: SortSettings
  currentFolder: string
  onSortChange: (next: SortSettings) => void
  onNavigateFolder: (folder: string) => void
  onSelectFile: (path: string, event?: MouseEvent) => void
  onContextMenu: (target: SidebarContextTarget, event: MouseEvent) => void
  onPinnedClick: (item: PinnedItem, event: MouseEvent) => void
  onOpenToday: () => void
  todayLabel: string
  todayPath: string
}

export function Sidebar(props: SidebarProps) {
  const {
    root,
    activePath,
    pinnedItems,
    sort,
    currentFolder,
    onSortChange,
    onNavigateFolder,
    onSelectFile,
    onContextMenu,
    onPinnedClick,
    onOpenToday,
    todayLabel,
    todayPath,
  } = props

  const currentNode = useMemo(
    () => findFolderNode(root, currentFolder),
    [root, currentFolder],
  )

  const currentChildren = useMemo(() => {
    if (!currentNode) return []
    return [...currentNode.children].sort((a, b) => {
      const sa: SortableEntry = { name: a.name, path: a.path, type: a.type }
      const sb: SortableEntry = { name: b.name, path: b.path, type: b.type }
      return compareEntries(sa, sb, sort)
    })
  }, [currentNode, sort])

  const toggleDirection = () =>
    onSortChange({
      ...sort,
      direction: sort.direction === 'asc' ? 'desc' : 'asc',
    })

  const setCriterion = (next: SortCriterion) => {
    if (sort.criterion === next) {
      toggleDirection()
    } else {
      onSortChange({ criterion: next, direction: 'asc' })
    }
  }

  return (
    <Box sx={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      <Stack
        direction="row"
        alignItems="center"
        spacing={1}
        onClick={onOpenToday}
        sx={{
          px: 1,
          py: 0.75,
          cursor: 'pointer',
          userSelect: 'none',
          borderBottom: '1px solid',
          borderColor: 'divider',
          bgcolor: activePath === todayPath ? 'action.selected' : 'transparent',
          '&:hover': { bgcolor: 'action.hover' },
        }}
      >
        <CalendarMonthIcon sx={{ fontSize: 18, color: '#6EA8FE' }} />
        <Box sx={{ minWidth: 0, flex: 1 }}>
          <Typography
            variant="body2"
            sx={{
              fontSize: 13,
              fontWeight: 600,
              whiteSpace: 'nowrap',
              overflow: 'hidden',
              textOverflow: 'ellipsis',
            }}
          >
            Today
          </Typography>
          <Typography
            variant="caption"
            color="text.secondary"
            sx={{
              fontFamily: 'ui-monospace, Menlo, monospace',
              fontSize: 11,
              display: 'block',
              whiteSpace: 'nowrap',
              overflow: 'hidden',
              textOverflow: 'ellipsis',
            }}
          >
            {todayLabel}
          </Typography>
        </Box>
      </Stack>

      {pinnedItems.length > 0 && (
        <PinnedSection
          items={pinnedItems}
          activePath={activePath}
          onClick={onPinnedClick}
          onContextMenu={(target, event) => onContextMenu(target, event)}
        />
      )}

      <Box sx={{ p: 1, borderBottom: '1px solid', borderColor: 'divider' }}>
        <Stack direction="row" spacing={1} alignItems="center">
          <Box sx={{ flex: 1 }} />
          <SortButton
            label="Name"
            active={sort.criterion === 'name'}
            direction={sort.criterion === 'name' ? sort.direction : null}
            onClick={() => setCriterion('name')}
          />
          <SortButton
            label="Date"
            active={sort.criterion === 'date'}
            direction={sort.criterion === 'date' ? sort.direction : null}
            onClick={() => setCriterion('date')}
          />
        </Stack>
      </Box>

      <Breadcrumb folder={currentFolder} onNavigate={onNavigateFolder} />

      <Box sx={{ flex: 1, overflow: 'auto' }}>
        <FolderContents
          children={currentChildren}
          activePath={activePath}
          topLevel={currentFolder === ''}
          onEnterFolder={onNavigateFolder}
          onSelectFile={onSelectFile}
          onContextMenu={onContextMenu}
        />
      </Box>
    </Box>
  )
}

function Breadcrumb({
  folder,
  onNavigate,
}: {
  folder: string
  onNavigate: (folder: string) => void
}) {
  const segments = breadcrumbSegments(folder)
  const canGoBack = folder !== ''
  return (
    <Box
      sx={{
        display: 'flex',
        alignItems: 'center',
        px: 1,
        py: 0.5,
        gap: 0.5,
        borderBottom: '1px solid',
        borderColor: 'divider',
        minHeight: 32,
      }}
    >
      <Tooltip title={canGoBack ? 'Back' : 'At root'}>
        <Box
          component="button"
          type="button"
          aria-label="back"
          disabled={!canGoBack}
          onClick={() => canGoBack && onNavigate(parentFolder(folder))}
          sx={{
            display: 'inline-flex',
            alignItems: 'center',
            justifyContent: 'center',
            border: 0,
            bgcolor: 'transparent',
            color: canGoBack ? 'text.primary' : 'text.disabled',
            cursor: canGoBack ? 'pointer' : 'default',
            p: 0.25,
            '&:hover': canGoBack ? { bgcolor: 'action.hover' } : {},
            borderRadius: 0.5,
          }}
        >
          <ChevronLeftIcon fontSize="small" />
        </Box>
      </Tooltip>
      <Box
        sx={{
          display: 'flex',
          alignItems: 'center',
          gap: 0.25,
          minWidth: 0,
          overflow: 'hidden',
          flex: 1,
        }}
      >
        {segments.map((seg, idx) => {
          const isLast = idx === segments.length - 1
          return (
            <Stack
              key={seg.path || '__root__'}
              direction="row"
              alignItems="center"
              sx={{ minWidth: 0 }}
            >
              <Box
                component="button"
                type="button"
                onClick={() => !isLast && onNavigate(seg.path)}
                disabled={isLast}
                sx={{
                  border: 0,
                  bgcolor: 'transparent',
                  color: isLast ? 'text.primary' : 'text.secondary',
                  fontFamily:
                    'ui-monospace, SFMono-Regular, Menlo, monospace',
                  fontSize: 12,
                  fontWeight: isLast ? 600 : 400,
                  cursor: isLast ? 'default' : 'pointer',
                  px: 0.5,
                  py: 0.25,
                  borderRadius: 0.5,
                  whiteSpace: 'nowrap',
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                  maxWidth: 120,
                  '&:hover': !isLast ? { bgcolor: 'action.hover' } : {},
                }}
              >
                {seg.label}
              </Box>
              {!isLast && (
                <Typography
                  variant="caption"
                  color="text.disabled"
                  sx={{ userSelect: 'none' }}
                >
                  /
                </Typography>
              )}
            </Stack>
          )
        })}
      </Box>
    </Box>
  )
}

function SortButton({
  label,
  active,
  direction,
  onClick,
}: {
  label: string
  active: boolean
  direction: 'asc' | 'desc' | null
  onClick: (event: MouseEvent) => void
}) {
  return (
    <Tooltip
      title={
        active
          ? `Sorted by ${label} ${direction === 'asc' ? '↑' : '↓'} — click to reverse`
          : `Sort by ${label}`
      }
    >
      <Box
        component="button"
        type="button"
        onClick={onClick}
        sx={{
          display: 'inline-flex',
          alignItems: 'center',
          gap: 0.25,
          border: 0,
          bgcolor: active ? 'action.selected' : 'transparent',
          color: active ? 'text.primary' : 'text.secondary',
          fontSize: 12,
          px: 0.75,
          py: 0.25,
          borderRadius: 0.75,
          cursor: 'pointer',
          fontFamily: 'inherit',
          '&:hover': { bgcolor: 'action.hover' },
        }}
      >
        {label}
        {active &&
          (direction === 'asc' ? (
            <ArrowUpwardIcon sx={{ fontSize: 12 }} />
          ) : (
            <ArrowDownwardIcon sx={{ fontSize: 12 }} />
          ))}
      </Box>
    </Tooltip>
  )
}

function PinnedSection({
  items,
  activePath,
  onClick,
  onContextMenu,
}: {
  items: PinnedItem[]
  activePath: string | null
  onClick: (item: PinnedItem, event: MouseEvent) => void
  onContextMenu: (target: SidebarContextTarget, event: MouseEvent) => void
}) {
  const [open, setOpen] = useState(true)
  return (
    <Box sx={{ borderBottom: '1px solid', borderColor: 'divider' }}>
      <Stack
        direction="row"
        alignItems="center"
        spacing={0.5}
        onClick={() => setOpen((o) => !o)}
        sx={{
          px: 1,
          py: 0.5,
          cursor: 'pointer',
          userSelect: 'none',
          '&:hover': { bgcolor: 'action.hover' },
        }}
      >
        {open ? (
          <ArrowDropDownIcon fontSize="small" />
        ) : (
          <ArrowRightIcon fontSize="small" />
        )}
        <PushPinIcon sx={{ fontSize: 14 }} />
        <Typography variant="caption" sx={{ fontWeight: 600 }}>
          Pinned
        </Typography>
      </Stack>
      <Collapse in={open}>
        <Box sx={{ pb: 0.5 }}>
          {items.map((item) => (
            <Row
              key={`${item.kind}:${item.path}`}
              active={item.kind === 'file' && activePath === item.path}
              onClick={(e) => onClick(item, e)}
              onContextMenu={(e) => {
                e.preventDefault()
                onContextMenu(
                  item.kind === 'file'
                    ? {
                        kind: 'file',
                        path: item.path,
                        name: basename(item.path),
                      }
                    : {
                        kind: 'folder',
                        path: item.path,
                        name: basename(item.path),
                      },
                  e,
                )
              }}
              icon={
                item.kind === 'folder' ? (
                  <StyledFolderIcon
                    style={folderStyleFor(basename(item.path) || item.path)}
                  />
                ) : (
                  <ArticleIcon fontSize="small" color="primary" />
                )
              }
              label={(() => {
                const name = basename(item.path) || item.path
                if (item.kind !== 'folder') return name
                const style = folderStyleFor(name)
                return style.emoji && name.startsWith(style.emoji)
                  ? name.slice(style.emoji.length).trimStart()
                  : name
              })()}
              labelColor={
                item.kind === 'folder'
                  ? folderStyleFor(basename(item.path) || item.path).color
                  : undefined
              }
            />
          ))}
        </Box>
      </Collapse>
    </Box>
  )
}

function FolderContents({
  children,
  activePath,
  topLevel,
  onEnterFolder,
  onSelectFile,
  onContextMenu,
}: {
  children: TreeNode[]
  activePath: string | null
  topLevel: boolean
  onEnterFolder: (folder: string) => void
  onSelectFile: (path: string, event?: MouseEvent) => void
  onContextMenu: (target: SidebarContextTarget, event: MouseEvent) => void
}) {
  if (children.length === 0) {
    return (
      <Box sx={{ p: 2 }}>
        <Typography variant="caption" color="text.secondary">
          Empty folder.
        </Typography>
      </Box>
    )
  }
  return (
    <Box sx={{ py: 0.5 }}>
      {children.map((node) => {
        if (node.type === 'tree') {
          const style = topLevel ? folderStyleFor(node.name) : null
          const label =
            style?.emoji && node.name.startsWith(style.emoji)
              ? node.name.slice(style.emoji.length).trimStart()
              : node.name
          return (
            <Row
              key={node.path}
              active={false}
              onClick={() => onEnterFolder(node.path)}
              onContextMenu={(e) => {
                e.preventDefault()
                onContextMenu(
                  { kind: 'folder', path: node.path, name: node.name },
                  e,
                )
              }}
              icon={
                style ? (
                  <StyledFolderIcon style={style} />
                ) : (
                  <FolderIcon fontSize="small" />
                )
              }
              label={label}
              labelColor={style?.color}
              muted={!style}
              trailing={
                <ChevronLeftIcon
                  sx={{
                    fontSize: 14,
                    transform: 'rotate(180deg)',
                    color: 'text.disabled',
                  }}
                />
              }
            />
          )
        }
        const md = isMarkdownPath(node.path)
        return (
          <Row
            key={node.path}
            active={activePath === node.path}
            onClick={(e) => onSelectFile(node.path, e)}
            onContextMenu={(e) => {
              e.preventDefault()
              onContextMenu(
                { kind: 'file', path: node.path, name: node.name },
                e,
              )
            }}
            icon={
              md ? (
                <ArticleIcon fontSize="small" color="primary" />
              ) : (
                <DescriptionIcon fontSize="small" />
              )
            }
            label={node.name}
          />
        )
      })}
    </Box>
  )
}

function Row({
  active,
  onClick,
  onContextMenu,
  icon,
  label,
  muted,
  trailing,
  labelColor,
}: {
  active: boolean
  onClick: (event: MouseEvent) => void
  onContextMenu?: (event: MouseEvent) => void
  icon: React.ReactNode
  label: string
  muted?: boolean
  trailing?: React.ReactNode
  labelColor?: string
}) {
  return (
    <Stack
      direction="row"
      alignItems="center"
      spacing={1}
      onClick={onClick}
      onContextMenu={onContextMenu}
      sx={{
        pl: '8px',
        pr: 1,
        py: '3px',
        cursor: 'pointer',
        userSelect: 'none',
        bgcolor: active ? 'action.selected' : 'transparent',
        '&:hover': { bgcolor: 'action.hover' },
      }}
    >
      {icon}
      <Typography
        variant="body2"
        sx={{
          flex: 1,
          fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
          fontSize: 13,
          color: labelColor ?? (muted ? 'text.secondary' : 'text.primary'),
          whiteSpace: 'nowrap',
          overflow: 'hidden',
          textOverflow: 'ellipsis',
        }}
      >
        {label}
      </Typography>
      {trailing}
    </Stack>
  )
}

function basename(path: string): string {
  const slash = path.lastIndexOf('/')
  return slash >= 0 ? path.slice(slash + 1) : path
}
