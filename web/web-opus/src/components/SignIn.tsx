import { Alert, Button, Paper, Stack, Typography } from '@mui/material'
import GitHubIcon from '@mui/icons-material/GitHub'
import { useAuth } from '../auth/AuthContext'

export function SignIn() {
  const { beginGitHubLogin, clientConfigured } = useAuth()

  return (
    <Paper
      elevation={2}
      sx={{ p: 4, maxWidth: 420, width: '100%', borderRadius: 3 }}
    >
      <Stack spacing={2}>
        <Typography variant="h5" fontWeight={700}>
          Repo Markdown Editor
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Sign in with GitHub, pick a repo, and edit its files — markdown gets
          a live preview.
        </Typography>
        {!clientConfigured && (
          <Alert severity="warning">
            Missing <code>VITE_GITHUB_CLIENT_ID</code>. Copy{' '}
            <code>.env.example</code> to <code>.env.local</code> and restart.
          </Alert>
        )}
        <Button
          variant="contained"
          size="large"
          startIcon={<GitHubIcon />}
          onClick={beginGitHubLogin}
          disabled={!clientConfigured}
        >
          Sign in with GitHub
        </Button>
      </Stack>
    </Paper>
  )
}
