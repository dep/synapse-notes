import { useCallback, useEffect, useRef, useState } from 'react'
import {
  Alert,
  Box,
  Button,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  List,
  ListItemButton,
  ListItemText,
  Paper,
  Popper,
  Stack,
  TextField,
  Typography,
} from '@mui/material'
import AutoAwesomeIcon from '@mui/icons-material/AutoAwesome'
import type { EditorSelectionInfo } from './MarkdownEditor'

export function AskClaudePill({
  selection,
  onAsk,
}: {
  selection: EditorSelectionInfo | null
  onAsk: () => void
}) {
  if (!selection || !selection.rect) return null
  const { left, bottom } = selection.rect
  return (
    <Box
      onMouseDown={(e) => {
        e.preventDefault()
      }}
      onClick={onAsk}
      sx={{
        position: 'fixed',
        left,
        top: bottom + 6,
        zIndex: 10,
        display: 'inline-flex',
        alignItems: 'center',
        gap: 0.5,
        px: 1,
        py: 0.5,
        bgcolor: 'primary.main',
        color: 'primary.contrastText',
        borderRadius: 999,
        fontSize: 12,
        fontWeight: 600,
        cursor: 'pointer',
        boxShadow: 3,
        userSelect: 'none',
        '&:hover': { filter: 'brightness(1.1)' },
      }}
      aria-label="ask claude"
    >
      <AutoAwesomeIcon sx={{ fontSize: 14 }} />
      Ask Claude
    </Box>
  )
}

export type AskClaudeMode =
  | { kind: 'rewrite'; selection: string }
  | { kind: 'insert'; before: string; after: string }

/** Returns the @-mention fragment the cursor is currently inside, or null. */
function getActiveMention(text: string, cursorPos: number): string | null {
  const before = text.slice(0, cursorPos)
  const match = before.match(/@(\S*)$/)
  return match ? match[1] : null
}

const MAX_SUGGESTIONS = 8

export function AskClaudeDialog({
  open,
  mode,
  hasApiKey,
  busy,
  error,
  filePaths,
  onSubmit,
  onClose,
  onOpenSettings,
}: {
  open: boolean
  mode: AskClaudeMode | null
  hasApiKey: boolean
  busy: boolean
  error: string | null
  filePaths: string[]
  onSubmit: (instruction: string) => void
  onClose: () => void
  onOpenSettings: () => void
}) {
  const [instruction, setInstruction] = useState('')
  const [mentionFragment, setMentionFragment] = useState<string | null>(null)
  const [selectedIdx, setSelectedIdx] = useState(0)
  const inputRef = useRef<HTMLTextAreaElement>(null)
  const anchorRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (open) {
      setInstruction('')
      setMentionFragment(null)
      setSelectedIdx(0)
    }
  }, [open])

  const suggestions = mentionFragment !== null
    ? filePaths
        .filter((p) => p.toLowerCase().includes(mentionFragment.toLowerCase()))
        .slice(0, MAX_SUGGESTIONS)
    : []

  const popperOpen = suggestions.length > 0

  const insertSuggestion = useCallback(
    (path: string) => {
      const el = inputRef.current
      if (!el) return
      const pos = el.selectionStart ?? instruction.length
      const before = instruction.slice(0, pos)
      const after = instruction.slice(pos)
      const atIdx = before.lastIndexOf('@')
      // Wrap paths that contain spaces in backticks so the parser can recover them.
      const token = path.includes(' ') ? `\`${path}\`` : path
      const newInstruction = before.slice(0, atIdx) + '@' + token + ' ' + after
      setInstruction(newInstruction)
      setMentionFragment(null)
      requestAnimationFrame(() => {
        el.focus()
        const newPos = atIdx + token.length + 2 // '@' + token + ' '
        el.setSelectionRange(newPos, newPos)
      })
    },
    [instruction],
  )

  const handleChange = useCallback(
    (e: React.ChangeEvent<HTMLTextAreaElement>) => {
      const val = e.target.value
      setInstruction(val)
      const pos = e.target.selectionStart ?? val.length
      const fragment = getActiveMention(val, pos)
      setMentionFragment(fragment)
      setSelectedIdx(0)
    },
    [],
  )

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLDivElement>) => {
      if (popperOpen) {
        if (e.key === 'ArrowDown') {
          e.preventDefault()
          setSelectedIdx((i) => Math.min(i + 1, suggestions.length - 1))
          return
        }
        if (e.key === 'ArrowUp') {
          e.preventDefault()
          setSelectedIdx((i) => Math.max(i - 1, 0))
          return
        }
        if (e.key === 'Enter' || e.key === 'Tab') {
          e.preventDefault()
          insertSuggestion(suggestions[selectedIdx])
          return
        }
        if (e.key === 'Escape') {
          e.preventDefault()
          setMentionFragment(null)
          return
        }
      }
      if (
        (e.metaKey || e.ctrlKey) &&
        e.key === 'Enter' &&
        instruction.trim() &&
        hasApiKey &&
        !busy
      ) {
        e.preventDefault()
        onSubmit(instruction.trim())
      }
    },
    [popperOpen, suggestions, selectedIdx, insertSuggestion, instruction, hasApiKey, busy, onSubmit],
  )

  const title = mode?.kind === 'insert' ? 'Ask Claude (insert)' : 'Ask Claude'
  const confirmLabel = mode?.kind === 'insert' ? 'Insert' : 'Rewrite'
  const placeholder =
    mode?.kind === 'insert'
      ? 'tip: @mention a file to add its content to the prompt'
      : 'e.g. make this more concise, rewrite as bullets, fix typos'

  return (
    <Dialog
      open={open}
      onClose={() => !busy && onClose()}
      maxWidth="sm"
      fullWidth
      TransitionProps={{ onEntered: () => inputRef.current?.focus() }}
    >
      <DialogTitle sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
        <AutoAwesomeIcon fontSize="small" sx={{ color: 'primary.main' }} />
        {title}
      </DialogTitle>
      <DialogContent>
        <Stack spacing={2} sx={{ mt: 1 }}>
          {!hasApiKey && (
            <Alert
              severity="warning"
              action={
                <Button size="small" onClick={onOpenSettings}>
                  Add key
                </Button>
              }
            >
              Add your Anthropic API key in settings to use this.
            </Alert>
          )}
          {mode?.kind === 'rewrite' && (
            <Box>
              <Typography variant="caption" color="text.secondary">
                Selection ({mode.selection.length} chars)
              </Typography>
              <PreviewBox>{truncateForPreview(mode.selection)}</PreviewBox>
            </Box>
          )}
          {mode?.kind === 'insert' && (
            <Box>
              <Typography variant="caption" color="text.secondary">
                Cursor position
              </Typography>
              <PreviewBox>
                {mode.before.trimStart() || '(beginning of note)'}
                <Box
                  component="span"
                  sx={{
                    color: 'primary.main',
                    fontWeight: 700,
                    px: 0.25,
                  }}
                >
                  ▎
                </Box>
                {mode.after.trimEnd() || '(end of note)'}
              </PreviewBox>
            </Box>
          )}
          <Box ref={anchorRef} sx={{ position: 'relative' }}>
            <TextField
              autoFocus
              fullWidth
              multiline
              minRows={2}
              label="Instruction"
              placeholder={placeholder}
              value={instruction}
              onChange={handleChange}
              disabled={busy || !hasApiKey}
              inputRef={inputRef}
              onKeyDown={handleKeyDown}
            />
            <Popper
              open={popperOpen}
              anchorEl={anchorRef.current}
              placement="bottom-start"
              style={{ zIndex: 1400, width: anchorRef.current?.offsetWidth }}
              modifiers={[{ name: 'offset', options: { offset: [0, 4] } }]}
            >
              <Paper elevation={4}>
                <List dense disablePadding>
                  {suggestions.map((path, idx) => (
                    <ListItemButton
                      key={path}
                      selected={idx === selectedIdx}
                      onMouseDown={(e) => e.preventDefault()}
                      onClick={() => insertSuggestion(path)}
                    >
                      <ListItemText
                        primary={path}
                        slotProps={{
                          primary: {
                            sx: {
                              fontFamily: 'ui-monospace, Menlo, monospace',
                              fontSize: 13,
                              overflow: 'hidden',
                              textOverflow: 'ellipsis',
                              whiteSpace: 'nowrap',
                            },
                          },
                        }}
                      />
                    </ListItemButton>
                  ))}
                </List>
              </Paper>
            </Popper>
          </Box>
          {error && <Alert severity="error">{error}</Alert>}
        </Stack>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose} disabled={busy}>
          Cancel
        </Button>
        <Button
          variant="contained"
          disabled={busy || !instruction.trim() || !hasApiKey}
          onClick={() => onSubmit(instruction.trim())}
        >
          {busy ? 'Thinking…' : confirmLabel}
        </Button>
      </DialogActions>
    </Dialog>
  )
}

function PreviewBox({ children }: { children: React.ReactNode }) {
  return (
    <Box
      component="pre"
      sx={{
        m: 0,
        mt: 0.5,
        p: 1,
        bgcolor: 'rgba(255,255,255,0.04)',
        border: '1px solid',
        borderColor: 'divider',
        borderRadius: 1,
        fontFamily: 'ui-monospace, Menlo, monospace',
        fontSize: 12,
        whiteSpace: 'pre-wrap',
        wordBreak: 'break-word',
        maxHeight: 120,
        overflow: 'auto',
        color: 'text.secondary',
      }}
    >
      {children}
    </Box>
  )
}

function truncateForPreview(s: string): string {
  if (s.length <= 400) return s
  return `${s.slice(0, 200)}\n…\n${s.slice(-180)}`
}

export function SettingsDialog({
  open,
  initialKey,
  initialHiddenPaths,
  onSave,
  onClose,
}: {
  open: boolean
  initialKey: string
  initialHiddenPaths: string
  onSave: (key: string, hiddenPaths: string) => void
  onClose: () => void
}) {
  const [key, setKey] = useState(initialKey)
  const [hiddenPaths, setHiddenPaths] = useState(initialHiddenPaths)
  useEffect(() => {
    if (open) {
      setKey(initialKey)
      setHiddenPaths(initialHiddenPaths)
    }
  }, [open, initialKey, initialHiddenPaths])

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>Settings</DialogTitle>
      <DialogContent>
        <Stack spacing={3} sx={{ mt: 1 }}>
          <Stack spacing={1}>
            <Typography variant="body2" color="text.secondary">
              Your Anthropic API key is stored in this browser only. It's sent
              directly to Anthropic — never to our servers.
            </Typography>
            <TextField
              autoFocus
              fullWidth
              label="Anthropic API key"
              placeholder="sk-ant-..."
              value={key}
              onChange={(e) => setKey(e.target.value)}
              type="password"
              autoComplete="off"
            />
            <Typography variant="caption" color="text.disabled">
              Create a key at{' '}
              <a
                href="https://console.anthropic.com/settings/keys"
                target="_blank"
                rel="noopener noreferrer"
                style={{ color: 'inherit' }}
              >
                console.anthropic.com/settings/keys
              </a>
            </Typography>
          </Stack>
          <Stack spacing={1}>
            <TextField
              fullWidth
              label="Hidden files & folders"
              placeholder=".obsidian, templates, _private"
              helperText="Comma-separated names or paths to hide from the sidebar."
              value={hiddenPaths}
              onChange={(e) => setHiddenPaths(e.target.value)}
            />
          </Stack>
        </Stack>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Cancel</Button>
        <Button
          variant="contained"
          onClick={() => {
            onSave(key, hiddenPaths)
            onClose()
          }}
        >
          Save
        </Button>
      </DialogActions>
    </Dialog>
  )
}
