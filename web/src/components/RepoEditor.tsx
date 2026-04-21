import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type MouseEvent,
} from 'react'
import {
  Alert,
  AppBar,
  Box,
  Button,
  CircularProgress,
  IconButton,
  ListItemIcon,
  ListItemText,
  Menu,
  MenuItem,
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
import MenuOpenIcon from '@mui/icons-material/MenuOpen'
import MenuIcon from '@mui/icons-material/Menu'
import IosShareIcon from '@mui/icons-material/IosShare'
import MoreVertIcon from '@mui/icons-material/MoreVert'
import { useAuth } from '../auth/AuthContext'
import { parseRepoFullName } from '../github/parseRepoFullName'
import {
  deleteFileContent,
  fetchFileContent,
  fetchRepoTree,
  putFileContent,
  type GitTreeEntry,
} from '../github/contents'
import { buildTree, isMarkdownPath } from '../github/tree'
import type { SelectedRepo } from '../App'
import { MarkdownEditor } from './MarkdownEditor'
import { MarkdownPreview } from './MarkdownPreview'
import { Sidebar, type SidebarContextTarget } from './Sidebar'
import { ContextMenu, type ContextMenuItem } from './ContextMenu'
import { PromptDialog } from './PromptDialog'
import { ConfirmDialog } from './ConfirmDialog'
import { SplitPane } from './SplitPane'
import { GistDialog, type GistSubmission } from './GistDialog'
import { CommandPalette } from './CommandPalette'
import { collectPaletteItems, type PaletteItem } from '../lib/palette'
import { buildWikilinkIndex, type WikilinkIndex } from '../lib/wikilinks'
import { canPublishGist, createGist } from '../github/gists'
import { loadPreviewRatio, savePreviewRatio } from '../lib/previewRatio'
import { createPinsStore, type PinnedItem } from '../lib/pins'
import {
  DEFAULT_SORT,
  formatSortToken,
  loadSortSettings,
  parseSortToken,
  saveSortSettings,
  type SortSettings,
} from '../lib/sort'
import { findFolderNode } from '../lib/navigator'
import {
  formatRoute,
  routeFile,
  routeFolder,
  routeQuery,
  type Route,
} from '../lib/route'
import { defaultCommitMessage } from '../lib/commit'
import {
  MOBILE_BREAKPOINT,
  WIDE_BREAKPOINT,
  crossedBreakpoint,
  isMobile,
  resolveVisible,
} from '../lib/responsive'
import { useWindowWidth } from '../lib/useWindowWidth'

type LoadedFile = {
  path: string
  content: string
  originalContent: string
  sha: string
  encoding: 'utf-8' | 'binary'
}

type ContextMenuState = {
  anchor: { mouseX: number; mouseY: number }
  target: SidebarContextTarget
} | null

type DialogState =
  | { kind: 'none' }
  | { kind: 'rename'; target: SidebarContextTarget }
  | { kind: 'newFile'; parentPath: string }
  | { kind: 'newFolder'; parentPath: string }
  | { kind: 'deleteFile'; path: string; sha: string }

export function RepoEditor({
  repo,
  route,
  navigate,
  onChangeRepo,
}: {
  repo: SelectedRepo
  route: Route
  navigate: (to: string, options?: { replace?: boolean }) => void
  onChangeRepo: () => void
}) {
  const { token, logout, scopes } = useAuth()
  const gistAllowed = canPublishGist(scopes)
  const parsed = useMemo(() => parseRepoFullName(repo.fullName), [repo.fullName])
  const [owner, repoName] = useMemo(() => repo.fullName.split('/'), [repo.fullName])

  const pinsStore = useMemo(() => createPinsStore(repo.fullName), [repo.fullName])
  const [pinnedItems, setPinnedItems] = useState<PinnedItem[]>(() =>
    pinsStore.list(),
  )
  const currentFolder = routeFolder(route)
  const currentFile = routeFile(route)
  const currentQuery = routeQuery(route)

  // Sort: URL wins, localStorage is the default, DEFAULT_SORT is last resort.
  const sort: SortSettings = useMemo(() => {
    const fromUrl = parseSortToken(currentQuery.sort)
    if (fromUrl) return fromUrl
    return loadSortSettings(repo.fullName) ?? DEFAULT_SORT
  }, [currentQuery.sort, repo.fullName])

  const navigateToFolder = useCallback(
    (folder: string) => {
      navigate(
        formatRoute({
          kind: 'folder',
          owner,
          repo: repoName,
          folder,
          query: currentQuery,
        }),
      )
    },
    [navigate, owner, repoName, currentQuery],
  )

  const navigateToFile = useCallback(
    (file: string) => {
      navigate(
        formatRoute({
          kind: 'file',
          owner,
          repo: repoName,
          file,
          query: currentQuery,
        }),
      )
    },
    [navigate, owner, repoName, currentQuery],
  )

  const setSort = useCallback(
    (next: SortSettings) => {
      saveSortSettings(repo.fullName, next)
      const nextQuery: Record<string, string> = {
        ...currentQuery,
        sort: formatSortToken(next),
      }
      // Replace, not push — sort is a preference, not a navigation.
      navigate(
        formatRoute(
          route.kind === 'picker'
            ? { kind: 'picker', query: nextQuery }
            : route.kind === 'repo'
              ? {
                  kind: 'repo',
                  owner: route.owner,
                  repo: route.repo,
                  query: nextQuery,
                }
              : route.kind === 'folder'
                ? {
                    kind: 'folder',
                    owner: route.owner,
                    repo: route.repo,
                    folder: route.folder,
                    query: nextQuery,
                  }
                : {
                    kind: 'file',
                    owner: route.owner,
                    repo: route.repo,
                    file: route.file,
                    query: nextQuery,
                  },
        ),
        { replace: true },
      )
    },
    [currentQuery, navigate, repo.fullName, route],
  )

  const [entries, setEntries] = useState<GitTreeEntry[]>([])
  const [treeError, setTreeError] = useState<string | null>(null)
  const [treeLoading, setTreeLoading] = useState(true)
  const [truncated, setTruncated] = useState(false)

  const [activeFile, setActiveFile] = useState<LoadedFile | null>(null)
  const [fileLoading, setFileLoading] = useState(false)
  const [fileError, setFileError] = useState<string | null>(null)

  const windowWidth = useWindowWidth()
  const prevWidthRef = useRef(windowWidth)
  const [sidebarOverride, setSidebarOverride] = useState<boolean | null>(null)
  const [previewOverride, setPreviewOverride] = useState<boolean | null>(null)

  useEffect(() => {
    const prev = prevWidthRef.current
    prevWidthRef.current = windowWidth
    if (crossedBreakpoint(prev, windowWidth, MOBILE_BREAKPOINT)) {
      setSidebarOverride(null)
    }
    if (crossedBreakpoint(prev, windowWidth, WIDE_BREAKPOINT)) {
      setPreviewOverride(null)
    }
  }, [windowWidth])

  const sidebarVisible = resolveVisible(
    windowWidth,
    MOBILE_BREAKPOINT,
    sidebarOverride,
  )
  const previewVisible = resolveVisible(
    windowWidth,
    WIDE_BREAKPOINT,
    previewOverride,
  )
  const mobile = isMobile(windowWidth)

  const [saving, setSaving] = useState(false)
  const [saveError, setSaveError] = useState<string | null>(null)

  const [contextMenu, setContextMenu] = useState<ContextMenuState>(null)
  const [overflowAnchor, setOverflowAnchor] = useState<HTMLElement | null>(null)
  const [dialog, setDialog] = useState<DialogState>({ kind: 'none' })
  const [dialogBusy, setDialogBusy] = useState(false)
  const [dialogError, setDialogError] = useState<string | null>(null)

  const [previewRatio, setPreviewRatio] = useState<number>(() =>
    loadPreviewRatio(repo.fullName),
  )
  useEffect(() => {
    setPreviewRatio(loadPreviewRatio(repo.fullName))
  }, [repo.fullName])
  const handleRatioChange = useCallback(
    (next: number) => {
      setPreviewRatio(next)
      savePreviewRatio(repo.fullName, next)
    },
    [repo.fullName],
  )

  const [gistOpen, setGistOpen] = useState(false)
  const [gistBusy, setGistBusy] = useState(false)
  const [gistError, setGistError] = useState<string | null>(null)

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

  useEffect(() => {
    if (
      entries.length > 0 &&
      currentFolder &&
      !findFolderNode(tree, currentFolder)
    ) {
      navigateToFolder('')
    }
  }, [tree, currentFolder, navigateToFolder, entries.length])

  const activeFileRef = useRef<LoadedFile | null>(null)
  activeFileRef.current = activeFile

  const handleSelectFile = useCallback(
    (path: string) => {
      const current = activeFileRef.current
      if (current && current.path === path) {
        if (mobile) setSidebarOverride(false)
        return
      }
      if (current && current.content !== current.originalContent) {
        const ok = window.confirm(`Discard unsaved changes in ${current.path}?`)
        if (!ok) return
      }
      navigateToFile(path)
      if (mobile) setSidebarOverride(false)
    },
    [navigateToFile, mobile],
  )

  useEffect(() => {
    if (!token || !parsed) return
    if (!currentFile) {
      setActiveFile(null)
      setFileError(null)
      setFileLoading(false)
      return
    }
    if (activeFileRef.current?.path === currentFile) return
    let cancelled = false
    setFileLoading(true)
    setFileError(null)
    setActiveFile(null)
    void fetchFileContent(
      token,
      parsed.owner,
      parsed.repo,
      currentFile,
      repo.defaultBranch,
    ).then((result) => {
      if (cancelled) return
      if (result.ok) {
        setActiveFile({
          path: currentFile,
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
    })
    return () => {
      cancelled = true
    }
  }, [token, parsed, repo.defaultBranch, currentFile])

  const dirty = Boolean(
    activeFile && activeFile.content !== activeFile.originalContent,
  )
  const dirtyRef = useRef(dirty)
  dirtyRef.current = dirty

  const savingRef = useRef(saving)
  savingRef.current = saving

  const doSave = useCallback(async () => {
    const file = activeFileRef.current
    if (!token || !parsed || !file) return
    if (file.content === file.originalContent) return
    if (file.encoding === 'binary') return
    if (savingRef.current) return
    setSaving(true)
    setSaveError(null)
    const result = await putFileContent(
      token,
      parsed.owner,
      parsed.repo,
      file.path,
      {
        content: file.content,
        message: defaultCommitMessage('update', file.path),
        branch: repo.defaultBranch,
        sha: file.sha,
      },
    )
    setSaving(false)
    if (result.ok) {
      setActiveFile((prev) =>
        prev && prev.path === file.path
          ? { ...prev, sha: result.newSha, originalContent: file.content }
          : prev,
      )
    } else {
      setSaveError(result.error)
    }
  }, [token, parsed, repo.defaultBranch])

  const [paletteOpen, setPaletteOpen] = useState(false)
  const paletteItems = useMemo(() => collectPaletteItems(tree), [tree])
  const wikilinkIndex = useMemo(() => buildWikilinkIndex(tree), [tree])

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      const combo = (e.metaKey || e.ctrlKey) && !e.shiftKey && !e.altKey
      if (combo && e.key === 's') {
        e.preventDefault()
        void doSave()
        return
      }
      if (combo && (e.key === 'k' || e.key === 'K')) {
        e.preventDefault()
        setPaletteOpen((v) => !v)
        return
      }
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [doSave])

  const handlePaletteSelect = useCallback(
    (item: PaletteItem) => {
      setPaletteOpen(false)
      if (item.kind === 'file') {
        handleSelectFile(item.path)
      } else {
        navigateToFolder(item.path)
      }
    },
    [handleSelectFile, navigateToFolder],
  )

  const handleContextMenu = useCallback(
    (target: SidebarContextTarget, event: MouseEvent) => {
      setContextMenu({
        target,
        anchor: { mouseX: event.clientX + 2, mouseY: event.clientY + 2 },
      })
    },
    [],
  )

  const isPinned = useCallback(
    (path: string) => pinnedItems.some((p) => p.path === path),
    [pinnedItems],
  )

  const togglePin = useCallback(
    (target: SidebarContextTarget) => {
      setPinnedItems(
        isPinned(target.path)
          ? pinsStore.unpin(target.path)
          : pinsStore.pin({ path: target.path, kind: target.kind }),
      )
    },
    [pinsStore, isPinned],
  )

  const openRenameDialog = useCallback((target: SidebarContextTarget) => {
    setDialogError(null)
    setDialog({ kind: 'rename', target })
  }, [])

  const openNewFileDialog = useCallback((parentPath: string) => {
    setDialogError(null)
    setDialog({ kind: 'newFile', parentPath })
  }, [])

  const openNewFolderDialog = useCallback((parentPath: string) => {
    setDialogError(null)
    setDialog({ kind: 'newFolder', parentPath })
  }, [])

  const openDeleteDialog = useCallback(
    async (target: SidebarContextTarget) => {
      if (target.kind !== 'file' || !token || !parsed) return
      setDialogError(null)
      setDialog({ kind: 'deleteFile', path: target.path, sha: '' })
      const result = await fetchFileContent(
        token,
        parsed.owner,
        parsed.repo,
        target.path,
        repo.defaultBranch,
      )
      if (result.ok) {
        setDialog({ kind: 'deleteFile', path: target.path, sha: result.sha })
      } else {
        setDialogError(result.error)
      }
    },
    [token, parsed, repo.defaultBranch],
  )

  const contextMenuItems: ContextMenuItem[] = useMemo(() => {
    if (!contextMenu) return []
    const t = contextMenu.target
    const pinned = isPinned(t.path)
    if (t.kind === 'folder') {
      return [
        {
          kind: 'item',
          label: 'New note',
          onClick: () => openNewFileDialog(t.path),
        },
        {
          kind: 'item',
          label: 'New folder',
          onClick: () => openNewFolderDialog(t.path),
        },
        { kind: 'divider' },
        {
          kind: 'item',
          label: pinned ? 'Unpin' : 'Pin',
          onClick: () => togglePin(t),
        },
        {
          kind: 'item',
          label: 'Rename',
          onClick: () => openRenameDialog(t),
          disabled: true,
        },
      ]
    }
    return [
      {
        kind: 'item',
        label: pinned ? 'Unpin' : 'Pin',
        onClick: () => togglePin(t),
      },
      { kind: 'item', label: 'Rename', onClick: () => openRenameDialog(t) },
      { kind: 'divider' },
      {
        kind: 'item',
        label: 'Delete',
        danger: true,
        onClick: () => void openDeleteDialog(t),
      },
    ]
  }, [
    contextMenu,
    isPinned,
    togglePin,
    openRenameDialog,
    openNewFileDialog,
    openNewFolderDialog,
    openDeleteDialog,
  ])

  const handlePinnedClick = useCallback(
    (item: PinnedItem) => {
      if (item.kind === 'file') {
        handleSelectFile(item.path)
      } else {
        navigateToFolder(item.path)
      }
    },
    [handleSelectFile, navigateToFolder],
  )

  // Dialog confirmations
  const handleDialogConfirm = useCallback(
    async (value?: string) => {
      if (!token || !parsed) return
      setDialogError(null)
      setDialogBusy(true)
      try {
        if (dialog.kind === 'rename' && value) {
          const oldPath = dialog.target.path
          const newPath = joinPath(dirnameOf(oldPath), value)
          if (dialog.target.kind === 'file') {
            const fetched = await fetchFileContent(
              token,
              parsed.owner,
              parsed.repo,
              oldPath,
              repo.defaultBranch,
            )
            if (!fetched.ok) {
              setDialogError(fetched.error)
              return
            }
            const created = await putFileContent(
              token,
              parsed.owner,
              parsed.repo,
              newPath,
              {
                content: fetched.content,
                message: defaultCommitMessage('rename', oldPath, newPath),
                branch: repo.defaultBranch,
              },
            )
            if (!created.ok) {
              setDialogError(created.error)
              return
            }
            const deleted = await deleteFileContent(
              token,
              parsed.owner,
              parsed.repo,
              oldPath,
              {
                message: defaultCommitMessage('rename', oldPath, newPath),
                branch: repo.defaultBranch,
                sha: fetched.sha,
              },
            )
            if (!deleted.ok) {
              setDialogError(deleted.error)
              return
            }
            setPinnedItems(pinsStore.rename(oldPath, newPath))
            if (activeFileRef.current?.path === oldPath) {
              setActiveFile((prev) =>
                prev ? { ...prev, path: newPath, sha: created.newSha } : prev,
              )
              navigateToFile(newPath)
            }
            setDialog({ kind: 'none' })
            await loadTree()
          } else {
            // Folder rename requires walking every file — out of scope for now.
            setDialogError('Folder rename is not supported yet.')
            return
          }
        } else if (dialog.kind === 'newFile' && value) {
          const name = value.endsWith('.md') ? value : `${value}.md`
          const newPath = joinPath(dialog.parentPath, name)
          const created = await putFileContent(
            token,
            parsed.owner,
            parsed.repo,
            newPath,
            {
              content: '',
              message: defaultCommitMessage('create', newPath),
              branch: repo.defaultBranch,
            },
          )
          if (!created.ok) {
            setDialogError(created.error)
            return
          }
          setDialog({ kind: 'none' })
          await loadTree()
          handleSelectFile(newPath)
        } else if (dialog.kind === 'newFolder' && value) {
          const folderPath = joinPath(dialog.parentPath, value)
          const placeholderPath = joinPath(folderPath, '.gitkeep')
          const created = await putFileContent(
            token,
            parsed.owner,
            parsed.repo,
            placeholderPath,
            {
              content: '',
              message: defaultCommitMessage('create', folderPath + '/'),
              branch: repo.defaultBranch,
            },
          )
          if (!created.ok) {
            setDialogError(created.error)
            return
          }
          setDialog({ kind: 'none' })
          await loadTree()
        } else if (dialog.kind === 'deleteFile') {
          if (!dialog.sha) {
            setDialogError('Still fetching file sha…')
            return
          }
          const deleted = await deleteFileContent(
            token,
            parsed.owner,
            parsed.repo,
            dialog.path,
            {
              message: defaultCommitMessage('delete', dialog.path),
              branch: repo.defaultBranch,
              sha: dialog.sha,
            },
          )
          if (!deleted.ok) {
            setDialogError(deleted.error)
            return
          }
          setPinnedItems(pinsStore.remove(dialog.path))
          if (activeFileRef.current?.path === dialog.path) {
            setActiveFile(null)
            const slash = dialog.path.lastIndexOf('/')
            const parent = slash >= 0 ? dialog.path.slice(0, slash) : ''
            navigateToFolder(parent)
          }
          setDialog({ kind: 'none' })
          await loadTree()
        }
      } finally {
        setDialogBusy(false)
      }
    },
    [
      token,
      parsed,
      repo.defaultBranch,
      dialog,
      pinsStore,
      loadTree,
      handleSelectFile,
      navigateToFile,
      navigateToFolder,
    ],
  )

  const handleGistSubmit = useCallback(
    async ({ description, isPublic }: GistSubmission) => {
      if (!token) return
      const file = activeFileRef.current
      if (!file) return
      setGistBusy(true)
      setGistError(null)
      const filename = basenameOf(file.path)
      const result = await createGist(token, {
        filename,
        content: file.content,
        description,
        isPublic,
      })
      setGistBusy(false)
      if (result.ok) {
        setGistOpen(false)
        window.open(result.htmlUrl, '_blank', 'noopener,noreferrer')
      } else {
        setGistError(result.error)
      }
    },
    [token],
  )

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
        width: '100vw',
        maxWidth: '100%',
        overflow: 'hidden',
        display: 'grid',
        gridTemplateRows: 'auto 1fr',
      }}
    >
      <AppBar position="static" color="default" elevation={0}>
        <Toolbar variant="dense" sx={{ gap: 1, minWidth: 0 }}>
          <Tooltip title={sidebarVisible ? 'Hide sidebar' : 'Show sidebar'}>
            <IconButton
              size="small"
              onClick={() => setSidebarOverride(!sidebarVisible)}
              aria-label="toggle sidebar"
            >
              {sidebarVisible ? (
                <MenuOpenIcon fontSize="small" />
              ) : (
                <MenuIcon fontSize="small" />
              )}
            </IconButton>
          </Tooltip>
          <Typography
            variant="subtitle1"
            fontWeight={700}
            sx={{
              fontFamily: 'ui-monospace, Menlo, monospace',
              minWidth: 0,
              whiteSpace: 'nowrap',
              overflow: 'hidden',
              textOverflow: 'ellipsis',
            }}
          >
            {repo.fullName}
          </Typography>
          <Typography
            variant="caption"
            color="text.secondary"
            sx={{
              display: { xs: 'none', sm: 'inline' },
              whiteSpace: 'nowrap',
            }}
          >
            branch: {repo.defaultBranch}
          </Typography>
          <Box flex={1} />
          {activeFile && (
            <Typography
              variant="caption"
              sx={{
                mr: 1,
                minWidth: 0,
                maxWidth: { xs: 120, sm: 240, md: 400 },
                whiteSpace: 'nowrap',
                overflow: 'hidden',
                textOverflow: 'ellipsis',
                display: { xs: 'none', sm: 'inline-block' },
              }}
            >
              {activeFile.path}
              {dirty && ' • unsaved'}
              {saving && ' • saving…'}
            </Typography>
          )}
          {saveError && (
            <Alert severity="error" sx={{ py: 0 }}>
              {saveError}
            </Alert>
          )}
          {isMarkdown && (
            <Tooltip title={previewVisible ? 'Hide preview' : 'Show preview'}>
              <IconButton
                size="small"
                onClick={() => setPreviewOverride(!previewVisible)}
                aria-label="toggle preview"
              >
                {previewVisible ? (
                  <VisibilityOffIcon fontSize="small" />
                ) : (
                  <VisibilityIcon fontSize="small" />
                )}
              </IconButton>
            </Tooltip>
          )}
          <Box sx={{ display: { xs: 'none', sm: 'inline-flex' } }}>
            <Tooltip
              title={
                gistAllowed
                  ? 'Publish as gist'
                  : 'Re-authorize with gist scope to enable'
              }
            >
              <span>
                <IconButton
                  size="small"
                  onClick={() => {
                    setGistError(null)
                    setGistOpen(true)
                  }}
                  disabled={
                    !gistAllowed ||
                    !activeFile ||
                    activeFile.encoding === 'binary'
                  }
                  aria-label="publish as gist"
                >
                  <IosShareIcon fontSize="small" />
                </IconButton>
              </span>
            </Tooltip>
          </Box>
          <Tooltip title="Save (⌘S)">
            <span>
              <Button
                size="small"
                variant="contained"
                startIcon={<SaveIcon />}
                onClick={() => void doSave()}
                disabled={
                  !dirty ||
                  saving ||
                  !activeFile ||
                  activeFile.encoding === 'binary'
                }
              >
                Save
              </Button>
            </span>
          </Tooltip>
          <Box sx={{ display: { xs: 'none', sm: 'inline-flex' } }}>
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
          </Box>
          <Box sx={{ display: { xs: 'inline-flex', sm: 'none' } }}>
            <Tooltip title="More">
              <IconButton
                size="small"
                onClick={(e) => setOverflowAnchor(e.currentTarget)}
                aria-label="more"
              >
                <MoreVertIcon fontSize="small" />
              </IconButton>
            </Tooltip>
          </Box>
        </Toolbar>
      </AppBar>

      <Menu
        open={Boolean(overflowAnchor)}
        anchorEl={overflowAnchor}
        onClose={() => setOverflowAnchor(null)}
      >
        {activeFile && (
          <MenuItem disabled sx={{ opacity: '1 !important' }}>
            <ListItemText
              primary={activeFile.path}
              secondary={`branch: ${repo.defaultBranch}`}
              primaryTypographyProps={{
                fontSize: 13,
                fontFamily: 'ui-monospace, Menlo, monospace',
                sx: {
                  whiteSpace: 'nowrap',
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                  maxWidth: 260,
                },
              }}
              secondaryTypographyProps={{ fontSize: 11 }}
            />
          </MenuItem>
        )}
        <MenuItem
          disabled={
            !gistAllowed || !activeFile || activeFile.encoding === 'binary'
          }
          onClick={() => {
            setOverflowAnchor(null)
            setGistError(null)
            setGistOpen(true)
          }}
        >
          <ListItemIcon>
            <IosShareIcon fontSize="small" />
          </ListItemIcon>
          <ListItemText
            primary={gistAllowed ? 'Publish as gist' : 'Gist (re-auth needed)'}
          />
        </MenuItem>
        <MenuItem
          onClick={() => {
            setOverflowAnchor(null)
            onChangeRepo()
          }}
        >
          <ListItemIcon>
            <SwapHorizIcon fontSize="small" />
          </ListItemIcon>
          <ListItemText primary="Switch repo" />
        </MenuItem>
        <MenuItem
          onClick={() => {
            setOverflowAnchor(null)
            logout()
          }}
        >
          <ListItemIcon>
            <LogoutIcon fontSize="small" />
          </ListItemIcon>
          <ListItemText primary="Sign out" />
        </MenuItem>
      </Menu>

      <Box
        sx={{
          position: 'relative',
          display: 'grid',
          gridTemplateColumns:
            sidebarVisible && !mobile ? '280px 1fr' : '1fr',
          overflow: 'hidden',
        }}
      >
        {mobile && sidebarVisible && (
          <Box
            aria-hidden
            onClick={() => setSidebarOverride(false)}
            sx={{
              position: 'absolute',
              inset: 0,
              bgcolor: 'rgba(0, 0, 0, 0.4)',
              zIndex: 2,
            }}
          />
        )}
        <Box
          sx={{
            display: sidebarVisible ? 'flex' : 'none',
            borderRight: '1px solid',
            borderColor: 'divider',
            overflow: 'hidden',
            bgcolor: 'background.paper',
            flexDirection: 'column',
            ...(mobile
              ? {
                  position: 'absolute',
                  top: 0,
                  left: 0,
                  bottom: 0,
                  width: 280,
                  maxWidth: '85vw',
                  zIndex: 3,
                  boxShadow: 6,
                }
              : {}),
          }}
        >
          <Box
            sx={{
              px: 1.5,
              py: 0.75,
              borderBottom: '1px solid',
              borderColor: 'divider',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
            }}
          >
            <Typography variant="caption" color="text.secondary">
              Files
            </Typography>
            <Box>
              <Tooltip
                title={`New note in ${currentFolder || 'root'}`}
              >
                <IconButton
                  size="small"
                  onClick={() => openNewFileDialog(currentFolder)}
                  sx={{ fontSize: 12 }}
                >
                  +
                </IconButton>
              </Tooltip>
              <IconButton size="small" onClick={loadTree} title="Reload">
                <RefreshIcon fontSize="inherit" />
              </IconButton>
            </Box>
          </Box>
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
              <Sidebar
                root={tree}
                activePath={activeFile?.path ?? null}
                pinnedItems={pinnedItems}
                sort={sort}
                currentFolder={currentFolder}
                onSortChange={setSort}
                onNavigateFolder={navigateToFolder}
                onSelectFile={handleSelectFile}
                onContextMenu={handleContextMenu}
                onPinnedClick={handlePinnedClick}
              />
            </>
          )}
        </Box>

        <Box
          sx={{ overflow: 'hidden', minWidth: 0 }}
          onMouseDownCapture={() => {
            if (mobile && sidebarVisible) setSidebarOverride(false)
          }}
        >
          <EditorPane
            loading={fileLoading}
            file={activeFile}
            fileError={fileError}
            isMarkdown={isMarkdown}
            previewVisible={previewVisible}
            mobile={mobile}
            previewRatio={previewRatio}
            wikilinkIndex={wikilinkIndex}
            onRatioChange={handleRatioChange}
            onWikilinkClick={handleSelectFile}
            onContentChange={(next) =>
              setActiveFile((prev) => (prev ? { ...prev, content: next } : prev))
            }
          />
        </Box>
      </Box>

      <ContextMenu
        anchor={contextMenu?.anchor ?? null}
        items={contextMenuItems}
        onClose={() => setContextMenu(null)}
      />

      <PromptDialog
        open={dialog.kind === 'rename'}
        title={
          dialog.kind === 'rename'
            ? `Rename ${dialog.target.kind === 'folder' ? 'folder' : 'file'}`
            : ''
        }
        label="New name"
        initialValue={
          dialog.kind === 'rename' ? dialog.target.name : ''
        }
        confirmLabel="Rename"
        onConfirm={(value) => void handleDialogConfirm(value)}
        onClose={() => setDialog({ kind: 'none' })}
        error={dialog.kind === 'rename' ? dialogError : null}
        busy={dialogBusy}
      />

      <PromptDialog
        open={dialog.kind === 'newFile'}
        title="New note"
        label="File name (.md optional)"
        initialValue=""
        confirmLabel="Create"
        onConfirm={(value) => void handleDialogConfirm(value)}
        onClose={() => setDialog({ kind: 'none' })}
        error={dialog.kind === 'newFile' ? dialogError : null}
        busy={dialogBusy}
      />

      <PromptDialog
        open={dialog.kind === 'newFolder'}
        title="New folder"
        label="Folder name"
        initialValue=""
        confirmLabel="Create"
        onConfirm={(value) => void handleDialogConfirm(value)}
        onClose={() => setDialog({ kind: 'none' })}
        error={dialog.kind === 'newFolder' ? dialogError : null}
        busy={dialogBusy}
      />

      <ConfirmDialog
        open={dialog.kind === 'deleteFile'}
        title="Delete file"
        message={
          dialog.kind === 'deleteFile'
            ? `Delete ${dialog.path}? This cannot be undone from here.`
            : ''
        }
        confirmLabel="Delete"
        onConfirm={() => void handleDialogConfirm()}
        onClose={() => setDialog({ kind: 'none' })}
        error={dialog.kind === 'deleteFile' ? dialogError : null}
        busy={dialogBusy}
      />

      <GistDialog
        open={gistOpen}
        filename={activeFile ? basenameOf(activeFile.path) : ''}
        onSubmit={(submission) => void handleGistSubmit(submission)}
        onClose={() => setGistOpen(false)}
        busy={gistBusy}
        error={gistError}
      />

      <CommandPalette
        open={paletteOpen}
        items={paletteItems}
        onSelect={handlePaletteSelect}
        onClose={() => setPaletteOpen(false)}
      />
    </Box>
  )
}

function EditorPane({
  loading,
  file,
  fileError,
  isMarkdown,
  previewVisible,
  mobile,
  previewRatio,
  wikilinkIndex,
  onRatioChange,
  onWikilinkClick,
  onContentChange,
}: {
  loading: boolean
  file: LoadedFile | null
  fileError: string | null
  isMarkdown: boolean
  previewVisible: boolean
  mobile: boolean
  previewRatio: number
  wikilinkIndex: WikilinkIndex
  onRatioChange: (next: number) => void
  onWikilinkClick: (path: string) => void
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

  const previewActive = isMarkdown && previewVisible
  const editor = (
    <MarkdownEditor
      value={file.content}
      onChange={onContentChange}
      markdownMode={isMarkdown}
    />
  )
  const preview = (
    <MarkdownPreview
      source={file.content}
      wikilinkIndex={wikilinkIndex}
      onWikilinkClick={onWikilinkClick}
    />
  )

  // Mobile: single pane, preview replaces editor.
  if (mobile) {
    return (
      <Box sx={{ height: '100%', overflow: 'hidden' }}>
        {previewActive ? preview : editor}
      </Box>
    )
  }

  // Desktop narrow (no preview): editor only.
  if (!previewActive) {
    return <Box sx={{ height: '100%', overflow: 'hidden' }}>{editor}</Box>
  }

  // Desktop split.
  return (
    <SplitPane
      ratio={previewRatio}
      onRatioChange={onRatioChange}
      left={editor}
      right={preview}
    />
  )
}

function dirnameOf(path: string): string {
  const slash = path.lastIndexOf('/')
  return slash >= 0 ? path.slice(0, slash) : ''
}

function basenameOf(path: string): string {
  const slash = path.lastIndexOf('/')
  return slash >= 0 ? path.slice(slash + 1) : path
}

function joinPath(parent: string, name: string): string {
  if (!parent) return name
  return `${parent}/${name}`
}
