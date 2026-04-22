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
import SettingsIcon from '@mui/icons-material/Settings'
import HistoryIcon from '@mui/icons-material/History'
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
import {
  MarkdownEditor,
  type MarkdownEditorHandle,
  type EditorSelectionInfo,
} from './MarkdownEditor'
import { MarkdownPreview } from './MarkdownPreview'
import { Sidebar, type SidebarContextTarget } from './Sidebar'
import { ContextMenu, type ContextMenuItem } from './ContextMenu'
import { PromptDialog } from './PromptDialog'
import { ConfirmDialog } from './ConfirmDialog'
import { SplitPane } from './SplitPane'
import { GistDialog, type GistSubmission } from './GistDialog'
import { FileHistory } from './FileHistory'
import { CommandPalette } from './CommandPalette'
import { collectPaletteItems, type PaletteItem } from '../lib/palette'
import { buildWikilinkIndex, type WikilinkIndex } from '../lib/wikilinks'
import { dailyNotePath, formatLocalDate } from '../lib/dailyNote'
import { TabBar } from './TabBar'
import { EmptyEditorState } from './EmptyEditorState'
import {
  AskClaudeDialog,
  AskClaudePill,
  SettingsDialog,
  type AskClaudeMode,
} from './AskClaude'
import { editSelection } from '../anthropic/editSelection'
import { generateAtCursor } from '../anthropic/generateAtCursor'
import { buildMentionContext, parseMentions } from '../anthropic/mentions'
import { loadAnthropicKey, saveAnthropicKey } from '../lib/anthropicKey'
import {
  isHidden,
  loadHiddenPaths,
  parseHiddenPatterns,
  saveHiddenPaths,
} from '../lib/hiddenPaths'
import {
  activateByIndex,
  activeTab as activeTabOf,
  closeTab as closeTabInState,
  loadTabs,
  openInActive,
  openInNewTab,
  renamePath as renamePathInTabs,
  saveTabs,
  type TabsState,
} from '../lib/tabs'
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
  const currentFile = routeFile(route)
  const currentQuery = routeQuery(route)
  // Sidebar folder is an independent axis of state:
  //   1. ?folder=... in the URL wins (user drilled while a file was open) —
  //      key *presence* matters; an empty string means "root".
  //   2. Otherwise, fall back to the route-derived folder (file's parent, or
  //      the /tree/... path when no file is open).
  const currentFolder =
    'folder' in currentQuery ? currentQuery.folder : routeFolder(route)

  // Sort: URL wins, localStorage is the default, DEFAULT_SORT is last resort.
  const sort: SortSettings = useMemo(() => {
    const fromUrl = parseSortToken(currentQuery.sort)
    if (fromUrl) return fromUrl
    return loadSortSettings(repo.fullName) ?? DEFAULT_SORT
  }, [currentQuery.sort, repo.fullName])

  const navigateToFolder = useCallback(
    (folder: string) => {
      // If a file is open, keep it open and update ?folder= so the sidebar
      // drills without closing the note. Always set the key (including empty
      // string for "root") so it overrides the file's parent fallback.
      if (route.kind === 'file') {
        navigate(
          formatRoute({
            ...route,
            query: { ...currentQuery, folder },
          }),
          { replace: true },
        )
        return
      }
      // No file open — nav as before. Strip any lingering ?folder since the
      // path carries the folder state now.
      const { folder: _stripped, ...restQuery } = currentQuery
      void _stripped
      navigate(
        formatRoute({
          kind: 'folder',
          owner,
          repo: repoName,
          folder,
          query: restQuery,
        }),
      )
    },
    [navigate, owner, repoName, currentQuery, route],
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
        formatRoute({ ...route, query: nextQuery }),
        { replace: true },
      )
    },
    [currentQuery, navigate, repo.fullName, route],
  )

  const [entries, setEntries] = useState<GitTreeEntry[]>([])
  const [treeError, setTreeError] = useState<string | null>(null)
  const [treeLoading, setTreeLoading] = useState(true)
  const [truncated, setTruncated] = useState(false)

  const [tabsState, setTabsState] = useState<TabsState>(() =>
    loadTabs(repo.fullName),
  )
  useEffect(() => saveTabs(repo.fullName, tabsState), [repo.fullName, tabsState])
  const active = useMemo(() => activeTabOf(tabsState), [tabsState])

  const [files, setFiles] = useState<Record<string, LoadedFile>>({})
  const activeFile: LoadedFile | null = active ? files[active.id] ?? null : null

  const updateActiveFile = useCallback(
    (patch: (prev: LoadedFile) => LoadedFile) => {
      setFiles((prev) => {
        if (!active) return prev
        const cur = prev[active.id]
        if (!cur) return prev
        return { ...prev, [active.id]: patch(cur) }
      })
    },
    [active],
  )

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
  const [historyOpen, setHistoryOpen] = useState(false)
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

  // Ask Claude state
  const editorHandleRef = useRef<MarkdownEditorHandle | null>(null)
  const [editorSelection, setEditorSelection] =
    useState<EditorSelectionInfo | null>(null)
  const [askOpen, setAskOpen] = useState(false)
  const [askBusy, setAskBusy] = useState(false)
  const [askError, setAskError] = useState<string | null>(null)
  // Either a rewrite (with selection range) or an insert (with cursor offset).
  // We capture this at dialog-open time so later edits don't shift the anchor.
  type AskAnchor =
    | {
        mode: 'rewrite'
        from: number
        to: number
        text: string
      }
    | { mode: 'insert'; offset: number; before: string; after: string }
  const [askAnchor, setAskAnchor] = useState<AskAnchor | null>(null)
  const [anthropicKey, setAnthropicKey] = useState<string | null>(() =>
    loadAnthropicKey(),
  )
  const [hiddenPathsRaw, setHiddenPathsRaw] = useState(() => loadHiddenPaths())
  const hiddenPatterns = useMemo(
    () => parseHiddenPatterns(hiddenPathsRaw),
    [hiddenPathsRaw],
  )
  const [settingsOpen, setSettingsOpen] = useState(false)

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

  const visibleEntries = useMemo(
    () => entries.filter((e) => !isHidden(e.path, hiddenPatterns)),
    [entries, hiddenPatterns],
  )
  const tree = useMemo(() => buildTree(visibleEntries), [visibleEntries])
  const filePaths = useMemo(
    () => visibleEntries.filter((e) => e.type === 'blob').map((e) => e.path),
    [visibleEntries],
  )

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

  // Keep tabs state in sync with the URL's current file.
  // - URL has a file → ensure it's in tabs + active (either re-activating an
  //   existing tab or replacing the active tab's path).
  // - URL has no file → deactivate (tabs list stays; nothing "active").
  useEffect(() => {
    setTabsState((prev) => {
      if (!currentFile) {
        return prev.activeId === null ? prev : { ...prev, activeId: null }
      }
      const existing = prev.tabs.find((t) => t.path === currentFile)
      if (existing) {
        return prev.activeId === existing.id
          ? prev
          : { ...prev, activeId: existing.id }
      }
      return openInActive(prev, currentFile)
    })
  }, [currentFile])

  const handleOpenInNewTab = useCallback(
    (path: string) => {
      setTabsState((prev) => openInNewTab(prev, path))
      navigateToFile(path)
      if (mobile) setSidebarOverride(false)
    },
    [navigateToFile, mobile],
  )

  const handleSelectFile = useCallback(
    (path: string, event?: MouseEvent) => {
      // Cmd/Ctrl-click → open in a new tab instead of replacing the active one.
      if (event && (event.metaKey || event.ctrlKey)) {
        handleOpenInNewTab(path)
        return
      }
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
    [navigateToFile, mobile, handleOpenInNewTab],
  )

  const handleActivateTab = useCallback(
    (id: string) => {
      // Activating is just navigating to that tab's path. The URL→tabs sync
      // effect will flip activeId to match.
      const tab = tabsState.tabs.find((t) => t.id === id)
      if (!tab) return
      navigateToFile(tab.path)
    },
    [tabsState.tabs, navigateToFile],
  )

  const handleCloseTab = useCallback(
    (id: string) => {
      const closing = tabsState.tabs.find((t) => t.id === id)
      const cachedFile = closing ? filesRef.current[closing.id] : null
      if (
        cachedFile &&
        cachedFile.content !== cachedFile.originalContent
      ) {
        const ok = window.confirm(`Discard unsaved changes in ${closing!.path}?`)
        if (!ok) return
      }
      setFiles((prev) => {
        if (!(id in prev)) return prev
        const { [id]: _, ...rest } = prev
        void _
        return rest
      })
      setTabsState((prev) => {
        const next = closeTabInState(prev, id)
        // If the active tab changed as a result, navigate to match.
        if (next.activeId !== prev.activeId) {
          const nextActive = next.activeId
            ? next.tabs.find((t) => t.id === next.activeId)
            : null
          // Defer the navigation; state updater must be pure.
          queueMicrotask(() => {
            if (nextActive) {
              navigateToFile(nextActive.path)
            } else {
              // No tabs left — move off the /blob URL to a /tree URL so the
              // empty state is reflected in the address bar. Using navigate()
              // directly; navigateToFolder() would preserve the file route.
              navigate(
                formatRoute(
                  currentFolder
                    ? {
                        kind: 'folder',
                        owner,
                        repo: repoName,
                        folder: currentFolder,
                        query: {},
                      }
                    : {
                        kind: 'repo',
                        owner,
                        repo: repoName,
                        query: {},
                      },
                ),
              )
            }
          })
        }
        return next
      })
    },
    [
      tabsState.tabs,
      navigateToFile,
      navigate,
      owner,
      repoName,
      currentFolder,
    ],
  )

  const dirtyTabIds = useMemo(() => {
    const set = new Set<string>()
    for (const [id, f] of Object.entries(files)) {
      if (f.content !== f.originalContent) set.add(id)
    }
    return set
  }, [files])

  // Load the active tab's file content on demand. We cache per-tab in `files`,
  // so switching back to a tab doesn't re-fetch and unsaved edits survive.
  // `filesRef` is read inside the effect so we don't re-run whenever the map
  // mutates — only when `active` or auth/parsed/branch change.
  const filesRef = useRef(files)
  filesRef.current = files
  useEffect(() => {
    if (!token || !parsed) return
    if (!active) {
      setFileError(null)
      setFileLoading(false)
      return
    }
    const cached = filesRef.current[active.id]
    if (cached && cached.path === active.path) {
      setFileError(cached.encoding === 'binary' ? 'Binary file — cannot edit in browser.' : null)
      setFileLoading(false)
      return
    }
    let cancelled = false
    setFileLoading(true)
    setFileError(null)
    void fetchFileContent(
      token,
      parsed.owner,
      parsed.repo,
      active.path,
      repo.defaultBranch,
    ).then((result) => {
      if (cancelled) return
      if (result.ok) {
        setFiles((prev) => ({
          ...prev,
          [active.id]: {
            path: active.path,
            content: result.content,
            originalContent: result.content,
            sha: result.sha,
            encoding: result.encoding,
          },
        }))
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
  }, [token, parsed, repo.defaultBranch, active])

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
      updateActiveFile((prev) =>
        prev.path === file.path
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
      // Ctrl-P toggles the preview pane. Uses plain ctrlKey so it doesn't
      // conflict with Cmd-P (print) on Mac — and preventDefault stops the
      // browser's print dialog on every platform.
      if (
        e.ctrlKey &&
        !e.metaKey &&
        !e.shiftKey &&
        !e.altKey &&
        (e.key === 'p' || e.key === 'P')
      ) {
        e.preventDefault()
        setPreviewOverride((prev) =>
          prev === null ? !previewVisible : !prev,
        )
        return
      }
      // Ctrl-W closes the active tab. Uses plain ctrlKey (not metaKey) so it
      // doesn't fight Cmd-W on Mac (browser close).
      if (
        e.ctrlKey &&
        !e.metaKey &&
        !e.shiftKey &&
        !e.altKey &&
        (e.key === 'w' || e.key === 'W')
      ) {
        if (tabsState.activeId) {
          e.preventDefault()
          handleCloseTab(tabsState.activeId)
        }
        return
      }
      // Ctrl-1..9 → activate the Nth tab. Use plain ctrlKey (not metaKey) to
      // avoid stomping the browser's Cmd-1..9 tab switch on Mac.
      if (e.ctrlKey && !e.metaKey && !e.shiftKey && !e.altKey) {
        if (e.key >= '1' && e.key <= '9') {
          const idx = Number(e.key)
          const target = activateByIndex(tabsState, idx)
          if (target.activeId !== tabsState.activeId) {
            e.preventDefault()
            const tab = target.tabs.find((t) => t.id === target.activeId)
            if (tab) navigateToFile(tab.path)
          }
          return
        }
      }
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [doSave, tabsState, navigateToFile, handleCloseTab, previewVisible])

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
    (item: PinnedItem, event: MouseEvent) => {
      if (item.kind === 'file') {
        handleSelectFile(item.path, event)
      } else {
        navigateToFolder(item.path)
      }
    },
    [handleSelectFile, navigateToFolder],
  )

  const todayPath = useMemo(() => dailyNotePath(), [])
  const todayLabel = useMemo(() => formatLocalDate(new Date()), [])

  const handleOpenToday = useCallback(async () => {
    if (!token || !parsed) return
    // Ask GitHub directly whether the file exists. Our in-memory tree can be
    // stale (another tab/session created the note after our last loadTree()).
    const existing = await fetchFileContent(
      token,
      parsed.owner,
      parsed.repo,
      todayPath,
      repo.defaultBranch,
    )
    if (existing.ok) {
      // Already exists — just open it.
      handleSelectFile(todayPath)
      return
    }
    // Assume 404 → create it. putFileContent returns a 422 if we were wrong,
    // which surfaces as a readable error.
    const created = await putFileContent(
      token,
      parsed.owner,
      parsed.repo,
      todayPath,
      {
        content: '',
        message: defaultCommitMessage('create', todayPath),
        branch: repo.defaultBranch,
      },
    )
    if (!created.ok) {
      setSaveError(created.error)
      return
    }
    await loadTree()
    handleSelectFile(todayPath)
  }, [
    token,
    parsed,
    repo.defaultBranch,
    todayPath,
    handleSelectFile,
    loadTree,
  ])

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      // Require BOTH Ctrl and Cmd (e.g. Ctrl+Cmd+H on macOS) so it doesn't
      // collide with the browser's Cmd+H (hide window) or Ctrl+H (history).
      const both = e.metaKey && e.ctrlKey && !e.shiftKey && !e.altKey
      if (!both) return
      if (e.key !== 'h' && e.key !== 'H') return
      e.preventDefault()
      void handleOpenToday()
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [handleOpenToday])

  // Resolve /:owner/:repo/today → /:owner/:repo/blob/Daily Notes/YYYY-MM-DD.md
  // using replaceState so /today doesn't sit in back-history.
  const todayResolvingRef = useRef(false)
  useEffect(() => {
    if (route.kind !== 'today') return
    if (!token || !parsed) return
    if (todayResolvingRef.current) return
    todayResolvingRef.current = true
    const run = async () => {
      try {
        const existing = await fetchFileContent(
          token,
          parsed.owner,
          parsed.repo,
          todayPath,
          repo.defaultBranch,
        )
        if (!existing.ok) {
          const created = await putFileContent(
            token,
            parsed.owner,
            parsed.repo,
            todayPath,
            {
              content: '',
              message: defaultCommitMessage('create', todayPath),
              branch: repo.defaultBranch,
            },
          )
          if (!created.ok) {
            setSaveError(created.error)
            return
          }
          await loadTree()
        }
        navigate(
          formatRoute({
            kind: 'file',
            owner,
            repo: repoName,
            file: todayPath,
            query: currentQuery,
          }),
          { replace: true },
        )
      } finally {
        todayResolvingRef.current = false
      }
    }
    void run()
  }, [
    route.kind,
    token,
    parsed,
    todayPath,
    loadTree,
    navigate,
    owner,
    repoName,
    currentQuery,
    repo.defaultBranch,
  ])

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
            setTabsState((prev) => renamePathInTabs(prev, oldPath, newPath))
            setFiles((prev) => {
              let changed = false
              const next: Record<string, LoadedFile> = {}
              for (const [k, v] of Object.entries(prev)) {
                if (v.path === oldPath) {
                  changed = true
                  next[k] = { ...v, path: newPath, sha: created.newSha }
                } else {
                  next[k] = v
                }
              }
              return changed ? next : prev
            })
            if (activeFileRef.current?.path === oldPath) {
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
          // Close any tabs that were on the deleted path and drop their cached file.
          const deletedPath = dialog.path
          setTabsState((prev) => {
            let next = prev
            for (const t of prev.tabs) {
              if (t.path === deletedPath) next = closeTabInState(next, t.id)
            }
            return next
          })
          setFiles((prev) => {
            const next: Record<string, LoadedFile> = {}
            let changed = false
            for (const [k, v] of Object.entries(prev)) {
              if (v.path === deletedPath) {
                changed = true
                continue
              }
              next[k] = v
            }
            return changed ? next : prev
          })
          if (activeFileRef.current?.path === deletedPath) {
            const slash = deletedPath.lastIndexOf('/')
            const parent = slash >= 0 ? deletedPath.slice(0, slash) : ''
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

  // Opens Ask Claude. If there's a non-empty selection → rewrite mode. Else →
  // insert mode at the current cursor. Caller should only invoke when an
  // editor is mounted.
  const openAskClaude = useCallback(() => {
    const handle = editorHandleRef.current
    if (!handle) return
    const sel = handle.getSelection()
    if (sel && sel.text.trim()) {
      setAskAnchor({
        mode: 'rewrite',
        from: sel.from,
        to: sel.to,
        text: sel.text,
      })
    } else {
      const cur = handle.getCursor()
      if (!cur) return
      setAskAnchor({
        mode: 'insert',
        offset: cur.offset,
        before: cur.beforeContext,
        after: cur.afterContext,
      })
    }
    setAskError(null)
    setAskOpen(true)
  }, [])

  const handleAskSubmit = useCallback(
    async (instruction: string) => {
      const anchor = askAnchor
      const file = activeFileRef.current
      if (!anchor || !file) return
      if (!anthropicKey) {
        setSettingsOpen(true)
        return
      }
      setAskBusy(true)
      setAskError(null)

      // Resolve @mentions: fetch each referenced file and inject as context.
      let resolvedInstruction = instruction
      const mentionPaths = parseMentions(instruction)
      if (mentionPaths.length > 0 && parsed && token) {
        const resolvedToken = token
        const resolved: Record<string, string> = {}
        await Promise.all(
          mentionPaths.map(async (path) => {
            const result = await fetchFileContent(
              resolvedToken,
              parsed.owner,
              parsed.repo,
              path,
              repo.defaultBranch,
            )
            if (result.ok) resolved[path] = result.content
          }),
        )
        const mentionCtx = buildMentionContext(resolved)
        if (mentionCtx) {
          resolvedInstruction = `Referenced files:\n\n${mentionCtx}\n\n${instruction}`
        }
      }

      if (anchor.mode === 'rewrite') {
        const result = await editSelection({
          apiKey: anthropicKey,
          instruction: resolvedInstruction,
          selection: anchor.text,
          documentContext: file.content,
        })
        setAskBusy(false)
        if (!result.ok) {
          setAskError(result.error)
          return
        }
        editorHandleRef.current?.replaceRange(
          anchor.from,
          anchor.to,
          result.text,
        )
      } else {
        const result = await generateAtCursor({
          apiKey: anthropicKey,
          instruction: resolvedInstruction,
          document: file.content,
          cursorOffset: anchor.offset,
        })
        setAskBusy(false)
        if (!result.ok) {
          setAskError(result.error)
          return
        }
        editorHandleRef.current?.insertAt(anchor.offset, result.text)
      }
      setAskOpen(false)
    },
    [anthropicKey, askAnchor, parsed, repo.defaultBranch, token],
  )

  // ⌘J / Ctrl-J opens Ask Claude. Selection present → rewrite; empty → insert
  // at cursor. No-op when the editor isn't focused/mounted.
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      const combo = (e.metaKey || e.ctrlKey) && !e.shiftKey && !e.altKey
      if (combo && (e.key === 'j' || e.key === 'J')) {
        if (!editorHandleRef.current) return
        e.preventDefault()
        openAskClaude()
      }
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [openAskClaude])

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
          <Box>
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
          disabled={!active}
          onClick={() => {
            setOverflowAnchor(null)
            setHistoryOpen(true)
          }}
        >
          <ListItemIcon>
            <HistoryIcon fontSize="small" />
          </ListItemIcon>
          <ListItemText primary="File history" />
        </MenuItem>
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
            setSettingsOpen(true)
          }}
        >
          <ListItemIcon>
            <SettingsIcon fontSize="small" />
          </ListItemIcon>
          <ListItemText primary="Settings" />
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
                onOpenToday={() => void handleOpenToday()}
                todayLabel={todayLabel}
                todayPath={todayPath}
              />
            </>
          )}
        </Box>

        <Box
          sx={{
            overflow: 'hidden',
            minWidth: 0,
            display: 'flex',
            flexDirection: 'column',
          }}
          onMouseDownCapture={() => {
            if (mobile && sidebarVisible) setSidebarOverride(false)
          }}
        >
          <TabBar
            tabs={tabsState.tabs}
            activeId={tabsState.activeId}
            dirtyIds={dirtyTabIds}
            onActivate={handleActivateTab}
            onClose={handleCloseTab}
          />
          <Box sx={{ flex: 1, overflow: 'hidden', minHeight: 0 }}>
            <EditorPane
              loading={fileLoading}
              file={activeFile}
              fileError={fileError}
              isMarkdown={isMarkdown}
              previewVisible={previewVisible}
              mobile={mobile}
              previewRatio={previewRatio}
              wikilinkIndex={wikilinkIndex}
              todayLabel={todayLabel}
              editorRef={editorHandleRef}
              onRatioChange={handleRatioChange}
              onWikilinkClick={handleSelectFile}
              onContentChange={(next) =>
                updateActiveFile((prev) => ({ ...prev, content: next }))
              }
              onSelectionChange={setEditorSelection}
              onOpenToday={() => void handleOpenToday()}
              onOpenPalette={() => setPaletteOpen(true)}
              onOpenSidebar={() => setSidebarOverride(true)}
            />
          </Box>
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

      {!askOpen && (
        <AskClaudePill
          selection={editorSelection}
          onAsk={openAskClaude}
        />
      )}

      <AskClaudeDialog
        open={askOpen}
        mode={
          askAnchor === null
            ? null
            : askAnchor.mode === 'rewrite'
              ? ({ kind: 'rewrite', selection: askAnchor.text } as AskClaudeMode)
              : ({
                  kind: 'insert',
                  before: askAnchor.before,
                  after: askAnchor.after,
                } as AskClaudeMode)
        }
        hasApiKey={Boolean(anthropicKey)}
        busy={askBusy}
        error={askError}
        filePaths={filePaths}
        onSubmit={handleAskSubmit}
        onClose={() => setAskOpen(false)}
        onOpenSettings={() => {
          setAskOpen(false)
          setSettingsOpen(true)
        }}
      />

      <SettingsDialog
        open={settingsOpen}
        initialKey={anthropicKey ?? ''}
        initialHiddenPaths={hiddenPathsRaw}
        onSave={(k, hidden) => {
          saveAnthropicKey(k)
          setAnthropicKey(k.trim() || null)
          saveHiddenPaths(hidden)
          setHiddenPathsRaw(hidden)
        }}
        onClose={() => setSettingsOpen(false)}
      />

      {parsed && activeFile && token && (
        <FileHistory
          open={historyOpen}
          token={token}
          owner={parsed.owner}
          repo={parsed.repo}
          branch={repo.defaultBranch}
          filePath={activeFile.path}
          onApply={(content) => {
            updateActiveFile((prev) => ({ ...prev, content }))
          }}
          onClose={() => setHistoryOpen(false)}
        />
      )}
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
  todayLabel,
  editorRef,
  onRatioChange,
  onWikilinkClick,
  onContentChange,
  onSelectionChange,
  onOpenToday,
  onOpenPalette,
  onOpenSidebar,
}: {
  loading: boolean
  file: LoadedFile | null
  fileError: string | null
  isMarkdown: boolean
  previewVisible: boolean
  mobile: boolean
  previewRatio: number
  wikilinkIndex: WikilinkIndex
  todayLabel: string
  editorRef: React.Ref<MarkdownEditorHandle>
  onRatioChange: (next: number) => void
  onWikilinkClick: (path: string) => void
  onContentChange: (next: string) => void
  onSelectionChange: (info: EditorSelectionInfo | null) => void
  onOpenToday: () => void
  onOpenPalette: () => void
  onOpenSidebar: () => void
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
      <EmptyEditorState
        mobile={mobile}
        todayLabel={todayLabel}
        onOpenToday={onOpenToday}
        onOpenPalette={onOpenPalette}
        onOpenSidebar={onOpenSidebar}
      />
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
      ref={editorRef}
      value={file.content}
      onChange={onContentChange}
      markdownMode={isMarkdown}
      onSelectionChange={onSelectionChange}
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
