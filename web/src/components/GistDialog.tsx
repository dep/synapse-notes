import { useEffect, useState } from 'react'
import {
  Alert,
  Button,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  FormControlLabel,
  Stack,
  Switch,
  TextField,
  Typography,
} from '@mui/material'

export type GistSubmission = {
  description: string
  isPublic: boolean
}

export function GistDialog({
  open,
  filename,
  onSubmit,
  onClose,
  busy,
  error,
}: {
  open: boolean
  filename: string
  onSubmit: (submission: GistSubmission) => void
  onClose: () => void
  busy?: boolean
  error?: string | null
}) {
  const [description, setDescription] = useState('')
  const [isPublic, setIsPublic] = useState(false)

  useEffect(() => {
    if (open) {
      setDescription('')
      setIsPublic(false)
    }
  }, [open])

  return (
    <Dialog open={open} onClose={() => !busy && onClose()}>
      <DialogTitle>Publish as gist</DialogTitle>
      <DialogContent sx={{ minWidth: 420 }}>
        <Stack spacing={2} sx={{ mt: 1 }}>
          <Typography variant="body2" color="text.secondary">
            Publishing <code>{filename}</code>
          </Typography>
          <TextField
            autoFocus
            fullWidth
            label="Description (optional)"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            disabled={busy}
          />
          <FormControlLabel
            control={
              <Switch
                checked={isPublic}
                onChange={(e) => setIsPublic(e.target.checked)}
                disabled={busy}
              />
            }
            label={
              isPublic
                ? 'Public gist (listed on your profile)'
                : 'Secret gist (shareable by URL only)'
            }
          />
          {error && <Alert severity="error">{error}</Alert>}
        </Stack>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose} disabled={busy}>Cancel</Button>
        <Button
          variant="contained"
          disabled={busy}
          onClick={() => onSubmit({ description, isPublic })}
        >
          {busy ? 'Publishing…' : 'Publish'}
        </Button>
      </DialogActions>
    </Dialog>
  )
}
