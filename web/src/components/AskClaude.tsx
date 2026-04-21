import { useEffect, useRef, useState } from 'react'
import {
  Alert,
  Box,
  Button,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
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
        // Prevent the click from clearing the selection before we act.
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

export function AskClaudeDialog({
  open,
  mode,
  hasApiKey,
  busy,
  error,
  onSubmit,
  onClose,
  onOpenSettings,
}: {
  open: boolean
  mode: AskClaudeMode | null
  hasApiKey: boolean
  busy: boolean
  error: string | null
  onSubmit: (instruction: string) => void
  onClose: () => void
  onOpenSettings: () => void
}) {
  const [instruction, setInstruction] = useState('')
  const inputRef = useRef<HTMLTextAreaElement>(null)
  useEffect(() => {
    if (open) setInstruction('')
  }, [open])

  const title = mode?.kind === 'insert' ? 'Ask Claude (insert)' : 'Ask Claude'
  const confirmLabel =
    mode?.kind === 'insert' ? 'Insert' : 'Rewrite'
  const placeholder =
    mode?.kind === 'insert'
      ? 'e.g. continue this thought, add a summary paragraph, sketch a todo list'
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
          <TextField
            autoFocus
            fullWidth
            multiline
            minRows={2}
            label="Instruction"
            placeholder={placeholder}
            value={instruction}
            onChange={(e) => setInstruction(e.target.value)}
            disabled={busy || !hasApiKey}
            inputRef={inputRef}
            onKeyDown={(e) => {
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
            }}
          />
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
  onSave,
  onClose,
}: {
  open: boolean
  initialKey: string
  onSave: (key: string) => void
  onClose: () => void
}) {
  const [key, setKey] = useState(initialKey)
  useEffect(() => {
    if (open) setKey(initialKey)
  }, [open, initialKey])

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>Settings</DialogTitle>
      <DialogContent>
        <Stack spacing={2} sx={{ mt: 1 }}>
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
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Cancel</Button>
        <Button
          variant="contained"
          onClick={() => {
            onSave(key)
            onClose()
          }}
        >
          Save
        </Button>
      </DialogActions>
    </Dialog>
  )
}
