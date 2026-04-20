import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  Alert,
  AppBar,
  Box,
  Button,
  CircularProgress,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  IconButton,
  Stack,
  TextField,
  Toolbar,
  Tooltip,
  Typography,
} from '@mui/material'
import LogoutIcon from '@mui/icons-material/Logout'
import SwapHorizIcon from '@mui/icons-material/SwapHoriz'
import VisibilityIcon from '@mui/icons-material/Visibility'
import VisibilityOffIcon from '@mui/icons-material/VisibilityOff'
import SaveIcon from '@mui/icons-material/Save'
import RefreshIcon from '@mui/icons-material/Refresh'
import { useAuth } from '../auth/AuthContext'
import { parseRepoFullName } from '../github/parseRepoFullName'
import {
  fetchFileContent,
  fetchRepoTree,
  putFileContent,
  type GitTreeEntry,
} from '../github/contents'
import { buildTree, isMarkdownPath } from '../github/tree'
import type { SelectedRepo } from '../App'
import { FileTree } from './FileTree'
import { MarkdownEditor } from './MarkdownEditor'
import { MarkdownPreview } from './MarkdownPreview'

type LoadedFile = {
  path: string
  content: string
  originalContent: string
  sha: string
  encoding: 'utf-8' | 'binary'
}

export function RepoEditor({
  repo,
  onChangeRepo,
}: {
  repo: SelectedRepo
  onChangeRepo: () => void
}) {
  const { token, logout } = useAuth()
  const parsed = useMemo(() => parseRepoFullName(repo.fullName), [repo.fullName])

  const [entries, setEntries] = useState<GitTreeEntry[]>([])
  const [treeError, setTreeError] = useState<string | null>(null)
  const [treeLoading, setTreeLoading] = useState(true)
  const [truncated, setTruncated] = useState(false)

  const [activeFile, setActiveFile] = useState<LoadedFile | null>(null)
  const [fileLoading, setFileLoading] = useState(false)
  const [fileError, setFileError] = useState<string | null>(null)

  const [showPreview, setShowPreview] = useState(true)
  const [saveOpen, setSaveOpen] = useState(false)
  const [commitMessage, setCommitMessage] = useState('')
  const [saving, setSaving] = useState(false)
  const [saveError, setSaveError] = useState<string | null>(null)

  const loadTree = useCallback(async () => {
    if (!token || !parsed) return
    setTreeLoading(true)
    setTreeError(null)
    const result = await fetchRepoTree(
      token,
      parsed.owner,
      parsed.repo,
      repo.defaultBranch,
    )
    if (result.ok) {
      setEntries(result.entries)
      setTruncated(result.truncated)
    } else {
      setTreeError(result.error)
    }
    setTreeLoading(false)
  }, [token, parsed, repo.defaultBranch])

  useEffect(() => {
    void loadTree()
  }, [loadTree])

  const tree = useMemo(() => buildTree(entries), [entries])

  const handleSelectFile = useCallback(
    async (path: string) => {
      if (!token || !parsed) return
      if (activeFile && activeFile.path === path) return
      if (activeFile && activeFile.content !== activeFile.originalContent) {
        const ok = window.confirm(
          `Discard unsaved changes in ${activeFile.path}?`,
        )
        if (!ok) return
      }
      setFileLoading(true)
      setFileError(null)
      setActiveFile(null)
      const result = await fetchFileContent(
        token,
        parsed.owner,
        parsed.repo,
        path,
        repo.defaultBranch,
      )
      if (result.ok) {
        setActiveFile({
          path,
          content: result.content,
          originalContent: result.content,
          sha: result.sha,
          encoding: result.encoding,
        })
        if (result.encoding === 'binary') {
          setFileError('Binary file — cannot edit in browser.')
        }
      } else {
        setFileError(result.error)
      }
      setFileLoading(false)
    },
    [token, parsed, repo.defaultBranch, activeFile],
  )

  const dirty = Boolean(
    activeFile && activeFile.content !== activeFile.originalContent,
  )

  const openSaveDialog = useCallback(() => {
    if (!activeFile) return
    setCommitMessage(`Update ${activeFile.path}`)
    setSaveError(null)
    setSaveOpen(true)
  }, [activeFile])

  const handleSave = useCallback(async () => {
    if (!token || !parsed || !activeFile) return
    setSaving(true)
    setSaveError(null)
    const result = await putFileContent(
      token,
      parsed.owner,
      parsed.repo,
      activeFile.path,
      {
        content: activeFile.content,
        message: commitMessage.trim() || `Update ${activeFile.path}`,
        branch: repo.defaultBranch,
        sha: activeFile.sha,
      },
    )
    setSaving(false)
    if (result.ok) {
      setActiveFile({
        ...activeFile,
        sha: result.newSha,
        originalContent: activeFile.content,
      })
      setSaveOpen(false)
    } else {
      setSaveError(result.error)
    }
  }, [token, parsed, activeFile, commitMessage, repo.defaultBranch])

  const isMarkdown = activeFile ? isMarkdownPath(activeFile.path) : false

  if (!parsed) {
    return (
      <Box sx={{ p: 4 }}>
        <Alert severity="error">Invalid repo: {repo.fullName}</Alert>
      </Box>
    )
  }

  return (
    <Box
      sx={{
        height: '100vh',
        display: 'grid',
        gridTemplateRows: 'auto 1fr',
      }}
    >
      <AppBar position="static" color="default" elevation={0}>
        <Toolbar variant="dense" sx={{ gap: 1 }}>
          <Typography
            variant="subtitle1"
            fontWeight={700}
            sx={{ fontFamily: 'ui-monospace, Menlo, monospace' }}
          >
            {repo.fullName}
          </Typography>
          <Typography variant="caption" color="text.secondary">
            branch: {repo.defaultBranch}
          </Typography>
          <Box flex={1} />
          {activeFile && (
            <Typography variant="caption" sx={{ mr: 1 }}>
              {activeFile.path}
              {dirty && ' • unsaved'}
            </Typography>
          )}
          {isMarkdown && (
            <Tooltip title={showPreview ? 'Hide preview' : 'Show preview'}>
              <IconButton
                size="small"
                onClick={() => setShowPreview((v) => !v)}
              >
                {showPreview ? (
                  <VisibilityOffIcon fontSize="small" />
                ) : (
                  <VisibilityIcon fontSize="small" />
                )}
              </IconButton>
            </Tooltip>
          )}
          <Button
            size="small"
            variant="contained"
            startIcon={<SaveIcon />}
            onClick={openSaveDialog}
            disabled={!dirty || !activeFile || activeFile.encoding === 'binary'}
          >
            Commit
          </Button>
          <Tooltip title="Switch repo">
            <IconButton size="small" onClick={onChangeRepo}>
              <SwapHorizIcon fontSize="small" />
            </IconButton>
          </Tooltip>
          <Tooltip title="Sign out">
            <IconButton size="small" onClick={logout}>
              <LogoutIcon fontSize="small" />
            </IconButton>
          </Tooltip>
        </Toolbar>
      </AppBar>

      <Box
        sx={{
          display: 'grid',
          gridTemplateColumns: '280px 1fr',
          overflow: 'hidden',
        }}
      >
        <Box
          sx={{
            borderRight: '1px solid',
            borderColor: 'divider',
            overflow: 'auto',
            bgcolor: 'background.paper',
          }}
        >
          <Stack
            direction="row"
            alignItems="center"
            justifyContent="space-between"
            sx={{ px: 1.5, py: 1, borderBottom: '1px solid', borderColor: 'divider' }}
          >
            <Typography variant="caption" color="text.secondary">
              Files
            </Typography>
            <IconButton size="small" onClick={loadTree} title="Reload">
              <RefreshIcon fontSize="inherit" />
            </IconButton>
          </Stack>
          {treeLoading ? (
            <Box sx={{ display: 'grid', placeItems: 'center', py: 4 }}>
              <CircularProgress size={20} />
            </Box>
          ) : treeError ? (
            <Alert severity="error" sx={{ m: 1 }}>
              {treeError}
            </Alert>
          ) : (
            <>
              {truncated && (
                <Alert severity="warning" sx={{ m: 1 }}>
                  Tree truncated — very large repo.
                </Alert>
              )}
              <FileTree
                root={tree}
                activePath={activeFile?.path ?? null}
                onSelectFile={handleSelectFile}
              />
            </>
          )}
        </Box>

        <EditorPane
          loading={fileLoading}
          file={activeFile}
          fileError={fileError}
          isMarkdown={isMarkdown}
          showPreview={showPreview}
          onContentChange={(next) =>
            setActiveFile((prev) => (prev ? { ...prev, content: next } : prev))
          }
        />
      </Box>

      <Dialog open={saveOpen} onClose={() => !saving && setSaveOpen(false)}>
        <DialogTitle>Commit changes</DialogTitle>
        <DialogContent sx={{ minWidth: 420 }}>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
            Committing to <code>{repo.defaultBranch}</code>
          </Typography>
          <TextField
            autoFocus
            fullWidth
            label="Commit message"
            value={commitMessage}
            onChange={(e) => setCommitMessage(e.target.value)}
            disabled={saving}
          />
          {saveError && <Alert severity="error" sx={{ mt: 2 }}>{saveError}</Alert>}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setSaveOpen(false)} disabled={saving}>
            Cancel
          </Button>
          <Button
            variant="contained"
            onClick={handleSave}
            disabled={saving || !commitMessage.trim()}
          >
            {saving ? 'Committing…' : 'Commit'}
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  )
}

function EditorPane({
  loading,
  file,
  fileError,
  isMarkdown,
  showPreview,
  onContentChange,
}: {
  loading: boolean
  file: LoadedFile | null
  fileError: string | null
  isMarkdown: boolean
  showPreview: boolean
  onContentChange: (next: string) => void
}) {
  if (loading) {
    return (
      <Box sx={{ display: 'grid', placeItems: 'center' }}>
        <CircularProgress />
      </Box>
    )
  }
  if (fileError && !file) {
    return (
      <Box sx={{ p: 3 }}>
        <Alert severity="error">{fileError}</Alert>
      </Box>
    )
  }
  if (!file) {
    return (
      <Box
        sx={{
          display: 'grid',
          placeItems: 'center',
          color: 'text.secondary',
        }}
      >
        <Typography variant="body2">
          Select a file from the left to start editing.
        </Typography>
      </Box>
    )
  }
  if (file.encoding === 'binary') {
    return (
      <Box sx={{ p: 3 }}>
        <Alert severity="info">
          <code>{file.path}</code> is binary and cannot be edited here.
        </Alert>
      </Box>
    )
  }

  const previewActive = isMarkdown && showPreview
  return (
    <Box
      sx={{
        display: 'grid',
        gridTemplateColumns: previewActive ? '1fr 1fr' : '1fr',
        overflow: 'hidden',
      }}
    >
      <Box
        sx={{
          borderRight: previewActive ? '1px solid' : 0,
          borderColor: 'divider',
          overflow: 'hidden',
        }}
      >
        <MarkdownEditor
          value={file.content}
          onChange={onContentChange}
          markdownMode={isMarkdown}
        />
      </Box>
      {previewActive && <MarkdownPreview source={file.content} />}
    </Box>
  )
}
