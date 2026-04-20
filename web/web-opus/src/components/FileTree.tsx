import { useState } from 'react'
import { Box, Stack, Typography } from '@mui/material'
import FolderIcon from '@mui/icons-material/Folder'
import FolderOpenIcon from '@mui/icons-material/FolderOpen'
import DescriptionIcon from '@mui/icons-material/Description'
import ArticleIcon from '@mui/icons-material/Article'
import type { TreeNode } from '../github/tree'
import { isMarkdownPath } from '../github/tree'

export function FileTree({
  root,
  activePath,
  onSelectFile,
}: {
  root: TreeNode
  activePath: string | null
  onSelectFile: (path: string) => void
}) {
  return (
    <Box sx={{ py: 1 }}>
      {root.children.map((child) => (
        <TreeRow
          key={child.path}
          node={child}
          depth={0}
          activePath={activePath}
          onSelectFile={onSelectFile}
        />
      ))}
    </Box>
  )
}

function TreeRow({
  node,
  depth,
  activePath,
  onSelectFile,
}: {
  node: TreeNode
  depth: number
  activePath: string | null
  onSelectFile: (path: string) => void
}) {
  const [open, setOpen] = useState(depth === 0)

  if (node.type === 'tree') {
    return (
      <Box>
        <Row
          depth={depth}
          active={false}
          onClick={() => setOpen((o) => !o)}
          icon={open ? <FolderOpenIcon fontSize="small" /> : <FolderIcon fontSize="small" />}
          label={node.name}
          muted
        />
        {open &&
          node.children.map((child) => (
            <TreeRow
              key={child.path}
              node={child}
              depth={depth + 1}
              activePath={activePath}
              onSelectFile={onSelectFile}
            />
          ))}
      </Box>
    )
  }

  const md = isMarkdownPath(node.path)
  return (
    <Row
      depth={depth}
      active={activePath === node.path}
      onClick={() => onSelectFile(node.path)}
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
}

function Row({
  depth,
  active,
  onClick,
  icon,
  label,
  muted,
}: {
  depth: number
  active: boolean
  onClick: () => void
  icon: React.ReactNode
  label: string
  muted?: boolean
}) {
  return (
    <Stack
      direction="row"
      alignItems="center"
      spacing={1}
      onClick={onClick}
      sx={{
        pl: `${8 + depth * 14}px`,
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
          fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
          fontSize: 13,
          color: muted ? 'text.secondary' : 'text.primary',
          whiteSpace: 'nowrap',
          overflow: 'hidden',
          textOverflow: 'ellipsis',
        }}
      >
        {label}
      </Typography>
    </Stack>
  )
}
