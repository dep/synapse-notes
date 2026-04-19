import CssBaseline from '@mui/material/CssBaseline'
import Stack from '@mui/material/Stack'
import Typography from '@mui/material/Typography'
import { ThemeProvider, createTheme } from '@mui/material/styles'
import AppBar from '@mui/material/AppBar'
import Toolbar from '@mui/material/Toolbar'
import Box from '@mui/material/Box'

const theme = createTheme({
  palette: {
    mode: 'light',
    primary: {
      main: '#1f2937',
    },
  },
})

export default function App() {
  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <AppBar position="static" color="primary" elevation={0}>
        <Toolbar>
          <Typography variant="h6" component="h1" sx={{ flexGrow: 1 }}>
            Synapse
          </Typography>
        </Toolbar>
      </AppBar>
      <Box component="main" sx={{ p: 3 }}>
        <Stack spacing={2}>
          <Typography variant="h4" component="h2">
            Web (MVP)
          </Typography>
          <Typography variant="body1" color="text.secondary">
            Browser-based vault editing backed by GitHub. Markdown tools for tags
            and wiki links are available in code; vault UI ships next.
          </Typography>
        </Stack>
      </Box>
    </ThemeProvider>
  )
}
