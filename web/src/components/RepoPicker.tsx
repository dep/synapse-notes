import { useEffect, useMemo, useState } from 'react'
import {
  Alert,
  Box,
  Button,
  Chip,
  CircularProgress,
  IconButton,
  Link as MuiLink,
  List,
  ListItem,
  ListItemButton,
  ListItemText,
  Paper,
  Stack,
  TextField,
  Typography,
} from '@mui/material'
import LogoutIcon from '@mui/icons-material/Logout'
import {
  fetchRepoByFullName,
  fetchUserRepos,
  type GithubRepoListItem,
} from '../github/repos'
import { useAuth } from '../auth/AuthContext'
import type { SelectedRepo } from '../App'

export function RepoPicker({
  onSelect,
}: {
  onSelect: (repo: SelectedRepo) => void
}) {
  const { token, logout } = useAuth()
  const [repos, setRepos] = useState<GithubRepoListItem[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [filter, setFilter] = useState('')
  const [diagnostics, setDiagnostics] = useState<string[]>([])
  const [showDiag, setShowDiag] = useState(false)

  const [directName, setDirectName] = useState('')
  const [directLoading, setDirectLoading] = useState(false)
  const [directError, setDirectError] = useState<string | null>(null)

  useEffect(() => {
    if (!token) return
    let cancelled = false
    setLoading(true)
    fetchUserRepos(token).then((result) => {
      if (cancelled) return
      if (result.ok) {
        setRepos(result.repos)
        setDiagnostics(result.diagnostics)
        setError(null)
      } else {
        setError(result.error)
      }
      setLoading(false)
    })
    return () => {
      cancelled = true
    }
  }, [token])

  const filtered = useMemo(() => {
    const q = filter.trim().toLowerCase()
    if (!q) return repos
    return repos.filter((r) => r.full_name.toLowerCase().includes(q))
  }, [repos, filter])

  async function handleOpenByName() {
    if (!token || !directName.trim()) return
    setDirectLoading(true)
    setDirectError(null)
    const result = await fetchRepoByFullName(token, directName.trim())
    setDirectLoading(false)
    if (result.ok) {
      onSelect({
        fullName: result.repo.full_name,
        defaultBranch: result.repo.default_branch,
      })
    } else {
      setDirectError(result.error)
    }
  }

  return (
    <Box sx={{ maxWidth: 720, mx: 'auto', p: 3 }}>
      <Stack
        direction="row"
        justifyContent="space-between"
        alignItems="center"
        mb={2}
      >
        <Typography variant="h5" fontWeight={700}>
          Pick a repo
        </Typography>
        <IconButton onClick={logout} title="Sign out">
          <LogoutIcon />
        </IconButton>
      </Stack>

      <Paper variant="outlined" sx={{ p: 2, mb: 2 }}>
        <Typography variant="caption" color="text.secondary">
          Don't see a private or org repo? Open it directly:
        </Typography>
        <Stack direction="row" spacing={1} sx={{ mt: 1 }}>
          <TextField
            fullWidth
            size="small"
            placeholder="owner/repo"
            value={directName}
            onChange={(e) => setDirectName(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') void handleOpenByName()
            }}
            disabled={directLoading}
          />
          <Button
            variant="contained"
            onClick={handleOpenByName}
            disabled={directLoading || !directName.trim()}
          >
            Open
          </Button>
        </Stack>
        {directError && (
          <Alert severity="error" sx={{ mt: 1 }}>
            {directError}{' '}
            <MuiLink
              href="https://github.com/settings/applications"
              target="_blank"
              rel="noreferrer"
            >
              Manage OAuth access
            </MuiLink>
          </Alert>
        )}
      </Paper>

      <TextField
        fullWidth
        placeholder="Filter repos…"
        value={filter}
        onChange={(e) => setFilter(e.target.value)}
        size="small"
        sx={{ mb: 2 }}
      />
      {error && <Alert severity="error" sx={{ mb: 2 }}>{error}</Alert>}
      {loading ? (
        <Box sx={{ display: 'grid', placeItems: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      ) : (
        <Paper variant="outlined">
          <List dense sx={{ maxHeight: '60vh', overflow: 'auto', py: 0 }}>
            {filtered.map((repo) => (
              <ListItem key={repo.id} disablePadding>
                <ListItemButton
                  onClick={() =>
                    onSelect({
                      fullName: repo.full_name,
                      defaultBranch: repo.default_branch,
                    })
                  }
                >
                  <ListItemText
                    primary={repo.full_name}
                    secondary={`default branch: ${repo.default_branch}`}
                  />
                  {repo.private && <Chip label="private" size="small" />}
                </ListItemButton>
              </ListItem>
            ))}
            {filtered.length === 0 && (
              <Box sx={{ p: 3, textAlign: 'center' }}>
                <Typography variant="body2" color="text.secondary">
                  No repos match.
                </Typography>
              </Box>
            )}
          </List>
        </Paper>
      )}
      <Box mt={2}>
        <Typography variant="caption" color="text.secondary">
          Listed {repos.length} repos. Missing one?{' '}
          <MuiLink
            href="https://github.com/settings/applications"
            target="_blank"
            rel="noreferrer"
          >
            Check OAuth app access
          </MuiLink>{' '}
          ·{' '}
          <MuiLink
            component="button"
            type="button"
            onClick={() => setShowDiag((v) => !v)}
          >
            {showDiag ? 'hide' : 'show'} diagnostics
          </MuiLink>
        </Typography>
        {showDiag && (
          <Paper
            variant="outlined"
            sx={{
              mt: 1,
              p: 1.5,
              fontFamily: 'ui-monospace, Menlo, monospace',
              fontSize: 12,
              whiteSpace: 'pre-wrap',
            }}
          >
            {diagnostics.join('\n')}
          </Paper>
        )}
      </Box>
    </Box>
  )
}
