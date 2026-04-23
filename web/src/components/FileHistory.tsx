import { useEffect, useState } from 'react'
import {
  Alert,
  Box,
  Button,
  CircularProgress,
  Divider,
  Drawer,
  IconButton,
  List,
  ListItemButton,
  ListItemText,
  Tooltip,
  Typography,
} from '@mui/material'
import CloseIcon from '@mui/icons-material/Close'
import RestoreIcon from '@mui/icons-material/Restore'
import {
  fetchFileAtCommit,
  fetchFileCommits,
  type FileCommit,
} from '../github/contents'
import { MarkdownPreview } from './MarkdownPreview'

type Props = {
  open: boolean
  token: string
  owner: string
  repo: string
  branch: string
  filePath: string
  onApply: (content: string) => void
  onClose: () => void
}

function formatDate(iso: string): string {
  if (!iso) return ''
  const d = new Date(iso)
  return d.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

export function FileHistory({
  open,
  token,
  owner,
  repo,
  branch,
  filePath,
  onApply,
  onClose,
}: Props) {
  const [commits, setCommits] = useState<FileCommit[]>([])
  const [loadingCommits, setLoadingCommits] = useState(false)
  const [commitsError, setCommitsError] = useState<string | null>(null)

  const [selectedSha, setSelectedSha] = useState<string | null>(null)
  const [preview, setPreview] = useState<string | null>(null)
  const [loadingPreview, setLoadingPreview] = useState(false)
  const [previewError, setPreviewError] = useState<string | null>(null)

  // Fetch commit list when the drawer opens or file changes.
  useEffect(() => {
    if (!open || !filePath) return
    let cancelled = false
    setCommits([])
    setSelectedSha(null)
    setPreview(null)
    setCommitsError(null)
    setLoadingCommits(true)
    void fetchFileCommits(token, owner, repo, filePath, branch).then((result) => {
      if (cancelled) return
      setLoadingCommits(false)
      if (result.ok) {
        setCommits(result.commits)
      } else {
        setCommitsError(result.error)
      }
    })
    return () => {
      cancelled = true
    }
  }, [open, token, owner, repo, filePath, branch])

  // Fetch file content when a commit is selected.
  useEffect(() => {
    if (!selectedSha) return
    let cancelled = false
    setPreview(null)
    setPreviewError(null)
    setLoadingPreview(true)
    void fetchFileAtCommit(token, owner, repo, filePath, selectedSha).then(
      (result) => {
        if (cancelled) return
        setLoadingPreview(false)
        if (result.ok) {
          setPreview(result.content)
        } else {
          setPreviewError(result.error)
        }
      },
    )
    return () => {
      cancelled = true
    }
  }, [selectedSha, token, owner, repo, filePath])

  const selectedCommit = commits.find((c) => c.sha === selectedSha) ?? null

  return (
    <Drawer
      anchor="right"
      open={open}
      onClose={onClose}
      PaperProps={{
        sx: {
          width: { xs: '100vw', sm: 680 },
          display: 'flex',
          flexDirection: 'row',
          overflow: 'hidden',
        },
      }}
    >
      {/* Left pane: commit list */}
      <Box
        sx={{
          width: 240,
          flexShrink: 0,
          display: 'flex',
          flexDirection: 'column',
          borderRight: '1px solid',
          borderColor: 'divider',
          overflow: 'hidden',
        }}
      >
        <Box
          sx={{
            px: 2,
            py: 1.5,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            borderBottom: '1px solid',
            borderColor: 'divider',
            flexShrink: 0,
          }}
        >
          <Typography variant="subtitle2" noWrap>
            File history
          </Typography>
          <IconButton size="small" onClick={onClose} aria-label="close">
            <CloseIcon fontSize="small" />
          </IconButton>
        </Box>

        <Box
          sx={{
            px: 1.5,
            py: 1,
            borderBottom: '1px solid',
            borderColor: 'divider',
            flexShrink: 0,
          }}
        >
          <Typography
            variant="caption"
            color="text.secondary"
            sx={{
              fontFamily: 'ui-monospace, Menlo, monospace',
              wordBreak: 'break-all',
            }}
          >
            {filePath}
          </Typography>
        </Box>

        <Box sx={{ flex: 1, overflowY: 'auto' }}>
          {loadingCommits && (
            <Box sx={{ display: 'flex', justifyContent: 'center', pt: 4 }}>
              <CircularProgress size={24} />
            </Box>
          )}
          {commitsError && (
            <Box sx={{ p: 2 }}>
              <Alert severity="error" sx={{ fontSize: 12 }}>
                {commitsError}
              </Alert>
            </Box>
          )}
          {!loadingCommits && !commitsError && commits.length === 0 && (
            <Box sx={{ p: 2 }}>
              <Typography variant="caption" color="text.secondary">
                No history found.
              </Typography>
            </Box>
          )}
          <List dense disablePadding>
            {commits.map((c, idx) => (
              <Box key={c.sha}>
                <ListItemButton
                  selected={c.sha === selectedSha}
                  onClick={() => setSelectedSha(c.sha)}
                  sx={{ px: 1.5, py: 1 }}
                >
                  <ListItemText
                    primary={c.message || '(no message)'}
                    secondary={
                      <>
                        <span>{c.author}</span>
                        <br />
                        <span>{formatDate(c.date)}</span>
                      </>
                    }
                    primaryTypographyProps={{
                      fontSize: 12,
                      fontWeight: 500,
                      sx: {
                        overflow: 'hidden',
                        textOverflow: 'ellipsis',
                        whiteSpace: 'nowrap',
                      },
                    }}
                    secondaryTypographyProps={{ fontSize: 11 }}
                  />
                </ListItemButton>
                {idx < commits.length - 1 && <Divider />}
              </Box>
            ))}
          </List>
        </Box>
      </Box>

      {/* Right pane: preview */}
      <Box
        sx={{
          flex: 1,
          display: 'flex',
          flexDirection: 'column',
          overflow: 'hidden',
        }}
      >
        <Box
          sx={{
            px: 2,
            py: 1.5,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            borderBottom: '1px solid',
            borderColor: 'divider',
            flexShrink: 0,
            minHeight: 48,
          }}
        >
          {selectedCommit ? (
            <>
              <Box sx={{ minWidth: 0 }}>
                <Typography
                  variant="subtitle2"
                  noWrap
                  sx={{ fontSize: 13 }}
                >
                  {selectedCommit.message || '(no message)'}
                </Typography>
                <Typography variant="caption" color="text.secondary">
                  {selectedCommit.author} · {formatDate(selectedCommit.date)}
                </Typography>
              </Box>
              <Tooltip title="Apply this version to editor">
                <span>
                  <Button
                    size="small"
                    variant="contained"
                    startIcon={<RestoreIcon />}
                    disabled={preview === null || loadingPreview}
                    onClick={() => {
                      if (preview !== null) {
                        onApply(preview)
                        onClose()
                      }
                    }}
                  >
                    Apply
                  </Button>
                </span>
              </Tooltip>
            </>
          ) : (
            <Typography variant="body2" color="text.secondary">
              Select a commit to preview
            </Typography>
          )}
        </Box>

        <Box sx={{ flex: 1, overflowY: 'auto', position: 'relative' }}>
          {loadingPreview && (
            <Box sx={{ display: 'flex', justifyContent: 'center', pt: 6 }}>
              <CircularProgress size={28} />
            </Box>
          )}
          {previewError && (
            <Box sx={{ p: 2 }}>
              <Alert severity="error">{previewError}</Alert>
            </Box>
          )}
          {!loadingPreview && !previewError && preview !== null && (
            <Box sx={{ p: 2 }}>
              <MarkdownPreview source={preview} />
            </Box>
          )}
          {!selectedSha && !loadingPreview && (
            <Box
              sx={{
                position: 'absolute',
                inset: 0,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                pointerEvents: 'none',
              }}
            >
              <Typography variant="body2" color="text.disabled">
                ← Pick a commit
              </Typography>
            </Box>
          )}
        </Box>
      </Box>
    </Drawer>
  )
}
