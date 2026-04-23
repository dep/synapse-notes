import { useEffect, useState } from 'react'
import {
  Alert,
  Button,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  TextField,
} from '@mui/material'

export function PromptDialog({
  open,
  title,
  label,
  initialValue = '',
  confirmLabel = 'Save',
  onConfirm,
  onClose,
  error,
  busy,
}: {
  open: boolean
  title: string
  label: string
  initialValue?: string
  confirmLabel?: string
  onConfirm: (value: string) => void
  onClose: () => void
  error?: string | null
  busy?: boolean
}) {
  const [value, setValue] = useState(initialValue)

  useEffect(() => {
    if (open) setValue(initialValue)
  }, [open, initialValue])

  return (
    <Dialog open={open} onClose={() => !busy && onClose()}>
      <DialogTitle>{title}</DialogTitle>
      <DialogContent sx={{ minWidth: 400 }}>
        <TextField
          autoFocus
          fullWidth
          label={label}
          value={value}
          onChange={(e) => setValue(e.target.value)}
          disabled={busy}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && value.trim()) {
              e.preventDefault()
              onConfirm(value.trim())
            }
          }}
        />
        {error && <Alert severity="error" sx={{ mt: 2 }}>{error}</Alert>}
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose} disabled={busy}>Cancel</Button>
        <Button
          variant="contained"
          disabled={busy || !value.trim()}
          onClick={() => onConfirm(value.trim())}
        >
          {busy ? 'Working…' : confirmLabel}
        </Button>
      </DialogActions>
    </Dialog>
  )
}
